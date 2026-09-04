local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local CameraConfig = require(Shared.Config.CameraConfig)
local GoalkeeperConfig = require(Shared.Config.GoalkeeperConfig)

-- Held so the keeper-role watch can be replaced rather than stacked when
-- gameplay is entered more than once in a session.
local keeperRoleConnection: RBXScriptConnection? = nil
local keeperCharacterConnection: RBXScriptConnection? = nil
local GameConfig = require(Shared.Config.GameConfig)
local MatchRulesConfig = require(Shared.Config.MatchRulesConfig)
local BroadcastCamera = require(script.Parent.BroadcastCamera)
local FirstPersonCamera = require(script.Parent.FirstPersonCamera)
local CameraShake = require(script.Parent.CameraShake)
local ThirdPersonCamera = require(script.Parent.ThirdPersonCamera)
local InputController = require(script.Parent.Parent.Controllers:WaitForChild("InputController"))

local CameraController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local activeMode = "Default"
local toggleConnection: RBXScriptConnection? = nil
local mouseLockConnection: RBXScriptConnection? = nil
local characterAddedConnection: RBXScriptConnection? = nil
local originalCameraType: Enum.CameraType? = nil
local originalCameraSubject: Instance? = nil
local modeTransitionId = 0
local modeChangedEvent = Instance.new("BindableEvent")
local joinIntroPlayed = false
local setPieceConnection: RBXScriptConnection? = nil
--[[
	Set-piece camera state.

	`setPieceRestoreMode` is what the player was watching before the set piece;
	`setPieceAppliedMode` is what this system put them in. Keeping both is what
	lets a manual camera change during a dead ball win: if the active mode is no
	longer the one applied here, the player has taken over and nothing is
	restored over the top of their choice.
]]
local setPieceRestoreMode: string? = nil
local setPieceAppliedMode: string? = nil
local cachedRulesFolder: Instance? = nil
local cachedBallPart: BasePart? = nil
-- Last football action already turned into a shake, so one strike produces one
-- impulse however often the state is sampled.
local lastShakenTackleAt = 0

local function log(message: string)
	print(string.format("%s[Client][Camera] %s", GameConfig.LogPrefix, message))
end

local function getCurrentHumanoid(): Humanoid?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health > 0 then
		return humanoid
	end

	return nil
end

local function restoreDefaultCamera()
	local camera = Workspace.CurrentCamera

	if not camera then
		return
	end

	camera.CameraType = originalCameraType or Enum.CameraType.Custom
	camera.CameraSubject = getCurrentHumanoid() or originalCameraSubject
	localPlayer:SetAttribute("Beyond90CameraMode", "Default")
end

local function setMode(mode: string)
	if mode == "Broadcast" then
		mode = "Broadcast1"
	end
	if mode == "FirstPerson" and not CameraConfig.FirstPerson.Enabled then
		mode = "ThirdPerson"
	end

	local camera = Workspace.CurrentCamera

	if not camera then
		return
	end

	modeTransitionId += 1
	local transitionId = modeTransitionId
	local wasFirstPerson = activeMode == "FirstPerson"
	local firstPersonExitDelay = CameraConfig.FirstPerson.ExitRestoreDelay or 0

	local function afterFirstPersonExit(callback)
		if not wasFirstPerson or firstPersonExitDelay <= 0 then
			callback()
			return
		end

		task.delay(firstPersonExitDelay, function()
			if transitionId == modeTransitionId then
				callback()
			end
		end)
	end

	if mode == "Broadcast1" or mode == "Broadcast2" then
		if activeMode == "Default" then
			originalCameraType = camera.CameraType
			originalCameraSubject = camera.CameraSubject
		end

		activeMode = mode
		ThirdPersonCamera.Disable()
		FirstPersonCamera.Disable()
		FirstPersonCamera.RestoreLocalCharacterVisibility()
		BroadcastCamera.SetProfile(mode)
		afterFirstPersonExit(function()
			if activeMode == mode then
				BroadcastCamera.Enable()
			end
		end)
		log("Mode -> " .. mode)
	elseif mode == "ThirdPerson" then
		if activeMode == "Default" then
			originalCameraType = camera.CameraType
			originalCameraSubject = camera.CameraSubject
		end

		activeMode = "ThirdPerson"
		BroadcastCamera.Disable()
		FirstPersonCamera.Disable()
		FirstPersonCamera.RestoreLocalCharacterVisibility()
		afterFirstPersonExit(function()
			if activeMode == "ThirdPerson" then
				ThirdPersonCamera.Enable()
			end
		end)
		log("Mode -> ThirdPerson")
	elseif mode == "FirstPerson" then
		if activeMode == "Default" then
			originalCameraType = camera.CameraType
			originalCameraSubject = camera.CameraSubject
		end

		activeMode = "FirstPerson"
		BroadcastCamera.Disable()
		ThirdPersonCamera.Disable()
		FirstPersonCamera.Enable()
		log("Mode -> FirstPerson")
	else
		activeMode = "Default"
		BroadcastCamera.Disable()
		ThirdPersonCamera.Disable()
		FirstPersonCamera.Disable()
		restoreDefaultCamera()
		log("Mode -> Default")
	end

	modeChangedEvent:Fire(activeMode)
