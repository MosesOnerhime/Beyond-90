--!strict
--[[
	Goalkeeper tuning.

	Positioning follows the GameplayFootball `goalie_default` relationships:
	the keeper stands on the angular bisector of (ball -> near post, ball -> far
	post), which splits the goal into two equal halves from the ball's point of
	view, offset forward from the line by a possession-scaled depth bias.
	See docs/research/gameplay-football/goalkeeper.md.
]]
local GoalkeeperConfig = {
	Role = "Goalkeeper",
	RoleAttributeName = "Beyond90FootballerPosition",
	HeldAttributeName = "GoalkeeperHeld",
	HolderAttributeName = "GoalkeeperHolderFootballerId",

	Positioning = {
		-- Studs in front of the goal line. Standing exactly on the line means a
		-- save can only happen once the ball is already over it.
		LineOffset = 2.4,
		-- Fraction of the way from goal toward the ball at rest.
		DepthBias = 0.16,
		-- Fraction used when the keeper commits to narrowing the angle.
		RushDepthBias = 0.52,
		MaximumAdvance = 26,
		-- Lateral travel is clamped to just inside the posts.
		PostInset = 1.1,
		-- Prediction horizon for the resting position.
		BallPredictionSeconds = 0.45,
		ArrivalRadius = 1.1,
		MoveSpeed = 15,
		RushSpeed = 26,
		RecoverSpeed = 20,
		UpdateInterval = 1 / 20,
	},

	Save = {
		Enabled = true,
		-- How far ahead the shot path is projected when testing whether the ball
		-- is bound for goal.
		PredictionSeconds = 1.6,
		PredictionSteps = 10,
		-- Widen the goal mouth slightly so the keeper reacts to shots that are
		-- only just on target. Scaled down by keeper skill.
		PanicWidthScale = 1.06,
		-- Reach envelope. Deliberately modest: no impossible save radius.
		ReachRadius = 5.2,
		DiveReachBonus = 2.6,
		MaximumSaveHeight = 9,
		ReactionDelay = 0.14,
		Cooldown = 0.55,
		--[[
			Above this ball speed a save becomes a parry rather than a clean catch,
			and it SCALES WITH SKILL (§53, §70).

			This was a single 62 studs/s, which was a reasonable value against the
			old shot power. Shots now leave the foot between 108 and 168 studs/s
			(§65), so a fixed 62 meant every genuine shot was a parry and even a
			perfect keeper could never hold one -- measured: skill 100 produced
			5 parries and 0 catches across a seven-shot set.

			Scaling it means an elite keeper CATCHES an ordinary shot and is forced
			to parry only the hardest, which is both what a real keeper does and
			what makes the difference between skill 100 and skill 50 visible.
		]]
		CatchMaximumBallSpeed = 62,
		CatchMaximumBallSpeedAtFullSkill = 145,
		CatchMaximumHeight = 6.5,
		ParryDeflectionSpeed = 26,
		ParryLift = 7,
		-- Chance the keeper simply fails, scaled by skill. Saves are never
		-- guaranteed.
		BaseFailureChance = 0.12,
	},

	Possession = {
		-- Secure goalkeeper possession is not foot-dribble possession; the ball is
		-- constrained to the keeper rather than pushed/coasted/collected.
		HoldOffset = 2.1,
		HoldHeight = 2.6,
		HoldSeconds = 1.5,
		MaximumHoldSeconds = 5,
		-- Outfield tackles cannot contest a securely held football.
		Contestable = false,
	},

	Distribution = {
		Enabled = true,
		ActionType = "GroundPass",
		MinimumDistance = 14,
		MaximumDistance = 120,
		-- Prefer a teammate; clear upfield if nobody is available.
		ClearanceSpeed = 62,
		ClearanceLift = 26,
	},

	Region = {
		-- How far from its own goal the keeper may operate at all.
		MaximumDistanceFromGoal = 34,
		-- Loose balls inside this radius may be claimed.
		ClaimRadius = 13,
		ClaimMaximumBallHeight = 5.5,
	},

	--[[
		THE DIVE (§55, §56).

		A keeper must physically go and get the ball. Previously the save simply
		fired once the football happened to come within ReachRadius of a walking
		keeper, so anything struck to a corner was unreachable no matter how good
		the keeper was -- which is why an "elite" keeper still conceded easy shots.

		The dive is real physical movement: a velocity impulse toward the
		intercept, bounded in both speed and duration. It never teleports and
		never CFrame-snaps across the goal.

		No dedicated dive clip exists yet (§103 excludes authoring one), so the
		semantic hooks are named here and pointed at the nearest existing
		presentation. Point them at real assets when they are authored.
	]]
	Dive = {
		Enabled = true,
		--[[
			Chosen from the intercept's lateral distance and height (§56):

				<= StandingReach          -> standing catch, no dive
				<= LateralStepDistance    -> a quick step across
				otherwise, low ball       -> low dive
				otherwise, high ball      -> full lateral dive
		]]
		StandingReach = 3.2,
		LateralStepDistance = 5.5,
		LowBallHeight = 3.2,

		-- How fast the keeper launches, by dive kind. Bounded: a dive is a
		-- committed movement, not a teleport.
		StepSpeed = 19,
		LowDiveSpeed = 27,
		HighDiveSpeed = 31,
		-- Upward component, so a high dive actually leaves the ground.
		LowDiveLift = 4,
		HighDiveLift = 11,

		-- A dive commits. The keeper cannot re-steer mid-air, which is what makes
		-- going the wrong way a genuine mistake.
		Duration = 0.62,
		RecoverySeconds = 0.55,
		-- Never dive for a ball that is already past the keeper.
		MaximumLateralReach = 11,
		-- Beyond this the save was never physically available.
		MaximumInterceptTime = 1.1,

		--[[
			Semantic animation hooks (§55). Presentation only -- the save outcome
			is decided by the server before any of these are played.
		]]
		Actions = {
			StepLeft = "KeeperStepLeft",
			StepRight = "KeeperStepRight",
			DiveLowLeft = "KeeperDiveLowLeft",
			DiveLowRight = "KeeperDiveLowRight",
			DiveHighLeft = "KeeperDiveHighLeft",
			DiveHighRight = "KeeperDiveHighRight",
		},
		-- Until those clips exist, this is the nearest valid reach presentation.
		FallbackAction = "KeeperCatchStanding",
	},

	--[[
		GOALKEEPER SKILL, 0-100 (§52-§54).

		Stored 0-1; the DEV panel and the HUD present it as 0-100.

		Skill degrades FOOTBALL QUALITIES, never dice. A weak keeper reacts late,
		stands in the wrong place, misjudges the intercept and spills what it
		reaches -- all of which a player can see and exploit. It is deliberately
		NOT "randomly ignore some percentage of shots", which would be
		unreadable and unfair rather than merely worse.

		At skill 1.0 every one of these terms is zero: no reaction delay beyond
		the human floor, no positioning error, no misjudgement, no handling
		failure. An elite keeper is genuinely elite -- but its REACH is still
		finite, so a shot placed outside the dive envelope still scores (§53).
	]]
	Skill = {
		Default = 0.72,
		Minimum = 0,
		Maximum = 1,
		-- DEV panel presentation.
		DevelopmentStep = 0.1,
		AttributeName = "Beyond90GoalkeeperSkill",

		--[[
			Reaction. Even a perfect keeper has the irreducible delay of a real
			one; a poor keeper adds a lot more on top.
		]]
		MinimumReactionDelay = 0.09,
		MaximumReactionDelay = 0.42,

		-- Positioning error: how far off the ideal resting spot a keeper stands.
		MaximumPositioningErrorStuds = 5.5,
		-- How long a given positioning error persists before being re-rolled, so
		-- a weak keeper drifts rather than jittering.
		PositioningErrorInterval = 1.4,

		-- Intercept misjudgement: how far along the ball path the keeper
		-- mis-reads the crossing point.
		MaximumInterceptErrorStuds = 6,

		-- Reach. Skill buys a genuinely longer dive, within a hard ceiling.
		MinimumDiveReach = 4.5,
		MaximumDiveReach = 9.5,

		-- Handling. A weak keeper parries what a strong one catches.
		MinimumCatchChance = 0.3,
		MaximumCatchChance = 1,
		-- Parry quality: a weak parry goes a shorter, less controlled distance.
		MinimumParryQuality = 0.45,

		--[[
			Decision commitment: how likely the keeper is to commit to the dive at
			all rather than staying on its feet and watching it go past.
		]]
		MinimumCommitChance = 0.55,
	},

	--[[
		THE HUMAN GOALKEEPER.

		Choosing GK now genuinely puts the player in goal, so the question is what
		a human keeper's skill is actually made of. The answer asked for is
		explicit: heavily assisted, with the skill living in the TIMING of dives
		and saves and a little in positioning.

		So the split is:

			ASSISTED, automatically          EARNED, by the player
			-------------------------        --------------------------
			standing on the right line       when to commit to the dive
			facing the ball                  which way to go
			holding what you reach           where to stand between shots
			claiming a loose ball in the box catching the rebound
			never fumbling from bad luck     staying on your feet

		Everything in the left column happens without input; nothing in the right
		column is done for the player. Concretely, a human keeper is exempt from
		every SKILL DEGRADATION the AI keeper is subject to -- no reaction delay,
		no positioning error, no intercept misjudgement, no commitment roll, no
		handling failure -- because those model a bot's competence, and a human's
		competence is their own reactions. What is NOT relaxed is REACH: the dive
		envelope is the same one an AI keeper has, so a shot placed outside it
		beats a human keeper exactly as it beats a perfect AI one.
	]]
	Human = {
		Enabled = true,
		-- Human keepers bypass the skill model entirely; their skill is timing.
		Skill = 1,

		--[[
			The automatic part. A ball that arrives within this radius is caught or
			parried without the player pressing anything -- the "heavily assisted"
			half. It is deliberately a little wider than the AI keeper's standing
			reach: a human keeper standing in the right place should not lose a
			shot straight at them to a missed keypress.
		]]
		AssistedSaveRadius = 6.4,
		-- Loose balls this close are gathered automatically.
		AssistedClaimRadius = 6,

		--[[
			The earned part. A dive request is only useful inside this window
			before the ball would arrive: dive too early and you are on the floor
			when it comes, too late and you never get there. This IS the skill.
		]]
		DiveEarliestSeconds = 1.15,
		DiveLatestSeconds = 0.06,
		-- A dive with no live shot to read still commits, so panicking costs you.
		SpeculativeDiveDistance = 9,
		DiveCooldown = 0.35,

		--[[
			Positioning assistance, applied on the client when the player is not
			steering. It is a DRIFT toward the correct line, not a snap, so a
			keeper who wants to come off their line can, and one who is not paying
			attention is still roughly where they should be.
		]]
		PositionAssistSpeed = 9,
		PositionAssistDeadzone = 1.6,
		-- Beyond this the assist is off; the player has clearly gone somewhere
		-- deliberately and must walk back themselves.
		PositionAssistMaximumDistance = 22,

		-- How long the keeper may hold before distribution is forced.
		HoldPromptSeconds = 0.6,
	},

	--[[
		Replicated keeper state. The client reads these to prompt the human
		keeper and to apply positioning assistance; none of them decide an
		outcome, which stays entirely on the server.
	]]
	ActionRemoteName = "GoalkeeperAction",
	Attributes = {
		Diving = "Beyond90GoalkeeperDiving",
		RestingPosition = "Beyond90GoalkeeperRestingPosition",
		ThreatActive = "Beyond90GoalkeeperThreat",
		ThreatPoint = "Beyond90GoalkeeperThreatPoint",
		ThreatSeconds = "Beyond90GoalkeeperThreatSeconds",
		Holding = "Beyond90GoalkeeperHolding",
	},

	Debug = {
		Enabled = true,
		LogInterval = 2,
	},
}

return GoalkeeperConfig
