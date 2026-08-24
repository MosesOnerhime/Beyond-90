local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GameModeConfig = require(Shared.Config.GameModeConfig)
local BallService = require(script.Parent.BallService)

local GameModeService = {}

local initialized = false
local currentMode = GameModeConfig.DefaultMode
local modeFolder: Folder? = nil
local lastResetAtByPlayer = {}
local activeTrainingPlayers: { [Player]: boolean } = {}

local function getOrCreateRemote(name: string): RemoteEvent
	local existing = modeFolder and modeFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = modeFolder
	return remote
end

local function publishMode()
	local definition = GameModeConfig.Modes[currentMode]
	modeFolder:SetAttribute("CurrentMode", currentMode)
	modeFolder:SetAttribute("DisplayName", definition and definition.DisplayName or currentMode)
	modeFolder:SetAttribute("Ready", true)
end

function GameModeService.Initialize()
	if initialized then
		return
	end
	initialized = true
	modeFolder = ReplicatedStorage:FindFirstChild(GameModeConfig.ReplicatedFolderName) :: Folder?
	if not modeFolder then
		modeFolder = Instance.new("Folder")
		modeFolder.Name = GameModeConfig.ReplicatedFolderName
		modeFolder.Parent = ReplicatedStorage
	end
	local requestRemote = getOrCreateRemote(GameModeConfig.RequestRemoteName)
	local exitRemote = getOrCreateRemote(GameModeConfig.ExitRemoteName)
	local resetRemote = getOrCreateRemote(GameModeConfig.ResetBallRemoteName)
	requestRemote.OnServerEvent:Connect(function(player, requestedMode)
		local definition = typeof(requestedMode) == "string" and GameModeConfig.Modes[requestedMode] or nil
		if not definition or definition.Enabled ~= true then
			return
		end
		player:SetAttribute("Beyond90SelectedGameMode", requestedMode)
		player:SetAttribute("Beyond90ExperienceState", "ModeLoading")
		activeTrainingPlayers[player] = true
		BallService.SetSessionActive(true)
		if not player.Character then
			player:LoadCharacter()
		end
		task.spawn(function()
			local character = player.Character or player.CharacterAdded:Wait()
			local startedAt = os.clock()
			while character.Parent and character:GetAttribute("Beyond90CharacterReady") ~= true and os.clock() - startedAt < 15 do
				task.wait()
			end
			if player.Parent then
				player:SetAttribute("Beyond90ExperienceState", "Gameplay")
			end
		end)
	end)
	exitRemote.OnServerEvent:Connect(function(player)
		activeTrainingPlayers[player] = nil
		player:SetAttribute("Beyond90ExperienceState", "Menu")
		player:SetAttribute("Beyond90SelectedGameMode", "Development")
		if player.Character then
			player.Character:Destroy()
		end
		if next(activeTrainingPlayers) == nil then
			BallService.SetSessionActive(false)
		end
	end)
	resetRemote.OnServerEvent:Connect(function(player)
		local mode = player:GetAttribute("Beyond90SelectedGameMode") or currentMode
		local definition = GameModeConfig.Modes[mode]
		local now = os.clock()
		if not definition or definition.AllowsBallReset ~= true then
			return
		end
		if now - (lastResetAtByPlayer[player] or 0) < GameModeConfig.ResetCooldown then
			return
		end
		lastResetAtByPlayer[player] = now
		BallService.Reset()
	end)
	publishMode()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Beyond90ExperienceState", "Menu")
	end
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("Beyond90ExperienceState", "Menu")
	end)
	Players.PlayerRemoving:Connect(function(player)
		activeTrainingPlayers[player] = nil
		if next(activeTrainingPlayers) == nil then
			BallService.SetSessionActive(false)
		end
	end)
	print(string.format("%s[GameMode] Mode -> %s", GameConfig.LogPrefix, currentMode))
end

return GameModeService
