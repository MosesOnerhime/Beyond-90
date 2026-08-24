local CameraConfig = {
	DefaultMode = "Broadcast",

	Broadcast = {
		ModeName = "Broadcast",
		BroadcastSide = -1,
		Height = 86,
		FocusHeight = 1.6,
		SidelineDistance = 18,
		BaseFOV = 30,
		MinFOV = 29,
		MaxFOV = 34,
		DefaultDistancePresetIndex = 3,
		DistancePresets = {
			{ Name = "0.45x", DistanceScale = 0.45 },
			{ Name = "0.55x", DistanceScale = 0.55 },
			{ Name = "0.65x", DistanceScale = 0.65 },
			{ Name = "0.80x", DistanceScale = 0.8 },
			{ Name = "1.00x", DistanceScale = 1 },
			{ Name = "1.25x", DistanceScale = 1.25 },
			{ Name = "1.50x", DistanceScale = 1.5 },
		},
		PlayerBallWeightControlled = 0.76,
		PlayerBallWeightFree = 0.62,
		MaxBallInfluence = 9,
		LookAheadDistance = 18,
		LookAheadReferenceSpeed = 30,
		AttackingLookAheadDistance = 6,
		BallSeparationZoomScale = 0.18,
		BallSeparationZoomDeadzone = 5,
		OpenPlayFOVBoost = 0,
		GoalAreaFOVReduction = 0,
		LengthFollowStrength = 0.94,
		WidthFollowStrength = 0.86,
		TargetWidthClampScale = 0.84,
		TargetLengthClampScale = 0.6,
		FollowDeadZoneLength = 6.5,
		FollowDeadZoneWidth = 4.5,
		FollowResponsiveness = 3.2,
		CatchupResponsiveness = 5.2,
		CatchupDistance = 7,
		MaxTargetLag = 32,
		FollowDelaySeconds = 1.8,
		TargetHistorySeconds = 2.15,
		SafetyCatchupDistance = 24,
		SafetyCatchupFullDistance = 52,
		SafetyBlendResponsiveness = 2.6,
		SafetyCatchupResponsiveness = 6.5,
		WidthEdgePadding = 18,
		PositionResponsiveness = 8.5,
		PositionMaxSpeed = 72,
		PositionMaxAcceleration = 105,
		FocusResponsiveness = 10,
		FocusMaxSpeed = 62,
		FocusMaxAcceleration = 88,
		OrientationResponsiveness = 12,
		ZoomResponsiveness = 2.5,
		LengthEdgePadding = 24,
		MaxOutsideSidelineDistance = 126,
		FarSideInfieldPadding = 20,
		LengthCameraPadding = 18,
		ObstructionRaycastEnabled = true,
		ObstructionBackoff = 4,
		ObstructionLift = 18,
		ObstructionLiftSteps = 4,
		ObstructionFadeEnabled = true,
		ObstructionProbeLimit = 10,
		ObstructionTransparency = 0.65,
		BroadcastSideFadeEnabled = false,
		BroadcastSideFadeTransparency = 1,
		BroadcastSideFadeInfieldMargin = 8,
		MinimumObstructionDistance = 20,
		AttributeSampleInterval = 0.35,
	},

	ThirdPerson = {
		ModeName = "ThirdPerson",
		MinZoomDistance = 8,
		MaxZoomDistance = 32,
	},

	FirstPerson = {
		ModeName = "FirstPerson",
		Enabled = false,
		FOV = 72,
		MinZoomDistance = 0.5,
		MaxZoomDistance = 0.5,
		EyeForwardOffset = 0.2,
		EyeHeightFallback = 5.35,
		FocusDistance = 100,
		MouseSensitivity = 0.0024,
		GamepadSensitivity = 2.6,
		MinPitchDegrees = -72,
		MaxPitchDegrees = 64,
		ExitRestoreDelay = 0,
		ExitVisibilityRestoreDuration = 1.25,
	},
}

CameraConfig.Broadcast1 = CameraConfig.Broadcast
CameraConfig.Broadcast2 = table.clone(CameraConfig.Broadcast)
CameraConfig.Broadcast2.ModeName = "Broadcast2"
CameraConfig.Broadcast2.Height = 68
CameraConfig.Broadcast2.SidelineDistance = 10
CameraConfig.Broadcast2.BaseFOV = 34
CameraConfig.Broadcast2.MinFOV = 32
CameraConfig.Broadcast2.MaxFOV = 40
CameraConfig.Broadcast2.PlayerBallWeightControlled = 0.9
CameraConfig.Broadcast2.PlayerBallWeightFree = 0.72
CameraConfig.Broadcast2.LookAheadDistance = 22
CameraConfig.Broadcast2.AttackingLookAheadDistance = 10
CameraConfig.Broadcast2.MaxBallInfluence = 16
CameraConfig.Broadcast2.FollowDeadZoneLength = 7
CameraConfig.Broadcast2.FollowDeadZoneWidth = 5
CameraConfig.Broadcast2.FollowDelaySeconds = 1.1
CameraConfig.Broadcast2.TargetHistorySeconds = 1.45
CameraConfig.Broadcast2.FollowResponsiveness = 2.4
CameraConfig.Broadcast2.CatchupResponsiveness = 4
CameraConfig.Broadcast2.PositionResponsiveness = 6
CameraConfig.Broadcast2.PositionMaxSpeed = 58
CameraConfig.Broadcast2.PositionMaxAcceleration = 58
CameraConfig.Broadcast2.FocusResponsiveness = 6.5
CameraConfig.Broadcast2.FocusMaxSpeed = 52
CameraConfig.Broadcast2.FocusMaxAcceleration = 60
CameraConfig.Broadcast2.OrientationResponsiveness = 8
CameraConfig.Broadcast2.ZoomResponsiveness = 1.8
CameraConfig.Broadcast2.SafetyCatchupDistance = 22
CameraConfig.Broadcast2.SafetyCatchupFullDistance = 58
CameraConfig.Broadcast2.SafetyBlendResponsiveness = 1.8
CameraConfig.Broadcast2.SafetyCatchupResponsiveness = 5.5
CameraConfig.Broadcast2.BallSeparationZoomScale = 0.28
CameraConfig.Broadcast2.OpenPlayFOVBoost = 1.5
CameraConfig.Broadcast2.GoalAreaFOVReduction = 0.5

return CameraConfig
