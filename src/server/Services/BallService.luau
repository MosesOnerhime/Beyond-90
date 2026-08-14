local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PitchConfig = require(Shared.Config.PitchConfig)
local BallControlService = require(script.Parent.BallControlService)
local PitchService = require(script.Parent.PitchService)

local BallService = {}

local activeBall: Part? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local accumulatedTime = 0
local lastTouchByPlayer: { [Player]: number } = {}
local warnedMissingFootballVisual = false
local loggedFootballVisualLoaded = false
local loggedBallScale = false

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

local function clearBallVisuals(ball: BasePart)
	for _, child in ball:GetChildren() do
		if child:GetAttribute("Beyond90BallVisual") == true then
			child:Destroy()
		end
	end
end

local function configureVisualPart(part: BasePart, preserveAppearance: boolean?)
	part:SetAttribute("Beyond90BallVisual", true)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true

	if not preserveAppearance then
		part.Material = Enum.Material.SmoothPlastic
	end
end

local function weldVisualPart(part: BasePart, rootPart: BasePart, parent: Instance, preserveAppearance: boolean?)
	configureVisualPart(part, preserveAppearance)
	part.Parent = parent

	local weld = Instance.new("WeldConstraint")
	weld:SetAttribute("Beyond90BallVisual", true)
	weld.Part0 = rootPart
	weld.Part1 = part
	weld.Parent = part
end

local function createVisualBand(visualRoot: BasePart, name: string, size: Vector3, color: Color3, orientation: Vector3)
	local band = Instance.new("Part")
	band.Name = name
	band.Shape = Enum.PartType.Block
	band.Size = size
	band.Color = color
	band.CFrame = visualRoot.CFrame * CFrame.Angles(
		math.rad(orientation.X),
		math.rad(orientation.Y),
		math.rad(orientation.Z)
	)
	weldVisualPart(band, visualRoot, visualRoot)
end

local function createBrandMark(visualRoot: BasePart)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "Beyond90BrandMark"
	surfaceGui:SetAttribute("Beyond90BallVisual", true)
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 140
	surfaceGui.Parent = visualRoot

	local label = Instance.new("TextLabel")
	label.Name = "BrandText"
	label:SetAttribute("Beyond90BallVisual", true)
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = BallConfig.Visual.BrandText
	label.TextColor3 = BallConfig.Visual.AccentColor
	label.TextScaled = true
	label.Parent = surfaceGui
end

local function getFootballVisualAsset(): Instance?
	local assetsFolder = ReplicatedStorage:FindFirstChild(BallConfig.Visual.AssetFolderName)

	if not assetsFolder then
		return nil
	end

	return assetsFolder:FindFirstChild(BallConfig.Visual.FootballVisualAssetName)
end

local function scaleVisualPart(part: BasePart, visualDiameter: number)
	local maxDimension = math.max(part.Size.X, part.Size.Y, part.Size.Z)

	if maxDimension <= 0 then
		part.Size = Vector3.new(visualDiameter, visualDiameter, visualDiameter)
		return
	end

	part.Size *= visualDiameter / maxDimension
end

local function configureImportedVisual(ball: BasePart, asset: Instance, visualDiameter: number): boolean
	if asset:IsA("BasePart") then
		local visual = asset:Clone()
		visual.Name = "FootballVisual"
		visual.CFrame = ball.CFrame
		scaleVisualPart(visual, visualDiameter)
		weldVisualPart(visual, ball, ball, true)
		return true
	end

	if asset:IsA("Model") then
		local visualModel = asset:Clone()
		visualModel.Name = "FootballVisual"
		visualModel:SetAttribute("Beyond90BallVisual", true)
		visualModel.Parent = ball

		local okScale = pcall(function()
			local _, boundsSize = visualModel:GetBoundingBox()
			local maxDimension = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z)

			if maxDimension > 0 then
				visualModel:ScaleTo(visualModel:GetScale() * visualDiameter / maxDimension)
			end
		end)

		if not okScale then
			warn(string.format("%s[Ball] FootballVisual model could not be uniformly scaled; check imported asset dimensions", GameConfig.LogPrefix))
		end

		visualModel:PivotTo(ball.CFrame)

		for _, descendant in visualModel:GetDescendants() do
			if descendant:IsA("BasePart") then
				weldVisualPart(descendant, ball, visualModel, true)
			end
		end

		return true
	end

	return false
end

