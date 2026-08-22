local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared.Config.AnimationConfig)
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)

local Controllers = script.Parent
local MovementController = require(Controllers:WaitForChild("MovementController"))

local AnimationController = {}

local localPlayer = Players.LocalPlayer
local jogConfig = AnimationConfig.Locomotion.Jog
local offBallJogAnimationId = AnimationConfig.Assets.Locomotion.OffBall.JogForward

local initialized = false
local currentCharacter: Model? = nil
local currentHumanoid: Humanoid? = nil
local currentAnimator: Animator? = nil
local currentRootPart: BasePart? = nil
local jogAnimation: Animation? = nil
local jogTrack: AnimationTrack? = nil
local loadedJogAnimationId: string? = nil
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
local diagnostics = {
	State = "Default",
	HorizontalSpeed = 0,
	BasePlaybackRate = 0,
	JogPlaybackMultiplier = jogConfig.JogPlaybackMultiplier,
	FinalPlaybackRate = 0,
	HasBall = false,
	SprintRequested = false,
	TrackPlaying = false,
	Asset = offBallJogAnimationId,
	IsPlaceholder = false,
}

local function log(message: string)
	if AnimationConfig.DebugEnabled then
		print(string.format("%s[Client][Animation] %s", GameConfig.LogPrefix, message))
	end
end

local function warnLog(message: string)
	warn(string.format("%s[Client][Animation] %s", GameConfig.LogPrefix, message))
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

local function stopJog(fadeTime: number?)
	if jogTrack and jogTrack.IsPlaying then
		jogTrack:Stop(fadeTime or jogConfig.FadeOutTime)
	end
end

local function destroyTrack()
	stopJog(0)

	if jogTrack then
		jogTrack:Destroy()
		jogTrack = nil
	end

	if jogAnimation then
		jogAnimation:Destroy()
		jogAnimation = nil
	end

	loadedJogAnimationId = nil
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
	diagnostics.State = state
	diagnostics.HorizontalSpeed = speed
	diagnostics.BasePlaybackRate = basePlaybackRate
	diagnostics.JogPlaybackMultiplier = jogPlaybackMultiplier
	diagnostics.FinalPlaybackRate = finalPlaybackRate
	diagnostics.HasBall = hasBall
	diagnostics.SprintRequested = sprintRequested
	diagnostics.TrackPlaying = jogTrack ~= nil and jogTrack.IsPlaying
	diagnostics.Asset = assetId
	diagnostics.IsPlaceholder = isPlaceholder

	localPlayer:SetAttribute("Beyond90AnimationState", state)
	localPlayer:SetAttribute("Beyond90AnimationSpeed", speed)
	localPlayer:SetAttribute("Beyond90AnimationPlaybackRate", finalPlaybackRate)
	localPlayer:SetAttribute("Beyond90AnimationBasePlaybackRate", basePlaybackRate)
	localPlayer:SetAttribute("Beyond90JogPlaybackMultiplier", jogPlaybackMultiplier)
	localPlayer:SetAttribute("Beyond90AnimationAsset", assetId)
	localPlayer:SetAttribute("Beyond90AnimationTrackPlaying", diagnostics.TrackPlaying)
	localPlayer:SetAttribute("Beyond90AnimationHasBall", hasBall)
	localPlayer:SetAttribute("Beyond90AnimationSprintRequested", sprintRequested)
	localPlayer:SetAttribute("Beyond90AnimationIsPlaceholder", isPlaceholder)
	localPlayer:SetAttribute("Beyond90AnimationLocalForward", localForward)
	localPlayer:SetAttribute("Beyond90AnimationLocalRight", localRight)
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

	if state == "OffBallJog" or state == "BallJog" or state == "BallJogPlaceholder" then
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

local function loadJogTrack(animator: Animator, animationId: string, trackName: string)
	if loadedJogAnimationId == animationId and jogTrack then
		return
	end

	destroyTrack()

	jogAnimation = Instance.new("Animation")
	jogAnimation.Name = trackName
	jogAnimation.AnimationId = animationId

	local ok, result = pcall(function()
		return animator:LoadAnimation(jogAnimation :: Animation)
	end)

	if not ok or not result then
		warnLog(string.format("Could not load jog animation %s: %s", animationId, tostring(result)))
		return
	end

	jogTrack = result :: AnimationTrack
	jogTrack.Name = trackName
	jogTrack.Looped = true
	jogTrack.Priority = jogConfig.Priority
	loadedJogAnimationId = animationId
	log(string.format("Loaded %s asset=%s priority=%s", trackName, animationId, jogTrack.Priority.Name))
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

