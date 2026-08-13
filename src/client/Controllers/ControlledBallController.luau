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
local ballIntentDirection: Vector3? = nil
local controlMode = "Carry"
local captureStartedAt = 0
local lastCaptureExitAt = 0
local lastTouchEventTime = 0
local touchEventCount = 0
local lastDiagnosticTime = 0
local lastTouchSide = 1
local touchAirborneUntil = 0
local touchPulseCancelled = false
local touchDirection: Vector3? = nil
local cutbackSide = 0
local cutbackUntil = 0
local dribbleTouchEvent = Instance.new("BindableEvent")

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

local function getBallIntentTargetDirection(rootPart: BasePart, locomotionState): Vector3
	if locomotionState.RawMagnitude > 0 and locomotionState.RawDirection.Magnitude > 0 then
		return locomotionState.RawDirection.Unit
	end

	return getLocomotionDirection(rootPart, locomotionState)
end

local function updateBallIntentDirection(rootPart: BasePart, locomotionState, deltaTime: number): Vector3
	local targetDirection = getBallIntentTargetDirection(rootPart, locomotionState)
	local currentDirection = ballIntentDirection or controlDirection or targetDirection
	local dot = math.clamp(currentDirection:Dot(targetDirection), -1, 1)
	local turnAngle = math.deg(math.acos(dot))
	local turnRate = if turnAngle >= controlConfig.CaptureTurnAngleDegrees
		then controlConfig.BallIntentSharpTurnRate
		else controlConfig.BallIntentTurnRate

	if controlMode == "Capture" then
		turnRate = math.max(turnRate, controlConfig.CaptureDirectionTurnRate)
	end

	local alpha = math.clamp(turnRate * deltaTime, 0, 1)
	local nextDirection = BallControlMath.SafeUnit(currentDirection:Lerp(targetDirection, alpha), targetDirection)

	ballIntentDirection = nextDirection
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

local function getTouchInterval(locomotionState): number
	if locomotionState.IsSprinting then
		return controlConfig.SprintTouchInterval
	end

	return controlConfig.WalkTouchInterval
end

local function getTouchSpeedPulse(locomotionState): number
	if locomotionState.IsSprinting then
		return controlConfig.SprintTouchSpeedPulse
	end

	return controlConfig.WalkTouchSpeedPulse
end

local function getTouchHopHeight(locomotionState): number
	if locomotionState.IsSprinting then
		return controlConfig.SprintTouchHopHeight
	end

	return controlConfig.WalkTouchHopHeight
end

local function getTouchUpwardVelocity(locomotionState): number
	local hopHeight = getTouchHopHeight(locomotionState)

	if hopHeight <= 0 then
		return 0
	end

	return math.min(math.sqrt(2 * Workspace.Gravity * hopHeight), controlConfig.MaxTouchUpwardVelocity)
end

local function getTouchLeadPulse(locomotionState): number
	if locomotionState.IsSprinting then
		return controlConfig.SprintTouchLeadPulse
	end

	return controlConfig.WalkTouchLeadPulse
end

local function getTouchElapsed(): number
	return os.clock() - lastTouchEventTime
end

local function getTouchPulse(locomotionState): number
	if touchPulseCancelled or controlMode == "Capture" or locomotionState.RawMagnitude <= 0 or not locomotionState.IsMoving then
		return 0
	end

	local elapsed = getTouchElapsed()

	if elapsed < 0 or elapsed > controlConfig.TouchPulseDuration then
		return 0
	end

	return 1 - elapsed / controlConfig.TouchPulseDuration
end

local function getDribblePhase(locomotionState): string
	if controlMode == "Capture" then
		return "Collect"
	end

	if locomotionState.RawMagnitude <= 0 or not locomotionState.IsMoving then
		return "Settle"
	end

	if getTouchPulse(locomotionState) > 0 then
		return "Push"
	end

	local elapsed = getTouchElapsed()

	if elapsed > controlConfig.TouchPulseDuration
		and elapsed <= controlConfig.TouchPulseDuration + controlConfig.TouchCoastDuration
	then
		return "Coast"
	end

	return "Collect"
end

local function updateTouchCancellation(locomotionState)
	if lastTouchEventTime <= 0 or touchPulseCancelled then
		return
	end

	if locomotionState.RawMagnitude <= 0 then
		touchPulseCancelled = true
		touchAirborneUntil = 0
		return
	end

	if not touchDirection or locomotionState.RawDirection.Magnitude <= 0 then
		return
	end

	local dot = math.clamp((touchDirection :: Vector3):Dot(locomotionState.RawDirection.Unit), -1, 1)
	local turnAngle = math.deg(math.acos(dot))

	if turnAngle >= controlConfig.CancelPushTurnAngleDegrees then
		touchPulseCancelled = true
		touchAirborneUntil = 0
	end
end

