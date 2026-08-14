local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local CameraConfig = require(Shared.Config.CameraConfig)
local GameConfig = require(Shared.Config.GameConfig)

local BroadcastCamera = {}

local localPlayer = Players.LocalPlayer
local config = CameraConfig.Broadcast
local renderConnection: RBXScriptConnection? = nil
local active = false
local selectedDistancePresetIndex = config.DefaultDistancePresetIndex or 1
local smoothedPosition: Vector3? = nil
local smoothedFocus: Vector3? = nil
local smoothedForward: Vector3? = nil
local smoothedFOV = config.BaseFOV
local lastAttributeSampleTime = 0
local fadedObstructionParts: { [BasePart]: number } = {}
local broadcastSideFadeParts: { [BasePart]: number } = {}
local broadcastSideFadeApplied = false
local getPitchOffsets

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

local function getCameraWeight(ball: BasePart?): number
	if ball
		and ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
	then
		return config.PlayerBallWeightControlled
	end

	return config.PlayerBallWeightFree
end

local function getBoundedBallInfluence(rootPart: BasePart, ball: BasePart?): Vector3
	if not ball then
		return Vector3.zero
	end

	local influence = BallControlMath.GetHorizontal(ball.Position - rootPart.Position) * (1 - getCameraWeight(ball))
	return BallControlMath.ClampMagnitude(influence, config.MaxBallInfluence)
end

local function getMovementLookAhead(rootPart: BasePart, pitchState): Vector3
	local horizontalVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local speedAlpha = math.clamp(horizontalVelocity.Magnitude / math.max(config.LookAheadReferenceSpeed, 1), 0, 1)

	if speedAlpha <= 0 then
		return Vector3.zero
	end

	speedAlpha = speedAlpha * speedAlpha * (3 - 2 * speedAlpha)
	local direction = BallControlMath.SafeUnit(horizontalVelocity, pitchState.LengthAxis)
	local attackBias = pitchState.LengthAxis
		* math.max(0, direction:Dot(pitchState.LengthAxis))
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

local function applySoftCompositionZone(target: Vector3, pitchState): Vector3
	if not smoothedFocus then
		return target
	end

	local previousLength, previousWidth = getPitchOffsets(smoothedFocus :: Vector3, pitchState)
	local targetLength, targetWidth = getPitchOffsets(target, pitchState)
	local lengthDelta = targetLength - previousLength
	local widthDelta = targetWidth - previousWidth

	if math.abs(lengthDelta) <= config.SoftZoneLength then
		targetLength = previousLength
	else
		targetLength -= sign(lengthDelta) * config.SoftZoneLength
	end

	if math.abs(widthDelta) <= config.SoftZoneWidth then
		targetWidth = previousWidth
	else
		targetWidth -= sign(widthDelta) * config.SoftZoneWidth
	end

	return positionFromOffsets(targetLength, targetWidth, pitchState)
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

local function updateCamera(deltaTime: number)
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
	local framingPoint = rootPart.Position
		+ getMovementLookAhead(rootPart, pitchState)
		+ getBoundedBallInfluence(rootPart, ball)

	framingPoint = clampTargetToPitch(framingPoint, pitchState, distanceScale)
	framingPoint = applySoftCompositionZone(framingPoint, pitchState)
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
	rigPosition = clampCameraToSafeCorridor(rigPosition, pitchState, distanceScale)
	rigPosition = resolveObstruction(focusTarget, rigPosition, pitchState, distanceScale, ball)

	local ballSeparation = if ball then BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude else 0
	local targetFOV = math.clamp(
		config.BaseFOV + math.max(0, ballSeparation - config.BallSeparationZoomDeadzone) * config.BallSeparationZoomScale,
		config.MinFOV,
		config.MaxFOV
	)

	smoothedPosition = smoothVector(smoothedPosition, rigPosition, config.PositionResponsiveness, deltaTime)
	smoothedFocus = smoothVector(smoothedFocus, focusTarget, config.FocusResponsiveness, deltaTime)
	smoothedFOV += (targetFOV - smoothedFOV) * expAlpha(config.ZoomResponsiveness, deltaTime)

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
		localPlayer:SetAttribute("Beyond90CameraMode", "Broadcast")
		localPlayer:SetAttribute("Beyond90CameraTargetDistance", ((smoothedPosition :: Vector3) - (smoothedFocus :: Vector3)).Magnitude)
		localPlayer:SetAttribute("Beyond90CameraFOV", smoothedFOV)
		localPlayer:SetAttribute("Beyond90CameraLengthOffset", cameraLengthOffset)
		localPlayer:SetAttribute("Beyond90CameraWidthOffset", cameraWidthOffset)
		localPlayer:SetAttribute("Beyond90CameraPlayerDistance", ((smoothedPosition :: Vector3) - rootPart.Position).Magnitude)
		localPlayer:SetAttribute("Beyond90CameraDistancePreset", preset.Name)
		localPlayer:SetAttribute("Beyond90CameraHeight", height)
		localPlayer:SetAttribute("Beyond90CameraDownAngle", math.deg(math.asin(math.clamp(-forward.Y, -1, 1))))

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
	smoothedForward = nil
	smoothedFOV = config.BaseFOV
	restoreSafeDefaultCamera()
	renderConnection = RunService.RenderStepped:Connect(updateCamera)
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
	smoothedForward = nil
	clearObstructionFade()
	clearBroadcastSideFade()
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
