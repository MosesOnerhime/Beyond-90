local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local CameraConfig = require(Shared.Config.CameraConfig)

local FirstPersonCamera = {}

local localPlayer = Players.LocalPlayer
local config = CameraConfig.FirstPerson
local active = false
local hiddenParts: { [BasePart]: number } = {}
local characterAddedConnection: RBXScriptConnection? = nil
local descendantAddedConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local inputChangedConnection: RBXScriptConnection? = nil
local previousCameraMode: Enum.CameraMode? = nil
local previousMinZoomDistance: number? = nil
local previousMaxZoomDistance: number? = nil
local previousCameraType: Enum.CameraType? = nil
local previousCameraSubject: Instance? = nil
local previousMouseBehavior: Enum.MouseBehavior? = nil
local previousMouseIconEnabled: boolean? = nil
local yaw = 0
local pitch = 0
local gamepadLook = Vector2.zero
local visibilityRestoreId = 0

local function getCurrentHumanoid(): Humanoid?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid and humanoid.Health > 0 then
		return humanoid
	end

	return nil
end

local function isAccessoryDescendant(instance: Instance): boolean
	local current = instance.Parent

	while current do
		if current:IsA("Accessory") then
			return true
		end

		current = current.Parent
	end

	return false
end

local function shouldHideInFirstPerson(part: BasePart): boolean
	return part.Name == "Head" or isAccessoryDescendant(part)
end

local function hidePart(part: BasePart)
	if hiddenParts[part] ~= nil then
		part.LocalTransparencyModifier = 1
		return
	end

	hiddenParts[part] = part.LocalTransparencyModifier
	part.LocalTransparencyModifier = 1
end

local function hideObstructions(character: Model?)
	if not character then
		return
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and shouldHideInFirstPerson(descendant) then
			hidePart(descendant)
		end
	end
end

local function restoreHiddenParts(makeVisible: boolean?)
	for part, transparency in hiddenParts do
		if part.Parent then
			part.LocalTransparencyModifier = if makeVisible then 0 else transparency
		end
	end

	table.clear(hiddenParts)
end

local function forceRestoreCharacterLocalTransparency(character: Model?)
	if not character then
		return
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 0
		end
	end
end

local function configureCameraForExit()
	local camera = Workspace.CurrentCamera
	local humanoid = getCurrentHumanoid()
	local restoredMode = previousCameraMode

	if restoredMode == Enum.CameraMode.LockFirstPerson then
		restoredMode = Enum.CameraMode.Classic
	end

	localPlayer.CameraMode = restoredMode or Enum.CameraMode.Classic
	localPlayer.CameraMinZoomDistance = previousMinZoomDistance or 0.5
	localPlayer.CameraMaxZoomDistance = previousMaxZoomDistance or 128

	if camera then
		camera.CameraType = previousCameraType or Enum.CameraType.Custom
		camera.CameraSubject = humanoid or previousCameraSubject
	end
end

local function restoreLocalCharacterVisibility()
	restoreHiddenParts(true)
	forceRestoreCharacterLocalTransparency(localPlayer.Character)
end

local function restoreLocalCharacterVisibilityForDuration(duration: number)
	visibilityRestoreId += 1
	local restoreId = visibilityRestoreId
	local startedAt = os.clock()

	local function step()
		if active or restoreId ~= visibilityRestoreId then
			return
		end

		restoreLocalCharacterVisibility()

		if os.clock() - startedAt < duration then
			task.delay(0.05, step)
		end
	end

	step()
end

local function getCharacterCameraParts(): (BasePart?, BasePart?)
	local character = localPlayer.Character

	if not character then
		return nil, nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")

	return if rootPart and rootPart:IsA("BasePart") then rootPart else nil,
		if head and head:IsA("BasePart") then head else nil
end

