local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local MovementController = {}

local localPlayer = Players.LocalPlayer
local movementConfig = PlayerConfig.Movement
local locomotionConfig = PlayerConfig.Locomotion
local inputConfig = PlayerConfig.Input
local captureStepName = "Beyond90RawInputCapture"
local applyStepName = "Beyond90Locomotion"

local initialized = false
local currentHumanoid: Humanoid? = nil
local sprintRequested = false
local sprintRemote: RemoteEvent? = nil
local characterAddedConnection: RBXScriptConnection? = nil
local humanoidDiedConnection: RBXScriptConnection? = nil
local controls = nil
local inputSource = "Humanoid"
local locomotionBound = false

local locomotionState = {
	RawDirection = Vector3.zero,
	RawMagnitude = 0,
	SmoothedDirection = Vector3.zero,
	SmoothedSpeed = 0,
	SmoothedVelocity = Vector3.zero,
	TargetSpeed = 0,
	TurnAngle = 0,
	IsSprinting = false,
	IsMoving = false,
	IsValid = false,
	InputSource = inputSource,
}

local function warnLog(message: string)
	warn(string.format("%s[Client][Movement] %s", GameConfig.LogPrefix, message))
end

local function getTargetSpeed(): number
	if sprintRequested then
		return movementConfig.SprintSpeed
	end

	return movementConfig.BaseSpeed
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

local function applyMovementSettings(humanoid: Humanoid)
	humanoid.WalkSpeed = if locomotionBound then math.max(locomotionState.SmoothedSpeed, 0) else getTargetSpeed()
	humanoid.AutoRotate = movementConfig.AutoRotate
	humanoid.UseJumpPower = true
	humanoid.JumpPower = movementConfig.JumpPower
	humanoid.JumpHeight = movementConfig.JumpHeight
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, movementConfig.JumpEnabled)

	if not movementConfig.JumpEnabled then
		humanoid.Jump = false
	end
end

local function getCameraRelativeMoveDirection(moveVector: Vector3): (Vector3, number)
	local horizontalInput = Vector3.new(moveVector.X, 0, moveVector.Z)
	local rawMagnitude = math.clamp(horizontalInput.Magnitude, 0, 1)

	if rawMagnitude <= locomotionConfig.RawInputDeadzone then
		return Vector3.zero, 0
	end

	local camera = Workspace.CurrentCamera

	if not camera then
		return Vector3.zero, 0
	end

	local cameraForward = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(camera.CFrame.LookVector), getFacingDirection())
	local cameraRight = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(camera.CFrame.RightVector), Vector3.xAxis)
	local worldDirection = cameraRight * moveVector.X + cameraForward * -moveVector.Z

	return BallControlMath.SafeUnit(worldDirection, Vector3.zero), rawMagnitude
end

local function resolvePlayerControls()
	local playerScripts = localPlayer:FindFirstChild("PlayerScripts")

	if not playerScripts then
		warnLog("PlayerScripts was not found; smoothing from captured Humanoid.MoveDirection")
		return
	end

	local playerModule = playerScripts:FindFirstChild("PlayerModule")

	if not playerModule or not playerModule:IsA("ModuleScript") then
		warnLog("PlayerModule was not found; smoothing from captured Humanoid.MoveDirection")
		return
	end

	local ok, playerModuleApi = pcall(require, playerModule)

	if not ok or typeof(playerModuleApi) ~= "table" or typeof(playerModuleApi.GetControls) ~= "function" then
		warnLog("PlayerModule controls could not be resolved; smoothing from captured Humanoid.MoveDirection")
		return
	end

	controls = playerModuleApi:GetControls()
	inputSource = "PlayerModule"
	locomotionState.InputSource = inputSource
end

local function resetLocomotionState()
	locomotionState.RawDirection = Vector3.zero
	locomotionState.RawMagnitude = 0
	locomotionState.SmoothedDirection = Vector3.zero
	locomotionState.SmoothedSpeed = 0
	locomotionState.SmoothedVelocity = Vector3.zero
	locomotionState.TargetSpeed = 0
	locomotionState.TurnAngle = 0
	locomotionState.IsSprinting = false
	locomotionState.IsMoving = false
	locomotionState.IsValid = currentHumanoid ~= nil
	locomotionState.InputSource = inputSource
end

local function capturePlayerModuleInput(): (Vector3?, number?)
	if not controls then
		return nil
	end

	local ok, moveVector = pcall(function()
		return controls:GetMoveVector()
	end)

	if not ok or typeof(moveVector) ~= "Vector3" then
		return nil
	end

	local direction, magnitude = getCameraRelativeMoveDirection(moveVector)
	return direction, magnitude
