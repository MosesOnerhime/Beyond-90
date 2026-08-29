--!strict
--[[
	Injuries.

	Deliberately rare and never random for its own sake: only a serious foul or a
	genuinely heavy collision can cause one, and even then only by chance. A
	competitive match that keeps stopping is worse than one with no injuries at
	all (§71).

	Applies identically to humans and AI -- an actor record is an actor record, so
	nothing here can accidentally make AI immune (§74).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchRulesConfig = require(Shared.Config.MatchRulesConfig)

local FootballerRegistryService = require(script.Parent.FootballerRegistryService)

local InjuryService = {}

local config = MatchRulesConfig.Injury
local States = config.States

local initialized = false
-- footballerId -> { State, RecoverAt, LastInjuryAt }
local injuries: { [number]: { State: string, RecoverAt: number, LastInjuryAt: number } } = {}
local injuredEvent = Instance.new("BindableEvent")

local function log(message: string)
	if MatchRulesConfig.Debug.Enabled then
		print(string.format("%s[Injury] %s", GameConfig.LogPrefix, message))
	end
end

local function applyAttribute(actor, state: string)
	if actor.Character and actor.Character.Parent then
		actor.Character:SetAttribute(config.StateAttributeName, state)
	end
	if actor.Player then
		actor.Player:SetAttribute(config.StateAttributeName, state)
	end
end

function InjuryService.GetState(footballerId: number): string
	local record = injuries[footballerId]
	return if record then record.State else States.Healthy
end

function InjuryService.IsInjured(footballerId: number): boolean
	return InjuryService.GetState(footballerId) ~= States.Healthy
end

--[[
	Movement multiplier for an injured footballer. Shared by human locomotion and
	AI carry speed, so an injury slows both the same way.
]]
function InjuryService.GetSpeedScale(footballerId: number): number
	local state = InjuryService.GetState(footballerId)
	if state == States.Knocked then
		return config.KnockedSpeedScale
	elseif state == States.Minor then
		return config.MinorSpeedScale
	elseif state == States.Moderate then
		return config.ModerateSpeedScale
	end
	return 1
end

--[[
	Does anyone currently need play stopped?

	An injury stops the match at most ONCE. Without this the referee stops again
	the moment play resumes, because the footballer is still injured -- the
	stoppage is for treatment, not for the duration of the injury.
]]
function InjuryService.GetStoppageCandidate(): number?
	for id, record in injuries do
		if record.State == config.StoppageState and not record.StoppageServed then
			return id
		end
	end
	return nil
end

-- Called by the referee once it has actually stopped play for this injury.
function InjuryService.MarkStoppageServed(footballerId: number)
	local record = injuries[footballerId]
	if record then
		record.StoppageServed = true
	end
end

local function setState(actor, state: string, seconds: number)
	local now = os.clock()
	local previous = injuries[actor.Id]
	injuries[actor.Id] = {
		State = state,
		RecoverAt = now + seconds,
		LastInjuryAt = now,
		-- Recovering down through the severities must not re-arm the stoppage.
		StoppageServed = previous ~= nil and previous.StoppageServed == true,
	}
	applyAttribute(actor, state)
	injuredEvent:Fire(actor, state)
	log(string.format("%s -> %s for %.1fs", actor.DisplayName or tostring(actor.Id), state, seconds))
end

--[[
	Consider injuring `actor` from an event.

	`cause` is "SeriousFoul" or "Collision"; `intensity` 0..1 scales the roll.
	Returns the state applied, or nil.
]]
function InjuryService.Consider(actor, cause: string, intensity: number): string?
	if config.Enabled ~= true or not actor or typeof(actor.Id) ~= "number" then
		return nil
	end

	local existing = injuries[actor.Id]
	local now = os.clock()
	-- Never injure the same footballer twice in quick succession.
	if existing and now - existing.LastInjuryAt < config.Cooldown then
		return nil
	end

	local chance = if cause == "SeriousFoul" then config.SeriousFoulChance else config.HeavyCollisionChance
	chance *= math.clamp(intensity, 0, 1)
	if math.random() >= chance then
		return nil
	end

	--[[
		Severity. A serious foul can put someone down properly; an ordinary
		collision only ever knocks them.
	]]
	local state, seconds
	if cause == "SeriousFoul" and intensity > 0.7 then
		state, seconds = States.Moderate, config.ModerateSeconds
	elseif cause == "SeriousFoul" then
		state, seconds = States.Minor, config.MinorSeconds
	else
		state, seconds = States.Knocked, config.KnockedSeconds
	end

	setState(actor, state, seconds)
	return state
end

-- Development tooling: apply an injury deterministically (§90).
function InjuryService.ForceInjury(actor, state: string?): string?
	if not actor or typeof(actor.Id) ~= "number" then
		return nil
	end
	local applied = state or States.Moderate
	local seconds = if applied == States.Moderate then config.ModerateSeconds
		elseif applied == States.Minor then config.MinorSeconds
		else config.KnockedSeconds
	setState(actor, applied, seconds)
	return applied
end

function InjuryService.Heal(footballerId: number)
	local record = injuries[footballerId]
	if not record then
		return
	end
	injuries[footballerId] = nil
	local actor = FootballerRegistryService.GetActorById(footballerId)
	if actor then
		applyAttribute(actor, States.Healthy)
	end
end

function InjuryService.ClearAll()
	for id in injuries do
		InjuryService.Heal(id)
	end
	table.clear(injuries)
end

function InjuryService.GetInjuredEvent(): BindableEvent
	return injuredEvent
end

local function step()
	local now = os.clock()
	for id, record in injuries do
		if now >= record.RecoverAt then
			-- Recover a step at a time rather than straight to healthy, so a
			-- moderate injury still leaves a footballer limping briefly.
			if record.State == States.Moderate then
				local actor = FootballerRegistryService.GetActorById(id)
				if actor then
					setState(actor, States.Minor, config.MinorSeconds * 0.5)
				else
					injuries[id] = nil
				end
			elseif record.State == States.Minor then
				local actor = FootballerRegistryService.GetActorById(id)
				if actor then
					setState(actor, States.Knocked, config.KnockedSeconds * 0.5)
				else
					injuries[id] = nil
				end
			else
				InjuryService.Heal(id)
			end
		end
	end
end

function InjuryService.Initialize()
	if initialized or config.Enabled ~= true then
		return
	end
	initialized = true
	task.spawn(function()
		while initialized do
			step()
			task.wait(0.5)
		end
	end)
end

return InjuryService
