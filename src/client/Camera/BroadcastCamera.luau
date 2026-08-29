local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local CameraConfig = require(Shared.Config.CameraConfig)
local MatchRulesConfig = require(ReplicatedStorage.Shared.Config.MatchRulesConfig)
local GameConfig = require(Shared.Config.GameConfig)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)

local BroadcastCamera = {}

local localPlayer = Players.LocalPlayer
local profileName = "Broadcast1"
local config = CameraConfig.Broadcast1 or CameraConfig.Broadcast
local renderConnection: RBXScriptConnection? = nil
local active = false
local selectedDistancePresetIndex = config.DefaultDistancePresetIndex or 1
local smoothedPosition: Vector3? = nil
local smoothedFocus: Vector3? = nil
local followAnchor: Vector3? = nil
local smoothedForward: Vector3? = nil
local smoothedFOV = config.BaseFOV
local targetHistory = {}
local safetyCatchupBlend = 0
local cameraVelocity = Vector3.zero
local focusVelocity = Vector3.zero
local lastAttributeSampleTime = 0
local fadedObstructionParts: { [BasePart]: number } = {}
local broadcastSideFadeParts: { [BasePart]: number } = {}
local broadcastSideFadeApplied = false
local getPitchOffsets
local joinIntroStartedAt: number? = nil

local function getFootball(): BasePart?
	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = rootFolder and rootFolder:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)

	if ball and ball:IsA("BasePart") then
		return ball
	end

	return nil
end

local function getCharacterRoot(): BasePart?
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function restoreSafeDefaultCamera()
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if camera then
		camera.CameraType = Enum.CameraType.Custom

		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function getPitchMetadata()
	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local pitchFolder = rootFolder and rootFolder:FindFirstChild("Pitch")
	local gameplayBounds = pitchFolder and pitchFolder:FindFirstChild("GameplayBounds")

	if gameplayBounds and gameplayBounds:IsA("BasePart") then
		local center = gameplayBounds:GetAttribute("PitchCenter")
		local lengthAxis = gameplayBounds:GetAttribute("PitchLengthAxis")
		local widthAxis = gameplayBounds:GetAttribute("PitchWidthAxis")
		local length = gameplayBounds:GetAttribute("PitchLength")
		local width = gameplayBounds:GetAttribute("PitchWidth")
		local groundY = gameplayBounds:GetAttribute("PitchGroundY")

		if typeof(center) == "Vector3"
			and typeof(lengthAxis) == "Vector3"
			and typeof(widthAxis) == "Vector3"
			and typeof(length) == "number"
			and typeof(width) == "number"
			and typeof(groundY) == "number"
		then
			return {
				Center = center,
				LengthAxis = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(lengthAxis), Vector3.new(0, 0, 1)),
				WidthAxis = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(widthAxis), Vector3.new(1, 0, 0)),
				Length = length,
				Width = width,
				GroundY = groundY,
			}
		end
	end

	return nil
end

local function expAlpha(responsiveness: number, deltaTime: number): number
	return 1 - math.exp(-responsiveness * deltaTime)
end

local function sign(value: number): number
	return if value >= 0 then 1 else -1
end

local function smoothVector(current: Vector3?, target: Vector3, responsiveness: number, deltaTime: number): Vector3
	if not current then
		return target
	end

	return current:Lerp(target, expAlpha(responsiveness, deltaTime))
end

local function clampMagnitude(vector: Vector3, maximum: number): Vector3
	if vector.Magnitude <= maximum then
		return vector
	end
	return vector.Unit * maximum
end

local function smoothLimitedVector(
	current: Vector3?,
	target: Vector3,
	velocity: Vector3,
	responsiveness: number,
	maxAcceleration: number,
	maxSpeed: number,
	deltaTime: number
): (Vector3, Vector3)
	if not current then
		return target, Vector3.zero
	end
	local offset = target - current
	local desiredVelocity = clampMagnitude(offset * responsiveness, maxSpeed)
	local velocityDelta = desiredVelocity - velocity
	velocity += clampMagnitude(velocityDelta, maxAcceleration * deltaTime)
	local step = velocity * deltaTime
	if step.Magnitude >= offset.Magnitude and step:Dot(offset) > 0 then
		return target, Vector3.zero
	end
	return current + step, velocity
