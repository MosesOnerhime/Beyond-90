local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local InputController = require(script.Parent:WaitForChild("InputController"))

local MovementController = {}

local localPlayer = Players.LocalPlayer
local movementConfig = PlayerConfig.Movement
local locomotionConfig = PlayerConfig.Locomotion
local inputConfig = PlayerConfig.Input
local applyStepName = "Beyond90Locomotion"

local initialized = false
local currentHumanoid: Humanoid? = nil
local currentRootPart: BasePart? = nil
local sprintRequested = false
local sprintRemote: RemoteEvent? = nil
local characterAddedConnection: RBXScriptConnection? = nil
local humanoidDiedConnection: RBXScriptConnection? = nil
local jumpInputConnection: RBXScriptConnection? = nil
local humanoidStateConnection: RBXScriptConnection? = nil
local inputSource = "InputAction"
local locomotionBound = false
local lastDiagnosticTime = 0
local setSprintRequested: ((boolean) -> ())? = nil
local cachedBall: BasePart? = nil
local movementMode = "Normal"
local actionProfileName = ""
local actionBrakeEnd = 0
local actionLockEnd = 0
local actionExitEnd = 0
local observedPassId = 0
local observedPassAt = 0
local lastReceptionAssistDiagnostic = 0
local lastReceptionAssistPhase = ""
local receptionFacingActive = false
local receptionFacingDirection: Vector3? = nil
local receptionFacingHoldUntil = 0
local lastReceptionFacingDiagnosticAt = 0
local actionFacingDirection: Vector3? = nil
local actionFacingUntil = 0
local jumpForce: VectorForce? = nil
local jumpAttachment: Attachment? = nil
local jumpStartedAt = 0
local jumpAssistToken = 0
local jumpStartY = 0
local jumpPeakY = 0
local coastStartedAt = 0
local coastStartPosition = Vector3.zero
local coastStartSpeed = 0
local coastSource = ""
local committedPossessionDirection = Vector3.zero
local pendingPossessionDirection = Vector3.zero
local pendingPossessionTurnStartedAt = 0
local pendingPossessionTurnTouchCount = 0
local pendingPossessionTurnAngle = 0
local log: (string) -> ()
local locomotionState

local function getFootball(): BasePart?
	if cachedBall and cachedBall.Parent then
		return cachedBall
	end

	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = rootFolder and rootFolder:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)

	if ball and ball:IsA("BasePart") then
		cachedBall = ball
		return ball
	end

	cachedBall = nil
	return nil
end

local function hasLocalPossession(ball: BasePart?): boolean
	return ball ~= nil
		and ball:GetAttribute("State") == "Controlled"
		and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
end

local function clearPendingPossessionTurn()
	pendingPossessionDirection = Vector3.zero
	pendingPossessionTurnStartedAt = 0
	pendingPossessionTurnTouchCount = 0
	pendingPossessionTurnAngle = 0
	localPlayer:SetAttribute("Beyond90PendingTurnActive", false)
end

local function commitPossessionDirection(direction: Vector3, reason: string, ball: BasePart?)
	committedPossessionDirection = direction
	if pendingPossessionTurnStartedAt > 0 then
		local elapsed = os.clock() - pendingPossessionTurnStartedAt
		log(string.format(
			"[PossessionTurn] angle=%.1f pendingTime=%.2f touchId=%d commitReason=%s lead=%.2f",
			pendingPossessionTurnAngle,
			elapsed,
			ball and (ball:GetAttribute("LastLocalControlTouchCount") or 0) or 0,
			reason,
			ball and (ball:GetAttribute("ClientBallLead") or 0) or 0
		))
	end
	clearPendingPossessionTurn()
end

