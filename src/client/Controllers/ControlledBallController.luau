local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local GameConfig = require(Shared.Config.GameConfig)
local MovementController = require(script.Parent:WaitForChild("MovementController"))
local PlayerConfig = require(Shared.Config.PlayerConfig)

local ControlledBallController = {}

local localPlayer = Players.LocalPlayer
local controlConfig = BallConfig.Control
local ownershipConfig = BallConfig.Ownership
local movementConfig = PlayerConfig.Movement

local initialized = false
local physicsConnection: RBXScriptConnection? = nil
local cachedBall: BasePart? = nil
local controlDirection: Vector3? = nil
local controlMode = "Carry"
local captureStartedAt = 0
local lastTouchEventTime = 0
local touchEventCount = 0
local lastDiagnosticTime = 0

local function log(message: string)
	print(string.format("%s[Client][ControlledBall] %s", GameConfig.LogPrefix, message))
end

local function isPlayerOwnedMode(): boolean
	return ownershipConfig.ControlledBallOwnershipMode == "Player"
end

local function getFootball(): BasePart?
	if cachedBall and cachedBall.Parent then
		return cachedBall
	end

	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = rootFolder and rootFolder:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)

	if ball and ball:IsA("BasePart") then
		cachedBall = ball
		return ball
	end

	cachedBall = nil
	return nil
end

local function getRootAndHumanoid(): (BasePart?, Humanoid?)
	local character = localPlayer.Character

	if not character then
		return nil, nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end

	return rootPart, humanoid
end

local function getFacingDirection(rootPart: BasePart): Vector3
	return BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
		Vector3.new(0, 0, -1)
	)
end

local function isLocalController(ball: BasePart): boolean
	return ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
end

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector(vector: Vector3): boolean
	return isFiniteNumber(vector.X) and isFiniteNumber(vector.Y) and isFiniteNumber(vector.Z)
end

local function applyVelocityDelta(ball: BasePart, deltaVelocity: Vector3): boolean
	if not isFiniteVector(deltaVelocity) or deltaVelocity.Magnitude <= 0 then
		return false
	end

	ball:ApplyImpulse(deltaVelocity * ball.AssemblyMass)
	return true
end

local function getMinimumControlDistance(): number
	return controlConfig.BodyExclusionRadius + BallConfig.Radius + controlConfig.BodyClearance
end

local function getLocomotionDirection(rootPart: BasePart, locomotionState): Vector3
	if locomotionState.IsValid and locomotionState.SmoothedDirection.Magnitude > 0 then
		return locomotionState.SmoothedDirection.Unit
	end

	if locomotionState.RawDirection.Magnitude > 0 then
		return locomotionState.RawDirection.Unit
	end

	return controlDirection or getFacingDirection(rootPart)
end

local function updateControlDirection(targetDirection: Vector3, deltaTime: number): Vector3
	local currentDirection = controlDirection or targetDirection
	local turnRate = if controlMode == "Capture" then controlConfig.CaptureDirectionTurnRate else controlConfig.ControlDirectionTurnRate
	local alpha = math.clamp(turnRate * deltaTime, 0, 1)
	local nextDirection = BallControlMath.SafeUnit(currentDirection:Lerp(targetDirection, alpha), targetDirection)

	controlDirection = nextDirection
	return nextDirection
end

local function getLeadDistance(locomotionState): number
	local minDistance = getMinimumControlDistance()

	if not locomotionState.IsMoving or locomotionState.SmoothedSpeed <= controlConfig.StationaryPlayerSpeed then
		return math.max(controlConfig.StationaryCarryLeadDistance, minDistance)
	end

	local speedAlpha = math.clamp(locomotionState.SmoothedSpeed / math.max(movementConfig.SprintSpeed, 1), 0, 1)
	local lead = controlConfig.CarryLeadDistance
		+ (controlConfig.SprintCarryLeadDistance - controlConfig.CarryLeadDistance) * speedAlpha

	if controlMode == "Capture" then
		lead *= controlConfig.CaptureLeadScale
	end

	return math.max(lead, minDistance)
end

local function getTargetPosition(rootPart: BasePart, direction: Vector3, leadDistance: number): Vector3
	local horizontalRootPosition = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
	local horizontalTarget = horizontalRootPosition + direction * leadDistance
	return Vector3.new(horizontalTarget.X, rootPart.Position.Y, horizontalTarget.Z)
end

