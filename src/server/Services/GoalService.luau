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
	local insideHeight = crossingPosition.Y >= goal.BottomY + radius
		and crossingPosition.Y <= goal.TopY - radius - GoalConfig.GeometrySafetyMargin

	if not insideWidth or not insideHeight then
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