local function resolvePossessionTurnDirection(direction: Vector3, magnitude: number, now: number): Vector3
	local config = locomotionConfig.PossessionTurn
	local ball = getFootball()
	if not config or not config.Enabled or not hasLocalPossession(ball) then
		clearPendingPossessionTurn()
		committedPossessionDirection = direction
		return direction
	end
	if magnitude <= locomotionConfig.RawInputDeadzone then
		clearPendingPossessionTurn()
		return Vector3.zero
	end
	if locomotionState.SmoothedSpeed < config.MinimumPlayerSpeed then
		commitPossessionDirection(direction, "low-speed", ball)
		return direction
	end

	local reference = committedPossessionDirection
	if reference.Magnitude <= 0.05 then
		reference = if locomotionState.SmoothedDirection.Magnitude > 0.05
			then locomotionState.SmoothedDirection
			else direction
	end
	local angle = math.deg(math.acos(math.clamp(reference.Unit:Dot(direction.Unit), -1, 1)))
	if angle <= config.ImmediateAngleDegrees then
		commitPossessionDirection(direction, "small-correction", ball)
		return direction
	end

	local pendingChanged = pendingPossessionDirection.Magnitude <= 0.05
		or pendingPossessionDirection:Dot(direction) < 0.985
	if pendingChanged then
		pendingPossessionDirection = direction
		pendingPossessionTurnStartedAt = now
		pendingPossessionTurnTouchCount = ball and (ball:GetAttribute("LastLocalControlTouchCount") or 0) or 0
		pendingPossessionTurnAngle = angle
		localPlayer:SetAttribute("Beyond90PendingTurnActive", true)
		localPlayer:SetAttribute("Beyond90PendingTurnAngle", angle)
	end

	local elapsed = now - pendingPossessionTurnStartedAt
	local touchCount = ball and (ball:GetAttribute("LastLocalControlTouchCount") or 0) or 0
	local lead = math.abs(ball and (ball:GetAttribute("ClientBallLead") or math.huge) or math.huge)
	local relativeSpeed = ball and (ball:GetAttribute("BallRelativeSpeed") or math.huge) or math.huge
	local phase = ball and (ball:GetAttribute("DribblePhase") or "") or ""
	local minimumPreparation = config.MinimumPreparationSeconds
	local contactReady = elapsed >= minimumPreparation
		and (touchCount > pendingPossessionTurnTouchCount
			or (phase == "Collect" and lead <= config.ContactLeadDistance and relativeSpeed <= config.ContactRelativeSpeed))
	local maximumWait
	if pendingPossessionTurnAngle < config.MajorAngleDegrees then
		maximumWait = config.SmallCorrectionMaximumWaitSeconds
	elseif pendingPossessionTurnAngle < config.SevereAngleDegrees then
		maximumWait = if sprintRequested
			then config.SprintModerateMaximumWaitSeconds
			else config.JogModerateMaximumWaitSeconds
	else
		maximumWait = if sprintRequested then config.SprintMaximumWaitSeconds else config.JogMaximumWaitSeconds
	end
	if contactReady then
		commitPossessionDirection(pendingPossessionDirection, "touch-window", ball)
		return committedPossessionDirection
	elseif elapsed >= maximumWait then
		commitPossessionDirection(pendingPossessionDirection, "maximum-wait", ball)
		return committedPossessionDirection
	end

	localPlayer:SetAttribute("Beyond90PendingTurnTime", elapsed)
	return reference
end

local function clearJumpAssist()
	if jumpForce then
		jumpForce:Destroy()
		jumpForce = nil
	end

	if jumpAttachment then
		jumpAttachment:Destroy()
		jumpAttachment = nil
	end

	localPlayer:SetAttribute("Beyond90JumpAssistActive", false)
end

local function startJumpAssist(rootPart: BasePart)
	clearJumpAssist()
	jumpAssistToken += 1
	local token = jumpAssistToken
	local profile = movementConfig.JumpProfile
	local attachment = Instance.new("Attachment")
	attachment.Name = "Beyond90JumpAssistAttachment"
	attachment.Parent = rootPart
	local force = Instance.new("VectorForce")
	force.Name = "Beyond90JumpAssist"
	force.Attachment0 = attachment
	force.ApplyAtCenterOfMass = true
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = Vector3.yAxis * rootPart.AssemblyMass * Workspace.Gravity * profile.GravityCompensation
	force.Parent = rootPart
	jumpAttachment = attachment
	jumpForce = force
	jumpStartedAt = os.clock()
	jumpStartY = rootPart.Position.Y
	jumpPeakY = jumpStartY
	localPlayer:SetAttribute("Beyond90JumpAssistActive", true)

	task.delay(profile.MaxAssistDuration, function()
		if token == jumpAssistToken then
			clearJumpAssist()
			localPlayer:SetAttribute("Beyond90JumpAssistActive", false)
		end
	end)
end

local function requestJump()
	local humanoid = currentHumanoid
	local rootPart = currentRootPart

	if not movementConfig.JumpEnabled or not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	local state = humanoid:GetState()
	local airborne = state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or humanoid.FloorMaterial == Enum.Material.Air

	if airborne then
		return
	end

	startJumpAssist(rootPart)
	humanoid.Jump = true
end

locomotionState = {
	InputDirection = Vector3.zero,
	InputMagnitude = 0,
	RawDirection = Vector3.zero,
	RawMagnitude = 0,
	SmoothedDirection = Vector3.zero,
	SmoothedSpeed = 0,
	SmoothedVelocity = Vector3.zero,
	TargetSpeed = 0,
	TurnAngle = 0,
	IsSprinting = false,
	IsMoving = false,
	IsValid = false,
	InputSource = inputSource,
	MovementMode = "Normal",
	ReceptionAssistPhase = "",
	ReceptionAssistWeight = 0,
}

local function warnLog(message: string)
	warn(string.format("%s[Client][Movement] %s", GameConfig.LogPrefix, message))
end

log = function(message: string)
	print(string.format("%s[Client][Movement] %s", GameConfig.LogPrefix, message))
end

local function getTargetSpeed(): number
	if sprintRequested then
		return movementConfig.SprintSpeed
	end

	return movementConfig.BaseSpeed
end

local function getFacingDirection(): Vector3
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if rootPart and rootPart:IsA("BasePart") then
		return BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
			Vector3.new(0, 0, -1)
		)
	end

	return Vector3.new(0, 0, -1)