end

--[[
	SET-PIECE CAMERA (§ user request).

	A dead ball that the LOCAL PLAYER is taking hands the camera to Pro Camera
	for the duration, then hands it back.

	Read from replicated state rather than driven by a remote: the server already
	publishes both the restart phase and which footballer holds the ball, and a
	presentation decision derived from state the client can already see does not
	need a message of its own. It also means the camera cannot end up out of step
	with the restart -- there is one source of truth and the camera follows it.
]]
local function getRulesFolder(): Instance?
	if cachedRulesFolder and cachedRulesFolder.Parent then
		return cachedRulesFolder
	end
	cachedRulesFolder = ReplicatedStorage:FindFirstChild(MatchRulesConfig.FolderName)
	return cachedRulesFolder
end

local function getFootball(): BasePart?
	if cachedBallPart and cachedBallPart.Parent then
		return cachedBallPart
	end
	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = rootFolder and rootFolder:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)
	cachedBallPart = if ball and ball:IsA("BasePart") then ball else nil
	return cachedBallPart
end

--[[
	Is the local player, right now, the one who has to strike a dead ball?

	All three conditions matter. The phase says the match is stopped for a
	restart; the restart kind says it is one worth aiming; the taker id says it
	is this player's problem rather than someone else's.
]]
local function localPlayerIsTakingAimedSetPiece(): boolean
	local setPiece = CameraConfig.SetPiece
	if not setPiece or setPiece.Enabled ~= true then
		return false
	end
	local rules = getRulesFolder()
	if not rules then
		return false
	end
	local phase = rules:GetAttribute(MatchRulesConfig.StateAttributeName)
	if not MatchRulesConfig.IsRestartPhase(phase) then
		return false
	end
	local restart = rules:GetAttribute(MatchRulesConfig.RestartAttributeName)
	if typeof(restart) ~= "string" or setPiece.Restarts[restart] ~= true then
		return false
	end
	local ball = getFootball()
	if not ball then
		return false
	end
	local takerId = ball:GetAttribute(MatchRulesConfig.RestartControl.ControlAttributeName)
	return takerId == localPlayer.UserId
end

--[[
	IMPACT FEEDBACK.

	Derived from replicated state rather than from new remotes, for the same
	reason the set-piece camera is: the server already publishes what struck the
	ball, when, and how hard, and a purely presentational effect has no business
	adding traffic to describe something every client can already see.

	Everything here is guarded by a timestamp, so sampling the same event twice
	produces one shake rather than two, and a shake can never be triggered by
	state that merely persists.
]]
local function updateImpactShake()
	--[[
		SHOOTING DOES NOT SHAKE THE CAMERA.

		It used to, scaled by ball speed, on the reasoning that a struck ball
		should feel struck. In play it reads as a small jitter at the exact
		moment the player most wants a clean look at where the ball went, and it
		fires on every shot -- which in football is constantly.

		The difference from a tackle is what settles it. A tackle is something
		that happens TO the player: a collision, unexpected, and the camera
		flinching with it is honest. A shot is something the player DOES, and
		they are already watching the ball leave. Shaking the frame on your own
		deliberate action adds nothing to read and takes away the shot's flight,
		which is the part worth seeing.

		The ball's own strike feedback -- the contact sound, the animation, the
		trajectory -- already carries the impact without moving the camera.
	]]
	local character = localPlayer.Character
	if not character then
		return
	end

	--[[
		A tackle the LOCAL player was involved in. Deliberately not every tackle
		on the pitch: a challenge forty studs away is someone else's collision,
		and shaking the camera for it would be noise.
	]]
	local tackledAt = character:GetAttribute("Beyond90TackledAt")
	if typeof(tackledAt) == "number" and tackledAt > lastShakenTackleAt then
		lastShakenTackleAt = tackledAt
		CameraShake.Trigger("Tackle", 1)
	end
end

