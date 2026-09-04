--!strict
-- Standing tackle / press. One rule set, used identically by humans and AI --
-- neither side gets a privileged possession-stealing path.
local DefendingConfig = {
	RemoteName = "DefensiveActionRequest",
	FeedbackRemoteName = "DefensiveActionFeedback",
	DebugEnabled = true,

	Tackle = {
		ActionType = "Tackle",
		-- Reach is measured tackler-root to ball, not tackler to opponent, so a
		-- tackle can only win a football that is genuinely exposed.
		MaximumBallDistance = 6.4,
		MaximumOpponentDistance = 8.5,
		-- The tackler must be facing the contest. This is what prevents a
		-- large invisible steal radius behind the defender.
		MinimumFacingDot = 0.35,
		-- Challenging from directly behind the carrier is far less likely to win
		-- the ball cleanly. 1.0 = directly behind, -1.0 = head on.
		MaximumBehindDot = 0.72,
		BehindPenalty = 0.45,

		-- Ball exposure: how far the football currently sits from its carrier.
		-- A ball tucked under the carrier's feet is much harder to take.
		MinimumExposure = 0.9,
		FullExposure = 4.2,
		ExposureWeight = 0.55,

		-- Closing speed helps, but only up to a point.
		ClosingSpeedFull = 14,
		ClosingSpeedWeight = 0.2,
		FacingWeight = 0.25,

		-- Above this combined score the challenge wins the ball.
		SuccessThreshold = 0.52,
		-- Between these two the ball is disturbed but not won outright.
		PartialThreshold = 0.34,

		Cooldown = 0.85,
		-- A missed challenge costs the defender a moment of recovery.
		RecoverySeconds = 0.6,
		FailedRecoverySeconds = 0.95,
		-- The tackler cannot instantly re-acquire what it just poked away, so the
		-- loose ball is genuinely contestable.
		TacklerAcquisitionSuppression = 0.34,
		TacklerExitDistance = 3.2,
		VictimAcquisitionSuppression = 0.5,
		VictimExitDistance = 4.6,

		--[[
			A CLEAN win (§43).

			Not a loose-ball impulse: a short controlled touch into the tackler's
			own path, followed by a reacquisition claim so the normal Capture
			path collects it. Possession is never assigned directly, so an
			opponent standing closer can still win the second ball.
		]]
		WonBallControl = {
			-- Gentle enough to stay inside the tackler's control lane.
			Speed = 7.5,
			Lift = 1.1,
			-- How much of the touch comes from the tackler's facing rather than
			-- from the geometry of the challenge.
			FacingWeight = 0.7,
			-- Priority while collecting. Comparable to the knock-on claim:
			-- meaningful, not decisive.
			ClaimSeconds = 1.6,
			ClaimScoreBonus = 1.1,
			-- Brief, because the challenge succeeded.
			RecoverySeconds = 0.22,
		},

		-- Loose-ball impulse applied on a PARTIAL poke.
		LooseBallSpeed = 17,
		LooseBallPartialSpeed = 9,
		LooseBallLift = 2.4,
		LooseBallLateralSpread = 0.35,
	},

	Press = {
		ActionType = "Press",
		-- Bounded assistance only. The human still chooses who to press and
		-- which direction to approach from.
		Enabled = true,
		--[[
			How far out holding V still counts as a press.

			26 studs was under half the distance a footballer covers in two
			seconds, so on a 343-stud pitch the assist refused to engage from most
			of the positions a defender actually presses from and holding V read
			as doing nothing. 44 is a genuine pressing distance without becoming
			"run anywhere on the pitch for me".
		]]
		MaximumDistance = 44,

		--[[
			HOLD-V ASSISTED PRESS (§41, §42).

			The assist runs toward a point GOAL-SIDE of the carrier, offset
			laterally so the approach is angled rather than straight into the
			carrier's back. Both numbers are small: this is help arriving in a
			useful position, not a defensive autopilot.
		]]
		GoalSideStandoff = 3.4,
		ApproachLateralOffset = 2.4,
		--[[
			PRESSING RUNS THE CARRIER DOWN AND CHALLENGES WHEN IT CAN.

			This has been both ways and the reasoning for each is worth keeping,
			because the disagreement was real and the resolution is not a
			coin-flip.

			IT USED TO AUTO-CHALLENGE, and was changed to pure containment on two
			grounds. First, an observation from the earlier eFootball capture that
			the defensive controls are three distinct things -- MATCH UP, DASH &
			PRESSURE and TACKLE -- and that holding contain there does not produce
			a tackle. Second, that deciding when to commit took a football decision
			from the player, which AGENTS.md section 2 names explicitly.

			IT AUTO-CHALLENGES AGAIN, by design decision, and both grounds are
			answered rather than overruled.

			On the footage: the observation stands, but it was read too narrowly.
			The three controls remain three distinct things here -- a TAP still
			tackles at a moment of the player's exact choosing, and that is a
			different act from holding. What changed is that the hold is no longer
			required to be passive to stay distinct from the tap.

			On the decision: AGENTS.md section 2 now carries a subsection, "A Held
			Input Is Itself A Decision", written after this argument. A sustained
			input is a choice the player is making continuously, and releasing it
			ends the behaviour at once. Holding a press is a request to win the
			ball back, not a request to stand nearby.

			The genuine risk in the old version -- that it read as a lunge -- is
			answered by geometry rather than by removing the feature. The challenge
			is gated on the ball-duel angle, so one whose path runs through the
			carrier's body is never requested. See
			TackleEvaluator.BallDuelLikeliness, a close port of the test
			GameplayFootball gates its own automatic challenge on.

			This threshold is retained for the AI presser, which has always had to
			decide for itself.
		]]
		AutoTackleScore = 0.56,

		--[[
			MATCH UP -- the containment phase.

			Once the defender has closed to within ContainRange, the assist stops
			trying to reach the carrier and starts holding a position in front of
			them instead. Goal-side, square, and at a real jockeying distance.

			StandoffDistance is about 1.8 metres at this pitch's scale, which is
			the distance a defender actually contains from: close enough to deny
			the ball forward, far enough to react to a change of direction rather
			than being beaten by it. The previous 3.4 studs is barely over a
			metre -- inside touching distance, which is why defenders ended up
			overlapping the carrier's body and shoving through them.
		]]
		Contain = {
			Enabled = true,
			-- Inside this gap the press stops approaching and starts containing.
			--[[
				WAS 13, WHICH MADE THE PRESS A JOG.

				Containment caps the defender at MaximumMoveMagnitude and forbids
				sprinting, on purpose -- a defender at top speed cannot turn. But
				starting it 13 studs out meant the whole APPROACH was capped too,
				so holding the press produced a defender jogging at 72% from a
				distance where he should be closing the ground flat out. Reported
				as "the automatic sprinting does not work", and it is the same
				cause as "he doesn't get round to a good position": the curved
				recovery approach exists, it was just never run at pace.

				Now it begins just outside the standoff the defender is trying to
				hold (5.6), so the sequence is sprint the ground down, then settle
				into the jockey on arrival -- which is the eFootball behaviour the
				milestone is reproducing.
			]]
			ContainRange = 8,
			StandoffDistance = 5.6,
			--[[
				A hard floor on how close the target may be to the carrier's
				centre. Body overlap is not a football interaction -- two players
				occupying the same space reads as a physics failure, not as
				pressure -- and no amount of lateral offset elsewhere helps if the
				target itself is inside the opponent.
			]]
			MinimumBodyGap = 3.4,
			--[[
				How far the containment leads the carrier's sideways movement. A
				defender who only reacts to where the carrier IS gets beaten by
				every change of direction; one who leads too much can be sent the
				wrong way by a feint. Small, and bounded below.
			]]
			LateralLeadSeconds = 0.16,
			MaximumLateralLead = 3.2,
			-- Containment does not sprint. A defender at full tilt cannot change
			-- direction, which is exactly what jockeying is for.
			MaximumMoveMagnitude = 0.72,
		},

		--[[
			DASH & PRESSURE -- the aggressive close.

			The same containment, with the standoff pulled in and the speed cap
			lifted, engaged while the player also holds sprint. It closes the
			carrier down and forces a decision, at the cost of being far easier to
			beat with a turn -- which is the trade the reference presents it as,
			and the reason it is a separate input rather than the default.
		]]
		Dash = {
			Enabled = true,
			StandoffDistance = 3.6,
			MaximumMoveMagnitude = 1,
		},
		-- Assistance never drives the player faster than they could run.
		MaximumAssistSpeedScale = 1,

		--[[
			THE PRESS SPRINTS WHILE IT IS CLOSING (§37).

			The assist previously ran at whatever speed the player happened to be
			holding, so a press from any real distance was a jog and arrived far
			too late to be a press at all. Beyond SprintDistance the assist now
			requests sprint through the ordinary sprint path -- same top speed,
			same acceleration, same stamina cost a human pays. Inside that it
			drops back to a jockey so the defender can react to a change of
			direction instead of running past the carrier.
		]]
		--[[
			HOLDING THE PRESS IS A CHASE, NOT A WALK.

			This was 11: the defender only sprinted while further than that from
			the carrier, and jogged the rest of the way in. Requested change --
			holding the press should run the carrier down the way Dash & Pressure
			does in eFootball, so the sprint now covers effectively the whole
			approach and only lifts once the defender is on top of the carrier.

			The jockey speed cap below still applies inside ContainRange, so this
			does not turn containment itself into a sprint -- a defender at top
			speed cannot turn, which is the thing jockeying exists to preserve.
		]]
		SprintDistance = 2.5,

		--[[
			How long a held press waits between challenge requests.

			Covers the server's own recovery after a refused or missed challenge,
			so the hold keeps trying without flooding the remote with requests
			that cannot succeed yet.
		]]
		AutoChallengeIntervalSeconds = 0.45,
		--[[
			ROUTING AROUND, NOT THROUGH (§38).

			Dot of the approach direction against the carrier's heading above
			which the defender is genuinely behind them and must recover to a
			front-side point rather than charging through their back. Mirrors the
			AI's own defending model so both press the same way.
		]]
		BehindRecoveryDot = 0.3,
		-- How far down the carrier's path the recovery line aims, as a multiple
		-- of the current gap, bounded at both ends.
		RecoveryLeadScale = 1.25,
		MinimumRecoveryLead = 8,
		MaximumRecoveryLead = 30,
		-- Recover on the side the defender is already on; cutting across the
		-- carrier is the path that runs straight through them.
		RecoveryLateralOffset = 4.5,
		-- Assistance stops helping once inside this distance so the player is not
		-- driven into the carrier automatically.
		HoldDistance = 4.2,
		--[[
			WAS 9, WHICH BLED SPEED OFF THE WHOLE CHASE.

			The assist scales its magnitude down between SlowDistance and
			HoldDistance so the defender settles onto the press point instead of
			running through it. At 9 that deceleration started while the defender
			was still most of a chase away, and bottomed out at 30% -- so a press
			that was allowed to sprint still crawled the last stretch.

			Pulled in to just outside the hold point: the defender now runs the
			ground down and decelerates late, which is both faster and closer to
			how a real press arrives.
		]]
		SlowDistance = 5.6,
		--[[
			Was 0.85. A press that the game has decided should sprint has no
			reason to be held below full: the jockey cap inside ContainRange is
			what keeps a contained defender balanced, and that still applies.
		]]
		MaximumMoveMagnitude = 1,
		ManualOverrideMagnitude = 0.9,
		FacingResponsiveness = 11,
		Duration = 1.35,
	},

	--[[
		THE SLIDE TACKLE.

		The high-risk challenge, and the one football keeps for the moments where
		staying on your feet is no longer an option -- a last man, a ball about to
		be played across the box, an attacker committing to a shot.

		It is defined entirely by its trade, and every number below exists to
		express one half of that trade:

		  IT REACHES FURTHER.  A slide is a lunge; the reward for going to ground
		     is a metre of extra reach and a real chance at a ball a standing
		     challenge cannot touch.

		  IT COMMITS THE BODY.  Once it starts, the defender is going where they
		     were pointed and nowhere else, and then they are on the floor. There
		     is no steering out of it and no cancelling it -- that commitment IS
		     the cost, and a slide that could be aborted would simply be a better
		     standing tackle.

		  IT FOULS FAR MORE EASILY.  Mistime it and you have taken someone down.
		     The severity multiplier below is what makes a slide through the back
		     of a carrier a free kick where the same standing challenge might be
		     waved on, and it is the reason this is a deliberate double-tap rather
		     than something a player can do by accident.

		The values that are not listed here are inherited from the standing
		Tackle, so the two cannot drift apart on the terms they share.
	]]
	--[[
		THE CONTACT WINDOW (Milestone 6.8).

		A challenge is a committed action that is contestable over a span of time,
		not a test taken at the instant the button is pressed. Two sources agree on
		this from different directions: GameplayFootball registers a tackle only
		while the actor is inside an animation frame window
		(`match.cpp:1835-1838`, frames 5-28), and the eFootball reference footage
		shows roughly a second from committed approach to won ball with about half
		of that in physical contact
		(docs/research/gameplay-football/ai/03-pressing-and-tackling.md, A3/B1).

		Windup is the part that cannot be taken back -- the leg is already going.
		The contact window is how long afterwards the challenge can still connect.
		Together they are what makes a tackle MISTIMEABLE: too early and the
		carrier has not arrived, too late and they are gone, and in both cases the
		defender has spent the commitment either way.

		Deliberately short. Beyond 90 leans arcade, and a long window would read as
		a magnet rather than a challenge.
	]]
	ContactWindow = {
		WindupSeconds = 0.08,
		ContactWindowSeconds = 0.28,
		-- Clients read this to hold the challenge animation and suppress input
		-- for its duration. The server owns the commitment.
		CommittedAttribute = "Beyond90ChallengeUntil",
	},

	Slide = {
		ActionType = "SlideTackle",
		Enabled = true,
		--[[
			Double-tap, and a deliberately generous window.

			The input has to be unmistakable -- nobody should slide by accident --
			but it also has to be usable in the moment it is wanted, which is
			always a moment of panic. A quarter of a second is comfortably
			distinguishable from a hold and comfortably reachable in a hurry.
		]]
		DoubleTapWindow = 0.28,

		-- Reach: a full metre further than a standing challenge at this scale.
		MaximumBallDistance = 9.5,
		MaximumOpponentDistance = 11.5,
		--[[
			A slide is a committed lunge along a line, so it is far LESS forgiving
			about direction than a standing tackle even though it reaches further.
			Sliding at a ball beside you is not a thing that works.
		]]
		MinimumFacingDot = 0.55,
		-- Easier to win when it does connect: the whole body is behind it.
		SuccessThreshold = 0.44,
		PartialThreshold = 0.28,

		--[[
			THE COMMITMENT.

			Launch speed along the tackler's facing, and how long they are on the
			floor afterwards. The recovery is long on purpose -- being beaten by a
			slide has to actually cost something, or sliding becomes the default
			challenge.
		]]
		LaunchSpeed = 34,
		SlideSeconds = 0.55,
		RecoverySeconds = 1.35,
		FailedRecoverySeconds = 1.8,
		Cooldown = 1.9,
		-- Character attribute clients read to suppress input and to animate the
		-- slide. Set by the server, which owns the commitment.
		SlidingAttribute = "Beyond90SlidingUntil",

		--[[
			How much more readily a slide fouls.

			Applied to the severity the ordinary foul evaluation produces rather
			than to a separate rule, so a slide is judged on exactly the same
			geometry as any other challenge -- mistiming, contact and angle -- and
			simply carries more consequence for the same mistake. Which is what
			the laws of the game actually say about it.
		]]
		FoulSeverityScale = 1.45,

		-- A slide cannot collect what it has just poked away: the tackler is on
		-- the ground. Longer than the standing equivalent for that reason.
		TacklerAcquisitionSuppression = 0.9,
		TacklerExitDistance = 4.5,
		-- The ball comes off a slide harder than off a standing poke.
		LooseBallSpeed = 21,
		LooseBallPartialSpeed = 13,
		LooseBallLift = 2.6,
	},

	--[[
		INTERCEPTIONS.

		Evaluated as a swept segment rather than a per-tick distance test -- see
		the long note at the top of InterceptionEvaluator for why a point sample
		cannot catch a ball travelling at pass speed.

		These numbers describe a leg, not a magnet. The base reach is a stride;
		the speed and skill bonuses are small; and a hard enough pass cannot be
		taken cleanly however well it is read.
	]]
	Interception = {
		Enabled = true,
		--[[
			Below this the ball is not a pass, it is a loose ball, and the
			ordinary reception path already owns it. Above BallConfig's
			SlowPickupSpeed so the two never both claim the same ball.
		]]
		MinimumBallSpeed = 12,
		--[[
			Reach: a standing leg, plus what movement and reading add to it.

			This totalled 4.2 + 1.9 + 1.3 = 7.4 studs -- a net nearly eleven studs
			wide dragged along every passing lane, which is why almost no AI pass
			in a 3v3 survived contact with a defender. A leg is a leg; brought
			back to about 5.4 at full stretch.
		]]
		BaseReach = 3.4,
		ReachPerSpeed = 0.07,
		MaximumSpeedReach = 1.2,
		SkillReachBonus = 0.8,
		--[[
			The ball must still be arriving. A closest approach right at the
			start of the sweep means it was already level when the tick began --
			it has gone past, and counting it would let defenders intercept
			backwards.
		]]
		MinimumSegmentFraction = 0.06,
		--[[
			Real interceptions are frequently made half-turned, so this stays
			generous -- but -0.15 allowed a ball crossing BEHIND the defender's
			shoulder to be cut out, which is not an interception, it is the ball
			going past someone. Now it must at least be in front of the shoulder
			line.
		]]
		MinimumFacingDot = 0.15,

		-- Up to this speed a well-read ball can be killed; past HopelessSpeed
		-- nothing can be taken cleanly and the best case is a deflection.
		CleanSpeedLimit = 34,
		HopelessSpeed = 95,

		--[[
			HOW CLOSE YOU ACTUALLY WERE HAS TO DOMINATE.

			It did not. With closeness at 0.5 against facing 0.3 plus skill 0.28,
			a defender who was merely pointed the right way scored about 0.55
			before closeness contributed anything at all -- comfortably over the
			0.3 deflection threshold. The runtime log is the proof:

				[Interception] HOME_AI_2 outcome=Deflected score=0.53 closeness=0.01
				[Interception] HOME_AI_3 outcome=Deflected score=0.35 closeness=0.03
				[Interception] AWAY_AI_3 outcome=Deflected score=0.42 closeness=0.04
				[Interception] HOME_AI_2 outcome=Deflected score=0.57 closeness=0.00

			-- balls passing essentially nowhere near a defender, cut out anyway,
			over and over. That is the whole of "the AI takes the ball off me too
			easily": possession changed hands 19 times in one 3v3 spell and almost
			every change was one of these, not a tackle.

			Closeness now carries the score and the other terms modulate it, which
			is the right shape: reading the pass and being a good defender should
			improve an interception you were in a position to make, not manufacture
			one you were not.
		]]
		ClosenessWeight = 0.95,
		FacingWeight = 0.16,
		SkillWeight = 0.18,
		SpeedPenaltyWeight = 0.62,

		--[[
			Above CleanThreshold the defender takes it down into their own path;
			between the two it comes off them as a genuine loose ball.

			Both raised so that an interception is an EVENT. Below the deflection
			threshold the defender simply misses it and the pass completes -- which
			previously almost never happened, and is what made passing feel
			pointless.
		]]
		CleanThreshold = 0.82,
		DeflectionThreshold = 0.52,
		-- How far a deflection bends from the ball's incoming line toward the
		-- defender. Mostly the incoming line: a ball off a shin keeps most of
		-- its direction, which is what makes a deflection unpredictable.
		DeflectionFacingBlend = 0.4,

		-- A controlled block is a touch, not a clearance: gentle enough to stay
		-- in the defender's control lane so the ordinary Capture path collects it.
		ControlledSpeed = 8.5,
		ControlledLift = 1,
		-- A deflection keeps a fraction of the pace that was on the ball.
		DeflectionSpeedRetention = 0.42,
		DeflectionLift = 2.2,

		-- The interceptor cannot immediately re-take what they just deflected;
		-- a clean block they may collect, exactly as with a won tackle.
		ClaimSeconds = 1.5,
		ClaimScoreBonus = 1,
		ControlledRecoverySeconds = 0.18,
		DeflectionSuppression = 0.3,
		DeflectionExitDistance = 3.2,
		--[[
			One interception per defender per this window. Without it a ball
			that stays in range across several ticks is intercepted repeatedly,
			and the ball ends up being batted along by one player.
		]]
		Cooldown = 0.55,
	},

	AI = {
		Enabled = true,

		--[[
			WHEN AN AI SLIDES (Milestone 6.8).

			Until now AI footballers never slid at all -- `AttemptSlideTackle` was
			reachable only from the client remote.

			GameplayFootball fires its slide inside a narrow band with a LOWER bound
			as well as an upper one (`playercontroller.cpp:388-415`,
			`ballDist in (0.7, 1.6)`), which is the non-obvious half: a ball at your
			feet is not a sliding situation, it is a standing one. Beyond 90 gets
			the same shape from its own numbers rather than a converted constant --
			the band starts just beyond `AI.TackleDistance`, where a standing
			challenge stops being possible, and ends inside `Slide.MaximumBallDistance`
			with margin. So an AI slides exactly when it cannot reach with a step
			but could reach by committing, which is both the reference's intent and
			the football reason for the shot.

			The reference also refuses to slide at all on a team containing a human
			(`GetHumanGamerCount() != 0`). That rule cannot come across: Beyond 90's
			whole identity is mixed human/AI sides (AGENTS.md 47), so it would
			disable the behaviour in nearly every match. The intent -- do not let
			bots slide recklessly around people -- is preserved through the score
			threshold and a long cooldown instead.
		]]
		Slide = {
			Enabled = true,
			-- Just beyond a standing challenge, comfortably inside slide reach.
			MinimumBallDistance = 6.6,
			MaximumBallDistance = 9.2,
			--[[
				The duel-likeliness gate. Higher than the standing-tackle threshold
				on purpose: a slide that does not come off leaves the defender on the
				floor, so it has to be a better bet than a tackle to be worth taking.
			]]
			--[[
				Measured at 0.58 / 7s: 8 slides across 150s of 3v3, with one AI
				going to ground four times in that span -- too often for a last
				resort, even allowing that a 3v3 contests the ball far more per
				player than a full-sided match would.
			]]
			MinimumScore = 0.63,
			-- Rarity. A slide is a last resort, not a challenge type.
			DecisionCooldown = 11,
			--[[
				The shot block. GameplayFootball widens its band for an opponent who
				is shooting with a touch pending, which is the one case where sliding
				at full stretch is correct even from further out.
			]]
			ShotBlockMaximumBallDistance = 10.5,
			ShotBlockMinimumScore = 0.4,
		},
		-- Only the designated presser challenges, so a team does not collapse
		-- onto one carrier.
		TackleDistance = 5.6,
		--[[
			Lowered with MinimumContainSeconds above. The reference has no score
			gate at all -- the angle is the whole decision -- but Beyond 90's
			evaluation also judges reach and facing, which the reference handles
			elsewhere, so a low floor is kept to stop challenges that cannot
			physically connect.
		]]
		MinimumScoreToAttempt = 0.3,
		DecisionCooldown = 1.15,
		CommitmentSeconds = 0.45,
		-- Bounded reaction so AI does not challenge with zero latency.
		-- Trimmed alongside the containment gate; the reference has no reaction
		-- delay on a challenge at all.
		ReactionDelay = 0.12,
		--[[
			THE AI CONTAINS BEFORE IT COMMITS.

			An AI defender that challenges the instant a tackle is legal is the
			same failure the human press had, and it is more visible on the AI
			because there are ten of them. A real defender arrives, holds the
			carrier up, and picks a moment.

			So the presser must have been engaged for at least this long before it
			is allowed to challenge at all. It is a floor on patience, not a
			delay on reaction: the AI still closes immediately, it simply does not
			dive in on arrival.
		]]
		--[[
			THE DUEL ANGLE GATE (ported thresholds).

			GameplayFootball gates its two challenge types on the same geometric
			test at two different heights: `_InterfereCommand` refuses below 0.2,
			`_SlidingCommand` refuses below 0.7
			(`playercontroller.cpp`, commit 1dc1518a). Those thresholds are used
			here unchanged -- they are ratios of a normalised dot product, so
			unlike a distance they carry across to Beyond 90's scale directly.

			0.2 is a LOW bar on purpose: it only rules out challenges that would
			have to go through the opponent's body. 0.7 is a high one, because a
			slide that misses leaves the defender on the floor.

			See TackleEvaluator.BallDuelLikeliness.
		]]
		MinimumDuelLikeliness = 0.2,
		SlideMinimumDuelLikeliness = 0.7,
		--[[
			ALMOST NOTHING, NOW THAT THE ANGLE DECIDES.

			Measured: adding the duel test ON TOP of this gate made defending more
			conservative, not less -- tackles fell from 3 to 1 across matched 100s
			samples, because a challenge then had to clear the angle test AND a
			score threshold AND half a second of containment AND a reaction delay.

			GameplayFootball has none of that stack. `_InterfereCommand` refuses
			only below 0.2 duel likeliness and otherwise challenges; there is no
			dwell, no score gate and no reaction delay anywhere in it. Adopting the
			reference means adopting that structure, not bolting its test onto a
			more cautious one.

			Kept at a token value rather than zero so a defender still cannot
			challenge on the same frame it arrives.
		]]
		MinimumContainSeconds = 0.15,
		--[[
			Above this score the challenge is good enough to take regardless of
			how long the defender has been containing. A ball left genuinely
			exposed is not a moment to be patient about.
		]]
		OpportunistScore = 0.72,
	},
}

--[[
	The slide's tackle-evaluation table.

	Built from the standing Tackle and overridden only where a slide genuinely
	differs, so every term the two share -- exposure, closing speed, the weights,
	the behind-penalty -- is guaranteed to stay identical. Two hand-maintained
	copies of the same rule set is how a standing tackle and a slide end up
	quietly disagreeing about what a legal challenge is.
]]
DefendingConfig.Slide.Evaluation = table.clone(DefendingConfig.Tackle)
DefendingConfig.Slide.Evaluation.MaximumBallDistance = DefendingConfig.Slide.MaximumBallDistance
DefendingConfig.Slide.Evaluation.MaximumOpponentDistance = DefendingConfig.Slide.MaximumOpponentDistance
DefendingConfig.Slide.Evaluation.MinimumFacingDot = DefendingConfig.Slide.MinimumFacingDot
DefendingConfig.Slide.Evaluation.SuccessThreshold = DefendingConfig.Slide.SuccessThreshold
DefendingConfig.Slide.Evaluation.PartialThreshold = DefendingConfig.Slide.PartialThreshold

return DefendingConfig
