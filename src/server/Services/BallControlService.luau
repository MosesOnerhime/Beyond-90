local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)
local BallControlMath = require(Shared.Football.BallControlMath)

local BallControlService = {}

local CONTROL_STATE_FREE = "Free"
local CONTROL_STATE_CONTROLLED = "Controlled"

local controlConfig = BallConfig.Control
local ownershipConfig = BallConfig.Ownership
local activeController: Player? = nil
local lastControlDirectionByPlayer: { [Player]: Vector3 } = {}
local lastLogicalTouchByPlayer: { [Player]: number } = {}
local logicalTouchCountByPlayer: { [Player]: number } = {}
local lastLeadDiagnosticByPlayer: { [Player]: number } = {}
local lastOwnershipValidationAt = 0
local distanceViolationStartedAt: number? = nil
local lastAcceptedBallState: { Position: Vector3, Velocity: Vector3, Timestamp: number }? = nil
local controllerNoCollisionConstraints: { NoCollisionConstraint } = {}
local controllerCharacterConnection: RBXScriptConnection? = nil

local function log(message: string)
	print(string.format("%s[Ball] %s", GameConfig.LogPrefix, message))
end

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector(vector: Vector3): boolean
	return isFiniteNumber(vector.X) and isFiniteNumber(vector.Y) and isFiniteNumber(vector.Z)
end

local function isPlayerOwnedMode(): boolean
	return ownershipConfig.ControlledBallOwnershipMode == "Player"
end

local function setServerNetworkOwner(ball: BasePart)
	local ok, err = pcall(function()
		ball:SetNetworkOwner(nil)
	end)

	if not ok then
		warn(string.format("%s[Ball] Failed to assign ball network owner to server: %s", GameConfig.LogPrefix, tostring(err)))
		return
	end

	ball:SetAttribute("NetworkOwnerUserId", 0)
	log("Ball network owner -> server")
end

local function warnIfAssemblyBlocksOwnership(ball: BasePart)
	if ball.Anchored then
		warn(string.format("%s[Ball] Football collider is anchored; network ownership cannot be assigned", GameConfig.LogPrefix))
	end

	for _, descendant in ball:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Anchored then
			warn(string.format(
				"%s[Ball] Football visual descendant is anchored and may block ownership: %s",
				GameConfig.LogPrefix,
				descendant:GetFullName()
			))
		end
	end
end

local function setPlayerNetworkOwner(ball: BasePart, player: Player)
	warnIfAssemblyBlocksOwnership(ball)

	local canSet, reason = ball:CanSetNetworkOwnership()

	if not canSet then
		warn(string.format(
			"%s[Ball] Ball network owner could not be assigned to %s: %s",
			GameConfig.LogPrefix,
			player.Name,
			tostring(reason)
		))
		setServerNetworkOwner(ball)
		return
	end

	local ok, err = pcall(function()
		ball:SetNetworkOwner(player)
	end)

	if not ok then
		warn(string.format(
			"%s[Ball] Failed to assign ball network owner to %s: %s",
			GameConfig.LogPrefix,
			player.Name,
			tostring(err)
		))
		setServerNetworkOwner(ball)
		return
	end

	ball:SetAttribute("NetworkOwnerUserId", player.UserId)
	log(string.format("Ball network owner -> %s", player.Name))
end

local function setBallState(ball: BasePart, state: string, controller: Player?)
	ball:SetAttribute("State", state)
	ball:SetAttribute("ControllerUserId", if controller then controller.UserId else 0)
end

local function clearLegacyDiagnostics(ball: BasePart)
	ball:SetAttribute("Recoverable", nil)
	ball:SetAttribute("EstimatedTimeToBall", nil)
	ball:SetAttribute("LastRecoverabilityFailure", nil)
end

local function clearControllerNoCollision()
	if controllerCharacterConnection then
		controllerCharacterConnection:Disconnect()
		controllerCharacterConnection = nil
	end

	for _, constraint in controllerNoCollisionConstraints do
		constraint:Destroy()
	end

	table.clear(controllerNoCollisionConstraints)
end

local function addNoCollisionConstraint(ball: BasePart, part: BasePart)
	if part == ball then
		return
	end

	local constraint = Instance.new("NoCollisionConstraint")
	constraint.Name = "Beyond90ControllerNoCollision"
	constraint.Part0 = ball
	constraint.Part1 = part
	constraint.Parent = ball
	table.insert(controllerNoCollisionConstraints, constraint)
