local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local GameConfig = require(Shared.Config.GameConfig)

local BallControlService = {}

local CONTROL_STATE_FREE = "Free"
local CONTROL_STATE_CONTROLLED = "Controlled"

local controlConfig = BallConfig.Control
local activeController: Player? = nil
local lastDribbleByPlayer: { [Player]: number } = {}
local lastControlDirectionByPlayer: { [Player]: Vector3 } = {}
local softInvalidStartedAt: number? = nil
local softInvalidReason: string? = nil

local function log(message: string)
	print(string.format("%s[Ball] %s", GameConfig.LogPrefix, message))
end

local function getHorizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector(vector: Vector3): boolean
	return isFiniteNumber(vector.X) and isFiniteNumber(vector.Y) and isFiniteNumber(vector.Z)
end

local function setBallState(ball: BasePart, state: string, controller: Player?)
	ball:SetAttribute("State", state)
	ball:SetAttribute("ControllerUserId", if controller then controller.UserId else 0)
end

local function clearSoftInvalid()
	softInvalidStartedAt = nil
	softInvalidReason = nil
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

local function getBallHeightLimit(heightTolerance: number): number
	return BallConfig.Radius + heightTolerance
end

local function isBallWithinHeight(ball: BasePart, heightTolerance: number): boolean
	return ball.Position.Y <= getBallHeightLimit(heightTolerance)
end

local function getPlayerMovementDirection(player: Player, rootPart: BasePart): (Vector3?, number)
	local velocity = getHorizontal(rootPart.AssemblyLinearVelocity)
	local speed = velocity.Magnitude

	if speed >= controlConfig.StationaryPlayerSpeed then
		return velocity.Unit, speed
	end

	local lastDirection = lastControlDirectionByPlayer[player]

	if lastDirection then
		return lastDirection, speed
	end

	return nil, speed
end

