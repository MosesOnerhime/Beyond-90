local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local BallService = require(script.Parent.Services.BallService)
local PitchService = require(script.Parent.Services.PitchService)

local function log(message: string)
	print(string.format("%s[Server] %s", GameConfig.LogPrefix, message))
end

local function placeCharacterAtDevelopmentSpawn(character: Model, spawnLocation: SpawnLocation)
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)

	if not humanoidRootPart then
		warn(string.format("%s[Server] Character missing HumanoidRootPart; could not place at development spawn", GameConfig.LogPrefix))
		return
	end

	character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 4, 0))
end

local function configurePlayerSpawn(player: Player, spawnLocation: SpawnLocation)
	player.RespawnLocation = spawnLocation

	player.CharacterAdded:Connect(function(character)
		placeCharacterAtDevelopmentSpawn(character, spawnLocation)
	end)

	if player.Character then
		placeCharacterAtDevelopmentSpawn(player.Character, spawnLocation)
	end
end

log("Initializing...")

local pitchState = PitchService.Initialize()
log("Pitch initialized")

BallService.Initialize()
log("Ball initialized")

for _, player in Players:GetPlayers() do
	configurePlayerSpawn(player, pitchState.SpawnLocation)
end

Players.PlayerAdded:Connect(function(player)
	configurePlayerSpawn(player, pitchState.SpawnLocation)
end)

log("Ready")
