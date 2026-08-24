local BallControlMath = require(script.Parent.BallControlMath)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Workspace = game:GetService("Workspace")

local PassPlanner = {}

local EPSILON = 1e-4

function PassPlanner.GetMaximumTargetRange(config): number
	local gameRoot = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local pitchFolder = gameRoot and gameRoot:FindFirstChild("Pitch")
	local gameplayBounds = pitchFolder and pitchFolder:FindFirstChild("GameplayBounds")
	local pitchLength = gameplayBounds and gameplayBounds:GetAttribute("PitchLength")
	if typeof(pitchLength) == "number" and pitchLength > 0 then
		return pitchLength * config.Targeting.PitchLengthRangeScale
	end
	return config.Targeting.FallbackMaxTargetRange
end

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

local function getCandidatePosition(candidate): Vector3?
	if typeof(candidate.Position) == "Vector3" and isFiniteVector(candidate.Position) then
		return candidate.Position
	end

	return nil
end

local function getCandidateVelocity(candidate): Vector3
	if typeof(candidate.Velocity) == "Vector3" and isFiniteVector(candidate.Velocity) then
		return getHorizontal(candidate.Velocity)
	end

	return Vector3.zero
end

local function getCandidateFacing(candidate): Vector3
	if typeof(candidate.FacingDirection) == "Vector3" and isFiniteVector(candidate.FacingDirection) then
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

local function getLaunchVelocity(
	origin: Vector3,
	target: Vector3,
	actionConfig,
	intensity: number
): (Vector3, number, number, number)
	local toTarget = getHorizontal(target - origin)
	local distance = toTarget.Magnitude
	local direction = safeUnit(toTarget, Vector3.zAxis)
	local distanceAlpha = math.clamp(
		(distance - actionConfig.MinDistance) / math.max(actionConfig.MaxDistance - actionConfig.MinDistance, EPSILON),
		0,
		1
	)
	local travelTime = actionConfig.TravelTimeMin
		+ (actionConfig.TravelTimeMax - actionConfig.TravelTimeMin) * math.sqrt(distanceAlpha)
	local arrivalAlpha = distanceAlpha * distanceAlpha * (3 - 2 * distanceAlpha)
	local desiredArrivalSpeed = actionConfig.ArrivalSpeed
		+ ((actionConfig.LongArrivalSpeed or actionConfig.ArrivalSpeed) - actionConfig.ArrivalSpeed) * arrivalAlpha
	local rollingDeceleration = actionConfig.EstimatedRollingDeceleration or 0
	local etaDrivenSpeed = distance / math.max(travelTime, EPSILON) + 0.5 * rollingDeceleration * travelTime
	local arrivalDrivenSpeed = desiredArrivalSpeed + rollingDeceleration * travelTime
	local speed = math.clamp(
		math.max(etaDrivenSpeed, arrivalDrivenSpeed) * intensity,
		actionConfig.MinLaunchSpeed,
		actionConfig.MaxLaunchSpeed * math.max(intensity, 1)
	)
	local discriminant = math.max(0, speed * speed - 2 * rollingDeceleration * distance)
	local predictedArrivalSpeed = math.sqrt(discriminant)
	if rollingDeceleration > EPSILON then
		travelTime = (speed - predictedArrivalSpeed) / rollingDeceleration
	else
		travelTime = distance / math.max(speed, EPSILON)
	end
	local liftStart = actionConfig.LiftStartDistance or math.huge
	local liftFull = math.max(actionConfig.LiftFullDistance or liftStart, liftStart + EPSILON)
	local liftAlpha = math.clamp((distance - liftStart) / (liftFull - liftStart), 0, 1)
	liftAlpha = liftAlpha * liftAlpha * (3 - 2 * liftAlpha)
	local verticalSpeed = actionConfig.GroundLiftSpeed
		+ ((actionConfig.LongLiftSpeed or actionConfig.GroundLiftSpeed) - actionConfig.GroundLiftSpeed) * liftAlpha

	return direction * speed + Vector3.yAxis * verticalSpeed, speed, travelTime, predictedArrivalSpeed
end

function PassPlanner.Plan(
	origin: Vector3,
	aimDirection: Vector3,
	holdDuration: number,
	actionType: string,
	candidates: { any },
	config,
	intensity: number?,
	requiredReceiverUserId: number?,
	intentConeOverride: number?
)
	if not isFiniteVector(origin) then
		return nil, "invalid origin"
	end
	if not isFiniteVector(aimDirection) then
		return nil, "invalid aim direction"
	end

	local sourceActionConfig = if actionType == "ThroughPass"
		then config.ThroughPass
		elseif actionType == "LobPass"
		then config.LobPass
		else config.Pass
	local actionConfig = table.clone(sourceActionConfig)
	actionConfig.MaxDistance = PassPlanner.GetMaximumTargetRange(config)
	if intentConeOverride then
		actionConfig.IntentConeDegrees = intentConeOverride
	end
	local intensityConfig = config.DevelopmentIntensity
	local safeIntensity = if actionConfig.PowerMode == "DistanceDerived"
		then 1
		elseif typeof(intensity) == "number"
		then math.clamp(intensity, intensityConfig.Min, intensityConfig.Max)
		else 1
	local normalizedAim = safeUnit(aimDirection, Vector3.zAxis)
	local bestPlan = nil

	for _, candidate in candidates do
		if requiredReceiverUserId and requiredReceiverUserId ~= 0 and candidate.UserId ~= requiredReceiverUserId then
			continue
		end

		local candidatePlan = scoreCandidate(origin, normalizedAim, candidate, actionType, actionConfig)

		if candidatePlan and (not bestPlan or candidatePlan.Score > bestPlan.Score) then
			bestPlan = candidatePlan
		end
	end

	if not bestPlan then
		return nil, "no valid receiver"
	end

	local selectedCandidate = bestPlan.Candidate
	local targetPosition = bestPlan.TargetPosition
	local score = bestPlan.Score
	local leadTime = bestPlan.LeadTime

	local launchVelocity, launchSpeed, predictedArrivalTime, predictedArrivalSpeed = getLaunchVelocity(
		origin,
		targetPosition,
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
		VerticalLaunchSpeed = launchVelocity.Y,
		Trajectory = if launchVelocity.Y > actionConfig.GroundLiftSpeed + 0.5 then "DrivenLift" else "Ground",
		Intensity = safeIntensity,
		ReceiverLeadTime = leadTime,
		AngleDegrees = bestPlan.AngleDegrees,
		Score = score,
		Distance = getHorizontal(targetPosition - origin).Magnitude,
		ReceiverRadius = actionConfig.ReceiverRadius,
		ReleaseReacquireSuppression = actionConfig.ReleaseReacquireSuppression,
		ReleaseReacquireExitDistance = actionConfig.ReacquireExitDistance,
	}, nil
end

function PassPlanner.PlanForReceiver(
	origin: Vector3,
	aimDirection: Vector3,
	holdDuration: number,
	actionType: string,
	candidate,
	config,
	intensity: number?,
	retentionConeDegrees: number?
)
	if not candidate then
		return nil, "receiver-missing"
	end
	return PassPlanner.Plan(
		origin,
		aimDirection,
		holdDuration,
		actionType,
		{ candidate },
		config,
		intensity,
		candidate.UserId,
		retentionConeDegrees or config.Targeting.RetentionConeDegrees
	)
end

return PassPlanner
