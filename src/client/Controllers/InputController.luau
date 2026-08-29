local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local CameraConfig = require(Shared.Config.CameraConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)

local InputController = {}

local localPlayer = Players.LocalPlayer
local inputConfig = PlayerConfig.Input
local locomotionConfig = PlayerConfig.Locomotion

local initialized = false
local inputFolder: Folder? = nil
local inputContext: Instance? = nil
local movementAction: Instance? = nil
local sprintAction: Instance? = nil
local jumpAction: Instance? = nil
local cameraToggleAction: Instance? = nil
local passAction: Instance? = nil
local throughPassAction: Instance? = nil
local knockOnAction: Instance? = nil
local shootAction: Instance? = nil
local connections: { RBXScriptConnection } = {}
local pressedKeys: { [Enum.KeyCode]: boolean } = {}
local actionStartedAt: { [string]: number } = {}
local fallbackThumbstick = Vector2.zero
local moveStateChanges = 0
local fallbackActive = false
local cameraToggleEvent = Instance.new("BindableEvent")
local jumpEvent = Instance.new("BindableEvent")
local footballActionEvent = Instance.new("BindableEvent")
local cameraLockToggleEvent = Instance.new("BindableEvent")
local tackleAction = nil
local autoSprintChangedEvent = Instance.new("BindableEvent")
local manualSprintRequested = false
local autoSprintEnabled = inputConfig.AutoSprintDefaultEnabled == true
local passCommitToken = 0
local lastPassReleaseAt = -math.huge
local passSecondTap = false
local nativeControls = nil
local clickToMoveConnection: RBXScriptConnection? = nil

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

local function disableNativeClickToMove()
	local playerModule = StarterPlayer:FindFirstChild("PlayerModule")
	local contexts = playerModule and playerModule:FindFirstChild("InputContexts")
	local characterContext = contexts and contexts:FindFirstChild("CharacterContext")
	for _, actionName in { "ClickToMoveAction", "ClickToMovePositionAction" } do
		local action = characterContext and characterContext:FindFirstChild(actionName)
		if action then
			pcall(function() action.Enabled = false end)
		end
	end
	local camera = Workspace.CurrentCamera
	local marker = camera and camera:FindFirstChild("ClickToMoveDisplay")
	if marker then marker:Destroy() end
	if camera then
		clickToMoveConnection = camera.ChildAdded:Connect(function(child)
			if child.Name == "ClickToMoveDisplay" then
				child:Destroy()
			end
		end)
	end
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

local function getPitchMetadata()
	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local pitchFolder = rootFolder and rootFolder:FindFirstChild("Pitch")
	local gameplayBounds = pitchFolder and pitchFolder:FindFirstChild("GameplayBounds")

	if not gameplayBounds or not gameplayBounds:IsA("BasePart") then
		return nil
	end

	local lengthAxis = gameplayBounds:GetAttribute("PitchLengthAxis")
	local widthAxis = gameplayBounds:GetAttribute("PitchWidthAxis")

	if typeof(lengthAxis) ~= "Vector3" or typeof(widthAxis) ~= "Vector3" then
		return nil
	end

	return {
		LengthAxis = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(lengthAxis), Vector3.new(0, 0, 1)),
		WidthAxis = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(widthAxis), Vector3.new(1, 0, 0)),
	}
end

local getCameraRelativeDirection

local function getBroadcastDirection(moveVector: Vector2): (Vector3, number)
	local magnitude = math.clamp(moveVector.Magnitude, 0, 1)

	if magnitude <= locomotionConfig.RawInputDeadzone then
		return Vector3.zero, 0
	end

	local pitchState = getPitchMetadata()

	if not pitchState then
		return getCameraRelativeDirection(moveVector)
	end

	local sideSign = if CameraConfig.Broadcast.BroadcastSide >= 0 then 1 else -1
	local screenRight = -pitchState.LengthAxis
	local screenForward = pitchState.WidthAxis * -sideSign
	local worldDirection = screenRight * moveVector.X + screenForward * moveVector.Y

	return BallControlMath.SafeUnit(worldDirection, Vector3.zero), magnitude
end

getCameraRelativeDirection = function(moveVector: Vector2): (Vector3, number)
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

local function getWorldMoveDirection(moveVector: Vector2): (Vector3, number)
	local cameraMode = localPlayer:GetAttribute("Beyond90CameraMode")

	if cameraMode == "ThirdPerson" or cameraMode == "FirstPerson" then
		return getCameraRelativeDirection(moveVector)
	end

	return getBroadcastDirection(moveVector)
end

