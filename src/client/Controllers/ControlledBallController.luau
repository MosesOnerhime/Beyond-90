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
local touchTargetLead = 0
local touchPeakSeparationReached = false
local currentDribblePhase = "Settle"
local cutbackSide = 0
local cutbackUntil = 0
local lastTouchBallPosition: Vector3? = nil
local peakForwardLeadSincePreviousTouch = 0
local minimumForwardLeadSincePreviousTouch = 0
local previousForwardLead: number? = nil
local predictedRecontactTime = 0
local previousTouchRecontactTime = 0
local leadDiagnosticSampleId = 0
local lastControlEpoch = -1
local handoffStabilizationUntil = 0
local handoffExpectedLead = 0
local handoffDirection: Vector3? = nil
local handoffNoTouchUntil = 0
local localActionReleaseSuppressedUntil = 0
local controlledRestCandidateStartedAt: number? = nil
local controlledRestActive = false
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
		local desiredDirection = locomotionState.RawDirection.Unit
		local facingDirection = getFacingDirection(rootPart)
		local facingInfluence = math.clamp(controlConfig.BallIntentFacingInfluence or 0, 0, 0.35)
		return BallControlMath.SafeUnit(
			desiredDirection * (1 - facingInfluence) + facingDirection * facingInfluence,
			desiredDirection
		)
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

local function getMovementTier(locomotionState): string
	if locomotionState.IsSprinting then
		return "Sprint"
	end

	if locomotionState.SmoothedSpeed >= controlConfig.LowMovementSpeedThreshold then
		return "Jog"
	end

	return "Low"
end

local function getTouchInterval(locomotionState): number
	local tier = getMovementTier(locomotionState)

	if tier == "Sprint" then
		return controlConfig.SprintTouchInterval
	elseif tier == "Jog" then
		return controlConfig.JogTouchInterval
	end

	return controlConfig.LowTouchInterval
end

local function getTouchSpeedPulse(locomotionState): number
	local tier = getMovementTier(locomotionState)

	if tier == "Sprint" then
		return controlConfig.SprintTouchSpeedPulse
	elseif tier == "Jog" then
		return controlConfig.JogTouchSpeedPulse
	end

	return controlConfig.LowTouchSpeedPulse
end

local function getTouchImpulseDeltaSpeed(locomotionState): number
	local tier = getMovementTier(locomotionState)

	if tier == "Sprint" then
		return controlConfig.SprintTouchImpulseDeltaSpeed
	elseif tier == "Jog" then
		return controlConfig.JogTouchImpulseDeltaSpeed
	end

	return controlConfig.LowTouchImpulseDeltaSpeed
end

local function getTouchHopHeight(locomotionState): number
	local tier = getMovementTier(locomotionState)

	if tier == "Sprint" then
		return controlConfig.SprintTouchHopHeight
	elseif tier == "Jog" then
		return controlConfig.JogTouchHopHeight
	end

	return controlConfig.LowTouchHopHeight
end

local function getTouchUpwardVelocity(locomotionState): number
	local hopHeight = getTouchHopHeight(locomotionState)

	if hopHeight <= 0 then
		return 0
	end

	return math.min(math.sqrt(2 * Workspace.Gravity * hopHeight), controlConfig.MaxTouchUpwardVelocity)
end

local function getTouchLeadPulse(locomotionState): number
	local tier = getMovementTier(locomotionState)

	if tier == "Sprint" then
		return controlConfig.SprintTouchLeadPulse
	elseif tier == "Jog" then
		return controlConfig.JogTouchLeadPulse
	end

	return controlConfig.LowTouchLeadPulse
end

local function getTargetPeakForwardLead(locomotionState): number
	local tier = getMovementTier(locomotionState)

	if tier == "Sprint" then
		return controlConfig.SprintPeakForwardLeadTarget
	elseif tier == "Jog" then
		return controlConfig.JogPeakForwardLeadTarget
	end

	return controlConfig.LowPeakForwardLeadTarget
end

local function getMaximumPeakForwardLead(locomotionState): number
	local tier = getMovementTier(locomotionState)

	if tier == "Sprint" then
		return controlConfig.SprintMaxForwardLead
	elseif tier == "Jog" then
		return controlConfig.JogMaxForwardLead
	end

	return controlConfig.LowMaxForwardLead
