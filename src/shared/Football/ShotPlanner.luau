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

--[[
	Pick the LATERAL target zone.

	Deterministic (§67). The zone comes from where the player is aiming and, when
	they are not aiming anywhere in particular, from where the goalkeeper is NOT.
	It used to be `lateralZones[math.random(...)]`, which meant a Shooting Skill
	of 100 still scattered shots across the goal -- the requirement that skill 100
	adds no random deviation cannot hold while the TARGET itself is a dice roll.

	Choosing the far side of the keeper is assistance with EXECUTION, not with the
	decision: the player has already chosen to shoot and roughly where. It never
	overrides a clear aim.
]]
local function selectLateralAlpha(lateralIntent: number, zones, goal, goalkeeperPosition: Vector3?, config): number
	local placement = config.Placement

	-- A clear aim picks the nearest zone to that aim, so intent is preserved.
	if math.abs(lateralIntent) >= placement.ClearIntentThreshold then
		local best, bestDistance = zones[1], math.huge
		for _, zone in zones do
			local distance = math.abs(zone - lateralIntent)
			if distance < bestDistance then
				best, bestDistance = zone, distance
			end
		end
		-- Blend toward the raw aim so a player can place between zones.
		return best * (1 - placement.IntentZoneInfluence) + lateralIntent * placement.IntentZoneInfluence
	end

	--[[
		No clear aim. Shoot away from the keeper: the zone whose position inside
		the goal mouth is furthest from where the keeper is standing.
	]]
	if goalkeeperPosition then
		local keeperAlpha = (goalkeeperPosition - goal.MouthCenter):Dot(goal.WidthAxis) / math.max(goal.Width * 0.5, 1e-3)
		local best, bestDistance = zones[1], -math.huge
		for _, zone in zones do
			local distance = math.abs(zone - keeperAlpha)
			if distance > bestDistance then
				best, bestDistance = zone, distance
			end
		end
		return best
	end

	-- No keeper either: down the middle, which is at least honest.
	return 0
end

