local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PitchConfig = require(Shared.Config.PitchConfig)

local PitchService = {}
local activePitchState = nil

local function log(message: string)
	print(string.format("%s[Pitch] %s", GameConfig.LogPrefix, message))
end

local function warnLog(message: string)
	warn(string.format("%s[Pitch] %s", GameConfig.LogPrefix, message))
end

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

local function configurePart(part: BasePart, size: Vector3, cframe: CFrame, color: Color3, transparency: number, canCollide: boolean)
	part.Anchored = true
	part.CanCollide = canCollide
	part.CanQuery = true
	part.CanTouch = true
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cframe
	part.Transparency = transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function getHorizontalUnit(vector: Vector3, fallback: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)

	if horizontal.Magnitude <= 0 then
		return fallback
	end

	return horizontal.Unit
end

local function getWorkspacePitchBounds(): BasePart?
	if not PitchConfig.UseWorkspacePitchBounds then
		return nil
	end

	local current: Instance = Workspace

	for _, name in PitchConfig.WorkspacePitchBoundsPath do
		local child = current:FindFirstChild(name)

		if not child then
			return nil
		end

		current = child
	end

	if current:IsA("BasePart") then
		return current
	end

	return nil
end

local function createPitchStateFromConfig()
	local center = Vector3.new(0, 0, 0)
	local lengthAxis = Vector3.new(0, 0, 1)
	local widthAxis = Vector3.new(1, 0, 0)

	return {
		IsUsingWorkspaceBounds = false,
		Center = center,
		CenterCFrame = CFrame.fromMatrix(center, widthAxis, Vector3.yAxis, -lengthAxis),
		LengthAxis = lengthAxis,
		WidthAxis = widthAxis,
		Length = PitchConfig.Length,
		Width = PitchConfig.Width,
		GroundY = 0,
	}
end

local function configurePitchBoundsReference(bounds: BasePart)
	bounds.Anchored = true
	bounds.CanCollide = false
	bounds.CanTouch = false
	bounds.CanQuery = false
	bounds.CastShadow = false
	bounds.Transparency = 1
end

local function createPitchStateFromBounds(bounds: BasePart)
	configurePitchBoundsReference(bounds)

	local rightAxis = getHorizontalUnit(bounds.CFrame.RightVector, Vector3.new(1, 0, 0))
	local lookAxis = getHorizontalUnit(bounds.CFrame.LookVector, Vector3.new(0, 0, 1))
	local lengthAxis = lookAxis
	local widthAxis = rightAxis
	local length = bounds.Size.Z
	local width = bounds.Size.X

	if bounds.Size.X > bounds.Size.Z then
		lengthAxis = rightAxis
		widthAxis = lookAxis
		length = bounds.Size.X
		width = bounds.Size.Z
	end

	local center = bounds.Position
	local groundY = bounds.Position.Y + bounds.Size.Y / 2
	local usesFallbackGroundY = false

	if bounds.Size.Y > PitchConfig.MaxPitchBoundsReferenceThickness then
		groundY = bounds.Position.Y
		usesFallbackGroundY = true
		warnLog(string.format(
			"PitchBounds thickness %.2f exceeds configured reference max %.2f; using PitchBounds center Y %.2f as temporary GroundY. Make PitchBounds a thin slab aligned to the grass.",
			bounds.Size.Y,
			PitchConfig.MaxPitchBoundsReferenceThickness,
			groundY
		))
	end

	return {
		IsUsingWorkspaceBounds = true,
		Center = center,
		CenterCFrame = CFrame.fromMatrix(center, widthAxis, Vector3.yAxis, -lengthAxis),
		LengthAxis = lengthAxis,
		WidthAxis = widthAxis,
		Length = length,
		Width = width,
		GroundY = groundY,
		PitchBoundsThickness = bounds.Size.Y,
		UsesFallbackGroundY = usesFallbackGroundY,
		PitchBounds = bounds,
	}
end

local function getPitchState()
	local bounds = getWorkspacePitchBounds()

	if bounds then
		return createPitchStateFromBounds(bounds)
	end

	return createPitchStateFromConfig()
end

