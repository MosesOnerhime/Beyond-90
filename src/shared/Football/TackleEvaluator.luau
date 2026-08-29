--!strict
-- Pure tackle evaluation. No side effects, no Player assumptions -- it takes
-- two actor-shaped records so humans and AI are scored by identical rules.
local BallControlMath = require(script.Parent.BallControlMath)

local TackleEvaluator = {}

export type Challenger = {
	Position: Vector3,
	Velocity: Vector3,
	FacingDirection: Vector3,
}

export type Carrier = {
	Position: Vector3,
	Velocity: Vector3,
	FacingDirection: Vector3,
}

--[[
	Returns a result table:
		Valid       -- geometry permitted the challenge at all
		Reason      -- rejection reason when not Valid
		Outcome     -- "Won" | "Partial" | "Missed"
		Score       -- 0..1 combined challenge quality
		Exposure    -- how far the ball sat from its carrier
		FacingDot   -- how squarely the tackler faced the ball
		BehindDot   -- 1 = directly behind the carrier
		LooseDirection -- unit direction to push the football on contact
]]
function TackleEvaluator.Evaluate(
	challenger: Challenger,
	carrier: Carrier,
	ballPosition: Vector3,
	config
)
	local toBall = BallControlMath.GetHorizontal(ballPosition - challenger.Position)
	local ballDistance = toBall.Magnitude
	if ballDistance > config.MaximumBallDistance then
		return { Valid = false, Reason = "ball-out-of-reach", Outcome = "Missed", Score = 0 }
	end

	local toOpponent = BallControlMath.GetHorizontal(carrier.Position - challenger.Position)
	if toOpponent.Magnitude > config.MaximumOpponentDistance then
		return { Valid = false, Reason = "opponent-out-of-range", Outcome = "Missed", Score = 0 }
	end

	local facing = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(challenger.FacingDirection),
		Vector3.zAxis
	)
	local ballDirection = BallControlMath.SafeUnit(toBall, facing)
	local facingDot = facing:Dot(ballDirection)
	if facingDot < config.MinimumFacingDot then
		return { Valid = false, Reason = "not-facing-contest", Outcome = "Missed", Score = 0, FacingDot = facingDot }
	end

	-- How far behind the carrier is this challenge coming from?
	local carrierFacing = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(carrier.FacingDirection),
		facing
	)
	local fromCarrier = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(challenger.Position - carrier.Position),
		-carrierFacing
	)
	local behindDot = -carrierFacing:Dot(fromCarrier)
	if behindDot > config.MaximumBehindDot then
		return {
			Valid = false,
			Reason = "challenge-from-behind",
			Outcome = "Missed",
			Score = 0,
			BehindDot = behindDot,
		}
	end

	-- Ball exposure -- a football tucked under the carrier is hard to win.
	local exposure = BallControlMath.GetHorizontal(ballPosition - carrier.Position).Magnitude
	if exposure < config.MinimumExposure then
		return {
			Valid = false,
			Reason = "ball-not-exposed",
			Outcome = "Missed",
			Score = 0,
			Exposure = exposure,
		}
	end
	local exposureAlpha = math.clamp(
		(exposure - config.MinimumExposure) / math.max(config.FullExposure - config.MinimumExposure, 1e-4),
		0,
		1
	)

	-- Closing speed toward the football.
	local relativeVelocity = BallControlMath.GetHorizontal(challenger.Velocity - carrier.Velocity)
	local closingSpeed = math.max(relativeVelocity:Dot(ballDirection), 0)
	local closingAlpha = math.clamp(closingSpeed / math.max(config.ClosingSpeedFull, 1e-4), 0, 1)

	local facingAlpha = math.clamp(
		(facingDot - config.MinimumFacingDot) / math.max(1 - config.MinimumFacingDot, 1e-4),
		0,
		1
	)

	local score = exposureAlpha * config.ExposureWeight
		+ closingAlpha * config.ClosingSpeedWeight
		+ facingAlpha * config.FacingWeight

	-- Challenging from the carrier's blind side is legal here but less clean.
	if behindDot > 0 then
		score -= behindDot * config.BehindPenalty * 0.5
	end

	--[[
		Position shapes tackling quality (§43). A defender wins challenges a
		forward would not, but the legality checks above are identical for
		everyone -- skill never makes an illegal challenge legal.
	]]
	score *= challenger.TackleSkill or 1
	score = math.clamp(score, 0, 1)

	local outcome = "Missed"
	if score >= config.SuccessThreshold then
		outcome = "Won"
	elseif score >= config.PartialThreshold then
		outcome = "Partial"
	end

	-- Push the football away from the carrier, biased through the challenge.
	local looseDirection = BallControlMath.SafeUnit(
		ballDirection * 0.65 + facing * 0.35,
		ballDirection
	)

	return {
		Valid = true,
		Reason = "",
		Outcome = outcome,
		Score = score,
		Exposure = exposure,
		FacingDot = facingDot,
		BehindDot = behindDot,
		ClosingSpeed = closingSpeed,
		BallDistance = ballDistance,
		LooseDirection = looseDirection,
	}
end

return TackleEvaluator
