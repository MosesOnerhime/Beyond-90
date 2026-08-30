local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared.Config.AnimationConfig)
local GoalkeeperConfig = require(Shared.Config.GoalkeeperConfig)
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local GroundProbe = require(Shared.World.GroundProbe)

local Controllers = script.Parent
local ControlledBallController = require(Controllers:WaitForChild("ControlledBallController"))
local FootballActionController = require(Controllers:WaitForChild("FootballActionController"))
local MovementController = require(Controllers:WaitForChild("MovementController"))

local AnimationController = {}

local localPlayer = Players.LocalPlayer
local idleConfig = AnimationConfig.Locomotion.Idle
local jogConfig = AnimationConfig.Locomotion.Jog
local sprintConfig = AnimationConfig.Locomotion.Sprint
local blendConfig = AnimationConfig.Blend
local jumpConfig = AnimationConfig.Jump
local passConfig = AnimationConfig.Pass
local shootConfig = AnimationConfig.Shoot
local receptionConfig = AnimationConfig.Reception
local stopTrapConfig = AnimationConfig.StopTrap
local transitionConfig = AnimationConfig.Transitions or {}
local groundingConfig = PlayerConfig.Appearance.Grounding or {}
local assets = AnimationConfig.Assets
local transitionAssets = (assets.Locomotion and assets.Locomotion.Transitions) or {}
local lastTransitionAt = {}
local reversalCandidateAt = 0
local reverseStartCandidateAt = 0
local drivenRotationTarget: Vector3? = nil
local drivenRotationUntil = 0
local drivenRotationRate = 540
local drivenRotationSign = 1
local drivenRotationRemaining = 0
local previousAutoRotate: boolean? = nil
local previousMovingDirection = Vector3.zero

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
local activeAction = ""
local activeActionUntil = 0
local activeActionExitAt = 0
local activeActionExitStarted = false
local desiredBaseState = "Idle"
local locomotionVisualActive = false
local jumpWasAirborne = false
local lastObservedControlEpoch: number? = nil
local warnedHighPlayback = false
local jogWeights = {}
local sprintWeights = {}
local groundingSamples = {}
local previousFootSample = nil
local airborneCandidateAt = 0
local stopTrapArmed = false
local stopTrapPlayed = false
local sprintTurnCandidate = "Forward"
local sprintTurnCandidateAt = 0
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

-- Which keeper clip is currently driving the rig, and whether the keeper set
-- owns the body at all. Kept out of the outfield state so neither can stomp the
-- other's bookkeeping.
local keeperPresentationActive = false
local currentKeeperClip = ""

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

local function angleBetweenDegrees(a: Vector3, b: Vector3): number
	if a.Magnitude <= 1e-3 or b.Magnitude <= 1e-3 then
		return 0
	end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
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

local GROUNDING_BUCKETS = {
	"Idle",
	"Jog",
	"Sprint",
	"IdleToSprint",
	"IdleToSprint180",
	"DirectionChange180",
}

local function resetGroundingDiagnostics()
	table.clear(groundingSamples)
	for _, key in GROUNDING_BUCKETS do
		groundingSamples[key] = createGroundingBucket()
	end
	previousFootSample = nil
end

