local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DevToolsConfig = require(Shared.Config.DevToolsConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)

local AIService = require(script.Parent.AIService)
local BallService = require(script.Parent.BallService)
local BallControlService = require(script.Parent.BallControlService)
local PitchService = require(script.Parent.PitchService)
local MatchRulesService = require(script.Parent.MatchRulesService)
local InjuryService = require(script.Parent.InjuryService)
local FootballerRegistryService = require(script.Parent.FootballerRegistryService)
local GoalkeeperService = require(script.Parent.GoalkeeperService)

--[[
	Development tooling. Studio-gated end to end: a production client cannot
	reach any of it, and every request goes through the normal football
	architecture rather than manipulating Instances directly.
]]
local DevToolsService = {}

local initialized = false
local requestRemote: RemoteEvent? = nil
local feedbackRemote: RemoteEvent? = nil
local lastRequestAt: { [Player]: number } = {}

local function log(message: string)
	print(string.format("%s[DevTools] %s", GameConfig.LogPrefix, message))
end

local function sendFeedback(player: Player, action: string, accepted: boolean, detail: string?)
	if feedbackRemote then
		feedbackRemote:FireClient(player, {
			Action = action,
			Accepted = accepted,
			Detail = detail or "",
			HomeAI = AIService.GetAICount("Home"),
			AwayAI = AIService.GetAICount("Away"),
			HomeGoalkeeper = AIService.HasGoalkeeper("Home"),
			AwayGoalkeeper = AIService.HasGoalkeeper("Away"),
			-- Compact match-rule state for the DEV panel (§80).
			MatchPhase = MatchRulesService.GetPhase(),
			MatchPeriod = MatchRulesService.GetPeriod(),
			MatchClock = math.floor(MatchRulesService.GetClockSeconds()),
			RestartType = MatchRulesService.GetActiveRestart(),
			LastTouch = (function()
				local touch = MatchRulesService.GetLastTouch()
				if not touch then
					return nil
				end
				return string.format("%d/%s/%s", touch.Id, tostring(touch.TeamId), touch.Kind)
			end)(),
		})
	end
end

local function resetPlayer(player: Player): (boolean, string)
	local character = player.Character
	if not character then
		return false, "no-character"
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not rootPart:IsA("BasePart") or not humanoid then
		return false, "character-invalid"
	end

	-- Reuse the existing gameplay pipeline rather than Roblox's respawn flow,
	-- which would tear down Beyond 90's character ownership and lifecycle.
	local ball = BallControlService.GetActiveController()
	if ball == player then
		local root = workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
		local folder = root and root:FindFirstChild("Ball")
		local football = folder and folder:FindFirstChild("DevelopmentFootball")
		if football and football:IsA("BasePart") then
			BallControlService.Reset(football)
		end
	end

	local pitchState = PitchService.GetState()
	local spawnPosition
	if pitchState and pitchState.SpawnPosition then
		spawnPosition = pitchState.SpawnPosition
	elseif pitchState then
		spawnPosition = pitchState.Center + Vector3.yAxis * 5
	else
		spawnPosition = rootPart.Position + Vector3.yAxis * 5
	end

	humanoid:Move(Vector3.zero, false)
	humanoid.WalkSpeed = 0
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(CFrame.new(spawnPosition + Vector3.yAxis * 3))

	-- Clear any action state the footballer was mid-way through.
	character:SetAttribute("Beyond90DevResetAt", os.clock())
	task.defer(function()
		if humanoid.Parent then
			humanoid.WalkSpeed = 0
		end
	end)
	return true, "reset"
end