end

local function getTouchElapsed(): number
	return os.clock() - lastTouchEventTime
end

local function getTouchGroundDistance(ball: BasePart): number
	if not lastTouchBallPosition then
		return math.huge
	end

	return BallControlMath.GetHorizontal(ball.Position - (lastTouchBallPosition :: Vector3)).Magnitude
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

local function updateDribblePhase(locomotionState, currentLead: number, carryLead: number): string
	local phase = getDribblePhase(locomotionState)

	if phase == "Push" or phase == "Settle" or phase == "Collect" and controlMode == "Capture" then
		currentDribblePhase = phase
		return phase
	end

	if phase == "Coast" or currentDribblePhase == "Coast" then
		local elapsed = getTouchElapsed()
		local requiredPeakLead = getTargetPeakForwardLead(locomotionState) * controlConfig.TouchPeakLeadFraction

		if currentLead >= requiredPeakLead then
			touchPeakSeparationReached = true
		end

		if currentLead >= getMaximumPeakForwardLead(locomotionState) then
			touchPeakSeparationReached = true
			currentDribblePhase = "Collect"
			return currentDribblePhase
		end

		if not touchPeakSeparationReached and elapsed <= controlConfig.TouchMaxSeparationWait then
			currentDribblePhase = "Coast"
			return currentDribblePhase
		end

		if elapsed <= controlConfig.TouchPulseDuration + controlConfig.TouchCoastDuration then
			currentDribblePhase = "Coast"
			return currentDribblePhase
		end
	end

	currentDribblePhase = phase
	return currentDribblePhase
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

local function canStartNextTouch(ball: BasePart, now: number, locomotionState, currentLead: number, carryLead: number): boolean
	local elapsedSinceTouch = now - lastTouchEventTime

	if lastTouchEventTime <= 0 then
		return true
	end

	if elapsedSinceTouch < getTouchInterval(locomotionState) then
		return false
	end

	local reachedPeak = peakForwardLeadSincePreviousTouch >= getTargetPeakForwardLead(locomotionState) * controlConfig.RecontactPeakLeadFraction
	local recoveredLead = currentLead <= carryLead + controlConfig.NextTouchLeadTolerance

	if recoveredLead and reachedPeak then
		previousTouchRecontactTime = elapsedSinceTouch
		return true
	end

	if elapsedSinceTouch >= controlConfig.ForcedNextTouchInterval and currentLead <= getMaximumPeakForwardLead(locomotionState) then
		previousTouchRecontactTime = elapsedSinceTouch
		return true
	end

	return false
end

local function logTouchMetrics(ball: BasePart, locomotionState, turnAngle: number, phaseBeforeTouch: string)
	if not controlConfig.TouchDiagnosticEnabled or lastTouchEventTime <= 0 or not lastTouchBallPosition then
		return
	end

	local now = os.clock()
	local timeSincePreviousTouch = now - lastTouchEventTime
	local worldBallTravel = getTouchGroundDistance(ball)
	local direction = touchDirection or locomotionState.SmoothedDirection
	local ballHorizontalVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	local playerVelocity = if direction.Magnitude > 0
		then direction.Unit * locomotionState.SmoothedSpeed
		else Vector3.zero
	local relativeLongitudinalVelocity = if direction.Magnitude > 0
		then (ballHorizontalVelocity - playerVelocity):Dot(direction.Unit)
		else 0
	log(string.format(
		"[Touch] id=%d speed=%.1f dt=%.2f worldBallTravel=%.2f peakForwardLead=%.2f minForwardLead=%.2f relativeLongitudinalVelocity=%.2f predictedRecontactTime=%.2f actualRecontactTime=%.2f phaseBefore=%s turn=%.0f",
		touchEventCount + 1,
		locomotionState.SmoothedSpeed,
		timeSincePreviousTouch,
		worldBallTravel,
		peakForwardLeadSincePreviousTouch,
		minimumForwardLeadSincePreviousTouch,
		relativeLongitudinalVelocity,
		predictedRecontactTime,
		previousTouchRecontactTime,
		phaseBeforeTouch,
		turnAngle
	))
	ball:SetAttribute("LastLocalTouchWorldBallTravel", worldBallTravel)
	ball:SetAttribute("LastLocalTouchInterval", timeSincePreviousTouch)
	ball:SetAttribute("LastLocalTouchPeakForwardLead", peakForwardLeadSincePreviousTouch)
	ball:SetAttribute("LastLocalTouchMinForwardLead", minimumForwardLeadSincePreviousTouch)
	ball:SetAttribute("LastLocalTouchRelativeLongitudinalVelocity", relativeLongitudinalVelocity)
	ball:SetAttribute("LastLocalTouchPredictedRecontactTime", predictedRecontactTime)
	ball:SetAttribute("LastLocalTouchActualRecontactTime", previousTouchRecontactTime)