local function getGroundingStateKey(state: string): string?
	if state == "Idle" then
		return "Idle"
	end

	-- Transition clips are measured in their own buckets so a single bad source
	-- animation cannot be hidden inside the jog average.
	if groundingSamples[state] then
		return state
	end

	if string.find(state, "Sprint", 1, true) then
		return "Sprint"
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
	return foot.Position.Y - foot.Size.Y / 2 + (groundingConfig.VisualSoleOffsetStuds or 0)
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
	local prefix = "Beyond90Grounding" .. stateKey
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
		if not record or record.Track ~= track then
			return
		end
		localPlayer:SetAttribute("Beyond90AnimationLength" .. slot, track.Length)
		if track.Length > 0 then
			return
		end

		--[[
			A TRACK REPORTING LENGTH 0 IS AN ASSET THAT NEVER ARRIVED.

			LoadAnimation returns immediately and the keyframe data streams in
			afterwards, so a length of zero two seconds later means the fetch
			did not complete -- not that the clip is empty. Until now this only
			warned, and the track stayed permanently useless: every action using
			it fell back to a fixed duration and played nothing, which is the
			"animation does not play" class of report.

			So try once more, and this time PRELOAD FIRST. PreloadAsync blocks
			until the asset is actually resolved, which is the difference between
			asking again and asking again with any reason to expect a different
			answer.

			Exactly one retry. A genuinely broken or moderated asset must not
			produce an endless reload loop, and the warning below is then the
			honest outcome: this clip is not going to play, and the fallback
			duration is what keeps the action timing correct without it.
		]]
		task.spawn(function()
			local preloadOk = pcall(function()
				ContentProvider:PreloadAsync({ record.Animation })
			end)
			local current = activeTracks[slot]
			if not current or current.Track ~= track then
				return
			end
			if track.Length > 0 then
				localPlayer:SetAttribute("Beyond90AnimationLength" .. slot, track.Length)
				return
			end
			warnLog(string.format(
				"%s asset=%s still reports length=0 after preload (preloaded=%s); actions will use their fallback duration",
				trackName,
				animationId,
				tostring(preloadOk)
			))
		end)
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
	if state == Enum.HumanoidStateType.Jumping then
		local intentionalJump = localPlayer:GetAttribute("Beyond90JumpAssistActive") == true
		local upwardVelocity = currentRootPart and currentRootPart.AssemblyLinearVelocity.Y or 0
		if intentionalJump or upwardVelocity > 2 then
			airborneCandidateAt = 0
			return true
		end
	elseif state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Climbing
	then
		airborneCandidateAt = 0
		return true
	end

	if state ~= Enum.HumanoidStateType.Freefall or humanoid.FloorMaterial ~= Enum.Material.Air then
		airborneCandidateAt = 0
		return false
	end

	local config = AnimationConfig.AirbornePresentation or {}
	local rootPart = currentRootPart

	--[[
		YOU CANNOT BE FALLING AT ZERO STUDS PER SECOND.

		The runtime log is full of a footballer standing perfectly still and
		flicking into the airborne fallback for about a tenth of a second every
		few seconds:

			State -> AirborneFallback ... speed=0.0 playback=0.00
			State -> Idle             ... speed=0.0

		The cause is that the Humanoid intermittently reports Freefall with
		FloorMaterial = Air. That is plausible here rather than a fluke: this
		character deliberately has a non-collidable root and non-collidable feet
		(PlayerService sets collidableParts = Head, LowerTorso, UpperTorso), so
		Roblox's own floor detection has little underneath it to find and drops
		the floor for a frame. The raycast guard below was meant to catch that,
		but it only rejects the case where the ray FINDS ground -- when the cast
		returns nothing, the code concludes "clearly above ground" and, after
		EnterDelay, plays the fallback.

		Vertical speed settles it without having to trust either signal. A
		footballer whose vertical velocity is essentially zero is resting on
		something, whatever the Humanoid believes.
		`GroundedVerticalSpeedTolerance` was already in the config for exactly
		this and had never been read by anything.

		A real jump is exempt, because a jump genuinely does pass through zero
		vertical speed at its apex and must not drop out of the airborne
		presentation for that frame.
	]]
	if rootPart and localPlayer:GetAttribute("Beyond90JumpAssistActive") ~= true then
		local verticalSpeed = math.abs(rootPart.AssemblyLinearVelocity.Y)
		if verticalSpeed <= (config.GroundedVerticalSpeedTolerance or 1.5) then
			airborneCandidateAt = 0
			return false
		end
	end

	if rootPart then
		local ground = GroundProbe.Raycast(rootPart.Position, 8, { currentCharacter :: Instance })
		local nearGround = ground and ground.Distance <= (humanoid.HipHeight + rootPart.Size.Y / 2 + 0.75)
		local fallingMeaningfully = rootPart.AssemblyLinearVelocity.Y <= -(config.MinimumFallSpeed or 2.25)
		local clearlyAboveGround = ground == nil
			or ground.Distance > (humanoid.HipHeight + rootPart.Size.Y / 2 + (config.ClearGroundDistancePadding or 1.5))
		if nearGround or (not fallingMeaningfully and not clearlyAboveGround) then
			airborneCandidateAt = 0
			return false
		end
	end
	if airborneCandidateAt <= 0 then
		airborneCandidateAt = os.clock()
	end
	return os.clock() - airborneCandidateAt >= (config.EnterDelay or 0.12)
end

local function isJumpAirborne(humanoid: Humanoid): boolean
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping then
		return localPlayer:GetAttribute("Beyond90JumpAssistActive") == true
			or (currentRootPart ~= nil and currentRootPart.AssemblyLinearVelocity.Y > 2)
	elseif state == Enum.HumanoidStateType.Freefall then
		return activeAction == "Jump" or isAirborne(humanoid)
	end
	return false
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

	if requested and (hasIntent or (sprintActive and speed > jogConfig.JogExitSpeed)) then
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