local function createFallbackVisual(ball: BasePart, visualDiameter: number)
	local visualConfig = BallConfig.Visual
	local visualRadius = visualDiameter / 2
	local visual = Instance.new("Part")
	visual.Name = "FootballVisual"
	visual.Shape = Enum.PartType.Ball
	visual.Size = Vector3.new(visualDiameter, visualDiameter, visualDiameter)
	visual.CFrame = ball.CFrame
	visual.Color = visualConfig.BaseColor
	configureVisualPart(visual)
	visual.Parent = ball

	local rootWeld = Instance.new("WeldConstraint")
	rootWeld:SetAttribute("Beyond90BallVisual", true)
	rootWeld.Part0 = ball
	rootWeld.Part1 = visual
	rootWeld.Parent = visual

	local bandThickness = visualRadius * 0.16
	local bandLength = visualRadius * 1.9
	createVisualBand(
		visual,
		"CharcoalPanelBandA",
		Vector3.new(bandLength, bandThickness, visualRadius * 0.08),
		visualConfig.PanelColor,
		Vector3.new(0, 0, 0)
	)
	createVisualBand(
		visual,
		"CharcoalPanelBandB",
		Vector3.new(bandThickness, bandLength, visualRadius * 0.08),
		visualConfig.PanelColor,
		Vector3.new(0, 0, 35)
	)
	createVisualBand(
		visual,
		"PurpleAccentBand",
		Vector3.new(bandLength * 0.72, bandThickness * 0.75, visualRadius * 0.09),
		visualConfig.AccentColor,
		Vector3.new(0, 0, -35)
	)
	createBrandMark(visual)
end

local function configureBallVisuals(ball: BasePart)
	clearBallVisuals(ball)
	ball.Transparency = 1

	local visualDiameter = BallConfig.Visual.VisualDiameter
	local visualAsset = getFootballVisualAsset()

	if visualAsset and configureImportedVisual(ball, visualAsset, visualDiameter) then
		if not loggedFootballVisualLoaded then
			loggedFootballVisualLoaded = true
			print(string.format("%s[Ball] Football visual asset loaded", GameConfig.LogPrefix))
		end

		return
	end

	if not warnedMissingFootballVisual then
		warnedMissingFootballVisual = true
		warn(string.format(
			"%s[Ball] ReplicatedStorage.%s.%s was not found or was not a supported visual asset; using temporary fallback football visual",
			GameConfig.LogPrefix,
			BallConfig.Visual.AssetFolderName,
			BallConfig.Visual.FootballVisualAssetName
		))
	end

	createFallbackVisual(ball, visualDiameter)
end

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector(vector: Vector3): boolean
	return isFiniteNumber(vector.X) and isFiniteNumber(vector.Y) and isFiniteNumber(vector.Z)
end

local function getBallSpawnPosition(): Vector3
	local pitchState = PitchService.GetState()

	if pitchState and pitchState.BallCenterPosition then
		local center = pitchState.BallCenterPosition
		return Vector3.new(center.X, pitchState.GroundY + BallConfig.Radius + 0.1, center.Z)
	end

	return Vector3.new(PitchConfig.BallCenterPosition.X, BallConfig.SpawnHeight, PitchConfig.BallCenterPosition.Z)
end

local function resetBall(ball: BasePart)
	BallControlService.Reset(ball)
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CFrame = CFrame.new(getBallSpawnPosition())
	ball:SetNetworkOwner(nil)
end

local function getHorizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function hasClearContactPath(character: Model, ball: BasePart, rootPart: BasePart): boolean
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character, ball }

	local result = Workspace:Raycast(rootPart.Position, ball.Position - rootPart.Position, raycastParams)

	return result == nil or not result.Instance.CanCollide
end

local function getCharacterTouchContext(player: Player, ball: BasePart)
	local character = player.Character

	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local toBall = ball.Position - rootPart.Position
	local horizontalToBall = getHorizontal(toBall)
	local distance = horizontalToBall.Magnitude
	local verticalDifference = math.abs(toBall.Y)
	local touchConfig = BallConfig.BasicTouch

	if distance > touchConfig.InteractionRadius or verticalDifference > touchConfig.MaxVerticalDifference then
		return nil
	end

	local playerVelocity = getHorizontal(rootPart.AssemblyLinearVelocity)
	local playerSpeed = playerVelocity.Magnitude

	if playerSpeed < touchConfig.MinPlayerSpeed or distance <= 0 then
		return nil
	end

	local movementDirection = playerVelocity.Unit
	local directionToBall = horizontalToBall.Unit
	local towardBallDot = movementDirection:Dot(directionToBall)

	if towardBallDot < touchConfig.MinTowardBallDot then
		return nil
	end

	if not hasClearContactPath(character, ball, rootPart) then
		return nil
	end

	return {
		Humanoid = humanoid,
		MovementDirection = movementDirection,
		PlayerSpeed = playerSpeed,
		TowardBallDot = towardBallDot,
	}
end

local function clampBallSpeed(ball: BasePart)
	local velocity = ball.AssemblyLinearVelocity

	if not isFiniteVector(velocity) then
		resetBall(ball)
		return
	end

	local speed = velocity.Magnitude

	if speed <= BallConfig.MaxSpeed then
		return
	end

	ball.AssemblyLinearVelocity = velocity.Unit * BallConfig.MaxSpeed
end

