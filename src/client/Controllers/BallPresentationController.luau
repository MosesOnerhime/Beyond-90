local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local BallPresentationController = {}

local localPlayer = Players.LocalPlayer
local visualConfig = BallConfig.Visual
local ownershipConfig = BallConfig.Ownership
local movementConfig = PlayerConfig.Movement
local renderStepName = "Beyond90BallPresentation"

local initialized = false
local proxyBall: Part? = nil
local cachedBall: BasePart? = nil
local proxyPosition: Vector3? = nil
local proxyRotation = CFrame.identity
local activeAuthoritativeBall: BasePart? = nil
local hiddenBasePartTransparency: { [BasePart]: number } = {}
local hiddenSurfaceGuiEnabled: { [SurfaceGui]: boolean } = {}
local reconciling = false
local reconcileStartedAt = 0
local reconcileStartPosition: Vector3? = nil
local lastDiagnosticTime = 0

local function log(message: string)
	print(string.format("%s[Client][BallPresentation] %s", GameConfig.LogPrefix, message))
end

local function isPresentationProxyEnabled(): boolean
	return ownershipConfig.ControlledBallOwnershipMode == "Server"
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

local function getRootAndHumanoid(): (BasePart?, Humanoid?)
	local character = localPlayer.Character

	if not character then
		return nil, nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end

	return rootPart, humanoid
end

local function getFacingDirection(rootPart: BasePart): Vector3
	return BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
		Vector3.new(0, 0, -1)
	)
end

local function getControlDirection(rootPart: BasePart, humanoid: Humanoid): (Vector3, number, boolean)
	local moveDirection = BallControlMath.GetHorizontal(humanoid.MoveDirection)
	local rootVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local speed = rootVelocity.Magnitude
	local isMoving = moveDirection.Magnitude > 0.05 or speed > 1

	if moveDirection.Magnitude > 0.05 then
		return moveDirection.Unit, speed, isMoving
	end

	if speed > 1 then
		return rootVelocity.Unit, speed, isMoving
	end

	return getFacingDirection(rootPart), speed, false
end

local function isSprinting(humanoid: Humanoid): boolean
	return humanoid.WalkSpeed > movementConfig.BaseSpeed + 0.5
end

local function isLocalController(ball: BasePart): boolean
	return ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
end

local function configureProxyVisualPart(part: BasePart, proxy: BasePart)
	part:SetAttribute("Beyond90LocalVisualBall", true)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = proxy

	local weld = Instance.new("WeldConstraint")
	weld:SetAttribute("Beyond90LocalVisualBall", true)
	weld.Part0 = proxy
	weld.Part1 = part
	weld.Parent = part
end

local function createVisualBand(proxy: BasePart, name: string, size: Vector3, color: Color3, orientation: Vector3)
	local band = Instance.new("Part")
	band.Name = name
	band.Shape = Enum.PartType.Block
	band.Size = size
	band.Color = color
	band.CFrame = proxy.CFrame * CFrame.Angles(
		math.rad(orientation.X),
		math.rad(orientation.Y),
		math.rad(orientation.Z)
	)
	configureProxyVisualPart(band, proxy)
end

local function createBrandMark(proxy: BasePart)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "Beyond90LocalBrandMark"
	surfaceGui:SetAttribute("Beyond90LocalVisualBall", true)
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 140
	surfaceGui.Parent = proxy

	local label = Instance.new("TextLabel")
	label.Name = "BrandText"
	label:SetAttribute("Beyond90LocalVisualBall", true)
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = visualConfig.BrandText
	label.TextColor3 = visualConfig.AccentColor
	label.TextScaled = true
	label.Parent = surfaceGui
end

