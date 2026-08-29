--!strict
--[[
	PRO CAMERA.

	Beyond 90's player-perspective camera, presented to the player as PRO CAMERA
	and modelled on a Pro Clubs player camera: what ONE footballer on the pitch
	sees, as opposed to the Broadcast Camera's view of the match.

	This file used to be a thin wrapper around Roblox's stock follow camera --
	`CameraType = Custom` with the humanoid as the subject, plus a mouse lock.
	AGENTS.md rules that out in as many words:

		"It should NOT simply be CameraType = Follow ... or a basic camera
		 attached directly behind the player's avatar. It should be its own
		 camera system."

	and the stock camera failed the football test in practice: it framed the
	avatar and nothing else, so the football was regularly off-screen, there was
	no anticipation of where play was going, and the mode read as a generic
	Roblox third-person game.

	What it does instead, and why each part earns its place:

	  ELEVATED AND ANGLED DOWN
	      At eye level a footballer sees a wall of grass. Lifting the camera and
	      tilting it down is what makes the pitch ahead legible -- the same
	      reason the Broadcast Camera is elevated, applied at player scale.

	  FOCUSED AHEAD, BIASED TOWARD THE BALL
	      The camera looks at a point in front of the footballer rather than at
	      them, pulled part of the way toward the football. That is what keeps
	      the ball in frame without ever letting the player leave it -- and the
	      pull is bounded in studs, because losing yourself off the bottom of the
	      frame is worse than losing the ball off the top.

	  POSSESSION-AWARE
	      On the ball it tucks in close and low, where control, dribbling and
	      shooting read best. Off the ball it lifts and pulls back, because the
	      job has changed from touching the ball to reading where to run.

	  SETTLED, NOT GLUED
	      The yaw follows the DIRECTION OF PLAY -- movement while running, the
	      way to the ball while standing -- not the avatar's instantaneous
	      facing. A dribble touch or a body feint must not swing the whole view.

	Mouse look, when the cursor is locked, overrides the automatic yaw and pitch
	entirely. That is the whole point of the locked mode: the player is aiming
	the camera themselves.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local CameraConfig = require(Shared.Config.CameraConfig)
local GameConfig = require(Shared.Config.GameConfig)
local BallControlMath = require(Shared.Football.BallControlMath)

local ThirdPersonCamera = {}

local localPlayer = Players.LocalPlayer
local config = CameraConfig.ThirdPerson
local active = false
local characterAddedConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local mouseLocked = false
local previousMouseBehavior: Enum.MouseBehavior? = nil

-- Smoothed camera state. Nil until the first frame, so the camera starts where
-- it belongs instead of easing in from wherever the previous mode left it.
local currentPosition: Vector3? = nil
local currentFocus: Vector3? = nil
local currentYaw = 0
local currentPitch = config.OnBall.Pitch
local currentFOV = config.OnBall.FOV
local currentRig = {
	Distance = config.OnBall.Distance,
	Height = config.OnBall.Height,
	Pitch = config.OnBall.Pitch,
	FOV = config.OnBall.FOV,
	LookAhead = config.OnBall.LookAhead,
}
local mouseYaw = 0
local mousePitch = config.OnBall.Pitch

local function getCurrentHumanoid(): Humanoid?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function getRootPart(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getFootball(): BasePart?
	local container = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = container and container:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)
	return if ball and ball:IsA("BasePart") then ball else nil
end

local function hasLocalPossession(ball: BasePart?): boolean
	return ball ~= nil
		and ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
end

local function expAlpha(responsiveness: number, deltaTime: number): number
	return 1 - math.exp(-math.max(responsiveness, 0) * deltaTime)
end

-- Shortest-path angular interpolation, so crossing the +/-pi seam does not spin
-- the camera the long way round.
local function lerpAngle(from: number, to: number, alpha: number): number
	local delta = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + delta * alpha
end

--[[
	Is this a small screen?

	Judged from the viewport rather than from TouchEnabled, because the thing
	that actually breaks the framing is vertical pixels -- a phone in landscape
	has roughly a third of a desktop's, and the desktop framing there shows the
	footballer and almost nothing else.
]]
local function isSmallViewport(camera: Camera): boolean
	return camera.ViewportSize.Y <= 500
end

--[[
	WHERE IS PLAY GOING?

	Movement while the footballer is actually running, and the direction of the
	football while they are standing still. Deliberately NOT the avatar's facing:
	facing changes on every touch and every feint, and a camera that tracked it
	would swing constantly during ordinary dribbling.
]]
local function getPlayDirection(rootPart: BasePart, ball: BasePart?): Vector3
	local velocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	if velocity.Magnitude >= config.MovementYawMinimumSpeed then
		return velocity.Unit
	end
	if ball then
		local toBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
		if toBall.Magnitude > 3 then
			return toBall.Unit
		end
	end
	return BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
		Vector3.zAxis
	)
end

local function updateCamera(deltaTime: number)
	local camera = Workspace.CurrentCamera
	local rootPart = getRootPart()
	if not camera or not rootPart then
		return
	end
	local ball = getFootball()
	local onBall = hasLocalPossession(ball)

	--[[
		The rig morphs between the on-ball and off-ball presets rather than
		switching, so winning or losing the ball is a settle rather than a lurch.
	]]
	local targetRig = if onBall then config.OnBall else config.OffBall
	local small = isSmallViewport(camera)
	local mobile = config.Mobile
	local rigAlpha = expAlpha(config.RigResponsiveness, deltaTime)
	currentRig.Distance += (targetRig.Distance * (if small then mobile.DistanceScale else 1) - currentRig.Distance) * rigAlpha
	currentRig.Height += (targetRig.Height * (if small then mobile.HeightScale else 1) - currentRig.Height) * rigAlpha
	currentRig.Pitch += (targetRig.Pitch - currentRig.Pitch) * rigAlpha
	currentRig.LookAhead += (targetRig.LookAhead - currentRig.LookAhead) * rigAlpha
	local targetFOV = targetRig.FOV + (if small then mobile.FOVBonus else 0)

	--[[
		YAW AND PITCH.

		Locked mouse: the player aims the camera, full stop. Free cursor: the
		camera follows the direction of play, smoothed, and holds the preset
		pitch.
	]]
	local playDirection = getPlayDirection(rootPart, ball)
	if mouseLocked then
		local delta = UserInputService:GetMouseDelta()
		mouseYaw -= delta.X * config.MouseYawSensitivity
		mousePitch = math.clamp(
			mousePitch + delta.Y * config.MousePitchSensitivity * 60,
			config.MinimumPitchDegrees,
			config.MaximumPitchDegrees
		)
		currentYaw = mouseYaw
		currentPitch = mousePitch
	else
		local targetYaw = math.atan2(-playDirection.X, -playDirection.Z)
		currentYaw = lerpAngle(currentYaw, targetYaw, expAlpha(config.YawResponsiveness, deltaTime))
		-- Keep the manual yaw in step, so toggling the mouse lock on does not
		-- snap the view somewhere else.
		mouseYaw = currentYaw
		currentPitch += (currentRig.Pitch - currentPitch) * expAlpha(config.RigResponsiveness, deltaTime)
		mousePitch = currentPitch
	end

	local back = Vector3.new(math.sin(currentYaw), 0, math.cos(currentYaw))
	local forward = -back

	--[[
		THE FOCUS POINT: ahead of the footballer, pulled toward the football.

		Bounded in studs so the ball can never drag the frame off the player.
		More pull off the ball, where the ball is the thing worth watching, and
		less on it, where the player and the ball are in the same place anyway.
	]]
	local anchor = rootPart.Position
	local focusTarget = anchor + forward * currentRig.LookAhead
	if ball then
		local weight = if onBall then config.BallFocusWeightOnBall else config.BallFocusWeightOffBall
		local pull = (ball.Position - focusTarget) * weight
		local flat = BallControlMath.GetHorizontal(pull)
		if flat.Magnitude > config.MaximumBallFocusOffset then
			flat = flat.Unit * config.MaximumBallFocusOffset
		end
		focusTarget += flat
	end

	local positionTarget = anchor
		+ back * currentRig.Distance
		+ Vector3.yAxis * currentRig.Height

	--[[
		Never underground. Cheap floor: the anchor's own height plus a minimum,
		which is enough on a flat pitch and costs no raycast every frame.
	]]
	local minimumY = anchor.Y + config.MinimumHeightAboveGround
	if positionTarget.Y < minimumY then
		positionTarget = Vector3.new(positionTarget.X, minimumY, positionTarget.Z)
	end

	currentPosition = if currentPosition
		then currentPosition + (positionTarget - currentPosition) * expAlpha(config.PositionResponsiveness, deltaTime)
		else positionTarget
	currentFocus = if currentFocus
		then currentFocus + (focusTarget - currentFocus) * expAlpha(config.FocusResponsiveness, deltaTime)
		else focusTarget
	currentFOV += (targetFOV - currentFOV) * expAlpha(config.FOVResponsiveness, deltaTime)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = currentFOV
	camera.CFrame = CFrame.lookAt(currentPosition :: Vector3, currentFocus :: Vector3)
end

local function resetSmoothing()
	currentPosition = nil
	currentFocus = nil
	local rootPart = getRootPart()
	if rootPart then
		local facing = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
			Vector3.zAxis
		)
		currentYaw = math.atan2(-facing.X, -facing.Z)
		mouseYaw = currentYaw
	end
	currentPitch = config.OnBall.Pitch
	mousePitch = currentPitch
	currentFOV = config.OnBall.FOV
	currentRig.Distance = config.OnBall.Distance
	currentRig.Height = config.OnBall.Height
	currentRig.Pitch = config.OnBall.Pitch
	currentRig.LookAhead = config.OnBall.LookAhead