end

local function updateObstructionFade(blockingParts: { BasePart })
	local stillBlocking: { [BasePart]: boolean } = {}

	for _, part in blockingParts do
		if broadcastSideFadeParts[part] ~= nil then
			continue
		end

		stillBlocking[part] = true

		if fadedObstructionParts[part] == nil then
			fadedObstructionParts[part] = part.LocalTransparencyModifier
		end

		part.LocalTransparencyModifier = math.max(part.LocalTransparencyModifier, config.ObstructionTransparency)
	end

	for part, transparency in fadedObstructionParts do
		if not stillBlocking[part] then
			if part.Parent then
				part.LocalTransparencyModifier = transparency
			end

			fadedObstructionParts[part] = nil
		end
	end
end

local function clearObstructionFade()
	for part, transparency in fadedObstructionParts do
		if part.Parent then
			part.LocalTransparencyModifier = transparency
		end
	end

	table.clear(fadedObstructionParts)
end

local function clearBroadcastSideFade()
	for part, transparency in broadcastSideFadeParts do
		if part.Parent then
			part.LocalTransparencyModifier = transparency
		end
	end

	table.clear(broadcastSideFadeParts)
	broadcastSideFadeApplied = false
end

local function applyBroadcastSideFade(pitchState)
	if broadcastSideFadeApplied or not config.BroadcastSideFadeEnabled then
		return
	end

	broadcastSideFadeApplied = true

	local sideSign = if config.BroadcastSide >= 0 then 1 else -1
	local sideThreshold = sideSign * (pitchState.Width / 2 - config.BroadcastSideFadeInfieldMargin)
	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local excludedRoot = rootFolder and rootFolder:FindFirstChild("Pitch")

	local ball = getFootball()

	for _, descendant in Workspace:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		if localPlayer.Character and descendant:IsDescendantOf(localPlayer.Character) then
			continue
		end

		if excludedRoot and descendant:IsDescendantOf(excludedRoot) then
			continue
		end

		if ball and descendant == ball then
			continue
		end

		local _, widthOffset = getPitchOffsets(descendant.Position, pitchState)
		local isOnCameraSide = if sideSign < 0 then widthOffset <= sideThreshold else widthOffset >= sideThreshold

		if isOnCameraSide then
			broadcastSideFadeParts[descendant] = descendant.LocalTransparencyModifier
			descendant.LocalTransparencyModifier = math.max(descendant.LocalTransparencyModifier, config.BroadcastSideFadeTransparency)
		end
	end
end

local function getCurrentPreset()
	local presets = config.DistancePresets
	local preset = presets and presets[selectedDistancePresetIndex]

	if preset then
		return preset
	end

	return {
		Name = "1.00x",
		DistanceScale = 1,
	}
end

local function hasLocalPossession(ball: BasePart?): boolean
	return ball ~= nil
		and ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
end

--[[
	How strongly does the camera hold the CONTROLLED PLAYER? (§61)

	On the ball: firmly, because the player and the football are the same
	subject.

	Off the ball: the football is the subject, and increasingly so the further
	away the play is -- but never completely, so the player can still locate
	themselves relative to it (§62).
]]
local function getCameraWeight(rootPart: BasePart, ball: BasePart?): number
	if hasLocalPossession(ball) then
		return config.PlayerBallWeightControlled
	end
	if not ball then
		return config.PlayerBallWeightFree
	end

	local distance = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude
	local alpha = math.clamp(distance / math.max(config.OffBallDistanceFull or 1, 1e-3), 0, 1)
	local floor = config.OffBallMinimumPlayerWeight or config.PlayerBallWeightFree
	return config.PlayerBallWeightFree + (floor - config.PlayerBallWeightFree) * alpha
end