local function setMoveVector(moveVector: Vector2, source: string)
	local clamped = if moveVector.Magnitude > 1 then moveVector.Unit else moveVector
	local direction, magnitude = getWorldMoveDirection(clamped)

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

local function fireFootballAction(actionType: string, phase: string, holdDuration: number?)
	local state = InputController.GetInputState()

	footballActionEvent:Fire({
		ActionType = actionType,
		Phase = phase,
		HoldDuration = holdDuration or 0,
		MoveVector = state.MoveVector,
		AimDirection = state.MoveDirection,
		MoveMagnitude = state.MoveMagnitude,
		SprintRequested = state.SprintRequested,
		Source = state.Source,
		Timestamp = os.clock(),
	})
end

local function handleBoolFootballAction(actionType: string, value: any)
	if typeof(value) ~= "boolean" then
		return
	end

	if value then
		actionStartedAt[actionType] = os.clock()
		fireFootballAction(actionType, "Pressed", 0)

		return
	end

	local startedAt = actionStartedAt[actionType]
	actionStartedAt[actionType] = nil

	if startedAt then
		fireFootballAction(actionType, "Released", os.clock() - startedAt)
	end
end

local function handlePassGesture(value: any)
	if typeof(value) ~= "boolean" then
		return
	end
	local now = os.clock()
	if value then
		passSecondTap = now - lastPassReleaseAt <= FootballActionConfig.Input.DoubleTapWindow
		actionStartedAt.GroundPass = now
		if passSecondTap then
			passCommitToken += 1
			fireFootballAction("LobPass", "Pressed", 0)
		else
			fireFootballAction("GroundPass", "Pressed", 0)
		end
		return
	end
	local startedAt = actionStartedAt.GroundPass
	actionStartedAt.GroundPass = nil
	if not startedAt then return end
	local duration = now - startedAt
	if passSecondTap then
		passCommitToken += 1
		lastPassReleaseAt = -math.huge
		passSecondTap = false
		fireFootballAction("LobPass", "Released", duration)
		return
	end
	lastPassReleaseAt = now
	passCommitToken += 1
	local token = passCommitToken
	task.delay(FootballActionConfig.Input.SingleTapCommitDelay, function()
		if initialized and token == passCommitToken then
			lastPassReleaseAt = -math.huge
			fireFootballAction("GroundPass", "Released", duration)
		end
	end)
end