local function updateCamera(deltaTime: number)
	local camera = Workspace.CurrentCamera
	local rootPart, head = getCharacterCameraParts()

	if not camera or not rootPart then
		return
	end

	local mouseDelta = UserInputService:GetMouseDelta()
	yaw -= mouseDelta.X * config.MouseSensitivity
	pitch = math.clamp(
		pitch - mouseDelta.Y * config.MouseSensitivity,
		math.rad(config.MinPitchDegrees),
		math.rad(config.MaxPitchDegrees)
	)

	if gamepadLook.Magnitude > 0.05 then
		yaw -= gamepadLook.X * config.GamepadSensitivity * deltaTime
		pitch = math.clamp(
			pitch + gamepadLook.Y * config.GamepadSensitivity * deltaTime,
			math.rad(config.MinPitchDegrees),
			math.rad(config.MaxPitchDegrees)
		)
	end

	local rotation = CFrame.fromOrientation(pitch, yaw, 0)
	local forward = BallControlMath.SafeUnit(rotation.LookVector, BallControlMath.SafeUnit(BallControlMath.GetHorizontal(rootPart.CFrame.LookVector), Vector3.new(0, 0, -1)))
	local origin = if head then head.Position else rootPart.Position + Vector3.yAxis * config.EyeHeightFallback
	local cameraPosition = origin + forward * config.EyeForwardOffset
	local focus = cameraPosition + forward * config.FocusDistance

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(cameraPosition, focus)
	camera.Focus = CFrame.new(focus)
	camera.FieldOfView = config.FOV
	localPlayer:SetAttribute("Beyond90CameraMode", "FirstPerson")
	localPlayer:SetAttribute("Beyond90CameraFOV", config.FOV)
end

local function initializeLookAngles()
	local camera = Workspace.CurrentCamera
	local rootPart = getCharacterCameraParts()
	local lookVector = if camera then camera.CFrame.LookVector else nil

	if not lookVector and rootPart then
		lookVector = rootPart.CFrame.LookVector
	end

	lookVector = lookVector or Vector3.new(0, 0, -1)
	yaw = math.atan2(-lookVector.X, -lookVector.Z)
	pitch = math.clamp(math.asin(math.clamp(lookVector.Y, -1, 1)), math.rad(config.MinPitchDegrees), math.rad(config.MaxPitchDegrees))
end

local function bindCharacter(character: Model?)
	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
		descendantAddedConnection = nil
	end

	if not character then
		return
	end

	hideObstructions(character)
	descendantAddedConnection = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and shouldHideInFirstPerson(descendant) then
			hidePart(descendant)
		end
	end)
end

function FirstPersonCamera.Enable()
	if active then
		return
	end

	active = true
	previousCameraMode = localPlayer.CameraMode
	previousMinZoomDistance = localPlayer.CameraMinZoomDistance
	previousMaxZoomDistance = localPlayer.CameraMaxZoomDistance
	local camera = Workspace.CurrentCamera

	if camera then
		previousCameraType = camera.CameraType
		previousCameraSubject = camera.CameraSubject
	end

	visibilityRestoreId += 1
	previousMouseBehavior = UserInputService.MouseBehavior
	previousMouseIconEnabled = UserInputService.MouseIconEnabled
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	initializeLookAngles()
	localPlayer.CameraMode = Enum.CameraMode.Classic
	localPlayer.CameraMinZoomDistance = config.MinZoomDistance
	localPlayer.CameraMaxZoomDistance = config.MaxZoomDistance
	bindCharacter(localPlayer.Character)
	renderConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if active then
			hideObstructions(localPlayer.Character)
			updateCamera(deltaTime)
		end
	end)
	inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
		if not active then
			return
		end

		if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	characterAddedConnection = localPlayer.CharacterAdded:Connect(function(character)
		if not active then
			return
		end

		task.defer(function()
			bindCharacter(character)
		end)
	end)
end

function FirstPersonCamera.Disable()
	if not active then
		return
	end

	active = false

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end

	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
		descendantAddedConnection = nil
	end

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if inputChangedConnection then
		inputChangedConnection:Disconnect()
		inputChangedConnection = nil
	end

	UserInputService.MouseBehavior = previousMouseBehavior or Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = if previousMouseIconEnabled == nil then true else previousMouseIconEnabled
	gamepadLook = Vector2.zero
	configureCameraForExit()
	restoreLocalCharacterVisibilityForDuration(config.ExitVisibilityRestoreDuration)
end

function FirstPersonCamera.IsEnabled(): boolean
	return active
end

function FirstPersonCamera.RestoreLocalCharacterVisibility()
	restoreLocalCharacterVisibilityForDuration(config.ExitVisibilityRestoreDuration)
end

return FirstPersonCamera