local function getModeTriggers(
	ball: BasePart,
	rootPart: BasePart,
	locomotionState,
	direction: Vector3
)
	local horizontalFromPlayer = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
	local ballLead = horizontalFromPlayer:Dot(direction)
	local distance = horizontalFromPlayer.Magnitude
	local minDistance = getMinimumControlDistance()
	local ballHorizontalVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	local playerDesiredVelocity = direction * locomotionState.SmoothedSpeed
	local relativeSpeed = (ballHorizontalVelocity - playerDesiredVelocity).Magnitude
	local turnDot = if locomotionState.RawDirection.Magnitude > 0 and controlDirection
		then math.clamp((controlDirection :: Vector3):Dot(locomotionState.RawDirection.Unit), -1, 1)
		else 1
	local turnAngleDegrees = math.deg(math.acos(turnDot))
	local releasedMovement = locomotionState.RawMagnitude <= 0 and locomotionState.SmoothedSpeed > controlConfig.StationaryPlayerSpeed
	local sharpTurn = turnAngleDegrees >= controlConfig.CaptureTurnAngleDegrees
	local behind = ballLead < controlConfig.CaptureBehindLead
	local bodyOverlap = distance < minDistance

	return {
		BallLead = ballLead,
		Distance = distance,
		RelativeSpeed = relativeSpeed,
		TurnAngleDegrees = turnAngleDegrees,
		ReleasedMovement = releasedMovement,
		SharpTurn = sharpTurn,
		Behind = behind,
		BodyOverlap = bodyOverlap,
	}
end

local function updateControlMode(triggers, targetErrorMagnitude: number)
	local now = os.clock()
	local shouldCapture = triggers.ReleasedMovement
		or triggers.SharpTurn
		or triggers.Behind
		or triggers.BodyOverlap

	if shouldCapture and controlMode ~= "Capture" then
		controlMode = "Capture"
		captureStartedAt = now
	elseif controlMode == "Capture" then
		local captureDuration = now - captureStartedAt
		local canExit = captureDuration >= controlConfig.CaptureMinDuration
			and targetErrorMagnitude <= controlConfig.CaptureExitError
			and triggers.RelativeSpeed <= controlConfig.CaptureExitRelativeSpeed

		if canExit or captureDuration >= controlConfig.CaptureMaxDuration then
			controlMode = "Carry"
		end
	end
end

local function applyBodyExclusion(ball: BasePart, rootPart: BasePart, direction: Vector3): Vector3
	local horizontalFromPlayer = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
	local distance = horizontalFromPlayer.Magnitude
	local minDistance = getMinimumControlDistance()

	if distance >= minDistance then
		return Vector3.zero
	end

	local outward = BallControlMath.SafeUnit(horizontalFromPlayer, direction)
	local overlap = minDistance - distance

	if distance <= controlConfig.DeepOverlapRescueDistance then
		local rescuedHorizontal = BallControlMath.GetHorizontal(rootPart.Position) + outward * minDistance
		ball.CFrame = CFrame.new(Vector3.new(rescuedHorizontal.X, ball.Position.Y, rescuedHorizontal.Z))
	end

	return outward * overlap * controlConfig.BodyExclusionGain
end

local function recordLogicalTouchEvent(ball: BasePart, targetErrorMagnitude: number)
	local now = os.clock()

	if now - lastTouchEventTime < controlConfig.ServoTouchEventInterval then
		return
	end

	if targetErrorMagnitude > controlConfig.ServoTouchEventError then
		return
	end

	lastTouchEventTime = now
	touchEventCount += 1
	ball:SetAttribute("LastLocalControlTouchTime", now)
	ball:SetAttribute("LastLocalControlTouchCount", touchEventCount)
end

local function sampleDiagnostics(ball: BasePart, rootPart: BasePart, direction: Vector3, locomotionState, relativeSpeed: number)
	local now = os.clock()

	if now - lastDiagnosticTime < controlConfig.LeadDiagnosticInterval then
		return
	end

	lastDiagnosticTime = now
	local lead = BallControlMath.GetHorizontal(ball.Position - rootPart.Position):Dot(direction)
	ball:SetAttribute("ClientBallLead", lead)
	ball:SetAttribute("ControlMode", controlMode)
	ball:SetAttribute("SmoothedPlayerSpeed", locomotionState.SmoothedSpeed)
	ball:SetAttribute("BallRelativeSpeed", relativeSpeed)

	local serverLead = ball:GetAttribute("ServerBallLead")
	log(string.format(
		"Lead sample realClient=%.2f server=%s mode=%s playerSpeed=%.2f relativeSpeed=%.2f",
		lead,
		if typeof(serverLead) == "number" then string.format("%.2f", serverLead) else "n/a",
		controlMode,
		locomotionState.SmoothedSpeed,
		relativeSpeed
	))