local function updateSetPieceCamera()
	local shouldTake = localPlayerIsTakingAimedSetPiece()
	local target = CameraConfig.SetPiece.Mode

	if shouldTake then
		if setPieceAppliedMode ~= nil then
			return
		end
		-- Already in the set-piece camera by choice: nothing to hand over, and
		-- nothing to hand back afterwards.
		if activeMode == target then
			return
		end
		setPieceRestoreMode = activeMode
		setPieceAppliedMode = target
		setMode(target)
		log(string.format("Set piece -> %s (restoring %s)", target, tostring(setPieceRestoreMode)))
		return
	end

	if setPieceAppliedMode == nil then
		return
	end

	local restore = setPieceRestoreMode
	local applied = setPieceAppliedMode
	setPieceRestoreMode = nil
	setPieceAppliedMode = nil
	-- The player changed camera mid-set-piece. Their choice stands.
	if activeMode ~= applied then
		log("Set piece over; player changed camera during it, leaving it alone")
		return
	end
	if typeof(restore) == "string" and restore ~= applied then
		setMode(restore)
		log("Set piece over -> " .. restore)
	end
end

local function togglePrimaryMode()
	if activeMode == "Broadcast1" then
		setMode("Broadcast2")
	elseif activeMode == "Broadcast2" then
		setMode("ThirdPerson")
	else
		setMode("Broadcast1")
	end
end

function CameraController.Initialize()
	if initialized then
		return
	end

	initialized = true
	toggleConnection = InputController.GetCameraToggleEvent().Event:Connect(togglePrimaryMode)
	-- L only means anything in Pro Camera; Broadcast modes are untouched.
	mouseLockConnection = InputController.GetCameraLockToggleEvent().Event:Connect(function()
		if activeMode ~= "ThirdPerson" then
			return
		end
		local locked = ThirdPersonCamera.ToggleMouseLock()
		log(string.format("ThirdPerson mouse lock -> %s", if locked then "locked" else "free"))
	end)
	characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
		if activeMode == "Default" then
			task.defer(restoreDefaultCamera)
		end
	end)

	--[[
		Sampled rather than event-driven, deliberately.

		The two instances this depends on -- the rules folder and the football --
		are created by the server and may not exist when the camera initialises,
		and either can be replaced during a session. Signals would need rebinding
		on both. Two cached attribute reads eight times a second cost nothing
		measurable and cannot miss an edge on an instance that appeared late.
	]]
	if CameraConfig.SetPiece and CameraConfig.SetPiece.Enabled == true then
		local sampleAccumulator = 0
		setPieceConnection = RunService.Heartbeat:Connect(function(delta)
			sampleAccumulator += delta
			if sampleAccumulator < CameraConfig.SetPiece.SampleInterval then
				return
			end
			sampleAccumulator = 0
			local ok, failure = pcall(function()
				updateSetPieceCamera()
				updateImpactShake()
			end)
			if not ok then
				warn("[Beyond90][Client][Camera] Camera state update failed: " .. tostring(failure))
			end
		end)
	end

	FirstPersonCamera.Disable()
	FirstPersonCamera.RestoreLocalCharacterVisibility()

	--[[
		Open in the camera the player chose in Settings (§64), falling back to
		the project default when they have not chosen one.
	]]
	local chosen = localPlayer:GetAttribute(CameraConfig.DefaultCameraAttribute)
	local valid = false
	if typeof(chosen) == "string" then
		for _, entry in CameraConfig.SelectableModes do
			if entry.Id == chosen then
				valid = true
			end
		end
	end

	--[[
		A KEEPER OPENS IN PRO CAMERA.

		Broadcast framing reads the pitch from side on, which is the wrong view
		for the one player judging a ball travelling toward him. An explicit
		choice in Settings still wins -- this only replaces the fallback, so a
		keeper who has picked Broadcast keeps it.

		THE ROLE ARRIVES LATE. The first version of this read the role attribute
		once, here, and the keeper camera never applied: the attribute is written
		by the server when GoalkeeperService registers the keeper, and it has not
		necessarily replicated by the time the camera opens. So the choice is made
		now AND re-made if the role turns up afterwards.
	]]
	local function resolveOpeningMode()
		local character = localPlayer.Character
		local isKeeper = character ~= nil
			and character:GetAttribute(GoalkeeperConfig.RoleAttributeName) == GoalkeeperConfig.Role

		--[[
			THE ROLE WINS, NOT THE STORED DEFAULT.

			This used to let a saved Settings choice beat the keeper rule, on the
			grounds that an explicit choice should stand. In practice the saved
			choice is Broadcast for anyone who has ever picked it once, so
			choosing GK opened in Broadcast every time and the keeper camera was
			reported missing again -- the log is `Mode -> Broadcast1` on every
			keeper spawn.

			Overruled deliberately: playing in goal is a different job from
			playing out, and the camera that job needs is not a preference the
			outfield choice should be answering for. The player can still switch
			once they are in.
		]]
		if isKeeper and CameraConfig.GoalkeeperDefaultMode then
			setMode(CameraConfig.GoalkeeperDefaultMode)
			return
		end
		if valid then
			setMode(chosen)
			return
		end
		if CameraConfig.DefaultMode == "Broadcast" then
			setMode("Broadcast1")
		else
			restoreDefaultCamera()
		end
	end

	resolveOpeningMode()

	--[[
		Watch for the role landing, on this character and on the next one.

		No longer gated on the player having made no camera choice. The role
		almost always arrives AFTER the camera opens -- that is the entire reason
		this watcher exists -- so gating it on `not valid` meant a player with any
		stored choice could never receive the keeper camera at all, by either
		path. Since the role now outranks the stored choice above, it has to
		outrank it here too or the two disagree.
	]]
	do
		if keeperRoleConnection then
			keeperRoleConnection:Disconnect()
			keeperRoleConnection = nil
		end
		local function watch(character: Model)
			if keeperRoleConnection then
				keeperRoleConnection:Disconnect()
			end
			keeperRoleConnection = character
				:GetAttributeChangedSignal(GoalkeeperConfig.RoleAttributeName)
				:Connect(resolveOpeningMode)
			resolveOpeningMode()
		end
		if localPlayer.Character then
			watch(localPlayer.Character)
		end
		if keeperCharacterConnection then
			keeperCharacterConnection:Disconnect()
		end
		keeperCharacterConnection = localPlayer.CharacterAdded:Connect(watch)
	end
