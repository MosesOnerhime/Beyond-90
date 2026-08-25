local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GameModeConfig = require(Shared.Config.GameModeConfig)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local BallService = require(script.Parent.BallService)
local GoalService = require(script.Parent.GoalService)

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

local function getOrCreateRemoteFunction(name: string): RemoteFunction
	local existing = modeFolder and modeFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local remote = Instance.new("RemoteFunction")
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
	local pingRemote = getOrCreateRemoteFunction(GameModeConfig.PingRemoteName)
	pingRemote.OnServerInvoke = function()
		return Workspace:GetServerTimeNow()
	end
	requestRemote.OnServerEvent:Connect(function(player, request)
		local requestedMode = if typeof(request) == "table" then request.Mode else request
		local requestedTeam = if typeof(request) == "table" then FootballTeamConfig.Normalize(request.TeamId) else nil
		local definition = typeof(requestedMode) == "string" and GameModeConfig.Modes[requestedMode] or nil
		if not definition or definition.Enabled ~= true or requestedMode == "TrainingFree" and not requestedTeam then
			return
		end
		local mapping = FootballTeamConfig.GetGoalMapping(requestedTeam)
		if requestedMode == "TrainingFree" and not mapping then
			return
		end
		local startingSession = next(activeTrainingPlayers) == nil
		if startingSession then
			GoalService.ResetScore()
		end
		player:SetAttribute(FootballTeamConfig.AttributeName, requestedTeam)
		player:SetAttribute(FootballTeamConfig.AttackingGoalAttributeName, mapping and mapping.AttackingGoalId or nil)
		player:SetAttribute(FootballTeamConfig.DefendedGoalAttributeName, mapping and mapping.DefendedGoalId or nil)
		player:SetAttribute("Beyond90SelectedGameMode", requestedMode)
		player:SetAttribute("Beyond90ExperienceState", "ModeLoading")
		activeTrainingPlayers[player] = true
		print(string.format("%s[GameMode] player=%s team=%s attacks=%s defends=%s", GameConfig.LogPrefix, player.Name, tostring(requestedTeam), tostring(mapping and mapping.AttackingGoalId), tostring(mapping and mapping.DefendedGoalId)))
		BallService.SetSessionActive(true)
		local existingCharacter = player.Character
		if existingCharacter and (not existingCharacter.Parent or not existingCharacter:FindFirstChildOfClass("Humanoid")) then
			player.Character = nil
			existingCharacter:Destroy()
			existingCharacter = nil
		end
		if not existingCharacter then
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
		player:SetAttribute(FootballTeamConfig.AttributeName, nil)
		player:SetAttribute(FootballTeamConfig.AttackingGoalAttributeName, nil)
		player:SetAttribute(FootballTeamConfig.DefendedGoalAttributeName, nil)
		if player.Character then
			local character = player.Character
			player.Character = nil
			character:Destroy()
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
