--!strict
--[[
	Pure goalkeeper geometry. No Instances, no side effects, no controller
	assumptions -- so a human goalkeeper can eventually consume the same maths.

	Adapted from GameplayFootball `goalie_default.cpp`:
	  - stand on the angular bisector of (ball -> post A, ball -> post B)
	  - clamp laterally to just inside the posts
	  - hold a small offset in front of the goal line, never on it
	  - bias forward along that line to narrow the angle when threatened
]]
local BallControlMath = require(script.Parent.BallControlMath)

local GoalkeeperPositioning = {}

--[[
	goal: a GoalGeometry record { MouthCenter, WidthAxis, InwardDirection, Width }

	InwardDirection points from the goal mouth INTO THE PITCH -- it is the
	direction play comes from, not the direction into the net. GoalService
	produces it that way (the Home goal at z=207 reports (0,0,-1), toward the
	centre circle). Reading it the other way round is what previously put the
	keeper inside its own net and stopped saves from ever being attempted.
]]
function GoalkeeperPositioning.GetRestingPosition(goal, ballPosition: Vector3, depthBias: number, config): Vector3
	--[[
		`goal.InwardDirection` points from the goal mouth INTO the pitch. Every
		depth term here is measured along it, so a positive depth is always on
		the playing side of the goal line.

		This previously negated it into an `outward` axis and then offset along
		that, which planted the keeper LineOffset studs BEHIND the line, inside
		the net -- where it can never reach a shot before the ball has already
		crossed. Depth is now expressed in one direction only, so the sign
		cannot be lost again.
	]]
	local pitchward = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(goal.InwardDirection),
		Vector3.zAxis
	)
	local rawWidthAxis = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(goal.WidthAxis),
		Vector3.xAxis
	)
	-- The stored width axis is not exactly perpendicular to the goal normal, so
	-- rebuilding a position from independently clamped lateral and depth terms
	-- leaks a little depth at full lateral extent. Orthogonalising first makes
	-- the two components independent and the depth guarantee exact.
	local widthAxis = BallControlMath.SafeUnit(
		rawWidthAxis - pitchward * rawWidthAxis:Dot(pitchward),
		Vector3.xAxis
	)
	local halfWidth = math.max(goal.Width * 0.5 - config.PostInset, 0.5)

	local postA = goal.MouthCenter + widthAxis * halfWidth
	local postB = goal.MouthCenter - widthAxis * halfWidth
	local ball = Vector3.new(ballPosition.X, goal.MouthCenter.Y, ballPosition.Z)

	-- The bisector of the two post directions is the line that splits the goal
	-- into equal halves as seen from the ball. It points from ball to goal, so
	-- its fallback is the goalward direction.
	local toPostA = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(postA - ball), -pitchward)
	local toPostB = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(postB - ball), -pitchward)
	local bisector = BallControlMath.SafeUnit(toPostA + toPostB, -pitchward)

	--[[
		Walk that bisector from the ball until it meets the plane held
		`LineOffset` studs in front of the line:
			(ball + bisector * t - MouthCenter) . pitchward = LineOffset
	]]
	local ballDepth = (ball - goal.MouthCenter):Dot(pitchward)
	local denominator = bisector:Dot(pitchward)
	local intersection
	if math.abs(denominator) < 1e-3 then
		intersection = goal.MouthCenter + pitchward * config.LineOffset
	else
		intersection = ball + bisector * ((config.LineOffset - ballDepth) / denominator)
	end

	-- Clamp laterally to inside the posts.
	local lateral = math.clamp((intersection - goal.MouthCenter):Dot(widthAxis), -halfWidth, halfWidth)
	local base = goal.MouthCenter + widthAxis * lateral + pitchward * config.LineOffset

	-- Depth: bias forward onto the pitch, toward the ball.
	local toBall = BallControlMath.GetHorizontal(ball - base)
	local advance = math.min(toBall.Magnitude * math.clamp(depthBias, 0, 1), config.MaximumAdvance)
	local target = base + BallControlMath.SafeUnit(toBall, pitchward) * advance

	--[[
		Re-clamp after advancing. Moving toward the ball carries a lateral
		component, so on a tight angle the keeper would otherwise finish outside
		its own post; and the depth is held between the line offset and the
		maximum advance so it can never drift back behind the line.
	]]
	local finalLateral = math.clamp((target - goal.MouthCenter):Dot(widthAxis), -halfWidth, halfWidth)
	local finalDepth = math.clamp(
		(target - goal.MouthCenter):Dot(pitchward),
		config.LineOffset,
		config.LineOffset + config.MaximumAdvance
	)
	target = goal.MouthCenter + widthAxis * finalLateral + pitchward * finalDepth

	return Vector3.new(target.X, goal.MouthCenter.Y, target.Z)
