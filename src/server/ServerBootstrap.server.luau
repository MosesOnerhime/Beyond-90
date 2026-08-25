local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
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
