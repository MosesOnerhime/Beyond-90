local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local InputController = {}

local localPlayer = Players.LocalPlayer
local inputConfig = PlayerConfig.Input
local locomotionConfig = PlayerConfig.Locomotion

local initialized = false
local inputFolder: Folder? = nil
local inputContext: Instance? = nil
local movementAction: Instance? = nil
local sprintAction: Instance? = nil
local cameraToggleAction: Instance? = nil
local sprintButtonGui: ScreenGui? = nil
local connections: { RBXScriptConnection } = {}
local pressedKeys: { [Enum.KeyCode]: boolean } = {}
local fallbackThumbstick = Vector2.zero
local cameraToggleEvent = Instance.new("BindableEvent")
local autoSprintChangedEvent = Instance.new("BindableEvent")
local manualSprintRequested = false
local autoSprintEnabled = inputConfig.AutoSprintDefaultEnabled == true

local inputState = {
	MoveVector = Vector2.zero,
	MoveDirection = Vector3.zero,
	MoveMagnitude = 0,
	SprintRequested = false,
	ManualSprintRequested = false,
	AutoSprintEnabled = autoSprintEnabled,
	Source = "InputAction",
}

local function log(message: string)
	print(string.format("%s[Client][Input] %s", GameConfig.LogPrefix, message))
end

local function warnLog(message: string)
	warn(string.format("%s[Client][Input] %s", GameConfig.LogPrefix, message))
end

local function setProperty(instance: Instance, property: string, value: any): boolean
	local ok, err = pcall(function()
		instance[property] = value
	end)

	if not ok then
		warnLog(string.format("Could not set %s.%s: %s", instance.ClassName, property, tostring(err)))
	end

	return ok
end

local function getFacingDirection(): Vector3
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
			Vector3.new(0, 0, -1)
		)
	end

	return Vector3.new(0, 0, -1)
end

local function getCameraRelativeDirection(moveVector: Vector2): (Vector3, number)
	local magnitude = math.clamp(moveVector.Magnitude, 0, 1)

	if magnitude <= locomotionConfig.RawInputDeadzone then
		return Vector3.zero, 0
	end

	local camera = Workspace.CurrentCamera

	if not camera then
		return Vector3.zero, 0
	end

	local cameraForward = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(camera.CFrame.LookVector), getFacingDirection())
	local cameraRight = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(camera.CFrame.RightVector), Vector3.xAxis)
	local worldDirection = cameraRight * moveVector.X + cameraForward * moveVector.Y

	return BallControlMath.SafeUnit(worldDirection, Vector3.zero), magnitude
end

local function setMoveVector(moveVector: Vector2, source: string)
	local clamped = if moveVector.Magnitude > 1 then moveVector.Unit else moveVector
	local direction, magnitude = getCameraRelativeDirection(clamped)

	inputState.MoveVector = clamped
	inputState.MoveDirection = direction
	inputState.MoveMagnitude = magnitude
	inputState.Source = source
	inputState.SprintRequested = manualSprintRequested
		or (autoSprintEnabled and magnitude >= inputConfig.AutoSprintThreshold)
end

local function setManualSprintRequested(requested: boolean, source: string)
	manualSprintRequested = requested
	inputState.ManualSprintRequested = requested
	inputState.SprintRequested = manualSprintRequested
		or (autoSprintEnabled and inputState.MoveMagnitude >= inputConfig.AutoSprintThreshold)
	inputState.Source = source
end

local function createInputFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(inputConfig.InputFolderName)

	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = inputConfig.InputFolderName
	folder.Parent = ReplicatedStorage

	return folder
end

local function createSprintTouchButton(): TextButton?
	if not UserInputService.TouchEnabled then
		return nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")

	if not playerGui then
		return nil
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Beyond90InputGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	sprintButtonGui = gui

	local button = Instance.new("TextButton")
	button.Name = "SprintButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = inputConfig.SprintTouchButtonPosition
	button.Size = UDim2.fromOffset(92, 52)
	button.BackgroundTransparency = 0.25
	button.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
	button.Text = "Sprint"
	button.TextColor3 = Color3.fromRGB(245, 245, 245)
	button.TextScaled = true
	button.Parent = gui

	return button
end

local function addBinding(parent: Instance, name: string, properties: { [string]: any }): Instance?
	local ok, binding = pcall(function()
		return Instance.new("InputBinding")
	end)

	if not ok then
		return nil
	end

	binding.Name = name

	for property, value in properties do
		setProperty(binding, property, value)
	end

	binding.Parent = parent
	return binding
