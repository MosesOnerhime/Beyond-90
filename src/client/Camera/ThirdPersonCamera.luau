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
local CameraShake = require(script.Parent.CameraShake)

local ThirdPersonCamera = {}

local localPlayer = Players.LocalPlayer
local config = CameraConfig.ThirdPerson
local active = false
local characterAddedConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local mouseLocked = false
local previousMouseBehavior: Enum.MouseBehavior? = nil
--[[
	Mouse-lock ownership while interactive UI is open.

	`uiSuspendedLock` remembers whether the lock was ON when a cursor-driven
	screen took over, so it can be handed back exactly as it was afterwards --
	rather than being restored to a default the player never chose.
]]
local uiSuspendedLock = false
local menuOpenConnection: RBXScriptConnection? = nil

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
-- Framing: where the controlled footballer currently sits in the frame, and how
-- far the ball has pulled that away from the configured composition.
local framingShiftX = 0
local framingShiftY = 0
-- How far open the view currently is, 0 = preset, 1 = fully widened.
local widenAlpha = 0

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

--[[
	COMPOSITION.

	Given a camera that is looking straight at `subject`, what rotation puts the
	subject at normalized screen position (sx, sy) instead of dead centre?

	Derived rather than tuned. In camera space the forward axis is -Z, so a
	direction d projects to normalized device coordinates

	    u = (d.x / -d.z) / tan(hFov/2)      v = (d.y / -d.z) / tan(vFov/2)

	with u = +1 at the right edge and v = +1 at the top. Rotating the camera by
	yaw t then pitch p sends the subject's direction to

	    d = (cos p * sin t, -sin p, -cos p * cos t)

	so u = tan t / tanH and v = -tan p / (cos t * tanV), which inverts cleanly to
	the two angles below. Being exact matters: it means the composition holds at
	any field of view and any viewport shape, including a phone in landscape,
	instead of drifting as soon as either changes.
]]
local function framingRotation(fov: number, viewport: Vector2, sx: number, sy: number): CFrame
	local tanV = math.tan(math.rad(fov) * 0.5)
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local tanH = tanV * aspect
	local u = sx * 2 - 1
	local v = 1 - sy * 2
	local yaw = math.atan(u * tanH)
	local pitch = -math.atan(v * tanV * math.cos(yaw))
	return CFrame.Angles(pitch, yaw, 0)
end

