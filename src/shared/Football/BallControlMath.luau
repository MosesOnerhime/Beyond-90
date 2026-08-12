local BallControlMath = {}

local EPSILON = 1e-4

function BallControlMath.GetHorizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

function BallControlMath.SafeUnit(vector: Vector3, fallback: Vector3?): Vector3
	if vector.Magnitude > EPSILON then
		return vector.Unit
	end

	return fallback or Vector3.zero
end

function BallControlMath.PredictHorizontalPosition(position: Vector3, velocity: Vector3, horizon: number): Vector3
	local horizontalVelocity = BallControlMath.GetHorizontal(velocity)
	return position + horizontalVelocity * horizon
end

function BallControlMath.ClampMagnitude(vector: Vector3, maxMagnitude: number): Vector3
	if vector.Magnitude > maxMagnitude then
		return vector.Unit * maxMagnitude
	end

	return vector
end

function BallControlMath.GetControlDirection(rootVelocity: Vector3, fallbackDirection: Vector3?): (Vector3?, number)
	local horizontalVelocity = BallControlMath.GetHorizontal(rootVelocity)
	local speed = horizontalVelocity.Magnitude

	if speed > EPSILON then
		return horizontalVelocity.Unit, speed
	end

	return fallbackDirection, speed
end

function BallControlMath.GetFutureContactDelay(playerSpeed: number, controlConfig): number
	local sprintReferenceSpeed = math.max(controlConfig.SprintReferenceSpeed, EPSILON)
	local speedAlpha = math.clamp(playerSpeed / sprintReferenceSpeed, 0, 1)
	local delayRange = controlConfig.MaximumFutureContactDelay - controlConfig.MinimumFutureContactDelay

	return controlConfig.MinimumFutureContactDelay + (speedAlpha ^ 2) * delayRange
end

function BallControlMath.GetFrontOfFootOffset(playerSpeed: number, controlConfig): number
	return math.clamp(
		controlConfig.FrontFootBaseDistance + playerSpeed * controlConfig.FrontFootVelocityLeadTime,
		controlConfig.MinimumFrontFootOffset,
		controlConfig.MaximumFrontFootOffset
	)
end

function BallControlMath.GetContactAssistDirection(
	rootPosition: Vector3,
	ballPosition: Vector3,
	ballVelocity: Vector3,
	fallbackDirection: Vector3,
	controlConfig
)
	local predictedBallPosition = BallControlMath.PredictHorizontalPosition(
		ballPosition,
		ballVelocity,
		controlConfig.ContactAssistPredictionTime
	)
	local toPredictedBall = BallControlMath.GetHorizontal(predictedBallPosition - rootPosition)

	return BallControlMath.SafeUnit(toPredictedBall, fallbackDirection), toPredictedBall.Magnitude, predictedBallPosition
end

function BallControlMath.GetAssistBias(distanceToPredictedBall: number, manualDirection: Vector3, assistDirection: Vector3, controlConfig): number
	local bias = math.clamp(
		(distanceToPredictedBall - controlConfig.ContactAssistStartDistance)
			/ math.max(controlConfig.ContactAssistFullDistance - controlConfig.ContactAssistStartDistance, EPSILON),
		0,
		1
	) * controlConfig.ContactAssistMaxBias

	if manualDirection.Magnitude > EPSILON and manualDirection:Dot(assistDirection) < controlConfig.ContactAssistReverseDot then
		bias = math.min(bias, controlConfig.ContactAssistReverseBias)
	end

	return bias
end

function BallControlMath.BlendManualAndAssistDirection(
	manualDirection: Vector3,
	assistDirection: Vector3,
	assistBias: number
): Vector3
	local manual = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(manualDirection), Vector3.zero)
	local assist = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(assistDirection), manual)

	if manual.Magnitude <= EPSILON then
		return Vector3.zero
	end

	local blended = manual * (1 - assistBias) + assist * assistBias
	return BallControlMath.SafeUnit(blended, manual)
end

function BallControlMath.GetPlannedContact(
	rootPosition: Vector3,
	rootVelocity: Vector3,
	controlDirection: Vector3,
	playerSpeed: number,
	isSprinting: boolean,
	controlConfig
)
	local horizontalDirection = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(controlDirection), Vector3.zAxis)
	local horizontalPlayerVelocity = BallControlMath.GetHorizontal(rootVelocity)
	local contactStartPosition = rootPosition + horizontalPlayerVelocity * controlConfig.ContactStartPredictionTime
	local futureDelay = BallControlMath.GetFutureContactDelay(playerSpeed, controlConfig)
	local frontOffset = BallControlMath.GetFrontOfFootOffset(playerSpeed, controlConfig)
	local plannedMovement = horizontalPlayerVelocity * futureDelay
	local plannedPosition = contactStartPosition + plannedMovement + horizontalDirection * frontOffset
	local maxDistance = if isSprinting
		then controlConfig.MaximumSprintPlannedDistance
		else controlConfig.MaximumWalkPlannedDistance
	local fromRoot = BallControlMath.GetHorizontal(plannedPosition - rootPosition)

	if fromRoot.Magnitude > maxDistance then
		plannedPosition = rootPosition + fromRoot.Unit * maxDistance
	end

	return {
		Position = plannedPosition,
		FutureDelay = futureDelay,
		FrontOffset = frontOffset,
		ContactStartPosition = contactStartPosition,
	}
