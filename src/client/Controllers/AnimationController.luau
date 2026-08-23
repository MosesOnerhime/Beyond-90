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
local ControlledBallController = require(Controllers:WaitForChild("ControlledBallController"))
local FootballActionController = require(Controllers:WaitForChild("FootballActionController"))
local MovementController = require(Controllers:WaitForChild("MovementController"))

local AnimationController = {}

local localPlayer = Players.LocalPlayer
local idleConfig = AnimationConfig.Locomotion.Idle
local jogConfig = AnimationConfig.Locomotion.Jog
local sprintConfig = AnimationConfig.Locomotion.Sprint
local directionChangeConfig = AnimationConfig.Locomotion.DirectionChange
local blendConfig = AnimationConfig.Blend
local jumpConfig = AnimationConfig.Jump
local passConfig = AnimationConfig.Pass
local shootConfig = AnimationConfig.Shoot
local receptionConfig = AnimationConfig.Reception
local groundingConfig = PlayerConfig.Appearance.Grounding or {}
local assets = AnimationConfig.Assets

local initialized = false
local currentCharacter: Model? = nil
local currentHumanoid: Humanoid? = nil
local currentAnimator: Animator? = nil
local currentRootPart: BasePart? = nil
local renderConnection: RBXScriptConnection? = nil
local appConnections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local cachedBall: BasePart? = nil
local activeTracks = {}
local disabledAnimateScripts = {}
local currentState = "Default"
local currentLocomotionFamily = "Default"
local currentDirection = "Forward"
local currentSprintTurn = "Forward"
local currentPlaybackRate = 0
local currentBasePlaybackRate = 0
local jogPlaybackMultiplier = jogConfig.JogPlaybackMultiplier
local sprintActive = false
local previousDesiredDirection: Vector3? = nil
local lastDirectionChangeAt = -math.huge
local activeAction = ""
local activeActionUntil = 0
local activeActionExitAt = 0
local activeActionExitStarted = false
local desiredBaseState = "Idle"
local locomotionVisualActive = false
local jumpWasAirborne = false
local lastObservedControlEpoch: number? = nil
local directionChangeAudit = nil
local warnedHighPlayback = false
local jogWeights = {}
local sprintWeights = {}
local groundingSamples = {}
local previousFootSample = nil
local diagnostics = {
	State = "Default",
	BaseState = "Default",
	Action = "",
	ActionExitTarget = "",
	LocomotionFamily = "Default",
	Direction = "Forward",
	MovementAngle = 0,
	HorizontalSpeed = 0,
	BasePlaybackRate = 0,
	JogPlaybackMultiplier = jogConfig.JogPlaybackMultiplier,
	FinalPlaybackRate = 0,
	HasBall = false,
	SprintRequested = false,
	SprintTurn = "Forward",
	SprintTurnAngle = 0,
	TrackPlaying = false,
	TrackLoaded = false,
	IsPlaceholder = false,
	JogWeights = {},
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

local function getHorizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getYaw(cframe: CFrame): number
	local look = cframe.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

local function getWrappedAngleDelta(fromAngle: number, toAngle: number): number
	return (toAngle - fromAngle + 180) % 360 - 180
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

local function createGroundingBucket()
	return { StartedAt = 0, Count = 0, Min = math.huge, Max = -math.huge, Sum = 0, Reported = false }
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

	if string.find(state, "Jog", 1, true) then
		return "Jog"
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

local function chooseContactClearance(left: number?, right: number?, leftVelocityY: number, rightVelocityY: number): number?
	if left and not right then
		return left
	elseif right and not left then
		return right
	elseif not left or not right then
		return nil
	end

	local threshold = groundingConfig.ContactFootVerticalVelocityThreshold or 1.5
	local leftStable = math.abs(leftVelocityY) <= threshold
	local rightStable = math.abs(rightVelocityY) <= threshold
	local target = groundingConfig.TargetFootClearanceStuds or 0

	if leftStable and not rightStable then
		return left
	elseif rightStable and not leftStable then
		return right
	elseif leftStable and rightStable then
		return if math.abs(left - target) <= math.abs(right - target) then left else right
	end

	return math.min(left, right)
end

local function reportGroundingBucket(stateKey: string, bucket)
	local character = currentCharacter
	local humanoid = currentHumanoid
	if not character or not humanoid or bucket.Count <= 0 then
		return
	end

	local average = bucket.Sum / bucket.Count
	local target = groundingConfig.TargetFootClearanceStuds or 0
	local result = if bucket.Min < -0.02 then "penetrating" else "accepted"
	local prefix = if stateKey == "Idle" then "Beyond90GroundingIdle" else "Beyond90GroundingJog"
	localPlayer:SetAttribute(prefix .. "MinContactClearance", bucket.Min)
	localPlayer:SetAttribute(prefix .. "AverageContactClearance", average)
	localPlayer:SetAttribute(prefix .. "MaxContactClearance", bucket.Max)
	groundingLog(string.format(
		"state=%s height=%.2f hipHeight=%.3f groundY=%.3f floorDistance=%.3f targetClearance=%.3f contactMin=%.3f contactAvg=%.3f contactMax=%.3f samples=%d result=%s",
		string.lower(stateKey),
		character:GetAttribute("Beyond90CharacterHeight") or -1,
		humanoid.HipHeight,
		character:GetAttribute("Beyond90PitchGroundY") or -1,
		character:GetAttribute("Beyond90FloorDistance") or -1,
		target,
		bucket.Min,
		average,
		bucket.Max,
		bucket.Count,
		result
	))
end

local function sampleGrounding(state: string)
	local stateKey = getGroundingStateKey(state)
	local character = currentCharacter
	if not stateKey or not character then
		return
	end

	local groundY = character:GetAttribute("Beyond90PitchGroundY")
	if typeof(groundY) ~= "number" then
		return
	end

	local leftBottomY = getFootBottomY(character, "LeftFoot")
	local rightBottomY = getFootBottomY(character, "RightFoot")
	local now = os.clock()
	local previous = previousFootSample
	previousFootSample = { Time = now, Left = leftBottomY, Right = rightBottomY }
	if not previous then
		return
	end

	local dt = math.max(now - previous.Time, 1 / 240)
	local leftVelocityY = if leftBottomY and previous.Left then (leftBottomY - previous.Left) / dt else math.huge
	local rightVelocityY = if rightBottomY and previous.Right then (rightBottomY - previous.Right) / dt else math.huge
	local clearance = chooseContactClearance(
		if leftBottomY then leftBottomY - groundY else nil,
		if rightBottomY then rightBottomY - groundY else nil,
		leftVelocityY,
		rightVelocityY
	)
	local bucket = groundingSamples[stateKey]
	if not clearance or not bucket or bucket.Reported then
		return
	end

	if bucket.Count == 0 then
		bucket.StartedAt = now
	end
	bucket.Count += 1
	bucket.Sum += clearance
	bucket.Min = math.min(bucket.Min, clearance)
	bucket.Max = math.max(bucket.Max, clearance)

	if bucket.Count >= (groundingConfig.DiagnosticMinSamples or 30)
		and now - bucket.StartedAt >= (groundingConfig.DiagnosticSampleSeconds or 2.5)
	then
		bucket.Reported = true
		reportGroundingBucket(stateKey, bucket)
	end
end

local function disconnectCharacterConnections()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
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

local function loadTrack(slot: string, animationId: string, trackName: string, priority: Enum.AnimationPriority, looped: boolean)
	local animator = currentAnimator
	if not animator then
		return
	end

	local animation = Instance.new("Animation")
	animation.Name = trackName
	animation.AnimationId = animationId
	local ok, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not result then
		animation:Destroy()
		warnLog(string.format("Could not load %s %s: %s", trackName, animationId, tostring(result)))
		return
	end

	local track = result :: AnimationTrack
	track.Name = trackName
	track.Looped = looped
	track.Priority = priority
	activeTracks[slot] = { Animation = animation, AnimationId = animationId, Track = track }
	log(string.format("Loaded %s asset=%s priority=%s looped=%s", trackName, animationId, priority.Name, tostring(looped)))
	task.delay(2, function()
		local record = activeTracks[slot]
		if record and record.Track == track then
			localPlayer:SetAttribute("Beyond90AnimationLength" .. slot, track.Length)

			if track.Length <= 0 then
				warnLog(string.format("%s asset=%s still reports length=0", trackName, animationId))
			end
		end
	end)
end

local function stopTrack(slot: string, fadeTime: number?)
	local record = activeTracks[slot]
	local track = record and record.Track
	if track and track.IsPlaying then
		track:Stop(fadeTime or jogConfig.FadeOutTime)
	end
end

local function stopFamily(prefix: string, fadeTime: number)
	for slot in activeTracks do
		if string.sub(slot, 1, #prefix) == prefix then
			stopTrack(slot, fadeTime)
		end
	end
end

local function stopLocomotion(fadeTime: number)
	stopTrack("Idle", fadeTime)
	stopFamily("Jog", fadeTime)
	stopFamily("Sprint", fadeTime)
end

local function destroyTracks()
	for slot, record in activeTracks do
		stopTrack(slot, 0)
		record.Track:Destroy()
		record.Animation:Destroy()
	end
	table.clear(activeTracks)
end

local function disableBundledAnimateScripts(character: Model)
	table.clear(disabledAnimateScripts)
	if not AnimationConfig.Authority.DisableDefaultAnimate then
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("LocalScript") and descendant.Name == "Animate" then
			descendant.Enabled = false
			table.insert(disabledAnimateScripts, descendant)
		end
	end
end

local function isCustomTrack(track: AnimationTrack): boolean
	for _, record in activeTracks do
		if record.Track == track then
			return true
		end
	end
	return false
end

local function suppressDefaultLocomotionTracks()
	if not AnimationConfig.Authority.StopNonBeyond90LocomotionTracks or not currentAnimator then
		return
	end
	for _, track in currentAnimator:GetPlayingAnimationTracks() do
		if not isCustomTrack(track)
			and (track.Priority == Enum.AnimationPriority.Core or track.Priority == Enum.AnimationPriority.Idle or track.Priority == Enum.AnimationPriority.Movement)
		then
			track:Stop(jogConfig.DefaultTrackFadeTime)
		end
	end
end

local function playTrack(slot: string, fadeTime: number, weight: number, speed: number)
	local record = activeTracks[slot]
	local track = record and record.Track
	if not track then
		return
	end
	if not track.IsPlaying then
		track:Play(fadeTime, weight, speed)
	else
		track:AdjustSpeed(speed)
		track:AdjustWeight(weight, fadeTime)
	end
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

local function isJumpAirborne(humanoid: Humanoid): boolean
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
end

local function getLocalMovement(rootPart: BasePart, horizontalVelocity: Vector3): (number, number, number)
	if horizontalVelocity.Magnitude <= 0.001 then
		return 0, 0, 0
	end
	local direction = horizontalVelocity.Unit
	local forward = getHorizontal(rootPart.CFrame.LookVector).Unit
	local right = getHorizontal(rootPart.CFrame.RightVector).Unit
	local localForward = direction:Dot(forward)
	local localRight = direction:Dot(right)
	return localForward, localRight, math.deg(math.atan2(localRight, localForward))
end

local function getDirectionalTargets(angle: number): { [string]: number }
	local normalized = (angle % 360 + 360) % 360
	local segment = normalized / 45
	local lowerIndex = math.floor(segment) % 8 + 1
	local upperIndex = lowerIndex % 8 + 1
	local alpha = segment - math.floor(segment)
	return {
		[jogConfig.DirectionOrder[lowerIndex]] = 1 - alpha,
		[jogConfig.DirectionOrder[upperIndex]] = alpha,
	}
end

local function smoothWeights(current, target, responsiveness: number, deltaTime: number)
	local alpha = 1 - math.exp(-responsiveness * deltaTime)
	for _, direction in jogConfig.DirectionOrder do
		current[direction] = (current[direction] or 0) + ((target[direction] or 0) - (current[direction] or 0)) * alpha
	end
end

local function selectDominantDirection(weights): string
	local bestDirection = currentDirection
	local bestWeight = weights[bestDirection] or 0
	for direction, weight in weights do
		if weight > bestWeight + jogConfig.DominantWeightHysteresis then
			bestDirection = direction
			bestWeight = weight
		end
	end
	currentDirection = bestDirection
	return bestDirection
end

local function getJogPlaybackRates(speed: number): (number, number)
	local base = speed / math.max(jogConfig.JogReferenceSpeed, 0.01)
	local raw = base * jogPlaybackMultiplier
	if raw >= 2 and not warnedHighPlayback then
		warnedHighPlayback = true
		warnLog(string.format("Jog would need %.2fx playback at speed %.1f", raw, speed))
	end
	return base, math.clamp(raw, jogConfig.JogMinPlaybackRate, jogConfig.JogMaxPlaybackRate)
end

local function playIdle()
	stopFamily("Jog", blendConfig.LocomotionToIdle)
	stopFamily("Sprint", blendConfig.LocomotionToIdle)
	playTrack("Idle", blendConfig.LocomotionToIdle, 1, 1)
	currentBasePlaybackRate = 1
	currentPlaybackRate = 1
end

local function playJog(angle: number, speed: number, deltaTime: number)
	stopTrack("Idle", blendConfig.IdleToLocomotion)
	stopFamily("Sprint", blendConfig.SprintToJog)
	local targets = getDirectionalTargets(angle)
	smoothWeights(jogWeights, targets, jogConfig.WeightResponsiveness, deltaTime)
	local baseRate, finalRate = getJogPlaybackRates(speed)
	for _, direction in jogConfig.DirectionOrder do
		local multiplier = jogConfig.PerDirectionPlaybackMultiplier[direction] or 1
		playTrack("Jog" .. direction, blendConfig.JogDirectional, jogWeights[direction] or 0, finalRate * multiplier)
	end
	currentBasePlaybackRate = baseRate
	currentPlaybackRate = finalRate
	return selectDominantDirection(jogWeights)
end

local function updateSprintActive(speed: number, requested: boolean, rawMagnitude: number): boolean
	local wasActive = sprintActive
	local hasIntent = rawMagnitude > sprintConfig.IntentThreshold

	if requested and hasIntent then
		sprintActive = true
	elseif sprintActive and not requested and speed > sprintConfig.ExitSpeed then
		-- Preserve the sprint presentation while physical sprint momentum decays.
		sprintActive = true
	else
		sprintActive = false
	end

	if sprintActive ~= wasActive then
		log(string.format(
			"[SprintState] requested=%s visual=%s speed=%.1f latched=%s",
			tostring(requested),
			if sprintActive then "Sprint" else "Jog",
			speed,
			tostring(sprintActive)
		))
	end

	return sprintActive
end

local function getSignedTurn(locomotionState): (number, string)
	local current = locomotionState.SmoothedDirection
	local desired = locomotionState.RawDirection
	if current.Magnitude <= 0.05 or desired.Magnitude <= 0.05 then
		return 0, "Forward"
	end
	local angle = math.deg(math.acos(math.clamp(current.Unit:Dot(desired.Unit), -1, 1)))
	local crossY = current.Unit:Cross(desired.Unit).Y
	local side = if crossY < 0 then "TurnRight" else "TurnLeft"
	return angle, side
end

local function playSprint(speed: number, locomotionState, deltaTime: number): (string, number)
	stopTrack("Idle", blendConfig.IdleToLocomotion)
	stopFamily("Jog", blendConfig.JogToSprint)
	local turnAngle, proposedTurn = getSignedTurn(locomotionState)
	if currentSprintTurn == "Forward" then
		if turnAngle >= sprintConfig.TurnEnterAngle then
			currentSprintTurn = proposedTurn
		end
	elseif turnAngle <= sprintConfig.TurnExitAngle then
		currentSprintTurn = "Forward"
	elseif proposedTurn ~= currentSprintTurn and turnAngle >= sprintConfig.TurnEnterAngle then
		currentSprintTurn = proposedTurn
	end

	local turnWeight = if currentSprintTurn == "Forward" then 0 else math.clamp(
		(turnAngle - sprintConfig.TurnExitAngle) / math.max(sprintConfig.TurnFullWeightAngle - sprintConfig.TurnExitAngle, 1),
		0,
		1
	)
	local targets = {
		Forward = 1 - turnWeight,
		TurnLeft = if currentSprintTurn == "TurnLeft" then turnWeight else 0,
		TurnRight = if currentSprintTurn == "TurnRight" then turnWeight else 0,
	}
	local alpha = 1 - math.exp(-sprintConfig.WeightResponsiveness * deltaTime)
	for _, direction in { "Forward", "TurnLeft", "TurnRight" } do
		sprintWeights[direction] = (sprintWeights[direction] or 0) + (targets[direction] - (sprintWeights[direction] or 0)) * alpha
	end
	local baseRate = speed / math.max(sprintConfig.ReferenceSpeed, 0.01)
	local finalRate = math.clamp(baseRate * sprintConfig.PlaybackMultiplier, sprintConfig.MinPlaybackRate, sprintConfig.MaxPlaybackRate)
	for _, direction in { "Forward", "TurnLeft", "TurnRight" } do
		playTrack("Sprint" .. direction, blendConfig.JogToSprint, sprintWeights[direction] or 0, finalRate)
	end
	currentBasePlaybackRate = baseRate
	currentPlaybackRate = finalRate
	return currentSprintTurn, turnAngle
end

local function getActionConfig(slot: string)
	if slot == "DirectionChange180" then
		return directionChangeConfig
	elseif slot == "ReceivePass" then
		return receptionConfig
	elseif slot == "Pass" then
		return passConfig
	elseif slot == "Jump" then
		return jumpConfig
	end

	return nil
end

local function startAction(slot: string)
	local record = activeTracks[slot]
	local track = record and record.Track
	local config = getActionConfig(slot)

	if not track or not config then
		return
	end

	if activeAction ~= "" and activeAction ~= slot then
		local previousConfig = getActionConfig(activeAction)
		stopTrack(activeAction, if previousConfig then previousConfig.FadeOutTime else blendConfig.ActionExit)
		if activeAction == "DirectionChange180" then
			directionChangeAudit = nil
		end
	end

	local playbackRate = config.PlaybackRate or 1
	local fallbackDuration = config.FallbackDuration or 0.6
	local exitBlend = config.ExitBlendTime or config.FadeOutTime or blendConfig.ActionExit
	track:Stop(0)
	track.TimePosition = 0
	track:Play(config.FadeInTime or blendConfig.ActionEnter, 1, playbackRate)
	activeAction = slot
	local duration = math.max(track.Length / math.max(playbackRate, 0.01), fallbackDuration)
	activeActionUntil = os.clock() + duration
	activeActionExitAt = math.max(os.clock(), activeActionUntil - exitBlend)
	activeActionExitStarted = false

	if slot == "DirectionChange180" and directionChangeConfig.RootAuditEnabled and currentRootPart then
		local rootJoint = currentRootPart:FindFirstChild("RootJoint")
		directionChangeAudit = {
			EntryFamily = currentLocomotionFamily,
			RootYaw = getYaw(currentRootPart.CFrame),
			RootJoint = if rootJoint and rootJoint:IsA("Motor6D") then rootJoint else nil,
			MotorYaw = if rootJoint and rootJoint:IsA("Motor6D") then getYaw(rootJoint.Transform) else 0,
			MaxRootYawDelta = 0,
			MaxAnimationYawDelta = 0,
		}
	end

	log(string.format("Action -> %s length=%.2f", slot, track.Length))
end

local function sampleDirectionChangeAudit()
	local audit = directionChangeAudit
	local rootPart = currentRootPart

	if activeAction ~= "DirectionChange180" or not audit or not rootPart then
		return
	end

	audit.MaxRootYawDelta = math.max(
		audit.MaxRootYawDelta,
		math.abs(getWrappedAngleDelta(audit.RootYaw, getYaw(rootPart.CFrame)))
	)
	local rootJoint = audit.RootJoint
	if rootJoint and rootJoint.Parent then
		audit.MaxAnimationYawDelta = math.max(
			audit.MaxAnimationYawDelta,
			math.abs(getWrappedAngleDelta(audit.MotorYaw, getYaw(rootJoint.Transform)))
		)
	end
end

local function beginActionExit(reason: string, fadeOverride: number?, speed: number?, sprintRequested: boolean?)
	if activeAction == "" or activeActionExitStarted then
		return
	end

	local config = getActionConfig(activeAction)
	local fadeTime = fadeOverride or (config and config.FadeOutTime) or blendConfig.ActionExit
	local record = activeTracks[activeAction]
	local track = record and record.Track
	activeActionExitStarted = true
	activeActionUntil = math.min(activeActionUntil, os.clock() + fadeTime)

	if track and track.IsPlaying then
		track:AdjustWeight(0, fadeTime)
	end

	if activeAction == "DirectionChange180" and directionChangeAudit then
		log(string.format(
			"[Turn180] entryFamily=%s rootYawDelta=%.1f animationRootYawDelta=%.1f exitFamily=%s fade=%.2f",
			directionChangeAudit.EntryFamily,
			directionChangeAudit.MaxRootYawDelta,
			directionChangeAudit.MaxAnimationYawDelta,
			desiredBaseState,
			fadeTime
		))
	end

	log(string.format(
		"[Transition] from=%s to=%s speed=%.1f sprintRequested=%s fade=%.2f reason=%s",
		activeAction,
		desiredBaseState,
		speed or 0,
		tostring(sprintRequested == true),
		fadeTime,
		reason
	))
end

local function updateReceptionAction(ball: BasePart?)
	if not ball then
		return
	end
	local epoch = ball:GetAttribute("ControlEpoch")
	if typeof(epoch) ~= "number" then
		return
	end
	if lastObservedControlEpoch == nil then
		lastObservedControlEpoch = epoch
		return
	end
	if epoch == lastObservedControlEpoch then
		return
	end
	lastObservedControlEpoch = epoch
	local actionType = ball:GetAttribute("LastReceptionActionType")
	local receiverUserId = ball:GetAttribute("LastReceptionPlayerUserId")
	if receptionConfig.Enabled
		and receiverUserId == localPlayer.UserId
		and typeof(actionType) == "string"
		and receptionConfig.PassActionTypes[actionType] == true
	then
		MovementController.BeginActionMovement("ReceivePass")
		startAction("ReceivePass")
	end
end

local function onFootballActionPresentation(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local actionType = payload.ActionType

	if typeof(actionType) ~= "string" or passConfig.ActionTypes[actionType] ~= true then
		return
	end

	if payload.Stage == "Predicted" then
		startAction("Pass")
	elseif payload.Stage == "Rejected" and activeAction == "Pass" then
		beginActionExit("rejected", passConfig.FadeOutTime)
	end
end

local function updateJumpAction(humanoid: Humanoid, speed: number, sprintRequested: boolean)
	local airborne = isJumpAirborne(humanoid)

	if airborne and not jumpWasAirborne and jumpConfig.Enabled then
		startAction("Jump")
	elseif not airborne and jumpWasAirborne and activeAction == "Jump" then
		beginActionExit("landed", jumpConfig.FadeOutTime, speed, sprintRequested)
	end

	jumpWasAirborne = airborne
end

local function maybeTriggerDirectionChange(locomotionState, speed: number)
	local desired = locomotionState.RawDirection

	if not directionChangeConfig.Enabled or desired.Magnitude <= 0.05 then
		return
	end

	if activeAction ~= "" then
		previousDesiredDirection = desired.Unit
		return
	end
	if previousDesiredDirection and speed >= directionChangeConfig.MinimumSpeed and os.clock() - lastDirectionChangeAt >= directionChangeConfig.Cooldown then
		local angle = math.deg(math.acos(math.clamp(previousDesiredDirection:Dot(desired.Unit), -1, 1)))
		if angle >= directionChangeConfig.TriggerAngle then
			lastDirectionChangeAt = os.clock()
			startAction("DirectionChange180")
		end
	end
	previousDesiredDirection = desired.Unit
end

local function updateActionLifecycle(speed: number, sprintRequested: boolean): boolean
	if activeAction == "" then
		return false
	end

	local record = activeTracks[activeAction]
	local track = record and record.Track
	local now = os.clock()

	if not activeActionExitStarted and now >= activeActionExitAt then
		local config = getActionConfig(activeAction)
		beginActionExit(
			"natural",
			if config then config.ExitBlendTime or config.FadeOutTime else blendConfig.ActionExit,
			speed,
			sprintRequested
		)
	end

	if now <= activeActionUntil and track and track.IsPlaying then
		return true
	end

	if track and track.IsPlaying then
		track:Stop(0)
	end

	activeAction = ""
	activeActionUntil = 0
	activeActionExitAt = 0
	activeActionExitStarted = false
	directionChangeAudit = nil
	return false
end

local function updateDiagnostics(state: string, family: string, direction: string, angle: number, speed: number, hasBall: boolean, sprintRequested: boolean, sprintTurn: string, sprintTurnAngle: number, localForward: number, localRight: number, isPlaceholder: boolean)
	local ball = getFootball()
	local lead = if ball then ball:GetAttribute("ClientBallLead") or 0 else 0
	local phase = if ball then ball:GetAttribute("DribblePhase") or "" else ""
	local expectedRecontact = if ball then ball:GetAttribute("LastLocalTouchPredictedRecontactTime") or 0 else 0
	diagnostics.State = state
	diagnostics.BaseState = desiredBaseState
	diagnostics.Action = activeAction
	diagnostics.ActionExitTarget = if activeAction ~= "" then desiredBaseState else ""
	diagnostics.LocomotionFamily = family
	diagnostics.Direction = direction
	diagnostics.MovementAngle = angle
	diagnostics.HorizontalSpeed = speed
	diagnostics.BasePlaybackRate = currentBasePlaybackRate
	diagnostics.FinalPlaybackRate = currentPlaybackRate
	diagnostics.HasBall = hasBall
	diagnostics.SprintRequested = sprintRequested
	diagnostics.SprintTurn = sprintTurn
	diagnostics.SprintTurnAngle = sprintTurnAngle
	diagnostics.IsPlaceholder = isPlaceholder
	diagnostics.JogWeights = table.clone(jogWeights)
	diagnostics.TrackPlaying = false
	diagnostics.TrackLoaded = false
	for _, record in activeTracks do
		diagnostics.TrackLoaded = diagnostics.TrackLoaded or record.Track.Length > 0
		diagnostics.TrackPlaying = diagnostics.TrackPlaying or record.Track.IsPlaying
	end

	localPlayer:SetAttribute("Beyond90AnimationState", state)
	localPlayer:SetAttribute("Beyond90AnimationBaseState", desiredBaseState)
	localPlayer:SetAttribute("Beyond90AnimationAction", activeAction)
	localPlayer:SetAttribute("Beyond90AnimationActionExitTarget", if activeAction ~= "" then desiredBaseState else "")
	localPlayer:SetAttribute("Beyond90AnimationLocomotionFamily", family)
	localPlayer:SetAttribute("Beyond90AnimationDirection", direction)
	localPlayer:SetAttribute("Beyond90AnimationMovementAngle", angle)
	localPlayer:SetAttribute("Beyond90AnimationSpeed", speed)
	localPlayer:SetAttribute("Beyond90AnimationPlaybackRate", currentPlaybackRate)
	localPlayer:SetAttribute("Beyond90AnimationBasePlaybackRate", currentBasePlaybackRate)
	localPlayer:SetAttribute("Beyond90JogPlaybackMultiplier", jogPlaybackMultiplier)
	localPlayer:SetAttribute("Beyond90AnimationHasBall", hasBall)
	localPlayer:SetAttribute("Beyond90AnimationSprintRequested", sprintRequested)
	localPlayer:SetAttribute("Beyond90AnimationSprintTurn", sprintTurn)
	localPlayer:SetAttribute("Beyond90AnimationSprintTurnAngle", sprintTurnAngle)
	localPlayer:SetAttribute("Beyond90AnimationLocalForward", localForward)
	localPlayer:SetAttribute("Beyond90AnimationLocalRight", localRight)
	localPlayer:SetAttribute("Beyond90AnimationIsPlaceholder", isPlaceholder)
	localPlayer:SetAttribute("Beyond90AnimationBallLead", lead)
	localPlayer:SetAttribute("Beyond90AnimationDribblePhase", phase)
	localPlayer:SetAttribute("Beyond90AnimationExpectedRecontactTime", expectedRecontact)
	localPlayer:SetAttribute("Beyond90AnimationTrackPlaying", diagnostics.TrackPlaying)
	localPlayer:SetAttribute("Beyond90AnimationTrackLoaded", diagnostics.TrackLoaded)
	localPlayer:SetAttribute("Beyond90AnimationAuthority", "Beyond90")
	localPlayer:SetAttribute(
		"Beyond90DefaultAnimateDisabled",
		AnimationConfig.Authority.DisableDefaultAnimate
			and (#disabledAnimateScripts > 0 or (currentCharacter ~= nil and currentCharacter:FindFirstChild("Animate") == nil))
	)
	for key, weight in jogWeights do
		localPlayer:SetAttribute("Beyond90AnimationJogWeight" .. key, weight)
	end

	if state ~= currentState then
		currentState = state
		log(string.format(
			"State -> %s family=%s direction=%s angle=%.1f speed=%.1f playback=%.2f hasBall=%s placeholder=%s forward=%.2f right=%.2f sprintTurn=%s turnAngle=%.1f",
			state, family, direction, angle, speed, currentPlaybackRate, tostring(hasBall), tostring(isPlaceholder), localForward, localRight, sprintTurn, sprintTurnAngle
		))
	end
	sampleGrounding(desiredBaseState)
end

local function updateLocomotionVisualActive(rawMagnitude: number, speed: number): boolean
	if locomotionVisualActive then
		if rawMagnitude <= jogConfig.MovementIntentThreshold and speed <= jogConfig.JogExitSpeed then
			locomotionVisualActive = false
		end
	elseif rawMagnitude > jogConfig.MovementIntentThreshold or speed >= jogConfig.JogEnterSpeed then
		locomotionVisualActive = true
	end

	return locomotionVisualActive
end

local function resolveBaseLocomotion(
	humanoid: Humanoid,
	locomotionState,
	movementAngle: number,
	speed: number,
	hasBall: boolean,
	deltaTime: number
): (string, string, string, string, number)
	local sprintTurn = currentSprintTurn
	local sprintTurnAngle = 0
	local direction = currentDirection
	local rawMagnitude = locomotionState.RawMagnitude or 0
	local visualMovement = updateLocomotionVisualActive(rawMagnitude, speed)
	local unsupportedAirborne = isAirborne(humanoid) and activeAction ~= "Jump"

	if unsupportedAirborne then
		stopLocomotion(blendConfig.JumpEnter)
		currentLocomotionFamily = "AirborneFallback"
		currentPlaybackRate = 0
		currentBasePlaybackRate = 0
		return "AirborneFallback", currentLocomotionFamily, direction, sprintTurn, sprintTurnAngle
	end

	if sprintActive then
		direction, sprintTurnAngle = playSprint(speed, locomotionState, deltaTime)
		sprintTurn = direction
		currentLocomotionFamily = "Sprint"
	elseif jogConfig.Enabled and visualMovement then
		direction = playJog(movementAngle, speed, deltaTime)
		currentLocomotionFamily = if hasBall then "BallJogPlaceholder" else "Jog"
	else
		playIdle()
		currentLocomotionFamily = "Idle"
		direction = "Idle"
	end

	local state = if currentLocomotionFamily == "Jog" then "Jog" .. direction else currentLocomotionFamily

	if currentLocomotionFamily == "BallJogPlaceholder" then
		state = "BallJogPlaceholder" .. direction
	elseif currentLocomotionFamily == "Sprint" then
		state = "Sprint" .. direction
	end

	return state, currentLocomotionFamily, direction, sprintTurn, sprintTurnAngle
end

local function updateAnimation(deltaTime: number)
	local humanoid = currentHumanoid
	local rootPart = currentRootPart

	if not humanoid or not rootPart or humanoid.Health <= 0 then
		stopLocomotion(blendConfig.LocomotionToIdle)
		return
	end

	suppressDefaultLocomotionTracks()
	local horizontalVelocity = getHorizontal(rootPart.AssemblyLinearVelocity)
	local speed = horizontalVelocity.Magnitude
	local locomotionState = MovementController.GetLocomotionState()
	local sprintRequested = locomotionState.IsSprinting == true
	local hasBall = hasLocalPossession()
	local presentationDirection = horizontalVelocity

	if presentationDirection.Magnitude <= 0.1 and locomotionState.RawDirection.Magnitude > 0.05 then
		presentationDirection = locomotionState.RawDirection
	end

	local localForward, localRight, movementAngle = getLocalMovement(rootPart, presentationDirection)
	local isPlaceholder = hasBall
	local ball = getFootball()
	updateReceptionAction(ball)
	updateJumpAction(humanoid, speed, sprintRequested)
	updateSprintActive(speed, sprintRequested, locomotionState.RawMagnitude or 0)

	if not isAirborne(humanoid) then
		maybeTriggerDirectionChange(locomotionState, speed)
	end

	local baseState, family, direction, sprintTurn, sprintTurnAngle = resolveBaseLocomotion(
		humanoid,
		locomotionState,
		movementAngle,
		speed,
		hasBall,
		deltaTime
	)
	desiredBaseState = baseState
	sampleDirectionChangeAudit()
	local actionActive = updateActionLifecycle(speed, sprintRequested)
	local displayState = if actionActive then activeAction else baseState

	updateDiagnostics(
		displayState,
		family,
		direction,
		movementAngle,
		speed,
		hasBall,
		sprintRequested,
		sprintTurn,
		sprintTurnAngle,
		localForward,
		localRight,
		isPlaceholder
	)
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
	currentLocomotionFamily = "Default"
	currentDirection = "Forward"
	currentSprintTurn = "Forward"
	currentPlaybackRate = 0
	currentBasePlaybackRate = 0
	sprintActive = false
	previousDesiredDirection = nil
	activeAction = ""
	activeActionUntil = 0
	activeActionExitAt = 0
	activeActionExitStarted = false
	desiredBaseState = "Idle"
	locomotionVisualActive = false
	jumpWasAirborne = false
	lastObservedControlEpoch = nil
	directionChangeAudit = nil
	table.clear(jogWeights)
	table.clear(sprintWeights)
end

local function configureCharacter(character: Model)
	cleanupCharacter()
	currentCharacter = character
	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not rootPart or not rootPart:IsA("BasePart") then
		warnLog("Character missing Humanoid or HumanoidRootPart")
		return
	end
	currentHumanoid = humanoid
	currentRootPart = rootPart
	currentAnimator = ensureAnimator(humanoid)
	warnedHighPlayback = false
	disableBundledAnimateScripts(character)
	loadTrack("Idle", assets.Locomotion.OffBall.Idle, "B90_LOC_OffBall_Idle", idleConfig.Priority, true)
	for direction, animationId in assets.Locomotion.OffBall.Jog do
		loadTrack("Jog" .. direction, animationId, "B90_LOC_OffBall_Jog_" .. direction, jogConfig.Priority, true)
		jogWeights[direction] = 0
	end
	for direction, animationId in assets.Locomotion.OffBall.Sprint do
		loadTrack("Sprint" .. direction, animationId, "B90_LOC_OffBall_Sprint_" .. direction, sprintConfig.Priority, true)
		sprintWeights[direction] = 0
	end
	loadTrack("DirectionChange180", assets.Actions.DirectionChange180, "B90_LOC_DirectionChange_180", directionChangeConfig.Priority, false)
	loadTrack("ReceivePass", assets.Actions.ReceivePass, "B90_ACT_ReceivePass", receptionConfig.Priority, false)
	loadTrack("Jump", assets.Locomotion.Jump, "B90_LOC_Jump", jumpConfig.Priority, false)
	loadTrack("Pass", assets.Actions.Pass, "B90_ACT_Pass", passConfig.Priority, false)
	loadTrack("Shoot", assets.Actions.Shoot, "B90_ACT_Shoot", shootConfig.Priority, false)
	local ball = getFootball()
	lastObservedControlEpoch = if ball then ball:GetAttribute("ControlEpoch") else nil
	table.insert(characterConnections, character:GetAttributeChangedSignal("Beyond90HipHeight"):Connect(resetGroundingDiagnostics))
	table.insert(characterConnections, humanoid.Died:Connect(function()
		stopLocomotion(blendConfig.LocomotionToIdle)
	end))
	log(string.format("Character ready rig=%s animator=true tracks=%d defaultAnimate=%s", humanoid.RigType.Name, 17, if character:FindFirstChild("Animate") then "disabled" else "absent"))
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
	table.insert(appConnections, localPlayer.CharacterRemoving:Connect(cleanupCharacter))
	table.insert(appConnections, ControlledBallController.GetDribbleTouchEvent().Event:Connect(function(touch)
		localPlayer:SetAttribute("Beyond90AnimationLastDribbleFoot", touch.FootSide)
		localPlayer:SetAttribute("Beyond90AnimationLastDribbleStrength", touch.TouchStrength)
		localPlayer:SetAttribute("Beyond90AnimationLastDribbleTouchTime", os.clock())
	end))
	table.insert(appConnections, FootballActionController.GetPresentationEvent().Event:Connect(onFootballActionPresentation))
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
	local clamped = math.round(math.clamp(multiplier, jogConfig.JogPlaybackMultiplierMin, jogConfig.JogPlaybackMultiplierMax) * 100) / 100
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
	return table.clone(diagnostics)
end

return AnimationController
