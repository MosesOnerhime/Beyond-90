local AnimationConfig = {
	--[[
		ROTATION AUTHORITY (§73).

		During a driven transition -- a 180 reversal above all -- exactly one
		system may turn the body. Three could previously write orientation in the
		same frame:

			Humanoid.AutoRotate            turns along the movement direction
			MovementController facing      reception and action facing assists
			AnimationController            the driven yaw of the turn itself

		They took it in turns to win, which is precisely what the visible stutter
		was: the driven turn stepping the yaw one way while AutoRotate or a facing
		assist pulled it back toward the velocity.

		AnimationController claims this attribute for the duration of the action
		and releases it afterwards. MovementController checks it before writing
		orientation, so the turn is uncontested and normal ownership returns the
		moment it ends.
	]]
	RotationAuthorityAttribute = "Beyond90RotationAuthority",
	RotationAuthorityAnimation = "Animation",

	DebugEnabled = true,

	Authority = {
		DisableDefaultAnimate = true,
		StopNonBeyond90LocomotionTracks = true,
	},

	Assets = {
		Locomotion = {
			Jump = "rbxassetid://135025541646177",

			-- Milestone 6.1 transition clips. These are visual transitions only;
			-- movement authority stays with MovementController.
			Transitions = {
				IdleToSprint = "rbxassetid://132361788117408",
				IdleToSprint180 = "rbxassetid://132361788117408",
				DirectionChange180 = "rbxassetid://131974818624664",
			},

			OffBall = {
				Idle = "rbxassetid://100655709305107",
				Jog = {
					Forward = "rbxassetid://107497463371889",
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
				A1OffBallJogForward = "rbxassetid://75443794500520",
			},
		},

		Actions = {
			ReceivePass = "rbxassetid://86547436800404",
			Pass = "rbxassetid://126850541210145",
			Shoot = "rbxassetid://138798529340032",
			HeadingBall = "rbxassetid://89336617530984",
		},

		-- Reactions to being challenged. Roblox animations do not move the
		-- HumanoidRootPart, so any clip that reads as falling or stumbling needs
		-- a matching code-driven root offset (see AnimationConfig.RootMotion).
		Tackled = {
			Normal = "rbxassetid://139818198071933",
			SlideFromFront = "rbxassetid://82042341415445",
			SlideFromBack = "rbxassetid://100471936001818",
		},

		InjuredWalk = "rbxassetid://140713948868201",

		Goalkeeper = {
			Idle = "rbxassetid://133331235579497",
			IdleWithBall = "rbxassetid://122918317006825",
			CatchStanding = "rbxassetid://104548309382864",
			ThrowPass = "rbxassetid://115099592784311",
			SideStep = "rbxassetid://128107875339373",
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
		JumpEnter = 0.05,
		JumpExit = 0.1,
		PassEnter = 0.05,
		PassExit = 0.12,
		TransitionEnter = 0.06,
		TransitionExit = 0.14,
	},

	-- Locomotion transition state machine. These clips are cosmetic overlays on
	-- top of the existing directional locomotion; they never gate input.
	Transitions = {
		Enabled = true,

		-- Disabled by request. Idle now crossfades straight into Jog/Sprint. The
		-- asset id and tuning are kept so the transition can be re-enabled for
		-- future experimentation without re-deriving them.
		IdleToSprint = {
			Enabled = false,
			-- Entering locomotion from a genuine standstill.
			MaximumEntrySpeed = 3.5,
			MinimumIntent = 0.35,
			FadeInTime = 0.06,
			FadeOutTime = 0.14,
			FallbackDuration = 0.55,
			PlaybackRate = 1.05,
			Cooldown = 0.6,
			Priority = Enum.AnimationPriority.Action,
		},

		-- Disabled alongside IdleToSprint; see the note above.
		IdleToSprint180 = {
			Enabled = false,
			-- Same standstill condition, but the requested direction is behind the
			-- footballer, so the body has to turn through the start.
			MaximumEntrySpeed = 3.5,
			MinimumIntent = 0.35,
			MinimumAngleDegrees = 115,
			-- Angle is measured against live facing only. A stale travel direction
			-- left over from a previous coast produced 180 starts at ~0 degrees.
			RequireStationaryFacing = true,
			-- The intent must persist briefly, so a single noisy frame cannot
			-- classify a straight-ahead start as a reversal.
			SustainSeconds = 0.06,
			DriveRotation = true,
			RotationDegreesPerSecond = 520,
			RotationHoldSeconds = 0.38,
			FadeInTime = 0.06,
			FadeOutTime = 0.14,
			FallbackDuration = 0.6,
			PlaybackRate = 1,
			Cooldown = 0.7,
			Priority = Enum.AnimationPriority.Action,
		},

		DirectionChange180 = {
			--[[
				OFF FOR NOW.

				The clip is authored as a single right-hand turn and Roblox has no
				runtime skeletal mirroring, so half of all reversals -- every one
				that goes left -- are played at a reduced blend weight against the
				direction the body is actually travelling. `UnmirroredClipWeight`
				below is the compensation for that, and a weight of 0.55 is an
				admission that the asset is wrong for the case rather than a fix
				for it.

				With this disabled the reversal falls through to ordinary
				locomotion, which turns correctly in both directions because it is
				driven by gameplay yaw rather than by an authored clip. A plain
				turn reads better than a turn leaning the wrong way.

				Everything else stays: the trigger, the handedness resolution and
				the driven-rotation handoff are all still here and all still
				correct. Set this back to true once a dedicated left-turn asset
				exists and `UnmirroredClipWeight` can go to 1.
			]]
			Enabled = false,
			-- A genuine reversal while already travelling. Curved running must not
			-- reach this threshold.
			MinimumSpeed = 11,
			MinimumAngleDegrees = 140,
			SustainSeconds = 0.05,
			-- The animation has no root yaw of its own, so gameplay drives the
			-- turn. Orientation authority is taken for the length of the clip and
			-- handed straight back.
			DriveRotation = true,
			-- The clip is authored as a turn to the player's RIGHT. -1 is right,
			-- +1 is left. Used when the requested reversal is close enough to a
			-- straight 180 that its handedness is numerically ambiguous.
			AuthoredTurnSign = -1,
			HandednessAmbiguityDegrees = 6,
			-- Weight used when the reversal goes LEFT. Roblox cannot mirror a
			-- track at runtime, so the right-authored clip is blended down rather
			-- than played at full strength against the travel direction.
			-- Set to 1 once a dedicated left-turn asset exists.
			UnmirroredClipWeight = 0.55,
			RotationDegreesPerSecond = 620,
			RotationHoldSeconds = 0.42,
			FadeInTime = 0.07,
			FadeOutTime = 0.16,
			FallbackDuration = 0.65,
			PlaybackRate = 1.1,
			Cooldown = 0.85,
			Priority = Enum.AnimationPriority.Action,
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

			JogEnterSpeed = 0.75,
			JogExitSpeed = 0.35,
			VisualExitSpeed = 4,
			MovementIntentThreshold = 0.05,
			--[[
				Below this measured speed the footballer counts as stationary for
				presentation purposes, however much direction they are holding.
			]]
			StationaryVisualSpeed = 1.5,
			--[[
				How long held intent may produce no movement before the visible
				run is dropped (§72). Long enough that real acceleration is never
				interrupted, short enough that a held footballer does not jog on
				the spot for a noticeable moment.
			]]
			StalledIntentSeconds = 0.2,
			JogReferenceSpeed = 14,
			JogPlaybackMultiplier = 1.05,
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
			ExitSpeed = 19,
			ReferenceSpeed = 28,
			PlaybackMultiplier = 1,
			MinPlaybackRate = 0.55,
			MaxPlaybackRate = 1.25,
			TurnEnterAngle = 22,
			TurnExitAngle = 12,
			TurnFullWeightAngle = 65,
			TurnMinimumSpeed = 18,
			TurnSustainTime = 0.08,
			WeightResponsiveness = 16,
			FadeInTime = 0.1,
			FadeOutTime = 0.1,
			Priority = Enum.AnimationPriority.Movement,
		},

	},

	--[[
		Root motion compensation.

		Roblox animations never translate the HumanoidRootPart, so a clip that
		reads as falling, stumbling or stepping sideways looks wrong unless the
		gameplay root is moved to match. Each entry describes, in studs and in the
		character's own local frame, the offset the clip implies:

			Forward  +ahead / -behind
			Right    +right / -left
			Up       +lift  / -drop      (negative = sink toward the pitch)

		Curve points are {alpha, scale} across normalized clip time, so the offset
		can go out and come back rather than only accumulating.
	]]
	RootMotion = {
		Enabled = true,
		-- Applied through the root CFrame each frame while a clip is active, then
		-- eased back out. Never a teleport.
		Responsiveness = 16,
		ReleaseResponsiveness = 9,

		Clips = {
			-- The source clip drives the body below the pitch surface. Lift the
			-- root through the impact so the footballer lands ON the grass.
			NormalTackled = {
				Duration = 1.15,
				Up = 0.62,
				Forward = -0.9,
				Curve = { { 0, 0 }, { 0.18, 1 }, { 0.62, 1 }, { 1, 0.15 } },
			},

			-- Challenged from the front: the footballer is taken through and
			-- falls backwards. The clip has no vertical travel of its own.
			SlideTackledFromFront = {
				Duration = 1.35,
				Up = -1.85,
				Forward = -2.6,
				Curve = { { 0, 0 }, { 0.22, 0.55 }, { 0.55, 1 }, { 1, 1 } },
			},

			-- Challenged from behind: carried forwards onto the ground.
			SlideTackledFromBack = {
				Duration = 1.35,
				Up = -1.85,
				Forward = 2.4,
				Curve = { { 0, 0 }, { 0.22, 0.55 }, { 0.55, 1 }, { 1, 1 } },
			},

			-- Keeper stumbles slightly to its right as it takes the ball standing.
			KeeperCatchStanding = {
				Duration = 0.9,
				Right = 1.15,
				Curve = { { 0, 0 }, { 0.35, 1 }, { 0.75, 1 }, { 1, 0.85 } },
			},

			-- Keeper steps forward into the throw, then recovers roughly 70% of
			-- that distance back.
			KeeperThrowPass = {
				Duration = 1.05,
				Forward = 1.9,
				Curve = { { 0, 0 }, { 0.4, 1 }, { 0.62, 1 }, { 1, 0.3 } },
			},

			-- Lateral guard step. The source clip moves left; the right-hand
			-- variant mirrors it via MirrorRight below.
			KeeperSideStep = {
				Duration = 0.72,
				Right = -1.55,
				Curve = { { 0, 0 }, { 0.45, 1 }, { 1, 1 } },
				MirrorRight = true,
			},
		},
	},

	-- Reaction clips played when a challenge lands.
	Tackled = {
		Enabled = true,
		FadeInTime = 0.05,
		FadeOutTime = 0.18,
		PlaybackRate = 1,
		Priority = Enum.AnimationPriority.Action,
		-- Movement is suppressed while the footballer is going down.
		RecoverySeconds = 0.35,
	},

	InjuredWalk = {
		Enabled = true,
		FadeInTime = 0.14,
		FadeOutTime = 0.16,
		PlaybackRate = 1,
		Priority = Enum.AnimationPriority.Movement,
	},

	Heading = {
		Enabled = true,
		FadeInTime = 0.05,
		FadeOutTime = 0.12,
		FallbackDuration = 0.8,
		PlaybackRate = 1,
		Priority = Enum.AnimationPriority.Action,
		-- Ball must be roughly head height for a header to read correctly.
		MinimumBallHeight = 3.2,
		MaximumBallHeight = 8.5,
		MaximumBallDistance = 5,
	},

	Goalkeeper = {
		Enabled = true,
		FadeInTime = 0.1,
		FadeOutTime = 0.14,
		PlaybackRate = 1,
		IdlePriority = Enum.AnimationPriority.Idle,
		ActionPriority = Enum.AnimationPriority.Action,
		MovementPriority = Enum.AnimationPriority.Movement,
		-- Below this lateral speed the keeper idles rather than side-stepping.
		SideStepMinimumSpeed = 1.6,
		FallbackDuration = 0.8,

		--[[
			Above this speed a keeper is MOVING, not guarding.

			The keeper vocabulary is a set-position one: idle, idle with the ball,
			a lateral guard step. It reads correctly while the keeper is holding
			their line and looks wrong the moment they travel, so past this speed
			the ordinary outfield locomotion set takes over.

			This was 7, and 7 is not a guard step -- it is a jog. The runtime log
			is unambiguous:

				State -> KeeperIdle family=Goalkeeper speed=6.8
				State -> KeeperIdle family=Goalkeeper speed=6.0
				State -> KeeperIdle family=Goalkeeper speed=7.0

			-- a keeper travelling at nearly half top speed with an IDLE clip on,
			so the body slid across the six-yard box with its feet planted. The
			threshold has to sit just above an actual shuffle, not just below a
			jog. Jog speed is 16, so a couple of studs per second is the honest
			boundary between adjusting your feet and going somewhere.

			Past it the directional locomotion set now genuinely works for a
			keeper, because their facing is pinned to the ball rather than to
			their travel direction: backing off plays the backward clip and
			stepping across plays the lateral ones.
		]]
		RunThreshold = 2.6,
	},

	AirbornePresentation = {
		EnterDelay = 0.28,
		GroundedVerticalSpeedTolerance = 1.5,
		MinimumFallSpeed = 3,
		ClearGroundDistancePadding = 1.5,
	},

	Jump = {
		Enabled = true,
		FallbackDuration = 0.55,
		-- The source clip reads sluggish against Beyond 90's jump arc, which
		-- peaks in roughly 0.38s. Play it faster so the animation matches.
		PlaybackRate = 1.45,
		FadeInTime = 0.05,
		FadeOutTime = 0.1,
		Priority = Enum.AnimationPriority.Action,
	},

	Pass = {
		Enabled = true,
		ActionTypes = {
			GroundPass = true,
			ThroughPass = true,
			LobPass = true,
		},
		FallbackDuration = 0.72,
		PlaybackRate = 1,
		FadeInTime = 0.05,
		FadeOutTime = 0.12,
		Priority = Enum.AnimationPriority.Action,
	},

	Shoot = {
		Enabled = true,
		FallbackDuration = 0.9,
		PlaybackRate = 1,
		FadeInTime = 0.05,
		FadeOutTime = 0.12,
		ExitBlendTime = 0.12,
		Priority = Enum.AnimationPriority.Action,
	},

	Reception = {
		Enabled = true,
		PassActionTypes = {
			GroundPass = true,
			ThroughPass = true,
			LobPass = true,
		},
		FadeInTime = 0.06,
		FadeOutTime = 0.12,
		ExitBlendTime = 0.12,
		FallbackDuration = 0.7,
		PlaybackRate = 1,
		Priority = Enum.AnimationPriority.Action,
	},

	StopTrap = {
		Enabled = true,
		TriggerSpeed = 4,
		MaximumBallLead = 4.5,
		FadeInTime = 0.06,
		FadeOutTime = 0.08,
		ExitBlendTime = 0.1,
		FallbackDuration = 0.65,
		PlaybackRate = 1,
		Priority = Enum.AnimationPriority.Action,
	},
}

return AnimationConfig