end

local function applyMovementSettings(humanoid: Humanoid)
	humanoid.WalkSpeed = if locomotionBound then math.max(locomotionState.SmoothedSpeed, 0) else getTargetSpeed()
	humanoid.AutoRotate = movementConfig.AutoRotate
	humanoid.UseJumpPower = true
	humanoid.JumpPower = movementConfig.JumpPower
	humanoid.JumpHeight = movementConfig.JumpHeight
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, movementConfig.JumpEnabled)

	if not movementConfig.JumpEnabled then
		humanoid.Jump = false
	end
end

local function resetLocomotionState()
	locomotionState.InputDirection = Vector3.zero
	locomotionState.InputMagnitude = 0
	locomotionState.RawDirection = Vector3.zero
	locomotionState.RawMagnitude = 0
	locomotionState.SmoothedDirection = Vector3.zero
	locomotionState.SmoothedSpeed = 0
	locomotionState.SmoothedVelocity = Vector3.zero
	locomotionState.TargetSpeed = 0
	locomotionState.TurnAngle = 0
	locomotionState.IsSprinting = false
	locomotionState.IsMoving = false
	locomotionState.IsValid = currentHumanoid ~= nil
	locomotionState.InputSource = inputSource
	locomotionState.MovementMode = "Normal"
	locomotionState.ReceptionAssistPhase = ""
	locomotionState.ReceptionAssistWeight = 0
	committedPossessionDirection = Vector3.zero
	clearPendingPossessionTurn()
end

local function getTurnSpeedFactor(currentVelocity: Vector3, targetDirection: Vector3): (number, number)
	if currentVelocity.Magnitude <= locomotionConfig.StopSpeed or targetDirection.Magnitude <= 0 then
		return 1, 0
	end

	local currentDirection = currentVelocity.Unit
	local dot = math.clamp(currentDirection:Dot(targetDirection), -1, 1)
	local turnAngle = math.deg(math.acos(dot))
	local severity = turnAngle / 180
	local loss

	if severity <= 0.5 then
		loss = (severity / 0.5) * locomotionConfig.TurnSpeedLossAt90
	else
		local alpha = (severity - 0.5) / 0.5
		loss = locomotionConfig.TurnSpeedLossAt90
			+ (locomotionConfig.TurnSpeedLossAt180 - locomotionConfig.TurnSpeedLossAt90) * alpha
	end

	return math.clamp(1 - loss, 0.25, 1), turnAngle
end

local function getVelocityChangeTime(currentVelocity: Vector3, targetVelocity: Vector3, turnAngle: number): number
	local currentSpeed = currentVelocity.Magnitude
	local targetSpeed = targetVelocity.Magnitude

	if targetSpeed <= locomotionConfig.StopSpeed then
		return if currentSpeed > movementConfig.BaseSpeed then locomotionConfig.SprintDecelerationTime else locomotionConfig.DecelerationTime
	end

	if currentSpeed <= locomotionConfig.StopSpeed then
		return if sprintRequested then locomotionConfig.SprintAccelerationTime else locomotionConfig.AccelerationTime
	end

	if turnAngle >= 135 then
		return locomotionConfig.ReverseAccelerationTime
	end

	if turnAngle >= 35 then
		return locomotionConfig.TurnAccelerationTime
	end

	if targetSpeed > currentSpeed then
		return if sprintRequested then locomotionConfig.SprintAccelerationTime else locomotionConfig.AccelerationTime
	end

	return if currentSpeed > movementConfig.BaseSpeed then locomotionConfig.SprintDecelerationTime else locomotionConfig.DecelerationTime
end

local function moveTowardVector(current: Vector3, target: Vector3, maxDelta: number): Vector3
	local delta = target - current

	if delta.Magnitude <= maxDelta then
		return target
	end

	return current + delta.Unit * maxDelta
end

local function sampleDiagnostics()
	local now = os.clock()

	if now - lastDiagnosticTime < locomotionConfig.DiagnosticInterval then
		return
	end

	lastDiagnosticTime = now
	localPlayer:SetAttribute("Beyond90RawMoveMagnitude", locomotionState.RawMagnitude)
	localPlayer:SetAttribute("Beyond90SmoothedPlayerSpeed", locomotionState.SmoothedSpeed)
	localPlayer:SetAttribute("Beyond90TurnAngle", locomotionState.TurnAngle)
	localPlayer:SetAttribute("Beyond90InputSource", locomotionState.InputSource)
	localPlayer:SetAttribute("Beyond90SprintRequested", sprintRequested)
	localPlayer:SetAttribute("Beyond90MovementMode", locomotionState.MovementMode)
	localPlayer:SetAttribute("Beyond90ReceptionAssistPhase", locomotionState.ReceptionAssistPhase)
	localPlayer:SetAttribute("Beyond90ReceptionAssistWeight", locomotionState.ReceptionAssistWeight)
end