local function playSprint(speed: number, locomotionState, deltaTime: number, forceForward: boolean?): (string, number)
	stopTrack("Idle", blendConfig.IdleToLocomotion)
	stopFamily("Jog", blendConfig.JogToSprint)
	local turnAngle, proposedTurn = getSignedTurn(locomotionState)
	if forceForward or speed < (sprintConfig.TurnMinimumSpeed or 0) then
		turnAngle = 0
		proposedTurn = "Forward"
		currentSprintTurn = "Forward"
		sprintTurnCandidate = "Forward"
		sprintTurnCandidateAt = 0
	elseif proposedTurn ~= "Forward" and turnAngle >= sprintConfig.TurnEnterAngle then
		if sprintTurnCandidate ~= proposedTurn then
			sprintTurnCandidate = proposedTurn
			sprintTurnCandidateAt = os.clock()
		end
		if os.clock() - sprintTurnCandidateAt < (sprintConfig.TurnSustainTime or 0) then
			proposedTurn = "Forward"
			turnAngle = 0
		end
	else
		sprintTurnCandidate = "Forward"
		sprintTurnCandidateAt = 0
	end
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
	if slot == "ReceivePass" then
		return receptionConfig
	elseif slot == "Pass" then
		return passConfig
	elseif slot == "Jump" then
		return jumpConfig
	elseif slot == "StopTrapPlaceholder" then
		return stopTrapConfig
	elseif slot == "Shoot" then
		return shootConfig
	elseif transitionConfig[slot] then
		return transitionConfig[slot]
	end

	return nil
end

--[[
	Actions that OWN the body while they run (§72, §73).

	A driven transition rotates the root itself and plays a clip authored to match
	that rotation. While one is running the ordinary locomotion selection must
	stand still: it has nothing useful to say, because the footballer's velocity
	during a reversal passes through zero and its facing is being driven rather
	than followed.

	This is the actual cause of the 180 stutter. resolveBaseLocomotion ran every
	frame regardless of what action was playing, so mid-reversal it kept
	re-selecting and re-weighting jog -- at a measured speed near zero, which is
	why the logs showed locomotion states chosen with speed = 0 -- and blended
	that against the reversal clip. Two systems animating the legs at once.
]]
local DRIVEN_TRANSITION_ACTIONS = {
	DirectionChange180 = true,
	IdleToSprint = true,
	IdleToSprint180 = true,
}

local function startAction(slot: string, weight: number?)
	local record = activeTracks[slot]
	local track = record and record.Track
	local config = getActionConfig(slot)

	if not track or not config then
		return
	end

	if activeAction ~= "" and activeAction ~= slot then
		local previousConfig = getActionConfig(activeAction)
		stopTrack(activeAction, if previousConfig then previousConfig.FadeOutTime else blendConfig.ActionExit)
	end

	local playbackRate = config.PlaybackRate or 1
	local fallbackDuration = config.FallbackDuration or 0.6
	local exitBlend = config.ExitBlendTime or config.FadeOutTime or blendConfig.ActionExit
	track:Stop(0)
	track.TimePosition = 0
	track:Play(config.FadeInTime or blendConfig.ActionEnter, weight or 1, playbackRate)
	activeAction = slot
	local duration = math.max(track.Length / math.max(playbackRate, 0.01), fallbackDuration)
	activeActionUntil = os.clock() + duration
	activeActionExitAt = math.max(os.clock(), activeActionUntil - exitBlend)
	activeActionExitStarted = false

	log(string.format("Action -> %s length=%.2f", slot, track.Length))
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

	if typeof(actionType) ~= "string" then
		return
	end
	local slot = if actionType == "Shoot" then "Shoot" elseif passConfig.ActionTypes[actionType] == true then "Pass" else nil
	if not slot then
		return
	end

	if payload.Stage == "Predicted" then
		startAction(slot)
	elseif payload.Stage == "Rejected" and activeAction == slot then
		local config = getActionConfig(slot)
		beginActionExit("rejected", config and config.FadeOutTime or blendConfig.ActionExit)
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