local function applyBasicTouch(player: Player, ball: BasePart, touchContext)
	local now = os.clock()
	local lastTouch = lastTouchByPlayer[player]
	local touchConfig = BallConfig.BasicTouch

	if lastTouch and now - lastTouch < touchConfig.Cooldown then
		return
	end

	lastTouchByPlayer[player] = now

	local isSprinting = touchContext.Humanoid:GetAttribute("SprintRequested") == true
	local targetSpeed = if isSprinting then touchConfig.SprintTargetSpeed else touchConfig.WalkTargetSpeed
	local ballVelocity = getHorizontal(ball.AssemblyLinearVelocity)
	local currentForwardSpeed = math.max(0, ballVelocity:Dot(touchContext.MovementDirection))
	local impulseDeltaSpeed = math.min(targetSpeed - currentForwardSpeed, touchConfig.MaxImpulseDeltaSpeed)

	if impulseDeltaSpeed <= 0 then
		return
	end

	local horizontalImpulseVelocity = touchContext.MovementDirection * impulseDeltaSpeed
	local impulseVelocity = Vector3.new(horizontalImpulseVelocity.X, touchConfig.UpwardLiftSpeed, horizontalImpulseVelocity.Z)

	if not isFiniteVector(impulseVelocity) then
		return
	end

	ball:ApplyImpulse(impulseVelocity * ball.AssemblyMass)
	clampBallSpeed(ball)
end

local function isOutOfDevelopmentBounds(position: Vector3): boolean
	local pitchState = PitchService.GetState()
	local padding = BallConfig.Safety.ResetOutOfBoundsPadding

	if pitchState then
		local fromCenter = position - pitchState.Center
		local widthDistance = fromCenter:Dot(pitchState.WidthAxis)
		local lengthDistance = fromCenter:Dot(pitchState.LengthAxis)
		local halfWidth = pitchState.Width / 2 + padding
		local halfLength = pitchState.Length / 2 + padding

		return math.abs(widthDistance) > halfWidth or math.abs(lengthDistance) > halfLength
	end

	local halfWidth = PitchConfig.Width / 2 + padding
	local halfLength = PitchConfig.Length / 2 + padding

	return math.abs(position.X) > halfWidth or math.abs(position.Z) > halfLength
end

local function validateBallState(ball: BasePart): boolean
	local position = ball.Position

	if not isFiniteVector(position) or position.Y < BallConfig.Safety.ResetFallY or isOutOfDevelopmentBounds(position) then
		resetBall(ball)
		return false
	end

	if not isFiniteVector(ball.AssemblyLinearVelocity) or not isFiniteVector(ball.AssemblyAngularVelocity) then
		resetBall(ball)
		return false
	end

	clampBallSpeed(ball)
	return true
end

local function updateBallInteractions(ball: Part, deltaTime: number, allowFreeTouch: boolean)
	if not validateBallState(ball) then
		return
	end

	local isControlled = BallControlService.Update(ball, deltaTime)

	if isControlled then
		clampBallSpeed(ball)
		return
	end

	if allowFreeTouch and BallConfig.BasicTouch.Enabled == true then
		for _, player in Players:GetPlayers() do
			local touchContext = getCharacterTouchContext(player, ball)

			if touchContext then
				applyBasicTouch(player, ball, touchContext)
			end
		end
	end
end

local function startInteractionLoop()
	if heartbeatConnection then
		return
	end

	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		lastTouchByPlayer[player] = nil
		BallControlService.CleanupPlayer(player, activeBall)
	end)

	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not activeBall then
			return
		end

		accumulatedTime += deltaTime
		local allowFreeTouch = accumulatedTime >= BallConfig.BasicTouch.CheckInterval

		if allowFreeTouch then
			accumulatedTime = 0
		end

		updateBallInteractions(activeBall, deltaTime, allowFreeTouch)
	end)
end

function BallService.Initialize()
	local rootFolder = getRootFolder()
	local ballFolder = getOrCreateBallFolder(rootFolder)
	local ball = getOrCreateFootball(ballFolder)
	local radius = BallConfig.Radius
	local physics = BallConfig.PhysicalProperties

	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	ball.Position = getBallSpawnPosition()
	ball.Anchored = false
	ball.CanCollide = true
	ball.CanQuery = true
	ball.CanTouch = true
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
	configureBallVisuals(ball)
	if not loggedBallScale then
		loggedBallScale = true
		print(string.format(
			"%s[Ball] Scale diameter=%.2f physics=%.2f visual=%.2f radius=%.3f restingCenterY=%.3f",
			GameConfig.LogPrefix,
			BallConfig.BallDiameter or radius * 2,
			BallConfig.PhysicsDiameter or radius * 2,
			BallConfig.Visual.VisualDiameter,
			radius,
			ball.Position.Y
		))
	end
	activeBall = ball
	BallControlService.Initialize(ball)
	startInteractionLoop()

	return ball
end

return BallService
