local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared.Config.AnimationConfig)
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local Controllers = script.Parent
local MovementController = require(Controllers:WaitForChild("MovementController"))

local AnimationController = {}

local localPlayer = Players.LocalPlayer
local idleConfig = AnimationConfig.Locomotion.Idle
local jogConfig = AnimationConfig.Locomotion.Jog
local groundingConfig = PlayerConfig.Appearance.Grounding or {}
local idleAnimationId = AnimationConfig.Assets.Locomotion.OffBall.Idle
local offBallJogAnimationId = AnimationConfig.Assets.Locomotion.OffBall.JogForward

local initialized = false
local currentCharacter: Model? = nil
local currentHumanoid: Humanoid? = nil
local currentAnimator: Animator? = nil
local currentRootPart: BasePart? = nil
local renderConnection: RBXScriptConnection? = nil
local appConnections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local cachedBall: BasePart? = nil
local currentState = "Default"
local currentPlaybackRate = 0
local currentBasePlaybackRate = 0
local jogPlaybackMultiplier = jogConfig.JogPlaybackMultiplier
local sprintFallbackActive = false
local warnedHighPlayback = false
local activeTracks = {}
local disabledAnimateScripts = {}
local groundingSamples = {}
local previousFootSample = nil
local diagnostics = {
	State = "Default",
	HorizontalSpeed = 0,
	BasePlaybackRate = 0,
	JogPlaybackMultiplier = jogConfig.JogPlaybackMultiplier,
	FinalPlaybackRate = 0,
	HasBall = false,
	SprintRequested = false,
	TrackPlaying = false,
	TrackLoaded = false,
	Asset = idleAnimationId,
	IsPlaceholder = false,
	IdleLength = 0,
	IdleWeight = 0,
	JogLength = 0,
	JogWeight = 0,
}

local function log(message: string)
	if AnimationConfig.DebugEnabled then
		print(string.format("%s[Client][Animation] %s", GameConfig.LogPrefix, message))
	end
end

local function warnLog(message: string)
	warn(string.format("%s[Client][Animation] %s", GameConfig.LogPrefix, message))
end

local function groundingLog(message: string)
	if AnimationConfig.DebugEnabled then
		print(string.format("%s[Client][Grounding] %s", GameConfig.LogPrefix, message))
	end
end

local function createGroundingBucket()
	return {
		StartedAt = 0,
		Count = 0,
		Min = math.huge,
		Max = -math.huge,
		Sum = 0,
		Reported = false,
	}
end

local function resetGroundingDiagnostics()
	table.clear(groundingSamples)
	groundingSamples.Idle = createGroundingBucket()
	groundingSamples.Jog = createGroundingBucket()
	previousFootSample = nil
end

local function getGroundingStateKey(state: string): string?
	if state == "Idle" then
		return "Idle"
	end

	if state == "OffBallJog" or state == "BallJog" or state == "BallJogPlaceholder" then
		return "Jog"
	end

	return nil
end

local function getCharacterGroundY(character: Model): number?
	local groundY = character:GetAttribute("Beyond90PitchGroundY")

	if typeof(groundY) == "number" then
		return groundY
	end

	return nil
end

local function getFootBottomY(character: Model, footName: string): number?
	local foot = character:FindFirstChild(footName)

	if not foot or not foot:IsA("BasePart") then
		return nil
	end

	return foot.Position.Y - foot.Size.Y / 2
end

local function chooseContactClearance(
	leftClearance: number?,
	rightClearance: number?,
	leftVelocityY: number,
	rightVelocityY: number
): number?
	if leftClearance and not rightClearance then
		return leftClearance
	end

	if rightClearance and not leftClearance then
		return rightClearance
	end

	if not leftClearance or not rightClearance then
		return nil
	end

	local velocityThreshold = groundingConfig.ContactFootVerticalVelocityThreshold or 1.5
	local leftStable = math.abs(leftVelocityY) <= velocityThreshold
	local rightStable = math.abs(rightVelocityY) <= velocityThreshold
	local targetClearance = groundingConfig.TargetFootClearanceStuds or 0

	if leftStable and not rightStable and leftClearance <= rightClearance + targetClearance then
		return leftClearance
	end

	if rightStable and not leftStable and rightClearance <= leftClearance + targetClearance then
		return rightClearance
	end

	if leftStable and rightStable then
		if math.abs(leftClearance - targetClearance) <= math.abs(rightClearance - targetClearance) then
			return leftClearance
		end

		return rightClearance
	end

	return math.min(leftClearance, rightClearance)