end

local function beginTouchPulse(ball: BasePart, locomotionState, direction: Vector3, currentLead: number, carryLead: number)
	local now = os.clock()

	if now < handoffNoTouchUntil then
		return
	end

	if controlMode == "Capture" or locomotionState.RawMagnitude <= 0 or not locomotionState.IsMoving then
		return
	end

	if not canStartNextTouch(ball, now, locomotionState, currentLead, carryLead) then
		return
	end

	logTouchMetrics(ball, locomotionState, locomotionState.TurnAngle or 0, currentDribblePhase)
	lastTouchEventTime = now
	touchPulseCancelled = false
	touchDirection = direction
	touchTargetLead = getLeadDistance(locomotionState) + getTouchLeadPulse(locomotionState)
	touchPeakSeparationReached = false
	lastTouchBallPosition = ball.Position
	peakForwardLeadSincePreviousTouch = currentLead
	minimumForwardLeadSincePreviousTouch = currentLead
	predictedRecontactTime = math.clamp(
		(getTargetPeakForwardLead(locomotionState) - carryLead) / math.max(locomotionState.SmoothedSpeed * 0.35, 1),
		getTouchInterval(locomotionState),
		controlConfig.ForcedNextTouchInterval
	)
	previousTouchRecontactTime = 0
	currentDribblePhase = "Push"
	touchAirborneUntil = now + controlConfig.TouchAirborneWindow
	touchEventCount += 1
	lastTouchSide *= -1
	ball:SetAttribute("LastLocalControlTouchTime", now)
	ball:SetAttribute("LastLocalControlTouchCount", touchEventCount)
	ball:SetAttribute("LastLocalDribbleFootSide", if lastTouchSide > 0 then "Right" else "Left")
	ball:SetAttribute("LastLocalDribbleTouchStrength", getMovementTier(locomotionState))

	local forwardImpulseDeltaSpeed = getTouchImpulseDeltaSpeed(locomotionState)

	if forwardImpulseDeltaSpeed > 0 then
		applyVelocityDelta(ball, direction * forwardImpulseDeltaSpeed)
	end

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
		TouchStrength = getMovementTier(locomotionState),
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
	local stationarySettled = locomotionState.RawMagnitude <= 0 and locomotionState.SmoothedSpeed <= controlConfig.StationaryPlayerSpeed
	local stationaryNeedsCapture = stationarySettled
		and (
			bodyOverlap
			or distance > controlConfig.StationaryCaptureDistance
			or relativeSpeed > controlConfig.StationaryCaptureRelativeSpeed
		)
	local stationaryStable = stationarySettled
		and not bodyOverlap
		and distance <= controlConfig.StationarySettleDistance
		and relativeSpeed <= controlConfig.StationarySettleRelativeSpeed

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
		RawMagnitude = locomotionState.RawMagnitude,
		PlayerSpeed = locomotionState.SmoothedSpeed,
		StationarySettled = stationarySettled,
		StationaryStable = stationaryStable,
		StationaryNeedsCapture = stationaryNeedsCapture,
	}
end