--[[
	Where does `point` land on screen, given a camera CFrame and lens?

	Used to ask the only question the framing actually cares about: is the
	football still inside the dead zone? Returns nil when the point is behind the
	camera, which the caller must treat as "definitely outside".
]]
local function projectToScreen(cameraCFrame: CFrame, fov: number, viewport: Vector2, point: Vector3): (number?, number?)
	local local_ = cameraCFrame:PointToObjectSpace(point)
	if local_.Z >= -0.05 then
		return nil, nil
	end
	local tanV = math.tan(math.rad(fov) * 0.5)
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local tanH = tanV * aspect
	local u = (local_.X / -local_.Z) / tanH
	local v = (local_.Y / -local_.Z) / tanV
	return (u + 1) * 0.5, (1 - v) * 0.5
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

	--[[
		HOW FAR AWAY IS PLAY?

		Distance to the football, blended slowly into `widenAlpha`. This is a
		SEPARATE question from possession -- a footballer without the ball may be
		right next to it or at the other end of the pitch, and those want very
		different framing -- which is why it scales the preset rather than being
		folded into it.
	]]
	local widening = config.Widening
	local ballDistance = if ball
		then BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude
		else 0
	local widenTarget = math.clamp(
		(ballDistance - widening.StartDistance) / math.max(widening.FullDistance - widening.StartDistance, 1),
		0,
		1
	)
	widenAlpha += (widenTarget - widenAlpha) * expAlpha(widening.Responsiveness, deltaTime)
	local widenDistance = 1 + (widening.DistanceScale - 1) * widenAlpha
	local widenHeight = 1 + (widening.HeightScale - 1) * widenAlpha

	currentRig.Distance += (targetRig.Distance * widenDistance * (if small then mobile.DistanceScale else 1) - currentRig.Distance) * rigAlpha
	currentRig.Height += (targetRig.Height * widenHeight * (if small then mobile.HeightScale else 1) - currentRig.Height) * rigAlpha
	currentRig.Pitch += (targetRig.Pitch - currentRig.Pitch) * rigAlpha
	currentRig.LookAhead += (targetRig.LookAhead - currentRig.LookAhead) * rigAlpha
	local targetFOV = targetRig.FOV
		+ widening.FOVBonus * widenAlpha
		+ (if small then mobile.FOVBonus else 0)

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
		--[[
			YAW DEAD ZONE.

			Inside a few degrees of where the camera already points, the camera
			simply does not turn. Dribbling is a continuous stream of small
			heading corrections and answering all of them is what makes a
			following camera feel unsettled -- the reference capture holds a
			steady line through exactly the sort of touches that were swinging
			this view. Outside the dead zone it tracks normally.
		]]
		local targetYaw = math.atan2(-playDirection.X, -playDirection.Z)
		local yawError = (targetYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi
		if math.abs(yawError) > math.rad(config.YawDeadZoneDegrees) then
			currentYaw = lerpAngle(currentYaw, targetYaw, expAlpha(config.YawResponsiveness, deltaTime))
		end
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
	--[[
		The aim point is the footballer, nudged ahead of them.

		The football no longer PULLS THE AIM. It used to, and that is what made
		the composition unpredictable: the ball dragged the centre of the frame
		around, so where the player appeared on screen depended on where the ball
		happened to be. The reference does the opposite -- the footballer holds a
		consistent place in the frame and the camera pans to keep the ball in
		shot. That is what the framing shift below does instead, and it is why
		this is now a short, fixed look-ahead rather than a large one competing
		with a ball weight.
	]]
	local focusTarget = anchor + forward * currentRig.LookAhead + Vector3.yAxis * 2

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

	--[[
		THE COMPOSITION, AND THE DEAD ZONE THAT PROTECTS IT.

		Start from the reference framing, project the football through it, and
		only if the ball has left the dead zone does the framing give way -- and
		then only as far as the clamp allows. The footballer therefore holds a
		stable place in the frame during ordinary play and yields it, smoothly
		and partially, when the ball genuinely needs the room.

		Mouse look is exempt from the ball shift. While the player is aiming the
		camera themselves, a camera that also pans on its own is fighting them.
	]]
	local framing = config.Framing
	local viewport = camera.ViewportSize
	local baseCFrame = CFrame.lookAt(currentPosition :: Vector3, currentFocus :: Vector3)

	local desiredShiftX, desiredShiftY = 0, 0
	if ball and not mouseLocked then
		local composed = baseCFrame * framingRotation(currentFOV, viewport, framing.SubjectX, framing.SubjectY)
		local ballX, ballY = projectToScreen(composed, currentFOV, viewport, ball.Position)
		if ballX ~= nil and ballY ~= nil then
			local halfX = framing.DeadZoneX * 0.5
			local halfY = framing.DeadZoneY * 0.5
			local overX = ballX - 0.5
			local overY = ballY - 0.5
			-- Only the part of the error that is OUTSIDE the dead zone counts.
			overX = if math.abs(overX) > halfX then overX - halfX * math.sign(overX) else 0
			overY = if math.abs(overY) > halfY then overY - halfY * math.sign(overY) else 0
			desiredShiftX = math.clamp(overX, -framing.MaximumBallShiftX, framing.MaximumBallShiftX)
			desiredShiftY = math.clamp(overY, -framing.MaximumBallShiftY, framing.MaximumBallShiftY)
		end
	end
	local shiftAlpha = expAlpha(framing.ShiftResponsiveness, deltaTime)
	framingShiftX += (desiredShiftX - framingShiftX) * shiftAlpha
	framingShiftY += (desiredShiftY - framingShiftY) * shiftAlpha

	local subjectX = math.clamp(framing.SubjectX + framingShiftX, 0.12, 0.88)
	local subjectY = math.clamp(framing.SubjectY + framingShiftY, 0.2, 0.9)
	--[[
		Shake is applied LAST, to the composed result, and is never written back
		into any smoothed state. That is what makes it presentation-only: the
		camera's position, aim and framing are already final by this point, so
		nothing about aiming a shot or judging a pass can be affected by it.
	]]
	camera.CFrame = baseCFrame
		* framingRotation(currentFOV, viewport, subjectX, subjectY)
		* CameraShake.Step(deltaTime)
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
	framingShiftX = 0
	framingShiftY = 0
	widenAlpha = 0
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

--[[
	INTERACTIVE UI OWNS THE CURSOR WHILE IT IS OPEN.

	Pro Camera locks the mouse to the centre of the screen and consumes its raw
	delta to aim. That is right during play and wrong the instant a screen the
	player has to CLICK appears: the cursor is invisible, pinned to the middle,
	and every attempt to move it aims the camera instead. A player who opens
	settings mid-match cannot press anything.

	So the lock is released while such a screen is up, and restored to whatever
	the player actually had when it closes. Nothing here decides WHETHER a menu
	is open -- it reads the same flag the movement and action controllers already
	stand down on, so all three agree by construction about when the player is in
	a menu rather than in a match.
]]
local function onMenuOpenChanged()
	if not active or config.MouseLockEnabled ~= true then
		return
	end
	local menuOpen = localPlayer:GetAttribute("Beyond90MenuOpen") == true
	if menuOpen then
		if mouseLocked then
			uiSuspendedLock = true
			applyMouseLock(false)
		end
		return
	end
	if uiSuspendedLock then
		uiSuspendedLock = false
		applyMouseLock(true)
	end
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
	uiSuspendedLock = false
	menuOpenConnection = localPlayer:GetAttributeChangedSignal("Beyond90MenuOpen"):Connect(onMenuOpenChanged)
	-- Apply the current state immediately: the camera may be enabled while a
	-- menu is already up, and starting locked behind a menu is the same bug.
	onMenuOpenChanged()
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
	uiSuspendedLock = false
	if menuOpenConnection then
		menuOpenConnection:Disconnect()
		menuOpenConnection = nil
	end
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
	-- A shake started under this camera must not leak into the next one.
	CameraShake.Clear()

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end
end

function ThirdPersonCamera.IsEnabled(): boolean
	return active
end

return ThirdPersonCamera
