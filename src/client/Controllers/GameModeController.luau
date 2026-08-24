local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameModeConfig = require(Shared.Config.GameModeConfig)

local GameModeController = {}

local initialized = false
local folder: Folder? = nil
local requestRemote: RemoteEvent? = nil
local resetRemote: RemoteEvent? = nil
local exitRemote: RemoteEvent? = nil

function GameModeController.Initialize()
	if initialized then
		return
	end
	initialized = true
	folder = ReplicatedStorage:WaitForChild(GameModeConfig.ReplicatedFolderName, 10) :: Folder?
	if folder then
		requestRemote = folder:WaitForChild(GameModeConfig.RequestRemoteName, 10) :: RemoteEvent?
		resetRemote = folder:WaitForChild(GameModeConfig.ResetBallRemoteName, 10) :: RemoteEvent?
		exitRemote = folder:WaitForChild(GameModeConfig.ExitRemoteName, 10) :: RemoteEvent?
	end
end

function GameModeController.ExitGameplay()
	if exitRemote then
		exitRemote:FireServer()
	end
end

function GameModeController.GetPlayerState(): string
	return Players.LocalPlayer:GetAttribute("Beyond90ExperienceState") or "Menu"
end

function GameModeController.EnterTrainingFree()
	if requestRemote then
		requestRemote:FireServer("TrainingFree")
	end
end

function GameModeController.ResetTrainingBall()
	if resetRemote then
		resetRemote:FireServer()
	end
end

function GameModeController.GetCurrentMode(): string
	return if folder then folder:GetAttribute("CurrentMode") or GameModeConfig.DefaultMode else GameModeConfig.DefaultMode
end

return GameModeController
