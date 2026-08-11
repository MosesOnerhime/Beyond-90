local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local MovementController = {}

local localPlayer = Players.LocalPlayer
local movementConfig = PlayerConfig.Movement
local inputConfig = PlayerConfig.Input

local initialized = false
local currentHumanoid: Humanoid? = nil
local sprintRequested = false
local sprintRemote: RemoteEvent? = nil
local characterAddedConnection: RBXScriptConnection? = nil
local humanoidDiedConnection: RBXScriptConnection? = nil

local function warnLog(message: string)
	warn(string.format("%s[Client][Movement] %s", GameConfig.LogPrefix, message))
end

local function getSprintSpeed(): number
	if sprintRequested then
		return movementConfig.SprintSpeed
	end

	return movementConfig.BaseSpeed
end

local function applyMovementSettings(humanoid: Humanoid)
	humanoid.WalkSpeed = getSprintSpeed()
	humanoid.AutoRotate = movementConfig.AutoRotate
	humanoid.UseJumpPower = true
	humanoid.JumpPower = movementConfig.JumpPower
	humanoid.JumpHeight = movementConfig.JumpHeight
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, movementConfig.JumpEnabled)

	if not movementConfig.JumpEnabled then
		humanoid.Jump = false
	end
end

local function sendSprintRequest(requested: boolean)
	if not sprintRemote then
		warnLog("Sprint remote is unavailable; local sprint prediction only")
		return
	end

	sprintRemote:FireServer(requested)
end

local function setSprintRequested(requested: boolean)
	if sprintRequested == requested then
		return
	end

	sprintRequested = requested

	if currentHumanoid then
		applyMovementSettings(currentHumanoid)
	end

	sendSprintRequest(requested)
end

local function onSprintAction(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		setSprintRequested(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprintRequested(false)
	end

	return Enum.ContextActionResult.Sink
end

local function configureCharacter(character: Model)
	sprintRequested = false

	if humanoidDiedConnection then
		humanoidDiedConnection:Disconnect()
		humanoidDiedConnection = nil
	end

	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid or not humanoid:IsA("Humanoid") then
		warnLog("Character missing Humanoid; movement settings were not applied")
		currentHumanoid = nil
		return
	end

	currentHumanoid = humanoid
	applyMovementSettings(humanoid)
	sendSprintRequest(false)

	humanoidDiedConnection = humanoid.Died:Connect(function()
		setSprintRequested(false)
	end)
end

local function bindSprintInput()
	ContextActionService:BindAction(
		inputConfig.SprintActionName,
		onSprintAction,
		true,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonL3
	)

	ContextActionService:SetTitle(inputConfig.SprintActionName, "Sprint")
	ContextActionService:SetPosition(inputConfig.SprintActionName, inputConfig.SprintTouchButtonPosition)
end

local function resolveSprintRemote()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)

	if not remotes then
		warnLog("ReplicatedStorage.Remotes was not found")
		return
	end

	local remote = remotes:WaitForChild(inputConfig.SprintRemoteName, 10)

	if not remote or not remote:IsA("RemoteEvent") then
		warnLog(string.format("%s remote was not found", inputConfig.SprintRemoteName))
		return
	end

	sprintRemote = remote
end

function MovementController.Initialize()
	if initialized then
		return
	end

	initialized = true
	resolveSprintRemote()
	bindSprintInput()

	characterAddedConnection = localPlayer.CharacterAdded:Connect(configureCharacter)

	if localPlayer.Character then
		configureCharacter(localPlayer.Character)
	end
end

function MovementController.Destroy()
	if not initialized then
		return
	end

	initialized = false
	ContextActionService:UnbindAction(inputConfig.SprintActionName)

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end

	if humanoidDiedConnection then
		humanoidDiedConnection:Disconnect()
		humanoidDiedConnection = nil
	end

	currentHumanoid = nil
	sprintRequested = false
end

return MovementController
