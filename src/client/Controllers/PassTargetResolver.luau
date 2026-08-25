local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local FootballTeamEligibility = require(Shared.Football.FootballTeamEligibility)
local GameConfig = require(Shared.Config.GameConfig)
local PassPlanner = require(Shared.Football.PassPlanner)
local InputController = require(script.Parent:WaitForChild("InputController"))

local PassTargetResolver = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local activeActionType = ""
local currentAim = Vector3.new(0, 0, -1)
local currentPlan = nil
local lastRefreshAt = 0
local inputConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local changedEvent = Instance.new("BindableEvent")

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

local function getAimDirection(direction: Vector3?): Vector3
	if typeof(direction) == "Vector3" then
		local horizontal = BallControlMath.GetHorizontal(direction)
		if horizontal.Magnitude > 0.05 then
			return horizontal.Unit
		end
	end
	return getFacingDirection()
end

local function collectCandidates()
	local candidates = {}
	for _, player in Players:GetPlayers() do
		local eligible = FootballTeamEligibility.AreTeammates(localPlayer, player, FootballActionConfig.Targeting)
		if eligible then
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

local function setPlan(plan)
	local previousId = if currentPlan and currentPlan.SelectedCandidate then currentPlan.SelectedCandidate.UserId else 0
	local nextId = if plan and plan.SelectedCandidate then plan.SelectedCandidate.UserId else 0
	currentPlan = plan
	if previousId ~= nextId then
		if plan then
			log(string.format(
				"receiverUserId=%d receiver=%s distance=%.1f angle=%.1f score=%.2f locked=true",
				nextId,
				plan.SelectedCandidate.Name,
				plan.Distance,
				plan.AngleDegrees or 0,
				plan.Score
			))
		else
			log("result=none reason=no-valid-receiver")
		end
	end
	changedEvent:Fire(currentPlan)
end

local function refreshSelection()
	if activeActionType == "" then
		return
	end

	local ball = getFootball()
	if not hasPossession(ball) then
		setPlan(nil)
		return
	end

	local candidates = collectCandidates()
	local bestPlan = PassPlanner.Plan(ball.Position, currentAim, 0, activeActionType, candidates, FootballActionConfig, 1)
	local retainedPlan = nil
	if currentPlan and currentPlan.SelectedCandidate then
		local retainedUserId = currentPlan.SelectedCandidate.UserId
		for _, candidate in candidates do
			if candidate.UserId == retainedUserId then
				retainedPlan = PassPlanner.PlanForReceiver(
					ball.Position,
					currentAim,
					0,
					activeActionType,
					candidate,
					FootballActionConfig,
					1,
					FootballActionConfig.Targeting.RetentionConeDegrees
				)
				break
			end
		end
	end

	if retainedPlan and bestPlan and bestPlan.SelectedCandidate.UserId ~= retainedPlan.SelectedCandidate.UserId then
		if bestPlan.Score <= retainedPlan.Score + FootballActionConfig.Targeting.SwitchScoreMargin then
			bestPlan = retainedPlan
		end
	elseif retainedPlan then
		bestPlan = retainedPlan
	end

	setPlan(bestPlan)
end

local function clearSelection()
	activeActionType = ""
	if currentPlan then
		setPlan(nil)
	end
end

local function onFootballAction(action)
	if typeof(action) ~= "table" then
		return
	end
	if action.ActionType ~= "GroundPass" and action.ActionType ~= "ThroughPass" and action.ActionType ~= "LobPass" then
		return
	end

	if action.Phase == "Pressed" then
		activeActionType = action.ActionType
		currentAim = getAimDirection(action.AimDirection)
		refreshSelection()
	elseif action.Phase == "Cancelled" then
		clearSelection()
	elseif action.Phase == "Released" then
		activeActionType = ""
		task.delay(0.25, function()
			if activeActionType == "" then
				setPlan(nil)
			end
		end)
	end
end

function PassTargetResolver.GetSelection()
	return currentPlan
end

function PassTargetResolver.ConsumeSelection(actionType: string)
	if not currentPlan or currentPlan.ActionType ~= actionType then
		return nil
	end
	local selected = currentPlan
	-- The release path owns cleanup after the request has consumed this exact
	-- receiver. Clearing here caused a one-frame line/receiver loss before send.
	return selected
end

function PassTargetResolver.GetChangedEvent(): BindableEvent
	return changedEvent
end

function PassTargetResolver.Initialize()
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
	end)
end

function PassTargetResolver.Destroy()
	initialized = false
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	clearSelection()
end

return PassTargetResolver
