local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PitchConfig = require(Shared.Config.PitchConfig)
local WorldScaleConfig = require(Shared.Config.WorldScaleConfig)
local CollisionGroupConfig = require(Shared.Config.CollisionGroupConfig)
local FreeBallPhysics = require(Shared.Football.FreeBallPhysics)
local BallControlService = require(script.Parent.BallControlService)
local PitchService = require(script.Parent.PitchService)

local BallService = {}

local activeBall: Part? = nil
local heartbeatConnection: RBXScriptConnection? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local accumulatedTime = 0
local ballSampledEvent = Instance.new("BindableEvent")
local lastTouchByPlayer: { [Player]: number } = {}
local warnedMissingFootballVisual = false
local loggedFootballVisualLoaded = false
local loggedBallScale = false
local sessionActive = false
local previousBallVelocity = Vector3.zero
local lastBounceAt = -math.huge

local function applySessionVisibility(ball: BasePart, active: boolean)
	ball.Anchored = not active
	ball.CanCollide = active
	ball.CanQuery = active
	ball.CanTouch = active
	ball.Transparency = if active then 0 else 1
	for _, descendant in ball:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = if active then 0 else 1
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = if active then 0 else 1
		end
	end
end

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
	--[[
		The football has its own collision group purely so the referee can be
		excluded from it. Ball-against-everything else is unchanged; see
		CollisionGroupConfig. Guarded so a missing group can never stop the ball
		from being created.
	]]
	pcall(function()
		ball.CollisionGroup = CollisionGroupConfig.Ball
	end)
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

local function resetBall(ball: BasePart, keepAnchored: boolean?)
	BallControlService.Reset(ball)
	-- Network ownership cannot be changed while the session-hidden ball is anchored.
	-- Temporarily unanchor it, reset authoritatively, then restore the requested state.
	ball.Anchored = false
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CFrame = CFrame.new(getBallSpawnPosition())
	ball:SetAttribute("FootballFlightComplete", true)
	ball:SetAttribute("FootballGrounded", true)
	ball:SetAttribute("FootballBounceCount", 0)
	ball:SetAttribute("LastFootballBounceImpactSpeed", 0)
	ball:SetAttribute("LastFootballBounceReboundSpeed", 0)
	previousBallVelocity = Vector3.zero
	lastBounceAt = -math.huge
	ball:SetNetworkOwner(nil)
	ball.Anchored = keepAnchored == true
	ballSampledEvent:Fire(ball, ball.Position, true)
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

local function applyFootballFlightGravity(ball: BasePart, deltaTime: number)
	local flightConfig = BallConfig.Flight
	if not flightConfig or flightConfig.Enabled ~= true then
		return
	end
	if ball:GetAttribute("FootballFlightComplete") == true then
		return
	end

	local actionName = ball:GetAttribute("LastFootballAction")
	if typeof(actionName) ~= "string" or flightConfig.Actions[actionName] ~= true then
		return
	end
	local actionTime = ball:GetAttribute("LastFootballActionTime")
	if typeof(actionTime) ~= "number" or os.clock() - actionTime > flightConfig.MaximumActionDuration then
		return
	end

	local pitchState = PitchService.GetState()
	local groundY = if pitchState then pitchState.GroundY else 0
	local restingCenterY = groundY + BallConfig.Radius
	if ball.Position.Y <= restingCenterY + flightConfig.ActivationHeight
		and ball.AssemblyLinearVelocity.Y <= 0
	then
		return
	end

	--[[
		CURVE (§69). Applied here, in the same step as the custom gravity, because
		it is the same kind of term: a constant acceleration on a ball that is
		already in flight. Reading it from an attribute keeps the decision at
		release and this integration purely mechanical.
	]]
	local curve = ball:GetAttribute(flightConfig.CurveAttributeName)
	if typeof(curve) == "Vector3" and curve.Magnitude > 1e-3 then
		local bounced = ball:GetAttribute("FootballBounceCount")
		if flightConfig.CurveSurvivesBounce ~= true and typeof(bounced) == "number" and bounced > 0 then
			ball:SetAttribute(flightConfig.CurveAttributeName, Vector3.zero)
		else
			local clamped = if curve.Magnitude > flightConfig.MaximumCurveAcceleration
				then curve.Unit * flightConfig.MaximumCurveAcceleration
				else curve
			ball.AssemblyLinearVelocity += clamped * deltaTime
		end
	end

	local bounceCount = ball:GetAttribute("FootballBounceCount")
	local effectiveGravity = flightConfig.EffectiveGravity
	if typeof(bounceCount) == "number" and bounceCount > 0 then
		effectiveGravity = BallConfig.Bounce.AirborneGravity
	end
	local gravityCompensation = Workspace.Gravity - effectiveGravity
	if gravityCompensation > 0 then
		ball.AssemblyLinearVelocity += Vector3.yAxis * gravityCompensation * math.max(deltaTime, 0)
	end
