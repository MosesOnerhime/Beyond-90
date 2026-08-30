local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GameModeConfig = require(Shared.Config.GameModeConfig)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local MatchConfig = require(Shared.Config.MatchConfig)
local BallService = require(script.Parent.BallService)
local AIService = require(script.Parent.AIService)
local MatchAssemblyService = require(script.Parent.MatchAssemblyService)
local MatchService = require(script.Parent.MatchService)
local GoalService = require(script.Parent.GoalService)

local GameModeService = {}

local initialized = false
local currentMode = GameModeConfig.DefaultMode
local modeFolder: Folder? = nil
local lastResetAtByPlayer = {}
local activeSessionPlayers: { [Player]: string } = {}

local function hasActiveMode(modeId: string): boolean
	for _, activeMode in activeSessionPlayers do
		if activeMode == modeId then
			return true
		end
	end
	return false
end

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
		--[[
			Only a mode that actually picks sides needs a team.

			Free practice does not, so it no longer refuses to start without one --
			it takes the default side and gets the player onto the pitch, which is
			the whole point of the mode.
		]]
		local needsTeam = GameModeConfig.Uses(requestedMode, "RequiresTeamSelection")
			and (requestedMode == "TrainingFree" or requestedMode == "Quick3v3")
		if not needsTeam and not requestedTeam then
			requestedTeam = FootballTeamConfig.Normalize("Home")
		end
		if not definition or definition.Enabled ~= true or needsTeam and not requestedTeam then
			return
		end
		local mapping = FootballTeamConfig.GetGoalMapping(requestedTeam)
		if needsTeam and not mapping then
			return
		end
		local startingSession = next(activeSessionPlayers) == nil
		if startingSession then
			GoalService.ResetScore()
		end
		player:SetAttribute(FootballTeamConfig.AttributeName, requestedTeam)
		player:SetAttribute(FootballTeamConfig.AttackingGoalAttributeName, mapping and mapping.AttackingGoalId or nil)
		player:SetAttribute(FootballTeamConfig.DefendedGoalAttributeName, mapping and mapping.DefendedGoalId or nil)
		player:SetAttribute("Beyond90SelectedGameMode", requestedMode)
		player:SetAttribute("Beyond90ExperienceState", "ModeLoading")
		activeSessionPlayers[player] = requestedMode
		-- Arm the match gate before anything spawns, so AI cannot act while this
		-- player is still inside ModeLoading.
		MatchService.AddParticipant(player, requestedMode)
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
			if not player.Parent then
				return
			end

			--[[
				ASSEMBLE THE FIELD BEFORE REVEALING IT (§23, §24, §82).

				This used to set ExperienceState to Gameplay first and spawn the AI
				afterwards, so the player watched their opponents, both goalkeepers
				and the referee appear one by one on an already-visible pitch. The
				reveal now waits for the complete match, and the ModeLoading
				presentation stays up until then.
			]]
			MatchAssemblyService.SetPlayerFieldReady(player, false)

			if requestedMode ~= "Quick3v3" and not hasActiveMode("Quick3v3") then
				AIService.Stop()
			end

			local ready, missing = MatchAssemblyService.Assemble(requestedMode)
			if not player.Parent then
				return
			end
			if not ready then
				--[[
					Assembly failed. The player is still let onto the pitch rather
					than being stranded on a loading screen -- an incomplete match
					is worse than a complete one, but it is far better than a
					session that never starts -- and the missing actor is named.
				]]
				warn(string.format(
					"%s[GameMode] Field assembly incomplete for %s (missing %s); revealing anyway",
					GameConfig.LogPrefix,
					player.Name,
					tostring(missing)
				))
			end

			MatchAssemblyService.SetPlayerFieldReady(player, true)
			player:SetAttribute("Beyond90ExperienceState", "Gameplay")
		end)
	end)
	exitRemote.OnServerEvent:Connect(function(player)
		local previousMode = activeSessionPlayers[player]
		activeSessionPlayers[player] = nil
		MatchService.RemoveParticipant(player)
		player:SetAttribute(MatchConfig.FieldReadyAttributeName, nil)
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
		if previousMode == "Quick3v3" then
			if hasActiveMode("Quick3v3") then
				AIService.Refresh3v3()
			else
				AIService.Stop()
			end
		end
		if next(activeSessionPlayers) == nil then
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
		local previousMode = activeSessionPlayers[player]
		activeSessionPlayers[player] = nil
		if previousMode == "Quick3v3" then
			task.defer(function()
				if hasActiveMode("Quick3v3") then
					AIService.Refresh3v3()
				else
					AIService.Stop()
				end
			end)
		end
		if next(activeSessionPlayers) == nil then
			BallService.SetSessionActive(false)
		end
	end)
	print(string.format("%s[GameMode] Mode -> %s", GameConfig.LogPrefix, currentMode))
end

return GameModeService