local function updateControlMode(triggers, targetErrorMagnitude: number)
	local now = os.clock()

	if now < handoffStabilizationUntil then
		controlMode = "Carry"
		currentDribblePhase = "Collect"
		touchPulseCancelled = true
		return
	end

	if triggers.StationaryStable then
		if controlMode == "Capture" then
			controlMode = "Carry"
			lastCaptureExitAt = now
			cutbackSide = 0
			cutbackUntil = 0
		end

		return
	end

	local shouldCapture = triggers.ReleasedMovement
		or (triggers.SharpTurn and not triggers.StationarySettled)
		or (triggers.Behind and not triggers.IntentionalPush and not triggers.StationarySettled)
		or triggers.BodyOverlap
		or triggers.StationaryNeedsCapture

	if shouldCapture
		and controlMode ~= "Capture"
		and now - lastCaptureExitAt >= controlConfig.CaptureReentryCooldown
	then
		controlMode = "Capture"
		captureStartedAt = now
		touchPulseCancelled = true
		currentDribblePhase = "Collect"

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

local function updateControlledRestState(triggers): boolean
	local now = os.clock()
	local leadError = math.abs(triggers.BallLead - controlConfig.StationaryCarryLeadDistance)
	local eligible = triggers.StationarySettled
		and not triggers.BodyOverlap
		and triggers.Distance <= controlConfig.ControlledRestMaxDistance
		and leadError <= controlConfig.ControlledRestLeadTolerance

	if not eligible
		or triggers.RawMagnitude > controlConfig.ControlledRestExitInputMagnitude
		or triggers.PlayerSpeed > controlConfig.ControlledRestMaxPlayerSpeed
	then
		controlledRestCandidateStartedAt = nil
		controlledRestActive = false
		return false
	end

	if not controlledRestCandidateStartedAt then
		controlledRestCandidateStartedAt = now
	end

	if now - (controlledRestCandidateStartedAt :: number) >= controlConfig.ControlledRestEnterDelay then
		controlledRestActive = true
		controlMode = "Carry"
		currentDribblePhase = "Settle"
		touchPulseCancelled = true
		touchAirborneUntil = 0
	end

	return controlledRestActive
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

local function getPhasePlayerVelocityScale(phase: string, locomotionState): number
	if controlMode == "Capture" then
		return 1
	end

	if phase == "Push" then
		return controlConfig.PushPlayerVelocityScale
	elseif phase == "Coast" then
		return controlConfig.CoastPlayerVelocityScale
	elseif phase == "Settle" then
		if locomotionState.SmoothedSpeed > controlConfig.StationaryPlayerSpeed then
			return controlConfig.ReleasedSettlePlayerVelocityScale
		end

		return controlConfig.SettlePlayerVelocityScale
	end

	return controlConfig.CollectPlayerVelocityScale
end

local function getPhaseTargetPosition(rootPart: BasePart, direction: Vector3, locomotionState): Vector3
	local phase = currentDribblePhase
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

local function getRecontactCrossingCorrection(ball: BasePart, direction: Vector3, currentLead: number): Vector3
	if not previousForwardLead then
		return Vector3.zero
	end

	if previousForwardLead < controlConfig.RecontactCrossingPreviousLead
		or currentLead > controlConfig.RecontactCrossingBehindLead
	then
		return Vector3.zero
	end

	touchPulseCancelled = true
	currentDribblePhase = "Collect"
	local ballHorizontalVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	local longitudinalSpeed = ballHorizontalVelocity:Dot(direction)
	local cancelSpeed = math.min(math.max(-longitudinalSpeed, 0), controlConfig.RecontactCrossingMaxCancelSpeed)
	local forwardRescue = (controlConfig.RecontactCrossingBehindLead - currentLead) * controlConfig.RecontactCrossingForwardGain
	return direction * (cancelSpeed + forwardRescue)
end

