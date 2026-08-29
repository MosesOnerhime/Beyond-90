local WorldScaleConfig = require(script.Parent.WorldScaleConfig)

local ballDiameter = 1.35
local physicsRadius = ballDiameter / 2
local visualDiameter = ballDiameter

local BallConfig = {
	Name = "DevelopmentFootball",
	BallDiameter = ballDiameter,
	PhysicsDiameter = ballDiameter,
	Radius = physicsRadius,
	SpawnHeight = physicsRadius + 1.25,
	MaxSpeed = 175,
	CanonicalDiameterMeters = 0.234,
	CanonicalDiameterStuds = 0.234 * WorldScaleConfig.StudsPerMeter,

	PhysicalProperties = {
		Density = 0.7,
		-- Free-ball ground response is modeled explicitly below. Keep Roblox's
		-- contact material quiet so it does not add a second, competing bounce.
		Friction = 0,
		Elasticity = 0,
		FrictionWeight = 100,
		ElasticityWeight = 100,
	},

	Bounce = {
		Enabled = true,
		-- Grass retains believable energy without allowing a hard clearance to
		-- begin another high aerial phase after its first bounce.
		Restitution = 0.48,
		AirborneGravity = WorldScaleConfig.MetersToStuds(9.81),
		LinearBounceLoss = WorldScaleConfig.MetersToStuds(0.4),
		MinimumImpactSpeed = WorldScaleConfig.MetersToStuds(0.65),
		SettleReboundSpeed = WorldScaleConfig.MetersToStuds(0.7),
		MaximumReboundSpeed = WorldScaleConfig.MetersToStuds(4.8),
		ContactTolerance = 0.18,
		SurfaceNormalMinUpDot = 0.65,
		Cooldown = 0.045,
		ImpactFrictionStartSpeed = WorldScaleConfig.MetersToStuds(0.5),
		ImpactFrictionFullSpeed = WorldScaleConfig.MetersToStuds(12),
		ImpactSpinCoupling = 0.5,
		ImpactAngularCoupling = 0.72,
		ImpactTangentLoss = 0.08,
		NormalSpinRetention = 0.82,
		MaximumSpinSurfaceSpeedRatio = 1.35,
		DiagnosticEnabled = true,
	},

	Ground = {
		Enabled = true,
		GrassDepth = WorldScaleConfig.MetersToStuds(0.025),
		QuadraticFriction = 0.04,
		LinearFriction = 1.6,
		RollingVelocityCoupling = 1.15,
		RollingSpinResponse = 7.5,
		NormalSpinDamping = 1.8,
		StopSpeed = WorldScaleConfig.MetersToStuds(0.18),
		MaximumUpwardContactSpeed = WorldScaleConfig.MetersToStuds(0.05),
		GroundedReleaseDistance = WorldScaleConfig.MetersToStuds(0.2),
		GroundedReleaseUpwardSpeed = WorldScaleConfig.MetersToStuds(0.3),
	},

	Flight = {
		Enabled = true,
		-- Roblox's default gravity is too strong relative to the 3.33 studs-per-metre pitch scale.
		EffectiveGravity = 72,
		ActivationHeight = 0.12,
		MaximumActionDuration = 5,
		Actions = {
			Shoot = true,
			Clearance = true,
			ThroughPass = true,
			LobPass = true,
		},

		--[[
			CURVE (§69).

			A constant horizontal acceleration, decided at release and stored on
			the ball. It is integrated alongside gravity while the ball is in
			flight, so a bent shot is genuinely bent -- not a straight shot with a
			bent line drawn under it.

			It is NOT homing: the vector is fixed when the ball leaves the foot
			and never consults the goal afterwards, so it is fully predictable and
			the local preview reproduces it exactly.
		]]
		CurveAttributeName = "FootballCurveAcceleration",
		-- Hard ceiling, so curve can never become a guided missile.
		MaximumCurveAcceleration = 62,
		-- Curve is a property of a struck ball in the air. Once it has bounced,
		-- the spin has largely gone.
		CurveSurvivesBounce = false,
	},

	BasicTouch = {
		Enabled = false,
		CheckInterval = 0.08,
		InteractionRadius = 3.2,
		MaxVerticalDifference = 1.8,
		MinPlayerSpeed = 2,
		MinTowardBallDot = 0.2,
		Cooldown = 0.18,
		WalkTargetSpeed = 13.5,
		SprintTargetSpeed = 19,
		MaxImpulseDeltaSpeed = 8,
		UpwardLiftSpeed = 0.25,
	},

	Control = {
		AcquireDistance = 5.35,
		HardControlDistance = 10.75,
		ControlOriginRadius = 1.1,
		MinimumControlSeparation = 0.14,
		MaximumControllableBallSpeed = 36,
		ControlHeightTolerance = 1.25,
		ControlRetentionMaxSpeed = 68,
		ControlRetentionSpeedViolationGrace = 0.22,
		-- Grace before a controller whose retention rule still reports valid, but
		-- for whom no control context could be built, is actually released.
		ControlContextLostGrace = 0.25,
		ControlAcquisitionSpeedGrace = 0.75,
		ControlRetentionHeightTolerance = 1.8,

		--[[
			HEIGHT GRACE ON ACQUISITION.

			A lofted pass ARRIVES FROM ABOVE. The reception is legitimate -- the
			receiver has taken it on the chest or the thigh and is bringing it
			down -- but for the first fraction of a second afterwards the football
			is still higher than a ball being dribbled ever is, so the retention
			check saw it above ControlRetentionHeightTolerance and released
			possession with "ball too high" the instant it had been granted.

			The speed check already had exactly this problem and already solves it
			the same way (ControlAcquisitionSpeedGrace): a ball that has just been
			received is allowed to still be settling. This is that rule applied to
			the axis a lob actually arrives on.

			Deliberately a GRACE and not a raised tolerance: once the touch has had
			time to bring the ball down, the ordinary limit applies again, so a
			player still cannot carry a football at head height.
		]]
		ControlAcquisitionHeightGrace = 0.8,
		ControlAcquisitionHeightTolerance = 5.5,
		AcquireMinPlayerSpeed = 2,
		AcquireMinTowardBallDot = 0.12,

		ContactAssistPredictionTime = 0.33,
		ContactAssistStartDistance = 1.25,
		ContactAssistFullDistance = 3.75,
		ContactAssistMaxBias = 0.72,
		ContactAssistReverseDot = -0.35,
		ContactAssistReverseBias = 0.12,

		ContactStartPredictionTime = 0.06,
		MinimumFutureContactDelay = 0.16,
		MaximumFutureContactDelay = 0.38,
		SprintReferenceSpeed = 30,
		FrontFootBaseDistance = 1.35,
		FrontFootVelocityLeadTime = 0.05,
		MinimumFrontFootOffset = 1.55,
		MaximumFrontFootOffset = 2.75,
		MaximumWalkPlannedDistance = 6.2,
		MaximumSprintPlannedDistance = 8.5,
		ContactTravelTimePadding = 0.08,
		WalkOverdrive = 1.25,
		SprintOverdrive = 7.5,
		OverdriveSpeedExponent = 1.35,
		MaxControlledBallSpeed = 46,

		LogicalTouchInterval = 0.22,
		ContactRegionRadius = 3.7,
		ContactAheadDistance = 5.8,
		ContactBehindTolerance = 0.9,
		ContactLateralTolerance = 2.4,
		ContactMinimumForwardIntentDot = -0.15,
		MaxContactVerticalDeltaSpeed = 5,

		StationaryLeadDistance = 2.15,
		StationaryFollowGain = 5,
		StationaryMaxDeltaSpeedPerSecond = 20,
		MovingLateralStabilizationGain = 2.5,
		MovingLateralMaxDeltaSpeedPerSecond = 8,
		StabilizationDeadzone = 0.18,

		StationaryPlayerSpeed = 1,
		DirectionSmoothing = 0.35,
		SharpTurnDirectionDot = -0.65,
		CarryLeadDistance = 2.35,
		SprintCarryLeadDistance = 3.55,
		StationaryCarryLeadDistance = 2.15,
		CarryPositionGain = 11,
		CarryVelocityDamping = 1.35,
		CapturePositionGain = 26,
		CaptureVelocityDamping = 3.1,
		CaptureTurnAngleDegrees = 85,
		CaptureBehindLead = -1.25,
		CaptureLeadScale = 0.72,
		CaptureMinDuration = 0.06,
		CaptureMaxDuration = 0.22,
		CaptureReentryCooldown = 0.1,
		CaptureExitError = 0.45,
		CaptureExitRelativeSpeed = 2.2,
		StationaryCaptureDistance = 3.2,
		StationaryCaptureRelativeSpeed = 6.8,
		StationarySettleDistance = 2.9,
		StationarySettleRelativeSpeed = 0.55,
		IdleVelocityDamping = 14,
		ControlledRestEnterDelay = 0.32,
		ControlledRestExitInputMagnitude = 0.08,
		ControlledRestMaxPlayerSpeed = 0.45,
		ControlledRestMaxDistance = 3.05,
		ControlledRestLeadTolerance = 0.75,
		ControlledRestTargetRelativeSpeed = 0.2,
		ControlledRestVelocityDamping = 34,
		ControlledRestPositionGain = 3,
		ControlledRestAngularDamping = 14,
		ControlledRestMaxDeltaSpeedPerSecond = 130,
		HandoffStabilizationDuration = 0.72,
		HandoffNoTouchDuration = 0.9,
		HandoffMinForwardLead = 1.65,
		HandoffTargetLead = 2.55,
		HandoffPositionGain = 7,
		HandoffVelocityDamping = 2.4,
		HandoffMaxDeltaSpeedPerSecond = 90,
		-- Reconcile the first player-owned frame when local character prediction
		-- has advanced well beyond the authoritative server ball handoff.
		HandoffImmediateRescueEnabled = true,
		HandoffImmediateRescueMinLead = 1.15,
		HandoffImmediateRescueServerLead = 1.75,
		HandoffImmediateRescueLeadError = 1.25,
		HandoffImmediateRescueForwardSpeed = 1.4,
		BodyExclusionRadius = 1.2,
		BodyClearance = 0.28,
		BodyExclusionGain = 32,
		DeepOverlapRescueDistance = 0.5,
		TargetBodyExclusionMargin = 0.22,
		CaptureDirectionTurnRate = 38,
		BallIntentTurnRate = 54,
		BallIntentSharpTurnRate = 78,
		BallIntentFacingInfluence = 0.12,
		MaxControlledCorrectionSpeed = 70,
		MaxControlledDeltaSpeedPerSecond = 260,
		CaptureDeltaSpeedMultiplier = 1.5,
		LowMovementSpeedThreshold = 7.5,
		LowTouchInterval = 0.68,
		JogTouchInterval = 0.56,
		SprintTouchInterval = 0.62,
		ForcedNextTouchInterval = 0.88,
		NextTouchLeadTolerance = 0.85,
		RecontactPeakLeadFraction = 0.78,
		LowPeakForwardLeadTarget = 3.0,
		JogPeakForwardLeadTarget = 4.5,
		SprintPeakForwardLeadTarget = 7.0,
		LowMaxForwardLead = 4.1,
		JogMaxForwardLead = 5.8,
		SprintMaxForwardLead = 8.6,
		TouchPulseDuration = 0.16,
		TouchCoastDuration = 0.48,
		TouchMaxSeparationWait = 0.58,
		TouchPeakLeadFraction = 0.86,
		TouchCoastSpeedPulseScale = 0.04,
		TouchAirborneWindow = 0.16,
		LowTouchLeadPulse = 0.75,
		JogTouchLeadPulse = 2.35,
		SprintTouchLeadPulse = 4.1,
		LowTouchSpeedPulse = 2.5,
		JogTouchSpeedPulse = 7.2,
		SprintTouchSpeedPulse = 21,
		LowTouchImpulseDeltaSpeed = 0,
		JogTouchImpulseDeltaSpeed = 0,
		SprintTouchImpulseDeltaSpeed = 7,
		LowTouchHopHeight = 0.04,
		JogTouchHopHeight = 0.1,
		SprintTouchHopHeight = 0.2,
		MaxTouchUpwardVelocity = 12,
		PushPlayerVelocityScale = 1,
		CoastPlayerVelocityScale = 0,
		CollectPlayerVelocityScale = 0.8,
		SettlePlayerVelocityScale = 0,
		ReleasedSettlePlayerVelocityScale = 0.78,
		CollectBackwardCorrectionScale = 0.28,
		PushPositionGainScale = 0.06,
		PushVelocityDampingScale = 0.08,
		CoastPositionGainScale = 0.045,
		CoastVelocityDampingScale = 0.04,
		CollectPositionGainScale = 0.65,
		CollectVelocityDampingScale = 0.8,
		SettlePositionGainScale = 1.65,
		SettleVelocityDampingScale = 2.5,
		TouchLateralOffset = 0.18,
		TouchAngularVelocityGain = 3.4,
		MaxTouchAngularVelocity = 42,
		PeakLeadOvershootBrakeGain = 4.5,
		PeakLeadOvershootMaxBrakeSpeed = 8,
		RecontactCrossingPreviousLead = 1.25,
		RecontactCrossingBehindLead = -0.25,
		RecontactCrossingForwardGain = 12,
		RecontactCrossingMaxCancelSpeed = 12,
		CancelPushTurnAngleDegrees = 115,
		CutbackTurnAngleDegrees = 135,
		CutbackDuration = 0.18,
		CutbackLateralOffset = 0.95,
		SeparationCorrectionStrength = 2,
		MaxSeparationImpulseDeltaSpeed = 1.2,
		ExistingControllerScoreBonus = 1.5,
		ControlStealScoreMargin = 1.25,
		LeadDiagnosticInterval = 0.75,
		TouchDiagnosticEnabled = true,
	},

	--[[
		Dribbling skill and fast direction changes.

		Skill affects CONTROL QUALITY, never top speed. At 100 a correctly
		executed touch carries no skill-based error at all; lower skill widens
		the control lane and slows the ball onto a new heading, but the ball is
		still recoverable -- no random failures.
	]]
	Dribbling = {
		Enabled = true,
		AttributeName = "Beyond90DribblingSkill",
		DefaultSkill = 70,

		-- Sharp-turn response. The ball rotates onto the new control lane
		-- earlier instead of finishing an obsolete forward touch first.
		FastTurn = {
			Enabled = true,
			-- Below this the normal cadence handles it.
			MinimumAngleDegrees = 55,
			--[[
				Full benefit by 130 degrees rather than 150.

				The ramp used to still be climbing at 135, so exactly the turns
				that throw the ball furthest -- 135 through 180 -- were getting
				only part of the tightening. A 90-degree turn now lands near the
				middle of the ramp and anything sharper gets all of it.
			]]
			FullAngleDegrees = 130,
			-- Multiplies BallIntentTurnRate at full skill and a full-angle turn.
			MaximumTurnRateScale = 2.35,
			MinimumTurnRateScale = 1.1,
			-- A sharp turn cancels the in-flight touch so the ball is not left
			-- travelling along the old axis.
			CancelTouchAngleDegrees = 95,
			-- Pull the lead in through a hard turn so the ball stays reachable.
			-- 0.62 was not enough to stop the ball running on along the old lane.
			LeadTightenScale = 0.42,
			-- Extra positional authority while the ball crosses to the new lane.
			TurnPositionGainBonus = 13,
			TurnVelocityDampingBonus = 2.2,
			-- Held slightly longer so the recapture covers the whole turn rather
			-- than expiring while the body is still coming round.
			RecoverySeconds = 0.3,
		},

		-- Skill 0..1 scaling applied to the above.
		Skill = {
			-- Lateral control error in studs at zero skill; zero at full skill.
			MaximumControlErrorStuds = 0.85,
			-- Fraction of the fast-turn benefit available at zero skill.
			MinimumTurnBenefit = 0.35,
			-- First-touch precision falloff at low skill.
			MaximumFirstTouchErrorStuds = 1.1,
			-- How much slower a low-skill footballer recovers a difficult touch.
			LowSkillRecoveryScale = 0.6,
		},
	},

	Reception = {
		DebugEnabled = true,
		DiagnosticCooldown = 0.25,
		MaxReachDistance = 4.65,
		IncomingReachDistance = 5.1,
		ChaseReachDistance = 4.2,
		LoosePickupDistance = 3.35,
		ControlRadius = 1.1,
		FrontReachDistance = 4.1,
		LateralReachDistance = 2.45,
		IncomingLateralTolerance = 2.85,
		BehindTolerance = 0.65,
		LooseBehindTolerance = 0.35,
		TurnTowardBehindDot = 0.35,
		IncomingApproachDot = 0.2,
		MinTowardBallDot = 0.08,
		MinChasePlayerSpeed = 2.5,
		StationaryPlayerSpeed = 1.2,
		MaxControlCenterHeight = physicsRadius + 1.25,
		MaxControllableBallSpeed = 54,
		MaxRelativeSpeed = 42,
		IntendedReceiverReachDistance = 8.25,
		IntendedReceiverMaxBallSpeed = 145,
		IntendedReceiverMaxCenterHeight = 4.25,
		IntendedReceiverLateralTolerance = 4.25,
		IntendedReceiverWindowSeconds = 5,
		NetworkOwnershipHandoffDelay = 0.1,
		ClientServoOwnershipBuffer = 0.03,
		DuplicateReceptionGuardSeconds = 1.5,
		SlowPickupSpeed = 6,
		CaptureRelativeSpeed = 22,
		TakeInStridePlayerSpeed = 8,
		SettleLeadDistance = 2.2,
		SettleForwardSpeed = 0.5,
		SettleMaxOutputSpeed = 5,
		SettleDamping = 0.72,
		TakeInStrideLeadBase = 2.7,
		TakeInStrideLeadPerSpeed = 0.055,
		TakeInStrideLeadMin = 2.9,
		TakeInStrideLeadMax = 4.7,
		TakeInStrideSpeedBonus = 2.2,
		TakeInStrideMaxSpeed = 29,
		CaptureLeadDistance = 2.45,
		CaptureForwardSpeed = 4,
		-- A capture must not brake a full-sprint receiver so sharply that the
		-- football falls behind before client ownership becomes active.
		CaptureMaxSpeed = 30,
		FirstTouchPositionGain = 2.4,
		MaxFirstTouchCorrectionSpeed = 12,
		MaxFirstTouchOutputSpeed = 30,
		MaxFirstTouchVerticalSpeed = 1.5,
		PreserveIncomingVelocity = 0.18,
		DistanceScorePenalty = 0.55,
		RelativeSpeedScorePenalty = 0.055,
		TowardBallScoreBonus = 1.2,
		IncomingScoreBonus = 1.1,
		TimeScorePenalty = 0.75,
		IntendedReceiverScoreBonus = 0.55,
		AngularDampingOnSettle = 0.65,
		AngularDampingOnReceive = 0.25,
	},

	Visual = {
		VisualDiameter = visualDiameter,
		PresentationDiameter = visualDiameter,
		AssetFolderName = "Assets",
		FootballVisualAssetName = "FootballVisual",
		WalkLeadDistance = 2.1,
		SprintLeadDistance = 2.85,
		StationaryLeadDistance = 1.55,
		VisualLeadTime = 0.035,
		MinimumMovingLeadDistance = 1.9,
		CatchUpResponsiveness = 28,
		AheadResponsiveness = 18,
		StationaryResponsiveness = 22,
		ReconciliationDuration = 0.16,
		ExtremeReconciliationDistance = 12,
		LeadDiagnosticInterval = 0.75,
		BaseColor = Color3.fromRGB(238, 236, 229),
		PanelColor = Color3.fromRGB(36, 36, 42),
		AccentColor = Color3.fromRGB(116, 78, 255),
		BrandText = "B90",
	},

	Ownership = {
		ControlledBallOwnershipMode = "Player",
		ValidationInterval = 0.2,
		MaxControlledDistance = 13.25,
		MaxControlledSpeed = 70,
		MaxControlledVerticalSpeed = 14,
		MaxControlledDisplacementPerSecond = 105,
		ValidationPositionTolerance = 5,
		DistanceViolationGrace = 0.32,
	},

	Safety = {
		ResetFallY = -40,
		ResetOutOfBoundsPadding = 80,
	},
}

return BallConfig