end

local function probeGround(ball: BasePart, maximumSeparation: number)
	local bounceConfig = BallConfig.Bounce
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { ball }
	raycastParams.RespectCanCollide = true
	local probeDistance = BallConfig.Radius + maximumSeparation + 0.02
	local surface = Workspace:Raycast(ball.Position, -Vector3.yAxis * probeDistance, raycastParams)
	if not surface or surface.Normal:Dot(Vector3.yAxis) < bounceConfig.SurfaceNormalMinUpDot then
		return nil
	end

	local separation = (ball.Position - surface.Position):Dot(surface.Normal) - BallConfig.Radius
	if separation > maximumSeparation then
		return nil
	end

	return {
		Result = surface,
		Normal = surface.Normal,
		Separation = separation,
	}
end

local function getGroundContact(ball: BasePart)
	return probeGround(ball, BallConfig.Bounce.ContactTolerance)
end

local function applyFootballBounce(ball: BasePart, previousVelocity: Vector3, contact)
	local bounceConfig = BallConfig.Bounce
	if not bounceConfig or bounceConfig.Enabled ~= true then
		return false
	end
	local now = os.clock()
	local impactSpeed = -previousVelocity:Dot(contact.Normal)
	if now - lastBounceAt < bounceConfig.Cooldown or impactSpeed < bounceConfig.MinimumImpactSpeed then
		return false
	end

	local response = FreeBallPhysics.ComputeBounce(
		previousVelocity,
		ball.AssemblyAngularVelocity,
		contact.Normal,
		BallConfig.Radius,
		bounceConfig
	)
	if contact.Separation < 0 then
		ball.CFrame += contact.Normal * (-contact.Separation + 0.01)
	end
	ball.AssemblyLinearVelocity = response.Velocity
	ball.AssemblyAngularVelocity = response.AngularVelocity
	ball:SetAttribute("FootballFlightComplete", response.ReboundSpeed == 0)
	ball:SetAttribute("FootballGrounded", response.ReboundSpeed == 0)
	ball:SetAttribute("LastFootballBounceImpactSpeed", response.ImpactSpeed)
	ball:SetAttribute("LastFootballBounceReboundSpeed", response.ReboundSpeed)
	ball:SetAttribute("FootballBounceCount", (ball:GetAttribute("FootballBounceCount") or 0) + 1)
	lastBounceAt = now

	if bounceConfig.DiagnosticEnabled == true then
		print(string.format(
			"%s[Ball] [Bounce] count=%d impact=%.2fm/s rebound=%.2fm/s tangent=%.2f->%.2fm/s impactFriction=%.2f",
			GameConfig.LogPrefix,
			ball:GetAttribute("FootballBounceCount"),
			WorldScaleConfig.StudsToMeters(response.ImpactSpeed),
			WorldScaleConfig.StudsToMeters(response.ReboundSpeed),
			WorldScaleConfig.StudsToMeters(response.IncomingTangentSpeed),
			WorldScaleConfig.StudsToMeters(response.OutgoingTangentSpeed),
			response.ImpactFactor
		))
	end

	return true
end

