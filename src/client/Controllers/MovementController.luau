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
local renderStepName = "Beyond90Locomotion"

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
	TargetSpeed = 0,
	IsSprinting = false,
	IsMoving = false,
	IsValid = false,
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
	local playerScripts = localPlayer:WaitForChild("PlayerScripts", 10)

	if not playerScripts then
		warnLog("PlayerScripts was not found; smoothing from Humanoid.MoveDirection")
		return
	end

	local playerModule = playerScripts:WaitForChild("PlayerModule", 10)

	if not playerModule or not playerModule:IsA("ModuleScript") then
		warnLog("PlayerModule was not found; smoothing from Humanoid.MoveDirection")
		return
	end

	local ok, playerModuleApi = pcall(require, playerModule)

	if not ok or typeof(playerModuleApi) ~= "table" or typeof(playerModuleApi.GetControls) ~= "function" then
		warnLog("PlayerModule controls could not be resolved; smoothing from Humanoid.MoveDirection")
		return
	end

	controls = playerModuleApi:GetControls()
	inputSource = "PlayerModule"
end

local function resetLocomotionState()
	locomotionState.RawDirection = Vector3.zero
	locomotionState.RawMagnitude = 0
	locomotionState.SmoothedDirection = Vector3.zero
	locomotionState.SmoothedSpeed = 0
	locomotionState.TargetSpeed = 0
	locomotionState.IsSprinting = false
	locomotionState.IsMoving = false
	locomotionState.IsValid = currentHumanoid ~= nil
end

local function getAccelerationTime(targetSpeed: number): number
	if targetSpeed > movementConfig.BaseSpeed then
		return locomotionConfig.SprintAccelerationTime
	end

	return locomotionConfig.AccelerationTime
end

local function getDecelerationTime(currentSpeed: number): number
	if currentSpeed > movementConfig.BaseSpeed then
		return locomotionConfig.SprintDecelerationTime
	end

	return locomotionConfig.DecelerationTime
end

local function updateDirection(rawDirection: Vector3, rawMagnitude: number, deltaTime: number): Vector3
	local currentDirection = locomotionState.SmoothedDirection

	if currentDirection.Magnitude <= 0.001 then
		currentDirection = if rawMagnitude > 0 then rawDirection else getFacingDirection()
	end

	if rawMagnitude <= 0 then
		return currentDirection
	end

	local dot = math.clamp(currentDirection:Dot(rawDirection), -1, 1)
	local turnSeverity = math.acos(dot) / math.pi
	local turnRate = if sprintRequested then locomotionConfig.SprintTurnRate else locomotionConfig.WalkTurnRate
	local responsiveness = turnRate * (1 - turnSeverity * locomotionConfig.HighSpeedTurnSlowdown)
	local alpha = math.clamp(responsiveness * deltaTime, 0, 1)
	local blended = currentDirection:Lerp(rawDirection, alpha)

	return BallControlMath.SafeUnit(blended, rawDirection)
end

local function updateSpeed(rawDirection: Vector3, rawMagnitude: number, nextDirection: Vector3, deltaTime: number): number
	local targetSpeed = getTargetSpeed() * rawMagnitude

	if rawMagnitude > 0 and locomotionState.SmoothedDirection.Magnitude > 0 then
		local dot = math.clamp(locomotionState.SmoothedDirection:Dot(rawDirection), -1, 1)
		local turnSeverity = math.acos(dot) / math.pi
		local turnSpeedFactor = math.clamp(1 - turnSeverity * locomotionConfig.TurnSpeedLoss, 0.25, 1)

		if dot < locomotionConfig.ReverseDot then
			turnSpeedFactor = math.min(turnSpeedFactor, locomotionConfig.ReverseBrakeFactor)
		end

		targetSpeed *= turnSpeedFactor
	end

	local currentSpeed = locomotionState.SmoothedSpeed
	local changeTime = if targetSpeed > currentSpeed
		then getAccelerationTime(targetSpeed)
		else getDecelerationTime(currentSpeed)
	local maxDelta = getTargetSpeed() / math.max(changeTime, 1 / 240) * deltaTime
	local speedDelta = math.clamp(targetSpeed - currentSpeed, -maxDelta, maxDelta)
	local nextSpeed = currentSpeed + speedDelta

	if nextSpeed <= locomotionConfig.StopSpeed and rawMagnitude <= 0 then
		nextSpeed = 0
	end

	locomotionState.TargetSpeed = targetSpeed
	return nextSpeed
end

local function getRawMovement(humanoid: Humanoid): (Vector3, number)
	if controls then
		local ok, moveVector = pcall(function()
			return controls:GetMoveVector()
		end)

		if ok and typeof(moveVector) == "Vector3" then
			return getCameraRelativeMoveDirection(moveVector)
		end
	end

	local moveDirection = BallControlMath.GetHorizontal(humanoid.MoveDirection)
	local rawMagnitude = math.clamp(moveDirection.Magnitude, 0, 1)

	if rawMagnitude <= locomotionConfig.RawInputDeadzone then
		return Vector3.zero, 0
	end

	return moveDirection.Unit, rawMagnitude
end

local function updateLocomotion(deltaTime: number)
	local humanoid = currentHumanoid

	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local rawDirection, rawMagnitude = getRawMovement(humanoid)
	local nextDirection = updateDirection(rawDirection, rawMagnitude, deltaTime)
	local nextSpeed = updateSpeed(rawDirection, rawMagnitude, nextDirection, deltaTime)
	local shouldMove = nextSpeed > locomotionConfig.StopSpeed and nextDirection.Magnitude > 0

	locomotionState.RawDirection = rawDirection
	locomotionState.RawMagnitude = rawMagnitude
	locomotionState.SmoothedDirection = if shouldMove then nextDirection else Vector3.zero
	locomotionState.SmoothedSpeed = if shouldMove then nextSpeed else 0
	locomotionState.IsSprinting = sprintRequested
	locomotionState.IsMoving = shouldMove
	locomotionState.IsValid = true

	humanoid.WalkSpeed = locomotionState.SmoothedSpeed

	if shouldMove then
		humanoid:Move(nextDirection, false)
	else
		humanoid:Move(Vector3.zero, false)
	end
end

local function bindLocomotion()
	if locomotionBound then
		return
	end

	locomotionBound = true
	RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Character.Value + 2, updateLocomotion)
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
		TargetSpeed = locomotionState.TargetSpeed,
		IsSprinting = locomotionState.IsSprinting,
		IsMoving = locomotionState.IsMoving,
		IsValid = locomotionState.IsValid,
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
		RunService:UnbindFromRenderStep(renderStepName)
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
