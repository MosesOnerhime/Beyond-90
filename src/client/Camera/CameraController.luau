local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraConfig = require(Shared.Config.CameraConfig)
local GameConfig = require(Shared.Config.GameConfig)
local BroadcastCamera = require(script.Parent.BroadcastCamera)
local FirstPersonCamera = require(script.Parent.FirstPersonCamera)
local InputController = require(script.Parent.Parent.Controllers:WaitForChild("InputController"))

local CameraController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local activeMode = "Default"
local toggleConnection: RBXScriptConnection? = nil
local characterAddedConnection: RBXScriptConnection? = nil
local originalCameraType: Enum.CameraType? = nil
local originalCameraSubject: Instance? = nil
local modeChangedEvent = Instance.new("BindableEvent")

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
	local camera = Workspace.CurrentCamera

	if not camera then
		return
	end

	if mode == "Broadcast" then
		if activeMode == "Default" then
			originalCameraType = camera.CameraType
			originalCameraSubject = camera.CameraSubject
		end

		activeMode = "Broadcast"
		FirstPersonCamera.Disable()
		BroadcastCamera.Enable()
		log("Mode -> Broadcast")
	elseif mode == "FirstPerson" then
		if activeMode == "Default" then
			originalCameraType = camera.CameraType
			originalCameraSubject = camera.CameraSubject
		end

		activeMode = "FirstPerson"
		BroadcastCamera.Disable()
		FirstPersonCamera.Enable()
		log("Mode -> FirstPerson")
	else
		activeMode = "Default"
		BroadcastCamera.Disable()
		FirstPersonCamera.Disable()
		restoreDefaultCamera()
		log("Mode -> Default")
	end

	modeChangedEvent:Fire(activeMode)
end

local function togglePrimaryMode()
	if activeMode == "FirstPerson" then
		setMode("Broadcast")
	else
		setMode("FirstPerson")
	end
end

function CameraController.Initialize()
	if initialized then
		return
	end

	initialized = true
	toggleConnection = InputController.GetCameraToggleEvent().Event:Connect(togglePrimaryMode)
	characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
		if activeMode == "Default" then
			task.defer(restoreDefaultCamera)
		end
	end)

	if CameraConfig.DefaultMode == "Broadcast" then
		setMode("Broadcast")
	else
		restoreDefaultCamera()
	end
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

function CameraController.GetModeChangedEvent(): BindableEvent
	return modeChangedEvent
end

function CameraController.Destroy()
	if not initialized then
		return
	end

	initialized = false

	if toggleConnection then
		toggleConnection:Disconnect()
		toggleConnection = nil
	end

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end

	BroadcastCamera.Disable()
	FirstPersonCamera.Disable()
	restoreDefaultCamera()
	activeMode = "Default"
	modeChangedEvent:Fire(activeMode)
end

return CameraController