local function getBoundedBallInfluence(rootPart: BasePart, ball: BasePart?): Vector3
	if not ball then
		return Vector3.zero
	end

	local influence = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
		* (1 - getCameraWeight(rootPart, ball))
	-- Off the ball the camera is allowed to travel much further toward the
	-- play; on the ball the tighter clamp keeps the carrier framed.
	local limit = if hasLocalPossession(ball)
		then config.MaxBallInfluence
		else (config.MaxBallInfluenceOffBall or config.MaxBallInfluence)
	return BallControlMath.ClampMagnitude(influence, limit)
end

local function getAttackingGoalContext(pitchState)
	local goalId = localPlayer:GetAttribute(FootballTeamConfig.AttackingGoalAttributeName)
	local stadium = Workspace:FindFirstChild("StadiumDevelopment")
	local goalBounds = stadium and stadium:FindFirstChild("GoalBounds")
	local goal = goalBounds and typeof(goalId) == "string" and goalBounds:FindFirstChild(goalId .. "GoalBounds")
	local goalPosition = if goal and goal:IsA("BasePart") then goal.Position else nil
	if not goalPosition then
		return pitchState.LengthAxis, nil, 0
	end
	local attackDirection = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(goalPosition - pitchState.Center), pitchState.LengthAxis)
	return attackDirection, goalPosition, 1
end

local function getMovementLookAhead(rootPart: BasePart, pitchState, attackingDirection: Vector3): Vector3
	local horizontalVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local speedAlpha = math.clamp(horizontalVelocity.Magnitude / math.max(config.LookAheadReferenceSpeed, 1), 0, 1)

	if speedAlpha <= 0 then
		return Vector3.zero
	end

	speedAlpha = speedAlpha * speedAlpha * (3 - 2 * speedAlpha)
	local direction = BallControlMath.SafeUnit(horizontalVelocity, pitchState.LengthAxis)
	local attackBias = attackingDirection
		* math.max(0, direction:Dot(attackingDirection))
		* config.AttackingLookAheadDistance
		* speedAlpha

	return direction * config.LookAheadDistance * speedAlpha + attackBias
end

function getPitchOffsets(position: Vector3, pitchState): (number, number)
	local fromCenter = BallControlMath.GetHorizontal(position - pitchState.Center)
	return fromCenter:Dot(pitchState.LengthAxis), fromCenter:Dot(pitchState.WidthAxis)
end

local function positionFromOffsets(lengthOffset: number, widthOffset: number, pitchState): Vector3
	return pitchState.Center
		+ pitchState.LengthAxis * lengthOffset
		+ pitchState.WidthAxis * widthOffset
end

local function clampTargetToPitch(position: Vector3, pitchState, distanceScale: number): Vector3
	local lengthOffset, widthOffset = getPitchOffsets(position, pitchState)
	local halfWidth = (pitchState.Width / 2) * config.TargetWidthClampScale / math.max(distanceScale, 0.01)
	local halfLength = (pitchState.Length / 2) * config.TargetLengthClampScale / math.max(distanceScale, 0.01)
	lengthOffset = math.clamp(lengthOffset, -halfLength, halfLength)
	widthOffset = math.clamp(widthOffset, -halfWidth, halfWidth)

	return positionFromOffsets(lengthOffset, widthOffset, pitchState)
end

