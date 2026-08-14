local WorldScaleConfig = require(script.Parent.WorldScaleConfig)

local PlayerConfig = {
	Movement = {
		BaseSpeed = 12.5,
		SprintSpeed = 30,
		JumpEnabled = false,
		JumpPower = 0,
		JumpHeight = 0,
		AutoRotate = true,
	},

	Locomotion = {
		RawInputDeadzone = 0.05,
		StopSpeed = 0.15,
		AccelerationTime = 0.18,
		DecelerationTime = 0.44,
		SprintAccelerationTime = 1.28,
		SprintDecelerationTime = 0.62,
		TurnAccelerationTime = 0.18,
		ReverseAccelerationTime = 0.28,
		TurnSpeedLossAt90 = 0.18,
		TurnSpeedLossAt180 = 0.58,
		DiagnosticInterval = 0.5,
	},

	Input = {
		InputFolderName = "Beyond90Inputs",
		PlayContextName = "Beyond90PlayContext",
		MoveActionName = "Beyond90Move",
		SprintActionName = "Beyond90Sprint",
		CameraToggleActionName = "Beyond90CameraToggle",
		CameraToggleKey = Enum.KeyCode.C,
		SprintRemoteName = "MovementSprintRequested",
		AutoSprintDefaultEnabled = false,
		AutoSprintThreshold = 0.9,
		SprintTouchButtonPosition = UDim2.new(1, -92, 1, -148),
	},

	Appearance = {
		StandardizeEnabled = true,
		RequiredRigType = "R15",
		ScaleToCanonicalHeight = true,
		HeightScale = 1,
		WidthScale = 1,
		DepthScale = 1,
		HeadScale = 1,
		BodyTypeScale = 0,
		ProportionScale = 0,
		RemoveAnimationPacks = true,
		RemoveBodyPackageParts = true,
		TargetHeightStuds = WorldScaleConfig.PlayerHeightTestStuds,
	},

	GameplayProfile = {
		CanonicalPlayerHeight = WorldScaleConfig.PlayerHeightTestStuds,
		CanonicalBodyRadius = 1.04,
		CanonicalFootContactHeight = 0.25,
		CanonicalFootForwardOffset = 1.25,
	},
}

return PlayerConfig
