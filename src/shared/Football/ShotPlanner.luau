local Workspace = game:GetService("Workspace")

local BallControlMath = require(script.Parent.BallControlMath)
local BallConfig = require(script.Parent.Parent.Config.BallConfig)

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

function ShotPlanner.Plan(origin: Vector3, aimDirection: Vector3, goal, ballRadius: number, config, shootingSkill: number?, bodyFacingDirection: Vector3?)
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
	local skillLateralError = (math.random() * 2 - 1) * skillConfig.MaximumLateralErrorStuds * errorScale
	local skillVerticalError = (math.random() * 2 - 1) * skillConfig.MaximumVerticalErrorStuds * errorScale
	local alignmentConfig = config.Alignment or {}
	local bodyFacing = BallControlMath.SafeUnit(horizontal(bodyFacingDirection or aim), centerDirection)
	local bodyAlignment = math.clamp(bodyFacing:Dot(centerDirection), -1, 1)
	local alignmentErrorAlpha = math.clamp(
		((alignmentConfig.FullAccuracyDot or 0.92) - bodyAlignment)
			/ math.max((alignmentConfig.FullAccuracyDot or 0.92) - (alignmentConfig.MaximumErrorDot or -0.65), 0.01),
		0,
		1
	)
	alignmentErrorAlpha = math.pow(alignmentErrorAlpha, alignmentConfig.ErrorExponent or 1)
	local alignmentLateralError = (math.random() * 2 - 1)
		* (alignmentConfig.MaximumLateralErrorStuds or 0) * alignmentErrorAlpha
	local alignmentVerticalError = (math.random() * 2 - 1)
		* (alignmentConfig.MaximumVerticalErrorStuds or 0) * alignmentErrorAlpha
	local lateralError = skillLateralError + alignmentLateralError
	local verticalError = skillVerticalError + alignmentVerticalError
	local target = intendedTarget + goal.WidthAxis * lateralError + Vector3.yAxis * verticalError
	local finalLateralOffset = (target - goal.MouthCenter):Dot(goal.WidthAxis)
	local onTarget = math.abs(finalLateralOffset) <= goal.Width / 2 - ballRadius
		and target.Y >= goal.BottomY + ballRadius
		and target.Y <= goal.TopY - ballRadius

	local speedAlpha = math.clamp(distance / math.max(config.ReferenceDistance, 1), 0, 1)
	local baseHorizontalSpeed = config.MinLaunchSpeed + (config.MaxLaunchSpeed - config.MinLaunchSpeed) * math.sqrt(speedAlpha)
	-- Vertical launch must use the same physical arrival time as horizontal travel.
	-- Clamping this independently made long shots arrive below their selected goal point.
	local travelTime = distance / math.max(baseHorizontalSpeed, 1) * (config.FlightTimeScale or 1)
	local horizontalSpeed = distance / math.max(travelTime, 0.01)
	local flightGravity = BallConfig.Flight and BallConfig.Flight.EffectiveGravity or Workspace.Gravity
	local verticalSpeed = (target.Y - origin.Y + 0.5 * flightGravity * travelTime * travelTime) / travelTime
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
		SkillHorizontalError = skillLateralError,
		SkillVerticalError = skillVerticalError,
		AlignmentHorizontalError = alignmentLateralError,
		AlignmentVerticalError = alignmentVerticalError,
		BodyAlignment = bodyAlignment,
		AlignmentErrorAlpha = alignmentErrorAlpha,
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

function ShotPlanner.PlanClearance(origin: Vector3, aimDirection: Vector3, attackingDirection: Vector3, config)
	local clearance = config.Clearance
	local forward = BallControlMath.SafeUnit(horizontal(attackingDirection), Vector3.new(0, 0, -1))
	local aim = BallControlMath.SafeUnit(horizontal(aimDirection), forward)
	local lateralAxis = Vector3.yAxis:Cross(forward).Unit
	local aimLateral = math.clamp(aim:Dot(lateralAxis), -1, 1) * (clearance.AimLateralInfluence or 0)
	local randomLateral = (math.random() * 2 - 1) * (clearance.RandomLateralSpread or 0)
	local direction = BallControlMath.SafeUnit(forward + lateralAxis * (aimLateral + randomLateral), forward)
	local flightTime = math.max(clearance.FlightTime or 0, 0)
	local flightGravity = BallConfig.Flight and BallConfig.Flight.EffectiveGravity or Workspace.Gravity
	local horizontalSpeed = if flightTime > 0 then clearance.TargetDistance / flightTime else clearance.HorizontalSpeed
	local verticalSpeed = if flightTime > 0 then 0.5 * flightGravity * flightTime else clearance.VerticalSpeed
	local launchVelocity = direction * horizontalSpeed + Vector3.yAxis * verticalSpeed
	return {
		ActionType = "Clearance",
		GoalId = "",
		TargetPosition = origin + direction * clearance.TargetDistance,
		LaunchVelocity = launchVelocity,
		LaunchSpeed = launchVelocity.Magnitude,
		HorizontalLaunchSpeed = horizontalSpeed,
		VerticalLaunchSpeed = verticalSpeed,
		Distance = clearance.TargetDistance,
		PredictedArrivalTime = if flightTime > 0 then flightTime else clearance.TargetDistance / horizontalSpeed,
		PredictedArrivalSpeed = horizontalSpeed,
		Intensity = 1,
		Score = 0,
		ShootingSkill = 0,
		Trajectory = "Clearance",
	}
end

return ShotPlanner