local function suppressDefaultMovementTracks()
	if not jogConfig.SuppressDefaultMovementTracks or not currentAnimator or not jogTrack then
		return
	end

	for _, track in currentAnimator:GetPlayingAnimationTracks() do
		if track ~= jogTrack and track.Priority == Enum.AnimationPriority.Movement then
			track:Stop(jogConfig.DefaultTrackFadeTime)
		end
	end
end

local function playJog(playbackRate: number)
	if not jogTrack then
		return
	end

	jogTrack.Looped = true
	jogTrack.Priority = jogConfig.Priority

	if not jogTrack.IsPlaying then
		jogTrack:Play(jogConfig.FadeInTime, 1, playbackRate)
	else
		jogTrack:AdjustSpeed(playbackRate)
	end

	currentPlaybackRate = playbackRate
	suppressDefaultMovementTracks()
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

local function shouldJog(speed: number, wantsMovement: boolean): boolean
	if not jogConfig.Enabled or not wantsMovement or sprintFallbackActive then
		return false
	end

	if currentState == "OffBallJog" or currentState == "BallJog" or currentState == "BallJogPlaceholder" then
		return speed > jogConfig.JogExitSpeed
	end

	return speed >= jogConfig.JogEnterSpeed
end

local function updateAnimation()
	local humanoid = currentHumanoid
	local rootPart = currentRootPart

	if not humanoid or not rootPart or humanoid.Health <= 0 then
		stopJog(jogConfig.FadeOutTime)
		sprintFallbackActive = false
		setState("Default", 0, 0, 0, false, false, 0, 0, offBallJogAnimationId, false)
		return
	end

	local horizontalVelocity = getHorizontal(rootPart.AssemblyLinearVelocity)
	local speed = horizontalVelocity.Magnitude
	local locomotionState = MovementController.GetLocomotionState()
	local sprintRequested = locomotionState.IsSprinting == true
	local wantsMovement = (locomotionState.RawMagnitude or 0) > 0.05 or locomotionState.IsMoving == true
	local hasBall = hasLocalPossession()
	local localForward, localRight = getLocalMovementComponents(rootPart, horizontalVelocity)
	local desiredState, animationId, trackName, isPlaceholder = getDesiredJogPresentation(hasBall)

	updateSprintFallback(speed, sprintRequested)

	if isAirborne(humanoid) then
		stopJog(jogConfig.FadeOutTime)
		setState("AirborneFallback", speed, 0, 0, hasBall, sprintRequested, localForward, localRight, animationId, isPlaceholder)
		return
	end

	if sprintFallbackActive then
		stopJog(jogConfig.FadeOutTime)
		setState("SprintFallback", speed, 0, 0, hasBall, sprintRequested, localForward, localRight, animationId, isPlaceholder)
		return
	end

	if shouldJog(speed, wantsMovement) then
		loadJogTrack(currentAnimator :: Animator, animationId, trackName)
		local basePlaybackRate, finalPlaybackRate = getPlaybackRates(speed)
		playJog(finalPlaybackRate)
		currentBasePlaybackRate = basePlaybackRate
		setState(
			desiredState,
			speed,
			basePlaybackRate,
			finalPlaybackRate,
			hasBall,
			sprintRequested,
			localForward,
			localRight,
			animationId,
			isPlaceholder
		)
		return
	end

	stopJog(jogConfig.FadeOutTime)
	currentPlaybackRate = 0
	currentBasePlaybackRate = 0
	setState("Default", speed, 0, 0, hasBall, sprintRequested, localForward, localRight, animationId, isPlaceholder)
end

local function cleanupCharacter()
	disconnectCharacterConnections()
	destroyTrack()
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
	loadJogTrack(currentAnimator, offBallJogAnimationId, "B90_LOC_OffBall_Jog_F")

	table.insert(characterConnections, humanoid.Died:Connect(function()
		stopJog(jogConfig.FadeOutTime)
		setState("Default", 0, 0, 0, false, false, 0, 0, offBallJogAnimationId, false)
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
		Asset = diagnostics.Asset,
		IsPlaceholder = diagnostics.IsPlaceholder,
	}
end

return AnimationController
