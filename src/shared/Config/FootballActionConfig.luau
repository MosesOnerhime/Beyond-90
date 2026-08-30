local FootballActionConfig = {
	RemotesFolderName = "Remotes",
	RequestRemoteName = "FootballActionRequest",
	FeedbackRemoteName = "FootballActionFeedback",
	DevelopmentShootingSkillRemoteName = "DevelopmentShootingSkill",
	DevelopmentPassTargetTag = "Beyond90PassTarget",
	DebugEnabled = true,
	Input = {
		DoubleTapWindow = 0.2,
		SingleTapCommitDelay = 0.18,
	},
	Targeting = {
		RequirePlayerReceiver = true,
		AllowUnteamedDevelopmentReceivers = true,
		AllowPartiallyAssignedStudioReceivers = true,
		PitchLengthRangeScale = 0.9,
		FallbackMaxTargetRange = 309,
		RetentionConeDegrees = 96,
		SwitchScoreMargin = 0.35,
		PreviewRefreshInterval = 0.1,
		ServerReleaseDelay = 0.12,
		LineHeight = 0.035,
		LineThickness = 1.15,
		LineDepth = 0.035,
		LineTransparency = 0.38,
		LineColor = Color3.fromRGB(218, 222, 226),
	},

	DevelopmentIntensity = {
		Min = 0.7,
		Max = 1.4,
	},

	--[[
		SHOT INTENSITY -- development only (§18).

		A physical POWER override for testing, deliberately separate from
		Shooting Skill:

			Shooting Skill  = accuracy / execution quality
			Shot Intensity  = raw power, so a given strength can be reproduced

		Expressed 0-100 and applied as a multiplier on the finished launch
		velocity, so 100 is exactly normal play and the control is inert until a
		tester moves it.
	]]
	DevelopmentShotIntensity = {
		Default = 100,
		Minimum = 0,
		Maximum = 100,
		Step = 10,
		-- 100 maps to 1.0x, so leaving it alone changes nothing.
		Reference = 100,
		AttributeName = "Beyond90ShotIntensity",
		RemoteName = "DevelopmentShotIntensity",
	},

	Pass = {
		ActionType = "GroundPass",
		Cooldown = 0.32,
		MinDistance = 4,
		MaxDistance = 88,
		DirectPassDistance = 28,
		IntentConeDegrees = 72,
		DirectionWeight = 3.8,
		DistanceWeight = 0.55,
		ForwardWeight = 0.45,
		HoldMaxTime = 0.85,
		MinIntensity = 0.95,
		MaxIntensity = 1.35,
		BaseLeadTime = 0.2,
		LeadTimePerStud = 0.018,
		MinLeadTime = 0.12,
		MaxLeadTime = 0.55,
		StationaryReceiveLead = 2.15,
		MovingReceiveLead = 2.75,
		MinLaunchSpeed = 24,
		MaxLaunchSpeed = 120,
		ArrivalSpeed = 32,
		LongArrivalSpeed = 72,
		EstimatedRollingDeceleration = 8,
		TravelTimeMin = 0.34,
		TravelTimeMax = 1.42,
		GroundLiftSpeed = 0.8,
		LongLiftSpeed = 26,
		LiftStartDistance = 32,
		LiftFullDistance = 150,
		ReceiverRadius = 3.5,
		ReleaseReacquireSuppression = 0.1,
		ReacquireExitDistance = 4.4,
		PowerMode = "DistanceDerived",
	},

	ThroughPass = {
		ActionType = "ThroughPass",
		Cooldown = 0.38,
		MinDistance = 7,
		MaxDistance = 105,
		DirectPassDistance = 42,
		IntentConeDegrees = 64,
		DirectionWeight = 4.3,
		DistanceWeight = 0.4,
		ForwardWeight = 0.7,
		HoldMaxTime = 0.95,
		MinIntensity = 1,
		MaxIntensity = 1.35,
		BaseLeadTime = 0.28,
		LeadTimePerStud = 0.022,
		MinLeadTime = 0.22,
		MaxLeadTime = 0.78,
		StationaryReceiveLead = 2.4,
		MovingReceiveLead = 3.4,
		LeadDistanceMin = 5,
		LeadDistanceMax = 18,
		LeadDistanceScale = 0.18,
		MinLaunchSpeed = 31,
		MaxLaunchSpeed = 132,
		ArrivalSpeed = 38,
		LongArrivalSpeed = 78,
		EstimatedRollingDeceleration = 7,
		TravelTimeMin = 0.42,
		TravelTimeMax = 1.7,
		GroundLiftSpeed = 1,
		LongLiftSpeed = 30,
		LiftStartDistance = 28,
		LiftFullDistance = 145,
		ReceiverRadius = 5,
		ReleaseReacquireSuppression = 0.12,
		ReacquireExitDistance = 4.8,
		PowerMode = "DistanceDerived",
	},

	LobPass = {
		ActionType = "LobPass",
		Cooldown = 0.42,
		MinDistance = 7,
		MaxDistance = 105,
		DirectPassDistance = 36,
		IntentConeDegrees = 72,
		DirectionWeight = 4.0,
		DistanceWeight = 0.45,
		ForwardWeight = 0.55,
		HoldMaxTime = 0.5,
		MinIntensity = 1,
		MaxIntensity = 1,
		BaseLeadTime = 0.3,
		LeadTimePerStud = 0.02,
		MinLeadTime = 0.24,
		MaxLeadTime = 0.82,
		StationaryReceiveLead = 2.3,
		MovingReceiveLead = 3.2,
		MinLaunchSpeed = 34,
		MaxLaunchSpeed = 112,
		ArrivalSpeed = 24,
		LongArrivalSpeed = 45,
		EstimatedRollingDeceleration = 3,
		TravelTimeMin = 0.72,
		TravelTimeMax = 2.1,
		GroundLiftSpeed = 24,
		LongLiftSpeed = 46,
		LiftStartDistance = 7,
		LiftFullDistance = 190,
		ReceiverRadius = 6.2,
		ReleaseReacquireSuppression = 0.16,
		ReacquireExitDistance = 5.2,
		PowerMode = "DistanceDerived",
	},

	KnockOn = {
		ActionType = "KnockOn",
		Cooldown = 0.7,
		ControlDistance = 5,
		ControlledTouchAllowance = 9.5,
		HoldMaxTime = 0.55,
		MinIntensity = 0.9,
		MaxIntensity = 1.25,
		PeakSeparation = 36,
		CatchUpTime = 3.6,
		MinRelativeForwardSpeed = 11,
		MaxRelativeForwardSpeed = 23,
		VerticalVelocity = 6.5,
		MovingAimSpeedThreshold = 8,
		PlayerForwardCarry = 1,
		PlayerLateralCarry = 0.35,
		--[[
			Knock-On is a soft release, not a loss of possession.

			The suppression window is now only long enough that the ball actually
			leaves the foot -- a 1.6s lockout plus an 11-stud exit made the player
			fight a neutral contest for a ball they had just deliberately played.
			Priority during the chase comes from Reacquisition below instead, which
			an opponent can still beat.
		]]
		ReleaseReacquireSuppression = 0.35,
		ReacquireExitDistance = 5,
		Reacquisition = {
			-- Roughly the recovery time of a sprint knock-on.
			ClaimSeconds = 3.2,
			-- Added to the candidate score while chasing. Comparable to the
			-- existing-controller bonus: meaningful, not decisive.
			ScoreBonus = 0.9,
		},
		ReleasedHorizontalDeceleration = 11.5,
		MaximumReleasedDuration = 8,
		JogPredictionTime = 0.58,
		SprintPredictionTime = 0.74,
		JogAdditionalLead = 14,
		SprintAdditionalLead = 30,
		MaximumPredictedPlayerTravel = 32,
		LaunchSpeedPadding = 1.5,

		--[[
			Velocity-aware separation.

			A flat relative push cannot separate from a sprinting footballer: the
			player is already travelling at 28, so a fixed +23 barely pulls ahead
			before the ball's own deceleration brings it back. The push therefore
			scales with the player's current speed, which is what makes a sprint
			knock-on visibly longer than a jog one while staying predictable.
		]]
		VelocityScaling = {
			Enabled = true,
			-- Reference speeds for the interpolation.
			LowSpeed = 6,
			SprintSpeed = 28,
			-- Relative forward push at each end of that range. Solved against the
			-- 11.5 studs/s^2 released deceleration so a sprint knock-on peaks at
			-- roughly PeakSeparation and takes ~4s to fully recover, per the
			-- 3-5s design target. Adding a further fraction of player speed on
			-- top double-counted and produced 80+ stud separations.
			-- Raised after playtesting: the modelled separation sat inside the
			-- design target but did not read as a knock-on in actual play. The
			-- ball has to be genuinely chased, not merely stepped after.
			LowRelativePush = 14,
			SprintRelativePush = 32,
			PlayerSpeedCarry = 0,
		},
	},

	--[[
		Throw-in (§32-§34).

		Separate from every pass type because a throw genuinely is a different
		action: it starts above the head, it is slower and higher than a driven
		pass, and its distance is chosen by how long Pass is held rather than by
		the distance to a target.
	]]
	ThrowIn = {
		ActionType = "ThrowIn",
		Cooldown = 0.4,

		-- Hold-to-distance. A tap finds the nearest option, a full hold goes long.
		HoldMaxTime = 0.9,
		HoldCurveExponent = 1.15,
		MinDistance = 14,
		MaxDistance = 62,
		-- A throw physically cannot reach beyond this, whatever the hold.
		MaximumReach = 78,

		-- Receiver selection weights. The player's own selection outranks both.
		DistanceWeight = 1.6,
		AimWeight = 0.55,
		SelectedReceiverBonus = 10,

		--[[
			Flight shape. Slower and higher than a driven pass: a throw-in that
			arrives at pass speed does not read as a throw.
		]]
		ReferenceHorizontalSpeed = 38,
		MinFlightTime = 0.42,
		MaxFlightTime = 1.5,
		LeadFactor = 0.85,
		-- Aim at the receiver's chest, not their feet.
		ReceiveHeight = 2.4,

		-- Where the ball leaves the hands, above the thrower's root.
		ReleaseHeight = 4.6,
		-- Nobody to throw to: a short throw infield rather than straight back out.
		SafeFallbackDistance = 16,

		ReleaseReacquireSuppression = 0.35,
		ReacquireExitDistance = 6,
	},

	Shoot = {
		ActionType = "Shoot",
		Cooldown = 0.48,

		-- Hold-to-charge. Power and accuracy stay separate concepts: charging
		-- raises launch speed, it does not improve placement.
		Charge = {
			Enabled = true,
			MinimumHoldSeconds = 0.06,
			MaximumHoldSeconds = 0.85,
			-- A tap must still be a shot, not a pass at the goal (§65).
			MinimumPower = 0.58,
			MaximumPower = 1,
			-- Slightly eased so a short tap is still a usable shot and the top of
			-- the range takes deliberate commitment.
			CurveExponent = 1.25,
		},

		-- Double-tap Shoot cancels the pending shot instead of releasing it.
		FakeShot = {
			Enabled = true,
			DoubleTapWindow = 0.26,
			-- Presentation exit; no dedicated fake-shot clip exists yet.
			RecoverSeconds = 0.3,
		},

		-- Client-side buffering. A shot pressed while the football is out on a
		-- sprint touch waits for the next reachable contact instead of being
		-- rejected as controlled-ball-out-of-range.
		--[[
			SPRINT-SHOT BUFFER (§41, §42).

			ROOT CAUSE OF THE SPRINT WHIFF. At sprint the football sits up to
			~8.8 studs ahead at the peak of a touch and returns to the foot after
			0.88-1.07s (measured). The strike window is 4.4 studs. So for roughly
			half of every sprint touch the ball is legitimately out of range --
			which is correct -- but the buffer gave up after 0.6s, BEFORE the ball
			could possibly have come back, and then sent the request anyway. The
			server saw an out-of-range ball and rejected it, and the player saw a
			leg swing through empty grass.

			Two changes fix it. The wait now outlasts a full sprint touch cycle,
			and the controlled ball is actively drawn back into the strike window
			while the intent is held (StrikePreparation below) rather than the
			shot merely waiting and hoping.
		]]
		Buffer = {
			Enabled = true,
			-- Longer than the measured 1.07s worst-case sprint recontact.
			MaximumWaitSeconds = 1.3,
			PollInterval = 1 / 30,
			-- The intent survives while the ball is still recoverable.
			AbandonDistance = 12,
			--[[
				While a shot is queued, ask the controlled ball to come back to a
				strikeable lead instead of completing its normal touch.

				This is bounded assistance executing an intent the player has
				already declared (§33) -- it does not teleport the ball, raise the
				possession radius, or let a shot fire from an impossible distance.
				It shortens the NEXT touch, which is what a footballer does when
				they have decided to shoot.
			]]
			StrikePreparation = {
				Enabled = true,
				-- Target lead while preparing, as a fraction of the strike window.
				LeadScale = 0.6,
				-- How hard the ball is drawn back to it.
				PositionGain = 9,
			},
		},
		ControlDistance = 5.2,
		ControlledTouchAllowance = 7.25,
		--[[
			POWER (§65). Raised: shots read as underpowered in playtest -- a close
			shot at the bottom of the charge curve was leaving the foot at barely
			35 studs/s, which a keeper could walk to.

			Combined with the raised MinimumPower below, a tap is now a proper
			shot and a full charge is a genuine strike, without every tap becoming
			a rocket.
		]]
		MinLaunchSpeed = 108,
		MaxLaunchSpeed = 168,
		ReferenceDistance = 120,
		FlightTimeScale = 1.15,
		MinTravelTime = 0.34,
		MaxTravelTime = 0.92,
		TargetHeightAlpha = 0.34,
		AimLateralInfluence = 0.78,
		GoalSafetyMargin = 0.42,
		MaximumAttackingDistance = 175,
		MinimumShotProgressStuds = 0,
		Skill = {
			Default = 0.9,
			Minimum = 0,
			Maximum = 1,
			DevelopmentStep = 0.05,
			MaximumLateralErrorStuds = 13,
			MaximumVerticalErrorStuds = 7,
			ErrorExponent = 1.2,
			LowSkillSafetyMargin = 0.12,
			HighSkillSafetyMargin = 0.85,
		},
		Alignment = {
			FullAccuracyDot = 0.92,
			MaximumErrorDot = -0.65,
			MaximumLateralErrorStuds = 6,
			MaximumVerticalErrorStuds = 2.75,
			ErrorExponent = 1.5,
		},
		--[[
			TARGET ZONES (§68).

			Nine reachable places in the goal rather than "somewhere near the
			middle": three lateral bands each side plus the centre, crossed with a
			height ramp that now reaches the top corners.

			Zone selection is DETERMINISTIC (see ShotPlanner) -- it comes from the
			player's aim, the range and the goalkeeper's position, never from
			math.random. That is what allows Shooting Skill 100 to add no
			deviation at all (§67): if the target itself were a dice roll, no
			amount of skill could remove the scatter.
		]]
		Placement = {
			LateralZones = { -0.82, -0.5, -0.22, 0, 0.22, 0.5, 0.82 },
			--[[
				Fractions of the usable goal height. Previously topped out at 0.6,
				which is why every shot looked like a flat ground drive (§66).
			]]
			HeightZones = { 0.1, 0.26, 0.44, 0.62, 0.82 },
			-- How much a clear aim pulls the target off the nearest zone, so a
			-- player can place between zones.
			IntentZoneInfluence = 0.72,
			-- Below this the player is not aiming anywhere in particular, and the
			-- assist may pick the side away from the keeper.
			ClearIntentThreshold = 0.15,
			-- A hard-driven shot is kept lower, a placed one lifted.
			DrivenHeightReduction = 1.1,
			-- A keeper this far off its line is fully "advanced".
			KeeperAdvanceReference = 14,
			KeeperAdvanceHeightBonus = 1.2,
		},

		--[[
			FINESSE (§69).

			A real bend, not a visual one: a constant lateral acceleration fixed at
			release and integrated by BallService alongside gravity. Because it is
			constant and decided up-front, the local trajectory preview reproduces
			it exactly and it can never home toward the goal.

			Scaled by how far across the goal the shot is placed and by how little
			power was used -- a driven shot has no time to bend -- and by Shooting
			Skill, because bending a ball is a technique rather than luck.
		]]
		Finesse = {
			Enabled = true,
			-- Studs/s^2. Bounded well under BallConfig.Flight's own ceiling.
			MaximumAcceleration = 46,
			-- Below this the bend would not be visible; not worth the attribute.
			MinimumAcceleration = 5,
			-- Lateral placement at which the full bend is applied.
			FullBendAlpha = 0.6,
			-- How much a full-power shot suppresses the bend.
			PowerSuppression = 0.75,
		},
		Clearance = {
			HorizontalSpeed = 78,
			VerticalSpeed = 67,
			TargetDistance = 145,
			FlightTime = 1.85,
			AimLateralInfluence = 0.42,
			RandomLateralSpread = 0.48,
		},
		ContactFallbackTime = 0.38,
		PreparedActionLifetime = 0.8,
		ReleaseReacquireSuppression = 0.18,
		ReacquireExitDistance = 5.2,

		-- Shot contact preparation. A shot requested while the football is out on
		-- a sprint touch must wait for a reachable contact instead of launching
		-- from wherever the ball happens to be, which is what made the footballer
		-- visibly swing through empty space.
		Contact = {
			Enabled = true,
			--[[
				THE STRIKE WINDOW MUST TRACK THE DRIBBLE, OR SHOTS WHIFF.

				This was the single largest gameplay defect in the build: shooting
				while running produced a swing at nothing.

				The cause was two systems disagreeing about one number. The strike
				window was authored against JOGGING touches -- BallConfig's
				JogPeakForwardLeadTarget is 4.5, and the forward window here was
				4.4, which matches almost exactly. Sprint carry was later widened
				so the ball is pushed 7.0 studs ahead at pace and may reach 8.6.
				Nothing here changed. So at sprint the ball spent most of every
				touch cycle 7 studs out, outside both a 4.6-stud contact radius
				and a 4.4-stud forward window; the strike could only land in the
				brief part of the cycle where the ball came back, and otherwise
				waited until it expired. The result on screen is a player running
				through the ball without kicking it.

				Two changes fix it properly rather than by inflating a radius:

				1. THE WINDOW IS DERIVED FROM SPEED, spanning the same range the
				   dribble uses. At rest the window is tight, because a stationary
				   player genuinely does have the ball at their feet and a
				   generous radius would let them strike a ball they are not
				   near. At sprint it opens to cover the sprint carry, because
				   the ball being out in front IS what sprint dribbling is.

				2. THE STRIKE IS JUDGED WHERE THE BALL WILL BE, not where it is.
				   A footballer running onto a ball swings at the point their
				   foot will meet it. When player and ball are travelling forward
				   at similar speed the gap between them is stable, and it is
				   only the instantaneous snapshot that makes it look unreachable.
				   Evaluating relative motion a fraction of a second ahead is what
				   makes a running strike land.

				Both are bounded and neither lets a player strike a ball that is
				genuinely someone else's: possession is still required, and the
				lateral and rear windows are unchanged.
			]]
			-- The speed at which the sprint end of the window applies. Matches
			-- PlayerConfig.Movement.SprintSpeed; below it the window interpolates.
			SprintReferenceSpeed = 31,
			-- Reachable radius, at rest and at full sprint. The sprint value
			-- covers BallConfig SprintMaxForwardLead (8.6) with a small margin,
			-- because a ball at the far end of a legal sprint touch is still the
			-- player's ball and must still be strikeable.
			ContactRadiusAtRest = 4.6,
			ContactRadiusSprint = 9.4,
			-- Forward window relative to the player's control direction. The
			-- sprint value sits just above BallConfig SprintMaxForwardLead.
			MaximumForwardLeadAtRest = 4.4,
			MaximumForwardLeadSprint = 9,
			--[[
				How far ahead the strike is judged.

				One touch-cycle poll is 1/30s and a strike animation has not been
				authored yet, so this is the honest latency between deciding to
				shoot and the foot arriving. Small on purpose: it is enough to
				close the gap on a ball the player is running onto, and far too
				short to let them strike a ball that is genuinely running away.
			]]
			StrikeLookaheadSeconds = 0.09,
			MaximumBehindLead = 1.6,
			MaximumLateralOffset = 2.9,
			MaximumHeight = 1.9,
			--[[
				Bounded wait. A queued shot can never outlive this.

				Matched to the client buffer: both must outlast a sprint touch
				cycle or the server rejects a shot the client is still correctly
				waiting to release.
			]]
			MaximumWaitSeconds = 1.1,
			PollInterval = 1 / 30,
			-- Bounded orientation assistance toward the contact point while waiting.
			FacingAssistDegreesPerSecond = 320,
			--[[
				Give up only once the ball is genuinely unrecoverable.

				This has to sit above BallConfig's HardControlDistance: while the
				player still HAS the ball, a pending shot must wait rather than be
				thrown away. At 13 against a retention distance of 12.5 the margin
				was half a stud, and the logs are full of `shot-contact-lost` on
				balls the player had not actually lost.
			]]
			AbandonDistance = 15,
		},
	},

	ShotTrajectory = {
		Enabled = true,
		SegmentCount = 28,
		SegmentDiameter = 0.23,
		PreparedTransparency = 0.18,
		FadeDelay = 0.18,
		FadeDuration = 0.75,
		MaximumLifetime = 3.2,
		Colors = {
			Color3.fromRGB(76, 220, 255),
			Color3.fromRGB(84, 122, 255),
			Color3.fromRGB(220, 230, 255),
		},
		DiagnosticSampleInterval = 0.08,
	},

	Debug = {
		ShowPassTargetMarker = true,
		PassTargetMarkerMeaning = "TargetPoint",
		MarkerDuration = 1.4,
		TargetMarkerSize = 1.1,
		ReceiverMarkerHeight = 4.2,
	},
}