end

-- Called by Settings. Stores the choice and, when a match is already running,
-- switches immediately so the setting can be felt without re-entering.
function CameraController.SetDefaultMode(mode: string)
	local valid = false
	for _, entry in CameraConfig.SelectableModes do
		if entry.Id == mode then
			valid = true
		end
	end
	if not valid then
		return false
	end
	localPlayer:SetAttribute(CameraConfig.DefaultCameraAttribute, mode)
	if initialized then
		setMode(mode)
	end
	return true
end

function CameraController.GetDefaultMode(): string
	local chosen = localPlayer:GetAttribute(CameraConfig.DefaultCameraAttribute)
	if typeof(chosen) == "string" then
		for _, entry in CameraConfig.SelectableModes do
			if entry.Id == chosen then
				return chosen
			end
		end
	end
	return CameraConfig.FallbackSelectableMode
end

function CameraController.SetMode(mode: string)
	setMode(mode)
end

function CameraController.Toggle()
	togglePrimaryMode()
end

function CameraController.TogglePrimaryMode()
	togglePrimaryMode()
end

function CameraController.GetActiveMode(): string
	return activeMode
end

function CameraController.PlayJoinIntro()
	if joinIntroPlayed then return end
	joinIntroPlayed = true
	if activeMode == "Broadcast1" then
		BroadcastCamera.PlayJoinIntro()
		localPlayer:SetAttribute("Beyond90CameraJoinIntroStarted", os.clock())
		log("Broadcast1 join sky reveal")
	end
end

function CameraController.GetModeChangedEvent(): BindableEvent
	return modeChangedEvent
end

function CameraController.CycleBroadcastDistancePreset(): string
	return BroadcastCamera.CycleDistancePreset()
end

function CameraController.GetBroadcastDistancePresetLabel(): string
	return BroadcastCamera.GetDistancePresetLabel()
end

function CameraController.Destroy()
	if not initialized then
		return
	end

	initialized = false
	modeTransitionId += 1

	if toggleConnection then
		toggleConnection:Disconnect()
		toggleConnection = nil
	end

	if mouseLockConnection then
		mouseLockConnection:Disconnect()
		mouseLockConnection = nil
	end

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end

	if setPieceConnection then
		setPieceConnection:Disconnect()
		setPieceConnection = nil
	end
	setPieceRestoreMode = nil
	setPieceAppliedMode = nil
	cachedRulesFolder = nil
	cachedBallPart = nil

	BroadcastCamera.Disable()
	ThirdPersonCamera.Disable()
	FirstPersonCamera.Disable()
	FirstPersonCamera.RestoreLocalCharacterVisibility()
	restoreDefaultCamera()
	activeMode = "Default"
	modeChangedEvent:Fire(activeMode)
end

return CameraController