end

local function setControllerNoCollision(ball: BasePart, character: Model)
	clearControllerNoCollision()

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			addNoCollisionConstraint(ball, descendant)
		end
	end

	controllerCharacterConnection = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and activeController and ball.Parent then
			addNoCollisionConstraint(ball, descendant)
		end
	end)
end

local function getCharacterParts(player: Player)
	local character = player.Character

	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return character, rootPart, humanoid
end

local function getHardControllerInvalidReason(player: Player?): string?
	if not player or player.Parent ~= Players then
		return "player missing"
	end

	local character = player.Character

	if not character then
		return "character missing"
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not rootPart or not rootPart:IsA("BasePart") then
		return "HumanoidRootPart missing"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return "Humanoid missing"
	end

	if humanoid.Health <= 0 then
		return "Humanoid dead"
	end

	return nil
end

local function isBallWithinHeight(ball: BasePart, heightTolerance: number): boolean
	return ball.Position.Y <= BallConfig.Radius + heightTolerance
end

local function hasClearContactPath(character: Model, ball: BasePart, rootPart: BasePart): boolean
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character, ball }

	local result = Workspace:Raycast(rootPart.Position, ball.Position - rootPart.Position, raycastParams)

	return result == nil or not result.Instance.CanCollide
end

local function getFacingDirection(rootPart: BasePart): Vector3
	return BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
		Vector3.new(0, 0, -1)
	)
end

local function getPlayerMovementDirection(player: Player, rootPart: BasePart, humanoid: Humanoid): (Vector3, number)
	local fallback = lastControlDirectionByPlayer[player] or getFacingDirection(rootPart)
	local moveDirection = BallControlMath.GetHorizontal(humanoid.MoveDirection)

	if moveDirection.Magnitude >= controlConfig.StationaryPlayerSpeed / math.max(humanoid.WalkSpeed, 1) then
		return moveDirection.Unit, BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity).Magnitude
	end

	local direction, speed = BallControlMath.GetControlDirection(rootPart.AssemblyLinearVelocity, fallback)

	return direction or fallback, speed
end

local function isSprinting(humanoid: Humanoid): boolean
	return humanoid:GetAttribute("SprintRequested") == true
end

local function updateControlDirection(player: Player, rootPart: BasePart, movementDirection: Vector3, playerSpeed: number): Vector3
	local lastDirection = lastControlDirectionByPlayer[player]
	local desiredDirection = if playerSpeed >= controlConfig.StationaryPlayerSpeed
		then movementDirection
		else getFacingDirection(rootPart)

	if not lastDirection then
		lastControlDirectionByPlayer[player] = desiredDirection
		return desiredDirection
	end

	local smoothing = controlConfig.DirectionSmoothing

	if lastDirection:Dot(desiredDirection) < controlConfig.SharpTurnDirectionDot then
		smoothing = 1
	end

	local smoothed = lastDirection:Lerp(desiredDirection, smoothing)
	local direction = BallControlMath.SafeUnit(smoothed, desiredDirection)
	lastControlDirectionByPlayer[player] = direction

	return direction
end

local function getControlContext(
	player: Player,
	ball: BasePart,
	distanceLimit: number,
	maxBallSpeed: number,
	heightTolerance: number,
	requireAcquireMovement: boolean,
	requireClearContactPath: boolean
)
	local character, rootPart, humanoid = getCharacterParts(player)

	if not character or not rootPart or not humanoid then
		return nil
	end

	if not isBallWithinHeight(ball, heightTolerance) then
		return nil
	end

	if ball.AssemblyLinearVelocity.Magnitude > maxBallSpeed then
		return nil
	end

	local horizontalToBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
	local distance = horizontalToBall.Magnitude

	if distance <= 0 or distance > distanceLimit then
		return nil
	end

	local movementDirection, playerSpeed = getPlayerMovementDirection(player, rootPart, humanoid)

	if requireAcquireMovement and playerSpeed < controlConfig.AcquireMinPlayerSpeed then
		return nil
	end

	local directionToBall = horizontalToBall.Unit
	local towardBallDot = movementDirection:Dot(directionToBall)

	if requireAcquireMovement and towardBallDot < controlConfig.AcquireMinTowardBallDot then
		return nil
	end

	if requireClearContactPath and not hasClearContactPath(character, ball, rootPart) then
		return nil
	end

	local score = towardBallDot * 2 - distance / controlConfig.AcquireDistance

	if player == activeController then
		score += controlConfig.ExistingControllerScoreBonus
	end

	return {
		Player = player,
		Character = character,
		RootPart = rootPart,
		Humanoid = humanoid,
		MovementDirection = movementDirection,
		PlayerSpeed = playerSpeed,
		DirectionToBall = directionToBall,
		Distance = distance,
		TowardBallDot = towardBallDot,
		Score = score,
	}
