local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PitchConfig = require(Shared.Config.PitchConfig)
local BallControlService = require(script.Parent.BallControlService)

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

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector(vector: Vector3): boolean
	return isFiniteNumber(vector.X) and isFiniteNumber(vector.Y) and isFiniteNumber(vector.Z)
end

local function getBallSpawnPosition(): Vector3
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
	local padding = BallConfig.Safety.ResetOutOfBoundsPadding
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

local function updateBallInteractions(ball: Part)
	if not validateBallState(ball) then
		return
	end

	local isControlled = BallControlService.Update(ball)

	if isControlled then
		clampBallSpeed(ball)
		return
	end

	for _, player in Players:GetPlayers() do
		local touchContext = getCharacterTouchContext(player, ball)

		if touchContext then
			applyBasicTouch(player, ball, touchContext)
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
		accumulatedTime += deltaTime

		if accumulatedTime < BallConfig.BasicTouch.CheckInterval then
			return
		end

		accumulatedTime = 0

		if activeBall then
			updateBallInteractions(activeBall)
		end
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
	activeBall = ball
	BallControlService.Initialize(ball)
	startInteractionLoop()

	return ball
end

return BallService
