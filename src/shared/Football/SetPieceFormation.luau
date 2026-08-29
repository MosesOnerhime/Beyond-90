--!strict
--[[
	Set-piece placement.

	Ported closely from GameplayFootball's `AI_GetAdaptedFormationPosition`, which
	is the single idea every one of its set pieces is built on:

		take the footballer's own normalized formation anchor,
		remap it into a bounded box chosen for this set piece,
		then pull it toward focus points.

	The consequence is that a defender stays a defender inside a corner-kick box.
	Nobody is teleported into a hardcoded arrangement, which is exactly what §65
	asks for, and it means new positions need no set-piece code of their own.

	Pure module. See docs/research/gameplay-football/match-rules-and-positions.md.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PitchGeometry = require(ReplicatedStorage.Shared.Football.PitchGeometry)

local SetPieceFormation = {}

export type Box = {
	-- Normalized longitudinal bounds. `Back` is the end nearer the team's own
	-- goal; `Front` may be either side of it, the remap does not care.
	Back: number,
	Front: number,
	LowLateral: number,
	HighLateral: number,
	-- Optional pulls, all normalized.
	LongitudinalFocus: number?,
	LongitudinalFocusStrength: number?,
	LateralFocus: number?,
	LateralFocusStrength: number?,
}

-- Remap t in -1..1 onto a..b.
local function remap(value: number, a: number, b: number): number
	return a + (math.clamp(value, -1, 1) * 0.5 + 0.5) * (b - a)
end

--[[
	Where `anchor` (a normalized { Longitudinal, Lateral }) should stand for this
	set piece, in `frame` (the team's attacking frame).
]]
function SetPieceFormation.Resolve(
	frame: PitchGeometry.Frame,
	anchor: { Longitudinal: number, Lateral: number },
	box: Box
): Vector3
	local longitudinal = remap(anchor.Longitudinal, box.Back, box.Front)
	local lateral = remap(anchor.Lateral, box.LowLateral, box.HighLateral)

	if box.LongitudinalFocus and box.LongitudinalFocusStrength then
		local strength = math.clamp(box.LongitudinalFocusStrength, 0, 1)
		longitudinal += (box.LongitudinalFocus - longitudinal) * strength
	end
	if box.LateralFocus and box.LateralFocusStrength then
		local strength = math.clamp(box.LateralFocusStrength, 0, 1)
		lateral += (box.LateralFocus - lateral) * strength
	end

	return PitchGeometry.FromNormalized(
		frame,
		math.clamp(longitudinal, -0.99, 0.99),
		math.clamp(lateral, -0.99, 0.99)
	)
end

--[[
	Box definitions per restart, as normalized bounds in the TEAM'S OWN attacking
	frame. Ratios converted from the source's `pitchHalfW * k` forms; the sign
	work the source does with `team->GetSide()` is unnecessary here because the
	frame is already team-relative.

	`taking` selects the box for the side awarded the restart.
]]
function SetPieceFormation.GetBox(restart: string, taking: boolean, ballLongitudinal: number, ballLateral: number): Box
	if restart == "Kickoff" then
		-- Both sides confined to their own half.
		return {
			Back = -0.6,
			Front = -0.06,
			LowLateral = -0.6,
			HighLateral = 0.6,
		}
	elseif restart == "GoalKick" then
		if taking then
			return { Back = -0.5, Front = 0.2, LowLateral = -0.7, HighLateral = 0.7 }
		end
		return { Back = -0.4, Front = 0.1, LowLateral = -0.7, HighLateral = 0.7 }
	elseif restart == "CornerKick" then
		if taking then
			-- Attacking side crowds the far end, pulled toward the box.
			return {
				Back = 0.2,
				Front = 0.96,
				LowLateral = -0.6,
				HighLateral = 0.6,
				LongitudinalFocus = 0.82,
				LongitudinalFocusStrength = 0.7,
				LateralFocus = ballLateral * 0.1,
				LateralFocusStrength = 0.7,
			}
		end
		-- Defending side sits deep on its own line.
		return {
			Back = -0.98,
			Front = -0.5,
			LowLateral = -0.6,
			HighLateral = 0.6,
			LongitudinalFocus = -0.92,
			LongitudinalFocusStrength = 0.8,
			LateralFocus = ballLateral * 0.1,
			LateralFocusStrength = 0.9,
		}
	elseif restart == "ThrowIn" then
		-- Both sides band around the ball's longitudinal position.
		local back = math.clamp(ballLongitudinal - 0.55, -1, 1)
		local front = math.clamp(ballLongitudinal + (if taking then 0.36 else 0.27), -1, 1)
		return {
			Back = back,
			Front = front,
			LowLateral = math.clamp(-0.75 + ballLateral * 0.25, -1, 1),
			HighLateral = math.clamp(0.75 + ballLateral * 0.25, -1, 1),
			LongitudinalFocus = math.clamp(ballLongitudinal + (if taking then 0.07 else -0.29), -1, 1),
			LongitudinalFocusStrength = if taking then 0.4 else 0.2,
			LateralFocus = ballLateral * (if taking then 0.996 else 0.95),
			LateralFocusStrength = if taking then 0.6 else 0.5,
		}
	elseif restart == "FreeKick" then
		-- Bounds slide with how far up the pitch the kick is.
		local advance = math.clamp(ballLongitudinal, -1, 1) * 0.5 + 0.5
		if taking then
			return {
				Back = math.clamp(-0.7 + advance * 0.7, -1, 1),
				Front = math.clamp(0.3 + advance * 0.7, -1, 1),
				LowLateral = -0.7,
				HighLateral = 0.7,
				LongitudinalFocus = math.clamp(ballLongitudinal + 0.18, -1, 1),
				LongitudinalFocusStrength = 0.5 + advance * 0.2,
				LateralFocus = ballLateral * 0.4,
				LateralFocusStrength = 0.6 + advance * 0.2,
			}
		end
		return {
			Back = math.clamp(-1 + advance * 0.6, -1, 1),
			Front = math.clamp(-0.5 + advance * 0.8, -1, 1),
			LowLateral = -0.7,
			HighLateral = 0.7,
			LongitudinalFocus = math.clamp(ballLongitudinal - 0.36, -1, 1),
			LongitudinalFocusStrength = 0.6 - advance * 0.4,
			LateralFocus = ballLateral * 0.2,
			LateralFocusStrength = 0.8 - advance * 0.4,
		}
	elseif restart == "Penalty" then
		if taking then
			return {
				Back = math.clamp(ballLongitudinal - 0.9, -1, 1),
				Front = math.clamp(ballLongitudinal - 0.18, -1, 1),
				LowLateral = -0.8,
				HighLateral = 0.8,
				LongitudinalFocus = math.clamp(ballLongitudinal - 0.2, -1, 1),
				LongitudinalFocusStrength = 0.6,
				LateralFocus = 0,
				LateralFocusStrength = 0.8,
			}
		end
		return {
			Back = math.clamp(ballLongitudinal - 0.36, -1, 1),
			Front = math.clamp(ballLongitudinal - 0.2, -1, 1),
			LowLateral = -0.8,
			HighLateral = 0.8,
			LongitudinalFocus = math.clamp(ballLongitudinal - 0.28, -1, 1),
			LongitudinalFocusStrength = 1,
			LateralFocus = 0,
			LateralFocusStrength = 1,
		}
	end

	-- Unknown restart: hold normal shape rather than inventing one.
	return { Back = -0.7, Front = 0.7, LowLateral = -0.7, HighLateral = 0.7 }
end

--[[
	A defensive wall: `count` footballers standing `distance` studs from the ball
	on the ball -> goal line, fanned slightly so they do not occupy one point.
	Mirrors the source's 3-player, 9.15 m wall.
]]
function SetPieceFormation.GetWallPositions(
	ballPosition: Vector3,
	goalPosition: Vector3,
	count: number,
	distance: number,
	spread: number
): { Vector3 }
	local toGoal = Vector3.new(goalPosition.X - ballPosition.X, 0, goalPosition.Z - ballPosition.Z)
	if toGoal.Magnitude <= 1e-3 then
		return {}
	end
	toGoal = toGoal.Unit
	local right = Vector3.new(-toGoal.Z, 0, toGoal.X)

	local positions = {}
	for index = 1, math.max(count, 0) do
		-- Centre the fan on the ball -> goal line.
		local offset = (index - 1) - (count - 1) * 0.5
		local direction = (toGoal + right * (offset * spread)).Unit
		local point = ballPosition + direction * distance
		table.insert(positions, Vector3.new(point.X, ballPosition.Y, point.Z))
	end
	return positions
end

return SetPieceFormation
