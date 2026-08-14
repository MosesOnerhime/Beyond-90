local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local InputController = require(script.Parent:WaitForChild("InputController"))
local CameraController = require(script.Parent.Parent.Camera:WaitForChild("CameraController"))

local DevelopmentHUDController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local gui: ScreenGui? = nil
local autoSprintButton: TextButton? = nil
local cameraButton: TextButton? = nil
local connections: { RBXScriptConnection } = {}

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
	local displayMode = if mode == "FirstPerson" then "FIRST PERSON" else string.upper(mode)
	cameraButton.Text = string.format("CAMERA: %s", displayMode)
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

	table.insert(connections, autoSprintButton.Activated:Connect(function()
		InputController.ToggleAutoSprint()
	end))
	table.insert(connections, cameraButton.Activated:Connect(function()
		CameraController.TogglePrimaryMode()
	end))
	table.insert(connections, InputController.GetAutoSprintChangedEvent().Event:Connect(updateAutoSprintButton))
	table.insert(connections, CameraController.GetModeChangedEvent().Event:Connect(updateCameraButton))

	updateAutoSprintButton()
	updateCameraButton()
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

	if gui then
		gui:Destroy()
		gui = nil
	end

	autoSprintButton = nil
	cameraButton = nil
end

return DevelopmentHUDController