local function updateStopTrapAction(locomotionState, speed: number, hasBall: boolean, ball: BasePart?)
	if not stopTrapConfig.Enabled then
		return
	end

	local inputMagnitude = locomotionState.InputMagnitude or locomotionState.RawMagnitude or 0
	if activeAction == "StopTrapPlaceholder" then
		if inputMagnitude > jogConfig.MovementIntentThreshold or not hasBall then
			beginActionExit("cancelled-by-movement", stopTrapConfig.FadeOutTime, speed, locomotionState.IsSprinting)
		end
		return
	end

	if not hasBall or inputMagnitude > jogConfig.MovementIntentThreshold then
		stopTrapArmed = false
		stopTrapPlayed = false
		return
	end

	if speed > stopTrapConfig.TriggerSpeed then
		stopTrapArmed = true
		return
	end

	local lead = if ball then math.abs(ball:GetAttribute("ClientBallLead") or math.huge) else math.huge
	if stopTrapArmed
		and not stopTrapPlayed
		and activeAction == ""
		and lead <= stopTrapConfig.MaximumBallLead
	then
		stopTrapPlayed = true
		stopTrapArmed = false
		startAction("StopTrapPlaceholder")
		log(string.format("StopTrapPlaceholder lead=%.2f speed=%.2f", lead, speed))
	end
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

--[[
	INTENT WITHOUT MOTION IS NOT A RUN (§72).

	Entry used to be intent alone, so a footballer who is holding a direction but
	is not actually going anywhere played a full jog cycle on the spot -- the
	`JogForward speed=0.0` in the runtime evidence. It happens wherever movement
	is externally held: restart setup, repositioning, the pre-match freeze.

	Entry is still IMMEDIATE on intent, so a genuine start has no added latency:
	real acceleration produces speed within a frame or two and the state simply
	continues. What is new is that intent which never turns into motion is given
	a short grace and then dropped back to Idle, so a held footballer stands
	still instead of running in place.
]]
local intentWithoutMotionSince = 0

local function updateLocomotionVisualActive(rawMagnitude: number, speed: number): boolean
	-- The footballer also travels under reception and loose-ball assistance, where
	-- raw stick input is zero. Presentation follows actual movement, not only
	-- input, otherwise an assisted run toward the ball plays Idle.
	local movingUnderAssist = speed > (jogConfig.VisualExitSpeed or jogConfig.JogExitSpeed)
	local hasIntent = rawMagnitude > jogConfig.MovementIntentThreshold
	local stationary = speed <= (jogConfig.StationaryVisualSpeed or 1.5)
	local now = os.clock()

	if hasIntent and stationary then
		if intentWithoutMotionSince <= 0 then
			intentWithoutMotionSince = now
		end
	else
		intentWithoutMotionSince = 0
	end

	-- Intent that has produced no movement for this long is a held footballer,
	-- not a running one.
	local stalledIntent = intentWithoutMotionSince > 0
		and now - intentWithoutMotionSince >= (jogConfig.StalledIntentSeconds or 0.2)

	if locomotionVisualActive then
		if (not hasIntent and not movingUnderAssist) or stalledIntent then
			locomotionVisualActive = false
		end
	elseif (hasIntent and not stalledIntent) or movingUnderAssist then
		locomotionVisualActive = true
	end

	return locomotionVisualActive
end

--[[
	Drive the footballer's actual yaw through a turn transition.

	The imported clips carry no root rotation, so without this the animation
	plays while the body still faces the old direction and then snaps. Authority
	is taken only for the length of the clip and handed straight back to normal
	movement, so AutoRotate is never fought continuously.
]]
--[[
	Which way the footballer turns, decided once and shared by the clip choice
	and the yaw driver so the two can never disagree.

	Handedness is picked explicitly rather than left to a shortest-path lerp:
	near 180 degrees the shortest arc is numerically ambiguous and the body can
	flick either way between frames. facing:Cross(target).Y is positive when the
	target lies to the player's left, which matches a positive CFrame.Angles Y
	rotation, so a negative Y is a right turn.

	Returns +1 for left, -1 for right.
]]
local function resolveTurnSign(config, target: Vector3): number
	local rootPart = currentRootPart
	local facing = getHorizontal(if rootPart then rootPart.CFrame.LookVector else Vector3.zero)
	local authored = config.AuthoredTurnSign or -1

	if facing.Magnitude <= 1e-3 or target.Magnitude <= 1e-3 then
		return authored
	end

	facing = facing.Unit
	local horizontal = getHorizontal(target)
	if horizontal.Magnitude <= 1e-3 then
		return authored
	end
	horizontal = horizontal.Unit

	local cross = facing:Cross(horizontal).Y
	local angle = angleBetweenDegrees(facing, horizontal)

	-- Effectively a straight reversal: follow the clip's authored direction.
	if angle >= 180 - (config.HandednessAmbiguityDegrees or 6) or math.abs(cross) <= 1e-3 then
		return authored
	end

	return if cross > 0 then 1 else -1
end

