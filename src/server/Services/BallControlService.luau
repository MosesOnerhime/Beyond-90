local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AIConfig = require(Shared.Config.AIConfig)
local BallConfig = require(Shared.Config.BallConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GameConfig = require(Shared.Config.GameConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local ReceptionPlanner = require(Shared.Football.ReceptionPlanner)

local BallControlService = {}

local CONTROL_STATE_FREE = "Free"
local CONTROL_STATE_CONTROLLED = "Controlled"

local controlConfig = BallConfig.Control
local ownershipConfig = BallConfig.Ownership
local activeController: Player? = nil
local activeAIController = nil
local lastControlDirectionByPlayer: { [Player]: Vector3 } = {}
local lastLogicalTouchByPlayer: { [Player]: number } = {}
local logicalTouchCountByPlayer: { [Player]: number } = {}
local lastLeadDiagnosticByPlayer: { [Player]: number } = {}
local leadDiagnosticSampleIdByPlayer: { [Player]: number } = {}
local acquisitionSuppressedUntilByPlayer: { [Player]: any } = {}
--[[
	Reacquisition claims.

	A knock-on is not a loss of possession -- the player deliberately pushed the
	ball ahead and is chasing their own touch. Treating it like any other loose
	ball meant the originator was suppressed for well over a second and then had
	to win a neutral contest for a ball they had just played.

	A claim is priority, never ownership: it only adds to the originator's
	candidate score, so an opponent who genuinely arrives first still wins the
	football.
]]
local reacquisitionClaimByPlayer: { [Player]: { Until: number, ScoreBonus: number } } = {}

--[[
	Report a football contact to the referee.

	Resolved lazily so this module never has to require MatchRulesService at load
	time, which keeps the dependency strictly one-way.
]]
local matchRulesService = nil
local footballerRegistryService = nil
local function getRegistry()
	if footballerRegistryService == nil then
		local ok, resolved = pcall(function()
			return require(script.Parent.FootballerRegistryService)
		end)
		footballerRegistryService = if ok then resolved else false
	end
	return footballerRegistryService or nil
end

local function notifyRulesTouch(actor, kind: string)
	if not actor then
		return
	end
	if matchRulesService == nil then
		local ok, resolved = pcall(function()
			return require(script.Parent.MatchRulesService)
		end)
		matchRulesService = if ok then resolved else false
	end
	if matchRulesService then
		matchRulesService.NotifyTouch(actor, kind)
	end
end

local function getReacquisitionBonus(player: Player): number
	local claim = reacquisitionClaimByPlayer[player]
	if not claim then
		return 0
	end
	if os.clock() >= claim.Until then
		reacquisitionClaimByPlayer[player] = nil
		return 0
	end
	return claim.ScoreBonus
end

local lastReceptionDiagnosticAtByPlayer: { [Player]: number } = {}
local lastOwnershipValidationAt = 0
local distanceViolationStartedAt: number? = nil
local lastAcceptedBallState: { Position: Vector3, Velocity: Vector3, Timestamp: number }? = nil
local controllerNoCollisionConstraints: { NoCollisionConstraint } = {}
local controllerCharacterConnection: RBXScriptConnection? = nil
local controlEpoch = 0
local previousFreeBallPosition: Vector3? = nil
local networkOwnershipHandoffUntil = 0
local controlAcquiredAt = 0
local speedViolationStartedAt: number? = nil
local receptionTransactionByPassId: { [number]: { Player: Player, Time: number, Epoch: number } } = {}
-- Milestone 6.1 AI possession acceptance metrics.
local aiPossessionStats = {
	Acquisitions = 0,
	Releases = 0,
	UnintendedReleases = 0,
	DistanceExceeded = 0,
	--[[
		RELEASE REASONS (§79).

		Losing the ball to a TACKLE was previously counted as an unintended
		release -- i.e. as an AI ball-control failure -- which made the possession
		stability metric read much worse than the control system deserved. An
		opponent winning the ball is the game working, not the AI failing.

		Kept separate so the stability number means what it claims to.
	]]
	Tackled = 0,
	OpponentWon = 0,
	InvalidState = 0,
	Unexpected = 0,
	DurationSum = 0,
	CurrentMinLead = 0,
	CurrentMaxLead = 0,
}

--[[
	Classify a release reason.

	Returns one of:
		IntentionalAction  the AI played the ball (pass, shot, clearance)
		Tackled            an opponent took it -- not a control failure
		OpponentWon        another footballer legitimately acquired it
		DistanceExceeded   the AI genuinely lost its own football
		InvalidState       the match tore the possession down (restart, reset)
		Unexpected         anything else, which is what should be investigated
]]
local function classifyReleaseReason(reason: string): string
	local function has(needle: string): boolean
		return string.find(reason, needle, 1, true) ~= nil
	end
	if has("Pass") or has("Shoot") or has("Clearance") or has("KnockOn") or has("ThrowIn") then
		return "IntentionalAction"
	end
	if has("Tackled") or has("tackle") then
		return "Tackled"
	end
	if has("distance exceeded") then
		return "DistanceExceeded"
	end
	--[[
		Other genuine control failures. These are the AI losing its own football --
		it went too high to keep, or too fast -- so they count against stability,
		but they are KNOWN causes and should not be reported as unexplained.
	]]
	if has("too high") or has("too fast") or has("speed") or has("invalid") then
		return "LostControl"
	end
	if has("restart") or has("stopped") or has("rebuilding") or has("reset") or has("kickoff") then
		return "InvalidState"
	end
	if has("acquired") or has("opponent") then
		return "OpponentWon"
	end
	return "Unexpected"
end

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

local function setBallState(ball: BasePart, state: string, controller: Player?, aiController)
	ball:SetAttribute("State", state)
	ball:SetAttribute("ControllerUserId", if controller then controller.UserId else 0)
	ball:SetAttribute("ControllerFootballerId", if aiController then aiController.Id else if controller then controller.UserId else 0)
	ball:SetAttribute("ControllerKind", if aiController then "AI" else if controller then "Human" else "")
end

local function advanceControlEpoch(ball: BasePart): number
	controlEpoch += 1
	ball:SetAttribute("ControlEpoch", controlEpoch)
	return controlEpoch
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

local function resolveControlDirection(ball: BasePart, candidate): Vector3
	local controlKey = candidate.ControlKey or candidate.Player
	local handoffUntil = ball:GetAttribute("ControlHandoffUntil")
	local initialDirection = ball:GetAttribute("InitialControlDirection")
	if typeof(handoffUntil) == "number" and os.clock() < handoffUntil
		and typeof(initialDirection) == "Vector3" and initialDirection.Magnitude > 0.05
	then
		local direction = BallControlMath.SafeUnit(initialDirection, getFacingDirection(candidate.RootPart))
		lastControlDirectionByPlayer[controlKey] = direction
		return direction
	end
	return updateControlDirection(
		controlKey,
		candidate.RootPart,
		candidate.MovementDirection,
		candidate.PlayerSpeed
	)
end

local function getControlContext(
	player: Player,
	ball: BasePart,
	distanceLimit: number,
	maxBallSpeed: number,
	heightTolerance: number,
	requireAcquireMovement: boolean,
	requireClearContactPath: boolean,
	useHorizontalSpeed: boolean?
)
	local character, rootPart, humanoid = getCharacterParts(player)

	if not character or not rootPart or not humanoid then
		return nil
	end

	if not isBallWithinHeight(ball, heightTolerance) then
		return nil
	end

	--[[
		Retention is defined on HORIZONTAL ball speed, and getControllerInvalidReason
		enforces exactly that, with a grace period. Measuring the full 3-D speed here
		made the two disagree: a normal dribble touch with its small vertical lift
		could exceed the 3-D limit while the horizontal component was still legal.
		getControllerInvalidReason then reported the controller valid, this returned
		nil anyway, and possession was dropped as "movement state invalid" with no
		grace at all -- mid-sprint, on a legitimate touch.
	]]
	local measuredSpeed = if useHorizontalSpeed
		then BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity).Magnitude
		else ball.AssemblyLinearVelocity.Magnitude
	if measuredSpeed > maxBallSpeed then
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
	local character, rootPart, humanoid = getCharacterParts(player)

	if not character or not rootPart or not humanoid then
		return nil
	end

	if not hasClearContactPath(character, ball, rootPart) then
		return nil
	end

	return ReceptionPlanner.Evaluate(player, ball, rootPart, humanoid, BallConfig.Reception, previousFreeBallPosition)
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
		false,
		-- Retention uses the horizontal measure, matching getControllerInvalidReason.
		true
	)