end

local function setupInputActions(): boolean
	local okContext, context = pcall(function()
		return Instance.new("InputContext")
	end)
	local okMove, moveAction = pcall(function()
		return Instance.new("InputAction")
	end)
	local okSprint, sprint = pcall(function()
		return Instance.new("InputAction")
	end)
	local okCameraToggle, cameraToggle = pcall(function()
		return Instance.new("InputAction")
	end)

	if not okContext or not okMove or not okSprint or not okCameraToggle then
		return false
	end

	inputFolder = createInputFolder()
	context.Name = inputConfig.PlayContextName
	setProperty(context, "Enabled", true)
	setProperty(context, "Sink", false)
	context.Parent = inputFolder
	inputContext = context

	moveAction.Name = inputConfig.MoveActionName
	setProperty(moveAction, "Type", Enum.InputActionType.Direction2D)
	moveAction.Parent = context
	movementAction = moveAction

	addBinding(moveAction, "KeyboardWASD", {
		Up = Enum.KeyCode.W,
		Down = Enum.KeyCode.S,
		Left = Enum.KeyCode.A,
		Right = Enum.KeyCode.D,
		ClampMagnitudeToOne = true,
	})
	addBinding(moveAction, "KeyboardArrows", {
		Up = Enum.KeyCode.Up,
		Down = Enum.KeyCode.Down,
		Left = Enum.KeyCode.Left,
		Right = Enum.KeyCode.Right,
		ClampMagnitudeToOne = true,
	})
	addBinding(moveAction, "GamepadLeftStick", {
		KeyCode = Enum.KeyCode.Thumbstick1,
		ClampMagnitudeToOne = true,
	})

	table.insert(connections, moveAction.StateChanged:Connect(function(value)
		if typeof(value) == "Vector2" then
			setMoveVector(value, "InputAction")
		end
	end))

	sprint.Name = inputConfig.SprintActionName
	setProperty(sprint, "Type", Enum.InputActionType.Bool)
	sprint.Parent = context
	sprintAction = sprint

	addBinding(sprint, "KeyboardLeftShift", {
		KeyCode = Enum.KeyCode.LeftShift,
	})
	addBinding(sprint, "KeyboardRightShift", {
		KeyCode = Enum.KeyCode.RightShift,
	})
	addBinding(sprint, "GamepadLeftStickButton", {
		KeyCode = Enum.KeyCode.ButtonL3,
	})
	addBinding(sprint, "GamepadY", {
		KeyCode = Enum.KeyCode.ButtonY,
	})

	local sprintButton = createSprintTouchButton()

	if sprintButton then
		addBinding(sprint, "TouchButton", {
			UIButton = sprintButton,
		})
	end

	table.insert(connections, sprint.StateChanged:Connect(function(value)
		if typeof(value) == "boolean" then
			setManualSprintRequested(value, "InputAction")
		end
	end))

	cameraToggle.Name = inputConfig.CameraToggleActionName
	setProperty(cameraToggle, "Type", Enum.InputActionType.Bool)
	cameraToggle.Parent = context
	cameraToggleAction = cameraToggle

	addBinding(cameraToggle, "KeyboardC", {
		KeyCode = inputConfig.CameraToggleKey,
	})

	table.insert(connections, cameraToggle.StateChanged:Connect(function(value)
		if value == true then
			cameraToggleEvent:Fire()
		end
	end))

	local moveStateOk, moveState = pcall(function()
		return moveAction:GetState()
	end)

	if moveStateOk and typeof(moveState) == "Vector2" then
		setMoveVector(moveState, "InputAction")
	end

	local sprintStateOk, sprintState = pcall(function()
		return sprint:GetState()
	end)

	if sprintStateOk and typeof(sprintState) == "boolean" then
		setManualSprintRequested(sprintState, "InputAction")
	end

	return true
end

local function getFallbackKeyboardVector(): Vector2
	if UserInputService:GetFocusedTextBox() then
		return Vector2.zero
	end

	local x = 0
	local y = 0

	if pressedKeys[Enum.KeyCode.A] or pressedKeys[Enum.KeyCode.Left] then
		x -= 1
	end

	if pressedKeys[Enum.KeyCode.D] or pressedKeys[Enum.KeyCode.Right] then
		x += 1
	end

	if pressedKeys[Enum.KeyCode.W] or pressedKeys[Enum.KeyCode.Up] then
		y += 1
	end

	if pressedKeys[Enum.KeyCode.S] or pressedKeys[Enum.KeyCode.Down] then
		y -= 1
	end

	local vector = Vector2.new(x, y)

	if vector.Magnitude > 1 then
		return vector.Unit
	end

	return vector