local function updateFollowAnchor(target: Vector3, pitchState, deltaTime: number, safetyBlend: number): Vector3
	if not followAnchor then
		followAnchor = target
		return target
	end

	local previousLength, previousWidth = getPitchOffsets(followAnchor :: Vector3, pitchState)
	local targetLength, targetWidth = getPitchOffsets(target, pitchState)
	local lengthDelta = targetLength - previousLength
	local widthDelta = targetWidth - previousWidth
	local desiredLength = previousLength
	local desiredWidth = previousWidth

	if math.abs(lengthDelta) > config.FollowDeadZoneLength then
		desiredLength = targetLength - sign(lengthDelta) * config.FollowDeadZoneLength
	end

	if math.abs(widthDelta) > config.FollowDeadZoneWidth then
		desiredWidth = targetWidth - sign(widthDelta) * config.FollowDeadZoneWidth
	end

	local desired = positionFromOffsets(desiredLength, desiredWidth, pitchState)
	local lag = BallControlMath.GetHorizontal(target - desired)
	if lag.Magnitude > config.MaxTargetLag then
		desired = target - lag.Unit * config.MaxTargetLag
	end

	local currentLag = BallControlMath.GetHorizontal(target - (followAnchor :: Vector3)).Magnitude
	local baseResponsiveness = if currentLag >= config.CatchupDistance
		then config.CatchupResponsiveness
		else config.FollowResponsiveness
	local responsiveness = baseResponsiveness
		+ (config.SafetyCatchupResponsiveness - baseResponsiveness) * safetyBlend
	followAnchor = smoothVector(followAnchor, desired, responsiveness, deltaTime)
	return followAnchor :: Vector3
end

local function getDelayedFramingTarget(target: Vector3, deltaTime: number): (Vector3, number)
	local now = os.clock()
	table.insert(targetHistory, { Time = now, Position = target })
	local oldestAllowed = now - config.TargetHistorySeconds
	while #targetHistory > 2 and targetHistory[2].Time < oldestAllowed do
		table.remove(targetHistory, 1)
	end

	local delayed = targetHistory[1].Position
	local cutoff = now - config.FollowDelaySeconds
	for index = #targetHistory, 1, -1 do
		local sample = targetHistory[index]
		if sample.Time <= cutoff then
			delayed = sample.Position
			break
		end
	end

	local separation = BallControlMath.GetHorizontal(target - delayed).Magnitude
	local targetSafetyBlend = math.clamp(
		(separation - config.SafetyCatchupDistance)
			/ math.max(config.SafetyCatchupFullDistance - config.SafetyCatchupDistance, 0.01),
		0,
		1
	)
	targetSafetyBlend = targetSafetyBlend * targetSafetyBlend * (3 - 2 * targetSafetyBlend)
	safetyCatchupBlend += (targetSafetyBlend - safetyCatchupBlend)
		* expAlpha(config.SafetyBlendResponsiveness, deltaTime)
	return delayed:Lerp(target, safetyCatchupBlend), safetyCatchupBlend
end

local function clampCameraToSafeCorridor(position: Vector3, pitchState, distanceScale: number): Vector3
	local lengthOffset, widthOffset = getPitchOffsets(position, pitchState)
	local sideSign = if config.BroadcastSide >= 0 then 1 else -1
	local maxOutside = config.MaxOutsideSidelineDistance * distanceScale
	local minWidth
	local maxWidth

	if sideSign < 0 then
		minWidth = -pitchState.Width / 2 - maxOutside
		maxWidth = pitchState.Width / 2 - config.FarSideInfieldPadding
	else
		minWidth = -pitchState.Width / 2 + config.FarSideInfieldPadding
		maxWidth = pitchState.Width / 2 + maxOutside
	end

	lengthOffset = math.clamp(
		lengthOffset,
		-pitchState.Length / 2 + config.LengthCameraPadding,
		pitchState.Length / 2 - config.LengthCameraPadding
	)
	widthOffset = math.clamp(widthOffset, minWidth, maxWidth)

	local horizontal = positionFromOffsets(lengthOffset, widthOffset, pitchState)
	return Vector3.new(horizontal.X, position.Y, horizontal.Z)
end

