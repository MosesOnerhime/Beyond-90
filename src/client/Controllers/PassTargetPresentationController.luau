local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GroundProbe = require(Shared.World.GroundProbe)
local PassTargetResolver = require(script.Parent:WaitForChild("PassTargetResolver"))

local PassTargetPresentationController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local previewPart: Part? = nil
local renderConnection: RBXScriptConnection? = nil

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
	if previewPart then
		previewPart:Destroy()
		previewPart = nil
	end
end

local function getFloorPoint(position: Vector3, exclusions: { Instance }): Vector3
	local result = GroundProbe.Raycast(position + Vector3.yAxis * 4, 24, exclusions)
	local groundY = if result then result.Position.Y else position.Y - 3
	return Vector3.new(position.X, groundY + FootballActionConfig.Targeting.LineHeight, position.Z)
end

local function updateLine()
	local plan = PassTargetResolver.GetSelection()
	local candidate = plan and plan.SelectedCandidate
	local receiver = candidate and candidate.Instance
	local passerRoot = getRoot(localPlayer)
	local receiverRoot = if receiver and receiver:IsA("Player") then getRoot(receiver) else nil
	local ball = getFootball()
	if not plan or not passerRoot or not receiverRoot or not hasPossession(ball) then
		hidePreview()
		return
	end

	local exclusions = { localPlayer.Character :: Instance, receiver.Character :: Instance }
	if ball then
		table.insert(exclusions, ball)
	end
	local startPoint = getFloorPoint(ball.Position, exclusions)
	local target = plan.TargetPosition or receiverRoot.Position
	local endPoint = getFloorPoint(target, exclusions)
	local distance = (endPoint - startPoint).Magnitude
	if distance <= 0.1 then
		hidePreview()
		return
	end

	local part = ensurePreviewPart()
	part.Size = Vector3.new(
		FootballActionConfig.Targeting.LineThickness,
		FootballActionConfig.Targeting.LineDepth,
		distance
	)
	part.CFrame = CFrame.lookAt((startPoint + endPoint) / 2, endPoint)
end

function PassTargetPresentationController.Initialize()
	if initialized then
		return
	end
	initialized = true
	renderConnection = RunService.RenderStepped:Connect(updateLine)
end

function PassTargetPresentationController.Destroy()
	initialized = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	hidePreview()
end

return PassTargetPresentationController