end

local function writeGroundingSummaryAttributes(stateKey: string, minClearance: number, averageClearance: number, maxClearance: number)
	local prefix = if stateKey == "Idle" then "Beyond90GroundingIdle" else "Beyond90GroundingJog"

	localPlayer:SetAttribute(prefix .. "MinContactClearance", minClearance)
	localPlayer:SetAttribute(prefix .. "AverageContactClearance", averageClearance)
	localPlayer:SetAttribute(prefix .. "MaxContactClearance", maxClearance)
	localPlayer:SetAttribute("Beyond90GroundingTargetClearance", groundingConfig.TargetFootClearanceStuds or 0)
end

local function reportGroundingBucket(stateKey: string, bucket)
	local character = currentCharacter
	local humanoid = currentHumanoid

	if not character or not humanoid or bucket.Count <= 0 then
		return
	end

	local targetClearance = groundingConfig.TargetFootClearanceStuds or 0
	local averageClearance = bucket.Sum / bucket.Count
	local floatTolerance = groundingConfig.DiagnosticFloatToleranceStuds or 0.18
	local result = "accepted"

	if bucket.Min < -0.02 then
		result = "penetrating"
	elseif averageClearance > targetClearance + floatTolerance then
		result = "floating"
	end

	writeGroundingSummaryAttributes(stateKey, bucket.Min, averageClearance, bucket.Max)

	groundingLog(string.format(
		"state=%s height=%.2f hipHeight=%.3f targetClearance=%.3f contactMin=%.3f contactAvg=%.3f contactMax=%.3f samples=%d result=%s",
		string.lower(stateKey),
		character:GetAttribute("Beyond90CharacterHeight") or character:GetAttribute("Beyond90MeasuredBodyHeightStuds") or -1,
		humanoid.HipHeight,
		targetClearance,
		bucket.Min,
		averageClearance,
		bucket.Max,
		bucket.Count,
		result
	))
end

local function sampleGrounding(state: string)
	local stateKey = getGroundingStateKey(state)
	local character = currentCharacter
	local humanoid = currentHumanoid

	if not stateKey or not character or not humanoid then
		return
	end

	local groundY = getCharacterGroundY(character)

	if not groundY then
		return
	end

	local leftBottomY = getFootBottomY(character, "LeftFoot")
	local rightBottomY = getFootBottomY(character, "RightFoot")

	if not leftBottomY and not rightBottomY then
		return
	end

	local now = os.clock()
	local previous = previousFootSample
	previousFootSample = {
		Time = now,
		LeftBottomY = leftBottomY,
		RightBottomY = rightBottomY,
	}

	if not previous then
		return
	end

	local dt = math.max(now - previous.Time, 1 / 240)
	local leftVelocityY = if leftBottomY and previous.LeftBottomY then (leftBottomY - previous.LeftBottomY) / dt else math.huge
	local rightVelocityY = if rightBottomY and previous.RightBottomY then (rightBottomY - previous.RightBottomY) / dt else math.huge
	local leftClearance = if leftBottomY then leftBottomY - groundY else nil
	local rightClearance = if rightBottomY then rightBottomY - groundY else nil
	local contactClearance = chooseContactClearance(leftClearance, rightClearance, leftVelocityY, rightVelocityY)

	if not contactClearance then
		return
	end

	local bucket = groundingSamples[stateKey]

	if not bucket or bucket.Reported then
		return
	end

	if bucket.Count == 0 then
		bucket.StartedAt = now
	end

	bucket.Count += 1
	bucket.Sum += contactClearance
	bucket.Min = math.min(bucket.Min, contactClearance)
	bucket.Max = math.max(bucket.Max, contactClearance)

	local sampleSeconds = groundingConfig.DiagnosticSampleSeconds or 2.5
	local minSamples = groundingConfig.DiagnosticMinSamples or 30

	if bucket.Count >= minSamples and now - bucket.StartedAt >= sampleSeconds then
		bucket.Reported = true
		reportGroundingBucket(stateKey, bucket)
	end
end

local function getHorizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getFootball(): BasePart?
	if cachedBall and cachedBall.Parent then
		return cachedBall
	end

	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = rootFolder and rootFolder:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)

	if ball and ball:IsA("BasePart") then
		cachedBall = ball
		return ball
	end

	cachedBall = nil
	return nil