local function getWorldPosition(pitchState, widthOffset: number, lengthOffset: number, yOffset: number): Vector3
	return pitchState.Center
		+ pitchState.WidthAxis * widthOffset
		+ pitchState.LengthAxis * lengthOffset
		+ Vector3.yAxis * (pitchState.GroundY + yOffset - pitchState.Center.Y)
end

local function getGameplayCFrame(pitchState, position: Vector3): CFrame
	return CFrame.fromMatrix(position, pitchState.WidthAxis, Vector3.yAxis, -pitchState.LengthAxis)
end

local function createSurface(pitchFolder: Folder, pitchState)
	local surface = getOrCreatePart(pitchFolder, "PlayingSurface")

	configurePart(
		surface,
		Vector3.new(pitchState.Width, PitchConfig.SurfaceThickness, pitchState.Length),
		getGameplayCFrame(
			pitchState,
			getWorldPosition(pitchState, 0, 0, -PitchConfig.SurfaceThickness / 2)
		),
		Color3.fromRGB(35, 130, 65),
		0,
		true
	)

	return surface
end

local function createGameplayBounds(pitchFolder: Folder, pitchState)
	local bounds = getOrCreatePart(pitchFolder, "GameplayBounds")

	configurePart(
		bounds,
		Vector3.new(pitchState.Width, 0.1, pitchState.Length),
		getGameplayCFrame(pitchState, getWorldPosition(pitchState, 0, 0, 0.05)),
		Color3.fromRGB(80, 180, 255),
		1,
		false
	)

	bounds.CanQuery = false
	bounds.CanTouch = false
	bounds:SetAttribute("Beyond90GameplayBounds", true)
	bounds:SetAttribute("PitchCenter", pitchState.Center)
	bounds:SetAttribute("PitchLengthAxis", pitchState.LengthAxis)
	bounds:SetAttribute("PitchWidthAxis", pitchState.WidthAxis)
	bounds:SetAttribute("PitchLength", pitchState.Length)
	bounds:SetAttribute("PitchWidth", pitchState.Width)
	bounds:SetAttribute("PitchGroundY", pitchState.GroundY)
	bounds:SetAttribute("PitchUsesWorkspaceBounds", pitchState.IsUsingWorkspaceBounds)
	return bounds
end

local function clearGeneratedVisualPitch(pitchFolder: Folder)
	local surface = pitchFolder:FindFirstChild("PlayingSurface")

	if surface then
		surface:Destroy()
	end

	local markings = pitchFolder:FindFirstChild("Markings")

	if markings then
		markings:Destroy()
	end
end

local function createMarkings(pitchFolder: Folder, pitchState)
	local markingsFolder = getOrCreateFolder(pitchFolder, "Markings")
	local lineColor = Color3.fromRGB(235, 235, 235)
	local lineY = PitchConfig.LineHeight / 2 + PitchConfig.LineY
	local lineHeight = PitchConfig.LineHeight
	local lineThickness = PitchConfig.LineThickness
	local halfWidth = pitchState.Width / 2
	local halfLength = pitchState.Length / 2

	local markings = {
		{
			Name = "CenterLine",
			Size = Vector3.new(pitchState.Width, lineHeight, lineThickness),
			Position = getWorldPosition(pitchState, 0, 0, lineY),
		},
		{
			Name = "LeftTouchline",
			Size = Vector3.new(lineThickness, lineHeight, pitchState.Length),
			Position = getWorldPosition(pitchState, -halfWidth, 0, lineY),
		},
		{
			Name = "RightTouchline",
			Size = Vector3.new(lineThickness, lineHeight, pitchState.Length),
			Position = getWorldPosition(pitchState, halfWidth, 0, lineY),
		},
		{
			Name = "NorthGoalLine",
			Size = Vector3.new(pitchState.Width, lineHeight, lineThickness),
			Position = getWorldPosition(pitchState, 0, halfLength, lineY),
		},
		{
			Name = "SouthGoalLine",
			Size = Vector3.new(pitchState.Width, lineHeight, lineThickness),
			Position = getWorldPosition(pitchState, 0, -halfLength, lineY),
		},
	}

	for _, marking in markings do
		local part = getOrCreatePart(markingsFolder, marking.Name)
		configurePart(part, marking.Size, getGameplayCFrame(pitchState, marking.Position), lineColor, 0, false)
	end
