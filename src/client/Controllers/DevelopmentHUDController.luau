local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DevToolsConfig = require(Shared.Config.DevToolsConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local AnimationController = require(script.Parent:WaitForChild("AnimationController"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local CameraController = require(script.Parent.Parent.Camera:WaitForChild("CameraController"))

local DevelopmentHUDController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local gui: ScreenGui? = nil
local toolsPanel: ScrollingFrame? = nil
local toolsToggle: TextButton? = nil
local autoSprintButton: TextButton? = nil
local cameraButton: TextButton? = nil
local cameraDistanceButton: TextButton? = nil
local jogRateLabel: TextLabel? = nil
local jogRateMinusButton: TextButton? = nil
local jogRatePlusButton: TextButton? = nil
local shootingSkillLabel: TextLabel? = nil
local shootingSkillMinusButton: TextButton? = nil
local shootingSkillPlusButton: TextButton? = nil
local shootingSkillRemote: RemoteEvent? = nil
local connections: { RBXScriptConnection } = {}
local heldActions: { [string]: number } = {}
local meters = {}
local devToolsRemote: RemoteEvent? = nil
local aiCountLabels: { [string]: TextLabel } = {}
local goalkeeperLabels: { [string]: TextLabel } = {}
local matchDiagnosticsLabel: TextLabel? = nil
local dribblingSkillLabel: TextLabel? = nil

local function sendDevRequest(action: string, extra: { [string]: any }?)
	if not devToolsRemote then
		return
	end
	local payload = { Action = action }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	devToolsRemote:FireServer(payload)
end

-- Compact section header so the panel stays readable as tools are added.
local function createSectionHeader(parent: Instance, text: string, position: UDim2): TextLabel
	local header = Instance.new("TextLabel")
	header.Name = text .. "Header"
	header.Position = position
	header.Size = UDim2.fromOffset(290, 18)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.Text = text
	header.TextColor3 = Color3.fromRGB(67, 218, 255)
	header.TextSize = 11
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = parent
	return header
end

-- [-] value [+] row, used for AI counts and Dribbling Skill.
local function createStepperRow(
	parent: Instance,
	name: string,
	title: string,
	position: UDim2,
	onDelta: (number) -> ()
): TextLabel
	local container = Instance.new("Frame")
	container.Name = name
	container.Position = position
	container.Size = UDim2.fromOffset(290, 32)
	container.BackgroundColor3 = Color3.fromRGB(24, 28, 34)
	container.BackgroundTransparency = 0.12
	container.BorderSizePixel = 0
	container.Parent = parent

	local minus = Instance.new("TextButton")
	minus.Name = "Minus"
	minus.Position = UDim2.fromOffset(6, 4)
	minus.Size = UDim2.fromOffset(30, 24)
	minus.BackgroundColor3 = Color3.fromRGB(12, 18, 33)
	minus.BorderSizePixel = 0
	minus.Font = Enum.Font.GothamBold
	minus.Text = "-"
	minus.TextColor3 = Color3.fromRGB(240, 240, 240)
	minus.TextSize = 16
	minus.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.fromOffset(42, 4)
	label.Size = UDim2.fromOffset(206, 24)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamSemibold
	label.Text = title
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.TextSize = 13
	label.Parent = container

	local plus = Instance.new("TextButton")
	plus.Name = "Plus"
	plus.Position = UDim2.fromOffset(254, 4)
	plus.Size = UDim2.fromOffset(30, 24)
	plus.BackgroundColor3 = Color3.fromRGB(12, 18, 33)
	plus.BorderSizePixel = 0
	plus.Font = Enum.Font.GothamBold
	plus.Text = "+"
	plus.TextColor3 = Color3.fromRGB(240, 240, 240)
	plus.TextSize = 16
	plus.Parent = container

	minus.Activated:Connect(function() onDelta(-1) end)
	plus.Activated:Connect(function() onDelta(1) end)
	return label
end

local function createButton(parent: Instance, name: string, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = UDim2.fromOffset(220, 36)
	button.BackgroundColor3 = Color3.fromRGB(24, 28, 34)
	button.BackgroundTransparency = 0.12
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamSemibold
	button.TextColor3 = Color3.fromRGB(245, 245, 245)
	button.TextSize = 15
	button.AutoButtonColor = true
	button.Parent = parent
	return button
end

local function getActionConfig(actionType: string)
	if actionType == "ThroughPass" then
		return FootballActionConfig.ThroughPass
	elseif actionType == "KnockOn" then
		return FootballActionConfig.KnockOn
	end

	return FootballActionConfig.Pass
end

local function getIntensity(actionType: string, holdDuration: number): (number, number)
	local actionConfig = getActionConfig(actionType)
	local minIntensity = actionConfig.MinIntensity or 1
	local maxIntensity = actionConfig.MaxIntensity or minIntensity
	local holdMaxTime = math.max(actionConfig.HoldMaxTime or 0.75, 0.05)
	local alpha = math.clamp(holdDuration / holdMaxTime, 0, 1)
	return minIntensity + (maxIntensity - minIntensity) * alpha, alpha
end

local function createIntensityMeter(parent: Instance, actionType: string, title: string, position: UDim2)
	local container = Instance.new("Frame")
	container.Name = actionType .. "ChargeMeter"
	container.Position = position
	container.Size = UDim2.fromOffset(260, 46)
	container.BackgroundColor3 = Color3.fromRGB(24, 28, 34)
	container.BackgroundTransparency = 0.12
	container.BorderSizePixel = 0
	container.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.fromOffset(10, 4)
	label.Size = UDim2.new(1, -20, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamSemibold
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = container

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(10, 29)
	track.Size = UDim2.new(1, -20, 0, 6)
	track.BackgroundColor3 = Color3.fromRGB(58, 65, 74)
	track.BorderSizePixel = 0
	track.Parent = container

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(85, 170, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track

	meters[actionType] = {
		Title = title,
		Label = label,
		Fill = fill,
	}
end

local function createJogRateControl(parent: Instance, position: UDim2)
	local container = Instance.new("Frame")
	container.Name = "JogRateControl"
	container.Position = position
	container.Size = UDim2.fromOffset(300, 84)
	container.BackgroundColor3 = Color3.fromRGB(24, 28, 34)
	container.BackgroundTransparency = 0.12
	container.BorderSizePixel = 0
	container.Parent = parent

	local minusButton = Instance.new("TextButton")
	minusButton.Name = "JogRateMinusButton"
	minusButton.Position = UDim2.fromOffset(10, 10)
	minusButton.Size = UDim2.fromOffset(34, 34)
	minusButton.BackgroundColor3 = Color3.fromRGB(45, 52, 61)
	minusButton.BorderSizePixel = 0
	minusButton.Font = Enum.Font.GothamBold
	minusButton.Text = "-"
	minusButton.TextColor3 = Color3.fromRGB(245, 245, 245)
	minusButton.TextSize = 20
	minusButton.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "JogRateLabel"
	label.Position = UDim2.fromOffset(52, 4)
	label.Size = UDim2.new(1, -104, 1, -8)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamSemibold
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.TextSize = 12
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = container

	local plusButton = Instance.new("TextButton")
	plusButton.Name = "JogRatePlusButton"
	plusButton.Position = UDim2.new(1, -44, 0, 10)
	plusButton.Size = UDim2.fromOffset(34, 34)
	plusButton.BackgroundColor3 = Color3.fromRGB(45, 52, 61)
	plusButton.BorderSizePixel = 0
	plusButton.Font = Enum.Font.GothamBold
	plusButton.Text = "+"
	plusButton.TextColor3 = Color3.fromRGB(245, 245, 245)
	plusButton.TextSize = 20
	plusButton.Parent = container

	jogRateLabel = label
	jogRateMinusButton = minusButton
	jogRatePlusButton = plusButton
end

local function createShootingSkillControl(parent: Instance, position: UDim2)
	local container = Instance.new("Frame")
	container.Name = "ShootingSkillControl"
	container.Position = position
	container.Size = UDim2.fromOffset(300, 54)
	container.BackgroundColor3 = Color3.fromRGB(24, 28, 34)
	container.BackgroundTransparency = 0.12
	container.BorderSizePixel = 0
	container.Parent = parent

	local minus = Instance.new("TextButton")
	minus.Name = "ShootingSkillMinus"
	minus.Position = UDim2.fromOffset(10, 10)
	minus.Size = UDim2.fromOffset(34, 34)
	minus.BackgroundColor3 = Color3.fromRGB(45, 52, 61)
	minus.BorderSizePixel = 0
	minus.Font = Enum.Font.GothamBold
	minus.Text = "-"
	minus.TextColor3 = Color3.fromRGB(245, 245, 245)
	minus.TextSize = 20
	minus.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "ShootingSkillLabel"
	label.Position = UDim2.fromOffset(52, 0)
	label.Size = UDim2.new(1, -104, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamSemibold
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.TextSize = 13
	label.Parent = container

	local plus = minus:Clone()
	plus.Name = "ShootingSkillPlus"
	plus.Position = UDim2.new(1, -44, 0, 10)
	plus.Text = "+"
	plus.Parent = container

	shootingSkillLabel = label
	shootingSkillMinusButton = minus
	shootingSkillPlusButton = plus
end

local function updateShootingSkillControl()
	if shootingSkillLabel then
		local skill = localPlayer:GetAttribute("Beyond90ShootingSkill")
		shootingSkillLabel.Text = string.format("SHOOTING SKILL  %.0f", (if typeof(skill) == "number" then skill else 0) * 100)
	end
end

local function adjustShootingSkill(delta: number)
	if not shootingSkillRemote then
		return
	end
	local config = FootballActionConfig.Shoot.Skill
	local current = localPlayer:GetAttribute("Beyond90ShootingSkill")
	local value = if typeof(current) == "number" then current else config.Default
	shootingSkillRemote:FireServer(math.clamp(value + delta, config.Minimum, config.Maximum))
end

local function setMeterValue(actionType: string, holdDuration: number)
	local meter = meters[actionType]

	if not meter then
		return
	end

	if holdDuration <= 0 then
		meter.Fill.Size = UDim2.fromScale(0, 1)
		meter.Label.Text = string.format("%s --", meter.Title)
		return
	end

	local intensity, alpha = getIntensity(actionType, holdDuration)
	meter.Fill.Size = UDim2.fromScale(alpha, 1)
	meter.Label.Text = string.format("%s %.2fx", meter.Title, intensity)
end

local function updateIntensityMeters()
	local now = os.clock()

	for actionType, startedAt in heldActions do
		setMeterValue(actionType, now - startedAt)
	end
end

local function updateJogRateControl()
	if not jogRateLabel then
		return
	end

	local diagnostics = AnimationController.GetDiagnostics()
	jogRateLabel.Text = string.format(
		"LOC %s %s  RATE %.2fx\nSPD %.1f  ANG %.0f  PLAY %.2f\nACTION %s  EXIT %s\nBALL %s  LEAD %.1f  ETA %.2f",
		diagnostics.LocomotionFamily or "Default",
		diagnostics.Direction or "",
		AnimationController.GetJogPlaybackMultiplier(),
		diagnostics.HorizontalSpeed or 0,
		diagnostics.MovementAngle or 0,
		diagnostics.FinalPlaybackRate or 0,
		diagnostics.Action ~= "" and diagnostics.Action or "none",
		diagnostics.ActionExitTarget ~= "" and diagnostics.ActionExitTarget or "--",
		localPlayer:GetAttribute("Beyond90AnimationDribblePhase") or "--",
		localPlayer:GetAttribute("Beyond90AnimationBallLead") or 0,
		localPlayer:GetAttribute("Beyond90AnimationExpectedRecontactTime") or 0
	)
end

local function updateDevelopmentMeters()
	updateIntensityMeters()
	updateJogRateControl()
end

local function onFootballAction(action)
	local actionType = action.ActionType

	if actionType ~= "GroundPass" and actionType ~= "ThroughPass" and actionType ~= "KnockOn" then
		return
	end

	if action.Phase == "Pressed" then
		heldActions[actionType] = os.clock()
	elseif action.Phase == "Released" or action.Phase == "Cancelled" then
		heldActions[actionType] = nil
		setMeterValue(actionType, 0)
	end
end

local function updateAutoSprintButton()
	if not autoSprintButton then
		return
	end

	autoSprintButton.Text = if InputController.IsAutoSprintEnabled()
		then "AUTO SPRINT: ON"
		else "AUTO SPRINT: OFF"
end

local function updateCameraButton()
	if not cameraButton then
		return
	end

	local mode = CameraController.GetActiveMode()
	-- User-facing name only; the internal mode id stays "ThirdPerson" (§22).
	local displayMode = if mode == "ThirdPerson"
		then "PRO CAMERA"
		else string.upper(mode)
	cameraButton.Text = string.format("CAMERA: %s", displayMode)
end

local function updateCameraDistanceButton()
	if not cameraDistanceButton then
		return
	end

	cameraDistanceButton.Text = string.format("CAM DIST: %s", CameraController.GetBroadcastDistancePresetLabel())
end

local function createGui()
	local playerGui = localPlayer:WaitForChild("PlayerGui", 10)

	if not playerGui then
		warn(string.format("%s[Client][DevHUD] PlayerGui unavailable; development HUD was not created", GameConfig.LogPrefix))
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "Beyond90DevelopmentHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 400
	screenGui.Parent = playerGui
	gui = screenGui

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "ToolsPanel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 76, 0.5, 0)
	panel.Size = UDim2.fromOffset(326, 360)
	panel.CanvasSize = UDim2.fromOffset(0, 470)
	panel.ScrollBarThickness = 4
	panel.ScrollBarImageColor3 = Color3.fromRGB(67, 218, 255)
	panel.BackgroundColor3 = Color3.fromRGB(6, 10, 24)
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	toolsPanel = panel

	local toggle = Instance.new("TextButton")
	toggle.Name = "ToolsToggle"
	toggle.AnchorPoint = Vector2.new(0, 0.5)
	toggle.Position = UDim2.new(0, 12, 0.5, 0)
	toggle.Size = UDim2.fromOffset(54, 38)
	toggle.BackgroundColor3 = Color3.fromRGB(11, 19, 42)
	toggle.BackgroundTransparency = 0.05
	toggle.BorderSizePixel = 0
	toggle.Font = Enum.Font.GothamBold
	toggle.Text = "DEV"
	toggle.TextColor3 = Color3.fromRGB(67, 218, 255)
	toggle.TextSize = 12
	toggle.Parent = screenGui
	toolsToggle = toggle

	-- MATCH -----------------------------------------------------------------
	createSectionHeader(panel, "MATCH", UDim2.fromOffset(16, 10))
	aiCountLabels.Home = createStepperRow(panel, "HomeAIRow", "HOME AI  0", UDim2.fromOffset(16, 30), function(delta)
		sendDevRequest(
			if delta > 0 then DevToolsConfig.Actions.AddAI else DevToolsConfig.Actions.RemoveAI,
			{ TeamId = "Home" }
		)
	end)
	aiCountLabels.Away = createStepperRow(panel, "AwayAIRow", "AWAY AI  0", UDim2.fromOffset(16, 66), function(delta)
		sendDevRequest(
			if delta > 0 then DevToolsConfig.Actions.AddAI else DevToolsConfig.Actions.RemoveAI,
			{ TeamId = "Away" }
		)
	end)
	--[[
		Goalkeepers occupy a separate slot from the three outfield AI, so they get
		their own controls. Being able to remove the keeper you are shooting at is
		the whole point of this in Training.
	]]
	goalkeeperLabels.Home = createStepperRow(panel, "HomeGKRow", "HOME GK  --", UDim2.fromOffset(16, 102), function(delta)
		sendDevRequest(
			if delta > 0 then DevToolsConfig.Actions.AddGoalkeeper else DevToolsConfig.Actions.RemoveGoalkeeper,
			{ TeamId = "Home" }
		)
	end)
	goalkeeperLabels.Away = createStepperRow(panel, "AwayGKRow", "AWAY GK  --", UDim2.fromOffset(16, 138), function(delta)
		sendDevRequest(
			if delta > 0 then DevToolsConfig.Actions.AddGoalkeeper else DevToolsConfig.Actions.RemoveGoalkeeper,
			{ TeamId = "Away" }
		)
	end)

	local resetPlayerButton = createButton(panel, "ResetPlayerButton", UDim2.fromOffset(16, 174))
	resetPlayerButton.Text = "RESET PLAYER"
	resetPlayerButton.Size = UDim2.fromOffset(290, 32)

	-- BALL ------------------------------------------------------------------
	createSectionHeader(panel, "BALL", UDim2.fromOffset(16, 216))
	--[[
		Split into two half-width buttons on the same row rather than pushing
		everything below it down: the panel is laid out in absolute offsets, so
		inserting a full-width row would mean re-numbering every control under it.
	]]
	local resetBallButton = createButton(panel, "ResetBallButton", UDim2.fromOffset(16, 236))
	resetBallButton.Text = "RESET BALL"
	resetBallButton.Size = UDim2.fromOffset(142, 32)

	local givePossessionButton = createButton(panel, "GivePossessionButton", UDim2.fromOffset(164, 236))
	givePossessionButton.Text = "GIVE ME BALL"
	givePossessionButton.Size = UDim2.fromOffset(142, 32)
	dribblingSkillLabel = createStepperRow(panel, "DribblingSkillRow", "DRIBBLING  --", UDim2.fromOffset(16, 272), function(delta)
		local config = DevToolsConfig.DribblingSkill
		local current = localPlayer:GetAttribute(config.AttributeName)
		current = if typeof(current) == "number" then current else config.Default
		sendDevRequest(DevToolsConfig.Actions.SetDribblingSkill, {
			Value = math.clamp(current + delta * config.Step, config.Minimum, config.Maximum),
		})
	end)

	-- DIAGNOSTICS -----------------------------------------------------------
	createSectionHeader(panel, "DIAGNOSTICS", UDim2.fromOffset(16, 316))
	autoSprintButton = createButton(panel, "AutoSprintButton", UDim2.fromOffset(16, 336))
	autoSprintButton.Size = UDim2.fromOffset(290, 32)
	cameraButton = createButton(panel, "CameraModeButton", UDim2.fromOffset(16, 372))
	cameraButton.Size = UDim2.fromOffset(290, 32)
	cameraDistanceButton = createButton(panel, "CameraDistanceButton", UDim2.fromOffset(16, 408))
	cameraDistanceButton.Size = UDim2.fromOffset(290, 32)
	createIntensityMeter(panel, "GroundPass", "PASS INTENSITY", UDim2.fromOffset(16, 448))
	createIntensityMeter(panel, "ThroughPass", "THROUGH INTENSITY", UDim2.fromOffset(16, 500))
	createIntensityMeter(panel, "KnockOn", "KNOCK-ON INTENSITY", UDim2.fromOffset(16, 552))
	createJogRateControl(panel, UDim2.fromOffset(16, 604))
	createShootingSkillControl(panel, UDim2.fromOffset(16, 694))
	--[[
		MATCH RULES (§80, §81).

		Development-only: a compact read-out of the referee's state, and buttons
		that force each restart so every rule path can be exercised deliberately
		rather than waiting for a match to produce one by chance.
	]]
	createSectionHeader(panel, "MATCH RULES", UDim2.fromOffset(16, 742))

	matchDiagnosticsLabel = Instance.new("TextLabel")
	matchDiagnosticsLabel.Name = "MatchDiagnostics"
	matchDiagnosticsLabel.Position = UDim2.fromOffset(16, 762)
	matchDiagnosticsLabel.Size = UDim2.fromOffset(290, 58)
	matchDiagnosticsLabel.BackgroundTransparency = 1
	matchDiagnosticsLabel.Font = Enum.Font.Code
	matchDiagnosticsLabel.Text = "phase=--"
	matchDiagnosticsLabel.TextColor3 = Color3.fromRGB(198, 208, 224)
	matchDiagnosticsLabel.TextSize = 11
	matchDiagnosticsLabel.TextXAlignment = Enum.TextXAlignment.Left
	matchDiagnosticsLabel.TextYAlignment = Enum.TextYAlignment.Top
	matchDiagnosticsLabel.Parent = panel

	local forcedRestarts = {
		{ Label = "FORCE THROW-IN", Restart = "ThrowIn" },
		{ Label = "FORCE CORNER", Restart = "CornerKick" },
		{ Label = "FORCE GOAL KICK", Restart = "GoalKick" },
		{ Label = "FORCE FREE KICK", Restart = "FreeKick" },
		{ Label = "FORCE PENALTY", Restart = "Penalty" },
	}
	for index, entry in forcedRestarts do
		local button = createButton(panel, "Force" .. entry.Restart, UDim2.fromOffset(16, 826 + (index - 1) * 34))
		button.Text = entry.Label
		button.Size = UDim2.fromOffset(290, 30)
		button.TextSize = 12
		table.insert(connections, button.Activated:Connect(function()
			sendDevRequest(DevToolsConfig.Actions.ForceRestart, { Restart = entry.Restart })
		end))
	end

	local injuryButton = createButton(panel, "ForceInjury", UDim2.fromOffset(16, 826 + #forcedRestarts * 34))
	injuryButton.Text = "FORCE INJURY (SELF)"
	injuryButton.Size = UDim2.fromOffset(290, 30)
	injuryButton.TextSize = 12
	table.insert(connections, injuryButton.Activated:Connect(function()
		sendDevRequest(DevToolsConfig.Actions.ForceInjury, {})
	end))

	--[[
		TEST PARAMETERS (§18, §52).

		Shot Intensity and Goalkeeper Skill are deliberately adjacent and
		deliberately distinct. Shooting Skill (above) is accuracy; Shot Intensity
		is raw power; Goalkeeper Skill is the opposition. §70 requires shooting and
		goalkeeping to be balanced against each other, which needs all three to be
		independently settable.
	]]
	local testBase = 826 + (#forcedRestarts + 1) * 34
	createSectionHeader(panel, "TEST PARAMETERS", UDim2.fromOffset(16, testBase + 8))

	shotIntensityLabel = createStepperRow(
		panel,
		"ShotIntensityRow",
		"SHOT INTENSITY  --",
		UDim2.fromOffset(16, testBase + 28),
		function(delta)
			local config = FootballActionConfig.DevelopmentShotIntensity
			local current = localPlayer:GetAttribute(config.AttributeName)
			current = if typeof(current) == "number" then current else config.Default
			sendDevRequest(DevToolsConfig.Actions.SetShotIntensity, {
				Value = math.clamp(current + delta * config.Step, config.Minimum, config.Maximum),
			})
		end
	)

	goalkeeperSkillLabel = createStepperRow(
		panel,
		"GoalkeeperSkillRow",
		"GK SKILL  --",
		UDim2.fromOffset(16, testBase + 64),
		function(delta)
			local config = DevToolsConfig.GoalkeeperSkill
			local current = localPlayer:GetAttribute(config.AttributeName)
			current = if typeof(current) == "number" then current else config.Default
			sendDevRequest(DevToolsConfig.Actions.SetGoalkeeperSkill, {
				Value = math.clamp(current + delta * config.Step, config.Minimum, config.Maximum),
			})
		end
	)

	panel.CanvasSize = UDim2.fromOffset(0, testBase + 130)

	local remotes = ReplicatedStorage:FindFirstChild(FootballActionConfig.RemotesFolderName)
	shootingSkillRemote = remotes and remotes:FindFirstChild(FootballActionConfig.DevelopmentShootingSkillRemoteName) :: RemoteEvent?
	devToolsRemote = remotes and remotes:FindFirstChild(DevToolsConfig.RemoteName) :: RemoteEvent?

	table.insert(connections, resetPlayerButton.Activated:Connect(function()
		sendDevRequest(DevToolsConfig.Actions.ResetPlayer)
	end))
	table.insert(connections, resetBallButton.Activated:Connect(function()
		sendDevRequest(DevToolsConfig.Actions.ResetBall)
	end))
	table.insert(connections, givePossessionButton.Activated:Connect(function()
		sendDevRequest(DevToolsConfig.Actions.GivePossession)
	end))

	-- Reflect authoritative AI counts and skill back into the panel.
	local feedback = remotes and remotes:FindFirstChild(DevToolsConfig.FeedbackRemoteName)
	if feedback and feedback:IsA("RemoteEvent") then
		table.insert(connections, feedback.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then return end
			if aiCountLabels.Home and typeof(payload.HomeAI) == "number" then
				aiCountLabels.Home.Text = string.format("HOME AI  %d", payload.HomeAI)
			end
			if matchDiagnosticsLabel then
				matchDiagnosticsLabel.Text = table.concat({
					string.format("phase=%s  period=%s", tostring(payload.MatchPhase), tostring(payload.MatchPeriod)),
					string.format("clock=%ss  restart=%s", tostring(payload.MatchClock), tostring(payload.RestartType)),
					string.format("lastTouch=%s", tostring(payload.LastTouch)),
				}, "\n")
			end
			if goalkeeperLabels.Home and typeof(payload.HomeGoalkeeper) == "boolean" then
				goalkeeperLabels.Home.Text = "HOME GK  " .. (if payload.HomeGoalkeeper then "ON" else "OFF")
			end
			if goalkeeperLabels.Away and typeof(payload.AwayGoalkeeper) == "boolean" then
				goalkeeperLabels.Away.Text = "AWAY GK  " .. (if payload.AwayGoalkeeper then "ON" else "OFF")
			end
			if aiCountLabels.Away and typeof(payload.AwayAI) == "number" then
				aiCountLabels.Away.Text = string.format("AWAY AI  %d", payload.AwayAI)
			end
		end))
	end
	local function refreshTestParameters()
		local intensityConfig = FootballActionConfig.DevelopmentShotIntensity
		if shotIntensityLabel then
			local value = localPlayer:GetAttribute(intensityConfig.AttributeName)
			value = if typeof(value) == "number" then value else intensityConfig.Default
			shotIntensityLabel.Text = string.format("SHOT INTENSITY  %d", value)
		end
		local gkConfig = DevToolsConfig.GoalkeeperSkill
		if goalkeeperSkillLabel then
			local value = localPlayer:GetAttribute(gkConfig.AttributeName)
			value = if typeof(value) == "number" then value else gkConfig.Default
			goalkeeperSkillLabel.Text = string.format("GK SKILL  %d", value)
		end
	end
	refreshTestParameters()
	table.insert(connections, localPlayer:GetAttributeChangedSignal(
		FootballActionConfig.DevelopmentShotIntensity.AttributeName
	):Connect(refreshTestParameters))
	table.insert(connections, localPlayer:GetAttributeChangedSignal(
		DevToolsConfig.GoalkeeperSkill.AttributeName
	):Connect(refreshTestParameters))

	local function refreshDribblingSkill()
		if not dribblingSkillLabel then return end
		local value = localPlayer:GetAttribute(DevToolsConfig.DribblingSkill.AttributeName)
		dribblingSkillLabel.Text = string.format(
			"DRIBBLING  %s",
			if typeof(value) == "number" then tostring(math.floor(value)) else "--"
		)
	end
	refreshDribblingSkill()
	table.insert(connections, localPlayer:GetAttributeChangedSignal(
		DevToolsConfig.DribblingSkill.AttributeName
	):Connect(refreshDribblingSkill))

	table.insert(connections, toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
		toggle.Text = if panel.Visible then "CLOSE" else "DEV"
	end))
	table.insert(connections, autoSprintButton.Activated:Connect(function()
		InputController.ToggleAutoSprint()
	end))
	table.insert(connections, cameraButton.Activated:Connect(function()
		CameraController.TogglePrimaryMode()
	end))
	table.insert(connections, cameraDistanceButton.Activated:Connect(function()
		CameraController.CycleBroadcastDistancePreset()
		updateCameraDistanceButton()
	end))
	table.insert(connections, jogRateMinusButton.Activated:Connect(function()
		AnimationController.AdjustJogPlaybackMultiplier(-AnimationController.GetJogPlaybackMultiplierStep())
		updateJogRateControl()
	end))
	table.insert(connections, jogRatePlusButton.Activated:Connect(function()
		AnimationController.AdjustJogPlaybackMultiplier(AnimationController.GetJogPlaybackMultiplierStep())
		updateJogRateControl()
	end))
	table.insert(connections, shootingSkillMinusButton.Activated:Connect(function()
		adjustShootingSkill(-FootballActionConfig.Shoot.Skill.DevelopmentStep)
	end))
	table.insert(connections, shootingSkillPlusButton.Activated:Connect(function()
		adjustShootingSkill(FootballActionConfig.Shoot.Skill.DevelopmentStep)
	end))
	table.insert(connections, localPlayer:GetAttributeChangedSignal("Beyond90ShootingSkill"):Connect(updateShootingSkillControl))
	table.insert(connections, InputController.GetAutoSprintChangedEvent().Event:Connect(updateAutoSprintButton))
	table.insert(connections, CameraController.GetModeChangedEvent().Event:Connect(updateCameraButton))
	table.insert(connections, InputController.GetFootballActionEvent().Event:Connect(onFootballAction))
	table.insert(connections, RunService.RenderStepped:Connect(updateDevelopmentMeters))

	setMeterValue("GroundPass", 0)
	setMeterValue("ThroughPass", 0)
	setMeterValue("KnockOn", 0)
	updateAutoSprintButton()
	updateCameraButton()
	updateCameraDistanceButton()
	updateJogRateControl()
	updateShootingSkillControl()
end

function DevelopmentHUDController.Initialize()
	if initialized then
		return
	end

	initialized = true
	createGui()
end

function DevelopmentHUDController.Destroy()
	if not initialized then
		return
	end

	initialized = false

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	table.clear(heldActions)

	if gui then
		gui:Destroy()
		gui = nil
	end
	toolsPanel = nil
	toolsToggle = nil

	autoSprintButton = nil
	cameraButton = nil
	cameraDistanceButton = nil
	jogRateLabel = nil
	jogRateMinusButton = nil
	jogRatePlusButton = nil
	shootingSkillLabel = nil
	shootingSkillMinusButton = nil
	shootingSkillPlusButton = nil
	shootingSkillRemote = nil
	table.clear(meters)
end

return DevelopmentHUDController
