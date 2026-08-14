local BallControlMath = require(script.Parent.BallControlMath)

local PassPlanner = {}

local EPSILON = 1e-4

local function getHorizontal(vector: Vector3): Vector3
	return BallControlMath.GetHorizontal(vector)
end

local function safeUnit(vector: Vector3, fallback: Vector3?): Vector3
	return BallControlMath.SafeUnit(getHorizontal(vector), fallback or Vector3.zAxis)
end

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector(vector: Vector3): boolean
	return isFiniteNumber(vector.X) and isFiniteNumber(vector.Y) and isFiniteNumber(vector.Z)
end

local function getHoldAlpha(holdDuration: number, actionConfig): number
	return math.clamp(holdDuration / math.max(actionConfig.HoldMaxTime, EPSILON), 0, 1)
end

local function getCandidatePosition(candidate): Vector3?
	if typeof(candidate.Position) == "Vector3" then
		return candidate.Position
	end

	return nil
end

local function getCandidateVelocity(candidate): Vector3
	if typeof(candidate.Velocity) == "Vector3" then
		return getHorizontal(candidate.Velocity)
	end

	return Vector3.zero
end

local function getCandidateFacing(candidate): Vector3
	if typeof(candidate.FacingDirection) == "Vector3" then
		return safeUnit(candidate.FacingDirection, Vector3.zAxis)
	end

	return Vector3.zAxis
end

local function getReceivingDirection(candidate, aimDirection: Vector3): Vector3
	local velocity = getCandidateVelocity(candidate)

	if velocity.Magnitude > 1 then
		return velocity.Unit
	end

	local facing = getCandidateFacing(candidate)

	if facing.Magnitude > 0 then
		return facing
	end

	return aimDirection
end

local function getPredictedTarget(origin: Vector3, aimDirection: Vector3, candidate, actionType: string, actionConfig)
	local candidatePosition = getCandidatePosition(candidate)

	if not candidatePosition then
		return nil
	end

	local distance = getHorizontal(candidatePosition - origin).Magnitude
	local leadTime = math.clamp(
		actionConfig.BaseLeadTime + distance * actionConfig.LeadTimePerStud,
		actionConfig.MinLeadTime,
		actionConfig.MaxLeadTime
	)
	local receiverDirection = getReceivingDirection(candidate, aimDirection)
	local receiverLead = if getCandidateVelocity(candidate).Magnitude > 1
		then actionConfig.MovingReceiveLead
		else actionConfig.StationaryReceiveLead
	local target = candidatePosition + getCandidateVelocity(candidate) * leadTime + receiverDirection * receiverLead

	if actionType == "ThroughPass" then
		local throughLead = math.clamp(
			distance * actionConfig.LeadDistanceScale,
			actionConfig.LeadDistanceMin,
			actionConfig.LeadDistanceMax
		)
		target += aimDirection * throughLead
	end

	return target, leadTime
end

local function scoreCandidate(origin: Vector3, aimDirection: Vector3, candidate, actionType: string, actionConfig)
	local target, leadTime = getPredictedTarget(origin, aimDirection, candidate, actionType, actionConfig)

	if not target then
		return nil
	end

	local toTarget = getHorizontal(target - origin)
	local distance = toTarget.Magnitude

	if distance < actionConfig.MinDistance or distance > actionConfig.MaxDistance then
		return nil
	end

	local targetDirection = safeUnit(toTarget, aimDirection)
	local dot = math.clamp(targetDirection:Dot(aimDirection), -1, 1)
	local angleDegrees = math.deg(math.acos(dot))

	if angleDegrees > actionConfig.IntentConeDegrees then
		return nil
	end

	local angleScore = 1 - angleDegrees / math.max(actionConfig.IntentConeDegrees, EPSILON)
	local idealDistance = (actionConfig.MinDistance + actionConfig.MaxDistance) * 0.42
	local distanceScore = 1 - math.clamp(math.abs(distance - idealDistance) / math.max(actionConfig.MaxDistance, 1), 0, 1)
	local forwardScore = math.max(0, dot)
	local score = angleScore * actionConfig.DirectionWeight
		+ distanceScore * actionConfig.DistanceWeight
		+ forwardScore * actionConfig.ForwardWeight

	return {
		Candidate = candidate,
		TargetPosition = target,
		LeadTime = leadTime,
		Distance = distance,
		AngleDegrees = angleDegrees,
		Score = score,
	}