local function finishCoast(result: string)
	if coastStartedAt <= 0 or not currentRootPart then
		return
	end
	local duration = os.clock() - coastStartedAt
	local distance = BallControlMath.GetHorizontal(currentRootPart.Position - coastStartPosition).Magnitude
	log(string.format("[Coast] source=%s distance=%.2f duration=%.2f result=%s", coastSource, distance, duration, result))
	localPlayer:SetAttribute("Beyond90LastCoastDistance", distance)
	localPlayer:SetAttribute("Beyond90LastCoastDuration", duration)
	coastStartedAt = 0
	coastStartSpeed = 0
	coastSource = ""
end

local function getActionMovement(now: number): (boolean, number, number)
	if actionProfileName == "" or now >= actionExitEnd then
		if actionProfileName ~= "" then
			actionProfileName = ""
			movementMode = "Normal"
		end
		return false, 1, 0
	end

	local profile = locomotionConfig.ActionMovement[actionProfileName]

	if not profile then
		actionProfileName = ""
		movementMode = "Normal"
		return false, 1, 0
	end

	if now < actionBrakeEnd then
		movementMode = "ActionBrake"
		return true, 0, profile.BrakeTime
	elseif now < actionLockEnd then
		movementMode = "ActionLocked"
		return true, 0, profile.BrakeTime
	end

	movementMode = "ActionExit"
	local exitAlpha = math.clamp((now - actionLockEnd) / math.max(profile.ExitDuration, 1 / 240), 0, 1)
	return true, exitAlpha, profile.BrakeTime
end

local function getReceptionAssist(
	manualDirection: Vector3,
	manualMagnitude: number,
	now: number
): (Vector3, number, string, number)
	local config = locomotionConfig.ReceptionAssist

	if not config.Enabled or not currentRootPart then
		return manualDirection, manualMagnitude, "", 0
	end

	local ball = getFootball()
	local intendedReceiver = ball and ball:GetAttribute("LastFootballActionIntendedReceiverUserId")
	local actionType = ball and ball:GetAttribute("LastFootballAction")
	local passId = ball and ball:GetAttribute("LastFootballActionPassId")
	local targetPosition = ball and ball:GetAttribute("LastFootballActionTargetPosition")
	local estimatedArrival = ball and ball:GetAttribute("LastFootballActionEstimatedArrivalTime")
	local validPass = ball
		and ball:GetAttribute("State") == "Free"
		and intendedReceiver == localPlayer.UserId
		and (actionType == "GroundPass" or actionType == "ThroughPass" or actionType == "LobPass")
		and typeof(passId) == "number"
		and passId > 0
		and typeof(targetPosition) == "Vector3"

	if not validPass then
		observedPassId = 0
		lastReceptionAssistPhase = ""
		return manualDirection, manualMagnitude, "", 0
	end

	if passId ~= observedPassId then
		observedPassId = passId
		observedPassAt = now
		receptionFacingDirection = nil
		receptionFacingActive = false
		receptionFacingHoldUntil = 0
	end

	local expiry = (if typeof(estimatedArrival) == "number" then estimatedArrival else 0) + config.ExpiryGraceTime

	if now - observedPassAt > expiry then
		return manualDirection, manualMagnitude, "", 0
	end

	local elapsed = now - observedPassAt
	local remainingTime = math.max(0.1, expiry - elapsed)
	local liveTarget = targetPosition :: Vector3
	local horizontalBallVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity)
	if horizontalBallVelocity.Magnitude > 3 then
		local distanceToPlannedTarget = BallControlMath.GetHorizontal(liveTarget - ball.Position).Magnitude
		local predictionTime = math.clamp(
			distanceToPlannedTarget / horizontalBallVelocity.Magnitude,
			0.1,
			math.min(1, remainingTime)
		)
		local verticalVelocity = ball.AssemblyLinearVelocity.Y
		local heightAboveTarget = math.max(0, ball.Position.Y - liveTarget.Y)
		local discriminant = verticalVelocity * verticalVelocity + 2 * Workspace.Gravity * heightAboveTarget
		if discriminant >= 0 then
			local landingTime = (verticalVelocity + math.sqrt(discriminant)) / Workspace.Gravity
			if landingTime > 0 then
				predictionTime = math.max(predictionTime, math.min(landingTime, remainingTime, 1))
			end
		end
		local liveProjection = ball.Position + horizontalBallVelocity * predictionTime
		local correction = BallControlMath.ClampMagnitude(
			BallControlMath.GetHorizontal(liveProjection - liveTarget),
			config.MaxLiveTargetCorrection
		)
		liveTarget += correction * config.LiveTargetWeight
	end

	local offset = BallControlMath.GetHorizontal(liveTarget - currentRootPart.Position)
	local distance = offset.Magnitude

	if distance > config.MaxDistance then
		return manualDirection, manualMagnitude, "", 0
	end

	local approachAlpha = math.clamp(
		(distance - config.StopDistance) / math.max(config.BrakeDistance - config.StopDistance, 0.01),
		0,
		1
	)
	local assistMagnitude = config.MaxMoveMagnitude * approachAlpha
	local manualOverride = math.clamp(
		(manualMagnitude - config.ManualBlendStart)
			/ math.max(config.ManualOverrideMagnitude - config.ManualBlendStart, 0.01),
		0,
		1
	)
	local assistWeight = 1 - manualOverride
	local assistDirection = if distance > 0.05 then offset.Unit else Vector3.zero
	local blended = assistDirection * assistMagnitude * assistWeight + manualDirection * manualMagnitude
	local outputMagnitude = math.clamp(blended.Magnitude, 0, 1)
	local outputDirection = if outputMagnitude > 0.05 then blended.Unit else Vector3.zero
	local phase = if distance <= config.StopDistance then "Receive" elseif distance <= config.BrakeDistance then "Brake" else "Approach"

	if phase ~= lastReceptionAssistPhase or now - lastReceptionAssistDiagnostic >= config.DiagnosticInterval then
		lastReceptionAssistDiagnostic = now
		lastReceptionAssistPhase = phase
		print(string.format(
			"%s[Client][Movement][ReceptionAssist] receiver=%s distanceToPoint=%.2f eta=%.2f assistWeight=%.2f phase=%s",
			GameConfig.LogPrefix,
			localPlayer.Name,
			distance,
			math.max(0, expiry - (now - observedPassAt)),
			assistWeight,
			phase
		))
	end

	return outputDirection, outputMagnitude, phase, assistWeight
