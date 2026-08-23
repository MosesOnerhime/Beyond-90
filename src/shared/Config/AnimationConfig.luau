local AnimationConfig = {
	DebugEnabled = true,

	Authority = {
		DisableDefaultAnimate = true,
		StopNonBeyond90LocomotionTracks = true,
	},

	Assets = {
		Locomotion = {
			Jump = "rbxassetid://135025541646177",
			OffBall = {
				Idle = "rbxassetid://100655709305107",
				Jog = {
					Forward = "rbxassetid://92336242583689",
					ForwardLeft = "rbxassetid://119455746372471",
					ForwardRight = "rbxassetid://116026120979285",
					Left = "rbxassetid://132655180471509",
					Right = "rbxassetid://123839178587148",
					Backward = "rbxassetid://140482033441047",
					BackLeft = "rbxassetid://96516897081411",
					BackRight = "rbxassetid://119089287285303",
				},
				Sprint = {
					Forward = "rbxassetid://131195698609108",
					TurnRight = "rbxassetid://138329456988853",
					TurnLeft = "rbxassetid://115476908545071",
				},
			},

			-- Possession-specific locomotion clips are intentionally absent in A1.
			Ball = {
				Jog = {},
				Sprint = {},
			},

			Historical = {
				A0OffBallJogForward = "rbxassetid://79878421059664",
			},
		},

		Actions = {
			DirectionChange180 = "rbxassetid://139073207440259",
			ReceivePass = "rbxassetid://86547436800404",
			Pass = "rbxassetid://126850541210145",
			Shoot = "rbxassetid://138798529340032",
		},
	},

	Blend = {
		IdleToLocomotion = 0.08,
		LocomotionToIdle = 0.1,
		JogDirectional = 0.08,
		JogToSprint = 0.1,
		SprintToJog = 0.1,
		ActionEnter = 0.06,
		ActionExit = 0.12,
		DirectionChangeExit = 0.14,
		JumpEnter = 0.05,
		JumpExit = 0.1,
		PassEnter = 0.05,
		PassExit = 0.12,
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

			JogEnterSpeed = 0.75,
			JogExitSpeed = 0.35,
			MovementIntentThreshold = 0.05,
			JogReferenceSpeed = 14,
			JogPlaybackMultiplier = 0.9,
			JogPlaybackMultiplierMin = 0.8,
			JogPlaybackMultiplierMax = 1.6,
			JogPlaybackMultiplierStep = 0.05,
			JogMinPlaybackRate = 0.55,
			JogMaxPlaybackRate = 1.6,

			DirectionOrder = {
				"Forward",
				"ForwardRight",
				"Right",
				"BackRight",
				"Backward",
				"BackLeft",
				"Left",
				"ForwardLeft",
			},
			DirectionAngles = {
				Forward = 0,
				ForwardRight = 45,
				Right = 90,
				BackRight = 135,
				Backward = 180,
				BackLeft = -135,
				Left = -90,
				ForwardLeft = -45,
			},
			PerDirectionPlaybackMultiplier = {
				Forward = 1,
				ForwardLeft = 1,
				ForwardRight = 1,
				Left = 1,
				Right = 1,
				Backward = 1,
				BackLeft = 1,
				BackRight = 1,
			},
			DirectionalDeadZone = 0.05,
			WeightResponsiveness = 18,
			DominantWeightHysteresis = 0.12,
			FadeInTime = 0.12,
			FadeOutTime = 0.1,
			DefaultTrackFadeTime = 0.08,
			Priority = Enum.AnimationPriority.Movement,
		},

		Sprint = {
			Enabled = true,
			IntentThreshold = 0.05,
			ExitSpeed = 18,
			ReferenceSpeed = 30,
			PlaybackMultiplier = 1,
			MinPlaybackRate = 0.55,
			MaxPlaybackRate = 1.25,
			TurnEnterAngle = 22,
			TurnExitAngle = 12,
			TurnFullWeightAngle = 65,
			WeightResponsiveness = 16,
			FadeInTime = 0.1,
			FadeOutTime = 0.1,
			Priority = Enum.AnimationPriority.Movement,
		},

		DirectionChange = {
			Enabled = true,
			TriggerAngle = 150,
			MinimumSpeed = 7.5,
			Cooldown = 0.7,
			FadeInTime = 0.06,
			FadeOutTime = 0.1,
			ExitBlendTime = 0.14,
			FallbackDuration = 0.55,
			PlaybackRate = 1,
			RootAuditEnabled = true,
			Priority = Enum.AnimationPriority.Action,
		},
	},

	Jump = {
		Enabled = true,
		FallbackDuration = 0.8,
		PlaybackRate = 1,
		FadeInTime = 0.05,
		FadeOutTime = 0.1,
		Priority = Enum.AnimationPriority.Action,
	},

	Pass = {
		Enabled = true,
		ActionTypes = {
			GroundPass = true,
			ThroughPass = true,
		},
		FallbackDuration = 0.72,
		PlaybackRate = 1,
		FadeInTime = 0.05,
		FadeOutTime = 0.12,
		Priority = Enum.AnimationPriority.Action,
	},

	Shoot = {
		Enabled = false,
		Priority = Enum.AnimationPriority.Action,
	},

	Reception = {
		Enabled = true,
		PassActionTypes = {
			GroundPass = true,
			ThroughPass = true,
		},
		FadeInTime = 0.06,
		FadeOutTime = 0.12,
		ExitBlendTime = 0.12,
		FallbackDuration = 0.7,
		PlaybackRate = 1,
		Priority = Enum.AnimationPriority.Action,
	},
}

return AnimationConfig