end

local function captureHumanoidInput(humanoid: Humanoid): (Vector3, number)
	local moveDirection = BallControlMath.GetHorizontal(humanoid.MoveDirection)
	local rawMagnitude = math.clamp(moveDirection.Magnitude, 0, 1)

	if rawMagnitude <= locomotionConfig.RawInputDeadzone then
		return Vector3.zero, 0
	end

	return moveDirection.Unit, rawMagnitude
end

local function captureRawInput()
	local humanoid = currentHumanoid

	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local direction, magnitude = capturePlayerModuleInput()

	if not direction then
		direction, magnitude = captureHumanoidInput(humanoid)
		inputSource = "Humanoid"
	end

	locomotionState.RawDirection = direction
	locomotionState.RawMagnitude = magnitude
	locomotionState.IsValid = true
	locomotionState.InputSource = inputSource
end

local function getTurnSpeedFactor(currentVelocity: Vector3, targetDirection: Vector3): (number, number)
	if currentVelocity.Magnitude <= locomotionConfig.StopSpeed or targetDirection.Magnitude <= 0 then
		return 1, 0
	end

	local currentDirection = currentVelocity.Unit
	local dot = math.clamp(currentDirection:Dot(targetDirection), -1, 1)
	local turnAngle = math.deg(math.acos(dot))
	local severity = turnAngle / 180
	local loss

	if severity <= 0.5 then
		loss = (severity / 0.5) * locomotionConfig.TurnSpeedLossAt90
	else
		local alpha = (severity - 0.5) / 0.5
		loss = locomotionConfig.TurnSpeedLossAt90
			+ (locomotionConfig.TurnSpeedLossAt180 - locomotionConfig.TurnSpeedLossAt90) * alpha
	end

	return math.clamp(1 - loss, 0.25, 1), turnAngle
end

local function getVelocityChangeTime(currentVelocity: Vector3, targetVelocity: Vector3, turnAngle: number): number
	local currentSpeed = currentVelocity.Magnitude
	local targetSpeed = targetVelocity.Magnitude

	if targetSpeed <= locomotionConfig.StopSpeed then
		return if currentSpeed > movementConfig.BaseSpeed then locomotionConfig.SprintDecelerationTime else locomotionConfig.DecelerationTime
	end

	if currentSpeed <= locomotionConfig.StopSpeed then
		return if sprintRequested then locomotionConfig.SprintAccelerationTime else locomotionConfig.AccelerationTime
	end

	if turnAngle >= 135 then
		return locomotionConfig.ReverseAccelerationTime
	end

	if turnAngle >= 35 then
		return locomotionConfig.TurnAccelerationTime
	end

	if targetSpeed > currentSpeed then
		return if sprintRequested then locomotionConfig.SprintAccelerationTime else locomotionConfig.AccelerationTime
	end

	return if currentSpeed > movementConfig.BaseSpeed then locomotionConfig.SprintDecelerationTime else locomotionConfig.DecelerationTime
end

local function moveTowardVector(current: Vector3, target: Vector3, maxDelta: number): Vector3
	local delta = target - current

	if delta.Magnitude <= maxDelta then
		return target
	end

	return current + delta.Unit * maxDelta
end

local function updateLocomotion(deltaTime: number)
	local humanoid = currentHumanoid

	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local rawDirection = locomotionState.RawDirection
	local rawMagnitude = locomotionState.RawMagnitude
	local targetSpeed = getTargetSpeed() * rawMagnitude
	local turnFactor, turnAngle = getTurnSpeedFactor(locomotionState.SmoothedVelocity, rawDirection)
	local targetVelocity = rawDirection * targetSpeed * turnFactor
	local changeTime = getVelocityChangeTime(locomotionState.SmoothedVelocity, targetVelocity, turnAngle)
	local maxDelta = getTargetSpeed() / math.max(changeTime, 1 / 240) * deltaTime
	local nextVelocity = moveTowardVector(locomotionState.SmoothedVelocity, targetVelocity, maxDelta)
	local nextSpeed = nextVelocity.Magnitude

	if nextSpeed <= locomotionConfig.StopSpeed and rawMagnitude <= 0 then
		nextVelocity = Vector3.zero
		nextSpeed = 0
	end

	local shouldMove = nextSpeed > locomotionConfig.StopSpeed

	locomotionState.SmoothedVelocity = nextVelocity
	locomotionState.SmoothedDirection = if shouldMove then nextVelocity.Unit else Vector3.zero
	locomotionState.SmoothedSpeed = if shouldMove then nextSpeed else 0
	locomotionState.TargetSpeed = targetSpeed
	locomotionState.TurnAngle = turnAngle
	locomotionState.IsSprinting = sprintRequested
	locomotionState.IsMoving = shouldMove
	locomotionState.IsValid = true

	humanoid.WalkSpeed = locomotionState.SmoothedSpeed

	if shouldMove then
		humanoid:Move(locomotionState.SmoothedDirection, false)
	else
		humanoid:Move(Vector3.zero, false)
	end