local function sampleDiagnostics(ball: BasePart, rootPart: BasePart, direction: Vector3, locomotionState, relativeSpeed: number)
	local now = os.clock()

	if now - lastDiagnosticTime < controlConfig.LeadDiagnosticInterval then
		return
	end

	lastDiagnosticTime = now
	leadDiagnosticSampleId += 1
	local lead = BallControlMath.GetHorizontal(ball.Position - rootPart.Position):Dot(direction)
	ball:SetAttribute("ClientBallLead", lead)
	ball:SetAttribute("ClientLeadSampleId", leadDiagnosticSampleId)
	ball:SetAttribute("ClientLeadSampleTime", now)
	ball:SetAttribute("ControlMode", controlMode)
	ball:SetAttribute("SmoothedPlayerSpeed", locomotionState.SmoothedSpeed)
	ball:SetAttribute("RawMoveMagnitude", locomotionState.RawMagnitude)
	ball:SetAttribute("TurnAngle", locomotionState.TurnAngle or 0)
	ball:SetAttribute("BallRelativeSpeed", relativeSpeed)
	ball:SetAttribute("DribblePhase", currentDribblePhase)
	ball:SetAttribute("BallIntentAngleError", if locomotionState.RawDirection.Magnitude > 0 then math.deg(math.acos(math.clamp(direction:Dot(locomotionState.RawDirection.Unit), -1, 1))) else 0)
	ball:SetAttribute("TurnCaptureActive", controlMode == "Capture")

	local serverLead = ball:GetAttribute("ServerBallLead")
	local serverSampleId = ball:GetAttribute("ServerLeadSampleId")
	log(string.format(
		"Lead sample id=%d serverId=%s realClient=%.2f server=%s mode=%s phase=%s raw=%.2f playerSpeed=%.2f relativeSpeed=%.2f turn=%.0f",
		leadDiagnosticSampleId,
		if typeof(serverSampleId) == "number" then tostring(serverSampleId) else "n/a",
		lead,
		if typeof(serverLead) == "number" then string.format("%.2f", serverLead) else "n/a",
		controlMode,
		currentDribblePhase,
		locomotionState.RawMagnitude,
		locomotionState.SmoothedSpeed,
		relativeSpeed,
		locomotionState.TurnAngle or 0
	))
end

