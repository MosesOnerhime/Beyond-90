local PlayerConfig = {
	Movement = {
		--[[
			PACE.

			The pitch is 343 studs long over a 110-metre field, so a stud is
			about 0.32 metres and these convert cleanly to real football speeds:
			16 studs/s is roughly 5.1 m/s (a purposeful jog) and 31 studs/s is
			roughly 10.0 m/s (an elite sprint). The previous 14 and 28 were 4.5
			and 9.0 -- correct for a club footballer and slightly slow for a
			GAME, where the reference titles all sit at or above the top of the
			real range because a match compressed into a few minutes on a
			readable pitch needs to move.

			AI speeds are derived from these two values, so a pace change moves
			both sides of the pitch together rather than quietly making bots
			faster or slower than the humans they play against.
		]]
		BaseSpeed = 16,
		-- Pulled back from 31 on playtest feedback that sprinting ran too fast for
		-- the pitch to read. AIConfig derives its own sprint from this value, so
		-- footballers on both sides move together and nothing gains an advantage.
		SprintSpeed = 27,
		JumpEnabled = true,
		JumpPower = 19,
		JumpHeight = 0,
		AutoRotate = true,
		JumpProfile = {
			GravityCompensation = 0.75,
			MaxAssistDuration = 0.78,
			ExpectedAirTime = 0.76,
			ExpectedPeakHeight = 3.7,
		},
	},

	Locomotion = {
		RawInputDeadzone = 0.05,
		StopSpeed = 0.15,
		--[[
			STOPPING WAS THE REAL REASON IT FELT SLOW.

			These are seconds to traverse the reference speed, so the old 2.2
			meant a footballer at full sprint took over two seconds and around 24
			studs -- nearly eight metres -- to come to a halt. That is skating,
			and AGENTS.md rules it out in as many words: "stopping should produce
			visible but short deceleration rather than an instantaneous freeze or
			long skating motion".

			It is also the single thing most responsible for the game feeling
			sluggish, more than top speed ever was. Every stop, every check, every
			change of pace and every arrival at the ball was spent sliding. A
			player who cannot stop cannot feel fast, however quickly they run.

			At 0.95 a sprint stops in roughly 13 studs -- about four metres, which
			is what a real footballer needs and what the reference games show.
			Deceleration is still visible and still has weight; it simply no
			longer outlasts the moment that caused it.
		]]
		AccelerationTime = 0.12,
		DecelerationTime = 0.85,
		SprintAccelerationTime = 0.28,
		SprintDecelerationTime = 0.95,
		TurnAccelerationTime = 0.18,
		ReverseAccelerationTime = 0.28,
		TurnSpeedLossAt90 = 0.18,
		TurnSpeedLossAt180 = 0.58,
		PossessionTurn = {
			Enabled = true,
			MinimumPlayerSpeed = 4,
			ImmediateAngleDegrees = 25,
			MajorAngleDegrees = 60,
			SevereAngleDegrees = 120,
			MinimumPreparationSeconds = 0.08,
			--[[
				CEILINGS ON HOW LONG A TURN MAY WAIT FOR A TOUCH.

				These are fallbacks, not typical waits -- a turn commits as soon
				as the next contact happens, and usually does. But a ceiling is
				still a ceiling: at 0.65 seconds a sprint reversal that missed its
				touch window left the player pointing the old way for two thirds
				of a second, which reads as the input having been ignored.

				AGENTS.md is explicit that "a 180-degree reversal should not place
				the player into a long slow-motion state", so every band is pulled
				in. The preparation minimum is untouched: some preparation is what
				makes a turn with the ball look like football rather than a pivot.
			]]
			SmallCorrectionMaximumWaitSeconds = 0.16,
			JogModerateMaximumWaitSeconds = 0.26,
			SprintModerateMaximumWaitSeconds = 0.32,
			JogMaximumWaitSeconds = 0.36,
			SprintMaximumWaitSeconds = 0.44,
			ContactLeadDistance = 3.8,
			ContactRelativeSpeed = 10,
		},
		DiagnosticInterval = 0.5,
		ActionMovement = {
			Pass = {
				BrakeTime = 0.13,
				BrakeDuration = 0.16,
				LockDuration = 0.26,
				ExitDuration = 0.1,
			},
			ReceivePass = {
				BrakeTime = 0.12,
				BrakeDuration = 0.14,
				LockDuration = 0.24,
				ExitDuration = 0.1,
			},
			Shoot = {
				BrakeTime = 0.11,
				BrakeDuration = 0.14,
				LockDuration = 0.3,
				ExitDuration = 0.12,
			},
		},
		ReceptionAssist = {
			Enabled = true,
			MaxDistance = 42,
			StopDistance = 2.6,
			BrakeDistance = 8,
			MaxMoveMagnitude = 0.9,
			ManualBlendStart = 0.35,
			ManualOverrideMagnitude = 0.9,
			ExpiryGraceTime = 2.2,
			DiagnosticInterval = 0.75,
			--[[
				HOW MUCH THE ASSIST TRUSTS THE BALL OVER THE PLAN.

				The assist steers toward the pass's PLANNED target, nudged toward
				where the ball is actually going by LiveTargetWeight. A fixed 0.55
				was wrong at both ends of the flight.

				Early, the plan is the better guide: it is where the pass was
				aimed, and the ball has not curved or bounced yet. Late, the plan
				is a fiction and the ball is the truth -- measured, a pass
				predicted to arrive in 1.16s actually took 1.95s:

					[PassArrival] predictedETA=1.16 measuredETA=1.95

				With a fixed weight the receiver settled next to a point the ball
				never reached and stood there while it rolled past. That is the
				other half of "sloppy".

				So trust ramps with proximity: the plan while the ball is far, the
				ball itself once it is inside FullTrustDistance. The receiver ends
				up where the ball is rather than where it was supposed to be.
			]]
			LiveTargetWeight = 0.55,
			LiveTargetFullTrustDistance = 18,
			MaxLiveTargetCorrection = 24,
			FacingResponsiveness = 12,
			FacingMinimumBallSpeed = 4,
			FacingRelockAngle = 35,
			PostContactFacingHold = 0.32,
			FacingDiagnosticInterval = 0.75,
		},
		LooseBallAssist = {
			Enabled = true,
			ActivationDistance = 10.5,
			ContactDistance = 2.55,
			PredictionTime = 0.16,
			MaximumMoveMagnitude = 0.92,
			ManualBlendStart = 0.45,
			ManualOverrideMagnitude = 0.95,
		},
	},

	Input = {
		InputFolderName = "Beyond90Inputs",
		-- How long a movement key must be held with no InputAction report before
		-- the UserInputService fallback takes over.
		InputActionWatchdogSeconds = 0.4,
		PlayContextName = "Beyond90PlayContext",
		MoveActionName = "Beyond90Move",
		SprintActionName = "Beyond90Sprint",
		JumpActionName = "Beyond90Jump",
		CameraToggleActionName = "Beyond90CameraToggle",
		PassActionName = "Beyond90Pass",
		ThroughPassActionName = "Beyond90ThroughPass",
		KnockOnActionName = "Beyond90KnockOn",
		ShootActionName = "Beyond90Shoot",
		TackleActionName = "Beyond90Tackle",
		CameraToggleKey = Enum.KeyCode.C,
		PassKey = Enum.KeyCode.E,
		ThroughPassKey = Enum.KeyCode.Q,
		KnockOnKey = Enum.KeyCode.R,
		ShootKey = Enum.KeyCode.F,
		-- Out of possession this is the defensive challenge. It does not collide
		-- with Pass/Through/Shoot/KnockOn/Sprint or the camera keys.
		TackleKey = Enum.KeyCode.V,
		CameraLockKey = Enum.KeyCode.L,
		JumpKey = Enum.KeyCode.Space,
		SprintRemoteName = "MovementSprintRequested",
		AutoSprintDefaultEnabled = false,
		AutoSprintThreshold = 0.9,
		SprintTouchButtonPosition = UDim2.new(1, -92, 1, -148),
	},

	Appearance = {
		StandardizeEnabled = true,
		RequiredRigType = "R15",
		ApplyDescriptionStandardization = false,

		--[[
			EVERY FOOTBALLER IS THE SAME HEIGHT. MEASURED, NOT ASSUMED.

			This was false, on the reasoning that height is the platform's to
			decide and a script measuring the result overrides the Avatar Settings.
			That reasoning held while every footballer came from the same
			StarterCharacter. It stopped holding the moment players started
			wearing their own avatars, because a human is now built by
			ApplyDescription rebuilding the rig while an NPC is a clone of a model
			someone authored -- two different sources that were never going to
			agree. Measured, same match:

				human     height 7.46  hipHeight 4.064
				AI / ref  height 8.27  hipHeight 3.780

			Three quarters of a stud, and the AI's hips two thirds of a stud
			lower. Control distance, tackle reach, shot contact radius,
			interception reach and body exclusion are all measured in studs from
			the root, so those two bodies were playing under measurably different
			rules -- a competitive-integrity problem, not a cosmetic one
			(AGENTS.md §41, §49).

			Standardising the FRAME (scales pinned to 1, body package cleared) is
			done first and gets the proportions honest, but it cannot fix this on
			its own: the StarterCharacter rig's part sizes are baked into the
			model and survive ApplyDescription. So the last step is explicit --
			measure the body and scale it to one number.

			The number is the measured height of the standard frame a human
			already builds to, so a human scales by 1.00 and nothing about the
			existing grounding, shot or camera calibration moves. It is the AI and
			the officials that come down to meet them.
		]]
		ScaleToCanonicalHeight = true,
		TargetHeightStuds = 7.46,
		HeightScale = 1,
		WidthScale = 1,
		DepthScale = 1,
		HeadScale = 1,
		BodyTypeScale = 1,
		ProportionScale = 1,
		RemoveAnimationPacks = false,
		RemoveBodyPackageParts = false,
		IntendedHeightStuds = 6,
		HeightTestOptionsStuds = { 6, 6.25, 6.5 },

		--[[
			HEIGHT IS THE PLATFORM'S TO DECIDE, NOT THIS FILE'S.

			Luau was forcing every footballer to 8.27 studs by measuring the rig
			after it spawned and calling ScaleTo on the difference. That is the
			wrong layer to own a body in. Roblox already has one place where an
			experience declares what its avatars look like -- the Avatar Settings
			the project owner configures -- and a script that measures the result
			and overrides it means the setting no longer means anything.

			MEASURED, in this place, at the standardised scales below: the R15
			build Roblox actually produces is 6.088 studs tall (root part 2.0,
			hip height 2.642). The forced target was inflating every footballer by
			roughly 36%, which is also why the pitch, the goals and the ball have
			all read slightly small next to the players.

			WHAT IS DELIBERATELY KEPT is the STANDARDISED COMPETITIVE BUILD. Every
			scale immediately above stays pinned to 1, so a player whose own
			avatar is unusually tall, short, wide or narrow still plays as the
			same physical footballer as everyone else. That is not cosmetic
			enforcement -- control distance, tackle reach, shot contact radius,
			interception reach and body exclusion are all measured in studs from
			the root part, so a taller collider would be a genuine competitive
			advantage. Appearance is the player's; the frame is everyone's.
		]]
		DevelopmentFootballerScaleEnabled = false,
		DevelopmentFootballerTargetHeightStuds = 8.27,

		--[[
			PLAYER IDENTITY.

			Beyond 90's fantasy is that YOU are one footballer on the pitch, and
			until now every footballer was literally the same body: the place has a
			StarterPlayer.StarterCharacter, so every player spawned as that model
			regardless of their own avatar. There was no identity to have.

			The default is now the player's OWN Roblox avatar. Their hair, their
			colours, their accessories -- applied onto the same rig, so nothing
			downstream has to care which body it is looking at.

			What is deliberately NOT inherited is SIZE. Every footballer is scaled
			to the same canonical height afterwards, because height in this game is
			not cosmetic: the pitch, the goals, the ball, the dribble lead
			distances, the camera framing and the grounding calibration are all
			tuned around one footballer height, and a player who joined with a
			taller avatar would get a longer stride and a wider reach. That is a
			competitive advantage bought in the avatar shop, which section 41
			rules out in as many words. So: your face, everyone's frame.

			`Beyond90Avatar` keeps the uniform look for players who prefer it, and
			is what a future kit / customisation system would extend.
		]]
		Identity = {
			Enabled = true,
			Sources = { RobloxAvatar = "RobloxAvatar", Beyond90Avatar = "Beyond90Avatar" },
			--[[
				YOU PLAY AS YOURSELF BY DEFAULT.

				`Beyond90Avatar` is the StarterCharacter -- the kit, and what every
				AI footballer and official wears. `RobloxAvatar` is the player's
				own avatar, their own clothes included.

				This was briefly defaulted to the kit, on the reasoning that a
				stadium full of unrelated avatars reads as a lobby rather than a
				team. That is a real concern and it is not this setting's to
				solve: a player's footballer is THEM, in the menu and on the
				pitch, and a team identity should come from kits worn over an
				avatar rather than from replacing the player with a mannequin.

				The kit remains one setting away, in Settings -> Footballer, and
				remains what every non-player footballer wears.
			]]
			Default = "RobloxAvatar",
			-- Stored on the player so any system can read the choice; session
			-- scoped, because persistence is a later milestone.
			AttributeName = "Beyond90AvatarSource",
			-- A web call. Bounded, and a failure falls back to the uniform body
			-- rather than blocking the spawn.
			FetchTimeoutSeconds = 6,
			RemoteName = "AvatarSourceRequest",
		},
		Grounding = {
			TargetFootClearanceStuds = 0.13,
			VisualSoleOffsetStuds = 0.035,
			--[[
				THE RIG DECIDES ITS OWN HIP HEIGHT. A CONSTANT CANNOT.

				This was a fixed 4.31, measured against the Beyond 90 kit back when
				every footballer on the pitch WAS the kit. That stopped being true
				the moment players started spawning as their own avatars: a Roblox
				avatar has its own leg length, and forcing its hip to the kit's
				number hangs it in the air. Measured, a player wearing their own
				avatar:

					phase=calibrated       rootY=4.684  footBottom=0.535  err=-0.095
					phase=late-calibrated  rootY=4.684  hipAdjustment=1.275
					phase=final-validation rootY=5.959  footBottom=1.892  err=+1.099

				-- feet correctly on the grass, then lifted 1.275 studs off it.
				That number is not a coincidence: it is exactly
				4.31 minus the avatar rig's own hip height, applied by

					nextHipHeight = math.max(minimumHipHeight, hipHeight + adjustment)

				with the geometry correction switched off, so the minimum was the
				only thing acting.

				The correction that belongs here already existed and was disabled:
				measure where the feet actually are, and move the hip by the
				difference. That is rig-agnostic by construction -- it works for
				the kit, for a tall avatar and for a short one, without anybody
				re-deriving a constant every time a body changes.

				The minimum stays as a SAFETY FLOOR only, far below any real rig,
				to catch a degenerate HipHeight rather than to set a good one.
			]]
			GeometryHipHeightCorrectionEnabled = true,
			AllowDownwardHipHeightCorrection = true,
			MinimumHipHeightStuds = 2,
			FootGroundToleranceStuds = 0.03,
			FloorProbeDistanceStuds = 20,
			MaxHipHeightCorrectionStuds = 0.55,
			ValidationCanAdjust = true,
			MaxLateHipHeightCorrectionStuds = 0.25,
			CalibrationDelaySeconds = 2.5,
			SettleRetryDelaySeconds = 1.5,
			MaxSettleRetries = 1,
			ValidationDelaySeconds = 5.5,
			FinalValidationDelaySeconds = 7.5,
			DiagnosticSampleSeconds = 2.5,
			DiagnosticMinSamples = 30,
			ContactFootVerticalVelocityThreshold = 1.5,
			DiagnosticFloatToleranceStuds = 0.18,
		},
	},

	Presentation = {
		PlayerIndicator = {
			Enabled = true,
			BaseRadius = 3.3,
			PossessionRadius = 3.8,
			SprintRadius = 4.2,
			SprintPossessionRadius = 4.55,
			MaximumRadius = 4.65,
			PossessionLeadPadding = 0,
			RadiusResponsiveness = 6,
			SegmentCount = 56,
			SegmentThickness = 0.12,
			SegmentHeight = 0.04,
			GroundOffset = 0.045,
			NormalColor = Color3.fromRGB(230, 224, 255),
			SprintColor = Color3.fromRGB(57, 177, 240),
			ColorResponsiveness = 10,
			Transparency = 0.2,
			GlowColor = Color3.fromRGB(137, 99, 255),
			GlowThickness = 0.32,
			GlowTransparency = 0.76,
			OverheadArrowColor = Color3.fromRGB(68, 78, 255),
			OverheadArrowOutlineColor = Color3.fromRGB(9, 11, 30),
			OverheadArrowHeight = 1.55,
			OverheadArrowWorldSize = 1.15,
			OverheadArrowWorldHeight = 0.92,
			OverheadArrowStripCount = 10,
			OverheadArrowOutlineThickness = 0.065,
			ArrowWidth = 1.15,
			ArrowLength = 1.5,
			ArrowHeight = 0.07,
			ArrowStripCount = 10,
			ArrowGap = 0.55,
			ArrowResponsiveness = 18,
			ArrowFadeResponsiveness = 14,
			ArrowShowIntentThreshold = 0.08,
			ArrowShowSpeedThreshold = 0.8,
			IntentAnticipationSeconds = 0.25,
			FloorProbeDistance = 20,
		},
	},

	GameplayProfile = {
		CanonicalPlayerHeight = 6,
		CanonicalBodyRadius = 1.04,
		CanonicalFootContactHeight = 0.25,
		CanonicalFootForwardOffset = 1.25,
	},

	--[[
		KEEPING BODIES OUT OF EACH OTHER.

		See `FootballerSeparation`. Footballers no longer collide with one
		another -- that collision was what they were climbing -- so this is what
		stops them merging instead.
	]]
	Separation = {
		Enabled = true,

		--[[
			Where avoidance starts, in studs between root parts.

			A footballer is about 2.1 studs across the shoulders
			(CanonicalBodyRadius 1.04). Three studs therefore leaves most of a
			body's width of daylight at the point the push begins and reaches
			full strength only when they are genuinely touching -- close enough
			to still look like a contested ball, far enough not to be walked
			through.
		]]
		--[[
			Raised from 3. Footballers collide again (see CollisionGroupConfig),
			so separation is now the thing that has to stop them REACHING the
			collision rather than a substitute for it -- it has to start pushing
			before shoulders meet, not as they touch.
		]]
		Radius = 4.2,
		-- Ceiling on the combined push, so being surrounded does not eject you.
		MaximumPush = 1,
		--[[
			How much of the push is mixed into the movement direction.

			Well under 1: separation must bend a run, never redirect it. At 0.6 a
			footballer running straight at an opponent leaves at roughly 30
			degrees off their line -- a sidestep, not a swerve -- and anyone not
			being crowded is unaffected entirely.

			Raised with the radius, for the same reason: it now has to turn a
			body away from a collision rather than tidy up a near miss.
		]]
		SteeringWeight = 0.6,
	},
}

return PlayerConfig
