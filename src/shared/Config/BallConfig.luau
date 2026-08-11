local BallConfig = {
	Name = "DevelopmentFootball",
	Radius = 1.4,
	SpawnHeight = 4,
	MaxSpeed = 70,

	PhysicalProperties = {
		Density = 0.7,
		Friction = 0.35,
		Elasticity = 0.45,
		FrictionWeight = 1,
		ElasticityWeight = 1,
	},

	BasicTouch = {
		CheckInterval = 0.08,
		InteractionRadius = 4.2,
		MaxVerticalDifference = 4,
		MinPlayerSpeed = 2,
		MinTowardBallDot = 0.2,
		Cooldown = 0.18,
		WalkTargetSpeed = 15,
		SprintTargetSpeed = 21,
		MaxImpulseDeltaSpeed = 10,
		UpwardLiftSpeed = 0.4,
	},

	Control = {
		AcquireDistance = 3.9,
		ReleaseDistance = 6.8,
		ControlOriginRadius = 1.55,
		MinimumControlSeparation = 0.35,
		ControlTargetDistanceWalk = 3.8,
		ControlTargetDistanceSprint = 5.3,
		MaximumControllableBallSpeed = 28,
		ControlHeightTolerance = 2.2,
		ControlRetentionMaxSpeed = 36,
		ControlRetentionHeightTolerance = 3,
		AcquireMinPlayerSpeed = 2,
		AcquireMinTowardBallDot = 0.12,
		ControlReleaseBehindThreshold = -0.65,
		ReleaseGracePeriod = 0.24,
		DribbleTouchStrengthWalk = 2.8,
		DribbleTouchStrengthSprint = 3.8,
		DribbleTouchInterval = 0.1,
		MaxDribbleImpulseDeltaSpeed = 7,
		StationaryPlayerSpeed = 1,
		TargetDeadzone = 0.6,
		DirectionSmoothing = 0.35,
		SharpTurnDirectionDot = -0.1,
		SeparationCorrectionStrength = 6.5,
		MaxSeparationImpulseDeltaSpeed = 6,
		ExistingControllerScoreBonus = 1.5,
		ControlStealScoreMargin = 1.25,
	},

	Safety = {
		ResetFallY = -40,
		ResetOutOfBoundsPadding = 80,
	},
}

return BallConfig