local function applyPossessionServo(ball: BasePart, rootPart: BasePart, locomotionState, deltaTime: number)
	local now = os.clock()
	local direction

	if now < handoffStabilizationUntil and handoffDirection then
		direction = handoffDirection :: Vector3
		controlDirection = direction
		ballIntentDirection = direction
	else
		direction = updateBallIntentDirection(rootPart, locomotionState, deltaTime)
	end

	updateTouchCancellation(locomotionState)
	local leadBeforeTarget = BallControlMath.GetHorizontal(ball.Position - rootPart.Position):Dot(direction)
	peakForwardLeadSincePreviousTouch = math.max(peakForwardLeadSincePreviousTouch, leadBeforeTarget)
	minimumForwardLeadSincePreviousTouch = math.min(minimumForwardLeadSincePreviousTouch, leadBeforeTarget)
	local carryLead = getLeadDistance(locomotionState)

	if now < handoffStabilizationUntil then
		controlMode = "Carry"
		currentDribblePhase = "Collect"
		touchPulseCancelled = true
		touchAirborneUntil = 0

		local targetLead = math.max(
			handoffExpectedLead,
			if locomotionState.IsMoving then controlConfig.HandoffTargetLead else controlConfig.StationaryCarryLeadDistance,
			controlConfig.HandoffMinForwardLead,
			getMinimumControlDistance()
		)
		local targetPosition = getTargetPosition(rootPart, direction, targetLead)
		local targetError = BallControlMath.GetHorizontal(targetPosition - ball.Position)
		local playerDesiredVelocity = if locomotionState.IsMoving
			then direction * locomotionState.SmoothedSpeed
			else Vector3.zero
		local ballHorizontalVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
		local relativeVelocity = ballHorizontalVelocity - playerDesiredVelocity
		local correctionVelocity = targetError * controlConfig.HandoffPositionGain
			- relativeVelocity * controlConfig.HandoffVelocityDamping
			+ applyBodyExclusion(ball, rootPart, direction)

		if leadBeforeTarget < controlConfig.HandoffMinForwardLead then
			correctionVelocity += direction * (controlConfig.HandoffMinForwardLead - leadBeforeTarget) * controlConfig.HandoffPositionGain
		end

		local desiredHorizontalVelocity = playerDesiredVelocity + correctionVelocity
		desiredHorizontalVelocity = BallControlMath.ClampMagnitude(
			desiredHorizontalVelocity,
			controlConfig.MaxControlledCorrectionSpeed
		)
		local horizontalDelta = desiredHorizontalVelocity - ballHorizontalVelocity
		local maxDelta = controlConfig.HandoffMaxDeltaSpeedPerSecond * deltaTime
		horizontalDelta = BallControlMath.ClampMagnitude(horizontalDelta, maxDelta)
		applyVelocityDelta(ball, Vector3.new(horizontalDelta.X, 0, horizontalDelta.Z))
		ball:SetAttribute("ControlledRestActive", false)
		sampleDiagnostics(ball, rootPart, direction, locomotionState, relativeVelocity.Magnitude)
		previousForwardLead = leadBeforeTarget
		return
	end

	beginTouchPulse(ball, locomotionState, direction, leadBeforeTarget, carryLead)
	updateDribblePhase(locomotionState, leadBeforeTarget, carryLead)
	local targetPosition = getPhaseTargetPosition(rootPart, direction, locomotionState)
	local targetError = BallControlMath.GetHorizontal(targetPosition - ball.Position)
	local triggers = getModeTriggers(ball, rootPart, locomotionState, direction)

	updateControlMode(triggers, targetError.Magnitude)
	updateControlledRestState(triggers)
	updateDribblePhase(locomotionState, leadBeforeTarget, carryLead)
	targetPosition = getPhaseTargetPosition(rootPart, direction, locomotionState)
	targetError = BallControlMath.GetHorizontal(targetPosition - ball.Position)

	local positionGain = if controlMode == "Capture" then controlConfig.CapturePositionGain else controlConfig.CarryPositionGain
	local velocityDamping = if controlMode == "Capture" then controlConfig.CaptureVelocityDamping else controlConfig.CarryVelocityDamping
	local phase = currentDribblePhase
	local positionScale, dampingScale = getPhaseServoScales(phase)
	positionGain *= positionScale
	velocityDamping *= dampingScale
	local maxForwardLead = getMaximumPeakForwardLead(locomotionState)
	local beyondPeakLead = math.max(0, leadBeforeTarget - maxForwardLead)

	if beyondPeakLead > 0 and controlMode ~= "Capture" then
		currentDribblePhase = "Collect"
		phase = currentDribblePhase
		positionGain = controlConfig.CarryPositionGain * controlConfig.CollectPositionGainScale
		velocityDamping = controlConfig.CarryVelocityDamping * controlConfig.CollectVelocityDampingScale
		touchPeakSeparationReached = true
	end

	local playerDesiredVelocity = if locomotionState.IsMoving
		then direction * locomotionState.SmoothedSpeed
		else Vector3.zero
	local ballHorizontalVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	local relativeVelocity = ballHorizontalVelocity - playerDesiredVelocity

	if controlledRestActive then
		local restTarget = getTargetPosition(rootPart, direction, controlConfig.StationaryCarryLeadDistance)
		local restTargetError = BallControlMath.GetHorizontal(restTarget - ball.Position)
		local exclusionVelocity = applyBodyExclusion(ball, rootPart, direction)
		local dampingAlpha = math.clamp(controlConfig.ControlledRestVelocityDamping * deltaTime, 0, 1)
		local horizontalDelta = -ballHorizontalVelocity * dampingAlpha
			+ restTargetError * controlConfig.ControlledRestPositionGain * deltaTime
			+ exclusionVelocity * deltaTime
		local maxDelta = controlConfig.ControlledRestMaxDeltaSpeedPerSecond * deltaTime
		horizontalDelta = BallControlMath.ClampMagnitude(horizontalDelta, maxDelta)
		applyVelocityDelta(ball, Vector3.new(horizontalDelta.X, 0, horizontalDelta.Z))
		ball.AssemblyAngularVelocity = ball.AssemblyAngularVelocity:Lerp(
			Vector3.zero,
			math.clamp(controlConfig.ControlledRestAngularDamping * deltaTime, 0, 1)
		)
		ball:SetAttribute("ControlledRestActive", true)
		sampleDiagnostics(ball, rootPart, direction, locomotionState, ballHorizontalVelocity.Magnitude)
		previousForwardLead = leadBeforeTarget
		return
	end

	ball:SetAttribute("ControlledRestActive", false)

	local correctionVelocity = targetError * positionGain - relativeVelocity * velocityDamping

	if triggers.StationaryStable and phase == "Settle" then
		correctionVelocity = targetError * (positionGain * 0.35) - ballHorizontalVelocity * controlConfig.IdleVelocityDamping
	end

	local longitudinalCorrection = direction * correctionVelocity:Dot(direction)
	local lateralCorrection = correctionVelocity - longitudinalCorrection

	if controlMode ~= "Capture" then
		if phase == "Coast" then
			correctionVelocity = lateralCorrection
		elseif phase == "Collect" and longitudinalCorrection:Dot(direction) < 0 then
			correctionVelocity = lateralCorrection + longitudinalCorrection * controlConfig.CollectBackwardCorrectionScale
		end
	end

	local exclusionVelocity = applyBodyExclusion(ball, rootPart, direction)
	local crossingCorrection = getRecontactCrossingCorrection(ball, direction, leadBeforeTarget)
	local pulse = getTouchPulse(locomotionState)
	local touchPulseVelocity = direction * getTouchSpeedPulse(locomotionState) * pulse
	local coastPulseVelocity = if phase == "Coast" and not touchPeakSeparationReached
		then direction * getTouchSpeedPulse(locomotionState) * controlConfig.TouchCoastSpeedPulseScale
		else Vector3.zero
	local basePlayerVelocity = playerDesiredVelocity * getPhasePlayerVelocityScale(phase, locomotionState)
	local desiredHorizontalVelocity

	if controlMode ~= "Capture" and phase == "Coast" then
		local forwardBallVelocity = direction * ballHorizontalVelocity:Dot(direction)
		local peakLimitVelocity = if beyondPeakLead > 0
			then -direction * math.min(beyondPeakLead * controlConfig.PeakLeadOvershootBrakeGain, controlConfig.PeakLeadOvershootMaxBrakeSpeed)
			else Vector3.zero
		desiredHorizontalVelocity = forwardBallVelocity
			+ correctionVelocity
			+ exclusionVelocity
			+ crossingCorrection
			+ coastPulseVelocity
			+ peakLimitVelocity
	else
		desiredHorizontalVelocity = basePlayerVelocity
			+ correctionVelocity
			+ exclusionVelocity
			+ crossingCorrection
			+ touchPulseVelocity
			+ coastPulseVelocity
	end

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
	previousForwardLead = leadBeforeTarget