local function createProxyBall(position: Vector3): Part
	local radius = (visualConfig.VisualDiameter or visualConfig.PresentationDiameter) / 2
	local proxy = Instance.new("Part")
	proxy.Name = "Beyond90LocalVisualFootball"
	proxy:SetAttribute("Beyond90LocalVisualBall", true)
	proxy.Shape = Enum.PartType.Ball
	proxy.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	proxy.CFrame = CFrame.new(position)
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanTouch = false
	proxy.CanQuery = false
	proxy.CastShadow = true
	proxy.Material = Enum.Material.SmoothPlastic
	proxy.Color = visualConfig.BaseColor
	proxy.Parent = Workspace

	local bandThickness = radius * 0.16
	local bandLength = radius * 1.9
	createVisualBand(
		proxy,
		"CharcoalPanelBandA",
		Vector3.new(bandLength, bandThickness, radius * 0.08),
		visualConfig.PanelColor,
		Vector3.zero
	)
	createVisualBand(
		proxy,
		"CharcoalPanelBandB",
		Vector3.new(bandThickness, bandLength, radius * 0.08),
		visualConfig.PanelColor,
		Vector3.new(0, 0, 35)
	)
	createVisualBand(
		proxy,
		"PurpleAccentBand",
		Vector3.new(bandLength * 0.72, bandThickness * 0.75, radius * 0.09),
		visualConfig.AccentColor,
		Vector3.new(0, 0, -35)
	)
	createBrandMark(proxy)

	return proxy
end

local function hideAuthoritativeBall(ball: BasePart)
	if activeAuthoritativeBall == ball then
		return
	end

	for part in hiddenBasePartTransparency do
		if part.Parent then
			part.LocalTransparencyModifier = hiddenBasePartTransparency[part]
		end
	end

	for gui in hiddenSurfaceGuiEnabled do
		if gui.Parent then
			gui.Enabled = hiddenSurfaceGuiEnabled[gui]
		end
	end

	table.clear(hiddenBasePartTransparency)
	table.clear(hiddenSurfaceGuiEnabled)
	activeAuthoritativeBall = ball

	for _, descendant in ball:GetDescendants() do
		if descendant:IsA("BasePart") then
			hiddenBasePartTransparency[descendant] = descendant.LocalTransparencyModifier
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("SurfaceGui") then
			hiddenSurfaceGuiEnabled[descendant] = descendant.Enabled
			descendant.Enabled = false
		end
	end

	hiddenBasePartTransparency[ball] = ball.LocalTransparencyModifier
	ball.LocalTransparencyModifier = 1
end

local function restoreAuthoritativeBall()
	for part, transparency in hiddenBasePartTransparency do
		if part.Parent then
			part.LocalTransparencyModifier = transparency
		end
	end

	for gui, enabled in hiddenSurfaceGuiEnabled do
		if gui.Parent then
			gui.Enabled = enabled
		end
	end

	table.clear(hiddenBasePartTransparency)
	table.clear(hiddenSurfaceGuiEnabled)
	activeAuthoritativeBall = nil
end

local function destroyProxy()
	if proxyBall then
		proxyBall:Destroy()
		proxyBall = nil
	end

	proxyPosition = nil
	proxyRotation = CFrame.identity
	reconciling = false
	reconcileStartPosition = nil
end

local function cleanup()
	restoreAuthoritativeBall()
	destroyProxy()
end

local function getDesiredVisualPosition(ball: BasePart, rootPart: BasePart, humanoid: Humanoid): (Vector3, Vector3, boolean)
	local direction, speed, isMoving = getControlDirection(rootPart, humanoid)
	local visualRadius = (visualConfig.VisualDiameter or visualConfig.PresentationDiameter) / 2
	local centerY = ball.Position.Y + visualRadius - BallConfig.Radius
	local leadDistance

	if isMoving then
		local modeLead = if isSprinting(humanoid) then visualConfig.SprintLeadDistance else visualConfig.WalkLeadDistance
		leadDistance = math.max(
			modeLead + speed * visualConfig.VisualLeadTime,
			visualConfig.MinimumMovingLeadDistance
		)
	else
		leadDistance = visualConfig.StationaryLeadDistance
	end

	return Vector3.new(rootPart.Position.X, centerY, rootPart.Position.Z) + direction * leadDistance, direction, isMoving
end

local function updateRotation(previousPosition: Vector3, nextPosition: Vector3)
	local visualRadius = (visualConfig.VisualDiameter or visualConfig.PresentationDiameter) / 2
	local displacement = BallControlMath.GetHorizontal(nextPosition - previousPosition)
	local distance = displacement.Magnitude

	if distance <= 0.001 then
		return
	end

	local axis = Vector3.yAxis:Cross(displacement.Unit)

	if axis.Magnitude <= 0.001 then
		return
	end

	proxyRotation = CFrame.fromAxisAngle(axis.Unit, distance / visualRadius) * proxyRotation
end

local function setProxyCFrame(position: Vector3)
	if not proxyBall then
		return
	end

	proxyBall.CFrame = CFrame.new(position) * proxyRotation
