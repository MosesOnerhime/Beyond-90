--!strict
--[[
	FIELD ASSEMBLY (§23, §24, §82).

	The barrier between "a mode was requested" and "the player may see the
	pitch". Before this existed, GameModeService revealed the gameplay view as
	soon as the human's own character was ready and then spawned the AI, the
	goalkeepers and the referee afterwards -- so the first visible frames showed
	footballers and officials popping into existence.

	The order is deliberate and each step depends on the last:

		mode requested
		    -> pitch and football exist
		    -> outfield footballers spawn and take their position slots
		    -> goalkeepers spawn
		    -> officials spawn (referee + assistants)
		    -> kick-off arranged, everyone placed, ball on the centre spot
		    -> FIELD READY
		    -> only now may the client reveal the pitch

	Every wait is BOUNDED. A missing optional asset must never hang a match, and
	when something REQUIRED times out the specific actor is named in the log
	rather than the match silently starting half-built.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AIConfig = require(Shared.Config.AIConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MatchConfig = require(Shared.Config.MatchConfig)

local AIService = require(script.Parent.AIService)
local FootballerRegistryService = require(script.Parent.FootballerRegistryService)
local MatchRulesService = require(script.Parent.MatchRulesService)
local PitchService = require(script.Parent.PitchService)
local RefereeService = require(script.Parent.RefereeService)

local MatchAssemblyService = {}

--[[
	Bounded budgets, in seconds. Generous enough for a cold Studio start, short
	enough that a genuine failure is reported rather than waited on.
]]
local PITCH_TIMEOUT = 10
local ACTOR_TIMEOUT = 8
local ARRANGE_TIMEOUT = 6
local POLL_INTERVAL = 0.1

local function log(message: string)
	print(string.format("%s[Assembly] %s", GameConfig.LogPrefix, message))
end

--[[
	Poll `predicate` until it is true or `timeout` elapses.
	Returns whether it became true, and how long it took.
]]
local function waitUntil(predicate: () -> boolean, timeout: number): (boolean, number)
	local startedAt = os.clock()
	while os.clock() - startedAt < timeout do
		if predicate() then
			return true, os.clock() - startedAt
		end
		task.wait(POLL_INTERVAL)
	end
	return predicate(), os.clock() - startedAt
end

-- How many outfielders and keepers are actually on the pitch, per team.
local function countFootballers(): (number, number)
	local outfield, keepers = 0, 0
	for _, actor in FootballerRegistryService.GetAll() do
		if actor.RootPart and actor.RootPart.Parent then
			if actor.Position == "Goalkeeper" then
				keepers += 1
			else
				outfield += 1
			end
		end
	end
	return outfield, keepers
end

--[[
	Assemble the match for `modeId`.

	Returns (ready, missing). `missing` names the first REQUIRED actor that could
	not be produced, so a failure is diagnosable from one log line.
]]
function MatchAssemblyService.Assemble(modeId: string): (boolean, string?)
	local startedAt = os.clock()

	-- 1. Pitch and football. Nothing can be positioned without them.
	local pitchReady = waitUntil(function()
		return PitchService.GetState() ~= nil
	end, PITCH_TIMEOUT)
	if not pitchReady then
		log("FAILED: pitch geometry never became available")
		return false, "Pitch"
	end

	-- 2. Footballers. Only the 3v3 mode fills a roster; a free-training session
	--    has no team to assemble and is ready as soon as the pitch is.
	if modeId ~= AIConfig.ModeId then
		log(string.format("Mode '%s' needs no team assembly", modeId))
		return true, nil
	end

	if AIService.IsActive() then
		AIService.Refresh3v3()
	else
		AIService.Start3v3()
	end

	--[[
		Both sides complete. 3v3 means three OUTFIELD footballers per side plus a
		goalkeeper each, so the expected counts come from the mode rather than
		from a hardcoded number.
	]]
	local expectedOutfield = AIConfig.TeamSize * 2
	local expectedKeepers = if AIConfig.GoalkeeperEnabled == true then AIConfig.GoalkeepersPerTeam * 2 else 0

	local actorsReady = waitUntil(function()
		local outfield, keepers = countFootballers()
		return outfield >= expectedOutfield and keepers >= expectedKeepers
	end, ACTOR_TIMEOUT)

	if not actorsReady then
		local outfield, keepers = countFootballers()
		log(string.format(
			"FAILED: roster incomplete after %.1fs -- outfield %d/%d, goalkeepers %d/%d",
			ACTOR_TIMEOUT,
			outfield,
			expectedOutfield,
			keepers,
			expectedKeepers
		))
		return false, if keepers < expectedKeepers then "Goalkeeper" else "Footballer"
	end

	-- 3. Officials. The referee and both assistants must be standing on the
	--    pitch before it is shown, not walk on afterwards.
	local officialsReady, missingOfficial = RefereeService.EnsureOfficials()
	if not officialsReady then
		log(string.format("FAILED: could not create official '%s'", tostring(missingOfficial)))
		return false, missingOfficial
	end

	--[[
		4. Arrange the kick-off. This places every footballer, puts the ball on
		   the centre spot and holds the whole arrangement still in PreMatch.

		   Retried within a bounded window because the registry can report a
		   footballer a frame before its root part has settled.
	]]
	local arranged = waitUntil(function()
		return MatchRulesService.PrepareMatch()
	end, ARRANGE_TIMEOUT)
	if not arranged then
		log("FAILED: kick-off could not be arranged")
		return false, "KickoffArrangement"
	end

	local outfield, keepers = countFootballers()
	log(string.format(
		"FIELD READY in %.2fs -- %d outfield, %d goalkeepers, %d officials",
		os.clock() - startedAt,
		outfield,
		keepers,
		RefereeService.GetOfficialCount()
	))
	return true, nil
end

--[[
	Publish readiness for one player.

	The client gates its reveal on this, so a player who joins an already
	assembled match is not shown a pitch that is still being built for them.
]]
function MatchAssemblyService.SetPlayerFieldReady(player: Player, ready: boolean)
	player:SetAttribute(MatchConfig.FieldReadyAttributeName, ready)
end

return MatchAssemblyService
