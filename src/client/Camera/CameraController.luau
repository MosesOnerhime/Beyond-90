local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraConfig = require(Shared.Config.CameraConfig)
local GameConfig = require(Shared.Config.GameConfig)
local BroadcastCamera = require(script.Parent.BroadcastCamera)
local FirstPersonCamera = require(script.Parent.FirstPersonCamera)
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

	if valid then
		setMode(chosen)
	elseif CameraConfig.DefaultMode == "Broadcast" then
		setMode("Broadcast1")
	else
		restoreDefaultCamera()
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

	BroadcastCamera.Disable()
	ThirdPersonCamera.Disable()
	FirstPersonCamera.Disable()
	FirstPersonCamera.RestoreLocalCharacterVisibility()
	restoreDefaultCamera()
	activeMode = "Default"
	modeChangedEvent:Fire(activeMode)
end

return CameraController