end

--[[
	Restart and pre-match acquisition block (§25, §27, §28).

	NOBODY acquires ordinary dribble possession while a restart is pending -- the
	designated taker included. That is the whole architectural point: runtime
	evidence showed a kick-off being "taken" as a LooseBall / TakeInStride
	reception, after which the taker simply dribbled away, which is not a legal
	kick-off in any code path.

	During a restart the taker holds RestartControl instead (RestartService), and
	the only way out of it is a legal release action. Before the match has been
	started at all, no one may touch the ball either.
]]
local function isRestartBlocked(_actor): boolean
	if matchRulesService == nil then
		local ok, resolved = pcall(function()
			return require(script.Parent.MatchRulesService)
		end)
		matchRulesService = if ok then resolved else false
	end
	if not matchRulesService then
		return false
	end
	if matchRulesService.IsPreMatch and matchRulesService.IsPreMatch() then
		return true
	end
	return matchRulesService.IsRestartActive()
end

local function chooseBestCandidate(ball: BasePart)
	local bestCandidate = nil
	local now = os.clock()

	for _, player in Players:GetPlayers() do
		local suppression = acquisitionSuppressedUntilByPlayer[player]

		if suppression then
			local suppress = false

			if typeof(suppression) == "number" then
				suppress = now < suppression
			else
				if suppression.ExpireAt and now >= suppression.ExpireAt then
					acquisitionSuppressedUntilByPlayer[player] = nil
				elseif suppression.MinUntil and now < suppression.MinUntil then
					suppress = true
				elseif suppression.RequiresExit and not suppression.HasExited then
					local _character, rootPart = getCharacterParts(player)
					local distance = if rootPart
						then BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude
						else math.huge

					if distance >= (suppression.ExitDistance or controlConfig.AcquireDistance) then
						suppression.HasExited = true
					else
						suppress = true
					end
				end
			end

			if suppress then
				continue
			end
		end

		local candidate = getCandidateContext(player, ball)

		if candidate and isRestartBlocked(getRegistry() and getRegistry().GetHumanActor(player)) then
			candidate = nil
		end

		if candidate then
			-- Chasing your own knock-on is favoured, not guaranteed: this only
			-- raises the score, so a better-placed opponent still wins the ball.
			candidate.Score += getReacquisitionBonus(player)
			if not bestCandidate or candidate.Score > bestCandidate.Score then
				bestCandidate = candidate
			end
		end
	end

	return bestCandidate
end

local function getCandidateFootballerId(candidate): number
	if typeof(candidate.FootballerId) == "number" then
		return candidate.FootballerId
	end
	return if typeof(candidate.Player) == "Instance" and candidate.Player:IsA("Player")
		then candidate.Player.UserId
		else 0
end

local function getCandidateDisplayName(candidate): string
	return candidate.DisplayName or (candidate.Player and candidate.Player.Name) or "Footballer"
end

local function applyReceptionFirstTouch(ball: BasePart, candidate, epoch: number)
	local velocity = candidate.FirstTouchVelocity

	if typeof(velocity) ~= "Vector3" or not isFiniteVector(velocity) then
		return
	end

	local ballVelocityBefore = ball.AssemblyLinearVelocity
	local ballSpeedBefore = BallControlMath.GetHorizontal(ballVelocityBefore).Magnitude
	local playerVelocity = BallControlMath.GetHorizontal(candidate.RootPart.AssemblyLinearVelocity)
	local controlDirection = BallControlMath.SafeUnit(candidate.ControlDirection, getFacingDirection(candidate.RootPart))
	local leadBefore = BallControlMath.GetHorizontal(ball.Position - candidate.RootPart.Position):Dot(controlDirection)
	local expectedLead = if typeof(candidate.FirstTouchTarget) == "Vector3"
		then BallControlMath.GetHorizontal(candidate.FirstTouchTarget - candidate.RootPart.Position):Dot(controlDirection)
		else BallConfig.Control.HandoffTargetLead

	ball.AssemblyLinearVelocity = velocity
	local horizontalVelocityAfter = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	local relativeSpeedAfter = (horizontalVelocityAfter - playerVelocity).Magnitude

	local angularDamping = if candidate.FirstTouchType == "Settle"
		then BallConfig.Reception.AngularDampingOnSettle
		else BallConfig.Reception.AngularDampingOnReceive
	ball.AssemblyAngularVelocity = ball.AssemblyAngularVelocity:Lerp(Vector3.zero, angularDamping)
	local receiverId = getCandidateFootballerId(candidate)
	local receiverName = getCandidateDisplayName(candidate)
	ball:SetAttribute("LastReceptionPlayerUserId", receiverId)
	ball:SetAttribute("LastReceptionPlayerName", receiverName)
	ball:SetAttribute("LastReceptionType", candidate.FirstTouchType)
	ball:SetAttribute("LastReceptionDistance", candidate.Distance)
	ball:SetAttribute("LastReceptionBallSpeed", candidate.BallSpeed)
	ball:SetAttribute("LastReceptionRelativeSpeed", candidate.RelativeSpeed)
	ball:SetAttribute("LastReceptionIntended", candidate.IntendedReceiver)
	ball:SetAttribute("LastReceptionActionType", candidate.ActionType)
	ball:SetAttribute("LastReceptionTime", os.clock())
	ball:SetAttribute("InitialControlDirection", controlDirection)
	ball:SetAttribute("InitialExpectedLead", expectedLead)
	ball:SetAttribute("InitialPlayerVelocity", playerVelocity)
	ball:SetAttribute("InitialBallVelocityAfterFirstTouch", ball.AssemblyLinearVelocity)
	ball:SetAttribute("ControlHandoffFirstTouchType", candidate.FirstTouchType)
	ball:SetAttribute("ControlHandoffUntil", os.clock() + BallConfig.Control.HandoffStabilizationDuration)
	local actionStartedAt = ball:GetAttribute("LastFootballActionTime")
	local predictedArrival = ball:GetAttribute("LastFootballActionEstimatedArrivalTime")
	local passId = ball:GetAttribute("LastFootballActionPassId")
	-- A pass is delivered exactly once. Without this latch every later
	-- re-acquisition inside the intended-receiver window re-measured the same
	-- pass against its original launch time, producing growing phantom ETAs.
	local passAlreadyDelivered = typeof(passId) == "number"
		and passId ~= 0
		and ball:GetAttribute("LastFootballActionDeliveredPassId") == passId
	if candidate.IntendedReceiver
		and not passAlreadyDelivered
		and (candidate.ActionType == "GroundPass" or candidate.ActionType == "ThroughPass" or candidate.ActionType == "LobPass")
		and typeof(actionStartedAt) == "number"
	then
		local measuredArrival = os.clock() - actionStartedAt
		if typeof(passId) == "number" and passId ~= 0 then
			ball:SetAttribute("LastFootballActionDeliveredPassId", passId)
		end
		log(string.format(
			"[PassArrival] type=%s receiver=%s passId=%s predictedETA=%.2f measuredETA=%.2f measuredArrivalSpeed=%.1f",
			candidate.ActionType,
			receiverName,
			tostring(passId or 0),
			if typeof(predictedArrival) == "number" then predictedArrival else 0,
			measuredArrival,
			ballSpeedBefore
		))
	end

	if not BallConfig.Reception.DebugEnabled then
		return
	end

	local diagnosticKey = candidate.ControlKey or candidate.Player
	local last = lastReceptionDiagnosticAtByPlayer[diagnosticKey]
	local now = os.clock()

	if last and now - last < BallConfig.Reception.DiagnosticCooldown then
		return
	end

	lastReceptionDiagnosticAtByPlayer[diagnosticKey] = now
	log(string.format(
		"[Reception] player=%s type=%s intended=%s distance=%.2f ballSpeed=%.2f relativeSpeed=%.2f result=Acquired firstTouch=%s",
		receiverName,
		if candidate.ActionType ~= "" then candidate.ActionType else "LooseBall",
		tostring(candidate.IntendedReceiver),
		candidate.Distance,
		candidate.BallSpeed,
		candidate.RelativeSpeed,
		candidate.FirstTouchType
	))
	log(string.format(
		"[ReceptionHandoff] epoch=%d player=%s type=%s firstTouch=%s playerSpeed=%.1f leadBefore=%.2f ballSpeedBefore=%.2f ballSpeedAfter=%.2f relativeSpeedAfter=%.2f expectedLead=%.2f",
		epoch,
		receiverName,
		if candidate.ActionType ~= "" then candidate.ActionType else "LooseBall",
		candidate.FirstTouchType,
		candidate.PlayerSpeed,
		leadBefore,
		ballSpeedBefore,
		horizontalVelocityAfter.Magnitude,
		relativeSpeedAfter,
		expectedLead
	))
