local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerConfig = require(Shared.Config.PlayerConfig)
local MovementController = require(script.Parent:WaitForChild("MovementController"))

local PlayerIndicatorController = {}

local localPlayer = Players.LocalPlayer
local config = PlayerConfig.Presentation.PlayerIndicator
local initialized = false
local renderConnection: RBXScriptConnection? = nil
local container: Folder? = nil
local segments: { Part } = {}
local arrow: WedgePart? = nil
local smoothedAngle: number? = nil

local function createPart(className: string, name: string): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = config.Transparency
	return part
end

local function ensureIndicator()
	if container and container.Parent then
		return
	end

	container = Instance.new("Folder")
	container.Name = "Beyond90LocalPlayerIndicator"
	container.Parent = Workspace
	table.clear(segments)

	for index = 1, config.SegmentCount do
		local segment = createPart("Part", string.format("Ring%02d", index)) :: Part
		segment.Size = Vector3.new(config.SegmentLength, config.SegmentHeight, config.SegmentThickness)
		segment.Parent = container
		table.insert(segments, segment)
	end

	arrow = createPart("WedgePart", "DirectionArrow") :: WedgePart
	arrow.Size = config.ArrowSize
	arrow.Parent = container
end

local function getRoot(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getGroundPosition(root: BasePart): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance }
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local result = Workspace:Raycast(root.Position, Vector3.yAxis * -config.FloorProbeDistance, params)
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
	local center = getGroundPosition(root)
	local sprinting = localPlayer:GetAttribute("Beyond90AnimationLocomotionFamily") == "Sprint"
	local color = if sprinting then config.SprintColor else config.NormalColor

	for index, segment in segments do
		local angle = (index - 1) / config.SegmentCount * math.pi * 2
		local radial = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local tangent = Vector3.new(math.cos(angle), 0, math.sin(angle))
		segment.Color = color
		segment.CFrame = CFrame.fromMatrix(center + radial * config.Radius, tangent, Vector3.yAxis)
	end

	local movement = MovementController.GetLocomotionState()
	local direction = if movement.RawDirection.Magnitude > 0.05 then movement.RawDirection else movement.SmoothedDirection
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
	if arrow then
		arrow.Color = color
		local position = center + worldRadial * (config.Radius + 0.12) + Vector3.yAxis * 0.02
		arrow.CFrame = CFrame.lookAt(position, position + worldRadial) * CFrame.Angles(0, math.pi, 0)
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
	table.clear(segments)
	arrow = nil
	smoothedAngle = nil
end

return PlayerIndicatorController