--[[
	Pick the HEIGHT zone (§66).

	Shots were arriving as almost-flat ground missiles because the height zones
	only reached 0.6 of the goal and were picked at random. Height is now chosen
	from real football reasoning:

	  - distance: a shot from range needs elevation to clear bodies and drop in
	  - the keeper: a keeper off its line or advancing invites a raised finish
	  - shot type: a finesse/placed shot is lifted, a driven shot is kept low

	Deterministic, so Shooting Skill 100 has no vertical scatter either.
]]
local function selectHeightAlpha(distance: number, goal, goalkeeperPosition: Vector3?, chargePower: number, config): number
	local placement = config.Placement
	local zones = placement.HeightZones

	-- Range term: further out means higher.
	local rangeAlpha = math.clamp(distance / math.max(config.ReferenceDistance, 1), 0, 1)
	local index = 1 + rangeAlpha * (#zones - 1)

	--[[
		A hard-struck shot stays lower; a placed one is lifted. Charge is the
		player's own power choice, so this keeps the shot type in their hands.
	]]
	local chargeConfig = config.Charge
	local powerAlpha = math.clamp(
		(chargePower - chargeConfig.MinimumPower) / math.max(chargeConfig.MaximumPower - chargeConfig.MinimumPower, 1e-3),
		0,
		1
	)
	index -= powerAlpha * placement.DrivenHeightReduction

	-- A keeper standing well off its line is beaten over the top.
	if goalkeeperPosition then
		local advance = (goalkeeperPosition - goal.MouthCenter).Magnitude
		index += math.clamp(advance / math.max(placement.KeeperAdvanceReference, 1), 0, 1)
			* placement.KeeperAdvanceHeightBonus
	end

	index = math.clamp(index, 1, #zones)
	-- Interpolate between zones so height is continuous rather than stepped.
	local lower = math.floor(index)
	local upper = math.min(lower + 1, #zones)
	local blend = index - lower
	return zones[lower] * (1 - blend) + zones[upper] * blend
end

--[[
	FINESSE / CURVE (§69).

	A placed shot into the far corner bends; a driven shot does not. The curve is
	a constant lateral acceleration decided HERE, at release, and handed to the
	ball -- never a force that tracks the goal.

	Two things scale it, and both are the player's own choices:

	  - how far across the goal they are placing it (the bend that makes a
	    far-corner finish possible from an angle)
	  - how little power they used (a driven shot has no time to bend)

	Skill scales it too, because bending a ball is a technique. At skill 0 there
	is no curve at all -- a poor finisher simply hits it straight.
]]
local function resolveCurve(goal, lateralAlpha: number, chargePower: number, skill: number, config): Vector3
	local finesse = config.Finesse
	if finesse.Enabled ~= true then
		return Vector3.zero
	end
	local chargeConfig = config.Charge
	local powerAlpha = math.clamp(
		(chargePower - chargeConfig.MinimumPower) / math.max(chargeConfig.MaximumPower - chargeConfig.MinimumPower, 1e-3),
		0,
		1
	)
	-- A placed shot (low power) bends most.
	local placement = 1 - powerAlpha * finesse.PowerSuppression
	local magnitude = finesse.MaximumAcceleration
		* math.clamp(math.abs(lateralAlpha) / math.max(finesse.FullBendAlpha, 1e-3), 0, 1)
		* placement
		* math.clamp(skill, 0, 1)

	if magnitude < finesse.MinimumAcceleration then
		return Vector3.zero
	end
	--[[
		Bend BACK toward the middle of the goal from the side it was placed to --
		the inswinging shape of a real placed finish. Because the vector is fixed
		at release, a shot aimed too wide still misses; the bend does not rescue
		it.
	]]
	local sign = if lateralAlpha >= 0 then -1 else 1
	return goal.WidthAxis * (magnitude * sign)
end

function ShotPlanner.Plan(
	origin: Vector3,
	aimDirection: Vector3,
	goal,
	ballRadius: number,
	config,
	shootingSkill: number?,
	bodyFacingDirection: Vector3?,
	goalkeeperPosition: Vector3?,
	chargePower: number?
)
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

	local skillConfig = config.Skill
	local skill = math.clamp(shootingSkill or skillConfig.Default, skillConfig.Minimum, skillConfig.Maximum)
	local charge = chargePower or config.Charge.MaximumPower

	local margin = config.GoalSafetyMargin + ballRadius + skillConfig.HighSkillSafetyMargin
	local usableHalfWidth = math.max(0, goal.Width / 2 - margin)
	local usableHeight = math.max(0, goal.Height - margin * 2)

	--[[
		WHERE IS THE PLAYER AIMING, AT THE GOAL? (§68)

		This is measured by projecting the aim ray forward to the GOAL PLANE and
		asking where it crosses, as a fraction of the usable half-width.

		It used to be the raw direction ratio `aim . widthAxis / forwardAlignment`,
		which is a completely different quantity: it shrinks with distance. Aiming
		at the far post from 60 studs produced a ratio of only 0.13 -- under the
		"is the player aiming anywhere in particular" threshold -- so the shot fell
		through to the centre. Measured across the goal, aiming at -0.45, 0 and
		+0.45 all produced the SAME target: dead centre. Which is precisely the
		"shots always target goal centre" behaviour §68 exists to remove.

		Projected at the plane, aiming at a post means aiming at that post from any
		range.
	]]
	local lateralAtGoal = (aim:Dot(goal.WidthAxis) / forwardAlignment) * distance
	local lateralIntent = math.clamp(lateralAtGoal / math.max(usableHalfWidth, 1e-3), -1, 1)

	--[[
		TARGET (§67, §68). Both zones are now chosen deterministically from the
		player's aim, the situation and the keeper. Nothing about the INTENDED
		target is random any more, so at Shooting Skill 100 the only thing between
		intent and outcome is physical contact and the goalkeeper.
	]]
	local intendedLateralAlpha = selectLateralAlpha(
		lateralIntent,
		config.Placement.LateralZones,
		goal,
		goalkeeperPosition,
		config
	)
	local intendedHeightAlpha = selectHeightAlpha(distance, goal, goalkeeperPosition, charge, config)

	local intendedTarget = goal.MouthCenter + goal.WidthAxis * (usableHalfWidth * intendedLateralAlpha)
	intendedTarget = Vector3.new(
		intendedTarget.X,
		goal.BottomY + margin + usableHeight * intendedHeightAlpha,
		intendedTarget.Z
	)

	--[[
		ERROR. Skill error is zero at skill 1 (§67); body-alignment error is a
		physical consequence of shooting off balance and remains for everyone,
		which is deliberate -- it is not a skill deficiency, it is the shot being
		taken from a bad body position.
	]]
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

	--[[
		LAUNCH (§65). Speed scales with distance so a long shot still arrives,
		and the vertical component is solved from the SAME flight time as the
		horizontal travel -- clamping them independently is what previously made
		long shots arrive below their chosen point.
	]]
	local speedAlpha = math.clamp(distance / math.max(config.ReferenceDistance, 1), 0, 1)
	local baseHorizontalSpeed = config.MinLaunchSpeed
		+ (config.MaxLaunchSpeed - config.MinLaunchSpeed) * math.sqrt(speedAlpha)
	local travelTime = distance / math.max(baseHorizontalSpeed, 1) * (config.FlightTimeScale or 1)
	local horizontalSpeed = distance / math.max(travelTime, 0.01)
	local flightGravity = BallConfig.Flight and BallConfig.Flight.EffectiveGravity or Workspace.Gravity

	local curveAcceleration = resolveCurve(goal, intendedLateralAlpha, charge, skill, config)

	--[[
		Aim OFF the curve. The ball will be pushed sideways by a known constant
		acceleration for a known flight time, so the launch direction is offset by
		exactly that displacement -- which is why a curved shot still arrives on
		its chosen target instead of bending away from it.
	]]
	local curveDrift = curveAcceleration * (0.5 * travelTime * travelTime)
	local aimPoint = target - curveDrift

	local verticalSpeed = (aimPoint.Y - origin.Y + 0.5 * flightGravity * travelTime * travelTime) / travelTime
	local launchDirection = BallControlMath.SafeUnit(horizontal(aimPoint - origin), centerDirection)
	local launchVelocity = launchDirection * horizontalSpeed + Vector3.yAxis * verticalSpeed

	return {
		ActionType = "Shoot",
		Goal = goal,
		GoalId = goal.Id,
		TargetPosition = target,
		IntendedGoalTarget = intendedTarget,
		FinalGoalTarget = target,
		IntendedLateralAlpha = intendedLateralAlpha,
		IntendedHeightAlpha = intendedHeightAlpha,
		HorizontalError = lateralError,
		VerticalError = verticalError,
		SkillHorizontalError = skillLateralError,
		SkillVerticalError = skillVerticalError,
		AlignmentHorizontalError = alignmentLateralError,
		AlignmentVerticalError = alignmentVerticalError,
		BodyAlignment = bodyAlignment,
		AlignmentErrorAlpha = alignmentErrorAlpha,
		CurveAcceleration = curveAcceleration,
		IsFinesse = curveAcceleration.Magnitude > 1e-3,
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
