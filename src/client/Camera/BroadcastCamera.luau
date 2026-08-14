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
local smoothedPosition: Vector3? = nil
local smoothedFocus: Vector3? = nil
local smoothedFOV = config.BaseFOV
local lastAttributeSampleTime = 0

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

local function smoothVector(current: Vector3?, target: Vector3, responsiveness: number, deltaTime: number): Vector3
	if not current then
		return target
	end

	return current:Lerp(target, expAlpha(responsiveness, deltaTime))
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

	if horizontalVelocity.Magnitude <= 0.5 then
		return Vector3.zero
	end

	local direction = horizontalVelocity.Unit
	local speedLead = math.clamp(horizontalVelocity.Magnitude * config.SpeedLookAheadScale, 0, config.LookAheadDistance)
	local forwardBias = math.max(0, direction:Dot(pitchState.LengthAxis)) * 0

	return direction * (config.LookAheadDistance * 0.35 + speedLead + forwardBias)
end

local function clampAlongLength(position: Vector3, pitchState): Vector3
	local fromCenter = BallControlMath.GetHorizontal(position - pitchState.Center)
	local halfLength = pitchState.Length / 2 - config.LengthEdgePadding
	local lengthOffset = math.clamp(fromCenter:Dot(pitchState.LengthAxis), -halfLength, halfLength)
	local widthOffset = fromCenter:Dot(pitchState.WidthAxis)

	return pitchState.Center + pitchState.LengthAxis * lengthOffset + pitchState.WidthAxis * widthOffset
end

local function updateCamera(deltaTime: number)
	if not active then
		return
	end

	local camera = Workspace.CurrentCamera
	local rootPart = getCharacterRoot()

	if not camera or not rootPart then
		return
	end

	local pitchState = getPitchMetadata()
	if not pitchState then
		return
	end

	local ball = getFootball()
	local framingPoint = rootPart.Position
		+ getMovementLookAhead(rootPart, pitchState)
		+ getBoundedBallInfluence(rootPart, ball)
	framingPoint = clampAlongLength(framingPoint, pitchState)

	local sideSign = if config.BroadcastSide >= 0 then 1 else -1
	local fromCenter = BallControlMath.GetHorizontal(framingPoint - pitchState.Center)
	local lengthOffset = math.clamp(
		fromCenter:Dot(pitchState.LengthAxis),
		-(pitchState.Length / 2 - config.LengthEdgePadding),
		pitchState.Length / 2 - config.LengthEdgePadding
	)
	local railPosition = pitchState.Center
		+ pitchState.LengthAxis * lengthOffset
		+ pitchState.WidthAxis * sideSign * (pitchState.Width / 2 + config.SidelineDistance)
		+ Vector3.yAxis * (pitchState.GroundY + config.Height - pitchState.Center.Y)

	local focusTarget = Vector3.new(framingPoint.X, pitchState.GroundY + 3, framingPoint.Z)
	local ballSeparation = if ball then BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude else 0
	local playerSpeed = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity).Magnitude
	local targetFOV = math.clamp(
		config.BaseFOV + ballSeparation * config.BallSeparationZoomScale + playerSpeed * config.SpeedZoomScale,
		config.MinFOV,
		config.MaxFOV
	)

	smoothedPosition = smoothVector(smoothedPosition, railPosition, config.PositionResponsiveness, deltaTime)
	smoothedFocus = smoothVector(smoothedFocus, focusTarget, config.FocusResponsiveness, deltaTime)
	smoothedFOV += (targetFOV - smoothedFOV) * expAlpha(config.ZoomResponsiveness, deltaTime)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(smoothedPosition :: Vector3, smoothedFocus :: Vector3)
	camera.Focus = CFrame.new(smoothedFocus :: Vector3)
	camera.FieldOfView = smoothedFOV

	local now = os.clock()

	if now - lastAttributeSampleTime >= config.AttributeSampleInterval then
		lastAttributeSampleTime = now
		localPlayer:SetAttribute("Beyond90CameraMode", "Broadcast")
		localPlayer:SetAttribute("Beyond90CameraTargetDistance", ((smoothedPosition :: Vector3) - (smoothedFocus :: Vector3)).Magnitude)
		localPlayer:SetAttribute("Beyond90CameraFOV", smoothedFOV)
	end
end

function BroadcastCamera.Enable()
	if active then
		return
	end

	active = true
	smoothedPosition = nil
	smoothedFocus = nil
	smoothedFOV = config.BaseFOV
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
end

function BroadcastCamera.IsEnabled(): boolean
	return active
end

return BroadcastCamera
