local Workspace = game:GetService("Workspace")

local BallControlMath = require(script.Parent.BallControlMath)

local ShotPlanner = {}

local function horizontal(vector: Vector3): Vector3
	return BallControlMath.GetHorizontal(vector)
end

function ShotPlanner.ResolveAttackingGoal(origin: Vector3, aimDirection: Vector3, goals)
	local aim = BallControlMath.SafeUnit(horizontal(aimDirection), Vector3.new(0, 0, -1))
	local bestGoal = nil
	local bestScore = -math.huge
	for _, goal in goals do
		local toGoal = BallControlMath.SafeUnit(horizontal(goal.MouthCenter - origin), aim)
		local alignment = toGoal:Dot(aim)
		local distance = horizontal(goal.MouthCenter - origin).Magnitude
		local score = alignment * 4 - distance * 0.001
		if score > bestScore then
			bestGoal = goal
			bestScore = score
		end
	end
	return bestGoal, bestScore
end

function ShotPlanner.Plan(origin: Vector3, aimDirection: Vector3, goal, ballRadius: number, config, shootingSkill: number?)
	if not goal then
		return nil, "goal-unavailable"
	end
	local toCenter = horizontal(goal.MouthCenter - origin)
	local distance = toCenter.Magnitude
	if distance <= 0.1 then
		return nil, "invalid-shot-distance"
	end

	local aim = BallControlMath.SafeUnit(horizontal(aimDirection), toCenter.Unit)
	local centerDirection = toCenter.Unit
	local forwardAlignment = math.max(0.2, aim:Dot(centerDirection))
	local lateralIntent = math.clamp(aim:Dot(goal.WidthAxis) / forwardAlignment, -1, 1)
	local skillConfig = config.Skill
	local skill = math.clamp(shootingSkill or skillConfig.Default, skillConfig.Minimum, skillConfig.Maximum)
	local margin = config.GoalSafetyMargin + ballRadius + skillConfig.HighSkillSafetyMargin
	local usableHalfWidth = math.max(0, goal.Width / 2 - margin)
	local placement = config.Placement
	local lateralZones = placement.LateralZones
	local heightZones = placement.HeightZones
	local randomLateral = lateralZones[math.random(1, #lateralZones)]
	local intendedLateralAlpha = if math.abs(lateralIntent) < 0.15
		then randomLateral
		else randomLateral * (1 - placement.IntentZoneInfluence) + lateralIntent * placement.IntentZoneInfluence
	local intendedHeightAlpha = heightZones[math.random(1, #heightZones)]
	local intendedTarget = goal.MouthCenter + goal.WidthAxis * (usableHalfWidth * intendedLateralAlpha)
	local usableHeight = math.max(0, goal.Height - margin * 2)
	intendedTarget = Vector3.new(
		intendedTarget.X,
		goal.BottomY + margin + usableHeight * intendedHeightAlpha,
		intendedTarget.Z
	)
	local errorScale = math.pow(1 - skill, skillConfig.ErrorExponent or 1)
	local lateralError = (math.random() * 2 - 1) * skillConfig.MaximumLateralErrorStuds * errorScale
	local verticalError = (math.random() * 2 - 1) * skillConfig.MaximumVerticalErrorStuds * errorScale
	local target = intendedTarget + goal.WidthAxis * lateralError + Vector3.yAxis * verticalError
	local finalLateralOffset = (target - goal.MouthCenter):Dot(goal.WidthAxis)
	local onTarget = math.abs(finalLateralOffset) <= goal.Width / 2 - ballRadius
		and target.Y >= goal.BottomY + ballRadius
		and target.Y <= goal.TopY - ballRadius

	local speedAlpha = math.clamp(distance / math.max(config.ReferenceDistance, 1), 0, 1)
	local horizontalSpeed = config.MinLaunchSpeed + (config.MaxLaunchSpeed - config.MinLaunchSpeed) * math.sqrt(speedAlpha)
	local travelTime = math.clamp(distance / math.max(horizontalSpeed, 1), config.MinTravelTime, config.MaxTravelTime)
	local verticalSpeed = (target.Y - origin.Y + 0.5 * Workspace.Gravity * travelTime * travelTime) / travelTime
	local launchDirection = BallControlMath.SafeUnit(horizontal(target - origin), centerDirection)
	local launchVelocity = launchDirection * horizontalSpeed + Vector3.yAxis * verticalSpeed

	return {
		ActionType = "Shoot",
		Goal = goal,
		GoalId = goal.Id,
		TargetPosition = target,
		IntendedGoalTarget = intendedTarget,
		FinalGoalTarget = target,
		HorizontalError = lateralError,
		VerticalError = verticalError,
		Result = if onTarget then "OnTarget" else "OffTarget",
		LaunchVelocity = launchVelocity,
		LaunchSpeed = launchVelocity.Magnitude,
		HorizontalLaunchSpeed = horizontalSpeed,
		VerticalLaunchSpeed = verticalSpeed,
		Distance = distance,
		PredictedArrivalTime = travelTime,
		PredictedArrivalSpeed = horizontalSpeed,
		Intensity = 1,
		Score = 0,
		ShootingSkill = skill,
	}, nil
end

function ShotPlanner.PlanClearance(origin: Vector3, aimDirection: Vector3, config)
	local direction = BallControlMath.SafeUnit(horizontal(aimDirection), Vector3.new(0, 0, -1))
	local clearance = config.Clearance
	local launchVelocity = direction * clearance.HorizontalSpeed + Vector3.yAxis * clearance.VerticalSpeed
	return {
		ActionType = "Clearance",
		GoalId = "",
		TargetPosition = origin + direction * clearance.TargetDistance,
		LaunchVelocity = launchVelocity,
		LaunchSpeed = launchVelocity.Magnitude,
		HorizontalLaunchSpeed = clearance.HorizontalSpeed,
		VerticalLaunchSpeed = clearance.VerticalSpeed,
		Distance = clearance.TargetDistance,
		PredictedArrivalTime = clearance.TargetDistance / clearance.HorizontalSpeed,
		PredictedArrivalSpeed = clearance.HorizontalSpeed,
		Intensity = 1,
		Score = 0,
		ShootingSkill = 0,
		Trajectory = "Clearance",
	}
end

return ShotPlanner