local function resolveObstruction(focus: Vector3, desiredPosition: Vector3, pitchState, distanceScale: number, ball: BasePart?): Vector3
	if not config.ObstructionRaycastEnabled then
		return desiredPosition
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {}

	if localPlayer.Character then
		table.insert(excluded, localPlayer.Character)
	end

	if ball then
		table.insert(excluded, ball)
	end

	raycastParams.FilterDescendantsInstances = excluded
	raycastParams.IgnoreWater = true

	local function collectBlockingParts(position: Vector3): { BasePart }
		local direction = position - focus
		local blockingParts = {}

		if direction.Magnitude <= 0 then
			return blockingParts
		end

		local dynamicExcluded = table.clone(excluded)
		local probeLimit = config.ObstructionProbeLimit or 8

		for _ = 1, probeLimit do
			raycastParams.FilterDescendantsInstances = dynamicExcluded
			local result = Workspace:Raycast(focus, direction, raycastParams)

			if not result then
				break
			end

			local instance = result.Instance

			if instance:IsA("BasePart") then
				table.insert(blockingParts, instance)
				table.insert(dynamicExcluded, instance)
			else
				break
			end
		end

		return blockingParts
	end

	local desiredBlockingParts = collectBlockingParts(desiredPosition)

	if #desiredBlockingParts == 0 then
		updateObstructionFade({})
		return desiredPosition
	end

	if config.ObstructionFadeEnabled then
		updateObstructionFade(desiredBlockingParts)
		return desiredPosition
	end

	local lift = config.ObstructionLift
	local liftSteps = config.ObstructionLiftSteps or 1

	for step = 1, liftSteps do
		local elevated = clampCameraToSafeCorridor(
			desiredPosition + Vector3.yAxis * lift * step,
			pitchState,
			distanceScale
		)

		if #collectBlockingParts(elevated) == 0 then
			return elevated
		end
	end

	local direction = desiredPosition - focus

	if direction.Magnitude <= 0 then
		return desiredPosition
	end

	local result = Workspace:Raycast(focus, direction, raycastParams)

	if not result then
		return desiredPosition
	end

	local safeDistance = math.max(result.Distance - config.ObstructionBackoff, config.MinimumObstructionDistance)
	local corrected = focus + direction.Unit * safeDistance + Vector3.yAxis * config.ObstructionLift
	return clampCameraToSafeCorridor(corrected, pitchState, distanceScale)
end

--[[
	AUTHORITATIVE REPOSITION CATCH-UP (§64).

	When the rules teleport the controlled footballer for a restart, the ordinary
	Broadcast smoothing -- which is deliberately slow, because that is what makes
	it feel like a camera operator rather than a follow cam -- spent a long time
	drifting across the pitch to find them again.

	The server bumps a reposition epoch on the character whenever it moves them
	authoritatively. That is the signal this watches for: a brief, strongly
	boosted catch-up, then straight back to normal. Nothing about ordinary
	Broadcast1 / Broadcast2 smoothing is changed.
]]
local repositionBoostUntil = 0
local repositionEpoch: number? = nil
local repositionConnection: RBXScriptConnection? = nil
local repositionWatchedCharacter: Model? = nil

local function watchRepositionEpoch(character: Model?)
	if character == repositionWatchedCharacter then
		return
	end
	if repositionConnection then
		repositionConnection:Disconnect()
		repositionConnection = nil
	end
	repositionWatchedCharacter = character
	repositionEpoch = nil
	if not character then
		return
	end
	local attribute = MatchRulesConfig.RepositionEpochAttributeName
	repositionEpoch = character:GetAttribute(attribute)
	repositionConnection = character:GetAttributeChangedSignal(attribute):Connect(function()
		local value = character:GetAttribute(attribute)
		if typeof(value) ~= "number" then
			return
		end
		-- Only a CHANGE counts, so simply joining a match does not trigger it.
		if repositionEpoch ~= nil and value ~= repositionEpoch then
			repositionBoostUntil = os.clock() + CameraConfig.Reposition.DurationSeconds
		end
		repositionEpoch = value
	end)
end

--[[
	Scale factors for this frame: (responsiveness, acceleration, shouldSnap).
	Both are 1 in ordinary play, which is what keeps normal smoothing intact.
]]
local function getRepositionBoost(currentPosition: Vector3?, targetPosition: Vector3): (number, number, boolean)
	local config = CameraConfig.Reposition
	if config.Enabled ~= true or os.clock() >= repositionBoostUntil then
		return 1, 1, false
	end
	--[[
		A displacement this large cannot be interpolated without reading as a whip
		pan across the stadium, so the camera cuts instead.
	]]
	local snap = currentPosition ~= nil
		and (targetPosition - currentPosition).Magnitude >= config.SnapDistance
	return config.ResponsivenessScale, config.AccelerationScale, snap