end

local function getLooseBallAssist(manualDirection: Vector3, manualMagnitude: number): (Vector3, number, string, number)
	local config = locomotionConfig.LooseBallAssist
	local ball = getFootball()
	if not config or config.Enabled ~= true or not currentRootPart or not ball or ball:GetAttribute("State") ~= "Free" then
		return manualDirection, manualMagnitude, "", 0
	end
	if ball:GetAttribute("FootballControlPhase") == "KnockOnReleased"
		and ball:GetAttribute("LastFootballActionPlayerUserId") == localPlayer.UserId
	then
		return manualDirection, manualMagnitude, "", 0
	end
	-- Assistance refines a chase the player has chosen. It must never create
	-- movement from rest, which reads as the rolling ball pulling the footballer.
	if manualMagnitude < (config.MinimumManualMagnitude or 0.08) then
		return manualDirection, manualMagnitude, "", 0
	end

	local predictedBall = ball.Position
		+ BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity) * config.PredictionTime
	local offset = BallControlMath.GetHorizontal(predictedBall - currentRootPart.Position)
	local distance = offset.Magnitude
	if distance <= config.ContactDistance or distance > config.ActivationDistance then
		return manualDirection, manualMagnitude, "", 0
	end

	local manualOverride = math.clamp(
		(manualMagnitude - config.ManualBlendStart)
			/ math.max(config.ManualOverrideMagnitude - config.ManualBlendStart, 0.01),
		0,
		1
	)
	local approachMagnitude = config.MaximumMoveMagnitude
		* math.clamp((distance - config.ContactDistance) / math.max(config.ActivationDistance - config.ContactDistance, 0.01), 0.25, 1)
	local assistDirection = if distance > 0.05 then offset.Unit else Vector3.zero
	local blended = assistDirection * approachMagnitude * (1 - manualOverride) + manualDirection * manualMagnitude
	local magnitude = math.clamp(blended.Magnitude, 0, 1)
	return if magnitude > 0.05 then blended.Unit else Vector3.zero, magnitude, "LooseBall", 1 - manualOverride
end

