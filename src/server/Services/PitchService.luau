local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PitchConfig = require(Shared.Config.PitchConfig)

local PitchService = {}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)

	if existing then
		assert(existing:IsA("Folder"), string.format("%s exists but is not a Folder", existing:GetFullName()))
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent

	return folder
end

local function getOrCreatePart(parent: Instance, name: string, className: string?): BasePart
	local existing = parent:FindFirstChild(name)

	if existing then
		assert(existing:IsA("BasePart"), string.format("%s exists but is not a BasePart", existing:GetFullName()))
		return existing
	end

	local part = Instance.new(className or "Part")
	part.Name = name
	part.Parent = parent

	return part :: BasePart
end

local function configurePart(part: BasePart, size: Vector3, position: Vector3, color: Color3, transparency: number, canCollide: boolean)
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanQuery = true
	part.CanTouch = true
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.Position = position
	part.Transparency = transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function createSurface(pitchFolder: Folder)
	local surface = getOrCreatePart(pitchFolder, "PlayingSurface")

	configurePart(
		surface,
		PitchConfig.SurfaceSize,
		PitchConfig.SurfacePosition,
		Color3.fromRGB(35, 130, 65),
		0,
		true
	)

	return surface
end

local function createMarkings(pitchFolder: Folder)
	local markingsFolder = getOrCreateFolder(pitchFolder, "Markings")
	local lineColor = Color3.fromRGB(235, 235, 235)
	local lineY = PitchConfig.LineY
	local lineHeight = PitchConfig.LineHeight
	local lineThickness = PitchConfig.LineThickness
	local halfWidth = PitchConfig.Width / 2
	local halfLength = PitchConfig.Length / 2

	local markings = {
		{
			Name = "CenterLine",
			Size = Vector3.new(PitchConfig.Width, lineHeight, lineThickness),
			Position = Vector3.new(0, lineY, 0),
		},
		{
			Name = "LeftTouchline",
			Size = Vector3.new(lineThickness, lineHeight, PitchConfig.Length),
			Position = Vector3.new(-halfWidth, lineY, 0),
		},
		{
			Name = "RightTouchline",
			Size = Vector3.new(lineThickness, lineHeight, PitchConfig.Length),
			Position = Vector3.new(halfWidth, lineY, 0),
		},
		{
			Name = "NorthGoalLine",
			Size = Vector3.new(PitchConfig.Width, lineHeight, lineThickness),
			Position = Vector3.new(0, lineY, halfLength),
		},
		{
			Name = "SouthGoalLine",
			Size = Vector3.new(PitchConfig.Width, lineHeight, lineThickness),
			Position = Vector3.new(0, lineY, -halfLength),
		},
	}

	for _, marking in markings do
		local part = getOrCreatePart(markingsFolder, marking.Name)
		configurePart(part, marking.Size, marking.Position, lineColor, 0, false)
	end
end

local function createGoals(pitchFolder: Folder)
	local goalsFolder = getOrCreateFolder(pitchFolder, "Goals")
	local goalColor = Color3.fromRGB(245, 215, 80)
	local zoneY = PitchConfig.LineY + 0.08
	local halfLength = PitchConfig.Length / 2
	local zoneSize = Vector3.new(PitchConfig.GoalWidth, 0.2, PitchConfig.GoalDepth)

	local northGoal = getOrCreatePart(goalsFolder, "NorthGoalZone")
	configurePart(
		northGoal,
		zoneSize,
		Vector3.new(0, zoneY, halfLength - PitchConfig.GoalDepth / 2),
		goalColor,
		0.6,
		false
	)
	northGoal:SetAttribute("Beyond90GoalZone", true)
	northGoal:SetAttribute("GoalSide", "North")

	local southGoal = getOrCreatePart(goalsFolder, "SouthGoalZone")
	configurePart(
		southGoal,
		zoneSize,
		Vector3.new(0, zoneY, -halfLength + PitchConfig.GoalDepth / 2),
		goalColor,
		0.6,
		false
	)
	southGoal:SetAttribute("Beyond90GoalZone", true)
	southGoal:SetAttribute("GoalSide", "South")
end

local function createSpawn(rootFolder: Folder)
	local spawnsFolder = getOrCreateFolder(rootFolder, "Spawns")
	local spawn = getOrCreatePart(spawnsFolder, "DevelopmentSpawn", "SpawnLocation") :: SpawnLocation

	configurePart(
		spawn,
		Vector3.new(8, 1, 8),
		PitchConfig.SpawnPosition,
		Color3.fromRGB(60, 165, 255),
		0.25,
		true
	)

	spawn.Enabled = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.AllowTeamChangeOnTouch = false

	return spawn
end

function PitchService.Initialize()
	local rootFolder = getOrCreateFolder(Workspace, GameConfig.WorkspaceContainerName)
	local pitchFolder = getOrCreateFolder(rootFolder, "Pitch")

	createSurface(pitchFolder)
	createMarkings(pitchFolder)
	createGoals(pitchFolder)
	local spawnLocation = createSpawn(rootFolder)

	return {
		RootFolder = rootFolder,
		PitchFolder = pitchFolder,
		SpawnLocation = spawnLocation,
	}
end

return PitchService
