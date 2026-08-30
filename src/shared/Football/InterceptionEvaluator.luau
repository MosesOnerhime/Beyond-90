--!strict
--[[
	INTERCEPTIONS.

	A defender standing in a passing lane gets a foot to the ball. Beyond 90 had
	no way for that to happen, and the reason is worth stating plainly because it
	is not a missing feature so much as a sampling failure.

	The only route from a travelling ball to a defender's possession was the
	ordinary reception path, which asks, once per server tick, "is the football
	within reach right now, and slow enough to control?" Both halves of that fail
	for a pass:

	  * A driven pass travels at 60+ studs per second. A defender's reach is
	    around five studs. The ball is therefore inside that reach for well under
	    a tenth of a second -- frequently less than the gap between two ticks. A
	    point-in-time distance test does not miss it occasionally; it misses it
	    almost always, and the ball appears to pass straight through the defender.

	  * Reception also refuses anything above MaxControllableBallSpeed, which is
	    a sensible rule for TAKING A TOUCH and the wrong rule entirely for
	    sticking out a leg. You cannot control a driven pass on your instep. You
	    can absolutely block it.

	So interception is evaluated as a SWEPT SEGMENT rather than a sample. The
	ball's travel over the tick is a line; the defender's reach is a disc around
	them; if the line passes through the disc, contact happened, whatever the
	tick rate was. That is the same reasoning any collision system uses for a
	fast-moving body, applied to the one interaction in this game where the ball
	is routinely the fastest thing on the pitch.

	WHAT AN INTERCEPTION IS NOT

	It is not a possession grant. The outcomes here are a controlled block that
	drops the ball into the defender's own path, or a deflection that sends it
	somewhere neither side chose. In both cases the ball is left FREE and the
	ordinary acquisition rules decide who ends up with it -- exactly as a won
	tackle does. Nothing in this module hands anybody the ball.

	It is also not a decision. Being in the lane is the football decision, and
	the player made it by standing there. Reading the pass and putting a body in
	its path IS the skill; the leg going out is execution, which is why this is
	automatic and does not need an input of its own.

	Pure and deterministic: no Instances, no services, no randomness. The server
	is the only caller, and a client could run the identical evaluation for
	prediction without either drifting from the other.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BallControlMath = require(ReplicatedStorage:WaitForChild("Shared").Football.BallControlMath)

local InterceptionEvaluator = {}

export type Defender = {
	Position: Vector3,
	Velocity: Vector3,
	FacingDirection: Vector3,
	-- 0-1. Positional aptitude, so a centre back reads a pass better than a
	-- striker does. Same source as the tackle evaluator's TackleSkill.
	Skill: number,
}

export type Result = {
	Valid: boolean,
	Reason: string?,
	Score: number,
	Outcome: string?,
	ContactPoint: Vector3?,
	LooseDirection: Vector3?,
	Closeness: number?,
}

--[[
	Closest approach of a point to a segment, in the horizontal plane.

	Returns the distance and how far along the segment it happened, 0-1. The
	fraction matters: contact at the very start of the segment means the ball was
	already level with the defender when the tick began, which is the signature of
	a ball that has ALREADY gone past rather than one arriving.
]]
local function closestApproach(from: Vector3, to: Vector3, point: Vector3): (number, number)
	local segment = BallControlMath.GetHorizontal(to - from)
	local toPoint = BallControlMath.GetHorizontal(point - from)
	local lengthSquared = segment:Dot(segment)
	if lengthSquared <= 1e-6 then
		return toPoint.Magnitude, 0
	end
	local t = math.clamp(toPoint:Dot(segment) / lengthSquared, 0, 1)
	local closest = segment * t
	return (toPoint - closest).Magnitude, t
end

--[[
	Did `defender` intercept a ball travelling from `ballFrom` to `ballTo`?

	`config` is DefendingConfig.Interception.
]]
function InterceptionEvaluator.Evaluate(
	defender: Defender,
	ballFrom: Vector3,
	ballTo: Vector3,
	ballVelocity: Vector3,
	config
): Result
	local invalid = function(reason: string): Result
		return { Valid = false, Reason = reason, Score = 0 }
	end

	local speed = BallControlMath.GetHorizontal(ballVelocity).Magnitude
	--[[
		A ball barely moving is not a pass to intercept, it is a loose ball to
		pick up, and the reception path already owns that. Without this floor
		every stationary ball beside a defender would read as a permanent
		interception.
	]]
	if speed < config.MinimumBallSpeed then
		return invalid("ball-too-slow")
	end

	local distance, along = closestApproach(ballFrom, ballTo, defender.Position)

	--[[
		HOW FAR CAN THIS DEFENDER REACH?

		The base reach is a standing leg. It grows with the defender's own
		movement, because a player already moving across the lane covers ground
		during the block, and with positional skill, because reading the pass
		early is most of what makes the difference between a defender who
		intercepts and one who watches it go by.

		It is deliberately NOT scaled by ball speed. A faster ball is harder to
		intercept, and that is expressed below in the SCORE -- as a worse outcome
		rather than as no contact at all, which is what actually happens when a
		defender gets a boot to a driven pass.
	]]
	local lateralSpeed = BallControlMath.GetHorizontal(defender.Velocity).Magnitude
	local reach = config.BaseReach
		+ math.min(lateralSpeed * config.ReachPerSpeed, config.MaximumSpeedReach)
		+ math.clamp(defender.Skill, 0, 1) * config.SkillReachBonus
	if distance > reach then
		return invalid("out-of-reach")
	end

	--[[
		The ball must still be COMING. A ball whose closest approach was at the
		very start of the sweep has already gone past, and letting that count
		would let defenders intercept backwards.
	]]
	if along < config.MinimumSegmentFraction then
		return invalid("ball-already-past")
	end

	--[[
		The defender must be facing something like the ball. Not tightly -- an
		interception is often made half-turned, and demanding a square stance
		would rule out most real ones -- but a ball crossing behind a defender's
		back is not one they have any way of reading.
	]]
	local toBall = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(ballFrom - defender.Position),
		defender.FacingDirection
	)
	local facing = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(defender.FacingDirection),
		toBall
	)
	local facingDot = facing:Dot(toBall)
	if facingDot < config.MinimumFacingDot then
		return invalid("not-facing")
	end

	--[[
		THE SCORE, and therefore how clean the interception is.

		Three things decide it, and each is something a real defender would
		recognise:

		  CLOSENESS  -- a ball straight at the defender is blocked properly; one
		                at the very edge of their reach comes off a toe.
		  FACING     -- a defender who has read it and is square to the pass has
		                a chance to kill it; one reacting sideways has not.
		  SPEED      -- and a ball hit hard enough simply cannot be taken down,
		                however well it is met.

		Skill lifts the whole thing, because reading the pass early is what
		converts a block into possession.
	]]
	local closeness = 1 - math.clamp(distance / math.max(reach, 0.01), 0, 1)
	local facingQuality = math.clamp(
		(facingDot - config.MinimumFacingDot) / math.max(1 - config.MinimumFacingDot, 0.01),
		0,
		1
	)
	local speedPenalty = math.clamp(
		(speed - config.CleanSpeedLimit) / math.max(config.HopelessSpeed - config.CleanSpeedLimit, 1),
		0,
		1
	)

	local score = closeness * config.ClosenessWeight
		+ facingQuality * config.FacingWeight
		+ math.clamp(defender.Skill, 0, 1) * config.SkillWeight
		- speedPenalty * config.SpeedPenaltyWeight

	--[[
		Where the ball goes.

		A CONTROLLED block is played into the defender's own path -- the same
		shape as a won tackle, and for the same reason: it must be a free ball
		the defender is standing over, not a possession grant.

		A DEFLECTION comes off them. The incoming direction is mostly preserved
		and bent away from the defender's facing, because that is what a ball
		hitting a shin does; it is nobody's ball afterwards, which is the honest
		outcome of getting a leg to a pass you could not control.
	]]
	local incoming = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(ballVelocity), facing)
	local contactPoint = ballFrom:Lerp(ballTo, along)

	if score >= config.CleanThreshold then
		return {
			Valid = true,
			Score = score,
			Outcome = "Controlled",
			ContactPoint = contactPoint,
			LooseDirection = facing,
			Closeness = closeness,
		}
	end

	if score >= config.DeflectionThreshold then
		local deflected = BallControlMath.SafeUnit(
			incoming * (1 - config.DeflectionFacingBlend) + facing * config.DeflectionFacingBlend,
			incoming
		)
		return {
			Valid = true,
			Score = score,
			Outcome = "Deflected",
			ContactPoint = contactPoint,
			LooseDirection = deflected,
			Closeness = closeness,
		}
	end

	return invalid("missed")
end

return InterceptionEvaluator
