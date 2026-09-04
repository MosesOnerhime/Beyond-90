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
			-- Played on the scorer's own client when their team goes ahead.
			Celebration = "rbxassetid://96125809200675",
			HeadingBall = "rbxassetid://89336617530984",

			--[[
				THE TACKLER'S OWN CLIPS -- ASSETS STILL NEEDED (Milestone 6.8).

				Every clip under `Tackled` below animates the player who was
				challenged. Nothing has ever animated the player doing the
				challenging, which is the most visible hole in the feature: a slide
				currently launches a footballer along the floor in a running pose.

				These two slots are deliberately empty rather than absent. Track
				loading is pcall-guarded (AIAnimationService.loadTrack), so an empty
				id loads nothing and every PlayAction call for it is a no-op -- the
				wiring below is already complete and live, and dropping a real
				rbxassetid in here is the only remaining step.

				When the clips exist they also need:
				  - RootMotion entries, authored against the actual clip rather than
				    guessed. The slide already carries the body with a real launch
				    velocity (DefendingConfig.Slide.LaunchSpeed), so its root motion
				    must NOT add forward travel or the two will compound.
				  - Semantic markers per AGENTS.md 39: ActionCommit, TackleContact,
				    Recover. TackleContact is presentation only -- it may say WHEN
				    contact reads, never WHETHER the challenge was valid, which the
				    server has already decided by then.
			]]
			StandingTackle = "",
			SlideTackle = "",
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
			--[[
				THE DIVES.

				Authored in place: the clips put the keeper on the floor but move
				the rig neither sideways nor downward, so the travel and the fall
				are both code-driven. `RootMotion.Actions.KeeperDiveLeft` /
				`KeeperDiveRight` supply the drop, and the dive's lateral travel
				is the server-approved launch velocity the movement controller is
				already driving the humanoid with.
			]]
			DiveLeft = "rbxassetid://85231153864936",
			DiveRight = "rbxassetid://108977133363146",

			--[[
				GETTING BACK UP -- ITS OWN CLIP PER SIDE.

				The dive used to end and simply release the body, with the code
				unwinding the 78-degree roll over a fixed 0.34s. That was a timer
				pretending to be an animation: it could not know when the keeper
				was actually back on their feet, so it was always approximately
				wrong, and the keeper drifted out of the dive.

				With a real clip the CLIP is the authority. Its length decides how
				long the keeper is committed, the roll unwinds across exactly that
				window, and input returns when the keeper is standing rather than
				when a constant expires.

				Sided to match the dive that caused it: getting up from a left
				dive is not the same movement as getting up from a right one.
			]]
			GetUpLeft = "rbxassetid://136113003809024",
			GetUpRight = "rbxassetid://123002585780935",
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
		--[[
			WHICH WAY THE KEEPER IS GOING, DECIDED BY ANGLE.

			`SideStepMinimumSpeed` is a threshold in STUDS PER SECOND, and a
			speed cannot express "sideways". The faster the keeper travels, the
			smaller the wobble needed to clear it -- at their 16 stud/s line pace
			a deviation of 5.7 degrees is enough:

				speed  6 -> side-steps from 15.5 deg off straight
				speed 16 -> side-steps from  5.7 deg off straight
				speed 24 -> side-steps from  3.8 deg off straight

			Which is exactly what the runtime showed. Every one of these was
			playing the side step:

				travelAngle=  14.3  lat= 3.95   <- straight ahead
				travelAngle= -20.2  lat=-3.60   <- straight ahead
				travelAngle= 154.2  lat=10.38   <- BACKWARDS
				travelAngle=-159.0  lat=-6.21   <- BACKWARDS

			One cause, three reported symptoms: the strafe never read as a
			strafe (it was always on), jog-backwards never played (backwards
			travel has lateral too), and the clip thrashed against jog whenever
			the wobble crossed the threshold.

			Sectors fix it because a sector is what "sideways" actually means.
			0 is straight ahead, +/-180 is straight back:

				|angle| <  50   forward   -> outfield jog / sprint
				|angle| > 130   backward  -> outfield jog backward
				otherwise       sideways  -> the keeper's own side step
		]]
		ForwardSectorDegrees = 50,
		--[[
			130 was too strict. Back-and-across travel lands in the 110-120 band
			and never reached the backward sector, so it kept side-stepping:

				travelAngle=-117.0 fwd= -8.59 speed=15.9  -> Sideways
				travelAngle= 114.8 fwd= -4.83 speed= 9.5  -> Sideways
				travelAngle= 117.6 fwd= -0.21 speed=16.0  -> Sideways

			110 puts those in Backward while leaving a 60 degree sideways band
			(50..110) centred on straight across the goal, which is where a
			keeper's line work actually lives.
		]]
		BackwardSectorDegrees = 110,
		--[[
			How far past a boundary the travel must go before the sector changes.

			Without it a keeper holding a diagonal near a boundary alternates at
			frame rate, which is the flip-flop the log caught (five clip changes
			in 450 ms on a steady input). This is GameplayFootball's continuity
			principle in its cheapest form: prefer the clip already running
			unless the body has clearly left its sector.
		]]
		SectorHysteresisDegrees = 12,
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

		--[[
			WHEN A KEEPER STOPS SHUFFLING AND STARTS RUNNING.

			The side step is a shuffle along the line, and it was being used for
			ANY movement the body called lateral -- including sprints. Because a
			keeper's body turns to face the ball, running out to close an
			attacker down is "sideways" as far as the torso is concerned, so the
			log was full of the shuffle clip at 30 and even 45 studs/s:

				State -> KeeperSideStep speed=45.2 playback=1.45

			Above this speed the keeper is running, whatever angle the body
			happens to be at, and the outfield locomotion set takes over -- it has
			proper directional clips (left, right, backward) so a fast sideways
			run still gets an honest one.

			RAISED FROM 9, WHICH WAS THE OVERCORRECTION.

			A keeper's ordinary line pace is Positioning.MoveSpeed = 15 studs/s
			and their rush is 26. A ceiling of 9 therefore sat BELOW walking
			pace, so every piece of normal line work exceeded it and handed over
			to the outfield jog -- the side step only ever played when the keeper
			was barely moving, which is the opposite of the intent.

			The ceiling exists to catch speeds no keeper can produce on their
			feet, which in practice means the body still carrying dive velocity.
			Set above the rush so genuine line work always keeps the keeper's own
			clip. Note the get-up clip now owns the body through the whole dive
			recovery anyway, so this is a backstop rather than the main defence.
		]]
		SideStepMaximumSpeed = 32,

		--[[
			THE KEEPER'S OWN CLIPS SPEED UP RATHER THAN BEING REPLACED.

			Requested: a keeper moving faster should play its own animation
			faster, not switch to the outfield sprint clip. A goalkeeper shuffling
			hard across its line is still a goalkeeper -- the outfield sprint reads
			as an outfielder who happens to be wearing gloves.

			Playback scales linearly with speed between the two reference speeds
			below and is clamped, so a keeper adjusting its feet still looks
			deliberate and one moving at pace looks urgent without the clip
			turning into a blur.
		]]
		SpeedScaledPlayback = true,
		--[[
			Speed at which the clip plays at its authored rate.

			Raised from 7, and the ceiling lowered from 2.3, because the side
			step was running at its cap almost permanently -- the log is full of
			`KeeperSideStep playback=2.30` at speeds of 25 to 45 studs/s, which
			is feet scrabbling far faster than the body is actually travelling.

			The reference speed is now a genuine shuffle-to-stride crossover and
			the cap is a stride rather than a blur, so the clip reads as
			connected to the ground the keeper is covering.
		]]
		PlaybackReferenceSpeed = 11,
		MinimumPlaybackRate = 0.8,
		MaximumPlaybackRate = 1.45,

		--[[
			THE DIVE.

			Its own fades because a dive is not a guard step. Going in is quick --
			the keeper is already moving by the time the clip is asked for -- and
			coming out is slower, because the exit is the visible end of a save
			settling into `KeeperIdleWithBall`.
		]]
		DiveFadeInTime = 0.05,
		DiveExitBlendTime = 0.22,
		--[[
			THE FALL HAS TO FINISH INSIDE THE DIVE.

			Measured off the clip, DiveLeft's torso goes down over about 1.3
			seconds and then lies still:

				t=0.00  17.7      t=0.80   54.3      t=1.33  102.1
				t=0.27  23.4      t=1.07   86.7      t=1.87  107.9  (flat after)

			`GoalkeeperConfig.Dive.Duration` is 0.78s, so at playback rate 1 the
			keeper was cut off at roughly 54 degrees -- still mid-fall -- and the
			get-up then started from its own lying pose near 100. That jump is
			part of what reads as the dive glitching.

			1.7 puts the 1.3s fall inside the 0.78s window (0.78 * 1.7 = 1.33),
			so the keeper is actually down when the dive ends and the get-up
			begins from where the dive left him. The COMMITTED WINDOW is
			unchanged -- this only makes the visual finish inside it, so no
			gameplay timing moves.
		]]
		DivePlaybackRate = 2.2,

		--[[
			GETTING UP.

			The clip is the authority for the whole recovery: its length decides
			how long the keeper stays committed, the body roll unwinds across
			exactly that window, and input comes back when the clip ends.

			`Beyond90KeeperGetUpUntil` is how that reaches MovementController --
			the animation publishes when it will be finished, and the movement
			side reads it rather than both of them holding their own timer and
			drifting apart. When no clip is loaded the attribute is never set and
			MovementController falls back to GoalkeeperConfig.Dive.StandUpSeconds,
			so a missing asset degrades to the old behaviour rather than leaving
			the keeper stuck on the floor.
		]]
		GetUpAttribute = "Beyond90KeeperGetUpUntil",
		--[[
			SET BY AnimationController THE FRAME THE DIVE CLIP ACTUALLY STARTS.

			The server publishes the approved dive, and two independent
			controllers react to it: MovementController drives the body,
			AnimationController starts the clip. They run in separate callbacks,
			so the body was moving one or two frames before the dive was drawn --

				35.111  server approves the dive
				35.118  clip is still KeeperIdle, body already launching
				35.135  KeeperDiveLeft finally starts

			-- about 24ms of the keeper sliding in the dive direction while still
			standing up. Reported as "moves slightly to the dive direction before
			the animation actually plays".

			The clip owns the moment now: it publishes when it began, and the
			launch waits for it. Same "one owner publishes, the other reads"
			shape as `GetUpAttribute`.
		]]
		DiveStartedAttribute = "Beyond90KeeperDiveClipStarted",
		GetUpFadeInTime = 0.08,
		GetUpExitBlendTime = 0.18,
		--[[
			This was 1 and was never applied to the track -- it only ever sized
			the get-up WINDOW. The clip itself fell through to the generic
			`MinimumPlaybackRate` of 0.8, so every get-up played 20% slow while
			the window was sized as though it were not, and the two disagreed by
			exactly that much. The runtime said so plainly:

				State -> KeeperGetUpRight ... playback=0.80

			Now applied to the track as well as the window, and raised, because a
			keeper pushes off the floor rather than easing off it.
		]]
		GetUpPlaybackRate = 1.8,
		-- Used only if the clip reports no length (asset still loading).
		GetUpFallbackDuration = 0.7,

		--[[
			SPRINTING BACKWARDS.

			A keeper faces the ball, so retreating at pace is backward travel --
			and the sprint set has only a forward clip. Past this angle from
			straight ahead a sprinting keeper plays the backward JOG clip sped
			up instead. See `resolveBaseLocomotion`.

			120 degrees, not 90: between 90 and 120 the keeper is still moving
			mostly sideways, and the lateral jog clips already read correctly
			there. Only genuinely rearward travel needs the substitution.
		]]
		BackwardSprint = {
			BackwardAngleDegrees = 120,
			-- What the sprint would have bought, spent on cadence instead.
			BackwardPlaybackScale = 1.35,
			BackwardMaximumPlaybackRate = 2,
		},
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

	--[[
		THE GOAL CELEBRATION.

		Longer fades than a football action, because nothing is being timed
		against a ball contact -- this plays into a dead-ball celebration window
		where the only thing that matters is that it reads well.

		Deliberately NOT looped and NOT movement-locking: the celebration window
		is already a stoppage, and a player who wants to run off and celebrate
		should be able to.
	]]
	Celebration = {
		Enabled = true,
		FallbackDuration = 2.4,
		PlaybackRate = 1,
		FadeInTime = 0.12,
		FadeOutTime = 0.25,
		ExitBlendTime = 0.25,
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
