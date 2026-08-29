--!strict
--[[
	The football reasoning behind an AI footballer's on-the-ball decision.

	Pure maths: it takes positions and velocities and returns ratings. No
	Instances, no services, no side effects -- so it can be reasoned about and
	tested on its own, and so the same evaluation could later score a human's
	assisted options without dragging AI plumbing along with it.

	------------------------------------------------------------------
	SOURCE
	------------------------------------------------------------------
	Ported closely from GameplayFootball, as requested.

		repository  https://github.com/vi3itor/GameplayFootball.git
		branch      windows
		commit      1dc1518abd0ffaa349c7e1a53ded6ba19213c73f (2021-08-21)
		researched  2026-08-28

		src/onthepitch/player/controller/elizacontroller.cpp
			ElizaController::GetOnTheBallCommands   (the decision itself)
			ElizaController::_GetPassingOdds        (interception model)
		src/onthepitch/AIsupport/AIfunctions.cpp
			AI_CalculateFreeSpace
		src/onthepitch/player/player.cpp
			Player::_CalculateTacticalSituation
		src/gamedefines.hpp
			pitchHalfW = 55, sprintVelocity = 8

	CONFIRMED FROM SOURCE. The structure, the weightings, the interception
	timing model and the ordering of the decision are the reference's. What is
	adapted is unit scale and Roblox-native data access.

	------------------------------------------------------------------
	WHY THIS EXISTS
	------------------------------------------------------------------
	Beyond 90's AI previously decided to shoot with a flat distance-and-angle
	gate (`MaximumDistance = 82`, `MinimumGoalAlignment = 0.58`). Every carrier
	therefore shot the moment it was pointed vaguely at goal from anywhere
	inside its own half -- the playtest log is a wall of

		[AIShot] distance=77.3 launchSpeed=139.7 result=OnTarget
		[AIShot] distance=78.2 launchSpeed=138.7 result=OnTarget
		[AIShot] distance=79.3 launchSpeed=138.5 result=OnTarget

	and, because shooting was checked before passing, a shot always beat a pass.
	The AI could not do anything else.

	GameplayFootball does not gate on distance. It asks two questions, and both
	of them are about the actual football situation:

		1. Is a team-mate in a BETTER position than I am?  (tactical rating)
		2. Would the ball survive the journey?             (interception odds)

	That is the whole difference between "dumb" and "not dumb" here.

	------------------------------------------------------------------
	UNITS
	------------------------------------------------------------------
	GameplayFootball works in metres on a 110 x 72 m pitch (half-length 55 m).
	Beyond 90's pitch measures 343 x 241 studs (half-length 171.5), so distances
	convert at roughly 3.1 studs per metre. Callers pass Beyond 90 studs and
	seconds; the constants in AIConfig record the metre value they came from.
	Times are real seconds in both, so the timing model carries over unchanged.
]]
local BallControlMath = require(script.Parent.BallControlMath)

local AITacticalEvaluator = {}

export type Opponent = {
	Position: Vector3,
	Velocity: Vector3,
	IsGoalkeeper: boolean?,
}

--[[
	UNITS INSIDE THE FORMULA, not just around it.

	The reference's interception model mixes seconds with DISTANCES, and two of
	its coefficients are therefore per-metre quantities that cannot be carried
	over unchanged:

		0.7 + travel * 0.03      seconds of ball flight; 0.03 is s per METRE
		(perpendicular + 1) / v  the +1 is one METRE of acceleration slack

	Converting the tuning constants in AIConfig but leaving these at their metre
	values made every ground pass look suicidal. Measured over 400 3v3-shaped
	passes with the raw coefficients: mean ground odds 0.004 -- the danger term
	saturated at its cap essentially always, because a 60-stud pass was being
	charged the flight time of a 60-METRE one. Lofted passes escaped it only
	because their opponent window is narrower, so the AI lobbed everything.

	GameplayFootball's pitch is 110 m long; Beyond 90's is 343 studs. Both are
	converted at that ratio below.
]]
local STUDS_PER_METRE = 343 / 110
-- Fixed cost of striking and settling the ball, in seconds. Already a time.
local BALL_BASE_SECONDS = 0.7
-- Reference: 0.03 seconds per metre of travel.
local BALL_SECONDS_PER_STUD = 0.03 / STUDS_PER_METRE
-- Reference: 1 metre of slack, standing in for the opponent's acceleration.
local INTERCEPT_SLACK_STUDS = 1 * STUDS_PER_METRE