local function updateReceptionFacing(deltaTime: number, phase: string)
	local ball = getFootball()
	local config = locomotionConfig.ReceptionAssist
	local shouldFaceBall = (phase == "Approach" or phase == "Brake" or phase == "Receive")
		and currentRootPart ~= nil
		and ball ~= nil
		and BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity).Magnitude >= config.FacingMinimumBallSpeed

	local now = os.clock()
	if not shouldFaceBall and not (receptionFacingActive and now < receptionFacingHoldUntil) then
		if receptionFacingActive and currentHumanoid then
			currentHumanoid.AutoRotate = movementConfig.AutoRotate
		end
		receptionFacingActive = false
		receptionFacingDirection = nil
		receptionFacingHoldUntil = 0
		return
	end

	local rootPart = currentRootPart :: BasePart
	local incomingVelocity = BallControlMath.GetHorizontal((ball :: BasePart).AssemblyLinearVelocity)
	local receiverToBall = BallControlMath.GetHorizontal((ball :: BasePart).Position - rootPart.Position)
	local sourceDirection = BallControlMath.SafeUnit(
		-incomingVelocity,
		BallControlMath.SafeUnit(receiverToBall, BallControlMath.GetHorizontal(rootPart.CFrame.LookVector))
	)
	local receiverDirection = BallControlMath.SafeUnit(receiverToBall, sourceDirection)
	-- Lock toward the source of the pass before the ball reaches the receiver. If a
	-- replicated sample is already beyond the contact plane, velocity still preserves
	-- the correct incoming side and prevents the previous 178-180 degree reversal.
	local incoming = if receiverToBall.Magnitude > 0.15 and receiverDirection:Dot(sourceDirection) > 0.15
		then BallControlMath.SafeUnit(sourceDirection:Lerp(receiverDirection, 0.35), sourceDirection)
		else sourceDirection
	if shouldFaceBall then
		receptionFacingHoldUntil = now + (config.PostContactFacingHold or 0.3)
	end
	if not receptionFacingDirection then
		receptionFacingDirection = incoming
		if now - lastReceptionFacingDiagnosticAt >= (config.FacingDiagnosticInterval or 0.75) then
			lastReceptionFacingDiagnosticAt = now
			local currentFacing = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(rootPart.CFrame.LookVector), incoming)
			local facingDot = math.clamp(currentFacing:Dot(incoming), -1, 1)
			log(string.format(
				"[ReceptionFacing] incomingVelocity=%s receiverToBall=%s desiredReceptionFacing=%s currentFacing=%s facingDot=%.3f facingAngle=%.1f",
				tostring(incomingVelocity), tostring(receiverToBall), tostring(incoming), tostring(currentFacing),
				facingDot, math.deg(math.acos(facingDot))
			))
		end
	elseif phase == "Brake" then
		local dot = math.clamp((receptionFacingDirection :: Vector3):Dot(incoming), -1, 1)
		if math.deg(math.acos(dot)) >= (config.FacingRelockAngle or 35) then
			receptionFacingDirection = BallControlMath.SafeUnit((receptionFacingDirection :: Vector3):Lerp(incoming, 0.2), incoming)
		end
	end
	incoming = receptionFacingDirection :: Vector3
	local currentFacing = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(rootPart.CFrame.LookVector), incoming)
	local alpha = 1 - math.exp(-config.FacingResponsiveness * deltaTime)
	local facing = BallControlMath.SafeUnit(currentFacing:Lerp(incoming, alpha), incoming)
	if currentHumanoid then
		currentHumanoid.AutoRotate = false
	end
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + facing, Vector3.yAxis)
	receptionFacingActive = true
end

local function updateActionFacing(deltaTime: number)
	local now = os.clock()
	local rootPart = currentRootPart
	local desired = actionFacingDirection
	if not rootPart or not desired or now >= actionFacingUntil then
		if desired and now >= actionFacingUntil then
			actionFacingDirection = nil
			actionFacingUntil = 0
			if currentHumanoid and not receptionFacingActive then
				currentHumanoid.AutoRotate = movementConfig.AutoRotate
			end
		end
		return
	end

	local current = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(rootPart.CFrame.LookVector), desired)
	local alpha = 1 - math.exp(-20 * deltaTime)
	local facing = BallControlMath.SafeUnit(current:Lerp(desired, alpha), desired)
	if currentHumanoid then
		currentHumanoid.AutoRotate = false
	end
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + facing, Vector3.yAxis)
end