end

local function getCandidateContext(player: Player, ball: BasePart)
	return getControlContext(
		player,
		ball,
		controlConfig.AcquireDistance,
		controlConfig.MaximumControllableBallSpeed,
		controlConfig.ControlHeightTolerance,
		true,
		true
	)
end

local function getActiveControllerContext(player: Player, ball: BasePart)
	local distanceLimit = if isPlayerOwnedMode()
		then ownershipConfig.MaxControlledDistance
		else controlConfig.HardControlDistance

	return getControlContext(
		player,
		ball,
		distanceLimit,
		controlConfig.ControlRetentionMaxSpeed,
		controlConfig.ControlRetentionHeightTolerance,
		false,
		false
	)
end

local function chooseBestCandidate(ball: BasePart)
	local bestCandidate = nil

	for _, player in Players:GetPlayers() do
		local candidate = getCandidateContext(player, ball)

		if candidate and (not bestCandidate or candidate.Score > bestCandidate.Score) then
			bestCandidate = candidate
		end
	end

	return bestCandidate
end

local function releaseControl(ball: BasePart, reason: string)
	if not activeController then
		setServerNetworkOwner(ball)
		setBallState(ball, CONTROL_STATE_FREE, nil)
		ball:SetAttribute("LastReleaseReason", reason)
		clearControllerNoCollision()
		lastAcceptedBallState = nil
		distanceViolationStartedAt = nil
		return
	end

	local previousController = activeController :: Player
	log(string.format("Control released: %s", reason))
	setServerNetworkOwner(ball)

	activeController = nil
	lastLogicalTouchByPlayer[previousController] = nil
	logicalTouchCountByPlayer[previousController] = nil
	lastControlDirectionByPlayer[previousController] = nil
	lastLeadDiagnosticByPlayer[previousController] = nil
	lastAcceptedBallState = nil
	lastOwnershipValidationAt = 0
	distanceViolationStartedAt = nil
	clearControllerNoCollision()
	setBallState(ball, CONTROL_STATE_FREE, nil)
	ball:SetAttribute("LastReleaseReason", reason)
end

local function acquireControl(ball: BasePart, player: Player)
	if activeController == player then
		return
	end

	local previousController = activeController
	local character = player.Character

	if previousController then
		lastLogicalTouchByPlayer[previousController] = nil
		logicalTouchCountByPlayer[previousController] = nil
		lastControlDirectionByPlayer[previousController] = nil
		lastLeadDiagnosticByPlayer[previousController] = nil
	end

	activeController = player
	lastLogicalTouchByPlayer[player] = nil
	logicalTouchCountByPlayer[player] = 0
	lastLeadDiagnosticByPlayer[player] = nil
	setBallState(ball, CONTROL_STATE_CONTROLLED, player)
	clearLegacyDiagnostics(ball)
	ball:SetAttribute("LastReleaseReason", "")
	ball:SetAttribute("LastControlTouchTime", -1)
	ball:SetAttribute("LastControlTouchCount", 0)
	ball:SetAttribute("LastLocalControlTouchTime", -1)
	ball:SetAttribute("LastLocalControlTouchCount", 0)
	ball:SetAttribute("ServerBallLead", 0)
	ball:SetAttribute("ClientBallLead", 0)
	ball:SetAttribute("NetworkOwnerUserId", 0)
	ball:SetAttribute("ControlMode", "")
	ball:SetAttribute("SmoothedPlayerSpeed", 0)
	ball:SetAttribute("BallRelativeSpeed", 0)
	ball:SetAttribute("RawMoveMagnitude", 0)
	ball:SetAttribute("TurnAngle", 0)
	ball:SetAttribute("DribblePhase", "")
	ball:SetAttribute("BallIntentAngleError", 0)
	ball:SetAttribute("TurnCaptureActive", false)
	ball:SetAttribute("LastLocalDribbleFootSide", "")
	ball:SetAttribute("LastLocalDribbleTouchStrength", "")

	if character then
		setControllerNoCollision(ball, character)
	end

	lastAcceptedBallState = {
		Position = ball.Position,
		Velocity = ball.AssemblyLinearVelocity,
		Timestamp = os.clock(),
	}
	lastOwnershipValidationAt = 0
	distanceViolationStartedAt = nil

	log(string.format("Control acquired by %s", player.Name))

	if isPlayerOwnedMode() then
		setPlayerNetworkOwner(ball, player)
	else
		setServerNetworkOwner(ball)
	end