end

local function hasLocalPossession(): boolean
	local ball = getFootball()

	return ball ~= nil
		and ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
end

local function disconnectCharacterConnections()
	for _, connection in characterConnections do
		connection:Disconnect()
	end

	table.clear(characterConnections)
end

local function stopTrack(slot: string, fadeTime: number?)
	local record = activeTracks[slot]
	local track = record and record.Track

	if track and track.IsPlaying then
		track:Stop(fadeTime or jogConfig.FadeOutTime)
	end
end

local function stopAllCustomTracks(fadeTime: number?)
	stopTrack("Idle", fadeTime or idleConfig.FadeOutTime)
	stopTrack("Jog", fadeTime or jogConfig.FadeOutTime)
end

local function destroyTracks()
	stopAllCustomTracks(0)

	for _, record in activeTracks do
		if record.Track then
			record.Track:Destroy()
		end

		if record.Animation then
			record.Animation:Destroy()
		end
	end

	table.clear(activeTracks)
end

local function disableBundledAnimateScripts(character: Model)
	if not AnimationConfig.Authority.DisableDefaultAnimate then
		return
	end

	table.clear(disabledAnimateScripts)

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("LocalScript") and descendant.Name == "Animate" then
			descendant.Enabled = false
			table.insert(disabledAnimateScripts, descendant)
		end
	end

	if #disabledAnimateScripts > 0 then
		log(string.format("Disabled %d bundled Animate script(s); Beyond90 AnimationController is animation authority.", #disabledAnimateScripts))
	end
end

local function getBallJogAnimationId(): string?
	local ballJog = AnimationConfig.Assets.Locomotion.Ball.JogForward

	if typeof(ballJog) == "string" and ballJog ~= "" then
		return ballJog
	end

	return nil
end

local function getDesiredJogPresentation(hasBall: boolean): (string, string, string, boolean)
	if hasBall then
		local ballJogAnimationId = getBallJogAnimationId()

		if ballJogAnimationId then
			return "BallJog", ballJogAnimationId, "B90_LOC_Ball_Jog_F", false
		end

		return "BallJogPlaceholder", offBallJogAnimationId, "B90_LOC_OffBall_Jog_F", true
	end

	return "OffBallJog", offBallJogAnimationId, "B90_LOC_OffBall_Jog_F", false
end

local function setPlayerDiagnostics(
	state: string,
	speed: number,
	basePlaybackRate: number,
	finalPlaybackRate: number,
	hasBall: boolean,
	sprintRequested: boolean,
	localForward: number,
	localRight: number,
	assetId: string,
	isPlaceholder: boolean
)
	local idleRecord = activeTracks.Idle
	local jogRecord = activeTracks.Jog
	local idlePlaying = idleRecord and idleRecord.Track and idleRecord.Track.IsPlaying
	local jogPlaying = jogRecord and jogRecord.Track and jogRecord.Track.IsPlaying
	local idleLoaded = idleRecord and idleRecord.Track and idleRecord.Track.Length > 0
	local jogLoaded = jogRecord and jogRecord.Track and jogRecord.Track.Length > 0
	local idleLength = if idleRecord and idleRecord.Track then idleRecord.Track.Length else 0
	local jogLength = if jogRecord and jogRecord.Track then jogRecord.Track.Length else 0
	local idleWeight = if idleRecord and idleRecord.Track then idleRecord.Track.WeightCurrent else 0
	local jogWeight = if jogRecord and jogRecord.Track then jogRecord.Track.WeightCurrent else 0

	diagnostics.State = state
	diagnostics.HorizontalSpeed = speed
	diagnostics.BasePlaybackRate = basePlaybackRate
	diagnostics.JogPlaybackMultiplier = jogPlaybackMultiplier
	diagnostics.FinalPlaybackRate = finalPlaybackRate
	diagnostics.HasBall = hasBall
	diagnostics.SprintRequested = sprintRequested
	diagnostics.TrackPlaying = idlePlaying or jogPlaying or false
	diagnostics.TrackLoaded = idleLoaded or jogLoaded or false
	diagnostics.Asset = assetId
	diagnostics.IsPlaceholder = isPlaceholder
	diagnostics.IdleLength = idleLength
	diagnostics.IdleWeight = idleWeight
	diagnostics.JogLength = jogLength
	diagnostics.JogWeight = jogWeight

	localPlayer:SetAttribute("Beyond90AnimationState", state)
	localPlayer:SetAttribute("Beyond90AnimationSpeed", speed)
	localPlayer:SetAttribute("Beyond90AnimationPlaybackRate", finalPlaybackRate)
	localPlayer:SetAttribute("Beyond90AnimationBasePlaybackRate", basePlaybackRate)
	localPlayer:SetAttribute("Beyond90JogPlaybackMultiplier", jogPlaybackMultiplier)
	localPlayer:SetAttribute("Beyond90AnimationAsset", assetId)
	localPlayer:SetAttribute("Beyond90AnimationTrackPlaying", diagnostics.TrackPlaying)
	localPlayer:SetAttribute("Beyond90AnimationTrackLoaded", diagnostics.TrackLoaded)
	localPlayer:SetAttribute("Beyond90AnimationIdleLength", idleLength)
	localPlayer:SetAttribute("Beyond90AnimationIdleWeight", idleWeight)
	localPlayer:SetAttribute("Beyond90AnimationJogLength", jogLength)
	localPlayer:SetAttribute("Beyond90AnimationJogWeight", jogWeight)
	localPlayer:SetAttribute("Beyond90AnimationHasBall", hasBall)
	localPlayer:SetAttribute("Beyond90AnimationSprintRequested", sprintRequested)
	localPlayer:SetAttribute("Beyond90AnimationIsPlaceholder", isPlaceholder)
	localPlayer:SetAttribute("Beyond90AnimationLocalForward", localForward)
	localPlayer:SetAttribute("Beyond90AnimationLocalRight", localRight)
	localPlayer:SetAttribute("Beyond90AnimationAuthority", "Beyond90")
	localPlayer:SetAttribute(
		"Beyond90DefaultAnimateDisabled",
		AnimationConfig.Authority.DisableDefaultAnimate
			and (#disabledAnimateScripts > 0 or (currentCharacter ~= nil and currentCharacter:FindFirstChild("Animate") == nil))
	)
end

local function setState(
	state: string,
	speed: number,
	basePlaybackRate: number,
	finalPlaybackRate: number,
	hasBall: boolean,
	sprintRequested: boolean,
	localForward: number,
	localRight: number,
	assetId: string,
	isPlaceholder: boolean
)
	if state == currentState then
		setPlayerDiagnostics(
			state,
			speed,
			basePlaybackRate,
			finalPlaybackRate,
			hasBall,
			sprintRequested,
			localForward,
			localRight,
			assetId,
			isPlaceholder
		)
		sampleGrounding(state)
		return
	end

	currentState = state
	setPlayerDiagnostics(
		state,
		speed,
		basePlaybackRate,
		finalPlaybackRate,
		hasBall,
		sprintRequested,
		localForward,
		localRight,
		assetId,
		isPlaceholder
	)
	sampleGrounding(state)

	if state == "Idle" then
		log(string.format("State -> Idle speed=%.1f hasBall=%s", speed, tostring(hasBall)))
	elseif state == "OffBallJog" or state == "BallJog" or state == "BallJogPlaceholder" then
		log(string.format(
			"State -> %s speed=%.1f basePlayback=%.2f multiplier=%.2f finalPlayback=%.2f hasBall=%s placeholder=%s forward=%.2f right=%.2f",
			state,
			speed,
			basePlaybackRate,
			jogPlaybackMultiplier,
			finalPlaybackRate,
			tostring(hasBall),
			tostring(isPlaceholder),
			localForward,
			localRight
		))
	elseif state == "SprintFallback" then
		log(string.format("State -> SprintFallback speed=%.1f sprintRequested=%s", speed, tostring(sprintRequested)))
	elseif state == "AirborneFallback" then
		log("State -> AirborneFallback")
	else
		log("State -> Default")
	end
end

local function ensureAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")

	if animator then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function loadTrack(slot: string, animator: Animator, animationId: string, trackName: string, priority: Enum.AnimationPriority)
	local record = activeTracks[slot]

	if record and record.AnimationId == animationId and record.Track then
		return
	end

	stopTrack(slot, 0)

	if record then
		if record.Track then
			record.Track:Destroy()
		end

		if record.Animation then
			record.Animation:Destroy()
		end
	end

	local animation = Instance.new("Animation")
	animation.Name = trackName
	animation.AnimationId = animationId

	local ok, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not result then
		warnLog(string.format("Could not load %s %s: %s", trackName, animationId, tostring(result)))
		return
	end

	local track = result :: AnimationTrack
	track.Name = trackName
	track.Looped = true
	track.Priority = priority

	activeTracks[slot] = {
		Animation = animation,
		AnimationId = animationId,
		Track = track,
	}

	log(string.format("Loaded %s asset=%s priority=%s", trackName, animationId, track.Priority.Name))

	task.delay(2, function()
		local latestRecord = activeTracks[slot]

		if latestRecord and latestRecord.Track == track and track.Length <= 0 then
			warnLog(string.format(
				"%s asset=%s still reports length=0 after load; verify animation ownership, permissions, and uploaded rig compatibility.",
				trackName,
				animationId
			))
		end
	end)
end

local function isAirborne(humanoid: Humanoid): boolean
	local state = humanoid:GetState()

	return state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Climbing
end

local function isCustomTrack(track: AnimationTrack): boolean
	for _, record in activeTracks do
		if record.Track == track then
			return true
		end
	end

	return false
end

local function shouldSuppressPriority(priority: Enum.AnimationPriority): boolean
	return priority == Enum.AnimationPriority.Core
		or priority == Enum.AnimationPriority.Idle
		or priority == Enum.AnimationPriority.Movement
end

local function suppressDefaultLocomotionTracks()
	if not AnimationConfig.Authority.StopNonBeyond90LocomotionTracks or not currentAnimator then
		return
	end

	for _, track in currentAnimator:GetPlayingAnimationTracks() do
		if not isCustomTrack(track) and shouldSuppressPriority(track.Priority) then
			track:Stop(jogConfig.DefaultTrackFadeTime)
		end
	end
end

local function playTrack(slot: string, playbackRate: number, fadeTime: number)
	local record = activeTracks[slot]
	local track = record and record.Track

	if not track then
		return
	end

	track.Looped = true

	if not track.IsPlaying then
		track:Play(fadeTime, 1, playbackRate)
	else
		track:AdjustSpeed(playbackRate)
	end
end

local function playIdle()
	stopTrack("Jog", jogConfig.FadeOutTime)
	playTrack("Idle", 1, idleConfig.FadeInTime)
	currentPlaybackRate = 1
	currentBasePlaybackRate = 1
	suppressDefaultLocomotionTracks()
end

local function playJog(playbackRate: number)
	stopTrack("Idle", idleConfig.FadeOutTime)
	playTrack("Jog", playbackRate, jogConfig.FadeInTime)
	currentPlaybackRate = playbackRate
	suppressDefaultLocomotionTracks()
end

local function getPlaybackRates(speed: number): (number, number)
	local referenceSpeed = math.max(jogConfig.JogReferenceSpeed, 0.01)
	local basePlaybackRate = speed / referenceSpeed
	local finalPlaybackRate = math.clamp(
		basePlaybackRate * jogPlaybackMultiplier,
		jogConfig.JogMinPlaybackRate,
		jogConfig.JogMaxPlaybackRate
	)

	if basePlaybackRate * jogPlaybackMultiplier >= 2 and not warnedHighPlayback then
		warnedHighPlayback = true
		warnLog(string.format(
			"Jog animation would need %.2fx playback at speed %.1f; check authored stride/cadence before hiding mismatch.",
			basePlaybackRate * jogPlaybackMultiplier,
			speed
		))
	end

	return basePlaybackRate, finalPlaybackRate
end

local function getLocalMovementComponents(rootPart: BasePart, horizontalVelocity: Vector3): (number, number)
	if horizontalVelocity.Magnitude <= 0.001 then
		return 0, 0
	end

	local direction = horizontalVelocity.Unit
	local forward = getHorizontal(rootPart.CFrame.LookVector)
	local right = getHorizontal(rootPart.CFrame.RightVector)

	if forward.Magnitude > 0.001 then
		forward = forward.Unit
	end

	if right.Magnitude > 0.001 then
		right = right.Unit
	end

	return direction:Dot(forward), direction:Dot(right)
end

local function updateSprintFallback(speed: number, sprintRequested: boolean): boolean
	if sprintFallbackActive then
		if not sprintRequested and speed <= jogConfig.SprintExitSpeed then
			sprintFallbackActive = false
		end
	else
		if sprintRequested and speed >= jogConfig.SprintEnterSpeed then
			sprintFallbackActive = true
		end
	end

	return sprintFallbackActive
end

local function isJogState(state: string): boolean
	return state == "OffBallJog" or state == "BallJog" or state == "BallJogPlaceholder"
end

local function shouldJog(speed: number, wantsMovement: boolean): boolean
	if not jogConfig.Enabled or not wantsMovement or sprintFallbackActive then
		return false
	end

	if isJogState(currentState) then
		return speed > jogConfig.JogExitSpeed
	end

	return speed >= jogConfig.JogEnterSpeed
end

local function shouldIdle(speed: number, wantsMovement: boolean): boolean
	if not idleConfig.Enabled or sprintFallbackActive then
		return false
	end

	if currentState == "Idle" then
		return speed < jogConfig.JogEnterSpeed
	end

	if isJogState(currentState) and not wantsMovement then
		return speed <= jogConfig.JogExitSpeed
	end

	if wantsMovement then
		return speed < jogConfig.JogEnterSpeed
	end

	return speed <= jogConfig.JogExitSpeed
end

local function updateAnimation()
	local humanoid = currentHumanoid
	local rootPart = currentRootPart

	if not humanoid or not rootPart or humanoid.Health <= 0 then
		stopAllCustomTracks(jogConfig.FadeOutTime)
		suppressDefaultLocomotionTracks()
		sprintFallbackActive = false
		setState("Default", 0, 0, 0, false, false, 0, 0, idleAnimationId, false)
		return
	end

	local horizontalVelocity = getHorizontal(rootPart.AssemblyLinearVelocity)
	local speed = horizontalVelocity.Magnitude
	local locomotionState = MovementController.GetLocomotionState()
	local sprintRequested = locomotionState.IsSprinting == true
	local wantsMovement = (locomotionState.RawMagnitude or 0) > 0.05 or locomotionState.IsMoving == true
	local velocityImpliesMovement = speed >= jogConfig.JogEnterSpeed
	local hasBall = hasLocalPossession()
	local localForward, localRight = getLocalMovementComponents(rootPart, horizontalVelocity)
	local desiredJogState, jogAnimationId, jogTrackName, isPlaceholder = getDesiredJogPresentation(hasBall)

	updateSprintFallback(speed, sprintRequested)

	if isAirborne(humanoid) then
		stopAllCustomTracks(jogConfig.FadeOutTime)
		suppressDefaultLocomotionTracks()
		setState("AirborneFallback", speed, 0, 0, hasBall, sprintRequested, localForward, localRight, idleAnimationId, false)
		return
	end

	if sprintFallbackActive then
		stopAllCustomTracks(jogConfig.FadeOutTime)
		suppressDefaultLocomotionTracks()
		setState("SprintFallback", speed, 0, 0, hasBall, sprintRequested, localForward, localRight, jogAnimationId, isPlaceholder)
		return
	end

	if shouldJog(speed, wantsMovement or velocityImpliesMovement) then
		loadTrack("Jog", currentAnimator :: Animator, jogAnimationId, jogTrackName, jogConfig.Priority)
		local basePlaybackRate, finalPlaybackRate = getPlaybackRates(speed)
		playJog(finalPlaybackRate)
		currentBasePlaybackRate = basePlaybackRate
		setState(
			desiredJogState,
			speed,
			basePlaybackRate,
			finalPlaybackRate,
			hasBall,
			sprintRequested,
			localForward,
			localRight,
			jogAnimationId,
			isPlaceholder
		)
		return
	end

	if shouldIdle(speed, wantsMovement) then
		playIdle()
		setState("Idle", speed, 1, 1, hasBall, sprintRequested, localForward, localRight, idleAnimationId, false)
		return
	end

	stopAllCustomTracks(jogConfig.FadeOutTime)
	suppressDefaultLocomotionTracks()
	currentPlaybackRate = 0
	currentBasePlaybackRate = 0
	setState("Default", speed, 0, 0, hasBall, sprintRequested, localForward, localRight, idleAnimationId, false)
end

local function cleanupCharacter()
	disconnectCharacterConnections()
	destroyTracks()
	resetGroundingDiagnostics()
	currentCharacter = nil
	currentHumanoid = nil
	currentAnimator = nil
	currentRootPart = nil
	currentState = "Default"
	currentPlaybackRate = 0
	currentBasePlaybackRate = 0
	sprintFallbackActive = false
end

local function configureCharacter(character: Model)
	cleanupCharacter()

	currentCharacter = character
	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)

	if not humanoid or not humanoid:IsA("Humanoid") then
		warnLog("Character has no Humanoid; animation controller disabled for this spawn.")
		return
	end

	if not rootPart or not rootPart:IsA("BasePart") then
		warnLog("Character has no HumanoidRootPart; animation controller disabled for this spawn.")
		return
	end

	currentHumanoid = humanoid
	currentRootPart = rootPart
	currentAnimator = ensureAnimator(humanoid)
	warnedHighPlayback = false
	disableBundledAnimateScripts(character)
	loadTrack("Idle", currentAnimator, idleAnimationId, "B90_LOC_OffBall_Idle", idleConfig.Priority)
	loadTrack("Jog", currentAnimator, offBallJogAnimationId, "B90_LOC_OffBall_Jog_F", jogConfig.Priority)

	table.insert(characterConnections, character:GetAttributeChangedSignal("Beyond90HipHeight"):Connect(function()
		resetGroundingDiagnostics()
	end))

	table.insert(characterConnections, humanoid.Died:Connect(function()
		stopAllCustomTracks(jogConfig.FadeOutTime)
		setState("Default", 0, 0, 0, false, false, 0, 0, idleAnimationId, false)
	end))

	log(string.format(
		"Character ready rig=%s animator=%s defaultAnimate=%s",
		humanoid.RigType.Name,
		tostring(currentAnimator ~= nil),
		if character:FindFirstChild("Animate") then "present" else "absent"
	))
end

function AnimationController.Initialize()
	if initialized then
		return
	end

	initialized = true

	if localPlayer.Character then
		task.defer(configureCharacter, localPlayer.Character)
	end

	table.insert(appConnections, localPlayer.CharacterAdded:Connect(configureCharacter))
	table.insert(appConnections, localPlayer.CharacterRemoving:Connect(function()
		cleanupCharacter()
	end))

	renderConnection = RunService.RenderStepped:Connect(updateAnimation)
end

function AnimationController.Destroy()
	if not initialized then
		return
	end

	initialized = false

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	for _, connection in appConnections do
		connection:Disconnect()
	end

	table.clear(appConnections)

	cleanupCharacter()
end

function AnimationController.SetJogPlaybackMultiplier(multiplier: number): number
	local clamped = math.clamp(
		multiplier,
		jogConfig.JogPlaybackMultiplierMin,
		jogConfig.JogPlaybackMultiplierMax
	)
	clamped = math.round(clamped * 100) / 100

	if math.abs(clamped - jogPlaybackMultiplier) > 0.001 then
		jogPlaybackMultiplier = clamped
		diagnostics.JogPlaybackMultiplier = clamped
		localPlayer:SetAttribute("Beyond90JogPlaybackMultiplier", clamped)
		log(string.format("Jog playback multiplier -> %.2fx", clamped))
	end

	return jogPlaybackMultiplier
end

function AnimationController.AdjustJogPlaybackMultiplier(delta: number): number
	return AnimationController.SetJogPlaybackMultiplier(jogPlaybackMultiplier + delta)
end

function AnimationController.GetJogPlaybackMultiplier(): number
	return jogPlaybackMultiplier
end

function AnimationController.GetJogPlaybackMultiplierStep(): number
	return jogConfig.JogPlaybackMultiplierStep
end

function AnimationController.GetDiagnostics()
	return {
		State = diagnostics.State,
		HorizontalSpeed = diagnostics.HorizontalSpeed,
		BasePlaybackRate = diagnostics.BasePlaybackRate,
		JogPlaybackMultiplier = diagnostics.JogPlaybackMultiplier,
		FinalPlaybackRate = diagnostics.FinalPlaybackRate,
		HasBall = diagnostics.HasBall,
		SprintRequested = diagnostics.SprintRequested,
		TrackPlaying = diagnostics.TrackPlaying,
		TrackLoaded = diagnostics.TrackLoaded,
		Asset = diagnostics.Asset,
		IsPlaceholder = diagnostics.IsPlaceholder,
		IdleLength = diagnostics.IdleLength,
		IdleWeight = diagnostics.IdleWeight,
		JogLength = diagnostics.JogLength,
		JogWeight = diagnostics.JogWeight,
	}
end

return AnimationController
