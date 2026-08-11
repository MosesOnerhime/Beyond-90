local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PitchConfig = require(Shared.Config.PitchConfig)

local BallService = {}

local function getRootFolder(): Folder
	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	assert(rootFolder and rootFolder:IsA("Folder"), "Beyond90 workspace container must exist before BallService initializes")

	return rootFolder
end

local function getOrCreateBallFolder(rootFolder: Folder): Folder
	local existing = rootFolder:FindFirstChild("Ball")

	if existing then
		assert(existing:IsA("Folder"), string.format("%s exists but is not a Folder", existing:GetFullName()))
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "Ball"
	folder.Parent = rootFolder

	return folder
end

local function getOrCreateFootball(ballFolder: Folder): Part
	local existing = ballFolder:FindFirstChild(BallConfig.Name)

	if existing then
		assert(existing:IsA("Part"), string.format("%s exists but is not a Part", existing:GetFullName()))
		return existing
	end

	local ball = Instance.new("Part")
	ball.Name = BallConfig.Name
	ball.Parent = ballFolder

	return ball
end

function BallService.Initialize()
	local rootFolder = getRootFolder()
	local ballFolder = getOrCreateBallFolder(rootFolder)
	local ball = getOrCreateFootball(ballFolder)
	local radius = BallConfig.Radius
	local physics = BallConfig.PhysicalProperties

	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	ball.Position = Vector3.new(PitchConfig.BallCenterPosition.X, BallConfig.SpawnHeight, PitchConfig.BallCenterPosition.Z)
	ball.Anchored = false
	ball.CanCollide = true
	ball.CanQuery = true
	ball.CanTouch = true
	ball.Color = Color3.fromRGB(245, 245, 245)
	ball.Material = Enum.Material.SmoothPlastic
	ball.TopSurface = Enum.SurfaceType.Smooth
	ball.BottomSurface = Enum.SurfaceType.Smooth
	ball.CustomPhysicalProperties = PhysicalProperties.new(
		physics.Density,
		physics.Friction,
		physics.Elasticity,
		physics.FrictionWeight,
		physics.ElasticityWeight
	)
	ball:SetAttribute("Beyond90Football", true)
	ball:SetAttribute("ServerOwned", true)
	ball:SetNetworkOwner(nil)

	return ball
end

return BallService
