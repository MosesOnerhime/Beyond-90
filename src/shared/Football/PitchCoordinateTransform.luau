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

function PitchCoordinateTransform.Project(
	transform,
	worldPosition: Vector3,
	defendingGoalPosition: Vector3,
	attackingGoalPosition: Vector3
): Vector2
	local attackSign = PitchCoordinateTransform.GetAttackSign(transform, defendingGoalPosition, attackingGoalPosition)
	local offset = BallControlMath.GetHorizontal(worldPosition - transform.Center)
	-- Keep the controlled team's attacking goal on the left, matching the
	-- broadcast camera orientation. Both axes rotate together when teams swap.
	local lengthCoordinate = offset:Dot(transform.LengthAxis) / transform.Length * attackSign
	local widthCoordinate = offset:Dot(transform.WidthAxis) / transform.Width * attackSign
	return Vector2.new(
		math.clamp(0.5 - lengthCoordinate, 0.025, 0.975),
		math.clamp(0.5 + widthCoordinate, 0.04, 0.96)
	)
end

return PitchCoordinateTransform
