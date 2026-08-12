local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local MovementController = {}

local localPlayer = Players.LocalPlayer
local movementConfig = PlayerConfig.Movement
local inputConfig = PlayerConfig.Input
local controlConfig = BallConfig.Control
local renderStepName = "Beyond90BallControlAssist"

local initialized = false
local currentHumanoid: Humanoid? = nil
local sprintRequested = false
local sprintRemote: RemoteEvent? = nil
local characterAddedConnection: RBXScriptConnection? = nil
local humanoidDiedConnection: RBXScriptConnection? = nil
local cachedBall: BasePart? = nil
local lastLeadDiagnosticTime = 0

local function warnLog(message: string)
	warn(string.format("%s[Client][Movement] %s", GameConfig.LogPrefix, message))
end

local function log(message: string)
	print(string.format("%s[Client][Movement] %s", GameConfig.LogPrefix, message))
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

local function getRootPart(): BasePart?
	local character = localPlayer.Character

	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	return rootPart
end

local function getFootball(): BasePart?
	if cachedBall and cachedBall.Parent then
		return cachedBall
	end

	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = rootFolder and rootFolder:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)

	if ball and ball:IsA("BasePart") then
		cachedBall = ball
		return ball
	end

	cachedBall = nil
	return nil
end

local function isLocalController(ball: BasePart): boolean
	return ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
end

local function getFacingDirection(rootPart: BasePart): Vector3
	return BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
		Vector3.new(0, 0, -1)
	)
end

local function updateClientLeadDiagnostic(ball: BasePart, rootPart: BasePart, controlDirection: Vector3, assistBias: number)
	local lead = BallControlMath.GetHorizontal(ball.Position - rootPart.Position):Dot(controlDirection)
	ball:SetAttribute("ClientBallLead", lead)

	local now = os.clock()

	if now - lastLeadDiagnosticTime < controlConfig.LeadDiagnosticInterval then
		return
	end

	lastLeadDiagnosticTime = now
	local serverLead = ball:GetAttribute("ServerBallLead")
	log(string.format(
		"Lead sample client=%.2f server=%s assistBias=%.2f",
		lead,
		if typeof(serverLead) == "number" then string.format("%.2f", serverLead) else "n/a",
		assistBias
	))
end

local function updateBallControlAssist()
	local humanoid = currentHumanoid

	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local ball = getFootball()

	if not ball or not isLocalController(ball) then
		return
	end

	local rootPart = getRootPart()

	if not rootPart then
		return
	end

	local manualMovement = BallControlMath.GetHorizontal(humanoid.MoveDirection)
	local manualSpeed = manualMovement.Magnitude
	local fallbackDirection = getFacingDirection(rootPart)
	local diagnosticDirection = if manualSpeed > 0.05 then manualMovement.Unit else fallbackDirection

	if manualSpeed <= 0.05 then
		updateClientLeadDiagnostic(ball, rootPart, diagnosticDirection, 0)
		return
	end

	local assistDirection, distanceToPredictedBall = BallControlMath.GetContactAssistDirection(
		rootPart.Position,
		ball.Position,
		ball.AssemblyLinearVelocity,
		fallbackDirection,
		controlConfig
	)

	if assistDirection.Magnitude <= 0 then
		updateClientLeadDiagnostic(ball, rootPart, diagnosticDirection, 0)
		return
	end

	local manualDirection = manualMovement.Unit
	local assistBias = BallControlMath.GetAssistBias(distanceToPredictedBall, manualDirection, assistDirection, controlConfig)
	local assistedDirection = BallControlMath.BlendManualAndAssistDirection(manualDirection, assistDirection, assistBias)

	if assistedDirection.Magnitude <= 0 then
		updateClientLeadDiagnostic(ball, rootPart, manualDirection, 0)
		return
	end

	humanoid:Move(assistedDirection, false)
	updateClientLeadDiagnostic(ball, rootPart, assistedDirection, assistBias)
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
	RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Character.Value + 1, updateBallControlAssist)

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
	RunService:UnbindFromRenderStep(renderStepName)

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
