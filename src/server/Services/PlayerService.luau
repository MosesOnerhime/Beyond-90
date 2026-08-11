local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local PlayerService = {}

local movementConfig = PlayerConfig.Movement
local inputConfig = PlayerConfig.Input

local initialized = false
local sprintRemote: RemoteEvent? = nil
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local sprintStateByPlayer: { [Player]: boolean } = {}
local configuredHumanoids: { [Humanoid]: boolean } = {}

local function warnLog(message: string)
	warn(string.format("%s[Server][PlayerService] %s", GameConfig.LogPrefix, message))
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)

	if existing then
		assert(existing:IsA("Folder"), string.format("%s exists but is not a Folder", existing:GetFullName()))
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent

	return folder
end

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)

	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s exists but is not a RemoteEvent", existing:GetFullName()))
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent

	return remote
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character

	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return nil
	end

	return humanoid
end

local function getConfiguredWalkSpeed(player: Player): number
	if sprintStateByPlayer[player] then
		return movementConfig.SprintSpeed
	end

	return movementConfig.BaseSpeed
end

local function applyMovementSettings(player: Player, humanoid: Humanoid)
	humanoid.WalkSpeed = getConfiguredWalkSpeed(player)
	humanoid.AutoRotate = movementConfig.AutoRotate
	humanoid.UseJumpPower = true
	humanoid.JumpPower = movementConfig.JumpPower
	humanoid.JumpHeight = movementConfig.JumpHeight
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, movementConfig.JumpEnabled)
	humanoid:SetAttribute("Beyond90MovementConfigured", true)
	humanoid:SetAttribute("SprintRequested", sprintStateByPlayer[player] == true)

	if not movementConfig.JumpEnabled then
		humanoid.Jump = false
	end
end

local function placeCharacterAtDevelopmentSpawn(character: Model, spawnLocation: SpawnLocation)
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)

	if not humanoidRootPart then
		warnLog("Character missing HumanoidRootPart; could not place at development spawn")
		return
	end

	character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 4, 0))
end

local function configureCharacter(player: Player, character: Model, spawnLocation: SpawnLocation)
	sprintStateByPlayer[player] = false
	placeCharacterAtDevelopmentSpawn(character, spawnLocation)

	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid or not humanoid:IsA("Humanoid") then
		warnLog(string.format("%s spawned without a Humanoid", player.Name))
		return
	end

	applyMovementSettings(player, humanoid)

	if not configuredHumanoids[humanoid] then
		configuredHumanoids[humanoid] = true

		humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
			if not movementConfig.JumpEnabled and humanoid.Jump then
				humanoid.Jump = false
			end
		end)

		humanoid.Destroying:Connect(function()
			configuredHumanoids[humanoid] = nil
		end)
	end
end

local function setSprintState(player: Player, requested: boolean)
	sprintStateByPlayer[player] = requested

	local humanoid = getHumanoid(player)

	if not humanoid then
		return
	end

	applyMovementSettings(player, humanoid)
end

local function configurePlayer(player: Player, spawnLocation: SpawnLocation)
	player.RespawnLocation = spawnLocation
	sprintStateByPlayer[player] = false

	local connections = playerConnections[player]

	if not connections then
		connections = {}
		playerConnections[player] = connections
	end

	table.insert(connections, player.CharacterAdded:Connect(function(character)
		configureCharacter(player, character, spawnLocation)
	end))

	if player.Character then
		configureCharacter(player, player.Character, spawnLocation)
	end
end

local function cleanupPlayer(player: Player)
	local connections = playerConnections[player]

	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	playerConnections[player] = nil
	sprintStateByPlayer[player] = nil
end

local function onSprintRequested(player: Player, requested: any)
	if typeof(requested) ~= "boolean" then
		warnLog(string.format("Rejected invalid sprint request from %s", player.Name))
		return
	end

	if player.Parent ~= Players then
		return
	end

	setSprintState(player, requested)
end

function PlayerService.Initialize(spawnLocation: SpawnLocation)
	if initialized then
		return
	end

	initialized = true

	local remotes = getOrCreateFolder(ReplicatedStorage, "Remotes")
	sprintRemote = getOrCreateRemoteEvent(remotes, inputConfig.SprintRemoteName)
	sprintRemote.OnServerEvent:Connect(onSprintRequested)

	for _, player in Players:GetPlayers() do
		configurePlayer(player, spawnLocation)
	end

	Players.PlayerAdded:Connect(function(player)
		configurePlayer(player, spawnLocation)
	end)

	Players.PlayerRemoving:Connect(cleanupPlayer)
end

return PlayerService
