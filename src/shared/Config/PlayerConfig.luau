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
		DecelerationTime = 0.2,
		SprintAccelerationTime = 0.22,
		SprintDecelerationTime = 0.3,
		WalkTurnRate = 13,
		SprintTurnRate = 8,
		HighSpeedTurnSlowdown = 0.35,
		TurnSpeedLoss = 0.48,
		ReverseDot = -0.55,
		ReverseBrakeFactor = 0.22,
	},

	Input = {
		SprintActionName = "Beyond90Sprint",
		SprintRemoteName = "MovementSprintRequested",
		SprintTouchButtonPosition = UDim2.new(1, -92, 1, -148),
	},
}

return PlayerConfig