end

--[[
	Is the football on a path into this goal?
	Samples the ballistic path and tests each segment against the goal plane,
	widened by `panicScale` so marginal shots still draw a reaction.
	Returns: bound (boolean), interceptPoint (Vector3?), timeSeconds (number?)
]]
function GoalkeeperPositioning.IsBallBoundForGoal(
	goal,
	samples: { Vector3 },
	sampleDuration: number,
	panicScale: number,
	maximumHeight: number
): (boolean, Vector3?, number?)
	-- Positive on the playing side of the goal line, negative behind it.
	local pitchward = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(goal.InwardDirection),
		Vector3.zAxis
	)
	local widthAxis = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(goal.WidthAxis),
		Vector3.xAxis
	)
	local halfWidth = goal.Width * 0.5 * panicScale
	local stepTime = sampleDuration / math.max(#samples - 1, 1)
	local floorY = goal.BottomY

	for index = 1, #samples - 1 do
		local current = samples[index]
		local nextSample = samples[index + 1]
		-- A ball predicted below pitch level is rolling, not underground.
		if current.Y < floorY then
			current = Vector3.new(current.X, floorY, current.Z)
		end
		if nextSample.Y < floorY then
			nextSample = Vector3.new(nextSample.X, floorY, nextSample.Z)
		end
		local currentDistance = (current - goal.MouthCenter):Dot(pitchward)
		local nextDistance = (nextSample - goal.MouthCenter):Dot(pitchward)

		--[[
			A shot travels from the pitch toward the goal, so its distance along
			pitchward falls through zero. The test previously looked for the
			opposite sign change -- a ball emerging from behind the line onto the
			pitch -- which no shot on goal ever produces, so no save was ever
			attempted.
		]]
		if currentDistance >= 0 and nextDistance < 0 then
			local alpha = math.clamp(
				(0 - currentDistance) / math.max(nextDistance - currentDistance, 1e-5),
				0,
				1
			)
			local crossing = current:Lerp(nextSample, alpha)
			local lateral = math.abs((crossing - goal.MouthCenter):Dot(widthAxis))
			local height = crossing.Y - goal.BottomY
			if lateral <= halfWidth and height >= -0.1 and height <= maximumHeight then
				return true, crossing, (index - 1 + alpha) * stepTime
			end
		end
	end

	return false, nil, nil
end

--[[
	Walk the line from the keeper toward the intercept point and return the first
	position the keeper can actually reach in time.
	Mirrors GameplayFootball's CalculateBestAchievableTarget.
]]
function GoalkeeperPositioning.GetAchievableSavePoint(
	keeperPosition: Vector3,
	interceptPoint: Vector3,
	availableTime: number,
	keeperSpeed: number,
	steps: number
): Vector3
	local count = math.max(math.floor(steps), 2)
	for index = 0, count do
		local alpha = index / count
		local candidate = keeperPosition:Lerp(interceptPoint, alpha)
		local distance = BallControlMath.GetHorizontal(candidate - keeperPosition).Magnitude
		local timeNeeded = distance / math.max(keeperSpeed, 1e-3)
		if timeNeeded <= availableTime * alpha + 1e-3 or alpha >= 1 then
			return candidate
		end
	end
	return interceptPoint
end

return GoalkeeperPositioning
