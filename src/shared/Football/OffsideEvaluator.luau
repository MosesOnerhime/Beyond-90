--!strict
--[[
	Offside.

	Ported closely from GameplayFootball's `AI_GetOffsideLine` and
	`Referee::BallTouched`, because the rule it implements is the actual rule:

		line = the SECOND-LAST opponent, not the last
		     ("we are actually looking for the one-but-deepest opponent
		       (association football rule!)" -- the source's own comment)
		if the ball is further forward than that, the ball becomes the line

	And, just as importantly, the two halves are kept separate:

		SNAPSHOT     taken the moment a team plays the ball: who was beyond the
		             line at that instant, and exactly where they were standing
		INVOLVEMENT  applied on the NEXT touch: only a player from that snapshot
		             who then plays the ball is penalised

	A player standing in an offside position is never punished for standing
	there. The restart is placed where the snapshot recorded them, not where they
	eventually received the ball.

	Pure module: callers pass plain actor-shaped records, so it works identically
	for human and AI footballers.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PitchGeometry = require(ReplicatedStorage.Shared.Football.PitchGeometry)

local OffsideEvaluator = {}

export type PlayerRecord = {
	Id: number,
	Position: Vector3,
	IsGoalkeeper: boolean?,
}

--[[
	The offside line, as a normalized longitudinal value in `attackFrame`
	(the frame whose +1 is the attacking team's target goal).

	`opponents` are the defending team's footballers. Returns nil when there are
	too few opponents for the rule to mean anything -- the source disables offside
	in its one-keeper debug mode for exactly this reason.
]]
function OffsideEvaluator.GetOffsideLine(
	attackFrame: PitchGeometry.Frame,
	opponents: { PlayerRecord },
	ballPosition: Vector3?
): number?
	if #opponents < 2 then
		return nil
	end

	-- Deepest = furthest toward the opponents' own goal, i.e. the LOWEST
	-- longitudinal value in the attacking frame. Usually the keeper.
	local deepest, secondDeepest = math.huge, math.huge
	for _, opponent in opponents do
		local longitudinal = PitchGeometry.ToNormalized(attackFrame, opponent.Position)
		if longitudinal < deepest then
			secondDeepest = deepest
			deepest = longitudinal
		elseif longitudinal < secondDeepest then
			secondDeepest = longitudinal
		end
	end

	if secondDeepest == math.huge then
		return nil
	end

	local line = secondDeepest

	-- "Level with the ball" -- if the ball is further forward than the
	-- second-last defender, the ball is the line.
	if ballPosition then
		local ballLongitudinal = PitchGeometry.ToNormalized(attackFrame, ballPosition)
		if ballLongitudinal > line then
			line = ballLongitudinal
		end
	end

	return line
end

--[[
	Who is in an offside position right now.

	`attackers` are the playing team's footballers; `touchingId` is the one who
	just played the ball and is excluded (a player is never offside from their own
	touch). Returns a list of { Id, Position } -- the snapshot.
]]
function OffsideEvaluator.TakeSnapshot(
	attackFrame: PitchGeometry.Frame,
	attackers: { PlayerRecord },
	opponents: { PlayerRecord },
	ballPosition: Vector3?,
	touchingId: number,
	relaxRatio: number,
	minimumTeammates: number
): { { Id: number, Position: Vector3 } }
	local snapshot = {}

	if #attackers < minimumTeammates then
		return snapshot
	end

	local line = OffsideEvaluator.GetOffsideLine(attackFrame, opponents, ballPosition)
	if not line then
		return snapshot
	end

	for _, attacker in attackers do
		if attacker.Id ~= touchingId and not attacker.IsGoalkeeper then
			local longitudinal = PitchGeometry.ToNormalized(attackFrame, attacker.Position)
			-- Beyond the line, with the source's small tolerance so a player
			-- exactly level is never given offside.
			if longitudinal > line + relaxRatio then
				-- Only in the opponents' half can a player be offside at all.
				if longitudinal > 0 then
					table.insert(snapshot, { Id = attacker.Id, Position = attacker.Position })
				end
			end
		end
	end

	return snapshot
end

--[[
	Did a snapshotted player become involved?

	Returns the recorded position of the offending player, or nil. The caller
	restarts from that position, which is what the source does -- the offence
	happened where they were standing when the ball was played.
]]
function OffsideEvaluator.FindInvolvement(
	snapshot: { { Id: number, Position: Vector3 } },
	touchingId: number
): Vector3?
	for _, entry in snapshot do
		if entry.Id == touchingId then
			return entry.Position
		end
	end
	return nil
end

return OffsideEvaluator