local function normalizedClamp(value: number, low: number, high: number): number
	return math.clamp((value - low) / math.max(high - low, 1e-4), 0, 1)
end

--[[
	How free a point on the pitch is, 0 (crowded) .. 1 (open).

	CONFIRMED: AI_CalculateFreeSpace. Opponents are not measured where they
	stand -- each is advanced by its own velocity and then run toward the point
	at sprint speed for the remaining lookahead, so "space" means space that
	will still be there when the ball arrives rather than space that is there
	now. That single detail is what stops an AI passing into a gap that is
	visibly closing.
]]
function AITacticalEvaluator.CalculateFreeSpace(
	focusPosition: Vector3,
	opponents: { Opponent },
	safeDistance: number,
	futureTimeSeconds: number,
	sprintSpeed: number,
	crowdedCount: number
): number
	local crowding = 0

	for _, opponent in opponents do
		-- The keeper is ignored: it is not what makes outfield space dangerous.
		if opponent.IsGoalkeeper ~= true then
			local position = opponent.Position + BallControlMath.GetHorizontal(opponent.Velocity) * 0.2

			local toFocus = BallControlMath.GetHorizontal(focusPosition - position)
			local closingDistance = sprintSpeed * math.max(futureTimeSeconds - 0.2, 0)
			local step = if toFocus.Magnitude > 1e-4
				then toFocus.Unit * math.min(closingDistance, toFocus.Magnitude)
				else Vector3.zero
			position += step

			local gap = BallControlMath.GetHorizontal(position - focusPosition).Magnitude
			crowding += 1 - math.clamp(gap, 0, safeDistance) / math.max(safeDistance, 1e-4)
		end
	end

	-- Saturates deliberately: one opponent right on top of the point is already
	-- close to "no space", and a third makes little further difference.
	return 1 - normalizedClamp(crowding, 0, crowdedCount)
end