local function beginTouchPulse(ball: BasePart, locomotionState, direction: Vector3)
	local now = os.clock()

	if controlMode == "Capture" or locomotionState.RawMagnitude <= 0 or not locomotionState.IsMoving then
		return
	end

	if now - lastTouchEventTime < getTouchInterval(locomotionState) then
		return
	end

	lastTouchEventTime = now
	touchPulseCancelled = false
	touchDirection = direction
	touchAirborneUntil = now + controlConfig.TouchAirborneWindow
	touchEventCount += 1
	lastTouchSide *= -1
	ball:SetAttribute("LastLocalControlTouchTime", now)
	ball:SetAttribute("LastLocalControlTouchCount", touchEventCount)
	ball:SetAttribute("LastLocalDribbleFootSide", if lastTouchSide > 0 then "Right" else "Left")
	ball:SetAttribute("LastLocalDribbleTouchStrength", if locomotionState.IsSprinting then "Sprint" else "Walk")

	local upwardVelocity = getTouchUpwardVelocity(locomotionState)

	if upwardVelocity > 0 then
		local verticalDelta = math.max(upwardVelocity - ball.AssemblyLinearVelocity.Y, 0)
		applyVelocityDelta(ball, Vector3.new(0, verticalDelta, 0))
	end

	local horizontalSpeed = math.max(BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity).Magnitude, 0.1)
	local lateralDirection = Vector3.new(-direction.Z, 0, direction.X)
	local spinAxis = lateralDirection * -lastTouchSide + direction * 0.2
	local angularVelocity = BallControlMath.ClampMagnitude(
		spinAxis * horizontalSpeed * controlConfig.TouchAngularVelocityGain,
		controlConfig.MaxTouchAngularVelocity
	)
	ball.AssemblyAngularVelocity = Vector3.new(angularVelocity.X, ball.AssemblyAngularVelocity.Y, angularVelocity.Z)
	dribbleTouchEvent:Fire({
		FootSide = if lastTouchSide > 0 then "Right" else "Left",
		TouchStrength = if locomotionState.IsSprinting then "Sprint" else "Walk",
		TouchPhase = "Push",
		IsSprinting = locomotionState.IsSprinting,
	})
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
	local lateralDirection = Vector3.new(-direction.Z, 0, direction.X)
	local ballLateral = horizontalFromPlayer:Dot(lateralDirection)
	local turnDot = if locomotionState.RawDirection.Magnitude > 0 and controlDirection
		then math.clamp((controlDirection :: Vector3):Dot(locomotionState.RawDirection.Unit), -1, 1)
		else 1
	local turnAngleDegrees = math.deg(math.acos(turnDot))
	local releasedMovement = locomotionState.RawMagnitude <= 0 and locomotionState.SmoothedSpeed > controlConfig.StationaryPlayerSpeed
	local sharpTurn = turnAngleDegrees >= controlConfig.CaptureTurnAngleDegrees
	local behind = ballLead < controlConfig.CaptureBehindLead
	local bodyOverlap = distance < minDistance
	local intentionalPush = getTouchPulse(locomotionState) > 0 or os.clock() < touchAirborneUntil

	return {
		BallLead = ballLead,
		Distance = distance,
		RelativeSpeed = relativeSpeed,
		TurnAngleDegrees = turnAngleDegrees,
		ReleasedMovement = releasedMovement,
		SharpTurn = sharpTurn,
		Behind = behind,
		BodyOverlap = bodyOverlap,
		IntentionalPush = intentionalPush,
		BallLateral = ballLateral,
	}
end

local function updateControlMode(triggers, targetErrorMagnitude: number)
	local now = os.clock()
	local shouldCapture = triggers.ReleasedMovement
		or triggers.SharpTurn
		or (triggers.Behind and not triggers.IntentionalPush)
		or triggers.BodyOverlap

	if shouldCapture
		and controlMode ~= "Capture"
		and now - lastCaptureExitAt >= controlConfig.CaptureReentryCooldown
	then
		controlMode = "Capture"
		captureStartedAt = now
		touchPulseCancelled = true

		if triggers.TurnAngleDegrees >= controlConfig.CutbackTurnAngleDegrees then
			if math.abs(triggers.BallLateral) > 0.05 then
				cutbackSide = if triggers.BallLateral >= 0 then 1 else -1
			else
				cutbackSide = lastTouchSide
			end

			cutbackUntil = now + controlConfig.CutbackDuration
		end
	elseif controlMode == "Capture" then
		local captureDuration = now - captureStartedAt
		local canExit = captureDuration >= controlConfig.CaptureMinDuration
			and targetErrorMagnitude <= controlConfig.CaptureExitError
			and triggers.RelativeSpeed <= controlConfig.CaptureExitRelativeSpeed

		if canExit or captureDuration >= controlConfig.CaptureMaxDuration then
			controlMode = "Carry"
			lastCaptureExitAt = now
			cutbackSide = 0
			cutbackUntil = 0
		end
	end
end