end

local function sampleVisualLead(ball: BasePart, rootPart: BasePart, controlDirection: Vector3)
	local visualPosition = proxyPosition

	if not visualPosition then
		return
	end

	local visualLead = BallControlMath.GetHorizontal(visualPosition - rootPart.Position):Dot(controlDirection)
	ball:SetAttribute("VisualBallLead", visualLead)

	local now = os.clock()

	if now - lastDiagnosticTime < visualConfig.LeadDiagnosticInterval then
		return
	end

	lastDiagnosticTime = now
	local serverLead = ball:GetAttribute("ServerBallLead")
	local clientLead = ball:GetAttribute("ClientBallLead")
	log(string.format(
		"Lead sample visual=%.2f client=%s server=%s",
		visualLead,
		if typeof(clientLead) == "number" then string.format("%.2f", clientLead) else "n/a",
		if typeof(serverLead) == "number" then string.format("%.2f", serverLead) else "n/a"
	))
end

local function beginReconciliation()
	if reconciling then
		return
	end

	reconciling = true
	reconcileStartedAt = os.clock()
	reconcileStartPosition = proxyPosition
end

local function updateReconciliation(ball: BasePart)
	if not proxyBall or not proxyPosition or not reconcileStartPosition then
		cleanup()
		return
	end

	local visualRadius = (visualConfig.VisualDiameter or visualConfig.PresentationDiameter) / 2
	local targetPosition = ball.Position + Vector3.yAxis * (visualRadius - BallConfig.Radius)
	local distance = (proxyPosition - targetPosition).Magnitude

	if distance > visualConfig.ExtremeReconciliationDistance then
		cleanup()
		return
	end

	local alpha = math.clamp((os.clock() - reconcileStartedAt) / visualConfig.ReconciliationDuration, 0, 1)
	local nextPosition = reconcileStartPosition:Lerp(targetPosition, alpha)
	updateRotation(proxyPosition, nextPosition)
	proxyPosition = nextPosition
	setProxyCFrame(nextPosition)

	if alpha >= 1 then
		cleanup()
	end
end

local function updatePresentation(deltaTime: number)
	if not isPresentationProxyEnabled() then
		cleanup()
		return
	end

	local ball = getFootball()

	if not ball or not ball.Parent then
		cleanup()
		return
	end

	if reconciling then
		updateReconciliation(ball)
		return
	end

	local rootPart, humanoid = getRootAndHumanoid()
	local shouldPredict = rootPart ~= nil and humanoid ~= nil and isLocalController(ball)

	if not shouldPredict then
		if proxyBall then
			beginReconciliation()
		else
			restoreAuthoritativeBall()
		end
		return
	end

	local desiredPosition, controlDirection, isMoving = getDesiredVisualPosition(ball, rootPart :: BasePart, humanoid :: Humanoid)
	hideAuthoritativeBall(ball)

	if not proxyBall then
		proxyPosition = desiredPosition
		proxyRotation = CFrame.identity
		proxyBall = createProxyBall(desiredPosition)
		ball:SetAttribute("VisualBallLead", BallControlMath.GetHorizontal(desiredPosition - (rootPart :: BasePart).Position):Dot(controlDirection))
		return
	end

	local currentPosition = proxyPosition or desiredPosition
	local targetDelta = BallControlMath.GetHorizontal(desiredPosition - currentPosition)
	local responsiveness = if isMoving then visualConfig.AheadResponsiveness else visualConfig.StationaryResponsiveness

	if targetDelta:Dot(controlDirection) > 0 then
		responsiveness = visualConfig.CatchUpResponsiveness
	end

	local alpha = 1 - math.exp(-responsiveness * math.max(deltaTime, 0))
	local nextPosition = currentPosition:Lerp(desiredPosition, math.clamp(alpha, 0, 1))
	updateRotation(currentPosition, nextPosition)
	proxyPosition = nextPosition
	setProxyCFrame(nextPosition)
	sampleVisualLead(ball, rootPart :: BasePart, controlDirection)
end

function BallPresentationController.Initialize()
	if initialized then
		return
	end

	initialized = true
	RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Camera.Value - 1, updatePresentation)
end

function BallPresentationController.Destroy()
	if not initialized then
		return
	end

	initialized = false
	RunService:UnbindFromRenderStep(renderStepName)
	cleanup()
end

return BallPresentationController