end

local function releaseControl(ball: BasePart, reason: string)
	networkOwnershipHandoffUntil = 0
	if not activeController then
		setServerNetworkOwner(ball)
		setBallState(ball, CONTROL_STATE_FREE, nil)
		ball:SetAttribute("LastReleaseReason", reason)
		ball:SetAttribute("ControlClientServoReadyAt", 0)
		clearControllerNoCollision()
		lastAcceptedBallState = nil
		distanceViolationStartedAt = nil
		return
	end

	local previousController = activeController :: Player
	log(string.format("Control released: %s", reason))
	setServerNetworkOwner(ball)

	activeController = nil
	controlAcquiredAt = 0
	speedViolationStartedAt = nil
	lastLogicalTouchByPlayer[previousController] = nil
	logicalTouchCountByPlayer[previousController] = nil
	lastControlDirectionByPlayer[previousController] = nil
	lastLeadDiagnosticByPlayer[previousController] = nil
	leadDiagnosticSampleIdByPlayer[previousController] = nil
	lastAcceptedBallState = nil
	lastOwnershipValidationAt = 0
	distanceViolationStartedAt = nil
	clearControllerNoCollision()
	setBallState(ball, CONTROL_STATE_FREE, nil)
	ball:SetAttribute("LastReleaseReason", reason)
	ball:SetAttribute("ControlClientServoReadyAt", 0)
end

local function acquireControl(ball: BasePart, player: Player, receptionContext)
	if activeController == player then
		return
	end

	local previousController = activeController
	if ball:GetAttribute("FootballControlPhase") == "KnockOnReleased"
		and ball:GetAttribute("LastFootballActionPlayerUserId") == player.UserId
	then
		local releasedAt = ball:GetAttribute("KnockOnReleasedAt")
		local duration = if typeof(releasedAt) == "number" then os.clock() - releasedAt else 0
		log(string.format(
			"[KnockOnRecontact] player=%s maxSeparation=%.1f recontactTime=%.2f",
			player.Name,
			ball:GetAttribute("KnockOnMaxSeparation") or 0,
			duration
		))
	end
	local character = player.Character

	if previousController then
		lastLogicalTouchByPlayer[previousController] = nil
		logicalTouchCountByPlayer[previousController] = nil
		lastControlDirectionByPlayer[previousController] = nil
		lastLeadDiagnosticByPlayer[previousController] = nil
		leadDiagnosticSampleIdByPlayer[previousController] = nil
	end

	local passId = ball:GetAttribute("LastFootballActionPassId")
	local previousReception = if receptionContext and receptionContext.IntendedReceiver and typeof(passId) == "number"
		then receptionTransactionByPassId[passId]
		else nil
	local reuseReception = previousReception ~= nil
		and previousReception.Player == player
		and os.clock() - previousReception.Time <= BallConfig.Reception.DuplicateReceptionGuardSeconds
	local epoch = if reuseReception then previousReception.Epoch else advanceControlEpoch(ball)

	if receptionContext and not reuseReception then
		applyReceptionFirstTouch(ball, receptionContext, epoch)
		lastControlDirectionByPlayer[player] = BallControlMath.SafeUnit(
			receptionContext.ControlDirection,
			getFacingDirection(receptionContext.RootPart)
		)
	elseif not reuseReception then
		ball:SetAttribute("InitialControlDirection", nil)
		ball:SetAttribute("InitialExpectedLead", 0)
		ball:SetAttribute("InitialPlayerVelocity", Vector3.zero)
		ball:SetAttribute("InitialBallVelocityAfterFirstTouch", ball.AssemblyLinearVelocity)
		ball:SetAttribute("ControlHandoffFirstTouchType", "")
		ball:SetAttribute("ControlHandoffUntil", 0)
	end
	if receptionContext and receptionContext.IntendedReceiver and typeof(passId) == "number" and not reuseReception then
		receptionTransactionByPassId[passId] = { Player = player, Time = os.clock(), Epoch = epoch }
	elseif reuseReception then
		log(string.format("[Reception] reused transaction passId=%d player=%s epoch=%d", passId, player.Name, epoch))
	end

	activeController = player
	controlAcquiredAt = os.clock()
	speedViolationStartedAt = nil
	lastLogicalTouchByPlayer[player] = nil
	logicalTouchCountByPlayer[player] = 0
	lastLeadDiagnosticByPlayer[player] = nil
	leadDiagnosticSampleIdByPlayer[player] = 0
	setBallState(ball, CONTROL_STATE_CONTROLLED, player)
	ball:SetAttribute("FootballControlPhase", "Controlled")
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
	ball:SetAttribute("LastLocalTouchWorldBallTravel", 0)
	ball:SetAttribute("LastLocalTouchPeakForwardLead", 0)
	ball:SetAttribute("LastLocalTouchMinForwardLead", 0)
	ball:SetAttribute("LastLocalTouchRelativeLongitudinalVelocity", 0)
	ball:SetAttribute("LastLocalTouchPredictedRecontactTime", 0)
	ball:SetAttribute("LastLocalTouchActualRecontactTime", 0)
	ball:SetAttribute("LastReceptionPlayerUserId", if receptionContext then getCandidateFootballerId(receptionContext) else 0)
	ball:SetAttribute("LastReceptionType", if receptionContext then receptionContext.FirstTouchType else "")
	ball:SetAttribute("ControlEpoch", epoch)
	local clientServoReadyAt = Workspace:GetServerTimeNow()
	if isPlayerOwnedMode() and receptionContext then
		clientServoReadyAt += BallConfig.Reception.NetworkOwnershipHandoffDelay
			+ BallConfig.Reception.ClientServoOwnershipBuffer
	end
	ball:SetAttribute("ControlClientServoReadyAt", clientServoReadyAt)

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
	-- Last touch drives every restart decision, so it is reported, not inferred.
	notifyRulesTouch(getRegistry() and getRegistry().GetHumanActor(player), "Control")

	if isPlayerOwnedMode() then
		if receptionContext then
			setServerNetworkOwner(ball)
			networkOwnershipHandoffUntil = os.clock() + BallConfig.Reception.NetworkOwnershipHandoffDelay
			local handoffEpoch = epoch
			task.delay(BallConfig.Reception.NetworkOwnershipHandoffDelay, function()
				if activeController == player
					and ball.Parent
					and ball:GetAttribute("ControlEpoch") == handoffEpoch
				then
					setPlayerNetworkOwner(ball, player)
					networkOwnershipHandoffUntil = 0
				end
			end)
		else
			setPlayerNetworkOwner(ball, player)
		end
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