end

local function createGoals(pitchFolder: Folder, pitchState)
	local goalsFolder = getOrCreateFolder(pitchFolder, "Goals")
	local goalColor = Color3.fromRGB(245, 215, 80)
	local zoneY = 0.12
	local halfLength = pitchState.Length / 2
	local zoneSize = Vector3.new(PitchConfig.GoalWidth, 0.2, PitchConfig.GoalDepth)

	local northGoal = getOrCreatePart(goalsFolder, "NorthGoalZone")
	configurePart(
		northGoal,
		zoneSize,
		getGameplayCFrame(
			pitchState,
			getWorldPosition(pitchState, 0, halfLength - PitchConfig.GoalDepth / 2, zoneY)
		),
		goalColor,
		if pitchState.IsUsingWorkspaceBounds then 1 else 0.6,
		false
	)
	northGoal:SetAttribute("Beyond90GoalZone", true)
	northGoal:SetAttribute("GoalSide", "North")

	local southGoal = getOrCreatePart(goalsFolder, "SouthGoalZone")
	configurePart(
		southGoal,
		zoneSize,
		getGameplayCFrame(
			pitchState,
			getWorldPosition(pitchState, 0, -halfLength + PitchConfig.GoalDepth / 2, zoneY)
		),
		goalColor,
		if pitchState.IsUsingWorkspaceBounds then 1 else 0.6,
		false
	)
	southGoal:SetAttribute("Beyond90GoalZone", true)
	southGoal:SetAttribute("GoalSide", "South")
end

local function createSpawn(rootFolder: Folder, pitchState)
	local spawnsFolder = getOrCreateFolder(rootFolder, "Spawns")
	local spawn = getOrCreatePart(spawnsFolder, "DevelopmentSpawn", "SpawnLocation") :: SpawnLocation
	local maxSpawnLengthOffset = pitchState.Length * 0.35
	local spawnLengthOffset = math.clamp(
		PitchConfig.DevelopmentSpawnLengthOffset,
		-maxSpawnLengthOffset,
		maxSpawnLengthOffset
	)
	local spawnSize = Vector3.new(8, 1, 8)
	local spawnPosition = getWorldPosition(pitchState, 0, spawnLengthOffset, spawnSize.Y / 2)

	configurePart(
		spawn,
		spawnSize,
		getGameplayCFrame(pitchState, spawnPosition),
		Color3.fromRGB(60, 165, 255),
		1,
		false
	)

	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Enabled = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.AllowTeamChangeOnTouch = false

	return spawn
end

function PitchService.GetState()
	return activePitchState
end

function PitchService.Initialize()
	local rootFolder = getOrCreateFolder(Workspace, GameConfig.WorkspaceContainerName)
	local pitchFolder = getOrCreateFolder(rootFolder, "Pitch")
	local pitchState = getPitchState()

	if pitchState.IsUsingWorkspaceBounds then
		log(string.format(
			"PitchBounds detected: length=%.2f width=%.2f groundY=%.2f thickness=%.2f",
			pitchState.Length,
			pitchState.Width,
			pitchState.GroundY,
			pitchState.PitchBoundsThickness or 0
		))
	end

	if pitchState.IsUsingWorkspaceBounds then
		clearGeneratedVisualPitch(pitchFolder)
	else
		createSurface(pitchFolder, pitchState)
		createMarkings(pitchFolder, pitchState)
	end

	createGameplayBounds(pitchFolder, pitchState)
	createGoals(pitchFolder, pitchState)
	local spawnLocation = createSpawn(rootFolder, pitchState)
	local ballCenterPosition = getWorldPosition(pitchState, 0, 0, 0)

	pitchState.RootFolder = rootFolder
	pitchState.PitchFolder = pitchFolder
	pitchState.SpawnLocation = spawnLocation
	pitchState.BallCenterPosition = ballCenterPosition
	activePitchState = pitchState

	return {
		RootFolder = rootFolder,
		PitchFolder = pitchFolder,
		SpawnLocation = spawnLocation,
		BallCenterPosition = ballCenterPosition,
		PitchState = pitchState,
	}
end

return PitchService