end

local function applyVelocityDelta(ball: BasePart, deltaVelocity: Vector3): boolean
	if not isFiniteVector(deltaVelocity) or deltaVelocity.Magnitude <= 0 then
		return false
	end

	ball:ApplyImpulse(deltaVelocity * ball.AssemblyMass)
	return true
end

local function getControllerInvalidReason(ball: BasePart): string?
	local hardReason = getHardControllerInvalidReason(activeController)

	if hardReason then
		return hardReason
	end

	local controller = activeController :: Player
	local _character, rootPart = getCharacterParts(controller)

	if not rootPart then
		return "character invalid"
	end

	if not isBallWithinHeight(ball, controlConfig.ControlRetentionHeightTolerance) then
		return "ball too high"
	end

	if ball.AssemblyLinearVelocity.Magnitude > controlConfig.ControlRetentionMaxSpeed then
		return "ball too fast"
	end

	local horizontalDistance = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude

	if horizontalDistance > controlConfig.HardControlDistance then
		return "hard distance exceeded"
	end

	return nil
end

local function getPerpendicular(direction: Vector3): Vector3
	return Vector3.new(-direction.Z, 0, direction.X)
end

local function applyMinimumSeparation(ball: BasePart, rootPart: BasePart, controlDirection: Vector3): boolean
	local horizontalFromPlayer = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
	local distance = horizontalFromPlayer.Magnitude
	local requiredCenterDistance = controlConfig.ControlOriginRadius + BallConfig.Radius + controlConfig.MinimumControlSeparation

	if distance >= requiredCenterDistance then
		return false
	end

	local radialDirection = if distance > 0 then horizontalFromPlayer.Unit else controlDirection
	local correctionDirection = BallControlMath.SafeUnit(radialDirection * 0.95 + controlDirection * 0.05, radialDirection)
	local separationError = requiredCenterDistance - distance
	local deltaSpeed = math.min(
		separationError * controlConfig.SeparationCorrectionStrength,
		controlConfig.MaxSeparationImpulseDeltaSpeed
	)

	return applyVelocityDelta(ball, correctionDirection * deltaSpeed)
end

local function isLogicalContactValid(ball: BasePart, candidate, controlDirection: Vector3): boolean
	local horizontalFromPlayer = BallControlMath.GetHorizontal(ball.Position - candidate.RootPart.Position)
	local distance = horizontalFromPlayer.Magnitude

	if distance > controlConfig.ContactRegionRadius then
		return false
	end

	local forwardDistance = horizontalFromPlayer:Dot(controlDirection)

	if forwardDistance < -controlConfig.ContactBehindTolerance or forwardDistance > controlConfig.ContactAheadDistance then
		return false
	end

	local lateralDistance = (horizontalFromPlayer - controlDirection * forwardDistance).Magnitude

	if lateralDistance > controlConfig.ContactLateralTolerance then
		return false
	end

	if candidate.PlayerSpeed >= controlConfig.StationaryPlayerSpeed
		and candidate.MovementDirection:Dot(controlDirection) < controlConfig.ContactMinimumForwardIntentDot
	then
		return false
	end

	return isBallWithinHeight(ball, controlConfig.ControlHeightTolerance)
end