-- Set while the retention rule reports a valid controller but no control context
-- could be built; see the grace handling in the update path.
local contextLostSince: number? = nil

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

	--[[
		A just-received lofted ball is allowed to still be coming down.

		Same shape as the speed grace immediately below: for a short window after
		acquisition the football is judged against a taller tolerance, because a
		lob is received from above and needs a touch to bring it to the floor.
		After the window the ordinary limit applies, so nobody dribbles at chest
		height.
	]]
	local sinceAcquired = os.clock() - controlAcquiredAt
	local heightTolerance = if sinceAcquired < controlConfig.ControlAcquisitionHeightGrace
		then controlConfig.ControlAcquisitionHeightTolerance
		else controlConfig.ControlRetentionHeightTolerance
	if not isBallWithinHeight(ball, heightTolerance) then
		return "ball too high"
	end

	local horizontalSpeed = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity).Magnitude
	local speedLimit = if sinceAcquired < controlConfig.ControlAcquisitionSpeedGrace
		then ownershipConfig.MaxControlledSpeed
		else controlConfig.ControlRetentionMaxSpeed
	if horizontalSpeed > speedLimit then
		local now = os.clock()
		speedViolationStartedAt = speedViolationStartedAt or now
		if now - speedViolationStartedAt >= controlConfig.ControlRetentionSpeedViolationGrace then
			return string.format("ball too fast (horizontal=%.1f limit=%.1f)", horizontalSpeed, speedLimit)
		end
	else
		speedViolationStartedAt = nil
	end

	local horizontalDistance = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude
	local retentionDistance = if isPlayerOwnedMode()
		then ownershipConfig.MaxControlledDistance
		else controlConfig.HardControlDistance

	if horizontalDistance > retentionDistance then
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
	local controlKey = candidate.ControlKey or candidate.Player
	local lastLogicalTouch = lastLogicalTouchByPlayer[controlKey]
	-- A human client takes over its own servo shortly after acquisition, so the
	-- long server no-touch window is harmless there. An AI has no client, so the
	-- same window would leave the football completely uncorrected while the
	-- footballer accelerates away from it.
	local noTouchDuration = if candidate.IsAI
		then AIConfig.ControlledBall.NoTouchDuration
		else controlConfig.HandoffNoTouchDuration
	if now - controlAcquiredAt < noTouchDuration then
		return false
	end

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

	lastLogicalTouchByPlayer[controlKey] = now
	local count = (logicalTouchCountByPlayer[controlKey] or 0) + 1
	logicalTouchCountByPlayer[controlKey] = count
	ball:SetAttribute("LastControlTouchTime", now)
	ball:SetAttribute("LastControlTouchCount", count)
	ball:SetAttribute("ControlTargetError", velocityPlan.ToPlannedBall.Magnitude)

	log(string.format(
		"Control touch #%d by %s plannedSpeed=%.2f playerSpeed=%.2f overdrive=%.2f",
		count,
		candidate.DisplayName or candidate.Player.Name,
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
	local controlKey = candidate.ControlKey or candidate.Player
	local currentLead = BallControlMath.GetHorizontal(ball.Position - candidate.RootPart.Position):Dot(controlDirection)
	local sampleId = (leadDiagnosticSampleIdByPlayer[controlKey] or 0) + 1
	leadDiagnosticSampleIdByPlayer[controlKey] = sampleId
	ball:SetAttribute("CurrentBallLead", currentLead)
	ball:SetAttribute("ServerBallLead", currentLead)
	ball:SetAttribute("ServerLeadSampleId", sampleId)
	ball:SetAttribute("ServerLeadSampleTime", now)

	local lastLogTime = lastLeadDiagnosticByPlayer[controlKey]

	if lastLogTime and now - lastLogTime < controlConfig.LeadDiagnosticInterval then
		return
	end

	lastLeadDiagnosticByPlayer[controlKey] = now
	if isPlayerOwnedMode() and not candidate.IsAI then
		log(string.format("Lead sample id=%d server=%.2f mode=player-owned", sampleId, currentLead))
	else
		log(string.format(
			"Lead sample server=%.2f serverContacts=%d",
			currentLead,
			logicalTouchCountByPlayer[controlKey] or 0
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
	local speed = BallControlMath.GetHorizontal(velocity).Magnitude

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
	local controlDirection = resolveControlDirection(ball, candidate)

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

-- Speed-scaled carry lead, using the same BallConfig relationships the human
-- client servo uses so AI and human dribbling share one football model.
local function getAICarryLead(playerSpeed: number): number
	if playerSpeed < controlConfig.StationaryPlayerSpeed then
		return controlConfig.StationaryCarryLeadDistance
	end
	local alpha = math.clamp(playerSpeed / math.max(controlConfig.SprintReferenceSpeed, 1e-4), 0, 1)
	return controlConfig.CarryLeadDistance
		+ (controlConfig.SprintCarryLeadDistance - controlConfig.CarryLeadDistance) * alpha
end

-- The AI equivalent of ControlledBallController's possession servo. Humans run
-- theirs on their own client; an AI has no client, so the authoritative server
-- has to keep the footballer/ball relationship coherent itself.
local function applyAIPossessionControl(ball: BasePart, candidate, deltaTime: number)
	local aiConfig = AIConfig.ControlledBall
	local controlDirection = resolveControlDirection(ball, candidate)
	local rootPart = candidate.RootPart
	local playerVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local leadDistance = getAICarryLead(candidate.PlayerSpeed)
	local targetPosition = rootPart.Position + controlDirection * leadDistance
	local positionError = BallControlMath.GetHorizontal(targetPosition - ball.Position)
	local currentLead = BallControlMath.GetHorizontal(ball.Position - rootPart.Position):Dot(controlDirection)

	local touched = false
	if candidate.PlayerSpeed >= controlConfig.StationaryPlayerSpeed then
		touched = applyPlannedContact(ball, candidate, controlDirection)
	end

	if not touched and aiConfig.Enabled == true and positionError.Magnitude > aiConfig.DeadzoneStuds then
		-- A football that has fallen behind the footballer needs a firmer pull
		-- than one drifting slightly ahead, otherwise it never returns to a
		-- controllable lane before the distance check releases possession.
		local recovering = currentLead < leadDistance - aiConfig.RecoverLeadError
		local positionGain = if recovering then aiConfig.RecoverPositionGain else aiConfig.PositionGain
		local velocityDamping = if recovering then aiConfig.RecoverVelocityDamping else aiConfig.VelocityDamping
		local ballVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
		local desiredVelocity = playerVelocity * aiConfig.PlayerVelocityScale
			+ positionError * positionGain
			- (ballVelocity - playerVelocity) * velocityDamping * deltaTime
		desiredVelocity = BallControlMath.ClampMagnitude(desiredVelocity, aiConfig.MaxCorrectionSpeed)
		local horizontalDelta = BallControlMath.ClampMagnitude(
			desiredVelocity - ballVelocity,
			aiConfig.MaxDeltaSpeedPerSecond * deltaTime
		)
		applyVelocityDelta(ball, Vector3.new(horizontalDelta.X, 0, horizontalDelta.Z))
	end

	if not touched then
		applyMinimumSeparation(ball, rootPart, controlDirection)
	end

	aiPossessionStats.CurrentMinLead = math.min(aiPossessionStats.CurrentMinLead, currentLead)
	aiPossessionStats.CurrentMaxLead = math.max(aiPossessionStats.CurrentMaxLead, currentLead)
	ball:SetAttribute("ControlTargetError", positionError.Magnitude)
	ball:SetAttribute("ControlMode", if currentLead < 0 then "AIRecover" else "AICarry")
	ball:SetAttribute("AIControlLeadMin", aiPossessionStats.CurrentMinLead)
	ball:SetAttribute("AIControlLeadMax", aiPossessionStats.CurrentMaxLead)
	updateLeadDiagnostics(ball, candidate, controlDirection)
end

local function getAIControllerContext(actor, ball: BasePart)
	if not actor or not actor.Character or not actor.Character.Parent then
		return nil
	end
	local rootPart = actor.RootPart
	local humanoid = actor.Humanoid
	if not rootPart or not rootPart.Parent or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local horizontalVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local playerSpeed = horizontalVelocity.Magnitude
	local movementDirection = BallControlMath.GetHorizontal(humanoid.MoveDirection)
	if movementDirection.Magnitude <= 0.05 then
		movementDirection = BallControlMath.SafeUnit(horizontalVelocity, getFacingDirection(rootPart))
	else
		movementDirection = movementDirection.Unit
	end
	local horizontalToBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
	if horizontalToBall.Magnitude <= 0 then
		return nil
	end
	return {
		Player = actor.Character,
		ControlKey = actor.Character,
		DisplayName = actor.DisplayName,
		IsAI = true,
		Character = actor.Character,
		RootPart = rootPart,
		Humanoid = humanoid,
		MovementDirection = movementDirection,
		PlayerSpeed = playerSpeed,
		DirectionToBall = horizontalToBall.Unit,
		Distance = horizontalToBall.Magnitude,
		TowardBallDot = movementDirection:Dot(horizontalToBall.Unit),
		Score = 0,
	}
end

local function getAIControllerInvalidReason(ball: BasePart): string?
	local actor = activeAIController
	local candidate = getAIControllerContext(actor, ball)
	if not candidate then
		return "AI character invalid"
	end
	if not isBallWithinHeight(ball, controlConfig.ControlRetentionHeightTolerance) then
		return "AI controlled ball too high"
	end
	local horizontalSpeed = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity).Magnitude
	if horizontalSpeed > controlConfig.ControlRetentionMaxSpeed then
		return "AI controlled ball too fast"
	end
	if candidate.Distance > controlConfig.HardControlDistance then
		return "AI controlled ball distance exceeded"
	end
	return nil
end

local function clearAIControlState(actor)
	if not actor then
		return
	end
	local key = actor.Character
	lastLogicalTouchByPlayer[key] = nil
	logicalTouchCountByPlayer[key] = nil
	lastControlDirectionByPlayer[key] = nil
	lastLeadDiagnosticByPlayer[key] = nil
	leadDiagnosticSampleIdByPlayer[key] = nil
end

function BallControlService.Initialize(ball: BasePart)
	previousFreeBallPosition = ball.Position
	activeController = nil
	activeAIController = nil
	controlAcquiredAt = 0
	speedViolationStartedAt = nil
	table.clear(lastLogicalTouchByPlayer)
	table.clear(logicalTouchCountByPlayer)
	table.clear(lastControlDirectionByPlayer)
	table.clear(lastLeadDiagnosticByPlayer)
	table.clear(leadDiagnosticSampleIdByPlayer)
	table.clear(acquisitionSuppressedUntilByPlayer)
	table.clear(reacquisitionClaimByPlayer)
	table.clear(lastReceptionDiagnosticAtByPlayer)
	table.clear(receptionTransactionByPassId)
	lastOwnershipValidationAt = 0
	distanceViolationStartedAt = nil
	lastAcceptedBallState = nil
	networkOwnershipHandoffUntil = 0
	controlAcquiredAt = 0
	speedViolationStartedAt = nil
	clearControllerNoCollision()
	setServerNetworkOwner(ball)
	setBallState(ball, CONTROL_STATE_FREE, nil)
	controlEpoch = 0
	ball:SetAttribute("ControlEpoch", controlEpoch)
	ball:SetAttribute("ControllerFootballerId", 0)
	ball:SetAttribute("ControllerKind", "")
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
	ball:SetAttribute("LastLocalTouchWorldBallTravel", 0)
	ball:SetAttribute("LastLocalTouchPeakForwardLead", 0)
	ball:SetAttribute("LastLocalTouchMinForwardLead", 0)
	ball:SetAttribute("LastLocalTouchRelativeLongitudinalVelocity", 0)
	ball:SetAttribute("LastLocalTouchPredictedRecontactTime", 0)
	ball:SetAttribute("LastLocalTouchActualRecontactTime", 0)
	ball:SetAttribute("LastFootballAction", "")
	ball:SetAttribute("LastFootballActionPlayerUserId", 0)
	ball:SetAttribute("LastFootballActionTime", -1)
	ball:SetAttribute("LastFootballActionIntendedReceiverUserId", 0)
	ball:SetAttribute("LastFootballActionIntendedReceiverName", "")
	ball:SetAttribute("LastFootballActionPassId", 0)
	ball:SetAttribute("LastFootballActionTargetPosition", nil)
	ball:SetAttribute("LastFootballActionTargetKind", "")
	ball:SetAttribute("LastFootballActionEstimatedArrivalTime", 0)
	ball:SetAttribute("LastFootballActionPredictedCatchTime", 0)
	ball:SetAttribute("LastFootballActionPeakSeparation", 0)
	ball:SetAttribute("LastFootballActionGoalId", "")
	ball:SetAttribute("FootballFlightComplete", true)
	ball:SetAttribute("FootballGrounded", true)
	ball:SetAttribute("FootballBounceCount", 0)
	ball:SetAttribute("LastFootballBounceImpactSpeed", 0)
	ball:SetAttribute("LastFootballBounceReboundSpeed", 0)
	ball:SetAttribute("LastReceptionPlayerUserId", 0)
	ball:SetAttribute("LastReceptionPlayerName", "")
	ball:SetAttribute("LastReceptionType", "")
	ball:SetAttribute("LastReceptionDistance", 0)
	ball:SetAttribute("LastReceptionBallSpeed", 0)
	ball:SetAttribute("LastReceptionRelativeSpeed", 0)
	ball:SetAttribute("LastReceptionIntended", false)
	ball:SetAttribute("LastReceptionActionType", "")
	ball:SetAttribute("LastReceptionTime", -1)
	ball:SetAttribute("InitialControlDirection", nil)
	ball:SetAttribute("InitialExpectedLead", 0)
	ball:SetAttribute("InitialPlayerVelocity", Vector3.zero)
	ball:SetAttribute("InitialBallVelocityAfterFirstTouch", Vector3.zero)
	ball:SetAttribute("ControlHandoffFirstTouchType", "")
	ball:SetAttribute("ControlHandoffUntil", 0)
end

function BallControlService.Reset(ball: BasePart)
	previousFreeBallPosition = nil
	if activeAIController then
		BallControlService.ReleaseAI(ball, "ball reset")
	elseif activeController then
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
	table.clear(leadDiagnosticSampleIdByPlayer)
	table.clear(acquisitionSuppressedUntilByPlayer)
	table.clear(reacquisitionClaimByPlayer)
	table.clear(lastReceptionDiagnosticAtByPlayer)
	lastOwnershipValidationAt = 0
	distanceViolationStartedAt = nil
	lastAcceptedBallState = nil
	networkOwnershipHandoffUntil = 0
	advanceControlEpoch(ball)
	ball:SetAttribute("LastControlTouchTime", -1)
	ball:SetAttribute("LastControlTouchCount", 0)
	ball:SetAttribute("LastLocalControlTouchTime", -1)
	ball:SetAttribute("LastLocalControlTouchCount", 0)
	ball:SetAttribute("ControlTargetError", -1)
	ball:SetAttribute("CurrentBallLead", 0)
	ball:SetAttribute("ServerBallLead", 0)
	ball:SetAttribute("ClientBallLead", 0)
	ball:SetAttribute("NetworkOwnerUserId", 0)
	ball:SetAttribute("ControllerFootballerId", 0)
	ball:SetAttribute("ControllerKind", "")
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
	ball:SetAttribute("LastLocalTouchWorldBallTravel", 0)
	ball:SetAttribute("LastLocalTouchPeakForwardLead", 0)
	ball:SetAttribute("LastLocalTouchMinForwardLead", 0)
	ball:SetAttribute("LastLocalTouchRelativeLongitudinalVelocity", 0)
	ball:SetAttribute("LastLocalTouchPredictedRecontactTime", 0)
	ball:SetAttribute("LastLocalTouchActualRecontactTime", 0)
	ball:SetAttribute("LastFootballAction", "")
	ball:SetAttribute("LastFootballActionPlayerUserId", 0)
	ball:SetAttribute("LastFootballActionTime", -1)
	ball:SetAttribute("LastFootballActionIntendedReceiverUserId", 0)
	ball:SetAttribute("LastFootballActionIntendedReceiverName", "")
	ball:SetAttribute("LastFootballActionPassId", 0)
	ball:SetAttribute("LastFootballActionTargetPosition", nil)
	ball:SetAttribute("LastFootballActionTargetKind", "")
	ball:SetAttribute("LastFootballActionEstimatedArrivalTime", 0)
	ball:SetAttribute("LastFootballActionPredictedCatchTime", 0)
	ball:SetAttribute("LastFootballActionPeakSeparation", 0)
	ball:SetAttribute("LastFootballActionGoalId", "")
	ball:SetAttribute("FootballFlightComplete", true)
	ball:SetAttribute("FootballGrounded", true)
	ball:SetAttribute("FootballBounceCount", 0)
	ball:SetAttribute("LastFootballBounceImpactSpeed", 0)
	ball:SetAttribute("LastFootballBounceReboundSpeed", 0)
	ball:SetAttribute("LastReceptionPlayerUserId", 0)
	ball:SetAttribute("LastReceptionPlayerName", "")
	ball:SetAttribute("LastReceptionType", "")
	ball:SetAttribute("LastReceptionDistance", 0)
	ball:SetAttribute("LastReceptionBallSpeed", 0)
	ball:SetAttribute("LastReceptionRelativeSpeed", 0)
	ball:SetAttribute("LastReceptionIntended", false)
	ball:SetAttribute("LastReceptionActionType", "")
	ball:SetAttribute("LastReceptionTime", -1)
	ball:SetAttribute("InitialControlDirection", nil)
	ball:SetAttribute("InitialExpectedLead", 0)
	ball:SetAttribute("InitialPlayerVelocity", Vector3.zero)
	ball:SetAttribute("InitialBallVelocityAfterFirstTouch", Vector3.zero)
	ball:SetAttribute("ControlHandoffFirstTouchType", "")
	ball:SetAttribute("ControlHandoffUntil", 0)
	clearLegacyDiagnostics(ball)
end

function BallControlService.CleanupPlayer(player: Player, ball: BasePart?)
	lastLogicalTouchByPlayer[player] = nil
	logicalTouchCountByPlayer[player] = nil
	lastControlDirectionByPlayer[player] = nil
	lastLeadDiagnosticByPlayer[player] = nil
	leadDiagnosticSampleIdByPlayer[player] = nil
	acquisitionSuppressedUntilByPlayer[player] = nil
	reacquisitionClaimByPlayer[player] = nil
	lastReceptionDiagnosticAtByPlayer[player] = nil

	if activeController == player then
		if ball then
			releaseControl(ball, "controller left")
		else
			activeController = nil
			controlAcquiredAt = 0
			speedViolationStartedAt = nil
			clearControllerNoCollision()
		end
	end
end

function BallControlService.GetActiveController(): Player?
	return activeController
end

function BallControlService.GetActiveAIController()
	return activeAIController
end

function BallControlService.IsControlledBy(player: Player, ball: BasePart?): boolean
	if activeController ~= player then
		return false
	end

	if ball then
		return ball:GetAttribute("State") == CONTROL_STATE_CONTROLLED
			and ball:GetAttribute("ControllerUserId") == player.UserId
	end

	return true
end

function BallControlService.IsControlledByAI(actor, ball: BasePart?): boolean
	if not actor or activeAIController ~= actor then
		return false
	end
	if ball then
		return ball:GetAttribute("State") == CONTROL_STATE_CONTROLLED
			and ball:GetAttribute("ControllerKind") == "AI"
			and ball:GetAttribute("ControllerFootballerId") == actor.Id
	end
	return true
end

function BallControlService.TryAcquireAI(ball: BasePart, actor, maximumDistance: number?, maximumSpeed: number?): boolean
	if activeController or activeAIController or not actor then
		return false
	end
	-- Nobody dribbles a stationary restart into play (§27).
	if isRestartBlocked(actor) then
		return false
	end
	local controlCandidate = getAIControllerContext(actor, ball)
	local receptionContext = ReceptionPlanner.EvaluateActor(actor, ball, BallConfig.Reception, previousFreeBallPosition)
	if not controlCandidate or not receptionContext
		or receptionContext.Distance > (maximumDistance or controlConfig.AcquireDistance)
		or BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity).Magnitude > (maximumSpeed or controlConfig.MaximumControllableBallSpeed)
		or not isBallWithinHeight(ball, controlConfig.ControlHeightTolerance)
	then
		return false
	end

	activeAIController = actor
	controlAcquiredAt = os.clock()
	speedViolationStartedAt = nil
	local epoch = advanceControlEpoch(ball)
	clearControllerNoCollision()
	setControllerNoCollision(ball, actor.Character)
	setServerNetworkOwner(ball)
	setBallState(ball, CONTROL_STATE_CONTROLLED, nil, actor)
	ball:SetAttribute("FootballControlPhase", "Controlled")
	ball:SetAttribute("LastReleaseReason", "")
	ball:SetAttribute("ControlClientServoReadyAt", 0)
	applyReceptionFirstTouch(ball, receptionContext, epoch)
	logicalTouchCountByPlayer[actor.Character] = 0
	lastControlDirectionByPlayer[actor.Character] = BallControlMath.SafeUnit(
		receptionContext.ControlDirection,
		getFacingDirection(actor.RootPart)
	)
	aiPossessionStats.Acquisitions += 1
	aiPossessionStats.CurrentMinLead = 0
	aiPossessionStats.CurrentMaxLead = 0
	log(string.format("Control acquired by AI %s id=%d", actor.DisplayName, actor.Id))
	notifyRulesTouch(actor, "Control")
	return true
end

--[[
	Force the football free, whoever holds it.

	Used when the referee stops play: a restart must place the ball on the pitch,
	and a ball still under control is dragged straight back to its controller by
	the possession servo, which is exactly what left corners unreachable.
]]
function BallControlService.ForceRelease(ball: BasePart, reason: string)
	if activeAIController then
		BallControlService.ReleaseAI(ball, reason)
	end
	if activeController then
		releaseControl(ball, reason)
	end
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
end

function BallControlService.ReleaseAI(ball: BasePart, reason: string): boolean
	local actor = activeAIController
	if not actor then
		return false
	end
	--[[
		Acceptance telemetry (§79). Only a release that represents the AI losing
		its OWN football counts against control stability; being tackled, or the
		match taking the ball away for a restart, does not.
	]]
	local duration = if controlAcquiredAt > 0 then os.clock() - controlAcquiredAt else 0
	local category = classifyReleaseReason(reason)
	aiPossessionStats.Releases += 1
	aiPossessionStats.DurationSum += duration

	if category == "Tackled" then
		aiPossessionStats.Tackled += 1
	elseif category == "OpponentWon" then
		aiPossessionStats.OpponentWon += 1
	elseif category == "DistanceExceeded" then
		aiPossessionStats.DistanceExceeded += 1
		aiPossessionStats.UnintendedReleases += 1
	elseif category == "LostControl" then
		aiPossessionStats.UnintendedReleases += 1
	elseif category == "InvalidState" then
		aiPossessionStats.InvalidState += 1
	elseif category == "Unexpected" then
		aiPossessionStats.Unexpected += 1
		aiPossessionStats.UnintendedReleases += 1
	end

	log(string.format(
		"AI control released: %s by %s duration=%.2fs category=%s minLead=%.2f maxLead=%.2f",
		reason,
		actor.DisplayName,
		duration,
		category,
		aiPossessionStats.CurrentMinLead,
		aiPossessionStats.CurrentMaxLead
	))
	setServerNetworkOwner(ball)
	clearAIControlState(actor)
	activeAIController = nil
	controlAcquiredAt = 0
	speedViolationStartedAt = nil
	clearControllerNoCollision()
	setBallState(ball, CONTROL_STATE_FREE, nil)
	ball:SetAttribute("LastReleaseReason", reason)
	ball:SetAttribute("ControlClientServoReadyAt", 0)
	return true
end

function BallControlService.ReleaseAIForFootballAction(
	ball: BasePart,
	actor,
	actionName: string,
	launchVelocity: Vector3,
	actionContext: { [string]: any }?
): boolean
	if activeAIController ~= actor or not isFiniteVector(launchVelocity) then
		return false
	end
	if not BallControlService.ReleaseAI(ball, string.format("%s by %s", actionName, actor.DisplayName)) then
		return false
	end
	ball.AssemblyLinearVelocity = launchVelocity
	local horizontalLaunchVelocity = Vector3.new(launchVelocity.X, 0, launchVelocity.Z)
	ball.AssemblyAngularVelocity = Vector3.yAxis:Cross(horizontalLaunchVelocity)
		/ math.max(BallConfig.Radius, 1e-5) * 0.38
	ball:SetAttribute("LastFootballAction", actionName)
	ball:SetAttribute("LastFootballActionPlayerUserId", actor.Id)
	ball:SetAttribute("LastFootballActionTime", os.clock())
	-- Playing the ball is a touch: it sets last-touch for restart decisions and
	-- is the moment the offside snapshot is taken.
	notifyRulesTouch(actor, actionName)
	ball:SetAttribute("LastFootballActionIntendedReceiverUserId", actionContext and actionContext.IntendedReceiverUserId or 0)
	ball:SetAttribute("LastFootballActionIntendedReceiverName", actionContext and actionContext.IntendedReceiverName or "")
	ball:SetAttribute("LastFootballActionPassId", actionContext and actionContext.PassId or 0)
	ball:SetAttribute("LastFootballActionTargetPosition", actionContext and actionContext.TargetPosition or nil)
	ball:SetAttribute("LastFootballActionTargetKind", actionContext and actionContext.TargetKind or "")
	ball:SetAttribute("LastFootballActionEstimatedArrivalTime", actionContext and actionContext.EstimatedArrivalTime or 0)
	ball:SetAttribute("LastFootballActionGoalId", actionContext and actionContext.GoalId or "")
	--[[
		CURVE (§69). Set once, at release, and integrated by BallService while the
		ball is in flight. Explicitly cleared when there is none, so a straight
		pass can never inherit the bend of the shot before it.
	]]
	ball:SetAttribute(
		BallConfig.Flight.CurveAttributeName,
		if actionContext and typeof(actionContext.CurveAcceleration) == "Vector3"
			then actionContext.CurveAcceleration
			else Vector3.zero
	)
	ball:SetAttribute("FootballFlightComplete", false)
	ball:SetAttribute("FootballGrounded", false)
	ball:SetAttribute("FootballBounceCount", 0)
	ball:SetAttribute("FootballControlPhase", "Loose")
	return true
end

--[[
	Release the football FROM A RESTART (§28, §29).

	A restart ball is not possessed -- it is held on its spot by RestartService --
	so this deliberately does not go through the possession release path. It is
	the only way a set piece can be played, which is what makes "dribble the
	kick-off away" unrepresentable rather than merely discouraged.

	`actor` is a footballer record; a human taker and an AI taker use the same
	call, so neither gets a privileged restart.
]]
function BallControlService.ReleaseForRestart(
	ball: BasePart,
	actor,
	actionName: string,
	launchVelocity: Vector3,
	actionContext: { [string]: any }?
): boolean
	if not actor or not isFiniteVector(launchVelocity) then
		return false
	end

	--[[
		A restart ball must be genuinely free before it is struck. Nothing should
		hold it at this point, but clearing any stale controller here means a
		mid-restart possession bug can never produce a ball that is launched and
		simultaneously owned.
	]]
	if activeController then
		BallControlService.Release(ball, "restart taken")
	end
	if activeAIController then
		BallControlService.ReleaseAI(ball, "restart taken")
	end

	ball:SetAttribute("State", "Free")
	ball:SetAttribute("ControllerKind", "")
	ball:SetAttribute("ControllerFootballerId", 0)
	ball:SetAttribute("ControllerUserId", 0)

	pcall(function()
		ball:SetNetworkOwner(nil)
	end)

	ball.AssemblyLinearVelocity = launchVelocity
	local horizontalLaunchVelocity = Vector3.new(launchVelocity.X, 0, launchVelocity.Z)
	ball.AssemblyAngularVelocity = Vector3.yAxis:Cross(horizontalLaunchVelocity)
		/ math.max(BallConfig.Radius, 1e-5) * 0.38

	ball:SetAttribute("LastFootballAction", actionName)
	ball:SetAttribute("LastFootballActionPlayerUserId", actor.Id)
	ball:SetAttribute("LastFootballActionTime", os.clock())
	ball:SetAttribute("LastFootballActionIntendedReceiverUserId", actionContext and actionContext.IntendedReceiverUserId or 0)
	ball:SetAttribute("LastFootballActionIntendedReceiverName", actionContext and actionContext.IntendedReceiverName or "")
	ball:SetAttribute("LastFootballActionPassId", actionContext and actionContext.PassId or 0)
	ball:SetAttribute("LastFootballActionTargetPosition", actionContext and actionContext.TargetPosition or nil)
	ball:SetAttribute("LastFootballActionTargetKind", actionContext and actionContext.TargetKind or "")
	ball:SetAttribute("LastFootballActionEstimatedArrivalTime", actionContext and actionContext.EstimatedArrivalTime or 0)
	ball:SetAttribute("LastFootballActionGoalId", actionContext and actionContext.GoalId or "")
	--[[
		CURVE (§69). Set once, at release, and integrated by BallService while the
		ball is in flight. Explicitly cleared when there is none, so a straight
		pass can never inherit the bend of the shot before it.
	]]
	ball:SetAttribute(
		BallConfig.Flight.CurveAttributeName,
		if actionContext and typeof(actionContext.CurveAcceleration) == "Vector3"
			then actionContext.CurveAcceleration
			else Vector3.zero
	)
	ball:SetAttribute("FootballFlightComplete", false)
	ball:SetAttribute("FootballGrounded", false)
	ball:SetAttribute("FootballBounceCount", 0)
	ball:SetAttribute("FootballControlPhase", "Loose")

	--[[
		The taker cannot immediately reclaim their own restart. Real restarts
		require a second touch by someone else first; this at least prevents the
		taker passing to themselves.
	]]
	if actor.Player then
		acquisitionSuppressedUntilByPlayer[actor.Player] = {
			MinUntil = os.clock() + 0.35,
			RequiresExit = true,
			HasExited = false,
			ExitDistance = 6,
			ExpireAt = os.clock() + 3,
		}
	end

	-- Report the touch so last-touch and the offside snapshot stay correct.
	notifyRulesTouch(actor, actionName)
	return true
end

function BallControlService.GetAIPossessionStats()
	local releases = math.max(aiPossessionStats.Releases, 1)
	return {
		Acquisitions = aiPossessionStats.Acquisitions,
		Releases = aiPossessionStats.Releases,
		UnintendedReleases = aiPossessionStats.UnintendedReleases,
		DistanceExceeded = aiPossessionStats.DistanceExceeded,
		Tackled = aiPossessionStats.Tackled,
		OpponentWon = aiPossessionStats.OpponentWon,
		InvalidState = aiPossessionStats.InvalidState,
		Unexpected = aiPossessionStats.Unexpected,
		MeanControlDuration = aiPossessionStats.DurationSum / releases,
		MinLead = aiPossessionStats.CurrentMinLead,
		MaxLead = aiPossessionStats.CurrentMaxLead,
	}
end

function BallControlService.ResetAIPossessionStats()
	aiPossessionStats.Acquisitions = 0
	aiPossessionStats.Releases = 0
	aiPossessionStats.UnintendedReleases = 0
	aiPossessionStats.DistanceExceeded = 0
	aiPossessionStats.Tackled = 0
	aiPossessionStats.OpponentWon = 0
	aiPossessionStats.InvalidState = 0
	aiPossessionStats.Unexpected = 0
	aiPossessionStats.DurationSum = 0
	aiPossessionStats.CurrentMinLead = 0
	aiPossessionStats.CurrentMaxLead = 0
end

--[[
	Give `player` temporary priority to win the football back, without blocking
	anyone else from contesting it.
]]
function BallControlService.RegisterReacquisitionClaim(player: Player, duration: number, scoreBonus: number)
	if duration <= 0 or scoreBonus <= 0 then
		return
	end
	reacquisitionClaimByPlayer[player] = {
		Until = os.clock() + duration,
		ScoreBonus = scoreBonus,
	}
end

function BallControlService.SuppressAcquisition(player: Player, duration: number, exitDistance: number?)
	local now = os.clock()
	local minDuration = math.max(duration, 0)

	acquisitionSuppressedUntilByPlayer[player] = {
		MinUntil = now + minDuration,
		RequiresExit = exitDistance ~= nil and exitDistance > 0,
		ExitDistance = exitDistance,
		HasExited = false,
		ExpireAt = now + math.max(minDuration, 0.1) + 3,
	}
end

function BallControlService.ReleaseForFootballAction(
	ball: BasePart,
	player: Player,
	actionName: string,
	launchVelocity: Vector3,
	reacquireSuppression: number?,
	reacquireExitDistance: number?,
	actionContext: { [string]: any }?
): boolean
	if activeController ~= player then
		return false
	end

	if not isFiniteVector(launchVelocity) then
		return false
	end

	BallControlService.SuppressAcquisition(player, reacquireSuppression or 0.1, reacquireExitDistance)
	releaseControl(ball, string.format("%s by %s", actionName, player.Name))
	ball.AssemblyLinearVelocity = launchVelocity
	local horizontalLaunchVelocity = Vector3.new(launchVelocity.X, 0, launchVelocity.Z)
	local rollingAngularVelocity = Vector3.yAxis:Cross(horizontalLaunchVelocity) / math.max(BallConfig.Radius, 1e-5)
	-- A kicked football is not immediately in a no-slip roll. Start with moderate
	-- forward spin so ground contact can visibly finish the rolling transition.
	ball.AssemblyAngularVelocity = rollingAngularVelocity * 0.38
	ball:SetAttribute("LastFootballAction", actionName)
	ball:SetAttribute("LastFootballActionPlayerUserId", player.UserId)
	ball:SetAttribute("LastFootballActionTime", os.clock())
	local registry = getRegistry()
	notifyRulesTouch(registry and registry.GetHumanActor(player), actionName)
	ball:SetAttribute("LastFootballActionIntendedReceiverUserId", actionContext and actionContext.IntendedReceiverUserId or 0)
	ball:SetAttribute("LastFootballActionIntendedReceiverName", actionContext and actionContext.IntendedReceiverName or "")
	ball:SetAttribute("LastFootballActionPassId", actionContext and actionContext.PassId or 0)
	ball:SetAttribute("LastFootballActionTargetPosition", actionContext and actionContext.TargetPosition or nil)
	ball:SetAttribute("LastFootballActionTargetKind", actionContext and actionContext.TargetKind or "")
	ball:SetAttribute("LastFootballActionEstimatedArrivalTime", actionContext and actionContext.EstimatedArrivalTime or 0)
	ball:SetAttribute("LastFootballActionPredictedCatchTime", actionContext and actionContext.PredictedCatchTime or 0)
	ball:SetAttribute("LastFootballActionPeakSeparation", actionContext and actionContext.PeakSeparation or 0)
	ball:SetAttribute("LastFootballActionGoalId", actionContext and actionContext.GoalId or "")
	--[[
		CURVE (§69). Set once, at release, and integrated by BallService while the
		ball is in flight. Explicitly cleared when there is none, so a straight
		pass can never inherit the bend of the shot before it.
	]]
	ball:SetAttribute(
		BallConfig.Flight.CurveAttributeName,
		if actionContext and typeof(actionContext.CurveAcceleration) == "Vector3"
			then actionContext.CurveAcceleration
			else Vector3.zero
	)
	ball:SetAttribute("FootballFlightComplete", false)
	ball:SetAttribute("FootballGrounded", false)
	ball:SetAttribute("FootballBounceCount", 0)
	ball:SetAttribute("LastFootballBounceImpactSpeed", 0)
	ball:SetAttribute("LastFootballBounceReboundSpeed", 0)
	if actionName == "KnockOn" then
		ball:SetAttribute("FootballControlPhase", "KnockOnReleased")
		ball:SetAttribute("KnockOnReleasedAt", os.clock())
		ball:SetAttribute("KnockOnMaxSeparation", 0)
	else
		ball:SetAttribute("FootballControlPhase", "Loose")
	end
	return true
end

function BallControlService.Update(ball: BasePart, deltaTime: number?): boolean
	local sampledBallPosition = ball.Position
	if ball:GetAttribute("FootballControlPhase") == "KnockOnReleased" then
		local knockOnConfig = FootballActionConfig.KnockOn
		local horizontalVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
		local horizontalSpeed = horizontalVelocity.Magnitude
		local stepDeltaTime = math.max(deltaTime or BallConfig.BasicTouch.CheckInterval, 1 / 240)
		if horizontalSpeed > 0 then
			local nextSpeed = math.max(0, horizontalSpeed - knockOnConfig.ReleasedHorizontalDeceleration * stepDeltaTime)
			ball.AssemblyLinearVelocity = horizontalVelocity.Unit * nextSpeed + Vector3.new(0, ball.AssemblyLinearVelocity.Y, 0)
		end

		local initiatorUserId = ball:GetAttribute("LastFootballActionPlayerUserId")
		for _, player in Players:GetPlayers() do
			if player.UserId == initiatorUserId then
				local _character, rootPart = getCharacterParts(player)
				if rootPart then
					local separation = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude
					ball:SetAttribute("KnockOnMaxSeparation", math.max(ball:GetAttribute("KnockOnMaxSeparation") or 0, separation))
				end
				break
			end
		end
		local releasedAt = ball:GetAttribute("KnockOnReleasedAt")
		if typeof(releasedAt) == "number" and os.clock() - releasedAt >= knockOnConfig.MaximumReleasedDuration then
			ball:SetAttribute("FootballControlPhase", "Loose")
		end
	end
	local stepDeltaTime = math.max(deltaTime or BallConfig.BasicTouch.CheckInterval, 1 / 240)

	if activeAIController then
		local invalidReason = getAIControllerInvalidReason(ball)
		if invalidReason then
			BallControlService.ReleaseAI(ball, invalidReason)
		end
	end

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

	local bestCandidate = if not activeAIController then chooseBestCandidate(ball) else nil

	if bestCandidate then
		if not activeController then
			acquireControl(ball, bestCandidate.Player, bestCandidate)
		elseif bestCandidate.Player ~= activeController then
			local currentCandidate = getActiveControllerContext(activeController, ball)
			local currentScore = if currentCandidate then currentCandidate.Score else -math.huge

			if bestCandidate.Score > currentScore + controlConfig.ControlStealScoreMargin then
				acquireControl(ball, bestCandidate.Player, bestCandidate)
			end
		end
	end

	if activeAIController then
		local aiCandidate = getAIControllerContext(activeAIController, ball)
		if not aiCandidate then
			BallControlService.ReleaseAI(ball, "AI movement state invalid")
			return false
		end
		previousFreeBallPosition = nil
		applyAIPossessionControl(ball, aiCandidate, stepDeltaTime)
		setBallState(ball, CONTROL_STATE_CONTROLLED, nil, activeAIController)
		return true
	end

	if not activeController then
		previousFreeBallPosition = sampledBallPosition
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
	if activeController then
		previousFreeBallPosition = nil
	end

	local activeCandidate = getActiveControllerContext(activeController, ball)

	if not activeCandidate then
		-- Distance/speed violations are handled above with their configured grace period.
		-- Do not bypass that grace while the ownership handoff is reconciling.
		if getControllerInvalidReason(ball) then
			contextLostSince = nil
			return false
		end
		--[[
			The authoritative retention rule says this controller is still valid,
			yet no control context could be built. That is a transient -- a frame
			mid-touch, a handoff still settling -- not a loss of possession, so it
			gets a short grace instead of an immediate release. A genuine problem
			persists and still releases; getControllerInvalidReason also remains
			free to release on its own terms.
		]]
		local now = os.clock()
		contextLostSince = contextLostSince or now
		if now - contextLostSince < controlConfig.ControlContextLostGrace then
			return false
		end
		contextLostSince = nil
		releaseControl(ball, "movement state invalid")
		return false
	end

	contextLostSince = nil

	if isPlayerOwnedMode() and os.clock() < networkOwnershipHandoffUntil then
		applyCoupledPossessionControl(ball, activeCandidate, stepDeltaTime)
	elseif isPlayerOwnedMode() then
		local controlDirection = resolveControlDirection(ball, activeCandidate)
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
