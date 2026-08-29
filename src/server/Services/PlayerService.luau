local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local CollisionGroupConfig = require(Shared.Config.CollisionGroupConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local GroundProbe = require(Shared.World.GroundProbe)
local CharacterAppearanceService = require(script.Parent.CharacterAppearanceService)

local PlayerService = {}

local movementConfig = PlayerConfig.Movement
local inputConfig = PlayerConfig.Input

local initialized = false
local sprintRemote: RemoteEvent? = nil
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local sprintStateByPlayer: { [Player]: boolean } = {}
local configuredHumanoids: { [Humanoid]: boolean } = {}
local developmentSpawnCharacterYOffset = 4

local function warnLog(message: string)
	warn(string.format("%s[Server][PlayerService] %s", GameConfig.LogPrefix, message))
end

local function log(message: string)
	print(string.format("%s[Server][PlayerService] %s", GameConfig.LogPrefix, message))
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

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)

	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s exists but is not a RemoteEvent", existing:GetFullName()))
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent

	return remote
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character

	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return nil
	end

	return humanoid
end

local function getConfiguredWalkSpeed(player: Player): number
	if sprintStateByPlayer[player] then
		return movementConfig.SprintSpeed
	end

	return movementConfig.BaseSpeed
end

local function applyMovementSettings(player: Player, humanoid: Humanoid)
	humanoid.WalkSpeed = getConfiguredWalkSpeed(player)
	humanoid.AutoRotate = movementConfig.AutoRotate
	humanoid.UseJumpPower = true
	humanoid.JumpPower = movementConfig.JumpPower
	humanoid.JumpHeight = movementConfig.JumpHeight
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, movementConfig.JumpEnabled)
	humanoid:SetAttribute("Beyond90MovementConfigured", true)
	humanoid:SetAttribute("SprintRequested", sprintStateByPlayer[player] == true)

	if not movementConfig.JumpEnabled then
		humanoid.Jump = false
	end
end

local function placeCharacterAtDevelopmentSpawn(character: Model, spawnLocation: SpawnLocation)
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)

	if not humanoidRootPart then
		warnLog("Character missing HumanoidRootPart; could not place at development spawn")
		return
	end

	character:PivotTo(spawnLocation.CFrame + Vector3.new(0, developmentSpawnCharacterYOffset, 0))
end

--[[
	Register the collision groups once, before any character is built.

	Registering is idempotent in effect but errors if a name already exists, so
	each call is guarded. See CollisionGroupConfig for why these exist at all.
]]
local collisionGroupsReady = false
local function ensureCollisionGroups()
	if collisionGroupsReady then
		return
	end
	collisionGroupsReady = true
	for _, groupName in { CollisionGroupConfig.Footballer, CollisionGroupConfig.Official, CollisionGroupConfig.Ball } do
		if not PhysicsService:IsCollisionGroupRegistered(groupName) then
			local ok, err = pcall(function()
				PhysicsService:RegisterCollisionGroup(groupName)
			end)
			if not ok then
				warn(string.format("%s[PlayerService] Could not register collision group %s: %s",
					GameConfig.LogPrefix, groupName, tostring(err)))
			end
		end
	end
	for _, pair in CollisionGroupConfig.NonCollidingPairs do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], false)
		end)
	end
end

--[[
	Put every part of a footballer into the Footballer group.

	This changes nothing about how footballers collide -- Footballer still
	collides with the world, the ball and other footballers. It exists so the
	referee has something to be excluded from.
]]
local function applyCollisionGroup(character: Model, groupName: string)
	ensureCollisionGroups()
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end
end

function PlayerService.ApplyCollisionGroup(character: Model, groupName: string)
	applyCollisionGroup(character, groupName)
end

--[[
	Register the collision groups. Called at bootstrap before anything assigns
	one, because assigning an unregistered group name throws.
]]
function PlayerService.EnsureCollisionGroups()
	ensureCollisionGroups()
end