local function updateLocomotion(deltaTime: number)
	local humanoid = currentHumanoid

	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local rawInput = InputController.GetInputState()
	inputSource = rawInput.Source
	local now = os.clock()

	if rawInput.SprintRequested ~= sprintRequested then
		setSprintRequested(rawInput.SprintRequested)
	end

	local inputDirection = rawInput.MoveDirection
	local inputMagnitude = rawInput.MoveMagnitude
	local rawDirection, rawMagnitude, receptionPhase, receptionWeight = getReceptionAssist(
		rawInput.MoveDirection,
		rawInput.MoveMagnitude,
		now
	)
	if receptionPhase == "" then
		rawDirection, rawMagnitude, receptionPhase, receptionWeight = getLooseBallAssist(rawDirection, rawMagnitude)
	end
	updateReceptionFacing(deltaTime, receptionPhase)
	updateActionFacing(deltaTime)
	if localPlayer:GetAttribute("Beyond90MenuOpen") == true then
		inputDirection = Vector3.zero
		inputMagnitude = 0
		rawDirection = Vector3.zero
		rawMagnitude = 0
	else
		rawDirection = resolvePossessionTurnDirection(rawDirection, rawMagnitude, now)
	end
	local actionActive, actionInputScale, actionBrakeTime = getActionMovement(now)

	if actionActive then
		rawMagnitude *= actionInputScale
		if rawMagnitude <= locomotionConfig.RawInputDeadzone then
			rawDirection = Vector3.zero
		end
	elseif receptionPhase ~= "" then
		movementMode = if receptionPhase == "LooseBall" then "LooseBallAssist" else "ReceptionAssist"
	else
		movementMode = "Normal"
	end

	local neutralCoast = inputMagnitude <= locomotionConfig.RawInputDeadzone
		and not actionActive
		and receptionPhase == ""
	if neutralCoast and coastStartedAt <= 0 and locomotionState.SmoothedSpeed > locomotionConfig.StopSpeed then
		coastStartedAt = now
		coastStartPosition = if currentRootPart then currentRootPart.Position else Vector3.zero
		coastStartSpeed = locomotionState.SmoothedSpeed
		coastSource = if locomotionState.SmoothedSpeed > movementConfig.BaseSpeed + 1 then "Sprint" else "Jog"
	end

	local targetSpeed = getTargetSpeed() * rawMagnitude
	local turnFactor, turnAngle = getTurnSpeedFactor(locomotionState.SmoothedVelocity, rawDirection)
	local targetVelocity = rawDirection * targetSpeed * turnFactor
	local changeTime = if actionActive
		then actionBrakeTime
		else getVelocityChangeTime(locomotionState.SmoothedVelocity, targetVelocity, turnAngle)
	local referenceSpeed = if neutralCoast and coastStartSpeed > 0
		then coastStartSpeed
		else math.max(locomotionState.SmoothedVelocity.Magnitude, targetVelocity.Magnitude, movementConfig.BaseSpeed)
	local maxDelta = referenceSpeed / math.max(changeTime, 1 / 240) * deltaTime
	local nextVelocity = moveTowardVector(locomotionState.SmoothedVelocity, targetVelocity, maxDelta)
	local nextSpeed = nextVelocity.Magnitude

	if nextSpeed <= locomotionConfig.StopSpeed and rawMagnitude <= 0 then
		nextVelocity = Vector3.zero
		nextSpeed = 0
	end

	local shouldMove = nextSpeed > locomotionConfig.StopSpeed
	if not neutralCoast and coastStartedAt > 0 then
		finishCoast("Interrupted")
	elseif not shouldMove and coastStartedAt > 0 then
		local ball = getFootball()
		local hasBall = ball and ball:GetAttribute("State") == "Controlled" and ball:GetAttribute("ControllerUserId") == localPlayer.UserId
		finishCoast(if hasBall then "StopTrap" else "Idle")
	end

	locomotionState.InputDirection = inputDirection
	locomotionState.InputMagnitude = inputMagnitude
	locomotionState.RawDirection = rawDirection
	locomotionState.RawMagnitude = rawMagnitude
	locomotionState.SmoothedVelocity = nextVelocity
	locomotionState.SmoothedDirection = if shouldMove then nextVelocity.Unit else Vector3.zero
	locomotionState.SmoothedSpeed = if shouldMove then nextSpeed else 0
	locomotionState.TargetSpeed = targetSpeed
	locomotionState.TurnAngle = turnAngle
	locomotionState.IsSprinting = sprintRequested
	locomotionState.IsMoving = shouldMove
	locomotionState.IsValid = true
	locomotionState.InputSource = inputSource
	locomotionState.MovementMode = movementMode
	locomotionState.ReceptionAssistPhase = receptionPhase
	locomotionState.ReceptionAssistWeight = receptionWeight

	humanoid.WalkSpeed = locomotionState.SmoothedSpeed

	if shouldMove then
		humanoid:Move(locomotionState.SmoothedDirection, false)
	else
		humanoid:Move(Vector3.zero, false)
	end
	if jumpStartedAt > 0 and currentRootPart then
		jumpPeakY = math.max(jumpPeakY, currentRootPart.Position.Y)
	end

	sampleDiagnostics()
end

local function bindLocomotion()
	if locomotionBound then
		return
	end

	locomotionBound = true
	RunService:BindToRenderStep(applyStepName, Enum.RenderPriority.Character.Value + 2, updateLocomotion)
end

local function sendSprintRequest(requested: boolean)
	if not sprintRemote then
		warnLog("Sprint remote is unavailable; local sprint prediction only")
		return
	end

	sprintRemote:FireServer(requested)
end

setSprintRequested = function(requested: boolean)
	if sprintRequested == requested then
		return
	end

	sprintRequested = requested

	if currentHumanoid and not locomotionBound then
		applyMovementSettings(currentHumanoid)
	end

	sendSprintRequest(requested)
end

local function configureCharacter(character: Model)
	jumpAssistToken += 1
	clearJumpAssist()
	sprintRequested = false
	actionProfileName = ""
	observedPassId = 0
	lastReceptionAssistPhase = ""
	jumpStartedAt = 0
	coastStartedAt = 0
	resetLocomotionState()

	if humanoidDiedConnection then
		humanoidDiedConnection:Disconnect()
		humanoidDiedConnection = nil
	end

	if humanoidStateConnection then
		humanoidStateConnection:Disconnect()
		humanoidStateConnection = nil
	end

	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid or not humanoid:IsA("Humanoid") then
		warnLog("Character missing Humanoid; movement settings were not applied")
		currentHumanoid = nil
		currentRootPart = nil
		return
	end

	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart or not rootPart:IsA("BasePart") then
		warnLog("Character missing HumanoidRootPart; movement settings were not applied")
		currentHumanoid = nil
		currentRootPart = nil
		return
	end

	currentHumanoid = humanoid
	currentRootPart = rootPart
	locomotionState.IsValid = true
	applyMovementSettings(humanoid)
	sendSprintRequest(false)

	humanoidDiedConnection = humanoid.Died:Connect(function()
		jumpAssistToken += 1
		clearJumpAssist()
		setSprintRequested(false)
		resetLocomotionState()
	end)

	humanoidStateConnection = humanoid.StateChanged:Connect(function(_, newState)
		if newState ~= Enum.HumanoidStateType.Landed and newState ~= Enum.HumanoidStateType.Running then
			return
		end

		if jumpStartedAt <= 0 or os.clock() - jumpStartedAt < 0.1 then
			return
		end

		local airTime = os.clock() - jumpStartedAt
		local peakHeight = math.max(0, jumpPeakY - jumpStartY)
		jumpAssistToken += 1
		clearJumpAssist()
		jumpStartedAt = 0
		localPlayer:SetAttribute("Beyond90JumpAirTime", airTime)
		localPlayer:SetAttribute("Beyond90JumpPeakHeight", peakHeight)
		log(string.format("Jump landed airTime=%.2f peakHeight=%.2f", airTime, peakHeight))
	end)
