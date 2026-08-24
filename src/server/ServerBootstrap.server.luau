local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GoalConfig = require(Shared.Config.GoalConfig)

local BallService = require(script.Parent.Services.BallService)
local FootballActionService = require(script.Parent.Services.FootballActionService)
local GoalService = require(script.Parent.Services.GoalService)
local GameModeService = require(script.Parent.Services.GameModeService)
local PlayerService = require(script.Parent.Services.PlayerService)
local PitchService = require(script.Parent.Services.PitchService)

local function log(message: string)
	print(string.format("%s[Server] %s", GameConfig.LogPrefix, message))
end

log("Initializing...")

local pitchState = PitchService.Initialize()
log("Pitch initialized")

PlayerService.Initialize(pitchState.SpawnLocation)
log("Players initialized")

local ball = BallService.Initialize()
log("Ball initialized")

GoalService.Initialize(ball, BallService.GetBallSampledEvent())
log("Goals initialized")
GoalService.GetGoalScoredEvent().Event:Connect(function(payload)
	if not GoalConfig.ResetBallAfterGoal then
		return
	end
	log(string.format("Goal presentation goal=%s; ball reset scheduled", tostring(payload.GoalId)))
	task.delay(GoalConfig.TrainingResetDelay, function()
		BallService.Reset()
		log("Ball reset to center after goal")
	end)
end)

GameModeService.Initialize()
log("Game mode initialized")

FootballActionService.Initialize()
log("Football actions initialized")

log("Ready")
