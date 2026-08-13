local PlayerConfig = {
	Movement = {
		BaseSpeed = 10.8,
		SprintSpeed = 15.8,
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
		SprintAccelerationTime = 0.24,
		SprintDecelerationTime = 0.56,
		TurnAccelerationTime = 0.13,
		ReverseAccelerationTime = 0.16,
		TurnSpeedLossAt90 = 0.14,
		TurnSpeedLossAt180 = 0.5,
		DiagnosticInterval = 0.5,
	},

	Input = {
		InputFolderName = "Beyond90Inputs",
		PlayContextName = "Beyond90PlayContext",
		MoveActionName = "Beyond90Move",
		SprintActionName = "Beyond90Sprint",
		SprintRemoteName = "MovementSprintRequested",
		SprintTouchButtonPosition = UDim2.new(1, -92, 1, -148),
	},
}

return PlayerConfig
