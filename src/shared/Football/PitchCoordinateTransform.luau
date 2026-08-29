local BallControlMath = require(script.Parent.BallControlMath)

local PitchCoordinateTransform = {}

function PitchCoordinateTransform.FromBounds(bounds: BasePart)
	local center = bounds:GetAttribute("PitchCenter")
	local lengthAxis = bounds:GetAttribute("PitchLengthAxis")
	local widthAxis = bounds:GetAttribute("PitchWidthAxis")
	local length = bounds:GetAttribute("PitchLength")
	local width = bounds:GetAttribute("PitchWidth")
	if typeof(center) ~= "Vector3" or typeof(lengthAxis) ~= "Vector3" or typeof(widthAxis) ~= "Vector3"
		or typeof(length) ~= "number" or typeof(width) ~= "number"
	then
		return nil
	end
	return {
		Center = center,
		LengthAxis = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(lengthAxis), Vector3.zAxis),
		WidthAxis = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(widthAxis), Vector3.xAxis),
		Length = length,
		Width = width,
	}
end

function PitchCoordinateTransform.GetAttackSign(transform, defendingGoalPosition: Vector3, attackingGoalPosition: Vector3): number
	local defendingCoordinate = (defendingGoalPosition - transform.Center):Dot(transform.LengthAxis)
	local attackingCoordinate = (attackingGoalPosition - transform.Center):Dot(transform.LengthAxis)
	return if attackingCoordinate >= defendingCoordinate then 1 else -1
end

--[[
	World position -> minimap coordinate, in the BROADCAST CAMERA'S frame.

	The minimap is a reading aid for what is on screen, so it must agree with what
	the player is looking at. The Broadcast Camera sits on one FIXED touchline
	(CameraConfig.BroadcastSide) and never swaps sides by team, so the minimap must
	not rotate by team either.

	It previously multiplied BOTH axes by an attacking-direction sign, which
	rotated the whole map 180 degrees for the Away team. The map then disagreed
	with the screen in both axes at once -- a teammate visibly to the left of the
	screen was drawn on the right of the map, and the far touchline was drawn as
	the near one.

	The frame here is derived from the camera instead:

		camera forward  = -broadcastSide * WidthAxis   (it looks across the pitch)
		camera right    = forward x up                 (screen +X)
		screen up       = away from the camera         (farther reads as higher)

	`attackSign` is still returned by GetAttackSign for callers that want to LABEL
	which end a team attacks -- which is how attacking direction should be shown,
	rather than by spinning the pitch.
]]
function PitchCoordinateTransform.Project(
	transform,
	worldPosition: Vector3,
	broadcastSide: number
): Vector2
	local sideSign = if (broadcastSide or -1) >= 0 then 1 else -1
	local offset = BallControlMath.GetHorizontal(worldPosition - transform.Center)

	local forward = transform.WidthAxis * -sideSign
	local right = forward:Cross(Vector3.yAxis)

	-- Along the camera's right: the pitch length runs left-to-right on screen.
	local rightCoordinate = offset:Dot(right) / transform.Length
	-- Away from the camera: farther from the touchline reads as higher up.
	local depthCoordinate = offset:Dot(forward) / transform.Width

	return Vector2.new(
		math.clamp(0.5 + rightCoordinate, 0.025, 0.975),
		-- UI Y grows downward, so more depth (farther away) is a SMALLER Y.
		math.clamp(0.5 - depthCoordinate, 0.04, 0.96)
	)
end

--[[
	Which horizontal end of the minimap a team attacks: -1 is the left edge, +1
	the right. Used to label the ends, never to rotate the map.
]]
function PitchCoordinateTransform.GetAttackingEndSign(
	transform,
	defendingGoalPosition: Vector3,
	attackingGoalPosition: Vector3,
	broadcastSide: number
): number
	local sideSign = if (broadcastSide or -1) >= 0 then 1 else -1
	local forward = transform.WidthAxis * -sideSign
	local right = forward:Cross(Vector3.yAxis)
	local attacking = BallControlMath.GetHorizontal(attackingGoalPosition - transform.Center):Dot(right)
	local defending = BallControlMath.GetHorizontal(defendingGoalPosition - transform.Center):Dot(right)
	return if attacking >= defending then 1 else -1
end

return PitchCoordinateTransform