--[[
	THE STRIKE WINDOW, IN ONE PLACE.

	The window opens with the footballer's speed -- see the long note on
	Shoot.Contact for why -- and BOTH the client's local check and the server's
	authoritative one have to use the identical numbers. When they were computed
	separately they drifted the moment the keys changed, and the client half
	crashed outright reading a field that no longer existed:

		FootballActionController:190: attempt to compare nil < number

	which took shooting with it entirely, standing still included. One function
	both sides call makes that class of mistake impossible rather than merely
	unlikely.

	Returns the reachable radius, the forward window and the lateral window for a
	footballer moving at `speed`.
]]
function FootballActionConfig.GetShotContactWindow(speed: number): (number, number, number)
	local contact = FootballActionConfig.Shoot.Contact
	local alpha = math.clamp(
		(speed or 0) / math.max(contact.SprintReferenceSpeed, 1),
		0,
		1
	)
	local radius = contact.ContactRadiusAtRest
		+ (contact.ContactRadiusSprint - contact.ContactRadiusAtRest) * alpha
	local forward = contact.MaximumForwardLeadAtRest
		+ (contact.MaximumForwardLeadSprint - contact.MaximumForwardLeadAtRest) * alpha
	--[[
		The lateral window widens far less than the forward one. A sprint touch
		is pushed AHEAD, not sideways, so a ball well off to one side is still
		not a ball this player can strike.
	]]
	local lateral = contact.MaximumLateralOffset * (1 + 0.35 * alpha)
	return radius, forward, lateral
end

return FootballActionConfig