end

local function applyPossessionServo(ball: BasePart, rootPart: BasePart, locomotionState, deltaTime: number)
	local targetDirection = getLocomotionDirection(rootPart, locomotionState)
	local direction = updateControlDirection(targetDirection, deltaTime)
	local leadDistance = getLeadDistance(locomotionState)
	local targetPosition = getTargetPosition(rootPart, direction, leadDistance)
	local targetError = BallControlMath.GetHorizontal(targetPosition - ball.Position)
	local triggers = getModeTriggers(ball, rootPart, locomotionState, direction)

	updateControlMode(triggers, targetError.Magnitude)

	local positionGain = if controlMode == "Capture" then controlConfig.CapturePositionGain else controlConfig.CarryPositionGain
	local velocityDamping = if controlMode == "Capture" then controlConfig.CaptureVelocityDamping else controlConfig.CarryVelocityDamping
	local playerDesiredVelocity = if locomotionState.IsMoving
		then direction * locomotionState.SmoothedSpeed
		else Vector3.zero
	local ballHorizontalVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	local relativeVelocity = ballHorizontalVelocity - playerDesiredVelocity
	local correctionVelocity = targetError * positionGain - relativeVelocity * velocityDamping
	local exclusionVelocity = applyBodyExclusion(ball, rootPart, direction)
	local desiredHorizontalVelocity = playerDesiredVelocity + correctionVelocity + exclusionVelocity
	desiredHorizontalVelocity = BallControlMath.ClampMagnitude(
		desiredHorizontalVelocity,
		controlConfig.MaxControlledCorrectionSpeed
	)

	local horizontalDelta = desiredHorizontalVelocity - ballHorizontalVelocity
	local maxDelta = controlConfig.MaxControlledDeltaSpeedPerSecond * deltaTime

	if controlMode == "Capture" then
		maxDelta *= controlConfig.CaptureDeltaSpeedMultiplier
	end

	horizontalDelta = BallControlMath.ClampMagnitude(horizontalDelta, maxDelta)
	applyVelocityDelta(ball, Vector3.new(horizontalDelta.X, 0, horizontalDelta.Z))
	recordLogicalTouchEvent(ball, targetError.Magnitude)
	sampleDiagnostics(ball, rootPart, direction, locomotionState, relativeVelocity.Magnitude)
end

local function resetLocalState()
	controlDirection = nil
	controlMode = "Carry"
	captureStartedAt = 0
	lastTouchEventTime = 0
	touchEventCount = 0
end

local function updateControlledBall(deltaTime: number)
	if not isPlayerOwnedMode() then
		return
	end

	local ball = getFootball()

	if not ball or not isLocalController(ball) then
		resetLocalState()
		return
	end

	local rootPart, humanoid = getRootAndHumanoid()

	if not rootPart or not humanoid then
		resetLocalState()
		return
	end

	local locomotionState = MovementController.GetLocomotionState()

	if not locomotionState.IsValid then
		locomotionState.SmoothedDirection = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(humanoid.MoveDirection),
			getFacingDirection(rootPart)
		)
		locomotionState.SmoothedSpeed = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity).Magnitude
		locomotionState.RawDirection = locomotionState.SmoothedDirection
		locomotionState.RawMagnitude = if locomotionState.SmoothedSpeed > controlConfig.StationaryPlayerSpeed then 1 else 0
		locomotionState.IsMoving = locomotionState.SmoothedSpeed > controlConfig.StationaryPlayerSpeed
		locomotionState.IsSprinting = humanoid:GetAttribute("SprintRequested") == true
	end

	applyPossessionServo(ball, rootPart, locomotionState, math.max(deltaTime, 1 / 240))
end

function ControlledBallController.Initialize()
	if initialized then
		return
	end

	initialized = true
	physicsConnection = RunService.PreSimulation:Connect(updateControlledBall)
end

function ControlledBallController.Destroy()
	if not initialized then
		return
	end

	initialized = false

	if physicsConnection then
		physicsConnection:Disconnect()
		physicsConnection = nil
	end

	resetLocalState()
end

return ControlledBallController