end

local function resolveSprintRemote()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)

	if not remotes then
		warnLog("ReplicatedStorage.Remotes was not found")
		return
	end

	local remote = remotes:WaitForChild(inputConfig.SprintRemoteName, 10)

	if not remote or not remote:IsA("RemoteEvent") then
		warnLog(string.format("%s remote was not found", inputConfig.SprintRemoteName))
		return
	end

	sprintRemote = remote
end

function MovementController.GetLocomotionState()
	return {
		InputDirection = locomotionState.InputDirection,
		InputMagnitude = locomotionState.InputMagnitude,
		RawDirection = locomotionState.RawDirection,
		RawMagnitude = locomotionState.RawMagnitude,
		SmoothedDirection = locomotionState.SmoothedDirection,
		SmoothedSpeed = locomotionState.SmoothedSpeed,
		SmoothedVelocity = locomotionState.SmoothedVelocity,
		TargetSpeed = locomotionState.TargetSpeed,
		TurnAngle = locomotionState.TurnAngle,
		IsSprinting = locomotionState.IsSprinting,
		IsMoving = locomotionState.IsMoving,
		IsValid = locomotionState.IsValid,
		InputSource = locomotionState.InputSource,
		MovementMode = locomotionState.MovementMode,
		ReceptionAssistPhase = locomotionState.ReceptionAssistPhase,
		ReceptionAssistWeight = locomotionState.ReceptionAssistWeight,
	}
end

function MovementController.FaceActionDirection(direction: Vector3, duration: number?)
	local horizontal = BallControlMath.GetHorizontal(direction)
	if horizontal.Magnitude <= 0.05 then
		return
	end
	actionFacingDirection = horizontal.Unit
	actionFacingUntil = os.clock() + math.max(duration or 0.38, 0.05)
end

function MovementController.BeginActionMovement(profileName: string): boolean
	local profile = locomotionConfig.ActionMovement[profileName]

	if not profile then
		warnLog(string.format("Unknown action movement profile: %s", profileName))
		return false
	end

	local now = os.clock()
	actionProfileName = profileName
	actionBrakeEnd = now + profile.BrakeDuration
	actionLockEnd = actionBrakeEnd + profile.LockDuration
	actionExitEnd = actionLockEnd + profile.ExitDuration
	movementMode = "ActionBrake"
	log(string.format(
		"Action movement -> %s brake=%.2f lock=%.2f exit=%.2f",
		profileName,
		profile.BrakeDuration,
		profile.LockDuration,
		profile.ExitDuration
	))
	return true
end

function MovementController.CancelActionMovement(profileName: string?)
	if profileName and actionProfileName ~= profileName then
		return
	end

	actionProfileName = ""
	actionBrakeEnd = 0
	actionLockEnd = 0
	actionExitEnd = 0
	actionFacingDirection = nil
	actionFacingUntil = 0
	movementMode = "Normal"
end

function MovementController.Initialize()
	if initialized then
		return
	end

	initialized = true
	resolveSprintRemote()
	bindLocomotion()
	jumpInputConnection = InputController.GetJumpEvent().Event:Connect(requestJump)
	log(string.format("Locomotion smoothing input source: %s", inputSource))

	characterAddedConnection = localPlayer.CharacterAdded:Connect(configureCharacter)

	if localPlayer.Character then
		configureCharacter(localPlayer.Character)
	end
end

function MovementController.Destroy()
	if not initialized then
		return
	end

	initialized = false

	if locomotionBound then
		RunService:UnbindFromRenderStep(applyStepName)
		locomotionBound = false
	end

	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end

	if humanoidDiedConnection then
		humanoidDiedConnection:Disconnect()
		humanoidDiedConnection = nil
	end

	if humanoidStateConnection then
		humanoidStateConnection:Disconnect()
		humanoidStateConnection = nil
	end

	if jumpInputConnection then
		jumpInputConnection:Disconnect()
		jumpInputConnection = nil
	end

	jumpAssistToken += 1
	clearJumpAssist()
	currentHumanoid = nil
	currentRootPart = nil
	actionProfileName = ""
	sprintRequested = false
	coastStartedAt = 0
	resetLocomotionState()
end

return MovementController
