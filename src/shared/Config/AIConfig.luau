local PlayerConfig = require(script.Parent.PlayerConfig)

--[[
	AI footballers are physically identical to human footballers.

	These speeds are read from the human locomotion configuration rather than
	restated, so an AI can never end up slower simply because a duplicated
	constant drifted. What the AI decides -- when to jog, when to sprint -- is
	still entirely the AI's, but the capability it is choosing between is the
	same capability a human has.
]]
local HUMAN_JOG_SPEED = PlayerConfig.Movement.BaseSpeed
local HUMAN_SPRINT_SPEED = PlayerConfig.Movement.SprintSpeed

local AIConfig = {
	Enabled = true,
	ModeId = "Quick3v3",
	TeamSize = 3,
	FootballerFolderName = "Footballers",
	Attributes = {
		Id = "Beyond90FootballerId",
		Kind = "Beyond90FootballerKind",
		Role = "Beyond90FootballerRole",
		State = "Beyond90AIState",
		Decision = "Beyond90AIDecision",
		DecisionAge = "Beyond90AIDecisionAge",
		MovementTarget = "Beyond90AIMovementTarget",
		FormationTarget = "Beyond90AIFormationTarget",
		TimeToBall = "Beyond90AITimeToBall",
		Possession = "Beyond90AIHasPossession",
	},

	Cadence = {
		PerceptionInterval = 0.15,
		ReactionDelay = 0.18,
		TeamInterval = 0.25,
		IndividualInterval = 0.18,
		MovementInterval = 1 / 30,
		DebugInterval = 1.5,
		-- A team that has just won the ball must not keep behaving as if the ball
		-- were loose. Possession-confirming transitions commit immediately; only
		-- losing possession keeps the bounded reaction delay.
		PossessionCommitImmediate = true,
		TransitionHoldSeconds = 0.35,
	},

	Locomotion = {
		ArrivalRadius = 2.4,
		--[[
			Arrival damping, not a general speed cap.

			This used to taper from 10 studs out down to 30% of full speed, and
			an AI holding a formation anchor is almost always inside that band --
			so the whole team permanently ran at roughly a third of its capable
			speed. The taper now starts close to the target and never drops below
			a brisk floor, so slowing down reads as arriving rather than as being
			slow.
		]]
		SlowRadius = 4,
		SlowMinimumScale = 0.55,
		PitchBoundaryMargin = 4,
		TurnResponsiveness = 8,
		AccelerationTime = 0.22,
		DecelerationTime = 0.5,
		SprintDistance = 24,
		--[[
			Distance thresholds at which an attacking run or a support run becomes
			a sprint (§51). These are much shorter than SprintDistance because an
			attacking run is meant to beat a defender over a short distance, not
			to cover a quarter of the pitch before it is worth accelerating.
		]]
		RunSprintDistance = 10,
		SupportSprintDistance = 15,
		JogSpeed = HUMAN_JOG_SPEED,
		SprintSpeed = HUMAN_SPRINT_SPEED,
	},

	Defending = {
		--[[
			How far goal-side of the carrier the designated presser aims.

			Small enough that the defender is genuinely engaging rather than
			dropping off, but far enough that it arrives in front of the carrier
			instead of trailing it -- the tackle evaluator requires the challenge
			to come from the front.
		]]
		PressStandoff = 3.2,
		-- Inside this distance from the football a presser faces the ball rather
		-- than its own movement direction.
		FaceBallDistance = 9,
		-- Turn responsiveness for that facing, per second.
		FaceBallResponsiveness = 9,

		--[[
			Recovery when caught behind (§38).

			Dot of the approach direction against the carrier's heading above
			which the defender is genuinely behind and must recover rather than
			challenge. 1.0 is directly behind.
		]]
		BehindRecoveryDot = 0.3,
		-- How far down the carrier's path the recovery line aims, as a multiple
		-- of the current gap, bounded at both ends.
		RecoveryLeadScale = 1.25,
		MinimumRecoveryLead = 8,
		MaximumRecoveryLead = 30,
		-- Recover on the side the defender is already on; cutting across the
		-- carrier is the path that runs through them.
		RecoveryLateralOffset = 4.5,
		-- Angle of approach when containing, so the challenge is not head-on into
		-- the carrier's chest.
		ContainLateralOffset = 2.6,
		-- Cap on how far ahead an interception is projected.
		MaximumInterceptLead = 1.1,

		--[[
			Speed selection while pressing (§85).

			Beyond EngageDistance the presser sprints to close the gap; inside it
			the presser slows to a jockey so it can react to a change of direction
			instead of running past.
		]]
		EngageDistance = 9,
		JockeySpeedScale = 0.62,

		--[[
			CONTAINMENT MUST EVENTUALLY BECOME A CHALLENGE.

			The press used to be containment and nothing else: the designated
			defender walked to a point PressStandoff studs goal-side of the
			carrier and stood there. Against a carrier who is running, that is
			correct football -- you jockey and wait for them to make the mistake.
			Against a carrier who is STANDING STILL it is a permanent stalemate,
			and it is exactly what the runtime showed: fifteen seconds of
			`state=OutOfPossession designated=AWAY_AI_2 timeToBall=0.20` while the
			human stood on the ball and nobody came.

			The gap is that nothing ever escalated. Two things fix it, and they
			mirror what a real defender does:

			  1. A stationary carrier is closed down TIGHTER. You do not stand off
			     someone who is not going anywhere; you step in. So the standoff
			     shrinks with the carrier's speed.

			  2. Dwelling on the ball invites a challenge. Once the same defender
			     has contained the same carrier for CommitAfterSeconds, the target
			     becomes the BALL rather than a containment point, which puts the
			     defender inside tackle range and lets the ordinary tackle
			     evaluation decide whether the challenge is on.

			Neither of these makes the AI tackle more often than the rules allow:
			the challenge still has to pass the same legality and score checks a
			human's does.
		]]
		-- Carrier speed at or above which full containment standoff is used.
		ContainSpeed = 8,
		-- Standoff used against a carrier who is standing still. Inside the AI
		-- tackle range on purpose -- this IS the step-in.
		StepInStandoff = 1.8,
		-- How long a contained carrier may dwell before the presser goes for the
		-- ball itself.
		CommitAfterSeconds = 1.1,
		-- The presser must actually be engaged for dwell to accumulate; a
		-- defender still running from thirty studs is not containing anybody.
		DwellEngageDistance = 7.5,

		--[[
			THE SECOND MAN.

			eFootball's pressure does not come from one defender; the nearest
			player contains and a second closes the passing angle and the space
			behind. Beyond 90 only ever designated ONE presser, so a carrier under
			pressure had a completely free pitch behind the man in front of them.

			The support presser closes, but does NOT challenge -- tackling stays
			restricted to the designated presser so a team cannot collapse into
			simultaneous challenges. It is pressure, not a swarm.
		]]
		SupportPress = {
			Enabled = true,
			-- Only worth sending a second man once the carrier is this close to
			-- our goal; further out, shape matters more than pressure.
			MaximumDistanceFromGoal = 150,
			-- Where the second man stands: further off, and on the opposite side
			-- to the first, so between them they cover both ways out.
			Standoff = 8.5,
			LateralOffset = 6.5,
			-- Never pull a defender across the whole pitch to support a press.
			MaximumTravel = 42,
		},
	},

	Character = {
		TeamColors = {
			Home = Color3.fromRGB(43, 126, 255),
			Away = Color3.fromRGB(230, 62, 78),
		},
		TeamColorBlend = 0.5,
	},

	-- 3v3 stays three OUTFIELD footballers per side; the goalkeeper is an
	-- additional slot, not one of the three.
	GoalkeeperEnabled = true,
	GoalkeepersPerTeam = 1,

	Formation = {
		LongitudinalScale = 0.34,
		WidthScale = 0.25,
		BallShift = 0.28,
		PossessionAdvance = 0.09,
		DefensiveRetreat = 0.1,
		MinimumTeammateSpacing = 14,
		Roles = {
			Defender = { Longitudinal = -0.52, Lateral = -0.18 },
			Support = { Longitudinal = -0.02, Lateral = 0.28 },
			Forward = { Longitudinal = 0.48, Lateral = -0.12 },
			Goalkeeper = { Longitudinal = -0.94, Lateral = 0 },
		},
	},

	--[[
		Set pieces (§80). An AI taker plays a legal restart action rather than
		acquiring possession, so these are the only timings it needs.
	]]
	Restart = {
		-- A beat between arriving over the ball and playing it, so a restart is
		-- never taken on the frame the taker stops moving.
		TakeDelaySeconds = 0.45,
		-- Bounded retry when the restart could not be played yet (no receiver in
		-- range, cooldown, etc.). Never a per-frame retry.
		RetrySeconds = 0.6,
	},

	LooseBall = {
		PredictionTimes = { 0, 0.2, 0.4, 0.65, 0.9 },
		ReachRadius = 2.8,
		AcquisitionDistance = 4.6,
		MaximumAcquisitionHeight = 2.25,
		MaximumAcquisitionSpeed = 52,
		DesignatedChaserHysteresis = 0.22,
		IntendedReceiverBonusSeconds = 0.42,
	},

	Possession = {
		MinimumDecisionAge = 0.65,
		ActionCooldown = 0.85,
		CarryLeadDistance = 3.1,
		SupportDistance = 22,
		RunDistance = 34,
		OpponentAvoidRadius = 16,
		OpponentAvoidStrength = 0.75,

		-- Secure phase. GameplayFootball settles a won ball before the player
		-- resumes tactical movement; sprinting away from a just-trapped ball is
		-- what produced the large negative leads and distance-exceeded releases.
		SecureDurationSeconds = 0.55,
		SecureMoveSpeed = 8,
		SecureLeadDistance = 12,
		-- Carry speed is bounded by how far the ball currently trails the
		-- footballer, so an AI can never outrun its own controlled football.
		CarryMaxSpeed = 22,
		CarryLeadSlowStart = 3.4,
		CarryLeadSlowFull = 7.5,
		CarryLeadSlowMinScale = 0.32,
		CarryRecoverySpeedBonus = 4,
	},

	-- Server-side controlled-ball servo for AI footballers. Humans get the same
	-- football relationships from ControlledBallController on their own client;
	-- the AI equivalent has to run here because an AI has no client.
	ControlledBall = {
		Enabled = true,
		NoTouchDuration = 0.16,
		PositionGain = 7.5,
		VelocityDamping = 2.1,
		PlayerVelocityScale = 0.85,
		MaxDeltaSpeedPerSecond = 120,
		MaxCorrectionSpeed = 34,
		RecoverPositionGain = 15,
		RecoverVelocityDamping = 3.2,
		RecoverLeadError = 2.6,
		DeadzoneStuds = 0.12,
		DiagnosticInterval = 1.5,
	},

	--[[
		Pass selection itself now lives in `Decision`, ported from
		GameplayFootball. The lane/space/forward scoring that used to sit here
		was replaced by the reference's tactical rating plus interception odds,
		so those weights are gone rather than left behind to look tunable when
		nothing reads them.
	]]
	Passing = {
		-- Fallback when the chooser somehow returns no pass type.
		ActionType = "GroundPass",
		-- How long a chosen receiver is held before the carrier may re-aim.
		CommitmentSeconds = 0.65,
	},

	--[[
		ON-THE-BALL DECISION (GameplayFootball, elizacontroller.cpp).

		See `src/shared/Football/AITacticalEvaluator.luau` for the source
		reference and the reasoning. These are the reference's own weightings;
		distances are its metre values converted at ~3.1 studs/m, the ratio
		between GameplayFootball's 55 m half-pitch and Beyond 90's 171.5 studs.
	]]
	Decision = {
		-- Rating weights. GameplayFootball scales ForwardWeight by a role
		-- "mindset" from 2 (defender) to 8 (striker); 3v3 footballers are
		-- all-rounders who attack and defend, so they sit mid-range.
		ForwardSpaceWeight = 0.4,
		SpaceWeight = 0.3,
		ForwardWeight = 3.5,
		-- Radius that counts as personal space. GF 5 m.
		SafeDistance = 15.5,
		-- Crowding at which a point is considered fully closed down.
		CrowdedCount = 2.5,
		SprintSpeed = HUMAN_SPRINT_SPEED,

		--[[
			How much better placed a team-mate must be before the carrier will
			give them the ball. This is the number that turns a ball-hog into a
			footballer: without it the AI passes to anyone reachable, and with it
			too high the AI never releases at all.
		]]
		TacticalImprovementThreshold = 0.05,
		-- Second-stage weighting: how much the positional gain matters against
		-- the raw chance of the ball arriving.
		TacticalDiffWeight = 4,
		PassWeight = 1,
		-- Odds floor. Below this the pass is not attempted whatever the gain.
		PassMinimum = 0.16,
		PassThreshold = 0.1,

		--[[
			The longer a footballer holds the ball the more willing it becomes to
			release it (GF `longPossessionFactor`, squared over 5 seconds).

			This is the direct fix for the carrier that dribbled in a straight
			line for six to ten seconds before shooting -- the reference makes
			holding on progressively less attractive rather than forbidding it.
		]]
		LongPossessionSeconds = 5,
		LongPossessionThresholdRelief = 0.05,
		LongPossessionMinimumRelief = 0.1,

		--[[
			THE GATE THAT ACTUALLY DECIDED EVERYTHING.

			A pass was only ever CONSIDERED when a team-mate rated better placed
			than the carrier by TacticalImprovementThreshold. That test is
			GameplayFootball's, and it is right -- but the rating is dominated by
			how far forward you are (ForwardWeight 3.5), and the carrier driving
			at goal is by construction the furthest-forward player on their team.
			So no team-mate ever cleared the bar, and the runtime showed the
			consequence plainly: single carries of 15.5 and 17.0 seconds, ending
			in a shot, with no pass attempted at all.

			The long-possession relief existed to fix exactly this, but it was
			only applied to the odds thresholds -- which are evaluated AFTER this
			gate. A carrier fifteen seconds into a dribble still refused to look
			at anybody. The relief now applies to the gate as well, so the bar
			falls as you hold the ball and eventually goes negative: after a few
			seconds a footballer will give the ball to someone no better placed
			than themselves, which is what a footballer does.

			Pressure does the same thing faster. A carrier being closed down does
			not stand there computing whether the pass is an improvement; they
			release it. Below is how much of the bar the closest opponent removes.
		]]
		LongPossessionImprovementRelief = 0.22,
		-- Opponent distance at which the carrier is fully under pressure.
		PressureDistance = 12,
		-- How much of the improvement bar full pressure removes.
		PressureImprovementRelief = 0.18,

		-- "Don't like playing back to the goalie" -- GF's comment, and its 0.7.
		GoalkeeperReceiverPenalty = 0.7,
		-- Below this a lofted ball is pointless; play it along the ground. GF 10 m.
		LoftedMinimumDistance = 31,
		--[[
			Pass odds below which a pressured carrier deep in its own half gives
			up on football and clears instead (GF `_AddPanicPass`). Deliberately
			low: clearing is the last resort, not the default response to
			pressure.
		]]
		PanicPassOdds = 0.3,
		GroundBallSpeedMultiplier = 1,
		LoftedBallSpeedMultiplier = 1,
	},

	Shooting = {
		--[[
			SHOOTING IS A POSITION, NOT A DISTANCE.

			The old gate was `distance <= 82 studs and alignment >= 0.58`, which
			on a 343-stud pitch permitted a shot from inside the AI's own half.
			The playtest log is a wall of 77-79 stud shots because of it, and
			since shooting was tested before passing it also suppressed every
			pass the AI might otherwise have made.

			GameplayFootball instead measures how close the footballer is to an
			IDEAL SHOOTING POSITION -- a point in front of the goal -- and fades
			the willingness to shoot out with an S-curve. Outside the radius the
			shot is not considered at all, so the decision falls through to
			passing on its own rather than being ordered around it.
		]]
		-- The ideal spot, out from the goal line. GF 7 m.
		IdealDistanceFromGoal = 22,
		-- Radius around it inside which shooting is considered. GF 16 m.
		IdealRadius = 50,
		-- Below this positional factor, no shot is evaluated.
		MinimumPositionFactor = 0.1,

		--[[
			Three aim points are tested -- near post, centre, far post -- and the
			least defended one is chosen, exactly as the reference does. A shot
			is a pass to the back of the net, so it is scored with the same
			interception model, at 3x ball speed.
		]]
		AimHalfWidth = 11,
		BallSpeedMultiplier = 3,
		--[[
			Fire when `odds + random(0, 0.5) > 0.5`. The randomness is the
			reference's, and it matters: it stops a whole team of AI footballers
			in similar positions making identical decisions on the same frame.
		]]
		OddsThreshold = 0.5,
		OddsRandomRange = 0.5,
		-- Distance at which a shot is hit at full power. GF 32 m.
		FullPowerDistance = 100,

		MinimumScore = 0.55,
		Skill = 0.76,
	},

	Clearance = {
		DefensiveProgressThreshold = -0.42,
		PressureDistance = 13,
	},

	Recovery = {
		OutOfPlayPadding = 8,
		StationarySpeed = 2.5,
		ResetDelay = 3,
	},

	Debug = {
		Enabled = true,
		VisualTargets = false,
		RateLimitedLogs = true,
	},
}

return AIConfig