end

local function resetLocalState(seedDirection: Vector3?)
	controlDirection = seedDirection
	ballIntentDirection = seedDirection
	controlMode = "Carry"
	captureStartedAt = 0
	lastCaptureExitAt = 0
	lastTouchEventTime = 0
	touchEventCount = 0
	lastTouchSide = 1
	touchAirborneUntil = 0
	touchPulseCancelled = false
	touchDirection = nil
	touchTargetLead = 0
	touchPeakSeparationReached = false
	currentDribblePhase = "Settle"
	cutbackSide = 0
	cutbackUntil = 0
	lastTouchBallPosition = nil
	peakForwardLeadSincePreviousTouch = 0
	minimumForwardLeadSincePreviousTouch = 0
	previousForwardLead = nil
	predictedRecontactTime = 0
	previousTouchRecontactTime = 0
	leadDiagnosticSampleId = 0
	lastControlEpoch = -1
	handoffStabilizationUntil = 0
	handoffExpectedLead = 0
	handoffDirection = nil
	handoffNoTouchUntil = 0
	controlledRestCandidateStartedAt = nil
	controlledRestActive = false
end

local function reconcileNewControlEpochBall(ball: BasePart, rootPart: BasePart, seedDirection: Vector3, expectedLead: number): (number, boolean)
	local initialLead = BallControlMath.GetHorizontal(ball.Position - rootPart.Position):Dot(seedDirection)

	if not controlConfig.HandoffImmediateRescueEnabled then
		return initialLead, false
	end

	local serverLead = ball:GetAttribute("ServerBallLead")
	local serverShowsForward = typeof(serverLead) == "number"
		and serverLead >= controlConfig.HandoffImmediateRescueServerLead
	local clientTooFarFromServer = serverShowsForward
		and math.abs(initialLead - serverLead) >= controlConfig.HandoffImmediateRescueLeadError
	local clientBehindOrTooClose = initialLead < controlConfig.HandoffImmediateRescueMinLead
	local clientBehindExpected = initialLead < expectedLead - controlConfig.HandoffImmediateRescueLeadError

	if not clientBehindOrTooClose and not clientTooFarFromServer and not clientBehindExpected then
		return initialLead, false
	end

	local targetLead = math.max(
		expectedLead,
		controlConfig.HandoffMinForwardLead,
		getMinimumControlDistance()
	)
	local rootHorizontal = BallControlMath.GetHorizontal(rootPart.Position)
	local targetHorizontal = rootHorizontal + seedDirection * targetLead
	ball.CFrame = CFrame.new(Vector3.new(targetHorizontal.X, ball.Position.Y, targetHorizontal.Z))

	local rootHorizontalVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local forwardPlayerSpeed = math.max(0, rootHorizontalVelocity:Dot(seedDirection))
	local seededHorizontalVelocity = seedDirection * (forwardPlayerSpeed + controlConfig.HandoffImmediateRescueForwardSpeed)
	local firstTouchVelocity = ball:GetAttribute("InitialBallVelocityAfterFirstTouch")

	if typeof(firstTouchVelocity) == "Vector3" and isFiniteVector(firstTouchVelocity) then
		local firstTouchHorizontal = BallControlMath.GetHorizontal(firstTouchVelocity)
		seededHorizontalVelocity = seededHorizontalVelocity:Lerp(firstTouchHorizontal, 0.35)
	end

	seededHorizontalVelocity = BallControlMath.ClampMagnitude(
		seededHorizontalVelocity,
		controlConfig.MaxControlledCorrectionSpeed
	)
	ball.AssemblyLinearVelocity = Vector3.new(
		seededHorizontalVelocity.X,
		math.min(ball.AssemblyLinearVelocity.Y, controlConfig.MaxContactVerticalDeltaSpeed),
		seededHorizontalVelocity.Z
	)

	local reconciledLead = BallControlMath.GetHorizontal(ball.Position - rootPart.Position):Dot(seedDirection)
	return reconciledLead, true