local function applyFootballGroundResponse(ball: BasePart, contact, deltaTime: number)
	local groundConfig = BallConfig.Ground
	if not groundConfig or groundConfig.Enabled ~= true then
		return
	end
	if ball.AssemblyLinearVelocity:Dot(contact.Normal) > groundConfig.MaximumUpwardContactSpeed then
		ball:SetAttribute("FootballGrounded", false)
		return
	end

	local grassDepth = math.max(groundConfig.GrassDepth, 1e-5)
	local grassInfluence = math.clamp(1 - math.max(0, contact.Separation) / grassDepth, 0, 1) ^ 0.7
	if grassInfluence <= 0 then
		ball:SetAttribute("FootballGrounded", false)
		return
	end
	local response = FreeBallPhysics.StepGround(
		ball.AssemblyLinearVelocity,
		ball.AssemblyAngularVelocity,
		contact.Normal,
		BallConfig.Radius,
		grassInfluence,
		deltaTime,
		WorldScaleConfig.MetersPerStud,
		groundConfig
	)
	ball.AssemblyLinearVelocity = response.Velocity
	ball.AssemblyAngularVelocity = response.AngularVelocity
	ball:SetAttribute("FootballGrounded", true)
	if response.Stopped then
		ball:SetAttribute("FootballFlightComplete", true)
	end
end

local function updateBallInteractions(ball: Part, deltaTime: number, allowFreeTouch: boolean, priorVelocity: Vector3)
	if not validateBallState(ball) then
		return
	end

	local isControlled = BallControlService.Update(ball, deltaTime)

	if isControlled then
		clampBallSpeed(ball)
		return
	end

	local groundContact = getGroundContact(ball)
	local bounced = false
	local alreadyGrounded = ball:GetAttribute("FootballGrounded") == true
	if groundContact and not alreadyGrounded then
		bounced = applyFootballBounce(ball, priorVelocity, groundContact)
	end
	if groundContact and not bounced then
		applyFootballGroundResponse(ball, groundContact, deltaTime)
	elseif not groundContact then
		local groundConfig = BallConfig.Ground
		local wasGrounded = ball:GetAttribute("FootballGrounded") == true
		local leftGround = not wasGrounded
			or ball.AssemblyLinearVelocity.Y > groundConfig.GroundedReleaseUpwardSpeed
			or probeGround(ball, groundConfig.GroundedReleaseDistance) == nil
		if leftGround then
			ball:SetAttribute("FootballGrounded", false)
		end
	end
	applyFootballFlightGravity(ball, deltaTime)

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
		if not activeBall or not sessionActive then
			return
		end

		-- Goal-line observers must see the physical sample before bounds validation can reset it.
		ballSampledEvent:Fire(activeBall, activeBall.Position, false)
		accumulatedTime += deltaTime
		local allowFreeTouch = accumulatedTime >= BallConfig.BasicTouch.CheckInterval

		if allowFreeTouch then
			accumulatedTime = 0
		end

		updateBallInteractions(activeBall, deltaTime, allowFreeTouch, previousBallVelocity)
		previousBallVelocity = activeBall.AssemblyLinearVelocity
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
	previousBallVelocity = ball.AssemblyLinearVelocity
	BallControlService.Initialize(ball)
	applySessionVisibility(ball, false)
	startInteractionLoop()

	return ball
end

function BallService.SetSessionActive(active: boolean)
	sessionActive = active
	if not activeBall then
		return
	end
	if active then
		applySessionVisibility(activeBall, true)
		BallControlService.Reset(activeBall)
		resetBall(activeBall, false)
	else
		BallControlService.Reset(activeBall)
		resetBall(activeBall, true)
		applySessionVisibility(activeBall, false)
	end
end

function BallService.IsSessionActive(): boolean
	return sessionActive
end

function BallService.Reset()
	if activeBall then
		BallControlService.Reset(activeBall)
		resetBall(activeBall)
	end
end

function BallService.GetBallSampledEvent(): BindableEvent
	return ballSampledEvent
end

return BallService