local function beginDrivenRotation(config, targetDirection: Vector3)
	if not config or config.DriveRotation ~= true then
		return
	end
	local horizontal = getHorizontal(targetDirection)
	if horizontal.Magnitude <= 1e-3 then
		return
	end
	local rootPart = currentRootPart
	local facing = getHorizontal(if rootPart then rootPart.CFrame.LookVector else Vector3.zero)
	if facing.Magnitude <= 1e-3 then
		return
	end

	local target = horizontal.Unit
	facing = facing.Unit

	local sign = resolveTurnSign(config, target)
	local angle = angleBetweenDegrees(facing, target)

	drivenRotationTarget = target
	drivenRotationSign = sign
	drivenRotationRemaining = angle
	drivenRotationUntil = os.clock() + (config.RotationHoldSeconds or 0.4)
	drivenRotationRate = config.RotationDegreesPerSecond or 540
	if currentHumanoid then
		-- Hand orientation to us for the duration of the turn (§73).
		previousAutoRotate = currentHumanoid.AutoRotate
		currentHumanoid.AutoRotate = false
		localPlayer:SetAttribute(
			AnimationConfig.RotationAuthorityAttribute,
			AnimationConfig.RotationAuthorityAnimation
		)
	end
end

local function updateDrivenRotation(deltaTime: number)
	if drivenRotationUntil <= 0 then
		return
	end
	local rootPart = currentRootPart
	local humanoid = currentHumanoid
	if not rootPart or not humanoid or os.clock() >= drivenRotationUntil then
		if humanoid and drivenRotationUntil > 0 then
			humanoid.AutoRotate = if previousAutoRotate == nil then true else previousAutoRotate
		end
		drivenRotationUntil = 0
		drivenRotationTarget = nil
		drivenRotationRemaining = 0
		previousAutoRotate = nil
		-- Orientation goes back to normal movement ownership (§73).
		localPlayer:SetAttribute(AnimationConfig.RotationAuthorityAttribute, nil)
		return
	end

	local target = drivenRotationTarget
	if not target then
		return
	end
	local current = getHorizontal(rootPart.CFrame.LookVector)
	if current.Magnitude <= 1e-3 then
		return
	end
	current = current.Unit

	--[[
		Bounded yaw step in the handedness chosen at the start of the turn.

		This rotates by an explicit signed angle rather than lerping toward the
		target, because a lerp always takes the shortest arc: on a left reversal
		it would silently drag the body back through the right-hand side and
		undo the mirrored turn.
	]]
	local remaining = math.min(drivenRotationRemaining, angleBetweenDegrees(current, target))
	if remaining <= 2 then
		humanoid.AutoRotate = if previousAutoRotate == nil then true else previousAutoRotate
		drivenRotationUntil = 0
		drivenRotationTarget = nil
		drivenRotationRemaining = 0
		previousAutoRotate = nil
		localPlayer:SetAttribute(AnimationConfig.RotationAuthorityAttribute, nil)
		return
	end

	local step = math.min(drivenRotationRate * deltaTime, remaining)
	drivenRotationRemaining = remaining - step

	local nextDirection = (CFrame.Angles(0, math.rad(step * drivenRotationSign), 0) * current)
	if nextDirection.Magnitude > 1e-3 then
		nextDirection = nextDirection.Unit
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + nextDirection)
	end
end

local function transitionReady(slot: string, config): boolean
	if not config or config.Enabled == false then
		return false
	end
	if not activeTracks[slot] then
		return false
	end
	local last = lastTransitionAt[slot]
	return not last or os.clock() - last >= (config.Cooldown or 0.5)
end

