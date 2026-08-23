local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PassPlanner = require(Shared.Football.PassPlanner)
local InputController = require(script.Parent:WaitForChild("InputController"))

local PassTargetPresentationController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local activeActionType = ""
local currentPlan = nil
local currentAim = Vector3.new(0, 0, -1)
local previewPart: Part? = nil
local inputConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local lastRefreshAt = 0
local lastSelectionUserId = 0

local function log(message: string)
	print(string.format("%s[Client][PassTarget] %s", GameConfig.LogPrefix, message))
end

local function getFootball(): BasePart?
	local container = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local folder = container and container:FindFirstChild("Ball")
	local ball = folder and folder:FindFirstChild(BallConfig.Name)
	return if ball and ball:IsA("BasePart") then ball else nil
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then root else nil
end

local function isEligibleReceiver(player: Player): boolean
	if player == localPlayer then
		return false
	end

	if localPlayer.Team or player.Team then
		return localPlayer.Team == player.Team
	end

	return FootballActionConfig.Targeting.AllowUnteamedDevelopmentReceivers == true
end

local function collectCandidates()
	local candidates = {}
	for _, player in Players:GetPlayers() do
		if isEligibleReceiver(player) then
			local root = getRoot(player)
			if root then
				table.insert(candidates, {
					Kind = "Player",
					Name = player.Name,
					UserId = player.UserId,
					Instance = player,
					Position = root.Position,
					Velocity = root.AssemblyLinearVelocity,
					FacingDirection = BallControlMath.GetHorizontal(root.CFrame.LookVector),
				})
			end
		end
	end
	return candidates
end

local function hasPossession(ball: BasePart?): boolean
	return ball ~= nil
		and ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
end

local function getFacingDirection(): Vector3
	local root = getRoot(localPlayer)
	return if root
		then BallControlMath.SafeUnit(BallControlMath.GetHorizontal(root.CFrame.LookVector), Vector3.new(0, 0, -1))
		else Vector3.new(0, 0, -1)
end

local function getAimDirection(aimDirection: Vector3?): Vector3
	if typeof(aimDirection) == "Vector3" then
		local horizontal = BallControlMath.GetHorizontal(aimDirection)
		if horizontal.Magnitude > 0.05 then
			return horizontal.Unit
		end
	end
	return getFacingDirection()
end

local function selectPlan(actionType: string, aimDirection: Vector3?)
	local ball = getFootball()
	if not hasPossession(ball) then
		return nil
	end

	local plan = PassPlanner.Plan(
		(ball :: BasePart).Position,
		getAimDirection(aimDirection),
		0,
		actionType,
		collectCandidates(),
		FootballActionConfig,
		1
	)
	return plan
end

local function ensurePreviewPart(): Part
	if previewPart and previewPart.Parent then
		return previewPart
	end

	local part = Instance.new("Part")
	part.Name = "Beyond90LocalPassTargetLine"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = FootballActionConfig.Targeting.LineColor
	part.Transparency = FootballActionConfig.Targeting.LineTransparency
	part.Parent = Workspace
	previewPart = part
	return part
end

local function hidePreview()
	currentPlan = nil
	lastSelectionUserId = 0
	if previewPart then
		previewPart:Destroy()
		previewPart = nil
	end
end

local function getFloorPoint(position: Vector3, exclusions: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local result = Workspace:Raycast(position + Vector3.yAxis * 4, Vector3.yAxis * -20, params)
	local groundY = if result then result.Position.Y else position.Y - 3
	return Vector3.new(position.X, groundY + FootballActionConfig.Targeting.LineHeight, position.Z)
end

local function updateLine()
	if activeActionType == "" or not currentPlan or not currentPlan.SelectedCandidate then
		hidePreview()
		return
	end

	local receiver = currentPlan.SelectedCandidate.Instance
	local passerRoot = getRoot(localPlayer)
	local receiverRoot = if receiver and receiver:IsA("Player") then getRoot(receiver) else nil
	local ball = getFootball()
	if not passerRoot or not receiverRoot or not hasPossession(ball) then
		hidePreview()
		return
	end

	local exclusions = { localPlayer.Character :: Instance, receiver.Character :: Instance }
	if ball then
		table.insert(exclusions, ball)
	end
	local startPoint = getFloorPoint(passerRoot.Position, exclusions)
	local endPoint = getFloorPoint(receiverRoot.Position, exclusions)
	local distance = (endPoint - startPoint).Magnitude
	if distance <= 0.1 then
		hidePreview()
		return
	end

	local part = ensurePreviewPart()
	local thickness = FootballActionConfig.Targeting.LineThickness
	part.Size = Vector3.new(thickness, thickness, distance)
	part.CFrame = CFrame.lookAt((startPoint + endPoint) / 2, endPoint)
end

local function refreshSelection()
	if activeActionType == "" then
		return
	end

	currentPlan = selectPlan(activeActionType, currentAim)
	local userId = if currentPlan and currentPlan.SelectedCandidate then currentPlan.SelectedCandidate.UserId or 0 else 0
	if userId ~= lastSelectionUserId then
		lastSelectionUserId = userId
		if currentPlan then
			log(string.format(
				"receiver=%s distance=%.1f score=%.2f targetPosition=%s",
				currentPlan.SelectedCandidate.Name,
				currentPlan.Distance,
				currentPlan.Score,
				tostring(currentPlan.TargetPosition)
			))
		else
			log("result=none reason=no-valid-receiver")
		end
	end
end

local function onFootballAction(action)
	if typeof(action) ~= "table" then
		return
	end

	local actionType = action.ActionType
	if actionType ~= "GroundPass" and actionType ~= "ThroughPass" then
		return
	end

	if action.Phase == "Pressed" then
		activeActionType = actionType
		currentAim = getAimDirection(action.AimDirection)
		refreshSelection()
	elseif action.Phase == "Released" or action.Phase == "Cancelled" then
		activeActionType = ""
		hidePreview()
	end
end

function PassTargetPresentationController.Select(actionType: string, aimDirection: Vector3?)
	return selectPlan(actionType, aimDirection)
end

function PassTargetPresentationController.Initialize()
	if initialized then
		return
	end
	initialized = true
	inputConnection = InputController.GetFootballActionEvent().Event:Connect(onFootballAction)
	renderConnection = RunService.RenderStepped:Connect(function()
		if activeActionType == "" then
			return
		end

		currentAim = getAimDirection(InputController.GetInputState().MoveDirection)
		if os.clock() - lastRefreshAt >= FootballActionConfig.Targeting.PreviewRefreshInterval then
			lastRefreshAt = os.clock()
			refreshSelection()
		end
		updateLine()
	end)
end

function PassTargetPresentationController.Destroy()
	initialized = false
	activeActionType = ""
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	hidePreview()
end

return PassTargetPresentationController