end

local function configureCamera()
	local camera = Workspace.CurrentCamera
	localPlayer.CameraMode = Enum.CameraMode.Classic
	localPlayer.CameraMinZoomDistance = config.MinZoomDistance
	localPlayer.CameraMaxZoomDistance = config.MaxZoomDistance
	if camera then
		-- Scriptable: this file owns the camera now, not Roblox's follow logic.
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = getCurrentHumanoid()
	end
	resetSmoothing()
	localPlayer:SetAttribute("Beyond90CameraMode", "ThirdPerson")
end

-- Locked: the cursor is centred and raw mouse delta aims the camera.
-- Free: the cursor behaves normally and the camera follows play by itself.
local function applyMouseLock(locked: boolean)
	if not active or config.MouseLockEnabled ~= true then
		return
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return
	end
	mouseLocked = locked
	if locked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	localPlayer:SetAttribute("Beyond90ThirdPersonMouseLocked", mouseLocked)
end

function ThirdPersonCamera.ToggleMouseLock(): boolean
	if not active then
		return false
	end
	applyMouseLock(not mouseLocked)
	return mouseLocked
end

function ThirdPersonCamera.IsMouseLocked(): boolean
	return active and mouseLocked
end

function ThirdPersonCamera.Enable()
	if active then
		return
	end

	active = true
	previousMouseBehavior = UserInputService.MouseBehavior
	configureCamera()
	applyMouseLock(config.MouseLockDefault == true)
	characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
		if active then
			task.defer(configureCamera)
		end
	end)
	renderConnection = RunService.RenderStepped:Connect(updateCamera)
end

function ThirdPersonCamera.Disable()
	if not active then
		return
	end

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	-- Always hand the cursor back on exit, whatever state it was left in.
	if config.MouseLockEnabled == true then
		UserInputService.MouseBehavior = previousMouseBehavior or Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	mouseLocked = false
	localPlayer:SetAttribute("Beyond90ThirdPersonMouseLocked", nil)
	active = false

	--[[
		Hand the camera back in a state the next mode can use. Leaving it
		Scriptable would freeze the view for whatever takes over, which is
		exactly the "camera stuck after switching modes" class of bug.
	]]
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = getCurrentHumanoid()
	end
	currentPosition = nil
	currentFocus = nil

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end
end

function ThirdPersonCamera.IsEnabled(): boolean
	return active
end

return ThirdPersonCamera
