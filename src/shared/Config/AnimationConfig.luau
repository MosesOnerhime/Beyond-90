local AnimationConfig = {
	DebugEnabled = true,

	Assets = {
		Locomotion = {
			OffBall = {
				JogForward = "rbxassetid://79878421059664",
			},

			Ball = {
				JogForward = nil,
			},
		},
	},

	Locomotion = {
		Jog = {
			Enabled = true,
			TemporaryUseOffBallJogForBallPlaceholder = true,

			JogEnterSpeed = 7.5,
			JogExitSpeed = 5,
			JogReferenceSpeed = 14,
			JogPlaybackMultiplier = 1,
			JogPlaybackMultiplierMin = 0.8,
			JogPlaybackMultiplierMax = 1.6,
			JogPlaybackMultiplierStep = 0.05,
			JogMinPlaybackRate = 0.55,
			JogMaxPlaybackRate = 1.6,

			SprintEnterSpeed = 24,
			SprintExitSpeed = 18,

			FadeInTime = 0.12,
			FadeOutTime = 0.1,
			DefaultTrackFadeTime = 0.08,
			SuppressDefaultMovementTracks = true,
			Priority = Enum.AnimationPriority.Movement,
		},
	},
}

return AnimationConfig