end

function BallControlMath.GetDesiredContactVelocity(
	ballPosition: Vector3,
	ballVelocity: Vector3,
	rootVelocity: Vector3,
	controlDirection: Vector3,
	playerSpeed: number,
	isSprinting: boolean,
	plannedContact,
	controlConfig
)
	local horizontalDirection = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(controlDirection), Vector3.zAxis)
	local playerHorizontalVelocity = BallControlMath.GetHorizontal(rootVelocity)
	local ballHorizontalVelocity = BallControlMath.GetHorizontal(ballVelocity)
	local toPlannedBall = BallControlMath.GetHorizontal(plannedContact.Position - ballPosition)
	local travelTime = math.max(plannedContact.FutureDelay + controlConfig.ContactTravelTimePadding, EPSILON)
	local desiredDirection = BallControlMath.SafeUnit(toPlannedBall, horizontalDirection)
	local rawDesiredSpeed = toPlannedBall.Magnitude / travelTime
	local playerForwardSpeed = math.max(0, playerHorizontalVelocity:Dot(horizontalDirection))
	local speedAlpha = math.clamp(playerSpeed / math.max(controlConfig.SprintReferenceSpeed, EPSILON), 0, 1)
	local maxOverdrive = controlConfig.WalkOverdrive
		+ (controlConfig.SprintOverdrive - controlConfig.WalkOverdrive) * (speedAlpha ^ controlConfig.OverdriveSpeedExponent)

	if isSprinting then
		maxOverdrive = math.max(maxOverdrive, controlConfig.WalkOverdrive)
	end

	local maxAllowedSpeed = math.max(
		playerForwardSpeed,
		math.min(playerForwardSpeed + maxOverdrive, controlConfig.MaxControlledBallSpeed)
	)
	local desiredSpeed = math.clamp(
		rawDesiredSpeed,
		playerForwardSpeed,
		maxAllowedSpeed
	)
	local desiredHorizontalVelocity = desiredDirection * desiredSpeed
	local desiredForwardSpeed = desiredHorizontalVelocity:Dot(horizontalDirection)

	if desiredForwardSpeed < playerForwardSpeed then
		desiredHorizontalVelocity += horizontalDirection * (playerForwardSpeed - desiredForwardSpeed)
		desiredForwardSpeed = playerForwardSpeed
	end

	if desiredHorizontalVelocity.Magnitude > maxAllowedSpeed then
		local lateralVelocity = desiredHorizontalVelocity - horizontalDirection * desiredForwardSpeed
		local maxLateralSpeed = math.sqrt(math.max(maxAllowedSpeed ^ 2 - desiredForwardSpeed ^ 2, 0))
		lateralVelocity = BallControlMath.ClampMagnitude(lateralVelocity, maxLateralSpeed)
		desiredHorizontalVelocity = horizontalDirection * desiredForwardSpeed + lateralVelocity
	end

	return {
		DesiredHorizontalVelocity = desiredHorizontalVelocity,
		CurrentHorizontalVelocity = ballHorizontalVelocity,
		ToPlannedBall = toPlannedBall,
		RawDesiredSpeed = rawDesiredSpeed,
		PlayerForwardSpeed = playerForwardSpeed,
		MaxOverdrive = maxOverdrive,
		TravelTime = travelTime,
		PlannedPosition = plannedContact.Position,
	}
end

function BallControlMath.GetStationaryControlVelocity(
	rootPosition: Vector3,
	ballPosition: Vector3,
	ballVelocity: Vector3,
	controlDirection: Vector3,
	controlConfig
)
	local horizontalDirection = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(controlDirection), Vector3.zAxis)
	local targetPosition = rootPosition + horizontalDirection * controlConfig.StationaryLeadDistance
	local positionError = BallControlMath.GetHorizontal(targetPosition - ballPosition)
	local desiredHorizontalVelocity = positionError * controlConfig.StationaryFollowGain

	return {
		DesiredHorizontalVelocity = BallControlMath.ClampMagnitude(desiredHorizontalVelocity, controlConfig.MaxControlledBallSpeed),
		CurrentHorizontalVelocity = BallControlMath.GetHorizontal(ballVelocity),
		PositionError = positionError,
		TargetError = positionError.Magnitude,
	}
end

return BallControlMath