local function applyPlannedContact(ball: BasePart, candidate, controlDirection: Vector3): boolean
	local now = os.clock()
	local lastLogicalTouch = lastLogicalTouchByPlayer[candidate.Player]

	if lastLogicalTouch and now - lastLogicalTouch < controlConfig.LogicalTouchInterval then
		return false
	end

	if not isLogicalContactValid(ball, candidate, controlDirection) then
		return false
	end

	local sprinting = isSprinting(candidate.Humanoid)
	local plannedContact = BallControlMath.GetPlannedContact(
		candidate.RootPart.Position,
		candidate.RootPart.AssemblyLinearVelocity,
		controlDirection,
		candidate.PlayerSpeed,
		sprinting,
		controlConfig
	)
	local velocityPlan = BallControlMath.GetDesiredContactVelocity(
		ball.Position,
		ball.AssemblyLinearVelocity,
		candidate.RootPart.AssemblyLinearVelocity,
		controlDirection,
		candidate.PlayerSpeed,
		sprinting,
		plannedContact,
		controlConfig
	)
	local horizontalDelta = velocityPlan.DesiredHorizontalVelocity - velocityPlan.CurrentHorizontalVelocity
	local verticalDelta = math.clamp(
		-ball.AssemblyLinearVelocity.Y * 0.35,
		-controlConfig.MaxContactVerticalDeltaSpeed,
		controlConfig.MaxContactVerticalDeltaSpeed
	)

	if not applyVelocityDelta(ball, Vector3.new(horizontalDelta.X, verticalDelta, horizontalDelta.Z)) then
		return false
	end

	lastLogicalTouchByPlayer[candidate.Player] = now
	local count = (logicalTouchCountByPlayer[candidate.Player] or 0) + 1
	logicalTouchCountByPlayer[candidate.Player] = count
	ball:SetAttribute("LastControlTouchTime", now)
	ball:SetAttribute("LastControlTouchCount", count)
	ball:SetAttribute("ControlTargetError", velocityPlan.ToPlannedBall.Magnitude)

	log(string.format(
		"Control touch #%d by %s plannedSpeed=%.2f playerSpeed=%.2f overdrive=%.2f",
		count,
		candidate.Player.Name,
		velocityPlan.DesiredHorizontalVelocity.Magnitude,
		candidate.PlayerSpeed,
		velocityPlan.MaxOverdrive
	))

	return true
end

local function applyStationaryStabilization(ball: BasePart, candidate, controlDirection: Vector3, deltaTime: number)
	local velocityPlan = BallControlMath.GetStationaryControlVelocity(
		candidate.RootPart.Position,
		ball.Position,
		ball.AssemblyLinearVelocity,
		controlDirection,
		controlConfig
	)

	if velocityPlan.TargetError <= controlConfig.StabilizationDeadzone then
		ball:SetAttribute("ControlTargetError", velocityPlan.TargetError)
		return
	end

	local horizontalDelta = velocityPlan.DesiredHorizontalVelocity - velocityPlan.CurrentHorizontalVelocity
	local maxDelta = controlConfig.StationaryMaxDeltaSpeedPerSecond * deltaTime
	horizontalDelta = BallControlMath.ClampMagnitude(horizontalDelta, maxDelta)

	applyVelocityDelta(ball, Vector3.new(horizontalDelta.X, 0, horizontalDelta.Z))
	ball:SetAttribute("ControlTargetError", velocityPlan.TargetError)
end

local function applyMovingLateralStabilization(ball: BasePart, candidate, controlDirection: Vector3, deltaTime: number)
	local horizontalFromPlayer = BallControlMath.GetHorizontal(ball.Position - candidate.RootPart.Position)
	local lateralDirection = getPerpendicular(controlDirection)
	local lateralError = horizontalFromPlayer:Dot(lateralDirection)

	if math.abs(lateralError) <= controlConfig.StabilizationDeadzone then
		ball:SetAttribute("ControlTargetError", math.abs(lateralError))
		return
	end

	local ballLateralSpeed = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity):Dot(lateralDirection)
	local desiredLateralSpeed = -lateralError * controlConfig.MovingLateralStabilizationGain
	local lateralDeltaSpeed = desiredLateralSpeed - ballLateralSpeed
	local maxDelta = controlConfig.MovingLateralMaxDeltaSpeedPerSecond * deltaTime
	lateralDeltaSpeed = math.clamp(lateralDeltaSpeed, -maxDelta, maxDelta)

	applyVelocityDelta(ball, lateralDirection * lateralDeltaSpeed)
	ball:SetAttribute("ControlTargetError", math.abs(lateralError))
