local AnimationConfig = {
	DebugEnabled = true,

	Authority = {
		DisableDefaultAnimate = true,
		StopNonBeyond90LocomotionTracks = true,
	},

	Assets = {
		Locomotion = {
			OffBall = {
				Idle = "rbxassetid://100655709305107",
				JogForward = "rbxassetid://107084636256080",
			},

			Ball = {
				JogForward = nil,
			},

			Historical = {
				A0OffBallJogForward = "rbxassetid://79878421059664",
			},
		},
	},

	Locomotion = {
		Idle = {
			Enabled = true,
			EnterSpeed = 0.8,
			ExitSpeed = 1.4,
			FadeInTime = 0.14,
			FadeOutTime = 0.12,
			Priority = Enum.AnimationPriority.Idle,
		},

		Jog = {
			Enabled = true,
			TemporaryUseOffBallJogForBallPlaceholder = true,

			JogEnterSpeed = 7.5,
			JogExitSpeed = 5,
			JogReferenceSpeed = 14,
			JogPlaybackMultiplier = 1.6,
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
			Priority = Enum.AnimationPriority.Movement,
		},
	},
}

return AnimationConfig