end

local function refreshFallbackMoveVector()
	local keyboardVector = getFallbackKeyboardVector()
	local moveVector = if fallbackThumbstick.Magnitude > keyboardVector.Magnitude
		then fallbackThumbstick
		else keyboardVector

	setMoveVector(moveVector, "UserInputService")
end

local function setupUserInputFallback()
	inputState.Source = "UserInputService"

	table.insert(connections, UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
		if gameProcessed and UserInputService:GetFocusedTextBox() then
			return
		end

		pressedKeys[inputObject.KeyCode] = true

		if inputObject.KeyCode == Enum.KeyCode.LeftShift
			or inputObject.KeyCode == Enum.KeyCode.RightShift
			or inputObject.KeyCode == Enum.KeyCode.ButtonL3
			or inputObject.KeyCode == Enum.KeyCode.ButtonY
		then
			setManualSprintRequested(true, "UserInputService")
		end

		if inputObject.KeyCode == inputConfig.CameraToggleKey then
			cameraToggleEvent:Fire()
		end

		refreshFallbackMoveVector()
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(inputObject)
		pressedKeys[inputObject.KeyCode] = nil

		if inputObject.KeyCode == Enum.KeyCode.LeftShift
			or inputObject.KeyCode == Enum.KeyCode.RightShift
			or inputObject.KeyCode == Enum.KeyCode.ButtonL3
			or inputObject.KeyCode == Enum.KeyCode.ButtonY
		then
			setManualSprintRequested(false, "UserInputService")
		end

		if inputObject.KeyCode == Enum.KeyCode.Thumbstick1 then
			fallbackThumbstick = Vector2.zero
		end

		refreshFallbackMoveVector()
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(inputObject)
		if inputObject.KeyCode ~= Enum.KeyCode.Thumbstick1 then
			return
		end

		local position = inputObject.Position
		fallbackThumbstick = Vector2.new(position.X, position.Y)

		if fallbackThumbstick.Magnitude > 1 then
			fallbackThumbstick = fallbackThumbstick.Unit
		end

		refreshFallbackMoveVector()
	end))
end

function InputController.GetInputState()
	return {
		MoveVector = inputState.MoveVector,
		MoveDirection = inputState.MoveDirection,
		MoveMagnitude = inputState.MoveMagnitude,
		SprintRequested = inputState.SprintRequested,
		ManualSprintRequested = inputState.ManualSprintRequested,
		AutoSprintEnabled = inputState.AutoSprintEnabled,
		Source = inputState.Source,
	}
end

function InputController.GetCameraToggleEvent(): BindableEvent
	return cameraToggleEvent
end

function InputController.GetAutoSprintChangedEvent(): BindableEvent
	return autoSprintChangedEvent
end

function InputController.IsAutoSprintEnabled(): boolean
	return autoSprintEnabled
end

function InputController.SetAutoSprintEnabled(enabled: boolean)
	if autoSprintEnabled == enabled then
		return
	end

	autoSprintEnabled = enabled
	inputState.AutoSprintEnabled = enabled
	inputState.SprintRequested = manualSprintRequested
		or (autoSprintEnabled and inputState.MoveMagnitude >= inputConfig.AutoSprintThreshold)
	autoSprintChangedEvent:Fire(enabled)
end

function InputController.ToggleAutoSprint()
	InputController.SetAutoSprintEnabled(not autoSprintEnabled)
end

function InputController.Initialize()
	if initialized then
		return
	end

	initialized = true

	if setupInputActions() then
		log("Input source: InputAction")
	else
		setupUserInputFallback()
		warnLog("InputAction instances unavailable; using UserInputService fallback")
	end
end

function InputController.Destroy()
	if not initialized then
		return
	end

	initialized = false

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	table.clear(pressedKeys)
	fallbackThumbstick = Vector2.zero
	setMoveVector(Vector2.zero, inputState.Source)
	setManualSprintRequested(false, inputState.Source)
	autoSprintEnabled = inputConfig.AutoSprintDefaultEnabled == true
	inputState.AutoSprintEnabled = autoSprintEnabled

	if inputContext then
		inputContext:Destroy()
		inputContext = nil
	end

	if sprintButtonGui then
		sprintButtonGui:Destroy()
		sprintButtonGui = nil
	end

	movementAction = nil
	sprintAction = nil
	cameraToggleAction = nil
	inputFolder = nil
end

return InputController