end

local function resetForControlEpoch(ball: BasePart, rootPart: BasePart, locomotionState)
	local seedDirection = ball:GetAttribute("InitialControlDirection")

	if typeof(seedDirection) ~= "Vector3" or not isFiniteVector(seedDirection) or seedDirection.Magnitude <= 0.05 then
		seedDirection = getLocomotionDirection(rootPart, locomotionState)
	end

	seedDirection = BallControlMath.SafeUnit(seedDirection, getFacingDirection(rootPart))
	resetLocalState(seedDirection)
	local epoch = ball:GetAttribute("ControlEpoch")
	lastControlEpoch = if typeof(epoch) == "number" then epoch else 0
	handoffStabilizationUntil = os.clock() + controlConfig.HandoffStabilizationDuration
	handoffNoTouchUntil = os.clock() + controlConfig.HandoffNoTouchDuration
	handoffDirection = seedDirection
	local expectedLead = ball:GetAttribute("InitialExpectedLead")
	handoffExpectedLead = if typeof(expectedLead) == "number" then expectedLead else controlConfig.HandoffTargetLead
	currentDribblePhase = "Collect"
	controlMode = "Carry"
	touchPulseCancelled = true

	local initialLead, rescued = reconcileNewControlEpochBall(ball, rootPart, seedDirection, handoffExpectedLead)
	log(string.format(
		"epoch=%d initialized initialLead=%.2f expectedLead=%.2f phase=Carry rescued=%s",
		lastControlEpoch,
		initialLead,
		handoffExpectedLead,
		tostring(rescued)
	))
end

local function updateControlledBall(deltaTime: number)
	if not isPlayerOwnedMode() then
		return
	end

	local ball = getFootball()

	if os.clock() < localActionReleaseSuppressedUntil then
		touchPulseCancelled = true
		touchAirborneUntil = 0
		return
	end

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

	local currentEpoch = ball:GetAttribute("ControlEpoch") or 0

	if currentEpoch ~= lastControlEpoch then
		resetForControlEpoch(ball, rootPart, locomotionState)
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

function ControlledBallController.NotifyLocalFootballActionRelease(duration: number?)
	localActionReleaseSuppressedUntil = os.clock() + (duration or 0.18)
	touchPulseCancelled = true
	touchAirborneUntil = 0
	lastTouchEventTime = 0
	currentDribblePhase = "Settle"
end

return ControlledBallController