local function getPhaseServoScales(phase: string): (number, number)
	if controlMode == "Capture" then
		return 1, 1
	end

	if phase == "Push" then
		return controlConfig.PushPositionGainScale, controlConfig.PushVelocityDampingScale
	elseif phase == "Coast" then
		return controlConfig.CoastPositionGainScale, controlConfig.CoastVelocityDampingScale
	elseif phase == "Settle" then
		return controlConfig.SettlePositionGainScale, controlConfig.SettleVelocityDampingScale
	end

	return controlConfig.CollectPositionGainScale, controlConfig.CollectVelocityDampingScale
end

local function getPhaseTargetPosition(rootPart: BasePart, direction: Vector3, locomotionState): Vector3
	local phase = getDribblePhase(locomotionState)
	local pulse = getTouchPulse(locomotionState)
	local leadDistance = getLeadDistance(locomotionState)
	local lateralDirection = Vector3.new(-direction.Z, 0, direction.X)
	local lateralOffset = lateralDirection * controlConfig.TouchLateralOffset * lastTouchSide * pulse

	if cutbackSide ~= 0 and os.clock() < cutbackUntil then
		lateralOffset += lateralDirection * controlConfig.CutbackLateralOffset * cutbackSide
	end

	local phaseLeadPulse = if phase == "Push" then getTouchLeadPulse(locomotionState) * pulse else 0

	return getTargetPosition(rootPart, direction, leadDistance + phaseLeadPulse) + lateralOffset
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
	ball:SetAttribute("RawMoveMagnitude", locomotionState.RawMagnitude)
	ball:SetAttribute("TurnAngle", locomotionState.TurnAngle or 0)
	ball:SetAttribute("BallRelativeSpeed", relativeSpeed)
	ball:SetAttribute("DribblePhase", getDribblePhase(locomotionState))
	ball:SetAttribute("BallIntentAngleError", if locomotionState.RawDirection.Magnitude > 0 then math.deg(math.acos(math.clamp(direction:Dot(locomotionState.RawDirection.Unit), -1, 1))) else 0)
	ball:SetAttribute("TurnCaptureActive", controlMode == "Capture")

	local serverLead = ball:GetAttribute("ServerBallLead")
	log(string.format(
		"Lead sample realClient=%.2f server=%s mode=%s phase=%s raw=%.2f playerSpeed=%.2f relativeSpeed=%.2f turn=%.0f",
		lead,
		if typeof(serverLead) == "number" then string.format("%.2f", serverLead) else "n/a",
		controlMode,
		getDribblePhase(locomotionState),
		locomotionState.RawMagnitude,
		locomotionState.SmoothedSpeed,
		relativeSpeed,
		locomotionState.TurnAngle or 0
	))
end

local function applyPossessionServo(ball: BasePart, rootPart: BasePart, locomotionState, deltaTime: number)
	local direction = updateBallIntentDirection(rootPart, locomotionState, deltaTime)
	updateTouchCancellation(locomotionState)
	beginTouchPulse(ball, locomotionState, direction)
	local targetPosition = getPhaseTargetPosition(rootPart, direction, locomotionState)
	local targetError = BallControlMath.GetHorizontal(targetPosition - ball.Position)
	local triggers = getModeTriggers(ball, rootPart, locomotionState, direction)

	updateControlMode(triggers, targetError.Magnitude)
	targetPosition = getPhaseTargetPosition(rootPart, direction, locomotionState)
	targetError = BallControlMath.GetHorizontal(targetPosition - ball.Position)

	local positionGain = if controlMode == "Capture" then controlConfig.CapturePositionGain else controlConfig.CarryPositionGain
	local velocityDamping = if controlMode == "Capture" then controlConfig.CaptureVelocityDamping else controlConfig.CarryVelocityDamping
	local phase = getDribblePhase(locomotionState)
	local positionScale, dampingScale = getPhaseServoScales(phase)
	positionGain *= positionScale
	velocityDamping *= dampingScale
	local playerDesiredVelocity = if locomotionState.IsMoving
		then direction * locomotionState.SmoothedSpeed
		else Vector3.zero
	local ballHorizontalVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	local relativeVelocity = ballHorizontalVelocity - playerDesiredVelocity
	local correctionVelocity = targetError * positionGain - relativeVelocity * velocityDamping
	local exclusionVelocity = applyBodyExclusion(ball, rootPart, direction)
	local pulse = getTouchPulse(locomotionState)
	local touchPulseVelocity = direction * getTouchSpeedPulse(locomotionState) * pulse
	local desiredHorizontalVelocity = playerDesiredVelocity + correctionVelocity + exclusionVelocity + touchPulseVelocity
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
	sampleDiagnostics(ball, rootPart, direction, locomotionState, relativeVelocity.Magnitude)
end

local function resetLocalState()
	controlDirection = nil
	ballIntentDirection = nil
	controlMode = "Carry"
	captureStartedAt = 0
	lastCaptureExitAt = 0
	lastTouchEventTime = 0
	touchEventCount = 0
	lastTouchSide = 1
	touchAirborneUntil = 0
	touchPulseCancelled = false
	touchDirection = nil
	cutbackSide = 0
	cutbackUntil = 0
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

function ControlledBallController.GetDribbleTouchEvent(): BindableEvent
	return dribbleTouchEvent
end

return ControlledBallController