-- Locomotion transitions are cosmetic. They are selected from actual movement
-- state and never gate input; MovementController keeps full authority.
local function updateLocomotionTransitions(locomotionState, speed: number, deltaTime: number)
	if transitionConfig.Enabled == false or activeAction ~= "" then
		return
	end

	local intent = math.max(locomotionState.InputMagnitude or 0, locomotionState.RawMagnitude or 0)
	local requestedDirection = getHorizontal(locomotionState.RawDirection or Vector3.zero)
	local movingDirection = getHorizontal(
		if currentRootPart then currentRootPart.AssemblyLinearVelocity else Vector3.zero
	)
	local facing = getHorizontal(if currentRootPart then currentRootPart.CFrame.LookVector else Vector3.zero)
	local now = os.clock()

	-- Genuine reversal while already travelling.
	local reversal = transitionConfig.DirectionChange180
	if reversal and reversal.Enabled ~= false
		and speed >= (reversal.MinimumSpeed or 11)
		and intent > 0.05
		and previousMovingDirection.Magnitude > 1e-3
		and requestedDirection.Magnitude > 1e-3
	then
		local reversalAngle = angleBetweenDegrees(previousMovingDirection, requestedDirection)
		if reversalAngle >= (reversal.MinimumAngleDegrees or 140) then
			if reversalCandidateAt <= 0 then
				reversalCandidateAt = now
			elseif now - reversalCandidateAt >= (reversal.SustainSeconds or 0.05)
				and transitionReady("DirectionChange180", reversal)
			then
				reversalCandidateAt = 0
				lastTransitionAt.DirectionChange180 = now

				--[[
					The clip is authored as a right turn and Roblox exposes no
					runtime skeletal mirroring, so a left reversal cannot be shown
					correctly from this asset. AdjustSpeed(-1) is playback
					reversal, not a mirror, and would be wrong here.

					The gameplay yaw is still mirrored properly by
					beginDrivenRotation. The clip itself is played at a reduced
					weight for a left turn so its right-hand lean blends toward
					normal locomotion instead of visibly contradicting the
					direction the body is travelling. A dedicated left-turn asset
					is required for true limb-level mirroring.
				]]
				local mirrored = resolveTurnSign(reversal, requestedDirection) > 0
				local weight = if mirrored
					then (reversal.UnmirroredClipWeight or 0.55)
					else 1

				startAction("DirectionChange180", weight)
				beginDrivenRotation(reversal, requestedDirection)
				return
			end
		else
			reversalCandidateAt = 0
		end
	else
		reversalCandidateAt = 0
	end

	-- Starting to move from a genuine standstill.
	local idleStart = transitionConfig.IdleToSprint
	local idleStart180 = transitionConfig.IdleToSprint180
	local standingStill = speed <= math.max(
		(idleStart and idleStart.MaximumEntrySpeed) or 3.5,
		(idleStart180 and idleStart180.MaximumEntrySpeed) or 3.5
	)

	if standingStill and not locomotionVisualActive and requestedDirection.Magnitude > 1e-3 then
		-- Measure only against live facing. Using a travel direction left over
		-- from a previous coast is what produced IdleToSprint180 firing with a
		-- logged angle of ~0 degrees.
		local facingAngle = if facing.Magnitude > 1e-3
			then angleBetweenDegrees(facing, requestedDirection)
			else 0
		local wantsReverseStart = idleStart180
			and idleStart180.Enabled ~= false
			and facing.Magnitude > 1e-3
			and intent >= (idleStart180.MinimumIntent or 0.35)
			and facingAngle >= (idleStart180.MinimumAngleDegrees or 115)

		-- Require the reversal intent to persist, so one noisy frame cannot
		-- classify a straight-ahead start as an opposite-direction start.
		if wantsReverseStart then
			if reverseStartCandidateAt <= 0 then
				reverseStartCandidateAt = now
			end
		else
			reverseStartCandidateAt = 0
		end

		if wantsReverseStart
			and now - reverseStartCandidateAt >= (idleStart180.SustainSeconds or 0.06)
			and transitionReady("IdleToSprint180", idleStart180)
		then
			reverseStartCandidateAt = 0
			lastTransitionAt.IdleToSprint180 = now
			startAction("IdleToSprint180")
			beginDrivenRotation(idleStart180, requestedDirection)
		elseif not wantsReverseStart
			and idleStart and idleStart.Enabled ~= false
			and intent >= (idleStart.MinimumIntent or 0.35)
			and transitionReady("IdleToSprint", idleStart)
		then
			lastTransitionAt.IdleToSprint = now
			startAction("IdleToSprint")
		end
	else
		reverseStartCandidateAt = 0
	end

	if movingDirection.Magnitude > 1e-3 then
		previousMovingDirection = movingDirection.Unit
	end
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
	-- Take whichever intent is larger. RawMagnitude carries assisted movement;
	-- InputMagnitude carries the player's own stick.
	local rawMagnitude = math.max(locomotionState.InputMagnitude or 0, locomotionState.RawMagnitude or 0)
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

