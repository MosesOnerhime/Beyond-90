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

local function configureVisualPart(part: BasePart, ball: BasePart)
	part:SetAttribute("Beyond90BallVisual", true)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = ball

	local weld = Instance.new("WeldConstraint")
	weld:SetAttribute("Beyond90BallVisual", true)
	weld.Part0 = ball
	weld.Part1 = part
	weld.Parent = part
end

local function createVisualBand(ball: BasePart, name: string, size: Vector3, color: Color3, orientation: Vector3)
	local band = Instance.new("Part")
	band.Name = name
	band.Shape = Enum.PartType.Block
	band.Size = size
	band.Color = color
	band.CFrame = ball.CFrame * CFrame.Angles(
		math.rad(orientation.X),
		math.rad(orientation.Y),
		math.rad(orientation.Z)
	)
	configureVisualPart(band, ball)
end

local function createBrandMark(ball: BasePart)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "Beyond90BrandMark"
	surfaceGui:SetAttribute("Beyond90BallVisual", true)
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 140
	surfaceGui.Parent = ball

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

local function configureBallVisuals(ball: BasePart)
	clearBallVisuals(ball)

	local radius = BallConfig.Radius
	local visualConfig = BallConfig.Visual
	local bandThickness = radius * 0.16
	local bandLength = radius * 1.9

	ball.Color = visualConfig.BaseColor
	createVisualBand(
		ball,
		"CharcoalPanelBandA",
		Vector3.new(bandLength, bandThickness, radius * 0.08),
		visualConfig.PanelColor,
		Vector3.new(0, 0, 0)
	)
	createVisualBand(
		ball,
		"CharcoalPanelBandB",
		Vector3.new(bandThickness, bandLength, radius * 0.08),
		visualConfig.PanelColor,
		Vector3.new(0, 0, 35)
	)
	createVisualBand(
		ball,
		"PurpleAccentBand",
		Vector3.new(bandLength * 0.72, bandThickness * 0.75, radius * 0.09),
		visualConfig.AccentColor,
		Vector3.new(0, 0, -35)
	)
	createBrandMark(ball)
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

	if allowFreeTouch then
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
	activeBall = ball
	BallControlService.Initialize(ball)
	startInteractionLoop()

	return ball
end

return BallService
