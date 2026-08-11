local PlayerConfig = {
	Movement = {
		BaseSpeed = 16,
		SprintSpeed = 23,
		JumpEnabled = false,
		JumpPower = 0,
		JumpHeight = 0,
		AutoRotate = true,
	},

	Input = {
		SprintActionName = "Beyond90Sprint",
		SprintRemoteName = "MovementSprintRequested",
		SprintTouchButtonPosition = UDim2.new(1, -92, 1, -148),
	},
}

return PlayerConfig