end

local function getDirectTarget(origin: Vector3, aimDirection: Vector3, holdDuration: number, actionConfig): Vector3
	local holdAlpha = getHoldAlpha(holdDuration, actionConfig)
	local distance = actionConfig.MinDistance
		+ (actionConfig.DirectPassDistance - actionConfig.MinDistance) * (0.35 + holdAlpha * 0.65)

	return origin + aimDirection * distance
end

local function getLaunchVelocity(
	origin: Vector3,
	target: Vector3,
	holdDuration: number,
	actionConfig,
	intensity: number
): (Vector3, number, number, number)
	local toTarget = getHorizontal(target - origin)
	local distance = toTarget.Magnitude
	local direction = safeUnit(toTarget, Vector3.zAxis)
	local holdAlpha = getHoldAlpha(holdDuration, actionConfig)
	local speedBasis = (actionConfig.MinLaunchSpeed + holdAlpha * 14) * intensity
	local travelTime = math.clamp(
		distance / math.max(speedBasis, 1),
		actionConfig.TravelTimeMin,
		actionConfig.TravelTimeMax
	)
	local speed = math.clamp(
		(distance / math.max(travelTime, EPSILON) + actionConfig.ArrivalSpeed * (0.35 + holdAlpha * 0.65)) * intensity,
		actionConfig.MinLaunchSpeed,
		actionConfig.MaxLaunchSpeed * math.max(intensity, 1)
	)
	local predictedArrivalSpeed = math.clamp(actionConfig.ArrivalSpeed * intensity, 0, speed)

	return direction * speed + Vector3.yAxis * actionConfig.GroundLiftSpeed, speed, travelTime, predictedArrivalSpeed
end

function PassPlanner.Plan(
	origin: Vector3,
	aimDirection: Vector3,
	holdDuration: number,
	actionType: string,
	candidates: { any },
	config,
	intensity: number?
)
	if not isFiniteVector(origin) then
		return nil, "invalid origin"
	end

	local actionConfig = if actionType == "ThroughPass" then config.ThroughPass else config.Pass
	local intensityConfig = config.DevelopmentIntensity
	local safeIntensity = if typeof(intensity) == "number"
		then math.clamp(intensity, intensityConfig.Min, intensityConfig.Max)
		else 1
	local normalizedAim = safeUnit(aimDirection, Vector3.zAxis)
	local bestPlan = nil

	for _, candidate in candidates do
		local candidatePlan = scoreCandidate(origin, normalizedAim, candidate, actionType, actionConfig)

		if candidatePlan and (not bestPlan or candidatePlan.Score > bestPlan.Score) then
			bestPlan = candidatePlan
		end
	end

	local targetPosition
	local selectedCandidate = nil
	local score = 0
	local leadTime = 0

	if bestPlan then
		selectedCandidate = bestPlan.Candidate
		targetPosition = bestPlan.TargetPosition
		score = bestPlan.Score
		leadTime = bestPlan.LeadTime
	else
		targetPosition = getDirectTarget(origin, normalizedAim, holdDuration, actionConfig)
	end

	local launchVelocity, launchSpeed, predictedArrivalTime, predictedArrivalSpeed = getLaunchVelocity(
		origin,
		targetPosition,
		holdDuration,
		actionConfig,
		safeIntensity
	)

	return {
		ActionType = actionType,
		SelectedCandidate = selectedCandidate,
		TargetPosition = targetPosition,
		AimDirection = normalizedAim,
		LaunchVelocity = launchVelocity,
		LaunchSpeed = launchSpeed,
		PredictedArrivalTime = predictedArrivalTime,
		PredictedArrivalSpeed = predictedArrivalSpeed,
		Intensity = safeIntensity,
		ReceiverLeadTime = leadTime,
		Score = score,
		Distance = getHorizontal(targetPosition - origin).Magnitude,
		ReceiverRadius = actionConfig.ReceiverRadius,
		ReleaseReacquireSuppression = actionConfig.ReleaseReacquireSuppression,
		ReleaseReacquireExitDistance = actionConfig.ReacquireExitDistance,
	}, nil
end

return PassPlanner