local function hasClearContactPath(character: Model, ball: BasePart, rootPart: BasePart): boolean
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character, ball }

	local result = Workspace:Raycast(rootPart.Position, ball.Position - rootPart.Position, raycastParams)

	return result == nil or not result.Instance.CanCollide
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

	local horizontalToBall = getHorizontal(ball.Position - rootPart.Position)
	local distance = horizontalToBall.Magnitude

	if distance <= 0 or distance > distanceLimit then
		return nil
	end

	local movementDirection, playerSpeed = getPlayerMovementDirection(player, rootPart)

	if not movementDirection then
		movementDirection = horizontalToBall.Unit
	end

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
	return getControlContext(
		player,
		ball,
		controlConfig.ReleaseDistance,
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

local function getControllerInvalidReason(ball: BasePart): (string?, boolean)
	local hardReason = getHardControllerInvalidReason(activeController)

	if hardReason then
		return hardReason, true
	end

	local controller = activeController :: Player
	local character, rootPart = getCharacterParts(controller)

	if not character or not rootPart then
		return "character invalid", true
	end

	if not isBallWithinHeight(ball, controlConfig.ControlRetentionHeightTolerance) then
		return "ball too high", false
	end

	if ball.AssemblyLinearVelocity.Magnitude > controlConfig.ControlRetentionMaxSpeed then
		return "ball too fast", false
	end

	local horizontalToBall = getHorizontal(ball.Position - rootPart.Position)
	local distance = horizontalToBall.Magnitude

	if distance > controlConfig.ReleaseDistance then
		return "distance exceeded", false
	end

	if distance > 0 then
		local movementDirection = getPlayerMovementDirection(controller, rootPart)

		if movementDirection then
			local directionToBall = horizontalToBall.Unit

			if movementDirection:Dot(directionToBall) < controlConfig.ControlReleaseBehindThreshold then
				return "ball behind player", false
			end
		end
	end

	if not hasClearContactPath(character, ball, rootPart) then
		return "contact path blocked", false
	end

	return nil, false
end

local function releaseControl(ball: BasePart, reason: string)
	if not activeController then
		setBallState(ball, CONTROL_STATE_FREE, nil)
		ball:SetAttribute("LastReleaseReason", reason)
		clearSoftInvalid()
		return
	end

	log(string.format("Control released: %s", reason))
	activeController = nil
	setBallState(ball, CONTROL_STATE_FREE, nil)
	ball:SetAttribute("LastReleaseReason", reason)
	clearSoftInvalid()
end

local function acquireControl(ball: BasePart, player: Player)
	if activeController == player then
		return
	end

	activeController = player
	setBallState(ball, CONTROL_STATE_CONTROLLED, player)
	ball:SetAttribute("LastReleaseReason", "")
	clearSoftInvalid()
	log(string.format("Control acquired by %s", player.Name))
end

local function shouldReleaseForSoftInvalid(reason: string): boolean
	local now = os.clock()

	if softInvalidReason ~= reason then
		softInvalidReason = reason
		softInvalidStartedAt = now
		return false
	end

	return softInvalidStartedAt ~= nil and now - softInvalidStartedAt >= controlConfig.ReleaseGracePeriod
end

local function updateControlDirection(player: Player, movementDirection: Vector3, playerSpeed: number): Vector3
	local lastDirection = lastControlDirectionByPlayer[player]

	if playerSpeed < controlConfig.StationaryPlayerSpeed then
		return lastDirection or movementDirection
	end

	if not lastDirection then
		lastControlDirectionByPlayer[player] = movementDirection
		return movementDirection
	end

	if lastDirection:Dot(movementDirection) < controlConfig.SharpTurnDirectionDot then
		return lastDirection
	end

	local smoothed = lastDirection:Lerp(movementDirection, controlConfig.DirectionSmoothing)

	if smoothed.Magnitude <= 0 then
		lastControlDirectionByPlayer[player] = movementDirection
		return movementDirection
	end

	local direction = smoothed.Unit
	lastControlDirectionByPlayer[player] = direction

	return direction
end

local function getDribbleTargetDistance(humanoid: Humanoid): number
	if humanoid:GetAttribute("SprintRequested") == true then
		return controlConfig.ControlTargetDistanceSprint
	end

	return controlConfig.ControlTargetDistanceWalk
end

local function getDribbleStrength(humanoid: Humanoid): number
	if humanoid:GetAttribute("SprintRequested") == true then
		return controlConfig.DribbleTouchStrengthSprint
	end

	return controlConfig.DribbleTouchStrengthWalk
end

local function applyImpulseVelocity(ball: BasePart, impulseVelocity: Vector3)
	if not isFiniteVector(impulseVelocity) or impulseVelocity.Magnitude <= 0 then
		return
	end

	ball:ApplyImpulse(impulseVelocity * ball.AssemblyMass)
end

local function applyMinimumSeparation(ball: BasePart, rootPart: BasePart, controlDirection: Vector3)
	local horizontalFromPlayer = getHorizontal(ball.Position - rootPart.Position)
	local distance = horizontalFromPlayer.Magnitude
	local requiredCenterDistance = controlConfig.ControlOriginRadius + BallConfig.Radius + controlConfig.MinimumControlSeparation

	if distance >= requiredCenterDistance then
		return
	end

	local radialDirection = if distance > 0 then horizontalFromPlayer.Unit else controlDirection
	local correctionDirection = radialDirection * 0.25 + controlDirection * 0.75

	if correctionDirection.Magnitude <= 0 then
		correctionDirection = controlDirection
	end

	local separationError = requiredCenterDistance - distance
	local deltaSpeed = math.min(
		separationError * controlConfig.SeparationCorrectionStrength,
		controlConfig.MaxSeparationImpulseDeltaSpeed
	)

	applyImpulseVelocity(ball, correctionDirection.Unit * deltaSpeed)
end

local function applyCloseControl(ball: BasePart, candidate)
	local controlDirection = updateControlDirection(candidate.Player, candidate.MovementDirection, candidate.PlayerSpeed)

	applyMinimumSeparation(ball, candidate.RootPart, controlDirection)

	if candidate.PlayerSpeed < controlConfig.StationaryPlayerSpeed then
		return
	end

	local now = os.clock()
	local lastDribble = lastDribbleByPlayer[candidate.Player]

	if lastDribble and now - lastDribble < controlConfig.DribbleTouchInterval then
		return
	end

	lastDribbleByPlayer[candidate.Player] = now

	local targetDistance = getDribbleTargetDistance(candidate.Humanoid)
	local targetPosition = candidate.RootPart.Position + controlDirection * targetDistance
	local toTarget = getHorizontal(targetPosition - ball.Position)
	local targetError = toTarget.Magnitude

	if targetError < controlConfig.TargetDeadzone then
		return
	end

	local ballVelocity = getHorizontal(ball.AssemblyLinearVelocity)
	local targetDirection = toTarget.Unit
	local currentTargetSpeed = math.max(0, ballVelocity:Dot(targetDirection))
	local desiredDeltaSpeed = math.min(
		targetError * getDribbleStrength(candidate.Humanoid) - currentTargetSpeed,
		controlConfig.MaxDribbleImpulseDeltaSpeed
	)

	if desiredDeltaSpeed <= 0 then
		return
	end

	applyImpulseVelocity(ball, targetDirection * desiredDeltaSpeed)
end

function BallControlService.Initialize(ball: BasePart)
	activeController = nil
	table.clear(lastDribbleByPlayer)
	table.clear(lastControlDirectionByPlayer)
	clearSoftInvalid()
	setBallState(ball, CONTROL_STATE_FREE, nil)
	ball:SetAttribute("LastReleaseReason", "")
end

function BallControlService.Reset(ball: BasePart)
	if activeController then
		releaseControl(ball, "ball reset")
	else
		setBallState(ball, CONTROL_STATE_FREE, nil)
		ball:SetAttribute("LastReleaseReason", "ball reset")
		clearSoftInvalid()
	end

	table.clear(lastDribbleByPlayer)
	table.clear(lastControlDirectionByPlayer)
end

function BallControlService.CleanupPlayer(player: Player, ball: BasePart?)
	lastDribbleByPlayer[player] = nil
	lastControlDirectionByPlayer[player] = nil

	if activeController == player then
		if ball then
			releaseControl(ball, "controller left")
		else
			activeController = nil
			clearSoftInvalid()
		end
	end
end

function BallControlService.Update(ball: BasePart): boolean
	if activeController then
		local invalidReason, releaseImmediately = getControllerInvalidReason(ball)

		if invalidReason then
			if releaseImmediately or shouldReleaseForSoftInvalid(invalidReason) then
				releaseControl(ball, invalidReason)
			else
				setBallState(ball, CONTROL_STATE_CONTROLLED, activeController)
				return true
			end
		else
			clearSoftInvalid()
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
		return false
	end

	local activeCandidate = getActiveControllerContext(activeController, ball)

	if not activeCandidate then
		releaseControl(ball, "movement state invalid")
		return false
	end

	applyCloseControl(ball, activeCandidate)
	setBallState(ball, CONTROL_STATE_CONTROLLED, activeController)

	return true
end

return BallControlService