end

local function bindLocomotion()
	if locomotionBound then
		return
	end

	locomotionBound = true
	RunService:BindToRenderStep(captureStepName, Enum.RenderPriority.Character.Value + 1, captureRawInput)
	RunService:BindToRenderStep(applyStepName, Enum.RenderPriority.Character.Value + 2, updateLocomotion)
end

local function sendSprintRequest(requested: boolean)
	if not sprintRemote then
		warnLog("Sprint remote is unavailable; local sprint prediction only")
		return
	end

	sprintRemote:FireServer(requested)
end

local function setSprintRequested(requested: boolean)
	if sprintRequested == requested then
		return
	end

	sprintRequested = requested

	if currentHumanoid and not locomotionBound then
		applyMovementSettings(currentHumanoid)
	end

	sendSprintRequest(requested)
end

local function onSprintAction(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		setSprintRequested(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprintRequested(false)
	end

	return Enum.ContextActionResult.Sink
end

local function configureCharacter(character: Model)
	sprintRequested = false
	resetLocomotionState()

	if humanoidDiedConnection then
		humanoidDiedConnection:Disconnect()
		humanoidDiedConnection = nil
	end

	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid or not humanoid:IsA("Humanoid") then
		warnLog("Character missing Humanoid; movement settings were not applied")
		currentHumanoid = nil
		return
	end

	currentHumanoid = humanoid
	locomotionState.IsValid = true
	applyMovementSettings(humanoid)
	sendSprintRequest(false)

	humanoidDiedConnection = humanoid.Died:Connect(function()
		setSprintRequested(false)
		resetLocomotionState()
	end)
end

local function bindSprintInput()
	ContextActionService:BindAction(
		inputConfig.SprintActionName,
		onSprintAction,
		true,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonL3
	)

	ContextActionService:SetTitle(inputConfig.SprintActionName, "Sprint")
	ContextActionService:SetPosition(inputConfig.SprintActionName, inputConfig.SprintTouchButtonPosition)
end

local function resolveSprintRemote()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)

	if not remotes then
		warnLog("ReplicatedStorage.Remotes was not found")
		return
	end

	local remote = remotes:WaitForChild(inputConfig.SprintRemoteName, 10)

	if not remote or not remote:IsA("RemoteEvent") then
		warnLog(string.format("%s remote was not found", inputConfig.SprintRemoteName))
		return
	end

	sprintRemote = remote
end

function MovementController.GetLocomotionState()
	return {
		RawDirection = locomotionState.RawDirection,
		RawMagnitude = locomotionState.RawMagnitude,
		SmoothedDirection = locomotionState.SmoothedDirection,
		SmoothedSpeed = locomotionState.SmoothedSpeed,
		SmoothedVelocity = locomotionState.SmoothedVelocity,
		TargetSpeed = locomotionState.TargetSpeed,
		TurnAngle = locomotionState.TurnAngle,
		IsSprinting = locomotionState.IsSprinting,
		IsMoving = locomotionState.IsMoving,
		IsValid = locomotionState.IsValid,
		InputSource = locomotionState.InputSource,
	}
end

function MovementController.Initialize()
	if initialized then
		return
	end

	initialized = true
	resolveSprintRemote()
	resolvePlayerControls()
	bindSprintInput()
	bindLocomotion()
	warnLog(string.format("Locomotion smoothing input source: %s", inputSource))

	characterAddedConnection = localPlayer.CharacterAdded:Connect(configureCharacter)

	if localPlayer.Character then
		configureCharacter(localPlayer.Character)
	end
end

function MovementController.Destroy()
	if not initialized then
		return
	end

	initialized = false
	ContextActionService:UnbindAction(inputConfig.SprintActionName)

	if locomotionBound then
		RunService:UnbindFromRenderStep(captureStepName)
		RunService:UnbindFromRenderStep(applyStepName)
		locomotionBound = false
	end

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end

	if humanoidDiedConnection then
		humanoidDiedConnection:Disconnect()
		humanoidDiedConnection = nil
	end

	currentHumanoid = nil
	sprintRequested = false
	resetLocomotionState()
end

return MovementController