local function onRequest(player: Player, payload)
	-- Development tooling only exists inside Studio.
	if not RunService:IsStudio() then
		return
	end
	if typeof(payload) ~= "table" or typeof(payload.Action) ~= "string" then
		return
	end

	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < DevToolsConfig.RequestCooldown then
		return
	end
	lastRequestAt[player] = now

	local action = payload.Action
	local actions = DevToolsConfig.Actions

	if action == actions.AddAI or action == actions.RemoveAI then
		local teamId = FootballTeamConfig.Normalize(payload.TeamId)
		if not teamId then
			sendFeedback(player, action, false, "invalid-team")
			return
		end
		local delta = if action == actions.AddAI then 1 else -1
		local ok, detail = AIService.AdjustAICount(teamId, delta, DevToolsConfig.MaximumAIPerTeam)
		log(string.format("%s %s %s -> %s", player.Name, action, teamId, detail))
		sendFeedback(player, action, ok, detail)
		return
	end

	if action == actions.AddGoalkeeper or action == actions.RemoveGoalkeeper then
		local teamId = FootballTeamConfig.Normalize(payload.TeamId)
		if not teamId then
			sendFeedback(player, action, false, "invalid-team")
			return
		end
		local enabled = action == actions.AddGoalkeeper
		local ok, detail = AIService.SetGoalkeeperEnabled(teamId, enabled)
		log(string.format("%s %s %s -> %s", player.Name, action, teamId, detail))
		sendFeedback(player, action, ok, detail)
		return
	end

	--[[
		Force a restart so each rule path can be exercised deliberately, rather
		than waiting for a match to produce one by chance (§81).
	]]
	if action == actions.ForceRestart then
		local restart = payload.Restart
		if typeof(restart) ~= "string" then
			sendFeedback(player, action, false, "invalid-restart")
			return
		end
		local teamId = FootballTeamConfig.Normalize(payload.TeamId)
			or FootballTeamConfig.Normalize(player:GetAttribute(FootballTeamConfig.AttributeName))
			or "Home"
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local context = {
			Reason = "dev-forced",
			-- Free kicks and penalties need a location; use where the player
			-- stands so the test is placed deliberately.
			Position = root and (root :: BasePart).Position or nil,
			Crossing = root and (root :: BasePart).Position or nil,
		}
		local ok = MatchRulesService.QueueRestart(restart, teamId, context)
		log(string.format("%s ForceRestart %s %s -> %s", player.Name, restart, teamId, tostring(ok)))
		sendFeedback(player, action, ok, if ok then restart else "rejected")
		return
	end

	if action == actions.ForceInjury then
		local actor = FootballerRegistryService.GetHumanActor(player)
		if not actor then
			sendFeedback(player, action, false, "no-character")
			return
		end
		local state = InjuryService.ForceInjury(actor, payload.State)
		log(string.format("%s ForceInjury -> %s", player.Name, tostring(state)))
		sendFeedback(player, action, state ~= nil, tostring(state))
		return
	end

	if action == actions.ResetPlayer then
		local ok, detail = resetPlayer(player)
		log(string.format("%s ResetPlayer -> %s", player.Name, detail))
		sendFeedback(player, action, ok, detail)
		return
	end

	if action == actions.ResetBall then
		BallService.Reset()
		log(string.format("%s ResetBall", player.Name))
		sendFeedback(player, action, true, "reset")
		return
	end

	--[[
		SHOT INTENSITY (§18). A power override for testing only; 100 is exactly
		normal play, so the control is inert until it is moved.
	]]
	if action == actions.SetShotIntensity then
		local config = FootballActionConfig.DevelopmentShotIntensity
		local requested = if typeof(payload) == "table" then payload.Value else nil
		if typeof(requested) ~= "number" then
			sendFeedback(player, action, false, "invalid-value")
			return
		end
		local clamped = math.clamp(math.floor(requested + 0.5), config.Minimum, config.Maximum)
		player:SetAttribute(config.AttributeName, clamped)
		sendFeedback(player, action, true)
		log(string.format("%s ShotIntensity -> %d", player.Name, clamped))
		return
	end

	--[[
		GOALKEEPER SKILL (§52). Applies to every keeper on the pitch, so a test
		can change the difficulty mid-session without respawning anyone.
	]]
	if action == actions.SetGoalkeeperSkill then
		local config = DevToolsConfig.GoalkeeperSkill
		local requested = if typeof(payload) == "table" then payload.Value else nil
		if typeof(requested) ~= "number" then
			sendFeedback(player, action, false, "invalid-value")
			return
		end
		local clamped = math.clamp(math.floor(requested + 0.5), config.Minimum, config.Maximum)
		GoalkeeperService.SetSkill(clamped / 100, nil)
		player:SetAttribute(config.AttributeName, clamped)
		sendFeedback(player, action, true)
		log(string.format("%s GoalkeeperSkill -> %d", player.Name, clamped))
		return
	end

	if action == actions.SetDribblingSkill then
		local skill = payload.Value
		if typeof(skill) ~= "number" then
			sendFeedback(player, action, false, "invalid-value")
			return
		end
		local config = DevToolsConfig.DribblingSkill
		local clamped = math.clamp(math.floor(skill), config.Minimum, config.Maximum)
		player:SetAttribute(config.AttributeName, clamped)
		log(string.format("%s DribblingSkill -> %d", player.Name, clamped))
		sendFeedback(player, action, true, tostring(clamped))
		return
	end
end

function DevToolsService.Initialize()
	if initialized then
		return
	end
	initialized = true

	local remotes = ReplicatedStorage:FindFirstChild(FootballActionConfig.RemotesFolderName)
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = FootballActionConfig.RemotesFolderName
		remotes.Parent = ReplicatedStorage
	end

	local function getOrCreate(name: string): RemoteEvent
		local existing = remotes:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
		return remote
	end

	requestRemote = getOrCreate(DevToolsConfig.RemoteName)
	feedbackRemote = getOrCreate(DevToolsConfig.FeedbackRemoteName)
	requestRemote.OnServerEvent:Connect(onRequest)

	local function initializePlayer(player: Player)
		-- Both test parameters start at their neutral values, so a fresh session
		-- behaves exactly like normal play until something is deliberately moved.
		player:SetAttribute(
			FootballActionConfig.DevelopmentShotIntensity.AttributeName,
			FootballActionConfig.DevelopmentShotIntensity.Default
		)
		player:SetAttribute(DevToolsConfig.GoalkeeperSkill.AttributeName, DevToolsConfig.GoalkeeperSkill.Default)
		local config = DevToolsConfig.DribblingSkill
		if typeof(player:GetAttribute(config.AttributeName)) ~= "number" then
			player:SetAttribute(config.AttributeName, config.Default)
		end
	end
	for _, player in Players:GetPlayers() do
		initializePlayer(player)
	end
	Players.PlayerAdded:Connect(initializePlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
	end)
end

return DevToolsService
