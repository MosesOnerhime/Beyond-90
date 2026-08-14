local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local InputController = require(script.Parent:WaitForChild("InputController"))

local MovementController = {}

local localPlayer = Players.LocalPlayer
local movementConfig = PlayerConfig.Movement
local locomotionConfig = PlayerConfig.Locomotion
local inputConfig = PlayerConfig.Input
local applyStepName = "Beyond90Locomotion"

local initialized = false
local currentHumanoid: Humanoid? = nil
local sprintRequested = false
local sprintRemote: RemoteEvent? = nil
local characterAddedConnection: RBXScriptConnection? = nil
local humanoidDiedConnection: RBXScriptConnection? = nil
local inputSource = "InputAction"
local locomotionBound = false
local lastDiagnosticTime = 0
local setSprintRequested: ((boolean) -> ())? = nil

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

local function log(message: string)
	print(string.format("%s[Client][Movement] %s", GameConfig.LogPrefix, message))
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

local function sampleDiagnostics()
	local now = os.clock()

	if now - lastDiagnosticTime < locomotionConfig.DiagnosticInterval then
		return
	end

	lastDiagnosticTime = now
	localPlayer:SetAttribute("Beyond90RawMoveMagnitude", locomotionState.RawMagnitude)
	localPlayer:SetAttribute("Beyond90SmoothedPlayerSpeed", locomotionState.SmoothedSpeed)
	localPlayer:SetAttribute("Beyond90TurnAngle", locomotionState.TurnAngle)
	localPlayer:SetAttribute("Beyond90InputSource", locomotionState.InputSource)
	localPlayer:SetAttribute("Beyond90SprintRequested", sprintRequested)
end

local function updateLocomotion(deltaTime: number)
	local humanoid = currentHumanoid

	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local rawInput = InputController.GetInputState()
	inputSource = rawInput.Source

	if rawInput.SprintRequested ~= sprintRequested then
		setSprintRequested(rawInput.SprintRequested)
	end

	local rawDirection = rawInput.MoveDirection
	local rawMagnitude = rawInput.MoveMagnitude
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

	locomotionState.RawDirection = rawDirection
	locomotionState.RawMagnitude = rawMagnitude
	locomotionState.SmoothedVelocity = nextVelocity
	locomotionState.SmoothedDirection = if shouldMove then nextVelocity.Unit else Vector3.zero
	locomotionState.SmoothedSpeed = if shouldMove then nextSpeed else 0
	locomotionState.TargetSpeed = targetSpeed
	locomotionState.TurnAngle = turnAngle
	locomotionState.IsSprinting = sprintRequested
	locomotionState.IsMoving = shouldMove
	locomotionState.IsValid = true
	locomotionState.InputSource = inputSource

	humanoid.WalkSpeed = locomotionState.SmoothedSpeed

	if shouldMove then
		humanoid:Move(locomotionState.SmoothedDirection, false)
	else
		humanoid:Move(Vector3.zero, false)
	end

	sampleDiagnostics()
end

local function bindLocomotion()
	if locomotionBound then
		return
	end

	locomotionBound = true
	RunService:BindToRenderStep(applyStepName, Enum.RenderPriority.Character.Value + 2, updateLocomotion)
end

local function sendSprintRequest(requested: boolean)
	if not sprintRemote then
		warnLog("Sprint remote is unavailable; local sprint prediction only")
		return
	end

	sprintRemote:FireServer(requested)
end

setSprintRequested = function(requested: boolean)
	if sprintRequested == requested then
		return
	end

	sprintRequested = requested

	if currentHumanoid and not locomotionBound then
		applyMovementSettings(currentHumanoid)
	end

	sendSprintRequest(requested)
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
	bindLocomotion()
	log(string.format("Locomotion smoothing input source: %s", inputSource))

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

	if locomotionBound then
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
