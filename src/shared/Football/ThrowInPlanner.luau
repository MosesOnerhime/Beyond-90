--!strict
--[[
	Throw-ins.

	A throw-in is not a pass taken from the ground. It leaves the thrower's hands
	above their head, travels as a genuine ballistic arc, and is aimed at a
	team-mate rather than at empty space (§32-§34).

	Two things are deliberately separated here:

		WHO the throw is aimed at   -> the player's choice, preserved
		HOW FAR / HARD it is thrown -> the hold duration

	The player still decides the football decision; hold length only shapes the
	execution of it, which is the distinction AGENTS.md §2 requires. Hold is used
	to CHOOSE a receiver only when the player has not selected one, and even then
	it chooses among legal team-mates rather than throwing into space.

	Pure module: no services, no Workspace, no state.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallControlMath = require(ReplicatedStorage.Shared.Football.BallControlMath)

local ThrowInPlanner = {}

local function horizontal(vector: Vector3): Vector3
	return BallControlMath.GetHorizontal(vector)
end

--[[
	How far the thrower is trying to throw, from how long Pass was held.

	A tap is a short throw to the nearest option; a full hold is a long throw
	down the line. The curve is deliberately gentle so the middle of the range is
	usable rather than being a narrow band between two extremes.
]]
function ThrowInPlanner.GetDesiredDistance(holdDuration: number, config): number
	local alpha = math.clamp(holdDuration / math.max(config.HoldMaxTime, 1e-3), 0, 1)
	alpha = math.pow(alpha, config.HoldCurveExponent or 1)
	return config.MinDistance + (config.MaxDistance - config.MinDistance) * alpha
end

--[[
	Choose the receiver.

	`candidates` are already filtered to legal team-mates by the caller. Each is
	`{ Id, Name, Position, Velocity, UserId }`.

	`selectedId` is who the player aimed at, if anyone. It wins whenever it is a
	legal option -- that is the player's football decision and the throw must not
	override it. Otherwise the team-mate whose distance best matches the hold is
	chosen, with aim direction breaking ties.
]]
function ThrowInPlanner.SelectReceiver(
	origin: Vector3,
	aimDirection: Vector3,
	candidates,
	desiredDistance: number,
	selectedId: number?,
	config
)
	local aim = BallControlMath.SafeUnit(horizontal(aimDirection), Vector3.zAxis)
	local best, bestScore = nil, -math.huge

	for _, candidate in candidates do
		local toCandidate = horizontal(candidate.Position - origin)
		local distance = toCandidate.Magnitude
		if distance >= config.MinDistance * 0.5 and distance <= config.MaximumReach then
			--[[
				Distance match is the primary term: the whole point of the hold is
				that a longer hold reaches a further team-mate.
			]]
			local distanceError = math.abs(distance - desiredDistance)
				/ math.max(config.MaxDistance - config.MinDistance, 1)
			local score = -distanceError * (config.DistanceWeight or 1)

			local alignment = BallControlMath.SafeUnit(toCandidate, aim):Dot(aim)
			score += alignment * (config.AimWeight or 0)

			-- The player's own selection is decisive, not merely favoured.
			if selectedId and candidate.Id == selectedId then
				score += config.SelectedReceiverBonus or 10
			end

			if score > bestScore then
				best, bestScore = candidate, score
			end
		end
	end

	return best
end

--[[
	Solve the throw itself.

	Deliberately ballistic and fully determined at release: the ball is given a
	velocity and then belongs to the physics engine. Nothing steers it afterwards
	(§34), so a throw can be misjudged, intercepted or headed away exactly like a
	real one.
]]
function ThrowInPlanner.Plan(
	origin: Vector3,
	targetPosition: Vector3,
	targetVelocity: Vector3?,
	config,
	gravity: number
)
	local flat = horizontal(targetPosition - origin)
	local distance = flat.Magnitude
	if distance <= 1e-3 then
		return nil, "throw-in-target-too-close"
	end

	--[[
		Lead a moving receiver. A throw hangs in the air long enough that
		throwing at where someone currently stands consistently lands behind them.
	]]
	local flightTime = math.clamp(
		distance / math.max(config.ReferenceHorizontalSpeed, 1),
		config.MinFlightTime,
		config.MaxFlightTime
	)
	local lead = horizontal(targetVelocity or Vector3.zero) * flightTime * (config.LeadFactor or 0)
	local aimPoint = targetPosition + lead
	aimPoint = Vector3.new(aimPoint.X, targetPosition.Y + config.ReceiveHeight, aimPoint.Z)

	flat = horizontal(aimPoint - origin)
	distance = flat.Magnitude
	flightTime = math.clamp(
		distance / math.max(config.ReferenceHorizontalSpeed, 1),
		config.MinFlightTime,
		config.MaxFlightTime
	)

	local horizontalSpeed = distance / flightTime
	-- Standard projectile solve for the vertical component: whatever launch speed
	-- puts the ball at the receiver's chest exactly when it arrives.
	local verticalSpeed = ((aimPoint.Y - origin.Y) + 0.5 * gravity * flightTime * flightTime) / flightTime

	local direction = BallControlMath.SafeUnit(flat, Vector3.zAxis)
	local launchVelocity = direction * horizontalSpeed + Vector3.yAxis * verticalSpeed

	return {
		ActionType = "ThrowIn",
		TargetPosition = aimPoint,
		LaunchVelocity = launchVelocity,
		LaunchSpeed = launchVelocity.Magnitude,
		HorizontalLaunchSpeed = horizontalSpeed,
		VerticalLaunchSpeed = verticalSpeed,
		Distance = distance,
		PredictedArrivalTime = flightTime,
		PredictedArrivalSpeed = horizontalSpeed,
		Trajectory = "Throw",
	}, nil
end

--[[
	No legal receiver.

	A throw-in must not simply be thrown straight back out of play. With nobody
	to aim at, the ball is thrown a short, safe distance INFIELD, perpendicular to
	the touchline -- the same thing a real player does under pressure.
]]
function ThrowInPlanner.PlanSafeFallback(origin: Vector3, infieldDirection: Vector3, config, gravity: number)
	local direction = BallControlMath.SafeUnit(horizontal(infieldDirection), Vector3.zAxis)
	local target = origin + direction * config.SafeFallbackDistance
	return ThrowInPlanner.Plan(
		origin,
		Vector3.new(target.X, origin.Y - config.ReleaseHeight, target.Z),
		nil,
		config,
		gravity
	)
end

return ThrowInPlanner