local function normalizeCharacterPhysics(character: Model)
	applyCollisionGroup(character, CollisionGroupConfig.Footballer)
	local unanchoredCount = 0
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local collidableParts = {}
	local leftFootCanCollide = false
	local rightFootCanCollide = false

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Anchored then
				descendant.Anchored = false
				unanchoredCount += 1
			end
		end
	end

	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		humanoidRootPart.CanCollide = false
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.CanCollide then
				table.insert(collidableParts, descendant.Name)
			end

			if descendant.Name == "LeftFoot" then
				leftFootCanCollide = descendant.CanCollide
			elseif descendant.Name == "RightFoot" then
				rightFootCanCollide = descendant.CanCollide
			end
		end
	end

	table.sort(collidableParts)
	character:SetAttribute("Beyond90RootCanCollide", humanoidRootPart and humanoidRootPart:IsA("BasePart") and humanoidRootPart.CanCollide or false)
	character:SetAttribute("Beyond90FootPartsCanCollide", leftFootCanCollide or rightFootCanCollide)
	character:SetAttribute("Beyond90CollidableBodyPartCount", #collidableParts)
	character:SetAttribute("Beyond90CollidableBodyParts", table.concat(collidableParts, ","))
	log(string.format(
		"Character collision rootCanCollide=%s feetCanCollide=%s collidableParts=%s",
		tostring(character:GetAttribute("Beyond90RootCanCollide")),
		tostring(character:GetAttribute("Beyond90FootPartsCanCollide")),
		if #collidableParts > 0 then table.concat(collidableParts, ",") else "none"
	))

	if unanchoredCount > 0 then
		warnLog(string.format(
			"Unanchored %d StarterCharacter part(s) for Humanoid movement compatibility",
			unanchoredCount
		))
	end
end

local function getPitchGroundContext(character: Model, spawnLocation: SpawnLocation): (number, string, string, number)
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		local probeDistance = (PlayerConfig.Appearance.Grounding or {}).FloorProbeDistanceStuds or 20
		local result = GroundProbe.Raycast(rootPart.Position, probeDistance, { character })

		if result then
			return result.Position.Y, result.Instance:GetFullName(), result.Material.Name, result.Distance
		end
	end

	local fallbackGroundY = spawnLocation.Position.Y - spawnLocation.Size.Y / 2
	return fallbackGroundY, spawnLocation:GetFullName(), spawnLocation.Material.Name, -1
end

local function getPartBottomY(character: Model, partName: string): number?
	local part = character:FindFirstChild(partName)

	if not part or not part:IsA("BasePart") then
		return nil
	end

	local visualSoleOffset = (PlayerConfig.Appearance.Grounding or {}).VisualSoleOffsetStuds or 0
	return part.Position.Y - part.Size.Y / 2 + visualSoleOffset
end

local function getLowestFootBottomY(character: Model): number?
	local leftFootBottomY = getPartBottomY(character, "LeftFoot")
	local rightFootBottomY = getPartBottomY(character, "RightFoot")

	if leftFootBottomY and rightFootBottomY then
		return math.min(leftFootBottomY, rightFootBottomY)
	end

	return leftFootBottomY or rightFootBottomY
end

local function getGroundingConfig()
	return PlayerConfig.Appearance.Grounding or {}
end

local function updateGroundingAttributes(
	character: Model,
	humanoid: Humanoid,
	spawnLocation: SpawnLocation,
	phase: string,
	hipAdjustment: number
)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local groundY, floorPartName, floorMaterial, floorDistance = getPitchGroundContext(character, spawnLocation)
	local leftFootBottomY = getPartBottomY(character, "LeftFoot")
	local rightFootBottomY = getPartBottomY(character, "RightFoot")
	local lowestFootBottomY = getLowestFootBottomY(character)
	local footGroundError = if lowestFootBottomY then lowestFootBottomY - groundY else nil
	local groundingConfig = getGroundingConfig()
	local targetClearance = groundingConfig.TargetFootClearanceStuds or 0
	local clearanceError = if footGroundError then footGroundError - targetClearance else nil

	character:SetAttribute("Beyond90CharacterHeight", character:GetAttribute("Beyond90MeasuredBodyHeightStuds"))
	character:SetAttribute("Beyond90HipHeight", humanoid.HipHeight)
	character:SetAttribute("Beyond90PitchGroundY", groundY)
	character:SetAttribute("Beyond90RootY", if rootPart and rootPart:IsA("BasePart") then rootPart.Position.Y else -1)
	character:SetAttribute("Beyond90LeftFootBottomY", leftFootBottomY or -1)
	character:SetAttribute("Beyond90RightFootBottomY", rightFootBottomY or -1)
	character:SetAttribute("Beyond90FootGroundError", footGroundError or 0)
	character:SetAttribute("Beyond90HipHeightAdjustment", hipAdjustment)
	character:SetAttribute("Beyond90TargetFootClearance", targetClearance)
	character:SetAttribute("Beyond90FootClearanceError", clearanceError or 0)
	character:SetAttribute("Beyond90FloorPart", floorPartName)
	character:SetAttribute("Beyond90FloorMaterial", floorMaterial)
	character:SetAttribute("Beyond90FloorDistance", floorDistance)
	character:SetAttribute("Beyond90GroundSurfaceValid", string.find(floorPartName, ".Player", 1, true) == nil)

	if phase ~= "waiting-settle" then
		log(string.format(
			"[Ground] player=%s validSurface=%s phase=%s height=%.2f hipHeight=%.3f rootY=%.3f groundY=%.3f targetClearance=%.3f visualSoleOffset=%.3f leftFootBottomY=%.3f rightFootBottomY=%.3f lowestClearance=%.3f clearanceError=%.3f hipAdjustment=%.3f hit=%s material=%s floorDistance=%.3f",
			character.Name,
			tostring(character:GetAttribute("Beyond90GroundSurfaceValid")),
			phase,
			character:GetAttribute("Beyond90MeasuredBodyHeightStuds") or -1,
			humanoid.HipHeight,
			if rootPart and rootPart:IsA("BasePart") then rootPart.Position.Y else -1,
			groundY,
			targetClearance,
			groundingConfig.VisualSoleOffsetStuds or 0,
			leftFootBottomY or -1,
			rightFootBottomY or -1,
			footGroundError or 0,
			clearanceError or 0,
			hipAdjustment,
			floorPartName,
			floorMaterial,
			floorDistance
		))
	end
end

local function isCharacterStillAtSpawnPivot(character: Model, spawnLocation: SpawnLocation): boolean
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local spawnPivotY = spawnLocation.Position.Y + developmentSpawnCharacterYOffset

	return rootPart ~= nil
		and rootPart:IsA("BasePart")
		and math.abs(rootPart.Position.Y - spawnPivotY) <= 0.05
end

local function applyCharacterGroundingCalibration(
	character: Model,
	humanoid: Humanoid,
	spawnLocation: SpawnLocation,
	phase: string,
	canAdjust: boolean,
	maxCorrectionOverride: number?
)
	local groundY = getPitchGroundContext(character, spawnLocation)
	local lowestFootBottomY = getLowestFootBottomY(character)

	if not lowestFootBottomY then
		updateGroundingAttributes(character, humanoid, spawnLocation, "missing-foot", 0)
		return
	end

	local groundingConfig = getGroundingConfig()
	local targetClearance = groundingConfig.TargetFootClearanceStuds or 0
	local desiredLowestFootBottomY = groundY + targetClearance
	local correction = desiredLowestFootBottomY - lowestFootBottomY
	local tolerance = groundingConfig.FootGroundToleranceStuds or 0.04
	local maxCorrection = maxCorrectionOverride or groundingConfig.MaxHipHeightCorrectionStuds or 0.25
	local hipAdjustment = 0

	if canAdjust then
		if groundingConfig.GeometryHipHeightCorrectionEnabled ~= false and math.abs(correction) > tolerance then
			hipAdjustment = math.clamp(correction, -maxCorrection, maxCorrection)
			if groundingConfig.AllowDownwardHipHeightCorrection == false then
				hipAdjustment = math.max(0, hipAdjustment)
			end
		end
		local minimumHipHeight = groundingConfig.MinimumHipHeightStuds or 0
		local nextHipHeight = math.max(minimumHipHeight, humanoid.HipHeight + hipAdjustment)
		hipAdjustment = nextHipHeight - humanoid.HipHeight
		if math.abs(hipAdjustment) > 1e-4 then
			humanoid.HipHeight = nextHipHeight
			RunService.Heartbeat:Wait()
		end
	end

	local resultPhase = phase

	if canAdjust and math.abs(hipAdjustment) <= 0 then
		resultPhase = "accepted"
	end

	updateGroundingAttributes(
		character,
		humanoid,
		spawnLocation,
		resultPhase,
		hipAdjustment
	)
end

local function scheduleGroundingCalibration(
	character: Model,
	humanoid: Humanoid,
	spawnLocation: SpawnLocation,
	delaySeconds: number,
	attempt: number
)
	task.delay(delaySeconds, function()
		if not character.Parent or not humanoid.Parent then
			return
		end

		local groundingConfig = getGroundingConfig()
		local maxSettleRetries = groundingConfig.MaxSettleRetries or 0

		if isCharacterStillAtSpawnPivot(character, spawnLocation) and attempt <= maxSettleRetries then
			updateGroundingAttributes(character, humanoid, spawnLocation, "waiting-settle", 0)
			scheduleGroundingCalibration(
				character,
				humanoid,
				spawnLocation,
				groundingConfig.SettleRetryDelaySeconds or 1,
				attempt + 1
			)
			return
		end

		if character:GetAttribute("Beyond90GroundingCalibrated") then
			return
		end

		character:SetAttribute("Beyond90GroundingCalibrated", true)
		applyCharacterGroundingCalibration(character, humanoid, spawnLocation, "calibrated", true)
	end)
end

local function scheduleGroundingValidation(
	character: Model,
	humanoid: Humanoid,
	spawnLocation: SpawnLocation,
	delaySeconds: number,
	phase: string,
	canAdjust: boolean,
	maxCorrectionOverride: number?
)
	task.delay(delaySeconds, function()
		if character.Parent and humanoid.Parent then
			applyCharacterGroundingCalibration(
				character,
				humanoid,
				spawnLocation,
				phase,
				canAdjust,
				maxCorrectionOverride
			)
		end
	end)
end

local function scheduleSettledGrounding(character: Model, humanoid: Humanoid, spawnLocation: SpawnLocation)
	local groundingConfig = getGroundingConfig()

	scheduleGroundingCalibration(
		character,
		humanoid,
		spawnLocation,
		groundingConfig.CalibrationDelaySeconds or 2,
		0
	)

	scheduleGroundingValidation(
		character,
		humanoid,
		spawnLocation,
		groundingConfig.ValidationDelaySeconds or 5,
		"late-calibrated",
		groundingConfig.ValidationCanAdjust == true,
		groundingConfig.MaxLateHipHeightCorrectionStuds
	)

	scheduleGroundingValidation(
		character,
		humanoid,
		spawnLocation,
		groundingConfig.FinalValidationDelaySeconds or 7,
		"final-validation",
		false,
		nil
	)
end

local function removeBundledAnimateScripts(character: Model)
	local removedCount = 0

	for _, child in character:GetChildren() do
		if child:IsA("LocalScript") and child.Name == "Animate" then
			child:Destroy()
			removedCount += 1
		end
	end

	if removedCount > 0 then
		warnLog(string.format(
			"Removed %d bundled Animate script(s); Beyond90 AnimationController owns character animation",
			removedCount
		))
	end
end

local function configureCharacter(player: Player, character: Model, spawnLocation: SpawnLocation)
	sprintStateByPlayer[player] = false

	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid or not humanoid:IsA("Humanoid") then
		warnLog(string.format("%s spawned without a Humanoid", player.Name))
		return
	end

	removeBundledAnimateScripts(character)
	CharacterAppearanceService.StandardizeCharacter(player, character, humanoid)
	normalizeCharacterPhysics(character)
	placeCharacterAtDevelopmentSpawn(character, spawnLocation)
	applyMovementSettings(player, humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	character:SetAttribute("Beyond90CharacterReady", true)
	scheduleSettledGrounding(character, humanoid, spawnLocation)

	if not configuredHumanoids[humanoid] then
		configuredHumanoids[humanoid] = true

		humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
			if not movementConfig.JumpEnabled and humanoid.Jump then
				humanoid.Jump = false
			end
		end)

		humanoid.Destroying:Connect(function()
			configuredHumanoids[humanoid] = nil
		end)
	end
end

local function setSprintState(player: Player, requested: boolean)
	sprintStateByPlayer[player] = requested

	local humanoid = getHumanoid(player)

	if not humanoid then
		return
	end

	applyMovementSettings(player, humanoid)
end

local function configurePlayer(player: Player, spawnLocation: SpawnLocation)
	player.RespawnLocation = spawnLocation
	sprintStateByPlayer[player] = false

	local connections = playerConnections[player]

	if not connections then
		connections = {}
		playerConnections[player] = connections
	end

	table.insert(connections, player.CharacterAdded:Connect(function(character)
		configureCharacter(player, character, spawnLocation)
	end))

	if player.Character then
		configureCharacter(player, player.Character, spawnLocation)
	end
end

local function cleanupPlayer(player: Player)
	local connections = playerConnections[player]

	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	playerConnections[player] = nil
	sprintStateByPlayer[player] = nil
end

local function onSprintRequested(player: Player, requested: any)
	if typeof(requested) ~= "boolean" then
		warnLog(string.format("Rejected invalid sprint request from %s", player.Name))
		return
	end

	if player.Parent ~= Players then
		return
	end

	setSprintState(player, requested)
end

--[[
	The footballer body, shared by everything that is not a real player.

	AI footballers and the referee must not spawn a different-looking rig from the
	one a human controls, so the Beyond 90 StarterCharacter is the primary
	template and a generic Roblox rig is only ever a last-resort fallback.

	Lives here because PlayerService already owns the footballer body -- physics
	normalization and grounding are immediately below. Returns the clone and the
	name of the source it came from, for diagnostics.
]]
function PlayerService.CloneFootballerTemplate(): (Model?, string)
	local starterCharacter = StarterPlayer:FindFirstChild("StarterCharacter")
	if starterCharacter and starterCharacter:IsA("Model")
		and starterCharacter:FindFirstChildOfClass("Humanoid")
		and starterCharacter:FindFirstChild("HumanoidRootPart")
	then
		return starterCharacter:Clone(), "StarterCharacter"
	end
	for _, player in Players:GetPlayers() do
		if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
			return player.Character:Clone(), "LivePlayerCharacter"
		end
	end
	local description = Instance.new("HumanoidDescription")
	local ok, generated = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if ok and generated then
		return generated, "GeneratedR15"
	end
	return nil, "none"
end

function PlayerService.NormalizeFootballerPhysics(character: Model)
	normalizeCharacterPhysics(character)
end

-- AI footballers spawn outside the Player spawn pipeline, so they need the same
-- HipHeight floor a human character receives. Only the minimum is applied here;
-- the full settle/validate schedule stays a Player-spawn concern.
function PlayerService.ApplyFootballerGrounding(character: Model, humanoid: Humanoid)
	local groundingConfig = getGroundingConfig()
	local minimumHipHeight = groundingConfig.MinimumHipHeightStuds

	if typeof(minimumHipHeight) == "number" and humanoid.HipHeight < minimumHipHeight then
		humanoid.HipHeight = minimumHipHeight
	end

	character:SetAttribute("Beyond90HipHeight", humanoid.HipHeight)
	character:SetAttribute("Beyond90GroundingCalibrated", true)

	local lowestFootBottomY = getLowestFootBottomY(character)
	if lowestFootBottomY then
		character:SetAttribute("Beyond90LowestFootBottomY", lowestFootBottomY)
	end
end

function PlayerService.Initialize(spawnLocation: SpawnLocation)
	if initialized then
		return
	end

	initialized = true
	Players.CharacterAutoLoads = false

	local remotes = getOrCreateFolder(ReplicatedStorage, "Remotes")
	sprintRemote = getOrCreateRemoteEvent(remotes, inputConfig.SprintRemoteName)
	sprintRemote.OnServerEvent:Connect(onSprintRequested)

	--[[
		WHICH BODY THE PLAYER WEARS (§23-§29).

		The choice lives on the SERVER, as a player attribute, because that is
		where the character is built -- a client-set attribute would not replicate
		up, so the spawn would never see it. The client asks; the server decides
		and records.

		Validated against the configured source list rather than trusted, so the
		remote cannot be used to put a footballer into a state the appearance
		service does not know how to build.
	]]
	local identity = PlayerConfig.Appearance.Identity
	if identity and identity.Enabled == true then
		local avatarRemote = getOrCreateRemoteEvent(remotes, identity.RemoteName)
		avatarRemote.OnServerEvent:Connect(function(player, requested)
			if typeof(requested) ~= "string" or not identity.Sources[requested] then
				return
			end
			player:SetAttribute(identity.AttributeName, requested)
			log(string.format("%s avatar source -> %s", player.Name, requested))
		end)
	end

	for _, player in Players:GetPlayers() do
		configurePlayer(player, spawnLocation)
	end

	Players.PlayerAdded:Connect(function(player)
		configurePlayer(player, spawnLocation)
	end)

	Players.PlayerRemoving:Connect(cleanupPlayer)
end

return PlayerService
