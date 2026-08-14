local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local CameraConfig = require(Shared.Config.CameraConfig)

local FirstPersonCamera = {}

local localPlayer = Players.LocalPlayer
local config = CameraConfig.FirstPerson
local active = false
local renderConnection: RBXScriptConnection? = nil
local smoothedPosition: Vector3? = nil
local lastAttributeSampleTime = 0

local function getCharacterParts(): (BasePart?, BasePart?)
	local character = localPlayer.Character

	if not character then
		return nil, nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart, if head and head:IsA("BasePart") then head else nil
	end

	return nil, nil
end

local function expAlpha(responsiveness: number, deltaTime: number): number
	return 1 - math.exp(-responsiveness * deltaTime)
end

local function updateCamera(deltaTime: number)
	if not active then
		return
	end

	local camera = Workspace.CurrentCamera
	local rootPart, head = getCharacterParts()

	if not camera or not rootPart then
		return
	end

	local forward = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(rootPart.CFrame.LookVector), Vector3.new(0, 0, -1))
	local targetPosition

	if head then
		targetPosition = head.Position + forward * config.EyeForwardOffset
	else
		targetPosition = rootPart.Position + Vector3.yAxis * config.EyeHeightFallback + forward * config.EyeForwardOffset
	end

	if not smoothedPosition then
		smoothedPosition = targetPosition
	else
		smoothedPosition = smoothedPosition:Lerp(targetPosition, expAlpha(config.PositionResponsiveness, deltaTime))
	end

	local focus = (smoothedPosition :: Vector3) + forward * config.FocusDistance
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(smoothedPosition :: Vector3, focus)
	camera.Focus = CFrame.new(focus)
	camera.FieldOfView = config.FOV

	local now = os.clock()

	if now - lastAttributeSampleTime >= config.AttributeSampleInterval then
		lastAttributeSampleTime = now
		localPlayer:SetAttribute("Beyond90CameraMode", "FirstPerson")
		localPlayer:SetAttribute("Beyond90CameraFOV", config.FOV)
	end
end

function FirstPersonCamera.Enable()
	if active then
		return
	end

	active = true
	smoothedPosition = nil
	renderConnection = RunService.RenderStepped:Connect(updateCamera)
end

function FirstPersonCamera.Disable()
	if not active then
		return
	end

	active = false

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	smoothedPosition = nil
end

function FirstPersonCamera.IsEnabled(): boolean
	return active
end

return FirstPersonCamera