end

local function updateCamera(deltaTime: number)
	watchRepositionEpoch(Players.LocalPlayer.Character)
	if not active then
		return
	end

	local camera = Workspace.CurrentCamera
	local rootPart = getCharacterRoot()

	if not camera or not rootPart then
		restoreSafeDefaultCamera()
		return
	end

	local pitchState = getPitchMetadata()
	if not pitchState then
		restoreSafeDefaultCamera()
		return
	end

	local ball = getFootball()
	local preset = getCurrentPreset()
	local distanceScale = preset.DistanceScale or 1
	local attackingDirection, attackingGoalPosition = getAttackingGoalContext(pitchState)
	local attackingProgress = math.clamp(
		BallControlMath.GetHorizontal(rootPart.Position - pitchState.Center):Dot(attackingDirection)
			/ math.max(pitchState.Length / 2, 1),
		-1,
		1
	)
	local goalBiasAlpha = math.clamp(
		(attackingProgress - (config.GoalBiasStartProgress or 0))
			/ math.max((config.GoalBiasFullProgress or 0.82) - (config.GoalBiasStartProgress or 0), 0.01),
		0,
		1
	)
	goalBiasAlpha = goalBiasAlpha ^ (config.GoalBiasCurveExponent or 1)
	local framingPoint = rootPart.Position
		+ getMovementLookAhead(rootPart, pitchState, attackingDirection)
		+ getBoundedBallInfluence(rootPart, ball)
		+ attackingDirection * (config.AttackingGoalTargetBias or 0) * goalBiasAlpha

	framingPoint = clampTargetToPitch(framingPoint, pitchState, distanceScale)
	local rawFramingPoint = framingPoint
	local safetyBlend
	framingPoint, safetyBlend = getDelayedFramingTarget(framingPoint, deltaTime)
	framingPoint = updateFollowAnchor(framingPoint, pitchState, deltaTime, safetyBlend)
	framingPoint = clampTargetToPitch(framingPoint, pitchState, distanceScale)

	local sideSign = if config.BroadcastSide >= 0 then 1 else -1
	local lengthOffset, widthOffset = getPitchOffsets(framingPoint, pitchState)
	local cameraLengthOffset = lengthOffset * config.LengthFollowStrength
	local cameraWidthOffset = sideSign * (pitchState.Width / 2 + config.SidelineDistance * distanceScale)
		+ widthOffset * config.WidthFollowStrength
	local cameraHorizontalPosition = positionFromOffsets(cameraLengthOffset, cameraWidthOffset, pitchState)
	local height = config.Height * (0.94 + distanceScale * 0.06)
	local rigPosition = cameraHorizontalPosition
		+ Vector3.yAxis * (pitchState.GroundY + height - pitchState.Center.Y)
	local focusTarget = Vector3.new(framingPoint.X, pitchState.GroundY + config.FocusHeight, framingPoint.Z)
	if attackingGoalPosition and (config.AttackingGoalFocusBlend or 0) > 0 then
		local goalFocus = Vector3.new(attackingGoalPosition.X, pitchState.GroundY + config.FocusHeight, attackingGoalPosition.Z)
		focusTarget = focusTarget:Lerp(goalFocus, (config.AttackingGoalFocusBlend or 0) * goalBiasAlpha)
	end
	rigPosition = clampCameraToSafeCorridor(rigPosition, pitchState, distanceScale)
	rigPosition = resolveObstruction(focusTarget, rigPosition, pitchState, distanceScale, ball)

	local ballSeparation = if ball then BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude else 0
	local fieldProgress = math.clamp(math.abs(lengthOffset) / math.max(pitchState.Length / 2, 1), 0, 1)
	local dangerAlpha = math.clamp((fieldProgress - 0.58) / 0.32, 0, 1)
	dangerAlpha = dangerAlpha * dangerAlpha * (3 - 2 * dangerAlpha)
	local contextualFOV = (config.OpenPlayFOVBoost or 0) * (1 - dangerAlpha)
		- (config.GoalAreaFOVReduction or 0) * dangerAlpha
	local targetFOV = math.clamp(
		config.BaseFOV
			+ contextualFOV
			+ math.max(0, ballSeparation - config.BallSeparationZoomDeadzone) * config.BallSeparationZoomScale,
		config.MinFOV,
		config.MaxFOV
	)
	local joinIntro = config.JoinIntro
	local joinIntroActive = false
	if joinIntroStartedAt and joinIntro then
		local progress = math.clamp((os.clock() - joinIntroStartedAt) / joinIntro.Duration, 0, 1)
		local eased = progress * progress * progress * (progress * (progress * 6 - 15) + 10)
		rigPosition += Vector3.yAxis * joinIntro.SkyHeight * (1 - eased)
		targetFOV = joinIntro.StartFOV + (targetFOV - joinIntro.StartFOV) * eased
		joinIntroActive = true
		if progress >= 1 then joinIntroStartedAt = nil end
	end

	if joinIntroActive then
		-- The reveal owns its path so it reaches the live rig with zero positional gap.
		smoothedPosition = rigPosition
		smoothedFocus = focusTarget
		smoothedFOV = targetFOV
		cameraVelocity = Vector3.zero
		focusVelocity = Vector3.zero
	else
		local responsivenessScale, accelerationScale, shouldSnap =
			getRepositionBoost(smoothedPosition, rigPosition)

		if shouldSnap then
			-- Extreme displacement: cut rather than whip-pan across the stadium.
			smoothedPosition = rigPosition
			smoothedFocus = focusTarget
			cameraVelocity = Vector3.zero
			focusVelocity = Vector3.zero
		else
			smoothedPosition, cameraVelocity = smoothLimitedVector(
				smoothedPosition,
				rigPosition,
				cameraVelocity,
				config.PositionResponsiveness * responsivenessScale,
				config.PositionMaxAcceleration * accelerationScale,
				config.PositionMaxSpeed * accelerationScale,
				deltaTime
			)
			smoothedFocus, focusVelocity = smoothLimitedVector(
				smoothedFocus,
				focusTarget,
				focusVelocity,
				config.FocusResponsiveness * responsivenessScale,
				config.FocusMaxAcceleration * accelerationScale,
				config.FocusMaxSpeed * accelerationScale,
				deltaTime
			)
		end
		smoothedFOV += (targetFOV - smoothedFOV)
			* expAlpha(config.ZoomResponsiveness * responsivenessScale, deltaTime)
	end

	local desiredForward = BallControlMath.SafeUnit((smoothedFocus :: Vector3) - (smoothedPosition :: Vector3), camera.CFrame.LookVector)
	smoothedForward = smoothVector(smoothedForward, desiredForward, config.OrientationResponsiveness, deltaTime)
	local forward = BallControlMath.SafeUnit(smoothedForward :: Vector3, desiredForward)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(smoothedPosition :: Vector3, (smoothedPosition :: Vector3) + forward)
	camera.Focus = CFrame.new(smoothedFocus :: Vector3)
	camera.FieldOfView = smoothedFOV

	local now = os.clock()

	if now - lastAttributeSampleTime >= config.AttributeSampleInterval then
		lastAttributeSampleTime = now
		localPlayer:SetAttribute("Beyond90CameraMode", profileName)
		localPlayer:SetAttribute("Beyond90CameraTargetDistance", ((smoothedPosition :: Vector3) - (smoothedFocus :: Vector3)).Magnitude)
		localPlayer:SetAttribute("Beyond90CameraFOV", smoothedFOV)
		localPlayer:SetAttribute("Beyond90CameraLengthOffset", cameraLengthOffset)
		localPlayer:SetAttribute("Beyond90CameraWidthOffset", cameraWidthOffset)
		localPlayer:SetAttribute("Beyond90CameraPlayerDistance", ((smoothedPosition :: Vector3) - rootPart.Position).Magnitude)
		localPlayer:SetAttribute("Beyond90CameraDistancePreset", preset.Name)
		localPlayer:SetAttribute("Beyond90CameraHeight", height)
		localPlayer:SetAttribute("Beyond90CameraDownAngle", math.deg(math.asin(math.clamp(-forward.Y, -1, 1))))
		localPlayer:SetAttribute("Beyond90CameraFollowLag", BallControlMath.GetHorizontal(rawFramingPoint - framingPoint).Magnitude)
		localPlayer:SetAttribute("Beyond90CameraFollowDeadZone", config.FollowDeadZoneLength)
		localPlayer:SetAttribute("Beyond90CameraFollowDelaySeconds", config.FollowDelaySeconds)
		localPlayer:SetAttribute("Beyond90CameraSafetyCatchup", safetyBlend > 0.01)
		localPlayer:SetAttribute("Beyond90CameraSafetyCatchupBlend", safetyBlend)
		localPlayer:SetAttribute("Beyond90CameraAttackingGoalBias", goalBiasAlpha)

		local head = localPlayer.Character and localPlayer.Character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local rootScreen = camera:WorldToViewportPoint(rootPart.Position)
			local headScreen = camera:WorldToViewportPoint(head.Position)
			localPlayer:SetAttribute("Beyond90ApproxPlayerScreenHeight", math.abs(headScreen.Y - rootScreen.Y) * 2)
		end
	end
