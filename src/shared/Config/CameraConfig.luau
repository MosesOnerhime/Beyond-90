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
		-- The floor. The controlled footballer never stops mattering entirely.
		OffBallMinimumPlayerWeight = 0.22,
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
		OnBall = { Distance = 21, Height = 10.5, Pitch = 15, FOV = 68, LookAhead = 15 },
		OffBall = { Distance = 26, Height = 14.5, Pitch = 21, FOV = 74, LookAhead = 22 },
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
CameraConfig.Broadcast2.OffBallMinimumPlayerWeight = 0.18
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
