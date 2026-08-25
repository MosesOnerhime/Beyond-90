local BallControlMath = require(script.Parent.BallControlMath)

local ReceptionPlanner = {}

local EPSILON = 1e-4

local function getHorizontal(vector: Vector3): Vector3
	return BallControlMath.GetHorizontal(vector)
end

local function safeUnit(vector: Vector3, fallback: Vector3?): Vector3
	return BallControlMath.SafeUnit(getHorizontal(vector), fallback or Vector3.zAxis)
end

local function getFacingDirection(rootPart: BasePart): Vector3
	return safeUnit(rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
end

local function getMovementDirection(rootPart: BasePart, humanoid: Humanoid, facingDirection: Vector3): (Vector3, number)
	local horizontalVelocity = getHorizontal(rootPart.AssemblyLinearVelocity)
	local speed = horizontalVelocity.Magnitude

	if speed > 0.4 then
		return horizontalVelocity.Unit, speed
	end

	local moveDirection = getHorizontal(humanoid.MoveDirection)

	if moveDirection.Magnitude > 0.05 then
		return moveDirection.Unit, speed
	end

	return facingDirection, speed
end

local function getBallActionContext(ball: BasePart)
	local targetPosition = ball:GetAttribute("LastFootballActionTargetPosition")

	return {
		ActionType = ball:GetAttribute("LastFootballAction") or "",
		ActionTime = ball:GetAttribute("LastFootballActionTime") or -math.huge,
		InitiatorUserId = ball:GetAttribute("LastFootballActionPlayerUserId") or 0,
		IntendedReceiverUserId = ball:GetAttribute("LastFootballActionIntendedReceiverUserId") or 0,
		TargetPosition = if typeof(targetPosition) == "Vector3" then targetPosition else nil,
	}
end

local function getFirstTouchType(ballSpeed: number, relativeSpeed: number, playerSpeed: number, actionType: string, config)
	if ballSpeed <= config.SlowPickupSpeed and playerSpeed <= config.StationaryPlayerSpeed then
		return "Settle"
	end

	if actionType == "ThroughPass" and playerSpeed >= config.TakeInStridePlayerSpeed then
		return "TakeInStride"
	end

	-- A fast player collecting a slow loose ball should carry momentum through
	-- the contact. Classifying this by relative speed alone brakes the football
	-- and leaves it behind a sprinting receiver during network handoff.
	if ballSpeed <= config.SlowPickupSpeed and playerSpeed >= config.TakeInStridePlayerSpeed then
		return "TakeInStride"
	end

	if relativeSpeed >= config.CaptureRelativeSpeed then
		return "Capture"
	end

	if playerSpeed >= config.TakeInStridePlayerSpeed then
		return "TakeInStride"
	end

	return "Settle"
end

local function getFirstTouchVelocity(
	rootPart: BasePart,
	ball: BasePart,
	controlDirection: Vector3,
	playerVelocity: Vector3,
	firstTouchType: string,
	config
): (Vector3, Vector3)
	local rootPosition = rootPart.Position
	local playerSpeed = getHorizontal(playerVelocity).Magnitude
	local leadDistance = config.SettleLeadDistance
	local desiredHorizontalVelocity = Vector3.zero

	if firstTouchType == "TakeInStride" then
		leadDistance = math.clamp(
			config.TakeInStrideLeadBase + playerSpeed * config.TakeInStrideLeadPerSpeed,
			config.TakeInStrideLeadMin,
			config.TakeInStrideLeadMax
		)
		desiredHorizontalVelocity = controlDirection * math.min(playerSpeed + config.TakeInStrideSpeedBonus, config.TakeInStrideMaxSpeed)
	elseif firstTouchType == "Capture" then
		leadDistance = config.CaptureLeadDistance
		desiredHorizontalVelocity = controlDirection * math.min(math.max(playerSpeed, config.CaptureForwardSpeed), config.CaptureMaxSpeed)
	else
		desiredHorizontalVelocity = controlDirection * config.SettleForwardSpeed
	end

	local target = rootPosition + controlDirection * leadDistance
	local targetHorizontal = getHorizontal(target - ball.Position)
	local correctionVelocity = BallControlMath.ClampMagnitude(
		targetHorizontal * config.FirstTouchPositionGain,
		config.MaxFirstTouchCorrectionSpeed
	)
	local currentHorizontalVelocity = getHorizontal(ball.AssemblyLinearVelocity)
	local outputVelocity = desiredHorizontalVelocity + correctionVelocity
	local maxOutputSpeed = if firstTouchType == "Settle" then config.SettleMaxOutputSpeed else config.MaxFirstTouchOutputSpeed
	outputVelocity = BallControlMath.ClampMagnitude(outputVelocity, maxOutputSpeed)

	if firstTouchType == "Settle" then
		outputVelocity -= currentHorizontalVelocity * config.SettleDamping
	else
		outputVelocity = outputVelocity:Lerp(currentHorizontalVelocity, config.PreserveIncomingVelocity)
	end

	outputVelocity = BallControlMath.ClampMagnitude(outputVelocity, maxOutputSpeed)

	return Vector3.new(outputVelocity.X, math.min(ball.AssemblyLinearVelocity.Y, config.MaxFirstTouchVerticalSpeed), outputVelocity.Z),
		Vector3.new(target.X, ball.Position.Y, target.Z)
end

function ReceptionPlanner.Evaluate(
	player: Player,
	ball: BasePart,
	rootPart: BasePart,
	humanoid: Humanoid,
	config,
	previousBallPosition: Vector3?
)
	local actionContext = getBallActionContext(ball)
	local intendedReceiver = actionContext.IntendedReceiverUserId == player.UserId
		and player.UserId ~= 0
		and os.clock() - actionContext.ActionTime <= config.IntendedReceiverWindowSeconds
	local ballVelocity = ball.AssemblyLinearVelocity
	local ballHorizontalVelocity = getHorizontal(ballVelocity)
	local ballSpeed = ballHorizontalVelocity.Magnitude
	local ballHeight = ball.Position.Y

	local maximumCenterHeight = if intendedReceiver
		then config.IntendedReceiverMaxCenterHeight
		else config.MaxControlCenterHeight
	if ballHeight > maximumCenterHeight then
		return nil
	end

	local maximumBallSpeed = if intendedReceiver
		then config.IntendedReceiverMaxBallSpeed
		else config.MaxControllableBallSpeed
	if ballSpeed > maximumBallSpeed then
		return nil
	end

	local facingDirection = getFacingDirection(rootPart)
	local movementDirection, playerSpeed = getMovementDirection(rootPart, humanoid, facingDirection)
	local playerVelocity = getHorizontal(rootPart.AssemblyLinearVelocity)
	local evaluationPosition = ball.Position
	if intendedReceiver and typeof(previousBallPosition) == "Vector3" then
		local segment = getHorizontal(ball.Position - previousBallPosition)
		local segmentLengthSquared = segment:Dot(segment)
		if segmentLengthSquared > EPSILON then
			local toPlayer = getHorizontal(rootPart.Position - previousBallPosition)
			local alpha = math.clamp(toPlayer:Dot(segment) / segmentLengthSquared, 0, 1)
			local sweptPosition = previousBallPosition + (ball.Position - previousBallPosition) * alpha
			if getHorizontal(sweptPosition - rootPart.Position).Magnitude
				< getHorizontal(evaluationPosition - rootPart.Position).Magnitude
			then
				evaluationPosition = sweptPosition
			end
		end
	end
	local horizontalFromPlayer = getHorizontal(evaluationPosition - rootPart.Position)
	local distance = horizontalFromPlayer.Magnitude
	if intendedReceiver and distance <= EPSILON and ballSpeed > EPSILON then
		horizontalFromPlayer = -ballHorizontalVelocity.Unit * EPSILON
		distance = EPSILON
	end

	local maximumReachDistance = if intendedReceiver
		then config.IntendedReceiverReachDistance
		else config.MaxReachDistance
	if distance < EPSILON or distance > maximumReachDistance then
		return nil
	end

	local directionToBall = horizontalFromPlayer.Unit
	local forwardLead = horizontalFromPlayer:Dot(movementDirection)
	local lateralDistance = (horizontalFromPlayer - movementDirection * forwardLead).Magnitude
	local towardBallDot = movementDirection:Dot(directionToBall)
	local ballApproachDot = if ballSpeed > EPSILON then ballHorizontalVelocity.Unit:Dot(-directionToBall) else 0
	local relativeSpeed = (ballHorizontalVelocity - playerVelocity).Magnitude

	local inFrontControlLane = forwardLead >= -config.BehindTolerance
		and forwardLead <= config.FrontReachDistance
		and lateralDistance <= config.LateralReachDistance
	local loosePickup = distance <= config.LoosePickupDistance
		and (forwardLead >= -config.LooseBehindTolerance or towardBallDot >= config.TurnTowardBehindDot)
	local incomingReachDistance = if intendedReceiver then maximumReachDistance else config.IncomingReachDistance
	local incomingLateralTolerance = if intendedReceiver
		then config.IntendedReceiverLateralTolerance
		else config.IncomingLateralTolerance
	local incomingReception = ballApproachDot >= config.IncomingApproachDot
		and distance <= incomingReachDistance
		and lateralDistance <= incomingLateralTolerance
	local chasingBall = playerSpeed >= config.MinChasePlayerSpeed
		and towardBallDot >= config.MinTowardBallDot
		and distance <= config.ChaseReachDistance

	if not inFrontControlLane and not loosePickup and not incomingReception and not chasingBall then
		return nil
	end

	if relativeSpeed > config.MaxRelativeSpeed and not incomingReception then
		return nil
	end

	local firstTouchType = getFirstTouchType(ballSpeed, relativeSpeed, playerSpeed, actionContext.ActionType, config)

	if firstTouchType == "Loose" then
		return nil
	end

	local touchDirection = movementDirection

	if incomingReception and ballSpeed > EPSILON then
		touchDirection = -ballHorizontalVelocity.Unit
	end

	if actionContext.ActionType == "KnockOn" and player.UserId == actionContext.InitiatorUserId and playerSpeed >= config.MinChasePlayerSpeed then
		touchDirection = movementDirection
	end

	local firstTouchVelocity, firstTouchTarget = getFirstTouchVelocity(
		rootPart,
		ball,
		touchDirection,
		playerVelocity,
		firstTouchType,
		config
	)

	local estimatedTimeToBall = math.max(0, (distance - config.ControlRadius) / math.max(playerSpeed + ballSpeed * math.max(ballApproachDot, 0), 1))
	local score = 8
		- distance * config.DistanceScorePenalty
		- relativeSpeed * config.RelativeSpeedScorePenalty
		+ math.max(towardBallDot, 0) * config.TowardBallScoreBonus
		+ math.max(ballApproachDot, 0) * config.IncomingScoreBonus
		- estimatedTimeToBall * config.TimeScorePenalty

	if intendedReceiver then
		score += config.IntendedReceiverScoreBonus
	end

	return {
		Player = player,
		RootPart = rootPart,
		Humanoid = humanoid,
		Distance = distance,
		BallSpeed = ballSpeed,
		RelativeSpeed = relativeSpeed,
		PlayerSpeed = playerSpeed,
		BallHeight = ballHeight,
		ApproachDot = ballApproachDot,
		TowardBallDot = towardBallDot,
		ForwardLead = forwardLead,
		LateralDistance = lateralDistance,
		FirstTouchType = firstTouchType,
		FirstTouchVelocity = firstTouchVelocity,
		FirstTouchTarget = firstTouchTarget,
		ControlDirection = touchDirection,
		Score = score,
		EstimatedTimeToBall = estimatedTimeToBall,
		ActionType = actionContext.ActionType,
		IntendedReceiver = intendedReceiver,
		InitiatorUserId = actionContext.InitiatorUserId,
	}
end

return ReceptionPlanner
