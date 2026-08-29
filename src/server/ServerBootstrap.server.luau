local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GoalConfig = require(Shared.Config.GoalConfig)

local BallService = require(script.Parent.Services.BallService)
local AIService = require(script.Parent.Services.AIService)
local FootballActionService = require(script.Parent.Services.FootballActionService)
local GoalService = require(script.Parent.Services.GoalService)
local GameModeService = require(script.Parent.Services.GameModeService)
local MatchService = require(script.Parent.Services.MatchService)
local DefendingService = require(script.Parent.Services.DefendingService)
local GoalkeeperService = require(script.Parent.Services.GoalkeeperService)
local DevToolsService = require(script.Parent.Services.DevToolsService)
local PlayerService = require(script.Parent.Services.PlayerService)
local PitchService = require(script.Parent.Services.PitchService)
local PositionService = require(script.Parent.Services.PositionService)
local MatchRulesService = require(script.Parent.Services.MatchRulesService)
local InjuryService = require(script.Parent.Services.InjuryService)
local RefereeService = require(script.Parent.Services.RefereeService)

local function log(message: string)
	print(string.format("%s[Server] %s", GameConfig.LogPrefix, message))
end

log("Initializing...")

-- Collision groups must exist before the ball or any character is built.
PlayerService.EnsureCollisionGroups()

local menuCharacter = Workspace:FindFirstChild("menu_character")
if menuCharacter and menuCharacter:IsA("Model") then
	local previousReplica = ReplicatedStorage:FindFirstChild("Beyond90MenuCharacter")
	if previousReplica then previousReplica:Destroy() end
	local replica = menuCharacter:Clone()
	replica.Name = "Beyond90MenuCharacter"
	for _, descendant in replica:GetDescendants() do
		if descendant:IsA("BaseScript") then descendant:Destroy() end
	end
	replica.Parent = ReplicatedStorage
	log("Workspace.menu_character replicated for the menu ViewportFrame")
else
	warn(string.format("%s[Server] Workspace.menu_character is missing", GameConfig.LogPrefix))
end

local pitchState = PitchService.Initialize()
log("Pitch initialized")

PlayerService.Initialize(pitchState.SpawnLocation)
log("Players initialized")

local ball = BallService.Initialize()
log("Ball initialized")

GoalService.Initialize(ball, BallService.GetBallSampledEvent())
log("Goals initialized")
GoalService.GetGoalScoredEvent().Event:Connect(function(payload)
	--[[
		In a real match the referee owns what happens after a goal: celebration,
		then a kick-off restart. Only fall back to the immediate ball reset when
		no match is running -- Training and the development sandbox.
	]]
	if MatchRulesService.NotifyGoal(tostring(payload.GoalId), payload.ScorerId) then
		return
	end
	if not GoalConfig.ResetBallAfterGoal then
		return
	end
	log(string.format("Goal presentation goal=%s; ball reset scheduled", tostring(payload.GoalId)))
	task.delay(GoalConfig.TrainingResetDelay, function()
		BallService.Reset()
		log("Ball reset to center after goal")
	end)
end)

FootballActionService.Initialize()
log("Football actions initialized")

MatchService.Initialize()
log("Match lifecycle initialized")

PositionService.Initialize()
log("Positions initialized")

MatchRulesService.SetBall(ball)
MatchRulesService.Initialize()
InjuryService.Initialize()
log("Match rules initialized")

-- Strictly downstream of the rules: the referee reacts to decisions, never makes
-- one. Initialized after MatchRulesService so the decision feed already exists.
RefereeService.SetBall(ball)
RefereeService.Initialize()
log("Referee initialized")

DefendingService.Initialize()
log("Defending initialized")

GoalkeeperService.Initialize(ball)
log("Goalkeepers initialized")

AIService.Initialize(pitchState.PitchState, ball)
log("AI initialized")

GameModeService.Initialize()
log("Game mode initialized")

DevToolsService.Initialize()
log("Development tools initialized")

log("Ready")
