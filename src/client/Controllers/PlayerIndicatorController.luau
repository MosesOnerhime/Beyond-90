local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local GroundProbe = require(Shared.World.GroundProbe)
local MovementController = require(script.Parent:WaitForChild("MovementController"))

local PlayerIndicatorController = {}

local localPlayer = Players.LocalPlayer
local config = PlayerConfig.Presentation.PlayerIndicator
local initialized = false
local renderConnection: RBXScriptConnection? = nil
local container: Folder? = nil
local segments: { Part } = {}
local glowSegments: { Part } = {}
local arrowParts: { Part } = {}
local smoothedAngle: number? = nil
local smoothedRadius = config.BaseRadius
local smoothedColor = config.NormalColor
local cachedBall: BasePart? = nil
local arrowVisibility = 0
local overheadArrowParts: { Part } = {}

local function createPart(className: string, name: string): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = config.Transparency
	return part
end

local function ensureOverheadArrow(root: BasePart)
	local head = root.Parent and root.Parent:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end
	local stripCount = config.OverheadArrowStripCount or 10
	if #overheadArrowParts == stripCount * 2 and overheadArrowParts[1].Parent then return end
	table.clear(overheadArrowParts)
	for index = 1, stripCount do
		local outline = createPart("Part", string.format("OverheadArrowOutline%d", index)) :: Part
		outline.Color = config.OverheadArrowOutlineColor
		outline.Transparency = 0.04
		outline.Parent = container
		table.insert(overheadArrowParts, outline)
		local fill = createPart("Part", string.format("OverheadArrowFill%d", index)) :: Part
		fill.Color = config.OverheadArrowColor
		fill.Transparency = 0
		fill.Parent = container
		table.insert(overheadArrowParts, fill)
	end
end

local function setOverheadStrip(
	part: Part,
	position: Vector3,
	screenRight: Vector3,
	screenUp: Vector3,
	cameraNormal: Vector3,
	width: number,
	height: number,
	depth: number
)
	part.Size = Vector3.new(width, height, depth)
	part.CFrame = CFrame.fromMatrix(position, screenRight, screenUp, cameraNormal)
end

local function ensureIndicator()
	if container and container.Parent then
		return
	end

	container = Instance.new("Folder")
	container.Name = "Beyond90LocalPlayerIndicator"
	container.Parent = Workspace
	table.clear(segments)
	table.clear(glowSegments)

	for index = 1, config.SegmentCount do
		local glow = createPart("Part", string.format("RingGlow%02d", index)) :: Part
		glow.Transparency = config.GlowTransparency
		glow.Parent = container
		table.insert(glowSegments, glow)
		local segment = createPart("Part", string.format("Ring%02d", index)) :: Part
		segment.Parent = container
		table.insert(segments, segment)
	end

	table.clear(arrowParts)
	for index = 1, config.ArrowStripCount do
		local strip = createPart("Part", string.format("DirectionArrow%02d", index)) :: Part
		strip.Parent = container
		table.insert(arrowParts, strip)
	end
end

local function getFootball(): BasePart?
	if cachedBall and cachedBall.Parent then
		return cachedBall
	end
	local gameRoot = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = gameRoot and gameRoot:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)
	cachedBall = if ball and ball:IsA("BasePart") then ball else nil
	return cachedBall
end