end

function BroadcastCamera.Enable()
	if active then
		return
	end

	active = true
	smoothedPosition = nil
	smoothedFocus = nil
	followAnchor = nil
	smoothedForward = nil
	smoothedFOV = config.BaseFOV
	table.clear(targetHistory)
	safetyCatchupBlend = 0
	cameraVelocity = Vector3.zero
	focusVelocity = Vector3.zero
	restoreSafeDefaultCamera()
	renderConnection = RunService.RenderStepped:Connect(updateCamera)
end

function BroadcastCamera.PlayJoinIntro()
	if active and profileName == "Broadcast1" and config.JoinIntro then
		joinIntroStartedAt = os.clock()
		smoothedPosition = nil
		smoothedFocus = nil
		smoothedForward = nil
		smoothedFOV = config.JoinIntro.StartFOV
	end
end

function BroadcastCamera.Disable()
	if not active then
		return
	end

	active = false

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	smoothedPosition = nil
	smoothedFocus = nil
	followAnchor = nil
	smoothedForward = nil
	table.clear(targetHistory)
	safetyCatchupBlend = 0
	cameraVelocity = Vector3.zero
	focusVelocity = Vector3.zero
	clearObstructionFade()
	clearBroadcastSideFade()
end

function BroadcastCamera.SetProfile(nextProfileName: string)
	local nextConfig = CameraConfig[nextProfileName]
	if typeof(nextConfig) ~= "table" then
		return false
	end
	profileName = nextProfileName
	config = nextConfig
	selectedDistancePresetIndex = math.clamp(
		selectedDistancePresetIndex,
		1,
		math.max(#(config.DistancePresets or {}), 1)
	)
	return true
end

function BroadcastCamera.GetProfile(): string
	return profileName
end

function BroadcastCamera.IsEnabled(): boolean
	return active
end

function BroadcastCamera.CycleDistancePreset(): string
	local presets = config.DistancePresets or {}

	if #presets <= 0 then
		return "1.00x"
	end

	selectedDistancePresetIndex += 1

	if selectedDistancePresetIndex > #presets then
		selectedDistancePresetIndex = 1
	end

	return BroadcastCamera.GetDistancePresetLabel()
end

function BroadcastCamera.GetDistancePresetLabel(): string
	local preset = getCurrentPreset()
	return preset.Name or string.format("%.2fx", preset.DistanceScale or 1)
end

function BroadcastCamera.GetDistancePresetIndex(): number
	return selectedDistancePresetIndex
end

return BroadcastCamera
