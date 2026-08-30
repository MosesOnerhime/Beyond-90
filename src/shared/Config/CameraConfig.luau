local CameraConfig = {
	DefaultMode = "Broadcast",

	--[[
		DEFAULT CAMERA, chosen by the player (§21, §64).

		The camera gameplay opens in. The player can still cycle during a match;
		this only decides where they start.

		The attribute is the single source of truth and is set on the player, so
		CameraController reads the same value the Settings screen wrote without
		either of them owning it. There is deliberately no DataStore here -- the
		milestone rules that out, and session persistence is enough until a real
		settings-persistence layer exists.
	]]
	DefaultCameraAttribute = "Beyond90DefaultCamera",
	SelectableModes = {
		{ Id = "Broadcast1", Label = "BROADCAST 1", Detail = "Wide broadcast framing." },
		{ Id = "Broadcast2", Label = "BROADCAST 2", Detail = "Higher, wider tactical view." },
		{ Id = "ThirdPerson", Label = "PRO CAMERA", Detail = "Behind your footballer." },
	},
	FallbackSelectableMode = "Broadcast1",

	Broadcast = {
		ModeName = "Broadcast",
		BroadcastSide = -1,
		Height = 86,
		FocusHeight = 1.6,
		SidelineDistance = 18,
		BaseFOV = 30,
		MinFOV = 29,
		MaxFOV = 34,
		DefaultDistancePresetIndex = 3,
		DistancePresets = {
			{ Name = "0.45x", DistanceScale = 0.45 },
			{ Name = "0.55x", DistanceScale = 0.55 },
			{ Name = "0.65x", DistanceScale = 0.65 },
			{ Name = "0.80x", DistanceScale = 0.8 },
			{ Name = "1.00x", DistanceScale = 1 },
			{ Name = "1.25x", DistanceScale = 1.25 },
			{ Name = "1.50x", DistanceScale = 1.5 },
		},
		--[[
			POSSESSION-AWARE FRAMING (§61, §62).

			The weight is how strongly the camera stays on the CONTROLLED PLAYER;
			the remainder goes to the football. Off the ball this was 0.62 --
			barely different from on the ball -- so the camera stayed glued to a
			footballer who was doing nothing while the actual match happened
			somewhere else on screen. In a game where a player controls one
			footballer, that is the wrong subject.

			On the ball the player and the football are in the same place, so a
			high weight is correct and unchanged. Off the ball the football takes
			priority, and how strongly depends on how far away the play is: near
			the play both still frame comfortably, far from it the football wins.

			It never reaches zero -- see OffBallMinimumPlayerWeight -- because the
			player must still be able to find themselves (§62).
		]]
		PlayerBallWeightControlled = 0.76,
		PlayerBallWeightFree = 0.5,
		-- Distance to the ball at which off-ball framing is fully ball-led.
		OffBallDistanceFull = 90,
		--[[
			The floor. The controlled footballer never stops mattering entirely.

			Measured against the supplied Pro Clubs broadcast capture, 0.22 was
			still too high. In that reference the ACTIVE PLAY is essentially
			centred and the human's own footballer is genuinely indistinguishable
			without the marker over their head -- the camera is covering the
			match, not the individual, which is what makes it read as broadcast
			rather than as a follow camera parked on one player.

			Lowered rather than removed, because AGENTS.md is explicit that the
			player must always be able to find themselves. What remains is enough
			to keep them on screen at the edge of the frame when play is at the
			far end; it is no longer enough to drag the camera off the match.
		]]
		OffBallMinimumPlayerWeight = 0.14,
		-- How far the camera may travel from the player toward the play when
		-- off the ball. Larger than the on-ball clamp, because the whole point
		-- is to reach an action that is somewhere else.
		MaxBallInfluenceOffBall = 34,
		MaxBallInfluence = 9,
		LookAheadDistance = 18,
		LookAheadReferenceSpeed = 30,
		AttackingLookAheadDistance = 6,
		GoalBiasStartProgress = 0,
		GoalBiasFullProgress = 0.52,
		GoalBiasCurveExponent = 0.62,
		AttackingGoalTargetBias = 27,
		AttackingGoalFocusBlend = 0.07,
		BallSeparationZoomScale = 0.18,
		BallSeparationZoomDeadzone = 5,
		OpenPlayFOVBoost = 0,
		GoalAreaFOVReduction = 0,
		LengthFollowStrength = 0.94,
		WidthFollowStrength = 0.86,
		TargetWidthClampScale = 0.84,
		TargetLengthClampScale = 0.6,
		FollowDeadZoneLength = 6.5,
		FollowDeadZoneWidth = 4.5,
		FollowResponsiveness = 3.2,
		CatchupResponsiveness = 5.2,
		CatchupDistance = 7,
		MaxTargetLag = 32,
		FollowDelaySeconds = 1.8,
		TargetHistorySeconds = 2.15,
		SafetyCatchupDistance = 24,
		SafetyCatchupFullDistance = 52,
		SafetyBlendResponsiveness = 2.6,
		SafetyCatchupResponsiveness = 6.5,
		WidthEdgePadding = 18,
		PositionResponsiveness = 8.5,
		PositionMaxSpeed = 72,
		PositionMaxAcceleration = 105,
		FocusResponsiveness = 10,
		FocusMaxSpeed = 62,
		FocusMaxAcceleration = 88,
		OrientationResponsiveness = 12,
		ZoomResponsiveness = 2.5,
		LengthEdgePadding = 24,
		MaxOutsideSidelineDistance = 126,
		FarSideInfieldPadding = 20,
		LengthCameraPadding = 18,
		ObstructionRaycastEnabled = true,
		ObstructionBackoff = 4,
		ObstructionLift = 18,
		ObstructionLiftSteps = 4,
		ObstructionFadeEnabled = true,
		ObstructionProbeLimit = 10,
		ObstructionTransparency = 0.65,
		BroadcastSideFadeEnabled = false,
		BroadcastSideFadeTransparency = 1,
		BroadcastSideFadeInfieldMargin = 8,
		MinimumObstructionDistance = 20,
		AttributeSampleInterval = 0.35,
		JoinIntro = {
			Duration = 2.6,
			SkyHeight = 155,
			StartFOV = 46,
		},
	},

	--[[
		PRO CAMERA.

		Presented to the player as PRO CAMERA and modelled on a Pro Clubs player
		camera: the view of someone who is ONE footballer on the pitch, not the
		manager of a team.

		It used to be `CameraType = Custom` with the humanoid as the subject --
		which is to say, Roblox's stock follow camera. AGENTS.md rules that out in
		as many words ("It should NOT simply be CameraType = Follow, or a basic
		camera attached directly behind the player's avatar"), and it showed: the
		football regularly sat off-screen, there was no anticipation of where play
		was going, and it read as a generic Roblox third-person game rather than
		as football.

		What replaces it is a real camera with football priorities:

		  * ELEVATED and angled down, so the pitch in front of the player is
		    legible instead of a wall of grass at eye level.
		  * FOCUSED AHEAD of the footballer rather than on them, biased toward the
		    football -- which is what keeps the ball in frame without the camera
		    ever leaving the player.
		  * POSSESSION-AWARE. On the ball it tucks in tight and low behind the
		    carrier, which is where control and shooting read best. Off the ball
		    it lifts and pulls back to show the run being made and the space to
		    move into.
		  * SETTLED, not glued. The yaw follows the direction of play rather than
		    the avatar's instantaneous facing, so ordinary dribbling touches do
		    not swing the whole view.
	]]
	ThirdPerson = {
		ModeName = "ThirdPerson",
		-- Retained for the mouse-lock path; the camera no longer uses Roblox's
		-- own zoom, so these only bound the native subject when it is restored.
		MinZoomDistance = 8,
		MaxZoomDistance = 32,
		-- PC Pro Camera drives the yaw straight from mouse movement, with no
		-- right-click drag. L toggles back to a free cursor.
		MouseLockDefault = true,
		MouseLockEnabled = true,

		--[[
			The rig, on the ball and off it.

			On-ball sits closer and lower: the player is doing something with their
			feet and needs to see the ball's relationship to them. Off-ball lifts
			and widens, because the job changes to reading where to run.
		]]
		OnBall = { Distance = 23, Height = 9.5, Pitch = 14, FOV = 70, LookAhead = 9 },
		OffBall = { Distance = 28, Height = 13, Pitch = 19, FOV = 76, LookAhead = 13 },
		-- How fast the rig morphs between those two. Slow enough that winning and
		-- losing the ball is not a lurch.
		RigResponsiveness = 3.2,

		--[[
			How much the football pulls the focus point away from the player.

			Never all the way: this is a camera for a footballer, and losing
			yourself off the bottom of the frame is worse than losing the ball off
			the top. Bounded in studs for the same reason.
		]]
		BallFocusWeightOnBall = 0.3,
		BallFocusWeightOffBall = 0.55,
		MaximumBallFocusOffset = 30,

		--[[
			Yaw. Follows the DIRECTION OF PLAY -- movement while running, the way
			to the ball when standing still -- rather than the avatar's facing, so
			a dribble touch or a body feint does not swing the camera.

			Mouse look overrides it entirely while the cursor is locked; that is
			the point of the mode.
		]]
		YawResponsiveness = 4.5,
		MouseYawSensitivity = 0.0032,
		MousePitchSensitivity = 0.0022,
		MinimumPitchDegrees = 4,
		MaximumPitchDegrees = 46,
		-- Below this speed the footballer is not "going" anywhere, so the yaw
		-- takes its cue from the ball instead of from noise in the velocity.
		MovementYawMinimumSpeed = 5,

		PositionResponsiveness = 7,
		FocusResponsiveness = 8,
		FOVResponsiveness = 4,

		--[[
			Small screens get a wider field and a little more height. A phone in
			landscape has roughly a third of the vertical pixels of a desktop, and
			the same framing there shows the player and almost nothing else.
		]]
		Mobile = {
			FOVBonus = 6,
			HeightScale = 1.1,
			DistanceScale = 1.08,
		},

		--[[
			FRAMING, MEASURED FROM THE REFERENCE.

			Frames pulled from the supplied Pro Camera capture were measured
			rather than eyeballed. In it the controlled footballer sits at roughly
			35% across and 68% down the frame -- low and left of centre, not
			centred -- with the horizon visible in the upper third. That
			composition is doing real work: everything the player is about to run
			into occupies the two thirds of the screen ahead of them, which is why
			the whole penalty area, the goal and half a dozen opponents fit in
			frame at once.

			A camera built on `CFrame.lookAt(position, focus)` cannot produce that
			by itself -- it puts the focus dead centre and is perfectly
			symmetrical, so the footballer can only ever be centred horizontally.
			The offsets below are therefore applied as an explicit angular
			correction derived from the field of view and the aspect ratio, which
			makes the composition CORRECT BY CONSTRUCTION at any FOV or viewport
			rather than approximated with hand-tuned distance and height numbers.

			X below 0.5 puts the footballer left of centre; Y above 0.5 puts them
			low in frame.
		]]
		Framing = {
			--[[
				THE CONTROLLED FOOTBALLER IS CENTRED.

				An earlier pass put them at 35%/68% from measurements of the
				reference capture. That measurement was of the wrong player: the
				controlled footballer in that video is the one carrying the marker
				above his head, and he is CENTRED -- what sat low and left was a
				team-mate.

				Centred is also the right answer independently. This is a camera
				behind one footballer, and an off-centre subject makes turning
				asymmetric: the player has more room to run one way than the
				other, for no reason they can see. The space ahead comes from the
				camera being elevated and pitched down, not from pushing the
				player into a corner.

				Slightly below centre, and only slightly: that is the headroom
				every behind-view football camera has, and it is what puts the
				pitch the player is about to run into in the upper half of the
				frame.
			]]
			SubjectX = 0.5,
			SubjectY = 0.56,
			--[[
				How far the framing may slide to keep the football in shot. This
				is the camera operator's pan: when the ball moves wide or long,
				the footballer gives up screen space rather than the ball leaving
				the frame. Bounded, because the player must always be able to find
				themselves (a footballer pushed off the edge of the screen is a
				worse failure than a ball that briefly is not).
			]]
			MaximumBallShiftX = 0.2,
			MaximumBallShiftY = 0.14,
			--[[
				DEAD ZONE.

				Inside this box around the centre of the frame the ball moves and
				the camera does not. Football is a game of constant small ball
				movement; a camera that answers every one of them is the "camera
				moves too much" complaint. Only when the ball leaves the box does
				the framing start to give.
			]]
			DeadZoneX = 0.3,
			DeadZoneY = 0.26,
			-- How quickly the framing slides. Slow: this is a pan, not a snap.
			ShiftResponsiveness = 2.6,
		},

		--[[
			THE VIEW WIDENS WHEN PLAY IS FAR AWAY.

			The clearest single behaviour in the reference capture: with the ball
			near the footballer the view is tight enough to read a touch, and when
			play is at the other end it opens out to something close to half the
			pitch -- fourteen players and both penalty areas in one frame.

			The existing on-ball / off-ball presets are a two-position switch and
			cannot express that; possession is not the same question as distance.
			So distance to the football scales the rig on top of the preset.
		]]
		Widening = {
			-- Ball distance at which widening begins, and where it is fully
			-- applied. Below the first the rig is exactly the preset.
			StartDistance = 26,
			FullDistance = 105,
			DistanceScale = 1.5,
			HeightScale = 1.65,
			FOVBonus = 12,
			-- Slower than the rig blend: opening out should read as the camera
			-- deciding to, not as a reaction.
			Responsiveness = 1.5,
		},

		--[[
			YAW DEAD ZONE.

			Small changes of direction do not move the camera at all. Dribbling is
			a continuous series of small heading changes, and a yaw that chases
			every one of them is what makes a football camera feel nauseous. Only
			a genuine change of direction turns the view.
		]]
		YawDeadZoneDegrees = 11,

		-- Never let the camera drop into the pitch on a slope or behind a stand.
		MinimumHeightAboveGround = 3.5,
	},

	FirstPerson = {
		ModeName = "FirstPerson",
		Enabled = false,
		FOV = 72,
		MinZoomDistance = 0.5,
		MaxZoomDistance = 0.5,
		EyeForwardOffset = 0.2,
		EyeHeightFallback = 5.35,
		FocusDistance = 100,
		MouseSensitivity = 0.0024,
		GamepadSensitivity = 2.6,
		MinPitchDegrees = -72,
		MaxPitchDegrees = 64,
		ExitRestoreDelay = 0,
		ExitVisibilityRestoreDuration = 1.25,
	},
}

--[[
	AUTHORITATIVE REPOSITION CATCH-UP (§64).

	Applies ONLY for a brief window after the rules teleport the controlled
	footballer -- a restart, a kick-off, a celebration reset. Ordinary Broadcast
	smoothing is untouched, which is the point: the camera was too slow to find
	the player after a set piece, not too slow in general.

	Fast but still smoothed. A hard snap is reserved for a displacement large
	enough that any interpolation would look like a whip pan.
]]
CameraConfig.Reposition = {
	Enabled = true,
	-- How long the boosted catch-up lasts after a reposition.
	DurationSeconds = 0.55,
	-- Multiplier applied to position, focus and follow responsiveness.
	ResponsivenessScale = 5.5,
	-- Multiplier on the acceleration clamp, so the boost is not throttled by it.
	AccelerationScale = 8,
	--[[
		Beyond this displacement, interpolating at all reads as a whip pan across
		the stadium, so the camera cuts instead. Set well above any normal set
		piece: only a kick-off from the far end reaches it.
	]]
	SnapDistance = 140,
}

--[[
	CAMERA SHAKE.

	Impact feedback for things that happen TO the player, and nothing else.
	Every value here is deliberately small: the job is to make contact FEEL like
	contact, not to simulate an earthquake. Presentation only -- see CameraShake
	for why that guarantee matters and how it is kept.

	Note what is absent: shooting. A shot is the player's own deliberate action
	and they are watching the ball leave, so shaking the frame there only costs
	them the flight -- see updateImpactShake in CameraController.

	Magnitudes are in DEGREES of camera rotation at the peak of the impulse. For
	scale, half a degree is about eight pixels of movement at the top of a 1080p
	frame: clearly felt, easily read through.
]]
CameraConfig.Shake = {
	Enabled = true,
	-- Never let overlapping impulses sum without limit; a goalmouth scramble
	-- can fire several within a second.
	MaximumConcurrent = 4,
	-- Ceiling on a caller's intensity scale, so a bad power value cannot turn
	-- a shot into a screen-wide lurch.
	MaximumScale = 1.5,
	-- Roll is the most nauseating axis and the least informative, so it gets a
	-- fraction of what pitch and yaw get.
	RollScale = 0.35,
	Presets = {
		-- A tackle connecting. Shorter and sharper than a shot: a collision is
		-- a single impact rather than a strike with follow-through.
		Tackle = { Magnitude = 0.5, Duration = 0.17, Frequency = 22 },
		-- Woodwork. The hardest single sound in football deserves the hardest
		-- single frame.
		Woodwork = { Magnitude = 0.8, Duration = 0.26, Frequency = 20 },
		-- A goal. Longer and softer -- this one is celebration, not impact.
		Goal = { Magnitude = 0.55, Duration = 0.5, Frequency = 9 },
	},
}

--[[
	SET-PIECE CAMERA.

	A dead ball is the one moment in football where the player is not reading the
	match -- they are AIMING. A penalty, a free kick, a corner, a goal kick or a
	throw-in is a single deliberate strike at a target, and the broadcast camera
	is the wrong tool for it: from a sideline rail eighty studs up, the taker
	cannot judge the line of the shot or the weight of the delivery, because the
	view is not along the ball's path.

	Pro Camera is. It sits behind the footballer looking down the pitch, which is
	exactly the axis the ball is about to travel, so the camera switches to it for
	the duration of the set piece and hands back afterwards.

	Only for the TAKER. A defender in the wall or an attacker making a run has no
	aiming problem to solve and is better served by the wider view they chose.
]]
CameraConfig.SetPiece = {
	Enabled = true,
	-- Which mode a set piece is taken in. Presented as PRO CAMERA.
	Mode = "ThirdPerson",
	--[[
		Which restarts hand the camera over.

		Kick-off is deliberately excluded. It is a square pass from the centre
		spot with no target to pick out, and it is the one restart that is also a
		presentation beat -- the broadcast framing of a kick-off is worth more
		than the marginal aiming help.
	]]
	Restarts = {
		Penalty = true,
		FreeKick = true,
		CornerKick = true,
		GoalKick = true,
		ThrowIn = true,
		Kickoff = false,
	},
	-- How often the restart state is sampled. A set piece is a multi-second
	-- event, so this needs to be responsive, not immediate.
	SampleInterval = 0.12,
}

CameraConfig.Broadcast1 = CameraConfig.Broadcast
CameraConfig.Broadcast2 = table.clone(CameraConfig.Broadcast)
CameraConfig.Broadcast2.ModeName = "Broadcast2"
CameraConfig.Broadcast2.Height = 68
CameraConfig.Broadcast2.SidelineDistance = 10
CameraConfig.Broadcast2.BaseFOV = 34
CameraConfig.Broadcast2.MinFOV = 32
CameraConfig.Broadcast2.MaxFOV = 40
CameraConfig.Broadcast2.PlayerBallWeightControlled = 0.9
CameraConfig.Broadcast2.PlayerBallWeightFree = 0.58
-- Broadcast2 is the wider, more tactical preset, so it is allowed to travel
-- further to the play and to sit slightly less on the individual.
CameraConfig.Broadcast2.OffBallDistanceFull = 80
-- Broadcast2 is the wider, more tactical preset, so it sits even further
-- toward the play than Broadcast1 does.
CameraConfig.Broadcast2.OffBallMinimumPlayerWeight = 0.1
CameraConfig.Broadcast2.MaxBallInfluenceOffBall = 46
CameraConfig.Broadcast2.LookAheadDistance = 22
CameraConfig.Broadcast2.AttackingLookAheadDistance = 10
CameraConfig.Broadcast2.AttackingGoalTargetBias = 36
CameraConfig.Broadcast2.AttackingGoalFocusBlend = 0.2
CameraConfig.Broadcast2.MaxBallInfluence = 16
CameraConfig.Broadcast2.FollowDeadZoneLength = 7
CameraConfig.Broadcast2.FollowDeadZoneWidth = 5
CameraConfig.Broadcast2.FollowDelaySeconds = 1.1
CameraConfig.Broadcast2.TargetHistorySeconds = 1.45
CameraConfig.Broadcast2.FollowResponsiveness = 2.4
CameraConfig.Broadcast2.CatchupResponsiveness = 4
CameraConfig.Broadcast2.PositionResponsiveness = 6
CameraConfig.Broadcast2.PositionMaxSpeed = 58
CameraConfig.Broadcast2.PositionMaxAcceleration = 58
CameraConfig.Broadcast2.FocusResponsiveness = 6.5
CameraConfig.Broadcast2.FocusMaxSpeed = 52
CameraConfig.Broadcast2.FocusMaxAcceleration = 60
CameraConfig.Broadcast2.OrientationResponsiveness = 8
CameraConfig.Broadcast2.ZoomResponsiveness = 1.8
CameraConfig.Broadcast2.SafetyCatchupDistance = 22
CameraConfig.Broadcast2.SafetyCatchupFullDistance = 58
CameraConfig.Broadcast2.SafetyBlendResponsiveness = 1.8
CameraConfig.Broadcast2.SafetyCatchupResponsiveness = 5.5
CameraConfig.Broadcast2.BallSeparationZoomScale = 0.28
CameraConfig.Broadcast2.OpenPlayFOVBoost = 1.5
CameraConfig.Broadcast2.GoalAreaFOVReduction = 0.5

return CameraConfig