local function getRoot(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getGroundPosition(root: BasePart): Vector3
	local ball = getFootball()
	local exclusions = { root.Parent :: Instance }
	if ball then
		table.insert(exclusions, ball)
	end
	local result = GroundProbe.Raycast(root.Position, config.FloorProbeDistance, exclusions)
	local fallbackY = root.Parent and root.Parent:GetAttribute("Beyond90PitchGroundY")
	local groundY = if result then result.Position.Y elseif typeof(fallbackY) == "number" then fallbackY else root.Position.Y - 4
	return Vector3.new(root.Position.X, groundY + config.GroundOffset, root.Position.Z)
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function update(deltaTime: number)
	if not config.Enabled then
		return
	end

	local root = getRoot()
	if not root then
		if container then
			container:Destroy()
			container = nil
		end
		return
	end

	ensureIndicator()
	ensureOverheadArrow(root)
	local overheadStripCount = config.OverheadArrowStripCount or 10
	if #overheadArrowParts == overheadStripCount * 2 then
		local head = root.Parent and root.Parent:FindFirstChild("Head")
		local camera = Workspace.CurrentCamera
		if head and head:IsA("BasePart") and camera then
			local center = head.Position + Vector3.yAxis * config.OverheadArrowHeight
			local cameraNormal = (camera.CFrame.Position - center).Unit
			local screenUp = camera.CFrame.UpVector
			local screenRight = camera.CFrame.RightVector
			local arrowWidth = config.OverheadArrowWorldSize
			local arrowHeight = config.OverheadArrowWorldHeight or arrowWidth
			local stripHeight = arrowHeight / overheadStripCount
			local outline = config.OverheadArrowOutlineThickness or 0.065
			for index = 1, overheadStripCount do
				local progress = (index - 0.5) / overheadStripCount
				local width = math.max(arrowWidth * (1 - progress), arrowWidth / overheadStripCount)
				local position = center + screenUp * (arrowHeight * (0.5 - progress))
				setOverheadStrip(
					overheadArrowParts[index * 2 - 1],
					position,
					screenRight,
					screenUp,
					cameraNormal,
					width + outline * 2,
					stripHeight + outline,
					0.12
				)
				setOverheadStrip(
					overheadArrowParts[index * 2],
					position + cameraNormal * 0.07,
					screenRight,
					screenUp,
					cameraNormal,
					width,
					stripHeight * 1.08,
					0.075
				)
			end
		end
	end
	local center = getGroundPosition(root)
	local sprinting = localPlayer:GetAttribute("Beyond90AnimationLocomotionFamily") == "Sprint"
	local targetColor = if sprinting then config.SprintColor else config.NormalColor
	local colorAlpha = 1 - math.exp(-config.ColorResponsiveness * deltaTime)
	smoothedColor = smoothedColor:Lerp(targetColor, colorAlpha)
	local ball = getFootball()
	local hasBall = ball ~= nil
		and ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
	local ballLead = if hasBall and ball then (Vector3.new(ball.Position.X, 0, ball.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude else 0
	local stateRadius = if sprinting and hasBall
		then config.SprintPossessionRadius
		elseif sprinting
		then config.SprintRadius
		elseif hasBall
		then config.PossessionRadius
		else config.BaseRadius
	local targetRadius = math.clamp(
		math.max(stateRadius, ballLead + config.PossessionLeadPadding),
		config.BaseRadius,
		config.MaximumRadius
	)
	smoothedRadius += (targetRadius - smoothedRadius) * (1 - math.exp(-config.RadiusResponsiveness * deltaTime))
	local segmentLength = 2 * math.pi * smoothedRadius / config.SegmentCount * 0.98

	for index, segment in segments do
		local angle = (index - 1) / config.SegmentCount * math.pi * 2
		local radial = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local tangent = Vector3.new(math.cos(angle), 0, math.sin(angle))
		segment.Size = Vector3.new(segmentLength, config.SegmentHeight, config.SegmentThickness)
		segment.Color = smoothedColor
		segment.CFrame = CFrame.fromMatrix(center + radial * smoothedRadius, tangent, Vector3.yAxis)
		local glow = glowSegments[index]
		glow.Size = Vector3.new(segmentLength * 1.04, config.SegmentHeight * 0.75, config.GlowThickness)
		glow.Color = config.GlowColor
		glow.CFrame = CFrame.fromMatrix(center + radial * smoothedRadius - Vector3.yAxis * 0.008, tangent, Vector3.yAxis)
	end

	local movement = MovementController.GetLocomotionState()
	local direction = if movement.InputDirection.Magnitude > 0.05 then movement.InputDirection else movement.RawDirection
	if direction.Magnitude > 0.05 then
		local localDirection = root.CFrame:VectorToObjectSpace(direction.Unit)
		local desiredAngle = math.atan2(localDirection.X, -localDirection.Z)
		if smoothedAngle == nil then
			smoothedAngle = desiredAngle
		else
			local alpha = 1 - math.exp(-config.ArrowResponsiveness * deltaTime)
			smoothedAngle += wrapAngle(desiredAngle - smoothedAngle) * alpha
		end
	end

	local angle = smoothedAngle or 0
	local localRadial = Vector3.new(math.sin(angle), 0, -math.cos(angle))
	local worldRadial = root.CFrame:VectorToWorldSpace(localRadial)
	worldRadial = Vector3.new(worldRadial.X, 0, worldRadial.Z).Unit
	local intentActive = movement.InputMagnitude >= config.ArrowShowIntentThreshold
		and (movement.InputDirection.Magnitude > 0.05 or localPlayer:GetAttribute("Beyond90PendingTurnActive") == true)
	local targetVisibility = if intentActive then 1 else 0
	arrowVisibility += (targetVisibility - arrowVisibility)
		* (1 - math.exp(-config.ArrowFadeResponsiveness * deltaTime))
	local tangent = Vector3.yAxis:Cross(worldRadial).Unit
	local stripDepth = config.ArrowLength / config.ArrowStripCount
	local baseDistance = smoothedRadius + config.SegmentThickness / 2 + config.ArrowGap
	for index, strip in arrowParts do
		local progress = (index - 0.5) / config.ArrowStripCount
		local width = math.max(config.ArrowWidth * (1 - progress), config.ArrowWidth * 0.08)
		local position = center
			+ worldRadial * (baseDistance + (index - 0.5) * stripDepth)
			+ Vector3.yAxis * 0.025
		strip.Size = Vector3.new(width, config.ArrowHeight, stripDepth * 1.05)
		strip.Color = smoothedColor
		strip.Transparency = 1 - (1 - config.Transparency) * arrowVisibility
		strip.CFrame = CFrame.fromMatrix(position, tangent, Vector3.yAxis, -worldRadial)
	end
end

function PlayerIndicatorController.Initialize()
	if initialized then
		return
	end
	initialized = true
	renderConnection = RunService.RenderStepped:Connect(update)
end

function PlayerIndicatorController.Destroy()
	initialized = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if container then
		container:Destroy()
		container = nil
	end
	table.clear(overheadArrowParts)
	table.clear(segments)
	table.clear(glowSegments)
	table.clear(arrowParts)
	smoothedAngle = nil
	smoothedRadius = config.BaseRadius
	smoothedColor = config.NormalColor
	cachedBall = nil
	arrowVisibility = 0
end

return PlayerIndicatorController
