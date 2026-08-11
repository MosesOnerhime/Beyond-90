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

	Safety = {
		ResetFallY = -40,
		ResetOutOfBoundsPadding = 80,
	},
}

return BallConfig
