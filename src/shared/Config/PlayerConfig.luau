local PlayerConfig = {
	Movement = {
		BaseSpeed = 14,
		SprintSpeed = 28,
		JumpEnabled = true,
		JumpPower = 19,
		JumpHeight = 0,
		AutoRotate = true,
		JumpProfile = {
			GravityCompensation = 0.75,
			MaxAssistDuration = 0.78,
			ExpectedAirTime = 0.76,
			ExpectedPeakHeight = 3.7,
		},
	},

	Locomotion = {
		RawInputDeadzone = 0.05,
		StopSpeed = 0.15,
		AccelerationTime = 0.12,
		DecelerationTime = 2.2,
		SprintAccelerationTime = 0.28,
		SprintDecelerationTime = 1.7,
		TurnAccelerationTime = 0.18,
		ReverseAccelerationTime = 0.28,
		TurnSpeedLossAt90 = 0.18,
		TurnSpeedLossAt180 = 0.58,
		PossessionTurn = {
			Enabled = true,
			MinimumPlayerSpeed = 4,
			ImmediateAngleDegrees = 25,
			MajorAngleDegrees = 60,
			SevereAngleDegrees = 120,
			MinimumPreparationSeconds = 0.08,
			SmallCorrectionMaximumWaitSeconds = 0.2,
			JogModerateMaximumWaitSeconds = 0.35,
			SprintModerateMaximumWaitSeconds = 0.45,
			JogMaximumWaitSeconds = 0.5,
			SprintMaximumWaitSeconds = 0.65,
			ContactLeadDistance = 3.8,
			ContactRelativeSpeed = 10,
		},
		DiagnosticInterval = 0.5,
		ActionMovement = {
			Pass = {
				BrakeTime = 0.13,
				BrakeDuration = 0.16,
				LockDuration = 0.26,
				ExitDuration = 0.1,
			},
			ReceivePass = {
				BrakeTime = 0.12,
				BrakeDuration = 0.14,
				LockDuration = 0.24,
				ExitDuration = 0.1,
			},
			Shoot = {
				BrakeTime = 0.11,
				BrakeDuration = 0.14,
				LockDuration = 0.3,
				ExitDuration = 0.12,
			},
		},
		ReceptionAssist = {
			Enabled = true,
			MaxDistance = 42,
			StopDistance = 2.6,
			BrakeDistance = 8,
			MaxMoveMagnitude = 0.9,
			ManualBlendStart = 0.35,
			ManualOverrideMagnitude = 0.9,
			ExpiryGraceTime = 2.2,
			DiagnosticInterval = 0.75,
			LiveTargetWeight = 0.55,
			MaxLiveTargetCorrection = 24,
			FacingResponsiveness = 12,
			FacingMinimumBallSpeed = 4,
			FacingRelockAngle = 35,
			PostContactFacingHold = 0.32,
			FacingDiagnosticInterval = 0.75,
		},
		LooseBallAssist = {
			Enabled = true,
			ActivationDistance = 10.5,
			ContactDistance = 2.55,
			PredictionTime = 0.16,
			MaximumMoveMagnitude = 0.92,
			ManualBlendStart = 0.45,
			ManualOverrideMagnitude = 0.95,
		},
	},

	Input = {
		InputFolderName = "Beyond90Inputs",
		-- How long a movement key must be held with no InputAction report before
		-- the UserInputService fallback takes over.
		InputActionWatchdogSeconds = 0.4,
		PlayContextName = "Beyond90PlayContext",
		MoveActionName = "Beyond90Move",
		SprintActionName = "Beyond90Sprint",
		JumpActionName = "Beyond90Jump",
		CameraToggleActionName = "Beyond90CameraToggle",
		PassActionName = "Beyond90Pass",
		ThroughPassActionName = "Beyond90ThroughPass",
		KnockOnActionName = "Beyond90KnockOn",
		ShootActionName = "Beyond90Shoot",
		TackleActionName = "Beyond90Tackle",
		CameraToggleKey = Enum.KeyCode.C,
		PassKey = Enum.KeyCode.E,
		ThroughPassKey = Enum.KeyCode.Q,
		KnockOnKey = Enum.KeyCode.R,
		ShootKey = Enum.KeyCode.F,
		-- Out of possession this is the defensive challenge. It does not collide
		-- with Pass/Through/Shoot/KnockOn/Sprint or the camera keys.
		TackleKey = Enum.KeyCode.V,
		CameraLockKey = Enum.KeyCode.L,
		JumpKey = Enum.KeyCode.Space,
		SprintRemoteName = "MovementSprintRequested",
		AutoSprintDefaultEnabled = false,
		AutoSprintThreshold = 0.9,
		SprintTouchButtonPosition = UDim2.new(1, -92, 1, -148),
	},

	Appearance = {
		StandardizeEnabled = true,
		RequiredRigType = "R15",
		ApplyDescriptionStandardization = false,
		ScaleToCanonicalHeight = false,
		HeightScale = 1,
		WidthScale = 1,
		DepthScale = 1,
		HeadScale = 1,
		BodyTypeScale = 1,
		ProportionScale = 1,
		RemoveAnimationPacks = false,
		RemoveBodyPackageParts = false,
		IntendedHeightStuds = 6,
		HeightTestOptionsStuds = { 6, 6.25, 6.5 },
		DevelopmentFootballerScaleEnabled = true,
		DevelopmentFootballerTargetHeightStuds = 8.27,

		--[[
			PLAYER IDENTITY.

			Beyond 90's fantasy is that YOU are one footballer on the pitch, and
			until now every footballer was literally the same body: the place has a
			StarterPlayer.StarterCharacter, so every player spawned as that model
			regardless of their own avatar. There was no identity to have.

			The default is now the player's OWN Roblox avatar. Their hair, their
			colours, their accessories -- applied onto the same rig, so nothing
			downstream has to care which body it is looking at.

			What is deliberately NOT inherited is SIZE. Every footballer is scaled
			to the same canonical height afterwards, because height in this game is
			not cosmetic: the pitch, the goals, the ball, the dribble lead
			distances, the camera framing and the grounding calibration are all
			tuned around one footballer height, and a player who joined with a
			taller avatar would get a longer stride and a wider reach. That is a
			competitive advantage bought in the avatar shop, which section 41
			rules out in as many words. So: your face, everyone's frame.

			`Beyond90Avatar` keeps the uniform look for players who prefer it, and
			is what a future kit / customisation system would extend.
		]]
		Identity = {
			Enabled = true,
			Sources = { RobloxAvatar = "RobloxAvatar", Beyond90Avatar = "Beyond90Avatar" },
			Default = "RobloxAvatar",
			-- Stored on the player so any system can read the choice; session
			-- scoped, because persistence is a later milestone.
			AttributeName = "Beyond90AvatarSource",
			-- A web call. Bounded, and a failure falls back to the uniform body
			-- rather than blocking the spawn.
			FetchTimeoutSeconds = 6,
			RemoteName = "AvatarSourceRequest",
		},
		Grounding = {
			TargetFootClearanceStuds = 0.13,
			VisualSoleOffsetStuds = 0.035,
			MinimumHipHeightStuds = 3.78,
			AllowDownwardHipHeightCorrection = false,
			GeometryHipHeightCorrectionEnabled = false,
			FootGroundToleranceStuds = 0.03,
			FloorProbeDistanceStuds = 20,
			MaxHipHeightCorrectionStuds = 0.55,
			ValidationCanAdjust = true,
			MaxLateHipHeightCorrectionStuds = 0.25,
			CalibrationDelaySeconds = 2.5,
			SettleRetryDelaySeconds = 1.5,
			MaxSettleRetries = 1,
			ValidationDelaySeconds = 5.5,
			FinalValidationDelaySeconds = 7.5,
			DiagnosticSampleSeconds = 2.5,
			DiagnosticMinSamples = 30,
			ContactFootVerticalVelocityThreshold = 1.5,
			DiagnosticFloatToleranceStuds = 0.18,
		},
	},

	Presentation = {
		PlayerIndicator = {
			Enabled = true,
			BaseRadius = 3.3,
			PossessionRadius = 3.8,
			SprintRadius = 4.2,
			SprintPossessionRadius = 4.55,
			MaximumRadius = 4.65,
			PossessionLeadPadding = 0,
			RadiusResponsiveness = 6,
			SegmentCount = 56,
			SegmentThickness = 0.12,
			SegmentHeight = 0.04,
			GroundOffset = 0.045,
			NormalColor = Color3.fromRGB(230, 224, 255),
			SprintColor = Color3.fromRGB(57, 177, 240),
			ColorResponsiveness = 10,
			Transparency = 0.2,
			GlowColor = Color3.fromRGB(137, 99, 255),
			GlowThickness = 0.32,
			GlowTransparency = 0.76,
			OverheadArrowColor = Color3.fromRGB(68, 78, 255),
			OverheadArrowOutlineColor = Color3.fromRGB(9, 11, 30),
			OverheadArrowHeight = 1.55,
			OverheadArrowWorldSize = 1.15,
			OverheadArrowWorldHeight = 0.92,
			OverheadArrowStripCount = 10,
			OverheadArrowOutlineThickness = 0.065,
			ArrowWidth = 1.15,
			ArrowLength = 1.5,
			ArrowHeight = 0.07,
			ArrowStripCount = 10,
			ArrowGap = 0.55,
			ArrowResponsiveness = 18,
			ArrowFadeResponsiveness = 14,
			ArrowShowIntentThreshold = 0.08,
			ArrowShowSpeedThreshold = 0.8,
			IntentAnticipationSeconds = 0.25,
			FloorProbeDistance = 20,
		},
	},

	GameplayProfile = {
		CanonicalPlayerHeight = 6,
		CanonicalBodyRadius = 1.04,
		CanonicalFootContactHeight = 0.25,
		CanonicalFootForwardOffset = 1.25,
	},
}

return PlayerConfig
