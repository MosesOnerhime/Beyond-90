--!strict
--[[
	Fouls.

	Adapted from GameplayFootball's `Referee::TripNotice`. The source scores a
	sliding tackle by summing three independent terms; Beyond 90 has no slide
	tackle yet (§84 excludes it), so the same three terms are applied to the
	standing challenge that does exist:

		mistiming    the challenge did not win the ball
		contact      it reached the opponent anyway
		from behind  the source's dot of (victim -> challenger) against the
		             victim's facing, which is the term that dominates its model

	A foul is never random. Every term comes from the same challenge geometry the
	tackle evaluator already measured, so a clean front tackle can never produce
	one and a mistimed lunge through the back of an opponent always does.

	Pure module.
]]
local FoulEvaluator = {}

export type Challenge = {
	-- From TackleEvaluator: did the challenge legally win the ball?
	WonBall: boolean,
	-- Dot of (victim -> challenger) against the victim's facing. 1 = directly
	-- behind the victim.
	BehindDot: number,
	-- Horizontal distance between challenger and victim at the challenge.
	ContactDistance: number,
	-- How far the victim was from the football.
	VictimBallDistance: number,
	-- Closing speed of the challenger onto the victim.
	RelativeSpeed: number,
	-- Contact radius: inside this the challenger physically reached the victim.
	ContactRadius: number,
}

export type Decision = {
	Type: string,
	Severity: number,
	FromBehind: boolean,
}

--[[
	Score a challenge. Returns nil for a legal one.

	`config` is MatchRulesConfig.Foul.
]]
function FoulEvaluator.Evaluate(challenge: Challenge, config): Decision?
	if config.Enabled ~= true then
		return nil
	end

	--[[
		The victim must genuinely have had the football. Without this a challenge
		near an opponent who is nowhere near the ball would be a foul, which is
		the source's `< 2.0` ball-distance condition.
	]]
	if challenge.VictimBallDistance > config.MaximumVictimBallDistance then
		return nil
	end

	-- No contact, no foul: a challenge that never reached the opponent is just a
	-- missed tackle.
	if challenge.ContactDistance > challenge.ContactRadius then
		return nil
	end

	-- Winning the ball cleanly is never a foul, however it looked.
	if challenge.WonBall then
		return nil
	end

	local weights = config.Severity

	-- Mistiming: the challenge made contact without winning the ball.
	local mistiming = 1

	-- From behind, normalized above the legality threshold.
	local behindSpan = math.max(1 - config.FromBehindDot, 1e-4)
	local fromBehind = math.clamp((challenge.BehindDot - config.FromBehindDot) / behindSpan, 0, 1)

	-- Recklessness: how fast the challenger came in.
	local speed = math.clamp(challenge.RelativeSpeed / math.max(config.RecklessRelativeSpeed, 1e-4), 0, 1)

	local severity = mistiming * weights.MistimingWeight
		+ fromBehind * weights.FromBehindWeight
		+ speed * weights.SpeedWeight

	if severity < weights.FoulThreshold then
		return nil
	end

	return {
		Type = if severity >= weights.SeriousThreshold then "SeriousFoul" else "Foul",
		Severity = severity,
		FromBehind = fromBehind > 0,
	}
end

return FoulEvaluator