end

local function updateLeadDiagnostics(ball: BasePart, candidate, controlDirection: Vector3)
	local now = os.clock()
	local currentLead = BallControlMath.GetHorizontal(ball.Position - candidate.RootPart.Position):Dot(controlDirection)
	ball:SetAttribute("CurrentBallLead", currentLead)
	ball:SetAttribute("ServerBallLead", currentLead)

	local lastLogTime = lastLeadDiagnosticByPlayer[candidate.Player]

	if lastLogTime and now - lastLogTime < controlConfig.LeadDiagnosticInterval then
		return
	end

	lastLeadDiagnosticByPlayer[candidate.Player] = now
	if isPlayerOwnedMode() then
		log(string.format("Lead sample server=%.2f mode=player-owned", currentLead))
	else
		log(string.format(
			"Lead sample server=%.2f serverContacts=%d",
			currentLead,
			logicalTouchCountByPlayer[candidate.Player] or 0
		))
	end
end

local function restoreLastAcceptedBallState(ball: BasePart)
	if not lastAcceptedBallState then
		return
	end

	ball.AssemblyLinearVelocity = lastAcceptedBallState.Velocity
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CFrame = CFrame.new(lastAcceptedBallState.Position)
end

local function getNetworkOwnerMismatchReason(ball: BasePart, expectedPlayer: Player): string?
	local ok, owner = pcall(function()
		return ball:GetNetworkOwner()
	end)

	if not ok then
		return "ownership unreadable"
	end

	if owner ~= expectedPlayer then
		return "ownership mismatch"
	end

	return nil
end

local function validatePlayerOwnedControl(ball: BasePart, candidate): boolean
	local now = os.clock()

	if now - lastOwnershipValidationAt < ownershipConfig.ValidationInterval then
		return true
	end

	lastOwnershipValidationAt = now

	if ball:GetAttribute("State") ~= CONTROL_STATE_CONTROLLED
		or ball:GetAttribute("ControllerUserId") ~= candidate.Player.UserId
	then
		log("Player-owned validation failed: possession mismatch")
		setServerNetworkOwner(ball)
		releaseControl(ball, "validation failed: possession mismatch")
		return false
	end

	local ownershipMismatchReason = getNetworkOwnerMismatchReason(ball, candidate.Player)

	if ownershipMismatchReason then
		log(string.format("Player-owned validation failed: %s", ownershipMismatchReason))
		setPlayerNetworkOwner(ball, candidate.Player)
	end

	local horizontalDistance = BallControlMath.GetHorizontal(ball.Position - candidate.RootPart.Position).Magnitude

	if horizontalDistance > ownershipConfig.MaxControlledDistance then
		log(string.format(
			"Player-owned validation failed: impossible distance distance=%.2f max=%.2f",
			horizontalDistance,
			ownershipConfig.MaxControlledDistance
		))
		restoreLastAcceptedBallState(ball)
		releaseControl(ball, "validation failed: impossible distance")
		return false
	end

	local velocity = ball.AssemblyLinearVelocity
	local speed = velocity.Magnitude

	if speed > ownershipConfig.MaxControlledSpeed then
		log(string.format(
			"Player-owned validation failed: impossible speed speed=%.2f max=%.2f",
			speed,
			ownershipConfig.MaxControlledSpeed
		))
		restoreLastAcceptedBallState(ball)
		releaseControl(ball, "validation failed: impossible speed")
		return false
	end

	if math.abs(velocity.Y) > ownershipConfig.MaxControlledVerticalSpeed then
		log(string.format(
			"Player-owned validation failed: impossible vertical velocity velocityY=%.2f max=%.2f",
			velocity.Y,
			ownershipConfig.MaxControlledVerticalSpeed
		))
		restoreLastAcceptedBallState(ball)
		releaseControl(ball, "validation failed: impossible vertical velocity")
		return false
	end

	if lastAcceptedBallState then
		local elapsed = math.max(now - lastAcceptedBallState.Timestamp, 1 / 240)
		local displacement = (ball.Position - lastAcceptedBallState.Position).Magnitude
		local allowedDisplacement = ownershipConfig.MaxControlledDisplacementPerSecond * elapsed
			+ ownershipConfig.ValidationPositionTolerance

		if displacement > allowedDisplacement then
			log(string.format(
				"Player-owned validation failed: impossible displacement displacement=%.2f allowed=%.2f elapsed=%.2f",
				displacement,
				allowedDisplacement,
				elapsed
			))
			restoreLastAcceptedBallState(ball)
			releaseControl(ball, "validation failed: impossible displacement")
			return false
		end
	end

	lastAcceptedBallState = {
		Position = ball.Position,
		Velocity = ball.AssemblyLinearVelocity,
		Timestamp = now,
	}

	return true
