local PlayerConfig = {
	Movement = {
		BaseSpeed = 16,
		SprintSpeed = 23,
		JumpEnabled = false,
		JumpPower = 0,
		JumpHeight = 0,
		AutoRotate = true,
	},

	Locomotion = {
		RawInputDeadzone = 0.05,
		StopSpeed = 0.15,
		AccelerationTime = 0.18,
		DecelerationTime = 0.24,
		SprintAccelerationTime = 0.24,
		SprintDecelerationTime = 0.32,
		TurnAccelerationTime = 0.16,
		ReverseAccelerationTime = 0.14,
		TurnSpeedLossAt90 = 0.18,
		TurnSpeedLossAt180 = 0.58,
	},

	Input = {
		SprintActionName = "Beyond90Sprint",
		SprintRemoteName = "MovementSprintRequested",
		SprintTouchButtonPosition = UDim2.new(1, -92, 1, -148),
	},
}

return PlayerConfig