--[[
	Will the ball survive the journey? 0 (certain interception) .. 1 (clean).

	CONFIRMED: _GetPassingOdds. For every opponent it compares two times to the
	point on the pass line the opponent could most easily reach:

		how long the OPPONENT needs to get there
		how long the BALL needs to get there

	and accumulates the shortfall. It is a genuine race, not a corridor width
	check, which is why it correctly permits a fast ball threaded past someone
	who cannot turn in time and correctly refuses a slow one into open grass a
	defender is already jogging across.

	`lofted` reproduces the reference's high-pass handling: only opponents in
	the middle of the flight matter, trapping the ball costs the receiver time,
	and a flat penalty discourages lofting when a ground pass would do.
]]
function AITacticalEvaluator.GetPassingOdds(
	origin: Vector3,
	target: Vector3,
	opponents: { Opponent },
	ballSpeedMultiplier: number,
	sprintSpeed: number,
	lofted: boolean
): number
	local secondScale = 1
	local toTarget = BallControlMath.GetHorizontal(target - origin)
	local lineLength = toTarget.Magnitude
	if lineLength <= 1e-3 then
		return 0
	end
	local lineDirection = toTarget.Unit

	local danger = 0
	for _, opponent in opponents do
		local position = opponent.Position + BallControlMath.GetHorizontal(opponent.Velocity) * 0.2
		local toOpponent = BallControlMath.GetHorizontal(position - origin)

		-- Where along the pass this opponent sits, 0 = at my feet, 1 = at the
		-- receiver. Deliberately unclamped: slightly past the receiver still
		-- counts, because the ball can be cut out on the far side of them.
		local u = toOpponent:Dot(lineDirection) / lineLength
		if u >= 0 and u <= 1.2 then
			local relevant = if lofted then (u >= 0.2 and u <= 0.65) else true
			if relevant then
				local clampedU = math.clamp(u, 0, 1)
				local intersect = origin + toTarget * clampedU
				local perpendicular = BallControlMath.GetHorizontal(position - intersect).Magnitude

				-- +1 stud of slack stands in for the acceleration the opponent
				-- needs before it is actually moving at sprint speed.
				local opponentSeconds = (perpendicular + INTERCEPT_SLACK_STUDS)
					/ math.max(sprintSpeed, 1e-3)

				-- Trapping a dropping ball costs the receiver real time, so a
				-- lofted pass is more interceptable late in its flight.
				local trapPenalty = if lofted and u > 0.5 then 2.5 else 0
				local travel = BallControlMath.GetHorizontal(intersect - origin).Magnitude
				local ballSeconds = (BALL_BASE_SECONDS + travel * u * BALL_SECONDS_PER_STUD + trapPenalty)
					/ math.max(ballSpeedMultiplier, 1e-3)

				-- Half a second of headroom: arriving simultaneously is already
				-- dangerous, so zero margin must not read as zero danger.
				danger += math.clamp(ballSeconds - opponentSeconds + secondScale * 0.5, 0, secondScale)
			end
		end
	end

	if lofted then
		danger += 0.4
	end

	return 1 - normalizedClamp(danger, 0, secondScale)
end

--[[
	How good is this footballer's situation, independent of the ball?

	CONFIRMED: Player::_CalculateTacticalSituation. Three components:

		ForwardSpace  space half a second's sprint AHEAD -- can I run into it?
		Space         space where I am standing         -- am I under pressure?
		Forward       progress toward the opponent goal, raised to 1.5 so the
		              last third counts for far more than the first

	The carrier compares its own rating against every team-mate's. A pass only
	happens when someone is genuinely better placed, which is the reference's
	answer to "when should I release the ball" and the reason its AI does not
	simply hammer the ball forward whenever a lane happens to be open.
]]
function AITacticalEvaluator.RateSituation(
	position: Vector3,
	velocity: Vector3,
	attackDirection: Vector3,
	attackingGoalPosition: Vector3,
	opponents: { Opponent },
	config
): { ForwardSpace: number, Space: number, Forward: number, Total: number }
	local sprintSpeed = config.SprintSpeed
	local safeDistance = config.SafeDistance

	local forwardTime = 0.5
	local forwardCheck = position + attackDirection * sprintSpeed * forwardTime
	local forwardSpace = AITacticalEvaluator.CalculateFreeSpace(
		forwardCheck,
		opponents,
		safeDistance,
		forwardTime,
		sprintSpeed,
		config.CrowdedCount
	)

	local spaceTime = 0.1
	local spaceCheck = position + BallControlMath.GetHorizontal(velocity) * spaceTime
	local space = AITacticalEvaluator.CalculateFreeSpace(
		spaceCheck,
		opponents,
		safeDistance,
		spaceTime,
		sprintSpeed,
		config.CrowdedCount
	)

	local goalDistance = BallControlMath.GetHorizontal(attackingGoalPosition - position).Magnitude
	local forward = 1 - math.clamp(goalDistance / math.max(config.PitchLength, 1e-3), 0, 1)
	forward = forward ^ 1.5

	local total = (
		forwardSpace * config.ForwardSpaceWeight
		+ space * config.SpaceWeight
		+ forward * config.ForwardWeight
	) / math.max(config.ForwardSpaceWeight + config.SpaceWeight + config.ForwardWeight, 1e-4)

	return { ForwardSpace = forwardSpace, Space = space, Forward = forward, Total = total }
end

return AITacticalEvaluator
