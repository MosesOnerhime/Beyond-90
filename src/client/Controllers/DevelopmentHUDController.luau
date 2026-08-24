local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local AnimationController = require(script.Parent:WaitForChild("AnimationController"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local CameraController = require(script.Parent.Parent.Camera:WaitForChild("CameraController"))

local DevelopmentHUDController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local gui: ScreenGui? = nil
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
	local displayMode = if mode == "ThirdPerson"
		then "THIRD PERSON"
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
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 20
	screenGui.Parent = playerGui
	gui = screenGui

	autoSprintButton = createButton(screenGui, "AutoSprintButton", UDim2.fromOffset(16, 16))
	cameraButton = createButton(screenGui, "CameraModeButton", UDim2.fromOffset(16, 58))
	cameraDistanceButton = createButton(screenGui, "CameraDistanceButton", UDim2.fromOffset(16, 100))
	createIntensityMeter(screenGui, "GroundPass", "PASS INTENSITY", UDim2.fromOffset(16, 148))
	createIntensityMeter(screenGui, "ThroughPass", "THROUGH INTENSITY", UDim2.fromOffset(16, 200))
	createIntensityMeter(screenGui, "KnockOn", "KNOCK-ON INTENSITY", UDim2.fromOffset(16, 252))
	createJogRateControl(screenGui, UDim2.fromOffset(16, 304))
	createShootingSkillControl(screenGui, UDim2.fromOffset(16, 394))
	local remotes = ReplicatedStorage:FindFirstChild(FootballActionConfig.RemotesFolderName)
	shootingSkillRemote = remotes and remotes:FindFirstChild(FootballActionConfig.DevelopmentShootingSkillRemoteName) :: RemoteEvent?

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
