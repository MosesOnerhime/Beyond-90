--!strict
--[[
	Pitch geometry in normalized space.

	Beyond 90's pitch is discovered from Workspace at runtime, so nothing here may
	assume a size. Positions are expressed as a pair of normalized coordinates and
	converted through a frame:

		longitudinal  -1 = own goal line, +1 = opponent goal line
		lateral       -1 .. +1 across the pitch

	This is the same representation GameplayFootball uses for formation entries,
	and it is what makes one formation description survive a change of pitch size
	and be remapped into a corner-kick or penalty box without re-authoring.

	Pure module: every function takes a frame and returns a value. No services, no
	state, no Workspace access -- so it is directly testable.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallControlMath = require(ReplicatedStorage.Shared.Football.BallControlMath)

local PitchGeometry = {}

export type Frame = {
	Center: Vector3,
	Forward: Vector3,
	Right: Vector3,
	HalfLength: number,
	HalfWidth: number,
	GroundY: number,
}

--[[
	Build a frame.

	`attackDirection` is the horizontal direction this frame treats as +1
	longitudinal. Pass a team's attacking direction for team-relative work, or the
	pitch's own length axis for neutral work such as boundary detection.
]]
function PitchGeometry.CreateFrame(pitchState, attackDirection: Vector3?): Frame
	local forward = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(attackDirection or pitchState.LengthAxis),
		Vector3.zAxis
	)
	-- Right-hand perpendicular in the ground plane; guaranteed orthogonal to
	-- Forward, so normalized components never bleed into each other.
	local right = Vector3.new(-forward.Z, 0, forward.X)

	return {
		Center = pitchState.Center,
		Forward = forward,
		Right = right,
		HalfLength = pitchState.Length * 0.5,
		HalfWidth = pitchState.Width * 0.5,
		GroundY = pitchState.GroundY,
	}
end

function PitchGeometry.ToNormalized(frame: Frame, position: Vector3): (number, number)
	local offset = BallControlMath.GetHorizontal(position - frame.Center)
	return offset:Dot(frame.Forward) / math.max(frame.HalfLength, 1e-4),
		offset:Dot(frame.Right) / math.max(frame.HalfWidth, 1e-4)
end

function PitchGeometry.FromNormalized(
	frame: Frame,
	longitudinal: number,
	lateral: number,
	height: number?
): Vector3
	return frame.Center
		+ frame.Forward * (longitudinal * frame.HalfLength)
		+ frame.Right * (lateral * frame.HalfWidth)
		+ Vector3.yAxis * ((frame.GroundY + (height or 0)) - frame.Center.Y)
end

-- Keep a position on the pitch, `marginRatio` in from every line.
function PitchGeometry.ClampToPitch(frame: Frame, position: Vector3, marginRatio: number?): Vector3
	local margin = marginRatio or 0
	local longitudinal, lateral = PitchGeometry.ToNormalized(frame, position)
	return PitchGeometry.FromNormalized(
		frame,
		math.clamp(longitudinal, -1 + margin, 1 - margin),
		math.clamp(lateral, -1 + margin, 1 - margin),
		position.Y - frame.GroundY
	)
end

--[[
	Has the WHOLE ball left the field of play?

	Uses the previous and current centre positions plus the ball radius, never
	`.Touched` (§50). A ball is only out when its trailing edge has cleared the
	outside of the line, matching the source's `pitchHalf + lineHalfW + epsilon`.

	Returns nil while in play, otherwise:
		Kind             "Touchline" | "GoalLine"
		Crossing         world position where the centre crossed the line plane
		LongitudinalSign which goal line (+1 / -1) for a GoalLine exit
		LateralSign      which touchline (+1 / -1) for a Touchline exit
]]
function PitchGeometry.ClassifyBallExit(
	frame: Frame,
	previousPosition: Vector3?,
	currentPosition: Vector3,
	ballRadius: number,
	lineRatio: number
)
	local longitudinal, lateral = PitchGeometry.ToNormalized(frame, currentPosition)

	-- The ball's own radius expressed in each normalized axis.
	local radiusLongitudinal = ballRadius / math.max(frame.HalfLength, 1e-4)
	local radiusLateral = ballRadius / math.max(frame.HalfWidth, 1e-4)

	local longitudinalLimit = 1 + lineRatio + radiusLongitudinal
	local lateralLimit = 1 + lineRatio + radiusLateral

	local overGoalLine = math.abs(longitudinal) > longitudinalLimit
	local overTouchline = math.abs(lateral) > lateralLimit

	if not overGoalLine and not overTouchline then
		return nil
	end

	local previous = previousPosition or currentPosition
	local previousLongitudinal, previousLateral = PitchGeometry.ToNormalized(frame, previous)

	--[[
		Interpolate where the centre crossed the line itself (not the offset
		limit), so a throw-in is placed where the ball actually left the pitch
		rather than where it was first noticed to be outside.
	]]
	local function crossingAlong(previousValue: number, currentValue: number, limit: number): number
		local span = currentValue - previousValue
		if math.abs(span) <= 1e-6 then
			return 1
		end
		return math.clamp((limit - previousValue) / span, 0, 1)
	end

	-- A ball can clear both lines in one step near a corner; whichever it crossed
	-- first is the one that stopped play.
	local goalAlpha = if overGoalLine
		then crossingAlong(previousLongitudinal, longitudinal, if longitudinal > 0 then 1 else -1)
		else math.huge
	local touchAlpha = if overTouchline
		then crossingAlong(previousLateral, lateral, if lateral > 0 then 1 else -1)
		else math.huge

	if goalAlpha <= touchAlpha then
		local alpha = if goalAlpha == math.huge then 1 else goalAlpha
		return {
			Kind = "GoalLine",
			Crossing = previous:Lerp(currentPosition, alpha),
			LongitudinalSign = if longitudinal > 0 then 1 else -1,
			LateralSign = if lateral > 0 then 1 else -1,
		}
	end

	local alpha = if touchAlpha == math.huge then 1 else touchAlpha
	return {
		Kind = "Touchline",
		Crossing = previous:Lerp(currentPosition, alpha),
		LongitudinalSign = if longitudinal > 0 then 1 else -1,
		LateralSign = if lateral > 0 then 1 else -1,
	}
end

--[[
	Is `position` inside the penalty area at the `longitudinalSign` end?
	Ratios come from MatchRulesConfig.Pitch.
]]
function PitchGeometry.IsInsidePenaltyArea(
	frame: Frame,
	position: Vector3,
	longitudinalSign: number,
	depthRatio: number,
	halfWidthRatio: number
): boolean
	local longitudinal, lateral = PitchGeometry.ToNormalized(frame, position)
	-- Distance in from that goal line, as a fraction of the half-length.
	local depth = 1 - longitudinal * longitudinalSign
	return depth >= 0 and depth <= depthRatio and math.abs(lateral) <= halfWidthRatio
end

-- Push `position` at least `distance` studs away from `origin`, horizontally.
function PitchGeometry.PushOutside(origin: Vector3, position: Vector3, distance: number): Vector3
	local offset = BallControlMath.GetHorizontal(position - origin)
	if offset.Magnitude >= distance then
		return position
	end
	local direction = BallControlMath.SafeUnit(offset, Vector3.xAxis)
	local pushed = origin + direction * distance
	return Vector3.new(pushed.X, position.Y, pushed.Z)
end

return PitchGeometry
