local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GameModeConfig = require(Shared.Config.GameModeConfig)
local GoalConfig = require(Shared.Config.GoalConfig)
local GoalGeometry = require(Shared.Football.GoalGeometry)
local PitchService = require(script.Parent.PitchService)

local GoalService = {}

local initialized = false
local goals = {}
local activeBall: BasePart? = nil
local previousPosition: Vector3? = nil
local sampleConnection: RBXScriptConnection? = nil
local goalScoredEvent = Instance.new("BindableEvent")
local goalRemote: RemoteEvent? = nil
local scoredLatch = {}
local liveBallScored = false
local scoreFolder: Folder? = nil
local homeScore = 0
local awayScore = 0

local function log(message: string)
	print(string.format("%s[Goal] %s", GameConfig.LogPrefix, message))
end

local function getOrCreateGoalRemote(): RemoteEvent
	local folder = ReplicatedStorage:FindFirstChild(FootballActionConfig.RemotesFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FootballActionConfig.RemotesFolderName
		folder.Parent = ReplicatedStorage
	end
	local existing = folder:FindFirstChild(GoalConfig.GoalScoredRemoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = GoalConfig.GoalScoredRemoteName
	remote.Parent = folder
	return remote
end

local function publishScore()
	if scoreFolder then
		scoreFolder:SetAttribute(GameModeConfig.HomeScoreAttributeName, homeScore)
		scoreFolder:SetAttribute(GameModeConfig.AwayScoreAttributeName, awayScore)
	end
end

local function inspectCrossing(goal, previous: Vector3, current: Vector3)
	if liveBallScored then
		return
	end

	local radius = BallConfig.Radius
	local previousDistance = (previous - goal.LinePoint):Dot(goal.InwardDirection)
	local currentDistance = (current - goal.LinePoint):Dot(goal.InwardDirection)
	local crossingDistance = -radius

	if scoredLatch[goal.Id] then
		return
	end
	if previousDistance <= crossingDistance or currentDistance > crossingDistance then
		return
	end

	local alpha = math.clamp(
		(previousDistance - crossingDistance) / math.max(previousDistance - currentDistance, 1e-5),
		0,
		1
	)
	local crossingPosition = previous:Lerp(current, alpha)
	local lateral = math.abs((crossingPosition - goal.MouthCenter):Dot(goal.WidthAxis))
	local insideWidth = lateral <= goal.Width / 2 - radius - GoalConfig.GeometrySafetyMargin

	--[[
		THERE IS NO BOTTOM BAR ON A GOAL.

		The lower bound used to be `Y >= BottomY + radius` -- the same "clear the
		frame by a whole ball" test the crossbar needs. But the bottom of a goal
		is the GRASS. A ball rolling over the line along the ground is the most
		ordinary goal in football, and it was being asked to float a full radius
		above the goal's bottom edge to count.

		On the development stadium that left 0.200 studs of clearance for a ball
		whose centre rests at 0.975. Any dip -- a sample taken mid-bounce, a
		fraction of compression against the turf -- failed the test. Every goal
		in the logs that DID register was airborne (Y = 2.05, 4.07, 5.20); the
		ones that went missing were the ones on the deck.

		So the floor is the floor: a ball at or above ground level is in. The
		crossbar keeps its radius and margin, because that bar is really there.
	]]
	local insideHeight = crossingPosition.Y >= goal.BottomY
		and crossingPosition.Y <= goal.TopY - radius - GoalConfig.GeometrySafetyMargin

	if not insideWidth or not insideHeight then
		--[[
			NEVER FAIL A GOAL SILENTLY.

			This returned with no log, so a shot that crossed the line and was
			judged out of frame left NOTHING behind -- which is exactly why "goals
			sometimes don't register" could not be diagnosed from a playtest log.
			Say which test failed and by how much.
		]]
		log(string.format(
			"goal=%s NO GOAL -- ball crossed the line but was judged outside the frame."
				.. " position=%s insideWidth=%s (lateral=%.2f limit=%.2f)"
				.. " insideHeight=%s (y=%.2f band=%.2f..%.2f)",
			goal.Id,
			tostring(crossingPosition),
			tostring(insideWidth),
			lateral,
			goal.Width / 2 - radius - GoalConfig.GeometrySafetyMargin,
			tostring(insideHeight),
			crossingPosition.Y,
			goal.BottomY,
			goal.TopY - radius - GoalConfig.GeometrySafetyMargin
		))
		return
	end

	scoredLatch[goal.Id] = true
	liveBallScored = true
	if goal.Id == "Away" then
		homeScore += 1
	elseif goal.Id == "Home" then
		awayScore += 1
	end
	publishScore()
	local payload = {
		GoalId = goal.Id,
		EnteredGoal = goal.Id,
		BallPosition = crossingPosition,
		LastRelevantPlayerUserId = activeBall and (activeBall:GetAttribute("LastFootballActionPlayerUserId") or 0) or 0,
		Timestamp = os.clock(),
		HomeScore = homeScore,
		AwayScore = awayScore,
	}
	log(string.format(
		"goal=%s ballPosition=%s lineCross=true insideWidth=%s insideHeight=%s scorer=%s",
		goal.Id,
		tostring(crossingPosition),
		tostring(insideWidth),
		tostring(insideHeight),
		tostring(payload.LastRelevantPlayerUserId)
	))
	goalScoredEvent:Fire(payload)
	if goalRemote then
		goalRemote:FireAllClients(payload)
	end
end

function GoalService.Initialize(ball: BasePart, ballSampledEvent: BindableEvent?)
	if initialized then
		return goals
	end
	initialized = true
	activeBall = ball
	scoreFolder = ReplicatedStorage:FindFirstChild(GameModeConfig.ScoreFolderName) :: Folder?
	if not scoreFolder then
		scoreFolder = Instance.new("Folder")
		scoreFolder.Name = GameModeConfig.ScoreFolderName
		scoreFolder.Parent = ReplicatedStorage
	end
	publishScore()
	goalRemote = getOrCreateGoalRemote()
	local reason
	goals, reason = GoalGeometry.ResolveAll(PitchService.GetState())
	if reason then
		warn(string.format("%s[Goal] Geometry incomplete: %s", GameConfig.LogPrefix, reason))
	end
	for goalId, goal in goals do
		log(string.format(
			"%s center=%s width=%.2f height=%.2f depth=%.2f line=%s inward=%s",
			goalId,
			tostring(goal.MouthCenter),
			goal.Width,
			goal.Height,
			goal.Depth,
			tostring(goal.LinePoint),
			tostring(goal.InwardDirection)
		))
	end
	previousPosition = ball.Position
	if not ballSampledEvent then
		warn(string.format("%s[Goal] Ball sample event unavailable; goal detection disabled", GameConfig.LogPrefix))
		return goals
	end
	sampleConnection = ballSampledEvent.Event:Connect(function(sampledBall: BasePart, current: Vector3, isReset: boolean)
		if sampledBall ~= activeBall or not activeBall or not activeBall.Parent then
			return
		end
		if isReset then
			previousPosition = current
			table.clear(scoredLatch)
			liveBallScored = false
			return
		end
		--[[
			THE LATCH HAS TO CLEAR ITSELF.

			`liveBallScored` is a GLOBAL block -- once a goal is counted, every
			further crossing at either end is ignored until it clears. And the
			only thing that cleared it was `isReset`, a full ball reset. Any
			restart that repositions the ball WITHOUT going through a reset left
			the flag stuck on, and from that moment no goal could ever be scored
			again for the rest of the match. Silently, because the guard sits
			above the near-miss logging.

			That is the "sometimes a goal doesn't register" report: it is not
			random, it is everything after the first goal that restarts the wrong
			way.

			Rather than wire every restart path to remember to clear it, the
			latch now heals on the only condition that actually matters -- the
			ball being back out in play, clear of both goals. A ball that has
			left the net cannot still be the goal that was already counted.
		]]
		if liveBallScored then
			local clearOfEveryGoal = true
			for _, goal in goals do
				local depth = (current - goal.LinePoint):Dot(goal.InwardDirection)
				if depth > -GoalConfig.LatchClearDistance then
					clearOfEveryGoal = false
				end
			end
			if clearOfEveryGoal then
				table.clear(scoredLatch)
				liveBallScored = false
			end
		end

		if previousPosition then
			for _, goal in goals do
				inspectCrossing(goal, previousPosition, current)
			end
		end
		previousPosition = current
	end)
	return goals
end

function GoalService.GetGoals()
	return goals
end

function GoalService.GetGoalScoredEvent(): BindableEvent
	return goalScoredEvent
end

function GoalService.ResetScore()
	homeScore = 0
	awayScore = 0
	publishScore()
end

return GoalService