--[[
	GOALKEEPER PRESENTATION.

	A keeper is not an outfielder standing in a different place: their set
	position, their lateral guard step and the way they hold the ball are their
	own vocabulary, and playing an outfield idle in goal is one of the things
	that made choosing GK feel like nothing had happened.

	The state machine is deliberately tiny, because the keeper's job on the line
	is tiny:

		holding the ball   -> the idle that has a ball in it
		diving             -> the reach clip, owned by the action layer
		shuffling          -> the lateral guard step
		otherwise standing -> the set position

	and above a running speed it hands back to the ordinary locomotion set, so
	sprinting off the line looks like a footballer sprinting.

	Returns whether it took ownership of the body this frame.
]]
local function updateGoalkeeperAnimation(rootPart: BasePart, speed: number, deltaTime: number): boolean
	local model = localPlayer.Character
	if not model or model:GetAttribute(GoalkeeperConfig.RoleAttributeName) ~= GoalkeeperConfig.Role then
		if keeperPresentationActive then
			-- No longer a keeper: release the keeper clips so the outfield set can
			-- take the body back cleanly.
			stopFamily("Keeper", blendConfig.LocomotionToIdle)
			keeperPresentationActive = false
		end
		return false
	end
	if not activeTracks.KeeperIdle then
		return false
	end

	local keeperConfig = AnimationConfig.Goalkeeper
	if keeperConfig.Enabled ~= true then
		return false
	end

	--[[
		Moving is footballer movement, not goalkeeping -- INCLUDING WITH THE BALL.

		The holding test that used to be here kept a keeper on the static
		`KeeperIdleWithBall` pose no matter how fast they moved, which was
		harmless only while holding also froze them in place. It does not any
		more: a keeper who has caught the ball walks it out to the edge of their
		box, and doing that in a standing pose is a footballer gliding across the
		grass. Moving feet with the wrong arms beats a statue on rails.
	]]
	if speed > keeperConfig.RunThreshold then
		if keeperPresentationActive then
			stopFamily("Keeper", keeperConfig.FadeOutTime)
			keeperPresentationActive = false
		end
		return false
	end

	local desired = "KeeperIdle"
	if model:GetAttribute(GoalkeeperConfig.Attributes.Holding) == true and activeTracks.KeeperIdleWithBall then
		desired = "KeeperIdleWithBall"
	else
		local lateral = math.abs(getHorizontal(rootPart.AssemblyLinearVelocity):Dot(rootPart.CFrame.RightVector))
		if lateral >= keeperConfig.SideStepMinimumSpeed and activeTracks.KeeperSideStep then
			desired = "KeeperSideStep"
		end
	end

	if not keeperPresentationActive then
		-- Coming from the outfield set: stop it rather than layering on top.
		stopLocomotion(keeperConfig.FadeInTime)
		keeperPresentationActive = true
	end
	if currentKeeperClip ~= desired then
		for _, slot in { "KeeperIdle", "KeeperIdleWithBall", "KeeperSideStep" } do
			if slot ~= desired then
				stopTrack(slot, keeperConfig.FadeOutTime)
			end
		end
		currentKeeperClip = desired
	end
	playTrack(desired, keeperConfig.FadeInTime, 1, keeperConfig.PlaybackRate)
	currentBasePlaybackRate = keeperConfig.PlaybackRate
	currentPlaybackRate = keeperConfig.PlaybackRate
	updateDiagnostics(desired, "Goalkeeper", "Idle", 0, speed, false, false, "Forward", 0, 0, 0, false)
	return true
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

	--[[
		The keeper owns the body while it is guarding the line. Placed before any
		outfield selection so the two sets can never both be driving the rig.
	]]
	if updateGoalkeeperAnimation(rootPart, speed, deltaTime) then
		return
	end

	local localForward, localRight, movementAngle = getLocalMovement(rootPart, presentationDirection)
	local isPlaceholder = hasBall
	local ball = getFootball()
	updateReceptionAction(ball)
	updateJumpAction(humanoid, speed, sprintRequested)
	updateSprintActive(speed, sprintRequested, math.max(locomotionState.InputMagnitude or 0, locomotionState.RawMagnitude or 0))
	updateStopTrapAction(locomotionState, speed, hasBall, ball)
	updateLocomotionTransitions(locomotionState, speed, deltaTime)
	updateDrivenRotation(deltaTime)

	--[[
		LOCOMOTION HOLDS WHILE A DRIVEN TRANSITION RUNS (§72).

		The transition owns the legs. Re-selecting jog or sprint underneath it is
		what produced the visible stutter, so the base selection is skipped
		entirely and the previous state is reported unchanged.
	]]
	local drivenTransition = activeAction ~= "" and DRIVEN_TRANSITION_ACTIONS[activeAction] == true

	local baseState, family, direction, sprintTurn, sprintTurnAngle
	if drivenTransition then
		baseState = desiredBaseState
		family = currentLocomotionFamily
		direction = currentDirection
		sprintTurn = currentSprintTurn
		sprintTurnAngle = 0
	else
		baseState, family, direction, sprintTurn, sprintTurnAngle = resolveBaseLocomotion(
			humanoid,
			locomotionState,
			movementAngle,
			speed,
			hasBall,
			deltaTime
		)
		desiredBaseState = baseState
	end

	local actionActive = updateActionLifecycle(speed, sprintRequested)

	--[[
		EXIT (§74).

		The transition has just finished. The body is now facing a completely
		different way from when it started, so the outgoing state must be chosen
		against the NEW facing and the CURRENT velocity rather than resumed from
		whatever was playing before the turn -- which is what made the exit snap
		into a directional jog that contradicted the body.

		Clearing the cached direction and family forces the next frame's selection
		to re-evaluate from scratch and to crossfade in, instead of assuming the
		clip already running is still the right one.
	]]
	if drivenTransition and not actionActive then
		currentDirection = "Forward"
		currentSprintTurn = "Forward"
		currentLocomotionFamily = "Default"
		sprintTurnCandidate = "Forward"
		sprintTurnCandidateAt = 0
		baseState, family, direction, sprintTurn, sprintTurnAngle = resolveBaseLocomotion(
			humanoid,
			locomotionState,
			movementAngle,
			speed,
			hasBall,
			deltaTime
		)
		desiredBaseState = baseState
	end

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
	sprintTurnCandidate = "Forward"
	sprintTurnCandidateAt = 0
	activeAction = ""
	activeActionUntil = 0
	activeActionExitAt = 0
	activeActionExitStarted = false
	desiredBaseState = "Idle"
	locomotionVisualActive = false
	jumpWasAirborne = false
	lastObservedControlEpoch = nil
	airborneCandidateAt = 0
	stopTrapArmed = false
	stopTrapPlayed = false
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
	loadTrack("ReceivePass", assets.Actions.ReceivePass, "B90_ACT_ReceivePass", receptionConfig.Priority, false)
	loadTrack("StopTrapPlaceholder", assets.Actions.ReceivePass, "B90_ACT_StopTrapPlaceholder", stopTrapConfig.Priority, false)
	loadTrack("Jump", assets.Locomotion.Jump, "B90_LOC_Jump", jumpConfig.Priority, false)
	loadTrack("Pass", assets.Actions.Pass, "B90_ACT_Pass", passConfig.Priority, false)
	loadTrack("Shoot", assets.Actions.Shoot, "B90_ACT_Shoot", shootConfig.Priority, false)

	--[[
		THE KEEPER SET.

		Loaded for every local footballer rather than only for goalkeepers,
		because the position can change between spawns and a keeper who is missing
		their clips falls back to an outfielder's idle -- which is precisely the
		"my animation does not use keeper animation" symptom. Five short clips
		cost far less than getting this wrong.

		These are the same assets the AI keepers already use, so a human keeper
		and a bot keeper are visually the same footballer.
	]]
	local keeperAssets = assets.Goalkeeper
	local keeperConfig = AnimationConfig.Goalkeeper
	if keeperAssets then
		loadTrack("KeeperIdle", keeperAssets.Idle, "B90_GK_Idle", keeperConfig.IdlePriority, true)
		loadTrack("KeeperIdleWithBall", keeperAssets.IdleWithBall, "B90_GK_IdleWithBall", keeperConfig.IdlePriority, true)
		loadTrack("KeeperSideStep", keeperAssets.SideStep, "B90_GK_SideStep", keeperConfig.MovementPriority, true)
		loadTrack("KeeperCatchStanding", keeperAssets.CatchStanding, "B90_GK_CatchStanding", keeperConfig.ActionPriority, false)
		loadTrack("KeeperThrowPass", keeperAssets.ThrowPass, "B90_GK_ThrowPass", keeperConfig.ActionPriority, false)
	end
	for slot, animationId in transitionAssets do
		local slotConfig = transitionConfig[slot]
		if slotConfig and slotConfig.Enabled ~= false then
			loadTrack(slot, animationId, "B90_LOC_" .. slot, slotConfig.Priority, false)
		end
	end
	table.clear(lastTransitionAt)
	reversalCandidateAt = 0
	previousMovingDirection = Vector3.zero
	local shootRecord = activeTracks.Shoot
	if shootRecord then
		table.insert(characterConnections, shootRecord.Track:GetMarkerReachedSignal("BallContact"):Connect(function()
			localPlayer:SetAttribute("Beyond90ShootBallContactMarkerObserved", true)
			FootballActionController.NotifyAnimationMarker("Shoot", "BallContact")
		end))
	end
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
