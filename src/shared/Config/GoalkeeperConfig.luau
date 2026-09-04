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
		--[[
			WHERE THE HELD BALL SITS, RELATIVE TO THE KEEPER'S CHEST.

			This was `HoldHeight = 2.6` fed through `rootY + HoldHeight -
			rootSize.Y/2`, which put the ball about 1.6 studs above the root --
			around 83% of body height, so level with the neck and head rather than
			gathered into the body.

			The HumanoidRootPart already sits at roughly 60% of body height on an
			R15 rig, which IS chest height, so the honest offset is a small one
			from the root and nothing to do with the root's own size. Positive
			raises it.
		]]
		HoldChestOffset = 0.1,
		HoldSeconds = 1.5,
		MaximumHoldSeconds = 5,
		--[[
			AUTOMATIC DISTRIBUTION IS AN AI DECISION, NOT A HUMAN ONE.

			`HoldSeconds` and `MaximumHoldSeconds` above make a keeper throw or
			kick the ball away on a timer. For an AI keeper that IS the decision
			-- section 2 puts tactical choice on the AI side for AI-controlled
			footballers, and a keeper who never distributes would stall the game.

			For a HUMAN keeper it is the opposite: the ball left their hands
			without them choosing to release it, which is precisely the thing
			section 2 forbids ("whether they should pass" is not the game's call).
			So a human keeper holds until they throw or kick.

			Set to a positive number of seconds to restore a safety release for
			humans -- e.g. football's own six-second rule, if that is ever
			implemented as an offence rather than as an automatic throw. Zero
			means the keeper holds until the player acts.
		]]
		HumanMaximumHoldSeconds = 0,
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
		--[[
			The drop kick. Struck rather than thrown: it trades the throw's
			accuracy for range, which is the choice the control exists to give.
		]]
		--[[
			THE DROP KICK. Reported as not going far enough.

			96 forward and 34 up carries 96 * 68 / 196.2 = 33 studs -- a punt
			that lands barely outside the six-yard box, which is not a
			distribution, it is a pass to the nearest opponent.

			Sized the same way as the goal kick below: a keeper's punt should
			clear the halfway line. 130 forward and 112 up carries 148 studs with
			1.14s of airtime, so it travels most of the pitch and is in the air
			long enough to read as a punt.
		]]
		DropKickSpeed = 130,
		DropKickLift = 112,

		--[[
			How long a keeper who has DELIBERATELY PUT THE BALL DOWN is stopped
			from re-claiming it.

			Much longer than the distribution grace, because it is answering a
			different question. A distribution only needs to survive the one
			frame where the ball sits in the keeper's own hands; a deliberate
			drop has to survive long enough for the keeper to actually step
			round the ball and play it with their feet. At 1.1s they were
			re-catching it before they could move.

			Pressing R again lifts this immediately -- that is the player asking
			for their hands back, and refusing them would be the same bug in the
			opposite direction.
		]]
		DropGraceSeconds = 4,

		--[[
			THE GOAL KICK. Struck to clear the halfway line.

			Reported as not going far enough. It was borrowing the drop kick's
			96/34, and 34 studs/s of lift is a driven ball -- the log shows it
			bouncing 0.3s after leaving the foot and running out at around 90
			studs, well short of halfway.

			A goal kick is a different strike: hit UP as much as forward, to
			clear the press and land in the opposition half.

			Sized from the pitch rather than by feel. Range for a projectile is
			v_h * 2 * v_v / g, and Roblox gravity is 196.2 studs/s^2. The kick is
			taken from the six-yard line at z=193.8 and the halfway line is at
			z=36, so the far half starts 158 studs away. At 125 forward and 100
			up the ball carries 125 * 200 / 196.2 = 127 studs and then rolls,
			which puts it into the opposition half rather than at the edge of it.

			It also spends 1.02s in the air and peaks 25 studs up, so it reads as
			a goal kick being launched rather than as a hard pass.
		]]
		GoalKickSpeed = 138,
		GoalKickLift = 122,

		--[[
			HOW LONG A KEEPER MAY NOT RE-HANDLE WHAT THEY JUST RELEASED.

			The ball leaves the hands at 62-96 studs/s, so it is 60+ studs clear
			within a second -- an order of magnitude outside the 6.4-stud
			assisted-save radius that was catching it again on the next frame.
			A second is therefore ample, and this is not a timer the player can
			feel: it ends the instant anybody else touches the ball.

			The upper bound matters more than the lower one. It exists so a
			clearance that reaches nobody -- straight out for a throw-in, say --
			cannot leave the keeper permanently unable to use their hands.
		]]
		ReleaseGraceSeconds = 1.1,
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
		--[[
			HOW FAR A DIVE ACTUALLY GOES.

			Reported as covering too little ground. It was 19/27/31 studs/s over
			0.62s, and a dive is decelerating the whole way, so a low dive was
			travelling around eight studs -- barely more than the keeper's own
			standing reach, which is why committing to one felt like it bought
			nothing.

			Raised together with the duration, because distance is the product of
			the two and lengthening only the speed makes the launch look like a
			catapult. A low dive now covers roughly the distance between the
			centre of the goal and a post, which is the distance the dive exists
			to cover.
		]]
		StepSpeed = 24,
		LowDiveSpeed = 50,
		HighDiveSpeed = 56,
		-- Upward component, so a high dive actually leaves the ground.
		--[[
			HOW HIGH THE KEEPER ACTUALLY LEAVES THE GROUND.

			These were 5 and 13, which read as "a slight lift" but produce no
			visible flight at all. Roblox gravity is 196.2 studs/s^2, so with
			apex = v^2/2g and hang = 2v/g:

				lift  5 -> apex 0.06 studs, airborne 0.05s   (invisible)
				lift 13 -> apex 0.43 studs, airborne 0.13s   (barely a hop)

			The keeper is 6 studs tall, so 0.06 studs is nothing -- he slid along
			the grass and stood back up without ever leaving it, which is what
			"does not fall to the floor before getting up" describes. (The value
			was also being dropped entirely by the client, which is fixed
			separately; raising it alone would not have shown.)

				lift 24 -> apex 1.47 studs, airborne 0.24s   LOW  dive
				lift 40 -> apex 4.08 studs, airborne 0.41s   HIGH dive

			A low dive is a shallow leap of about a quarter of body height; a
			high dive clears two thirds of it. Both land well inside the 0.78s
			dive window, so the keeper is on the ground before the get-up starts
			-- he falls, lands, and then rises, in that order.
		]]
		--[[
			BALLISTIC LAUNCH LIFT -- AI KEEPERS ONLY.

			The server owns an AI keeper's body, so it writes this into
			`AssemblyLinearVelocity` directly and gravity draws the arc. A HUMAN
			keeper's body is owned by their client and no longer uses this at
			all: see `DiveArc` below for why.

			Kept small deliberately. At 24 studs/s this reads as a vertical hop
			at the moment of launch rather than as a dive, because the upward
			velocity is at its maximum on the very first frame while the lateral
			travel has not visibly accumulated yet.
		]]
		LowDiveLift = 8,
		HighDiveLift = 16,

		-- A dive commits. The keeper cannot re-steer mid-air, which is what makes
		-- going the wrong way a genuine mistake.
		--[[
			HOW LONG THE KEEPER IS COMMITTED, AND THEREFORE HOW FAR HE GOES.

			Reported as looking like slow motion. It was: 0.78s of travel with
			the dive clip stretched across all of it, so both the body and the
			animation read as underwater.

				before  0.78s x 38 studs/s = 29.6 studs
				after   0.60s x 58 studs/s = 34.8 studs

			-- shorter, quicker, and further, which is the shape of a real dive.
			`AnimationConfig.Goalkeeper.DivePlaybackRate` is set from this: the
			clip's fall takes about 1.3s, so it needs 1.3 / 0.60 = 2.2 to finish
			inside the window. Change one and the other must follow.
		]]
		Duration = 0.60,

		--[[
			THE HUMAN KEEPER'S VERTICAL ARC, DRIVEN RATHER THAN THROWN.

			A ballistic impulse cannot express this shape. Its vertical speed is
			highest on the first frame and decays, so the body's fastest upward
			motion happens before the dive has visibly begun -- which is what
			"jumps a bit just before diving" describes. It also cannot put the
			keeper BELOW standing height, and lying on the grass is exactly
			where a dive ends.

			So the client drives the height across the dive instead:

				0.00 -> 0.28   rising    0 -> +1.3 studs, easing into the apex
				0.28 -> 1.00   falling  +1.3 -> -2.4 studs, accelerating

			ending 2.4 studs below standing hip height, which is the keeper on
			the floor. The get-up then raises him back over the get-up CLIP's
			own window, so he lands, stays down, and pushes up -- in that order.

			Applied through `Humanoid.HipHeight`, not by writing the root's Y.
			The Humanoid maintains hip height against the floor itself, so there
			is nothing to fight, the state stays Running (a thrown body enters
			Freefall, which the airborne test then treats as airborne and flips
			the animation), and the ground contact stays correct on a slope.
		]]
		DiveArc = {
			LeapApexStuds = 1.3,
			GroundDropStuds = 2.0,
			ApexFraction = 0.28,
			--[[
				WHEN THE KEEPER IS DOWN, as a fraction of the dive.

				The fall used to run to the very last frame of the dive, on a
				squared curve -- so its DOWNWARD RATE WAS AT ITS MAXIMUM at the
				instant it stopped, and the get-up then began from a standstill.
				That step change in vertical rate is the jolt on landing: nothing
				decelerated, the descent simply ceased.

				Landing early leaves the keeper flat on the grass for the last
				15% of the dive, and the fall between apex and landing is now
				eased at BOTH ends (zero rate leaving the apex, zero rate meeting
				the ground). The get-up already starts at zero rate, so the whole
				arc is continuous from launch to standing.
			]]
			LandFraction = 0.85,
		},
		RecoverySeconds = 0.55,
		--[[
			How long the keeper takes to get back on their feet.

			The body is rolled nearly flat by the dive and NOTHING in a Humanoid
			unrolls it -- see MovementController's dive tilt, where leaving it
			rolled left the keeper lying on the pitch flipping between airborne
			and idle for the rest of the match. This is the window the roll is
			unwound over.
		]]
		StandUpSeconds = 0.34,

		--[[
			THE KEEPER IS NOT DRIVING WHILE THEY GET UP.

			Reported: after a dive the keeper "glitches by moving backwards".
			The roll was being unwound correctly, but movement input was live the
			whole time -- so a keeper still holding a direction (or simply still
			carrying the input they dived with) was being walked around by the
			humanoid while the body was rotating back upright. The two fought,
			and the result read as sliding backwards out of the dive.

			Getting up is committed, like the dive itself. Input is refused for
			this long, measured from the end of the dive, and then handed back.
			Kept under the stand-up window so control returns the moment the
			keeper is on their feet rather than a beat later.
		]]
		StandUpInputLockSeconds = 0.3,
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
		--[[
			How long a click waits for a side before diving centrally.

			Long enough to catch a genuine click-then-press, short enough that a
			player who meant to dive straight never feels the game hesitate.
		]]
		DiveAimGraceSeconds = 0.2,

		--[[
			HOW FAR A KEEPER MAY TURN.

			Half a circle centred on facing out of their own goal, so the keeper
			can square up to an attacker arriving at either post -- the full width
			of anything that can actually threaten them -- and cannot rotate
			past the posts to face their own net.

			OBSERVED FROM FOOTAGE (ref/EA FC 26 Pro Clubs goalkeeper pov.mp4): the
			keeper's view swings from post to post as play crosses the box, and
			never turns to look into the goal, even when the ball goes behind for
			a corner. INTERPRETATION: the turn is bounded, not free-look, because
			an unbounded one loses the goal frame that the whole role is judged
			against.
		]]
		--[[
			HOW FAR OFF THEIR GOAL A KEEPER MAY TURN.

			Was 90, which permits the keeper to face fully ALONG their own goal
			line. At that extreme "across the goal" and "straight ahead" are the
			same direction for the body, so no clip selection can be right: a
			lateral shuffle and a forward jog describe the same motion. The
			runtime showed the body yaw spanning 244 degrees in one session,
			swinging 17 degrees inside 41 milliseconds on a steady input, and the
			side-step/jog flip-flop followed it exactly.

			45 keeps the keeper SQUARE, which is what a keeper does and what the
			reference shows. It also makes the two frames agree: travel across
			the goal is now at worst 45 degrees off the body's own lateral axis,
			so selecting on the goal frame (which does not move) and playing a
			clip on the body frame (which does) no longer contradict each other.

			Both posts stay reachable -- the keeper moves along their line rather
			than turning to face down it.
		]]
		MaximumFacingArcDegrees = 45,

		--[[
			How much steering it takes to override ball-tracking.

			Above this the keeper faces where the player is steering; below it
			they go back to watching the ball. Deliberately low -- any real input
			is a request to look somewhere -- but above stick drift and above the
			tiny residual magnitudes a keyboard release produces.

			Reported symptom without this: with the ball near a post the keeper
			was pinned to the edge of the facing arc and could not turn at all,
			because tracking never yielded.
		]]
		FacingOverrideThreshold = 0.2,
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
		--[[
			How much of a dive must be ACROSS the goal for it to be a dive.

			A shot-stopping dive is projected onto the goal's width axis (see
			`RequestHumanDive`). Below this the aim has no meaningful side to it
			-- the ball is coming straight at the keeper -- and the request is
			refused so the save is taken standing instead of the keeper being
			thrown sideways at nothing.

			2.5 studs against a `SpeculativeDiveDistance` of 9 means an aim
			within about 16 degrees of straight ahead takes the standing save.
		]]
		MinimumLateralDiveReach = 2.5,
		DiveCooldown = 0.35,

		--[[
			HOW FAST THE KEEPER'S BODY TRACKS THE BALL.

			A human keeper's facing is pinned to the football rather than to the
			direction they are running (MovementController.updateGoalkeeperFacing),
			so they shuffle across their line and back off toward the goal without
			ever turning their back on the play -- which is both what a goalkeeper
			does and what makes the backward and sideways jog clips select at all.

			Eased rather than snapped, at roughly the rate the reception facing
			uses, so tracking a ball across the box reads as a keeper turning
			their shoulders and not as the model spinning.
		]]
		FacingResponsiveness = 9,

		--[[
			POSITIONING ASSISTANCE IS GONE.

			`PositionAssistSpeed`, `PositionAssistDeadzone` and
			`PositionAssistMaximumDistance` used to drift the player toward the
			server's resting position whenever they were not steering. Removed at
			the player's request, and correctly so: angle and depth ARE the
			goalkeeping skill, so assisting them assists the decision rather than
			its execution, which is the line AGENTS.md §2 draws. A human keeper now
			stands exactly where they choose to stand.

			The server still publishes RestingPosition, because the AI keeper
			needs somewhere to stand.
		]]

		-- How long the keeper may hold before distribution is forced.
		HoldPromptSeconds = 0.6,
	},

	--[[
		Replicated keeper state. The client reads these to prompt the human
		keeper and to apply positioning assistance; none of them decide an
		outcome, which stays entirely on the server.
	]]
	--[[
		GROUND INDICATORS (see GoalkeeperIndicatorController).

		Reproduced from the Pro Clubs keeper view in
		`ref/EA FC 26 Pro Clubs goalkeeper pov.mp4`: a broken ring of arcs around
		the keeper that stays pale until he commits to a side, and a chevron
		pointing at a far ring marking where he should be standing.

		Colours are Beyond 90's own rather than the reference's -- cyan for the
		committed side because that is already this game's interaction colour,
		and a muted white for the resting ring so it never competes with the ball
		against grass.
	]]
	--[[
		The release reason that means "the keeper chose to put it down", as
		opposed to the ball being taken off them. Named here because
		GoalkeeperService matches on it to decide which grace applies, and a
		string typed twice is a bug waiting to happen.
	]]
	DropReason = "keeper put the ball down",

	Indicators = {
		Enabled = true,

		--[[
			MODELLED ON ref/EA FC 26 Pro Clubs goalkeeper pov.mp4.

			OBSERVED FROM FOOTAGE, frames at 0:12 and 0:20:

			  * ONE ring, and only one. A thin continuous ellipse sitting tight
			    around the keeper's feet, pale and low-contrast. It is not built
			    from visible segments and there is no second ring anywhere.
			  * At the moment of a save, two LARGE arcs appear either side of the
			    keeper at a much wider radius -- one green, one red-orange. They
			    are absent while the keeper simply stands.
			  * No chevron and no marker for where the keeper "should" be.

			INTERPRETATION: the ring is a stance/reach footprint, always on and
			deliberately quiet. The side arcs are the dive read, and they earn
			their brightness by appearing only when a dive is live.

			The previous version drew 16 spoke segments, a chevron and a second
			ring at the resting position -- which is where the reported "double
			circle underneath him" came from, since the two rings overlap
			whenever the keeper is near where it wants him.
		]]
		GroundOffset = 0.06,

		--[[
			THREE MARKS, AND NONE OF THEM UNDER THE KEEPER'S FEET.

			Read off the reference frames rather than described from memory. At
			0:13, with the keeper standing:

			  * A large pale HOOP standing up AROUND the keeper -- it rises from
			    the grass on one side, passes over his head, and comes back down
			    to the grass on the other. Head-high, thin, and grey.
			  * NO ring on the ground beneath him. The grass under his feet is
			    bare.
			  * A separate small ellipse further up the pitch, where he ought to
			    be standing.

			At 0:05, mid-dive, the hoop is gone and a bright ring sits on the
			ground where he is going.

			So the hoop is the keeper's own reach envelope, drawn in the plane he
			dives in -- which is why lighting one half of it reads as "this way".
			The ground ring is a destination, not a footprint, and belongs where
			he should be rather than where he is.
		]]

		--[[
			THE HOOP. A vertical half-circle in the keeper's lateral plane: up
			one side, over the head, down the other.

			Radius is the keeper's diving reach rather than a drawing choice.
			`Human.AssistedSaveRadius` is 6.4 -- everything inside it is saved
			without a keypress -- so a hoop of that radius is an honest picture
			of the ball the keeper can still get to. Slightly under it, so the
			mark promises a little less than the game delivers.
		]]
		--[[
			Widened from 5.6. Reported as sitting too close to the keeper -- in
			the reference the ring stands clear of the body rather than hugging
			it, so it reads as a separate mark and not as an outline of the man.
		]]
		HoopRadius = 7.4,
		HoopSegmentCount = 30,
		HoopWidth = 0.14,
		Thickness = 0.09,

		--[[
			THE HOOP IS BROKEN INTO THREE.

			The reference does not draw one unbroken arc: it is three separate
			strokes with clear gaps between them -- one either side and one over
			the top. Drawing it continuous made it read as a bubble around the
			keeper rather than as a reach indicator.

			Expressed as the fraction of each third that is actually drawn. At
			0.78 roughly a fifth of each third is gap, which is enough to read as
			three marks at a glance without the strokes becoming stubs.
		]]
		--[[
			THE THREE ARCS, MEASURED OFF THE REFERENCE FRAME AT 0:12.

			OBSERVED FROM FOOTAGE: the ring is not three equal thirds. Two LONG
			arcs run down either side of the keeper, nearly to the grass, and a
			much SHORTER arc sits over the head, with a clear gap either side of
			it. The equal-thirds version drew three identical strokes, which is
			why it still read as a broken circle rather than as the reference's
			bracket-and-cap.

			Angles are measured in the keeper's lateral plane: 0 is the grass on
			their left, 90 is directly overhead, 180 is the grass on their right.
			Explicit spans rather than a count-and-fill, because the arcs are
			deliberately different lengths and no single fill fraction can say
			that.

			Drawn: 60 + 22 + 60 = 142 degrees of the 180 available. The two
			13-degree breaks are what separates the cap from the sides in the
			footage, and the 6 degrees left at each end keeps the side arcs from
			burying themselves in the grass.

			Symmetric about 90 by construction: 6+174 = 79+101 = 180.
		]]
		HoopArcs = {
			{ Start = 6, Finish = 66 },
			{ Start = 79, Finish = 101 },
			{ Start = 114, Finish = 174 },
		},
		-- Quiet grey until the keeper commits, then blue on the side being gone
		-- to. Blue because that is already Beyond 90's interaction colour.
		--[[
			YELLOW, not grey. Asked for directly, and it is the better call
			anyway: a pale grey ring on pale grass is the one background it
			cannot survive, while warm yellow separates from turf under both the
			floodlit and daylight stadium settings.
		]]
		HoopColor = Color3.fromRGB(242, 205, 92),
		HoopTransparency = 0.5,
		CommitColor = Color3.fromRGB(90, 178, 255),
		CommitTransparency = 0.08,

		--[[
			THE TARGET RING, on the ground where the keeper should be standing --
			the position the server already publishes for the AI keeper to use.

			Hidden once the keeper is standing in it, which is what stops it
			reading as a second circle underneath them: a keeper in the right
			place should see nothing at all, and the mark should appear only when
			there is somewhere to go.
		]]
		TargetRadius = 2.4,
		TargetSegmentCount = 32,
		TargetWidth = 0.16,
		-- The resting-spot ring and its arrows, in the same yellow family as the
		-- hoop so the two read as one system rather than two unrelated marks.
		TargetColor = Color3.fromRGB(247, 214, 105),
		TargetTransparency = 0.4,
		-- Closer than this to the resting position and nothing is drawn.
		TargetHideDistance = 3.2,
		-- Fully faded in by this far away, so it arrives gradually.
		TargetFullDistance = 7,

		--[[
			THE ARROWS. Actual arrows, as the reference draws them.

			The previous version was a run of plain dashes that only implied a
			direction by fading along its length -- which does not read as
			pointing at anything. These are chevrons: each one a pair of angled
			bars meeting at a tip, stacked along the line to the target ring like
			the direction markers the footage shows on the grass.
		]]
		ArrowCount = 3,
		-- Length of each of the two bars that make one chevron.
		ArrowBarLength = 1.5,
		ArrowWidth = 0.34,
		-- Half-angle of the chevron. 38 degrees is a clear point without the
		-- bars becoming a line across the pitch.
		ArrowHalfAngleDegrees = 38,
		-- Distance between successive chevrons along the line.
		ArrowSpacing = 2.1,
		-- Left clear at each end so the arrow neither grows out of the keeper's
		-- feet nor collides with the ring.
		ArrowStartGap = 2,
		ArrowEndGap = 2.8,
	},

	ActionRemoteName = "GoalkeeperAction",
	Attributes = {
		Diving = "Beyond90GoalkeeperDiving",
		-- The launch the server approved, applied by the owning client (§32).
		DiveVelocity = "Beyond90GoalkeeperDiveVelocity",
		-- Outside their own area a keeper gets ordinary outfield controls.
		InsideOwnArea = "Beyond90GoalkeeperInsideArea",
		-- Out of the goal, toward the pitch: the centre of the keeper's turn arc.
		Pitchward = "Beyond90GoalkeeperPitchward",
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

--[[
	HANDLING OUTSIDE THE PENALTY AREA.

	A goalkeeper's hands are only a privilege inside their own penalty area.
	Outside it they are an outfield player, and picking the ball up is a direct
	free kick to the opposition -- one of the few laws in football with no
	judgement in it at all.

	Nothing here needs a new possession state: the keeper's hold IS the handling,
	so refusing the hold and awarding the free kick at the same point covers the
	whole offence. The automatic claims (the AI keeper's, and a human keeper's
	assisted gather) additionally check the area BEFORE they attempt anything, so
	a keeper who is simply positioned high up the pitch is never penalised for a
	ball rolling past them -- only a deliberate handling attempt is.
]]
GoalkeeperConfig.Handling = {
	Enabled = true,
	--[[
		Small tolerance on the penalty-area test, in normalized half-length /
		half-width, so a keeper standing exactly on the line is not punished for
		replication jitter. Football gives the benefit of the doubt on the line
		too: the line is part of the area.
	]]
	AreaMargin = 0.012,
	-- Guards against a keeper repeatedly attempting a handle in the same second
	-- turning into a stream of free kicks.
	FoulCooldown = 2.5,
}

return GoalkeeperConfig