--[[
	An InputContext only delivers input while it is a descendant of the
	LocalPlayer. Parented anywhere else -- ReplicatedStorage in particular --
	every InputAction is created successfully and silently never fires, which
	looks exactly like broken WASD while setupInputActions() still reports
	success. PlayerScripts is client-only and dies with the player, so the
	context has the right lifetime as well as the right owner.
]]
local function createInputFolder(): Folder
	local parent: Instance = localPlayer:FindFirstChildOfClass("PlayerScripts")
		or localPlayer:WaitForChild("PlayerScripts", 5)
		or localPlayer

	local existing = parent:FindFirstChild(inputConfig.InputFolderName)

	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = inputConfig.InputFolderName
	folder.Parent = parent

	return folder
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
	local okJump, jump = pcall(function()
		return Instance.new("InputAction")
	end)
	local okCameraToggle, cameraToggle = pcall(function()
		return Instance.new("InputAction")
	end)
	local okPass, pass = pcall(function()
		return Instance.new("InputAction")
	end)
	local okThroughPass, throughPass = pcall(function()
		return Instance.new("InputAction")
	end)
	local okKnockOn, knockOn = pcall(function()
		return Instance.new("InputAction")
	end)
	local okShoot, shoot = pcall(function()
		return Instance.new("InputAction")
	end)
	local okTackle, tackle = pcall(function()
		return Instance.new("InputAction")
	end)
	local okCameraLock, cameraLock = pcall(function()
		return Instance.new("InputAction")
	end)

	if not okTackle or not okCameraLock then
		return false
	end

	if not okContext
		or not okMove
		or not okSprint
		or not okJump
		or not okCameraToggle
		or not okPass
		or not okThroughPass
		or not okKnockOn
		or not okShoot
	then
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
			moveStateChanges += 1
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
	addBinding(sprint, "GamepadRightTrigger", {
		KeyCode = Enum.KeyCode.ButtonR2,
	})

	table.insert(connections, sprint.StateChanged:Connect(function(value)
		if typeof(value) == "boolean" then
			setManualSprintRequested(value, "InputAction")
		end
	end))

	jump.Name = inputConfig.JumpActionName
	setProperty(jump, "Type", Enum.InputActionType.Bool)
	jump.Parent = context
	jumpAction = jump

	addBinding(jump, "KeyboardJump", {
		KeyCode = inputConfig.JumpKey,
	})
	addBinding(jump, "GamepadJump", {
		KeyCode = Enum.KeyCode.ButtonA,
	})

	table.insert(connections, jump.StateChanged:Connect(function(value)
		if value == true then
			jumpEvent:Fire()
		end
	end))

	cameraToggle.Name = inputConfig.CameraToggleActionName
	setProperty(cameraToggle, "Type", Enum.InputActionType.Bool)
	cameraToggle.Parent = context
	cameraToggleAction = cameraToggle

	addBinding(cameraToggle, "KeyboardC", {
		KeyCode = inputConfig.CameraToggleKey,
	})
	addBinding(cameraToggle, "GamepadSelect", {
		KeyCode = Enum.KeyCode.ButtonSelect,
	})

	table.insert(connections, cameraToggle.StateChanged:Connect(function(value)
		if value == true then
			cameraToggleEvent:Fire()
		end
	end))

	pass.Name = inputConfig.PassActionName
	setProperty(pass, "Type", Enum.InputActionType.Bool)
	pass.Parent = context
	passAction = pass

	addBinding(pass, "KeyboardPass", {
		KeyCode = inputConfig.PassKey,
	})
	addBinding(pass, "GamepadPass", {
		KeyCode = Enum.KeyCode.ButtonX,
	})

	table.insert(connections, pass.StateChanged:Connect(function(value)
		handlePassGesture(value)
	end))

	throughPass.Name = inputConfig.ThroughPassActionName
	setProperty(throughPass, "Type", Enum.InputActionType.Bool)
	throughPass.Parent = context
	throughPassAction = throughPass

	addBinding(throughPass, "KeyboardThroughPass", {
		KeyCode = inputConfig.ThroughPassKey,
	})
	addBinding(throughPass, "GamepadThroughPass", {
		KeyCode = Enum.KeyCode.ButtonY,
	})

	table.insert(connections, throughPass.StateChanged:Connect(function(value)
		handleBoolFootballAction("ThroughPass", value)
	end))

	knockOn.Name = inputConfig.KnockOnActionName
	setProperty(knockOn, "Type", Enum.InputActionType.Bool)
	knockOn.Parent = context
	knockOnAction = knockOn

	addBinding(knockOn, "KeyboardKnockOn", {
		KeyCode = inputConfig.KnockOnKey,
	})
	addBinding(knockOn, "GamepadKnockOn", {
		KeyCode = Enum.KeyCode.ButtonR1,
	})

	table.insert(connections, knockOn.StateChanged:Connect(function(value)
		handleBoolFootballAction("KnockOn", value)
	end))

	shoot.Name = inputConfig.ShootActionName
	setProperty(shoot, "Type", Enum.InputActionType.Bool)
	shoot.Parent = context
	shootAction = shoot

	addBinding(shoot, "KeyboardShoot", {
		KeyCode = inputConfig.ShootKey,
	})
	addBinding(shoot, "GamepadShoot", {
		KeyCode = Enum.KeyCode.ButtonB,
	})

	table.insert(connections, shoot.StateChanged:Connect(function(value)
		handleBoolFootballAction("Shoot", value)
	end))

	tackle.Name = inputConfig.TackleActionName
	setProperty(tackle, "Type", Enum.InputActionType.Bool)
	tackle.Parent = context
	tackleAction = tackle

	addBinding(tackle, "KeyboardTackle", {
		KeyCode = inputConfig.TackleKey,
	})
	addBinding(tackle, "GamepadTackle", {
		KeyCode = Enum.KeyCode.ButtonL1,
	})

	table.insert(connections, tackle.StateChanged:Connect(function(value)
		handleBoolFootballAction("Tackle", value)
	end))

	cameraLock.Name = "Beyond90CameraLock"
	setProperty(cameraLock, "Type", Enum.InputActionType.Bool)
	cameraLock.Parent = context

	addBinding(cameraLock, "KeyboardCameraLock", {
		KeyCode = inputConfig.CameraLockKey,
	})

	table.insert(connections, cameraLock.StateChanged:Connect(function(value)
		if value == true then
			cameraLockToggleEvent:Fire()
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
	if fallbackActive then
		return
	end
	fallbackActive = true
	inputState.Source = "UserInputService"

	table.insert(connections, UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
		if gameProcessed and UserInputService:GetFocusedTextBox() then
			return
		end

		pressedKeys[inputObject.KeyCode] = true

		if inputObject.KeyCode == Enum.KeyCode.LeftShift
			or inputObject.KeyCode == Enum.KeyCode.RightShift
			or inputObject.KeyCode == Enum.KeyCode.ButtonL3
			or inputObject.KeyCode == Enum.KeyCode.ButtonR2
		then
			setManualSprintRequested(true, "UserInputService")
		end

		if inputObject.KeyCode == inputConfig.CameraToggleKey or inputObject.KeyCode == Enum.KeyCode.ButtonSelect then
			cameraToggleEvent:Fire()
		end

		if inputObject.KeyCode == inputConfig.JumpKey or inputObject.KeyCode == Enum.KeyCode.ButtonA then
			jumpEvent:Fire()
		end

		if inputObject.KeyCode == inputConfig.PassKey or inputObject.KeyCode == Enum.KeyCode.ButtonX then
			handlePassGesture(true)
		elseif inputObject.KeyCode == inputConfig.ThroughPassKey or inputObject.KeyCode == Enum.KeyCode.ButtonY then
			actionStartedAt.ThroughPass = os.clock()
			fireFootballAction("ThroughPass", "Pressed", 0)
		elseif inputObject.KeyCode == inputConfig.KnockOnKey or inputObject.KeyCode == Enum.KeyCode.ButtonR1 then
			actionStartedAt.KnockOn = os.clock()
			fireFootballAction("KnockOn", "Pressed", 0)
		elseif inputObject.KeyCode == inputConfig.ShootKey or inputObject.KeyCode == Enum.KeyCode.ButtonB then
			actionStartedAt.Shoot = os.clock()
			fireFootballAction("Shoot", "Pressed", 0)
		elseif inputObject.KeyCode == inputConfig.TackleKey or inputObject.KeyCode == Enum.KeyCode.ButtonL1 then
			actionStartedAt.Tackle = os.clock()
			fireFootballAction("Tackle", "Pressed", 0)
		end

		if inputObject.KeyCode == inputConfig.CameraLockKey then
			cameraLockToggleEvent:Fire()
		end

		refreshFallbackMoveVector()
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(inputObject)
		pressedKeys[inputObject.KeyCode] = nil

		if inputObject.KeyCode == Enum.KeyCode.LeftShift
			or inputObject.KeyCode == Enum.KeyCode.RightShift
			or inputObject.KeyCode == Enum.KeyCode.ButtonL3
			or inputObject.KeyCode == Enum.KeyCode.ButtonR2
		then
			setManualSprintRequested(false, "UserInputService")
		end

		if inputObject.KeyCode == Enum.KeyCode.Thumbstick1 then
			fallbackThumbstick = Vector2.zero
		end

		if inputObject.KeyCode == inputConfig.TackleKey or inputObject.KeyCode == Enum.KeyCode.ButtonL1 then
			local tackleStartedAt = actionStartedAt.Tackle
			actionStartedAt.Tackle = nil
			if tackleStartedAt then
				fireFootballAction("Tackle", "Released", os.clock() - tackleStartedAt)
			end
		end

		if inputObject.KeyCode == inputConfig.PassKey or inputObject.KeyCode == Enum.KeyCode.ButtonX then
			handlePassGesture(false)
		elseif inputObject.KeyCode == inputConfig.ThroughPassKey or inputObject.KeyCode == Enum.KeyCode.ButtonY then
			local startedAt = actionStartedAt.ThroughPass
			actionStartedAt.ThroughPass = nil

			if startedAt then
				fireFootballAction("ThroughPass", "Released", os.clock() - startedAt)
			end
		elseif inputObject.KeyCode == inputConfig.KnockOnKey or inputObject.KeyCode == Enum.KeyCode.ButtonR1 then
			local startedAt = actionStartedAt.KnockOn
			actionStartedAt.KnockOn = nil

			if startedAt then
				fireFootballAction("KnockOn", "Released", os.clock() - startedAt)
			end
		elseif inputObject.KeyCode == inputConfig.ShootKey or inputObject.KeyCode == Enum.KeyCode.ButtonB then
			local startedAt = actionStartedAt.Shoot
			actionStartedAt.Shoot = nil

			if startedAt then
				fireFootballAction("Shoot", "Released", os.clock() - startedAt)
			end
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
	local direction, magnitude = getWorldMoveDirection(inputState.MoveVector)
	inputState.MoveDirection = direction
	inputState.MoveMagnitude = magnitude
	inputState.SprintRequested = manualSprintRequested
		or (autoSprintEnabled and magnitude >= inputConfig.AutoSprintThreshold)

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

function InputController.SetTouchMoveVector(moveVector: Vector2)
	if typeof(moveVector) ~= "Vector2" then
		return
	end
	setMoveVector(moveVector, "TouchHUD")
end

function InputController.SetTouchSprint(requested: boolean)
	if typeof(requested) ~= "boolean" then
		return
	end
	setManualSprintRequested(requested, "TouchHUD")
end

function InputController.SetTouchFootballAction(actionType: string, pressed: boolean)
	if typeof(actionType) ~= "string" or typeof(pressed) ~= "boolean" then
		return
	end
	if actionType == "GroundPass" then
		handlePassGesture(pressed)
	elseif actionType == "ThroughPass" or actionType == "KnockOn" or actionType == "Shoot" then
		handleBoolFootballAction(actionType, pressed)
	end
end

function InputController.ReleaseTouchInputs()
	setMoveVector(Vector2.zero, "TouchHUD")
	setManualSprintRequested(false, "TouchHUD")
	passCommitToken += 1
	lastPassReleaseAt = -math.huge
	passSecondTap = false
	actionStartedAt.GroundPass = nil
	actionStartedAt.ThroughPass = nil
	actionStartedAt.KnockOn = nil
	actionStartedAt.Shoot = nil
end

function InputController.GetCameraLockToggleEvent(): BindableEvent
	return cameraLockToggleEvent
end

function InputController.GetCameraToggleEvent(): BindableEvent
	return cameraToggleEvent
end

function InputController.GetJumpEvent(): BindableEvent
	return jumpEvent
end

function InputController.GetFootballActionEvent(): BindableEvent
	return footballActionEvent
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

--[[
	Silent-failure guard. Several conditions let the InputAction path construct
	successfully and still never deliver a value: a rejected Type enum, a binding
	property this engine version does not accept, a context detached later. Each
	is indistinguishable from dead WASD at the gameplay layer. If a movement key
	is genuinely held down and the action has still reported nothing, hand over
	to the UserInputService path once rather than leaving the player stuck.
]]
local function armInputActionWatchdog()
	local movementKeys = {
		[Enum.KeyCode.W] = true,
		[Enum.KeyCode.A] = true,
		[Enum.KeyCode.S] = true,
		[Enum.KeyCode.D] = true,
	}

	local watchdog
	watchdog = UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
		if gameProcessed or not movementKeys[inputObject.KeyCode] then
			return
		end

		task.delay(inputConfig.InputActionWatchdogSeconds, function()
			if fallbackActive or not initialized or not watchdog.Connected then
				return
			end
			-- Only conclusive while the key is still held.
			if not UserInputService:IsKeyDown(inputObject.KeyCode) then
				return
			end

			watchdog:Disconnect()

			if moveStateChanges > 0 then
				return
			end

			warnLog("InputAction reported no movement while a movement key was held; switching to UserInputService fallback")
			setupUserInputFallback()
		end)
	end)

	table.insert(connections, watchdog)
end

function InputController.Initialize()
	if initialized then
		return
	end

	initialized = true
	disableNativeClickToMove()
	pcall(function()
		local playerModuleScript = localPlayer.PlayerScripts:WaitForChild("PlayerModule", 2)
		if not playerModuleScript then
			return
		end
		local playerModule = require(playerModuleScript)
		nativeControls = playerModule:GetControls()
		nativeControls:Disable()
	end)

	if setupInputActions() and inputContext and inputContext:IsDescendantOf(localPlayer) then
		log("Input source: InputAction")
		armInputActionWatchdog()
	else
		if inputFolder then
			inputFolder:Destroy()
			inputFolder = nil
			inputContext = nil
			movementAction = nil
		end
		setupUserInputFallback()
		warnLog("InputAction path unavailable or not player-owned; using UserInputService fallback")
	end
end

function InputController.Destroy()
	if not initialized then
		return
	end

	initialized = false
	passCommitToken += 1
	lastPassReleaseAt = -math.huge
	passSecondTap = false
	if clickToMoveConnection then
		clickToMoveConnection:Disconnect()
		clickToMoveConnection = nil
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	table.clear(pressedKeys)
	table.clear(actionStartedAt)
	fallbackThumbstick = Vector2.zero
	setMoveVector(Vector2.zero, inputState.Source)
	setManualSprintRequested(false, inputState.Source)
	autoSprintEnabled = inputConfig.AutoSprintDefaultEnabled == true
	inputState.AutoSprintEnabled = autoSprintEnabled

	if inputContext then
		inputContext:Destroy()
		inputContext = nil
	end

	movementAction = nil
	sprintAction = nil
	jumpAction = nil
	cameraToggleAction = nil
	passAction = nil
	throughPassAction = nil
	knockOnAction = nil
	shootAction = nil
	inputFolder = nil
end

return InputController