end

local function applyCoupledPossessionControl(ball: BasePart, candidate, deltaTime: number)
	local isStationary = candidate.PlayerSpeed < controlConfig.StationaryPlayerSpeed
	local controlDirection = updateControlDirection(
		candidate.Player,
		candidate.RootPart,
		candidate.MovementDirection,
		candidate.PlayerSpeed
	)

	local touched = false

	if not isStationary then
		touched = applyPlannedContact(ball, candidate, controlDirection)
	end

	if isStationary then
		applyStationaryStabilization(ball, candidate, controlDirection, deltaTime)
	elseif not touched then
		applyMovingLateralStabilization(ball, candidate, controlDirection, deltaTime)
	end

	if not touched then
		applyMinimumSeparation(ball, candidate.RootPart, controlDirection)
	end

	updateLeadDiagnostics(ball, candidate, controlDirection)
end

function BallControlService.Initialize(ball: BasePart)
	activeController = nil
	table.clear(lastLogicalTouchByPlayer)
	table.clear(logicalTouchCountByPlayer)
	table.clear(lastControlDirectionByPlayer)
	table.clear(lastLeadDiagnosticByPlayer)
	lastOwnershipValidationAt = 0
	distanceViolationStartedAt = nil
	lastAcceptedBallState = nil
	clearControllerNoCollision()
	setServerNetworkOwner(ball)
	setBallState(ball, CONTROL_STATE_FREE, nil)
	clearLegacyDiagnostics(ball)
	ball:SetAttribute("LastReleaseReason", "")
	ball:SetAttribute("LastControlTouchTime", -1)
	ball:SetAttribute("LastControlTouchCount", 0)
	ball:SetAttribute("LastLocalControlTouchTime", -1)
	ball:SetAttribute("LastLocalControlTouchCount", 0)
	ball:SetAttribute("ControlTargetError", -1)
	ball:SetAttribute("CurrentBallLead", 0)
	ball:SetAttribute("ServerBallLead", 0)
	ball:SetAttribute("ClientBallLead", 0)
	ball:SetAttribute("NetworkOwnerUserId", 0)
	ball:SetAttribute("ControlMode", "")
	ball:SetAttribute("SmoothedPlayerSpeed", 0)
	ball:SetAttribute("BallRelativeSpeed", 0)
	ball:SetAttribute("RawMoveMagnitude", 0)
	ball:SetAttribute("TurnAngle", 0)
	ball:SetAttribute("DribblePhase", "")
	ball:SetAttribute("BallIntentAngleError", 0)
	ball:SetAttribute("TurnCaptureActive", false)
	ball:SetAttribute("LastLocalDribbleFootSide", "")
	ball:SetAttribute("LastLocalDribbleTouchStrength", "")
end

function BallControlService.Reset(ball: BasePart)
	if activeController then
		releaseControl(ball, "ball reset")
	else
		setServerNetworkOwner(ball)
		setBallState(ball, CONTROL_STATE_FREE, nil)
		ball:SetAttribute("LastReleaseReason", "ball reset")
		clearControllerNoCollision()
	end

	table.clear(lastLogicalTouchByPlayer)
	table.clear(logicalTouchCountByPlayer)
	table.clear(lastControlDirectionByPlayer)
	table.clear(lastLeadDiagnosticByPlayer)
	lastOwnershipValidationAt = 0
	distanceViolationStartedAt = nil
	lastAcceptedBallState = nil
	ball:SetAttribute("LastControlTouchTime", -1)
	ball:SetAttribute("LastControlTouchCount", 0)
	ball:SetAttribute("LastLocalControlTouchTime", -1)
	ball:SetAttribute("LastLocalControlTouchCount", 0)
	ball:SetAttribute("ControlTargetError", -1)
	ball:SetAttribute("CurrentBallLead", 0)
	ball:SetAttribute("ServerBallLead", 0)
	ball:SetAttribute("ClientBallLead", 0)
	ball:SetAttribute("NetworkOwnerUserId", 0)
	ball:SetAttribute("ControlMode", "")
	ball:SetAttribute("SmoothedPlayerSpeed", 0)
	ball:SetAttribute("BallRelativeSpeed", 0)
	ball:SetAttribute("RawMoveMagnitude", 0)
	ball:SetAttribute("TurnAngle", 0)
	ball:SetAttribute("DribblePhase", "")
	ball:SetAttribute("BallIntentAngleError", 0)
	ball:SetAttribute("TurnCaptureActive", false)
	ball:SetAttribute("LastLocalDribbleFootSide", "")
	ball:SetAttribute("LastLocalDribbleTouchStrength", "")
	clearLegacyDiagnostics(ball)
