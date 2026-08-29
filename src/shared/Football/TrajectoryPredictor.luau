local BallConfig = require(script.Parent.Parent.Config.BallConfig)

--[[
	The ball's flight, as one shared model.

	BallService integrates this on the server; the local trajectory preview
	samples it on the client. Both must therefore describe exactly the same
	physics, or the drawn line is a lie (§71).

	Flight has three terms and no more:

		constant launch velocity
		constant downward gravity
		constant lateral CURVE acceleration, fixed at release

	Curve is deliberately a CONSTANT acceleration decided when the ball leaves
	the foot. It is not a steering force and never looks at the goal, so a curved
	shot can miss, be intercepted or be saved exactly like a straight one, and
	the preview can reproduce it in closed form rather than by simulating (§69).
]]
local TrajectoryPredictor = {}

function TrajectoryPredictor.GetGravity(): number
	return if BallConfig.Flight then BallConfig.Flight.EffectiveGravity else workspace.Gravity
end

function TrajectoryPredictor.SamplePosition(
	origin: Vector3,
	launchVelocity: Vector3,
	timeSeconds: number,
	curveAcceleration: Vector3?
): Vector3
	local time = math.max(timeSeconds, 0)
	local position = origin
		+ launchVelocity * time
		- Vector3.yAxis * (0.5 * TrajectoryPredictor.GetGravity() * time * time)
	if curveAcceleration then
		position += curveAcceleration * (0.5 * time * time)
	end
	return position
end

function TrajectoryPredictor.Sample(
	origin: Vector3,
	launchVelocity: Vector3,
	duration: number,
	segmentCount: number,
	curveAcceleration: Vector3?
): { Vector3 }
	local count = math.max(2, math.floor(segmentCount))
	local safeDuration = math.max(duration, 0.05)
	local samples = table.create(count)
	for index = 0, count - 1 do
		local alpha = index / (count - 1)
		samples[index + 1] = TrajectoryPredictor.SamplePosition(
			origin,
			launchVelocity,
			safeDuration * alpha,
			curveAcceleration
		)
	end
	return samples
end

return TrajectoryPredictor
