local CameraConfig = {
	DefaultMode = "Broadcast",

	Broadcast = {
		ModeName = "Broadcast",
		BroadcastSide = -1,
		Height = 44,
		SidelineDistance = 14,
		BaseFOV = 42,
		MinFOV = 37,
		MaxFOV = 56,
		PlayerBallWeightControlled = 0.9,
		PlayerBallWeightFree = 0.68,
		MaxBallInfluence = 12,
		LookAheadDistance = 24,
		SpeedLookAheadScale = 0.42,
		BallSeparationZoomScale = 0.48,
		SpeedZoomScale = 0.18,
		PositionResponsiveness = 6.5,
		FocusResponsiveness = 9,
		ZoomResponsiveness = 3.5,
		LengthEdgePadding = 24,
		AttributeSampleInterval = 0.35,
	},

	FirstPerson = {
		ModeName = "FirstPerson",
		FOV = 72,
		EyeForwardOffset = 0.2,
		EyeHeightFallback = 5.35,
		PositionResponsiveness = 18,
		FocusDistance = 100,
		AttributeSampleInterval = 0.35,
	},
}

return CameraConfig