end

function BallControlService.CleanupPlayer(player: Player, ball: BasePart?)
	lastLogicalTouchByPlayer[player] = nil
	logicalTouchCountByPlayer[player] = nil
	lastControlDirectionByPlayer[player] = nil
	lastLeadDiagnosticByPlayer[player] = nil

	if activeController == player then
		if ball then
			releaseControl(ball, "controller left")
		else
			activeController = nil
			clearControllerNoCollision()
		end
	end
end

function BallControlService.Update(ball: BasePart, deltaTime: number?): boolean
	local stepDeltaTime = math.max(deltaTime or BallConfig.BasicTouch.CheckInterval, 1 / 240)

	if activeController then
		local invalidReason = getControllerInvalidReason(ball)

		if invalidReason then
			if isPlayerOwnedMode() and invalidReason == "hard distance exceeded" then
				local now = os.clock()

				if not distanceViolationStartedAt then
					distanceViolationStartedAt = now
				elseif now - distanceViolationStartedAt >= ownershipConfig.DistanceViolationGrace then
					releaseControl(ball, invalidReason)
				end
			else
				releaseControl(ball, invalidReason)
			end
		else
			distanceViolationStartedAt = nil
		end
	end

	local bestCandidate = chooseBestCandidate(ball)

	if bestCandidate then
		if not activeController then
			acquireControl(ball, bestCandidate.Player)
		elseif bestCandidate.Player ~= activeController then
			local currentCandidate = getActiveControllerContext(activeController, ball)
			local currentScore = if currentCandidate then currentCandidate.Score else -math.huge

			if bestCandidate.Score > currentScore + controlConfig.ControlStealScoreMargin then
				acquireControl(ball, bestCandidate.Player)
			end
		end
	end

	if not activeController then
		setBallState(ball, CONTROL_STATE_FREE, nil)
		ball:SetAttribute("ControlTargetError", -1)
		ball:SetAttribute("CurrentBallLead", 0)
		ball:SetAttribute("ServerBallLead", 0)
		ball:SetAttribute("ControlMode", "")
		ball:SetAttribute("SmoothedPlayerSpeed", 0)
		ball:SetAttribute("BallRelativeSpeed", 0)
		ball:SetAttribute("RawMoveMagnitude", 0)
		ball:SetAttribute("TurnAngle", 0)
		ball:SetAttribute("DribblePhase", "")
		ball:SetAttribute("BallIntentAngleError", 0)
		ball:SetAttribute("TurnCaptureActive", false)
		ball:SetAttribute("LastLocalDribbleFootSide", "")
		ball:SetAttribute("LastLocalDribbleTouchStrength", "")
		return false
	end

	local activeCandidate = getActiveControllerContext(activeController, ball)

	if not activeCandidate then
		releaseControl(ball, "movement state invalid")
		return false
	end

	if isPlayerOwnedMode() then
		local controlDirection = updateControlDirection(
			activeCandidate.Player,
			activeCandidate.RootPart,
			activeCandidate.MovementDirection,
			activeCandidate.PlayerSpeed
		)
		updateLeadDiagnostics(ball, activeCandidate, controlDirection)

		if not validatePlayerOwnedControl(ball, activeCandidate) then
			return false
		end
	else
		applyCoupledPossessionControl(ball, activeCandidate, stepDeltaTime)
	end

	setBallState(ball, CONTROL_STATE_CONTROLLED, activeController)

	return true
end

return BallControlService
