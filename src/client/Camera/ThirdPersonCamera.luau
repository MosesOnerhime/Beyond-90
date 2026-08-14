local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraConfig = require(Shared.Config.CameraConfig)

local ThirdPersonCamera = {}

local localPlayer = Players.LocalPlayer
local config = CameraConfig.ThirdPerson
local active = false
local characterAddedConnection: RBXScriptConnection? = nil

local function getCurrentHumanoid(): Humanoid?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health > 0 then
		return humanoid
	end

	return nil
end

local function configureNativeThirdPerson()
	local camera = Workspace.CurrentCamera
	local humanoid = getCurrentHumanoid()

	localPlayer.CameraMode = Enum.CameraMode.Classic
	localPlayer.CameraMinZoomDistance = config.MinZoomDistance
	localPlayer.CameraMaxZoomDistance = config.MaxZoomDistance

	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end

	localPlayer:SetAttribute("Beyond90CameraMode", "ThirdPerson")
end

function ThirdPersonCamera.Enable()
	if active then
		return
	end

	active = true
	configureNativeThirdPerson()
	characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
		if active then
			task.defer(configureNativeThirdPerson)
		end
	end)
end

function ThirdPersonCamera.Disable()
	if not active then
		return
	end

	active = false

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end
end

function ThirdPersonCamera.IsEnabled(): boolean
	return active
end

return ThirdPersonCamera
