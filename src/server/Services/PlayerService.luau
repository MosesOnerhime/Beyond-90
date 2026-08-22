local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
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

local function normalizeCharacterPhysics(character: Model)
	local unanchoredCount = 0
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

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

	if unanchoredCount > 0 then
		warnLog(string.format(
			"Unanchored %d StarterCharacter part(s) for Humanoid movement compatibility",
			unanchoredCount
		))
	end
end

local function getPitchGroundY(spawnLocation: SpawnLocation): number
	return spawnLocation.Position.Y - spawnLocation.Size.Y / 2
end

local function getPartBottomY(character: Model, partName: string): number?
	local part = character:FindFirstChild(partName)

	if not part or not part:IsA("BasePart") then
		return nil
	end

	return part.Position.Y - part.Size.Y / 2
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
	local groundY = getPitchGroundY(spawnLocation)
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

	if phase ~= "waiting-settle" then
		log(string.format(
			"Grounding phase=%s height=%.2f hipHeight=%.3f rootY=%.3f groundY=%.3f targetClearance=%.3f leftFootBottomY=%.3f rightFootBottomY=%.3f lowestClearance=%.3f clearanceError=%.3f hipAdjustment=%.3f",
			phase,
			character:GetAttribute("Beyond90MeasuredBodyHeightStuds") or -1,
			humanoid.HipHeight,
			if rootPart and rootPart:IsA("BasePart") then rootPart.Position.Y else -1,
			groundY,
			targetClearance,
			leftFootBottomY or -1,
			rightFootBottomY or -1,
			footGroundError or 0,
			clearanceError or 0,
			hipAdjustment
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
	local groundY = getPitchGroundY(spawnLocation)
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

	if canAdjust and math.abs(correction) > tolerance then
		hipAdjustment = math.clamp(correction, -maxCorrection, maxCorrection)
		humanoid.HipHeight = math.max(0, humanoid.HipHeight + hipAdjustment)
		RunService.Heartbeat:Wait()
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

function PlayerService.Initialize(spawnLocation: SpawnLocation)
	if initialized then
		return
	end

	initialized = true

	local remotes = getOrCreateFolder(ReplicatedStorage, "Remotes")
	sprintRemote = getOrCreateRemoteEvent(remotes, inputConfig.SprintRemoteName)
	sprintRemote.OnServerEvent:Connect(onSprintRequested)

	for _, player in Players:GetPlayers() do
		configurePlayer(player, spawnLocation)
	end

	Players.PlayerAdded:Connect(function(player)
		configurePlayer(player, spawnLocation)
	end)

	Players.PlayerRemoving:Connect(cleanupPlayer)
end

return PlayerService
