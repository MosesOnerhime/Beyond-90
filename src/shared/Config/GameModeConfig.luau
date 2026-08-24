local GameModeConfig = {
	ReplicatedFolderName = "Beyond90GameMode",
	RequestRemoteName = "GameModeRequest",
	ExitRemoteName = "GameModeExit",
	ResetBallRemoteName = "TrainingResetBall",
	DefaultMode = "Development",
	Modes = {
		Development = {
			DisplayName = "Development",
			Enabled = true,
		},
		TrainingFree = {
			DisplayName = "Free Practice",
			Enabled = true,
			AllowsBallReset = true,
		},
		Quick3v3 = {
			DisplayName = "Quick 3v3",
			Enabled = false,
		},
		Tournament5v5 = {
			DisplayName = "Tournament 5v5",
			Enabled = false,
		},
		Clubs11v11 = {
			DisplayName = "Clubs 11v11",
			Enabled = false,
		},
	},
	ResetCooldown = 1,
}

return GameModeConfig
