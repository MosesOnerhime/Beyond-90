local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local BallService = require(script.Parent.Services.BallService)
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

BallService.Initialize()
log("Ball initialized")

log("Ready")
