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
local DefendingConfig = require(ReplicatedStorage.Shared.Config.DefendingConfig)
local MatchRulesConfig = require(ReplicatedStorage.Shared.Config.MatchRulesConfig)
local StaminaConfig = require(ReplicatedStorage.Shared.Config.StaminaConfig)
local AnimationConfig = require(ReplicatedStorage.Shared.Config.AnimationConfig)
local GoalkeeperConfig = require(ReplicatedStorage.Shared.Config.GoalkeeperConfig)
local AIConfig = require(ReplicatedStorage.Shared.Config.AIConfig)
local FootballerSeparation = require(ReplicatedStorage.Shared.Football.FootballerSeparation)
local RestartControl = require(ReplicatedStorage.Shared.Football.RestartControl)
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

--[[
	STAMINA (§46, §47).

	The ceiling is published by the server on the character, so the client never
	decides how fit it is -- it only reads an authoritative number. A tired
	footballer's SPRINT is capped; jogging is untouched, so fatigue slows a
	player down without taking the game away from them.
]]
local function getStaminaSprintCeiling(): number
	if StaminaConfig.Enabled ~= true then
		return movementConfig.SprintSpeed
	end
	local character = currentHumanoid and currentHumanoid.Parent
	local ceiling = character and character:GetAttribute(StaminaConfig.Attributes.SprintCeiling)
	if typeof(ceiling) ~= "number" then
		return movementConfig.SprintSpeed
	end
	return math.clamp(ceiling, movementConfig.BaseSpeed, movementConfig.SprintSpeed)
end

local function getTargetSpeed(): number
	if sprintRequested then
		return getStaminaSprintCeiling()
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

--[[
	Is another system currently turning the body? (§73)

	True while AnimationController is driving a transition's yaw. Nothing here may
	write orientation during that window, or the two fight and the turn stutters.
]]
local function animationOwnsRotation(): boolean
	return localPlayer:GetAttribute(AnimationConfig.RotationAuthorityAttribute)
		== AnimationConfig.RotationAuthorityAnimation
end

local function applyMovementSettings(humanoid: Humanoid)
	humanoid.WalkSpeed = if locomotionBound then math.max(locomotionState.SmoothedSpeed, 0) else getTargetSpeed()
	-- Never re-enable AutoRotate underneath a driven turn (§73).
	if not animationOwnsRotation() then
		humanoid.AutoRotate = movementConfig.AutoRotate
	end
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
		--[[
			Trust the ball more the closer it gets. See the note on
			LiveTargetWeight: the planned target is the better guide while the
			pass is in flight, and a fiction by the time it arrives.
		]]
		local ballDistance = BallControlMath.GetHorizontal(
			ball.Position - currentRootPart.Position
		).Magnitude
		local proximity = 1 - math.clamp(
			ballDistance / math.max(config.LiveTargetFullTrustDistance, 0.01),
			0,
			1
		)
		local liveWeight = config.LiveTargetWeight
			+ (1 - config.LiveTargetWeight) * proximity
		liveTarget += correction * liveWeight
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
	local assistDirection = if distance > 0.05 then offset.Unit else Vector3.zero

	--[[
		INPUT ONLY CANCELS THE ASSIST TO THE EXTENT IT DISAGREES WITH IT.

		Manual input used to switch the assist off outright, on magnitude alone.
		That is the correct instinct applied to the wrong quantity: it meant a
		player RUNNING AT THE INCOMING PASS -- the clearest possible statement of
		"I am receiving this" -- cancelled the very help that would have put him
		on the ball. The logs show it flicking between full assist and none as
		the player steered:

			[ReceptionAssist] assistWeight=1.00 phase=Approach
			[ReceptionAssist] assistWeight=0.00 phase=Brake

		Agency is about DIRECTION, not effort. Running toward the ball agrees
		with the assist and now keeps it; running across or away from it
		disagrees and still cancels it completely, so declining a pass, dummying
		it or peeling off to make space all behave exactly as before.

		This is assistance executing an intent the player has already expressed,
		which is the line AGENTS.md 23 draws -- not the game choosing to receive
		on their behalf.
	]]
	local disagreement = 1
	if manualMagnitude > 0.05 and assistDirection.Magnitude > 0.05 then
		local alignment = math.clamp(manualDirection.Unit:Dot(assistDirection), -1, 1)
		disagreement = math.clamp((1 - alignment) * 0.5, 0, 1)
	end
	local assistWeight = 1 - manualOverride * disagreement
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

--[[
	PRESS ASSISTANCE (§41, §42).

	DefendingController registers a provider rather than being required here,
	which keeps the dependency one-way: defending knows about movement, movement
	does not know about defending.
]]
local pressStateProvider: (() -> any)? = nil

function MovementController.SetPressStateProvider(provider: (() -> any)?)
	pressStateProvider = provider
end

--[[
	Goalkeeper positioning assistance.

	Registered the same way the press assist is, because it is the same kind of
	thing: a bounded correction toward a target the player has not contradicted.
	Keeping it in the ordinary locomotion pipeline rather than in a separate
	goalkeeper movement path means a keeper accelerates, turns and stops with the
	weight every other footballer has.
]]
local goalkeeperStateProvider: (() -> any)? = nil

function MovementController.SetGoalkeeperStateProvider(provider: (() -> any)?)
	goalkeeperStateProvider = provider
end

local function getGoalkeeperAssist(manualDirection: Vector3, manualMagnitude: number): (Vector3, number, boolean)
	if not goalkeeperStateProvider or not currentRootPart then
		return manualDirection, manualMagnitude, false
	end
	local state = goalkeeperStateProvider()
	if not state then
		return manualDirection, manualMagnitude, false
	end
	--[[
		A committed dive is server-driven physical movement, and a held ball is
		stationary by definition. Steering during either would fight the server
		for control of the same character.
	]]
	if state.Frozen then
		return Vector3.zero, 0, true
	end
	--[[
		No target: a keeper is not assisted anywhere any more (see
		GoalkeeperConfig.Human). This state exists purely so the caller knows the
		local footballer is a keeper and suppresses the outfield press and
		loose-ball assists, which would otherwise drag them out of their goal.
	]]
	return manualDirection, manualMagnitude, false
end

--[[
	Steer toward the press target while V is held.

	Bounded exactly like reception assistance: capped magnitude, and manual input
	blends it out entirely, so the player can always pull out of an approach they
	do not want. Nothing here raises the speed ceiling -- the result feeds the
	ordinary locomotion model, so acceleration, turning, injury and stamina all
	still apply.
]]
local function getPressAssist(manualDirection: Vector3, manualMagnitude: number): (Vector3, number, boolean)
	if not pressStateProvider or not currentRootPart then
		return manualDirection, manualMagnitude, false
	end
	local state = pressStateProvider()
	if not state or not state.TargetPosition then
		return manualDirection, manualMagnitude, false
	end
	local config = state.Config

	local offset = BallControlMath.GetHorizontal(state.TargetPosition - currentRootPart.Position)
	local distance = offset.Magnitude
	if distance <= config.HoldDistance then
		--[[
			Close enough. The assist deliberately stops driving here so the player
			is never pushed into the carrier -- arriving is the assist's job, the
			last two studs are the player's.
		]]
		return manualDirection, manualMagnitude, true
	end

	local manualOverride = math.clamp(
		manualMagnitude / math.max(config.ManualOverrideMagnitude, 0.01),
		0,
		1
	)

	--[[
		Ease off approaching the hold distance so the arrival is a jockey rather
		than a collision -- but only once the gap is genuinely closing. While the
		press is still a sprint the magnitude must be full, or the movement cap
		holds the footballer below the sprint speed it just requested (§37).
	]]
	--[[
		HOW HARD THE DEFENDER IS ALLOWED TO GO.

		Three cases, and they are the three defensive verbs:

		  still closing   -> full magnitude, or the movement cap holds the
		                     footballer below the sprint speed just requested.
		  DASH & PRESSURE -> full commitment; the player asked for it.
		  MATCH UP        -> held below full on purpose. A defender at top speed
		                     cannot change direction, and being able to change
		                     direction is the entire point of jockeying. This cap
		                     is what makes containment feel like balance rather
		                     than like running at someone.
	]]
	local maximumMagnitude
	if state.ShouldSprint and not state.Containing then
		maximumMagnitude = 1
	elseif state.Containing and state.Dashing and config.Dash.Enabled == true then
		maximumMagnitude = config.Dash.MaximumMoveMagnitude
	elseif state.Containing and config.Contain.Enabled == true then
		maximumMagnitude = config.Contain.MaximumMoveMagnitude
	else
		maximumMagnitude = config.MaximumMoveMagnitude
	end
	local approach = maximumMagnitude * math.clamp(
		(distance - config.HoldDistance) / math.max(config.SlowDistance - config.HoldDistance, 0.01),
		0.3,
		1
	)
	local assistDirection = offset.Unit

	--[[
		NEVER DRIVE INTO THE CARRIER'S BODY.

		Two footballers occupying the same space is not a football interaction --
		it reads as a physics failure, and it is what the containment standoff is
		there to prevent. The standoff handles the target; this handles the case
		the target cannot, which is the carrier running into the defender.

		Only the component of the assist pointing INTO them is removed. The
		defender can still slide across their line, which is exactly what a
		contained defender should be doing anyway.
	]]
	local carrierPosition = state.CarrierPosition
	if carrierPosition then
		local toCarrier = BallControlMath.GetHorizontal(carrierPosition - currentRootPart.Position)
		local gap = toCarrier.Magnitude
		local bodyGap = config.Contain.MinimumBodyGap
		if gap > 0.01 and gap < bodyGap then
			local into = toCarrier.Unit
			local closing = assistDirection:Dot(into)
			if closing > 0 then
				local corrected = assistDirection - into * closing
				assistDirection = if corrected.Magnitude > 0.01
					then corrected.Unit
					else Vector3.zero
			end
		end
	end

	local blended = assistDirection * approach * (1 - manualOverride) + manualDirection * manualMagnitude
	local magnitude = math.clamp(blended.Magnitude, 0, 1)
	if magnitude <= 0.05 then
		return Vector3.zero, 0, true
	end
	return blended.Unit, magnitude, true
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

	--[[
		A driven transition owns orientation while it runs (§73). Reception facing
		steps aside rather than lerping the body back toward the ball mid-turn.
	]]
	if animationOwnsRotation() then
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

--[[
	A KEEPER FACES THE BALL. THEY DO NOT TURN ROUND TO WALK BACKWARDS.

	Without this the goalkeeper is steered by ordinary locomotion, which rotates
	the body into whatever direction the player is travelling. Pressing back to
	drop toward the line spun the keeper 180 degrees and ran them at their own
	goal facing away from the play, and pressing left or right turned them side
	on -- both of which are the opposite of what a goalkeeper does. It also meant
	the directional locomotion set never had anything to choose from: every
	movement was "forward" once the body had turned to match it.

	Pinning facing to the ball fixes the animation as a consequence rather than
	as a separate change. The locomotion set already picks its clip from the
	angle between facing and travel, so a keeper backing off now genuinely IS
	moving backwards and gets B90_LOC_OffBall_Jog_Backward, and stepping across
	their goal gets the left/right clips. Nothing here selects an animation; it
	only stops the body lying about which way it is going.

	Precedence, in the order these run: a driven turn owns rotation outright, a
	reception or an action (a throw) aims the body deliberately, and this only
	takes over when none of those are speaking. While HOLDING the ball the
	keeper is walking out to distribute, which is ordinary footballer movement,
	so facing is handed back to normal locomotion.
]]
--[[
	Everyone else on the pitch, for body-overlap avoidance.

	Refilled in place each frame rather than reallocated -- this runs on the
	client every frame, and section 10 is explicit about not allocating tables
	per frame in a render path. AI footballers live in the shared folder; other
	humans come from the player list, which is the same pair of sources
	DefendingController already walks to find a carrier.
]]
local separationNeighbours: { { Id: number, Position: Vector3 } } = {}

--[[
	THE MAN YOU ARE PRESSING IS NOT AN OBSTACLE.

	Separation exists to stop bodies merging, and it does that by steering away
	from anyone close. A defender closing a carrier down is DELIBERATELY getting
	close -- so separation was pushing them off the one player they were trying
	to reach, and the last few studs of a press could never be closed. It shows
	up in the log as the tackle being refused on distance rather than the press
	failing outright:

		[Defending] [Tackle] runo -> AWAY_AI_2 rejected=ball-out-of-reach

	Steering assistance must not fight a decision the player has made. Pressing
	is such a decision -- the player is holding the key -- so the target of the
	press is excluded from separation for as long as it is held. Everyone else
	on the pitch still counts, including the carrier's team-mates.
]]
local function getPressTargetId(): number?
	if not pressStateProvider then
		return nil
	end
	local state = pressStateProvider()
	if not state then
		return nil
	end
	return if typeof(state.CarrierId) == "number" then state.CarrierId else nil
end

local function getSeparationNeighbours(): { { Id: number, Position: Vector3 } }
	table.clear(separationNeighbours)
	if PlayerConfig.Separation.Enabled ~= true then
		return separationNeighbours
	end
	local pressTargetId = getPressTargetId()

	local container = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local folder = container and container:FindFirstChild("Footballers")
	if folder then
		for _, model in folder:GetChildren() do
			local part = model:FindFirstChild("HumanoidRootPart")
			if part and part:IsA("BasePart") then
				local id = model:GetAttribute(AIConfig.Attributes.Id)
				local numeric = if typeof(id) == "number" then id else 0
				if numeric ~= pressTargetId then
					table.insert(separationNeighbours, { Id = numeric, Position = part.Position })
				end
			end
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local part = character and character:FindFirstChild("HumanoidRootPart")
		if part and part:IsA("BasePart") and player.UserId ~= pressTargetId then
			table.insert(separationNeighbours, { Id = player.UserId, Position = part.Position })
		end
	end
	return separationNeighbours
end

local goalkeeperFacingActive = false

--[[
	THE KEEPER GOES TO GROUND.

	The dive clips are authored IN PLACE: they put the keeper into a dive shape
	but translate the rig neither sideways nor downward. The sideways half is
	already covered -- the server-approved launch drives the humanoid, which is
	what actually carries the keeper across the goal -- but nothing was tipping
	the body over, so a diving keeper stayed bolt upright and slid.

	This is the tipping. The body rolls about its own travel axis from upright to
	very nearly flat over the first part of the dive and stays there until the
	dive ends, which is what turns a sideways slide into a save. It is rotation
	only: height comes from the lift impulse and gravity, exactly as before.

	Same mechanism the facing driver above uses -- AutoRotate off, write the
	CFrame -- because a Humanoid will right itself every frame otherwise.
]]
--[[
	THE CLIP ALREADY LAYS THE KEEPER DOWN. THE CODE MUST NOT DO IT AGAIN.

	Measured directly off the authored dive clips
	(`KeyframeSequenceProvider:GetKeyframeSequenceAsync`):

		DiveLeft    maxTorsoRot=107.9 deg   rootTranslations=0
		DiveRight   maxTorsoRot= 97.6 deg   rootTranslations=0
		GetUpLeft   maxTorsoRot=103.2 deg   rootTranslations=0
		GetUpRight  maxTorsoRot= 87.8 deg   rootTranslations=0

	and across DiveLeft's own timeline the torso goes 17.7 -> 108 degrees:

		t=0.00s   17.7      t=0.80s   54.3      t=1.60s  102.5
		t=0.27s   23.4      t=1.07s   86.7      t=1.87s  107.9

	The animator's note that "the animations have no x or y movements" was about
	TRANSLATION, and it is true -- rootTranslations is 0 for all four. It is not
	true of ROTATION: the clip tips the keeper over on its own, and the get-up
	clip stands him back up on its own.

	This code was rolling the ROOT a further 78 degrees on top, and unwinding it
	separately on recovery. About 178 degrees of tipping for one dive, applied
	twice and taken away twice. That is the reported "rolls around".

	So the roll is gone. The clip owns the body's ATTITUDE; this code owns only
	its TRANSLATION and its YAW. Set this above zero only if the clips are ever
	replaced with ones that do not carry the fall themselves -- and measure them
	first rather than assuming.
]]
local DIVE_TILT_DEGREES = 0
local DIVE_TILT_RISE_SECONDS = 0.2
-- The roll currently applied to the body, in radians. Signed: negative rolls
-- the keeper to their right.
local currentDiveRoll = 0
--[[
	THE DIVE'S FRAME, LATCHED AT THE START.

	Facing and roll direction used to be recomputed EVERY FRAME from
	`rootPart.CFrame` -- the very CFrame this function is rolling. That is a
	feedback loop: as the body tips past vertical the horizontal projection of
	its RightVector shrinks and eventually flips sign, so the roll direction
	flipped with it and the keeper rocked back and forth instead of falling one
	way. The runtime log caught the same loop in the animation, which picks its
	clip from the same vector:

		KeeperDiveLeft  speed=0.2
		KeeperDiveRight speed=16.2
		KeeperDiveLeft  speed=12.8

	-- three clip changes inside one dive. Rocking in place is exactly what that
	looks like on screen.

	A dive commits, so its frame is decided once from the UPRIGHT body at the
	instant the dive is approved, and nothing during the dive may revise it.
]]
--[[
	Whether this dive's upward impulse has been given. One dive, one leap: gravity
	owns the arc after that, so re-applying it every frame would hold the keeper
	in the air instead of letting him fall.
]]
--[[
	The attribute AnimationController publishes when the dive clip starts.

	Resolved through the config, with the literal as a fallback, because
	`GetAttribute(nil)` is a runtime error -- and a config that has not reached
	the running place yet (a Rojo sync that dropped, a stale Studio session) must
	degrade to "launch immediately", not to a crash in the middle of a dive.
]]
local DIVE_STARTED_ATTRIBUTE = AnimationConfig.Goalkeeper.DiveStartedAttribute
	or "Beyond90KeeperDiveClipStarted"

--[[
	THE KEEPER'S HEIGHT THROUGH THE DIVE, DRIVEN BY CODE.

	Held as an OFFSET from whatever hip height the character was calibrated to
	(PlayerService measures that per rig at spawn), so this never has to know
	the rig's proportions and always restores exactly what it borrowed.

	The humanoid is remembered alongside the baseline: a character that
	respawns mid-dive would otherwise leave a stale baseline behind and the
	next dive would restore the OLD rig's hip height onto the new one.
]]
local diveHipBaseline: number? = nil
local diveHipHumanoid: Humanoid? = nil

--[[
	Bound ONCE, when the character is bound, and never re-read afterwards.

	It used to be captured lazily on the first frame that needed it, which is a
	feedback loop waiting to happen: any path that reached the capture while an
	offset was already applied recorded the OFFSET height as the new baseline,
	and the next dive stacked on top of that. The runtime measured the result --

		[Grounding] state=jog hipHeight=9.602 ... contactMax=18.129

	against a calibrated 2.950, with the keeper mid-get-up. That is the reported
	"shoots up just after getting to the floor": each dive was adding roughly its
	own apex to the resting height of the character.

	A value read from the thing you are writing to cannot be a baseline. This one
	is captured before anything can have moved it, so it stays true however the
	dive ends.
]]
local function bindDiveHipBaseline(humanoid: Humanoid?)
	diveHipHumanoid = humanoid
	diveHipBaseline = if humanoid then humanoid.HipHeight else nil
end

local function applyDiveHipOffset(humanoid: Humanoid?, offset: number)
	if not humanoid or humanoid ~= diveHipHumanoid or not diveHipBaseline then
		return
	end
	-- Clamped above zero: a hip height at or below the floor drops the root
	-- through the pitch rather than laying the keeper on it.
	humanoid.HipHeight = math.max(diveHipBaseline + offset, 0.05)
end

--[[
	Puts the height back. Deliberately KEEPS the binding: the baseline belongs to
	the character, not to the dive, and clearing it here is what would let a
	later capture read an offset value.
]]
local function releaseDiveHipOffset()
	if diveHipHumanoid and diveHipBaseline then
		diveHipHumanoid.HipHeight = diveHipBaseline
	end
end

--[[
	Height offset for a point in the dive, 0 at launch through 1 at the end.

	Rise then fall, with the fall accelerating -- the shape gravity would have
	produced, except that it is allowed to finish BELOW where it started, which
	is the part a thrown body cannot do.
]]
local function diveHipOffsetAt(progress: number): number
	local arc = GoalkeeperConfig.Dive.DiveArc
	local apexAt = math.clamp(arc.ApexFraction, 0.05, 0.9)
	local landAt = math.clamp(arc.LandFraction or 1, apexAt + 0.05, 1)
	if progress <= apexAt then
		local t = progress / apexAt
		return arc.LeapApexStuds * (1 - (1 - t) * (1 - t))
	end
	if progress >= landAt then
		-- Down, and staying down until the get-up takes over.
		return -arc.GroundDropStuds
	end
	--[[
		Smoothstep: zero rate leaving the apex, zero rate MEETING THE GROUND.

		The fall was `t * t`, whose rate is greatest at the end -- so the keeper
		was descending fastest at the exact frame the descent stopped, and the
		get-up began from rest. That discontinuity in vertical rate is what reads
		as a jolt on landing. Trading a little of the accelerating-fall feel for
		a continuous one is the right way round for an arcade football game.
	]]
	local u = (progress - apexAt) / (landAt - apexAt)
	local eased = u * u * (3 - 2 * u)
	return arc.LeapApexStuds + (-arc.GroundDropStuds - arc.LeapApexStuds) * eased
end
local diveFacing: Vector3? = nil
local diveSign = 1

local diveTiltActive = false
--[[
	THE KEEPER HAS TO GET BACK UP.

	The first version tipped the body over and then simply stopped writing the
	CFrame when the dive ended -- on the assumption that the Humanoid would
	right itself. IT DOES NOT. `AutoRotate` governs YAW only; nothing in a
	Humanoid returns a rolled root to upright. So the keeper was left lying at
	78 degrees for the rest of the match, and a tipped Humanoid reports
	`FallingDown`, which `isAirborne` treats as airborne. That is the reported
	glitch, and the log shows it as a flip-flop that never stops:

		State -> KeeperIdle        speed=2.2
		State -> AirborneFallback  speed=2.7
		State -> KeeperIdle        speed=2.3
		State -> AirborneFallback  speed=3.1

	-- alternating every ~0.3s for eleven seconds after a single dive, with the
	body sliding (`[Coast] source=Jog distance=17.32`) because a keeper on its
	side has no footing.

	So the roll is a full arc: down over the dive, then back up over a recovery.
	Rotation the code applies, the code must also take away.
]]
local diveRecoveryFrom = 0
local diveRecoveryUntil = 0
-- While this is in the future the keeper is getting to their feet and does not
-- steer. See GoalkeeperConfig.Dive.StandUpInputLockSeconds.
local diveInputLockUntil = 0
local diveRecoveryFacing: Vector3? = nil

local function updateGoalkeeperDiveTilt(): boolean
	local rootPart = currentRootPart
	local model = localPlayer.Character
	local diving = model ~= nil
		and model:GetAttribute(GoalkeeperConfig.Attributes.Diving) == true

	if not rootPart or not diving then
		if diveTiltActive then
			-- The dive just ended. Start standing up rather than releasing the
			-- body at whatever angle it happened to be lying at.
			diveTiltActive = false
			diveFacing = nil
			--[[
				STOP THE BODY THE DIVE LAUNCHED.

				The dive drove the humanoid at `LowDiveSpeed`, and when it ended
				nothing took that momentum away -- the assembly kept coasting
				while the get-up clip played over the top. Measured:

					KeeperGetUpLeft  speed=48.7   [Coast] slid 31.4 studs
					KeeperGetUpLeft  speed=48.2   [Coast] slid 32.4 studs

				-- a keeper sliding thirty studs across his own box, animated as
				standing up. That is the reported "glitches backwards after
				diving": the body is still travelling in the dive's direction
				while the clip says the dive is over.

				Zeroing the HORIZONTAL component only, so a keeper still in the
				air finishes falling rather than being frozen mid-drop. Written
				on the OWNING CLIENT, which is this one -- section 32's rule is
				that the SERVER may not write to a client-owned assembly; the
				owner writing its own is exactly how the launch was applied in
				the first place.
			]]
			if rootPart then
				local carried = rootPart.AssemblyLinearVelocity
				rootPart.AssemblyLinearVelocity = Vector3.new(0, carried.Y, 0)
			end
			--[[
				Only worth standing up a body that still exists. A character
				removed mid-dive reaches here with no root, and the next one
				spawns upright anyway.
			]]
			if rootPart then
				--[[
					THE GET-UP CLIP DECIDES HOW LONG THIS TAKES.

					AnimationController publishes when the clip it just started
					will finish; the roll unwinds across exactly that window and
					input returns at the same instant, so the body is upright
					precisely when the animation says the keeper is standing.

					This replaces two independent constants that could only ever
					be approximately right. They are kept as the FALLBACK for the
					case where no get-up clip is loaded -- a missing asset should
					degrade to the old behaviour, not strand the keeper on the
					floor.

					Read a frame late by design: the animation controller sets the
					attribute on the same edge this branch fires, and whichever
					runs second wins. The `refreshDiveRecoveryFromClip` call in
					the recovery loop below picks it up either way.
				]]
				local dive = GoalkeeperConfig.Dive
				diveRecoveryFrom = currentDiveRoll
				diveRecoveryUntil = os.clock() + dive.StandUpSeconds
				diveInputLockUntil = os.clock() + dive.StandUpInputLockSeconds
				diveRecoveryFacing = BallControlMath.GetHorizontal(rootPart.CFrame.LookVector)
			else
				diveRecoveryUntil = 0
				currentDiveRoll = 0
				diveRecoveryFacing = nil
				releaseDiveHipOffset()
			end
		end

		--[[
			A borrowed hip height must never outlive the dive that borrowed it.

			The paths above cover the ordinary dive and the ordinary get-up, but
			a character removed or respawned part-way through reaches neither.
			Left held, the next life would spawn with a keeper's lying-down hip
			height and stand knee-deep in the pitch, so anything still holding
			the borrow once the keeper is neither diving nor recovering gives it
			straight back.
		]]
		if not diveTiltActive and diveRecoveryUntil <= 0 then
			releaseDiveHipOffset()
		end

		--[[
			STANDING UP. Unwind whatever roll is left, then hand the body back.

			The window comes from the get-up CLIP when one is playing. Adopted
			here rather than at the dive edge because the animation controller
			may publish the attribute either just before or just after this runs
			-- reading it every frame of the recovery removes the ordering
			question entirely.
		]]
		if rootPart and diveRecoveryUntil > 0 then
			local publishedEnd = model and model:GetAttribute(AnimationConfig.Goalkeeper.GetUpAttribute)
			if typeof(publishedEnd) == "number" and publishedEnd > diveRecoveryUntil then
				--[[
					The clip runs longer than the fallback constant, so the roll
					and the input lock both stretch to match it. Only ever
					extended, never shortened: a keeper standing up before the
					animation has them upright is the exact glitch this replaces.
				]]
				diveRecoveryUntil = publishedEnd
				diveInputLockUntil = publishedEnd
			end
			local remaining = diveRecoveryUntil - os.clock()
			if remaining <= 0 then
				diveRecoveryUntil = 0
				currentDiveRoll = 0
				diveRecoveryFacing = nil
				-- Give the calibrated hip height back exactly as it was found.
				releaseDiveHipOffset()
				--[[
					Upright again, so put the body back on its feet explicitly.
					A Humanoid that entered FallingDown while tipped stays there
					until told otherwise, and `GettingUp` is the state that ends
					it.
				]]
				if currentHumanoid then
					if currentHumanoid:GetState() == Enum.HumanoidStateType.FallingDown then
						currentHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
					end
					if not receptionFacingActive and not animationOwnsRotation() then
						currentHumanoid.AutoRotate = movementConfig.AutoRotate
					end
				end
			else
				local progress = 1 - remaining / math.max(GoalkeeperConfig.Dive.StandUpSeconds, 0.01)
				currentDiveRoll = diveRecoveryFrom * (1 - progress * progress)
				--[[
					AND BACK UP. The dive left the keeper on the floor; the
					get-up is what returns him to standing height, over the same
					window the get-up CLIP owns (adopted just above), so the body
					arrives upright on the frame the animation shows him upright.

					Slow at first, then quicker -- a keeper gathers himself and
					then pushes, rather than rising at a constant rate.
				]]
				applyDiveHipOffset(
					currentHumanoid,
					-GoalkeeperConfig.Dive.DiveArc.GroundDropStuds * (1 - progress * progress)
				)
				local facing = BallControlMath.SafeUnit(
					diveRecoveryFacing or BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
					Vector3.zAxis
				)
				local upright = CFrame.lookAt(rootPart.Position, rootPart.Position + facing, Vector3.yAxis)
				if currentHumanoid then
					currentHumanoid.AutoRotate = false
				end
				rootPart.CFrame = upright * CFrame.fromAxisAngle(Vector3.zAxis, currentDiveRoll)
				--[[
					HELD AT ZERO FOR THE WHOLE RECOVERY, NOT JUST AT THE END OF
					THE DIVE.

					Zeroing once when the dive finished was not enough, and the
					log says exactly why: the velocity went to zero and then came
					BACK.

						KeeperGetUpLeft  speed= 0.0   <- the one-shot zero worked
						KeeperIdle       speed=30.5   <- 1.2s later, backwards

					The line above writes `rootPart.CFrame` on EVERY recovery
					frame to unwind a 78 degree roll, and a per-frame CFrame
					write is integrated by the engine as motion -- the body is
					re-accelerated by its own stand-up. That is the reported
					"moves backwards weirdly and rolls around": the roll is
					generating the movement.

					Rotation the code applies, the code must take away -- and
					while it is applying it, it must also keep taking away the
					velocity that applying it creates. Vertical is left alone so
					a body still settling finishes falling.
				]]
				local settling = rootPart.AssemblyLinearVelocity
				rootPart.AssemblyLinearVelocity = Vector3.new(0, settling.Y, 0)
				return true
			end
		end
		return false
	end

	--[[
		THE BODY'S ORIENTATION WAITS FOR THE CLIP, exactly as its launch does.

		The launch was gated on `DiveStartedAttribute`, but this was not -- and
		this squares the keeper to `Pitchward` by writing `rootPart.CFrame`. A
		keeper may sit up to `MaximumFacingArcDegrees` off that line, so on the
		`Diving` edge the body snapped through as much as 45 degrees of yaw
		before the dive was drawn; and because a per-frame CFrame write is
		integrated by the engine as motion, the snap carried a small translation
		with it. Measured at 39ms of it in one dive:

			00:38:29.060  server approves
			00:38:29.099  KeeperDiveLeft starts

		That is the residual "moves slightly before the animation plays". Both
		halves of the body's commitment now begin on the same frame as the clip.
	]]
	if model:GetAttribute(DIVE_STARTED_ATTRIBUTE) == nil then
		return false
	end

	local velocity = model:GetAttribute(GoalkeeperConfig.Attributes.DiveVelocity)
	if typeof(velocity) ~= "Vector3" then
		return false
	end
	local travel = BallControlMath.GetHorizontal(velocity)
	if travel.Magnitude < 0.05 then
		-- A dive with no sideways component is a keeper going straight down on
		-- the ball; there is no axis to roll about, so leave them upright.
		return false
	end
	local direction = travel.Unit

	--[[
		How far through the tip we are. Taken from the dive's own start stamp so
		the roll is tied to the approved dive rather than to however many frames
		this controller happened to run.
	]]
	local startedAt = model:GetAttribute("Beyond90GoalkeeperDiveAt")
	local elapsed = if typeof(startedAt) == "number" then os.clock() - startedAt else DIVE_TILT_RISE_SECONDS
	local progress = math.clamp(elapsed / DIVE_TILT_RISE_SECONDS, 0, 1)
	-- Ease out: the keeper leaves their feet quickly and settles flat.
	local eased = 1 - (1 - progress) * (1 - progress)
	local roll = math.rad(DIVE_TILT_DEGREES) * eased

	--[[
		Roll about the direction of travel, keeping the keeper facing the pitch.
		Rolling about the travel axis rather than the body's own forward axis is
		what makes a leftward dive fall to the keeper's left and a rightward one
		to their right, without needing to know which clip is playing.
	]]
	--[[
		LATCHED ON THE FIRST FRAME OF THE DIVE, then reused unchanged.

		Reading facing from `rootPart.CFrame` every frame fed the roll back into
		its own input -- see `diveFacing` above for what that produced. The body
		is upright only on this first frame, so this is the only moment the
		question can be answered honestly.
	]]
	if not diveFacing then
		--[[
			THE KEEPER SQUARES UP TO DIVE.

			Taking facing from the body meant diving wherever the body happened
			to be pointing -- and a keeper may turn up to
			`MaximumFacingArcDegrees` (90) off the pitch, so at the edge of that
			arc a ball in front of goal is BEHIND them. The runtime measured
			exactly that, three dives in one session:

				launchWorld= 90.0  frame= -1.3  ->  +91.3  lateral, fine
				launchWorld=-90.9  frame= 90.6  -> +178.5  BEHIND the keeper
				launchWorld= 89.4  frame=-75.2  -> +164.6  BEHIND the keeper

			and the body did what it was told -- travelling backwards at 17-19
			studs/s with near-zero lateral, which is the reported "keeper moves
			backwards instead of sideways". No clip choice can fix that; the
			body genuinely was going backwards.

			So the dive squares the keeper to `Pitchward` -- out of their own
			goal, the published centre of their turn arc, the same value the
			animation picks its side from. A shot-stopping dive is across the
			goal, so measured from there it is lateral by construction: the
			left/right clips mean what they say, and the body travels sideways.

			This is section 32's split, not an exception: the SERVER still
			decides whether the dive happens and in which world direction. This
			only orients the body it gave to the clip that plays it -- and the
			dive already writes this CFrame for the roll, so it is the same
			authority, not a new one.

			Falls back to the body's own facing when `Pitchward` is unavailable.
		]]
		local facing = nil
		local pitchward = model:GetAttribute(GoalkeeperConfig.Attributes.Pitchward)
		if typeof(pitchward) == "Vector3" then
			local flat = BallControlMath.GetHorizontal(pitchward)
			if flat.Magnitude > 0.01 then
				facing = flat.Unit
			end
		end
		if not facing then
			facing = BallControlMath.SafeUnit(
				BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
				direction
			)
		end
		local uprightNow = CFrame.lookAt(rootPart.Position, rootPart.Position + facing, Vector3.yAxis)
		--[[
			A CFrame's local +Z points BACKWARD (LookVector is -Z), and a
			positive rotation about it carries +X (the body's right) up toward
			+Y -- which tips the keeper to their LEFT. So a dive to the right
			takes the negative angle.
		]]
		diveSign = if direction:Dot(uprightNow.RightVector) >= 0 then -1 else 1
		diveFacing = facing
		--[[
			THE LAUNCH STARTS FROM REST.

			The dive is driven through the Humanoid, which ACCELERATES toward the
			launch rather than snapping to it -- so whatever the keeper was
			already doing bleeds into the first frames of the dive. Measured, a
			keeper moving left-and-back who dives RIGHT:

				dive=[side=Right launchWorldAngle=90.0]  travelAngle=-105.6

			-- the body going the opposite way to the dive it was just granted.
			Clearing the horizontal component once, here, means the launch begins
			from nothing and goes where the server actually said. Vertical is
			left alone so a keeper already off the ground keeps falling.
		]]
		local carried = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(0, carried.Y, 0)
	end
	local upright = CFrame.lookAt(rootPart.Position, rootPart.Position + diveFacing, Vector3.yAxis)
	local sign = diveSign

	if currentHumanoid then
		currentHumanoid.AutoRotate = false
	end
	-- Remembered so the stand-up can unwind from exactly where the dive left it.
	currentDiveRoll = roll * sign
	rootPart.CFrame = upright * CFrame.fromAxisAngle(Vector3.zAxis, currentDiveRoll)
	diveTiltActive = true
	diveRecoveryUntil = 0
	diveInputLockUntil = 0
	return true
end

local function updateGoalkeeperFacing(deltaTime: number)
	local rootPart = currentRootPart
	local model = localPlayer.Character
	local isKeeper = model ~= nil
		and model:GetAttribute(GoalkeeperConfig.RoleAttributeName) == GoalkeeperConfig.Role
	local holding = model ~= nil
		and model:GetAttribute(GoalkeeperConfig.Attributes.Holding) == true

	-- A dive owns the body outright: it is committed movement, and standing
	-- guard has nothing to say while the keeper is in the air.
	if updateGoalkeeperDiveTilt() then
		goalkeeperFacingActive = false
		return
	end

	if not rootPart or not isKeeper or holding then
		if goalkeeperFacingActive then
			goalkeeperFacingActive = false
			if currentHumanoid and not receptionFacingActive and not animationOwnsRotation() then
				currentHumanoid.AutoRotate = movementConfig.AutoRotate
			end
		end
		return
	end

	-- A driven turn or a deliberate reception aim outranks standing guard.
	if animationOwnsRotation() or receptionFacingActive then
		return
	end

	--[[
		THE PLAYER CAN TURN. BALL-TRACKING IS A REST STATE, NOT A LOCK.

		Facing was pinned to the ball unconditionally, and the arc clamp is
		centred on facing out of the goal -- so with the ball close to a post the
		keeper was pinned hard against the edge of the arc and could not look
		anywhere else. Reported as being unable to rotate at all.

		The rule is now the ordinary one for assistance (section 2): the moment
		the player steers, the player is facing where they steer. Ball-tracking
		resumes when they stop, so a keeper who is not asking for anything still
		watches the ball. Nothing is taken away -- what was automatic is still
		automatic; it simply yields.
	]]
	--[[
		A KEEPER DOES NOT FACE WHERE THEY MOVE.

		Movement input used to steer the keeper's FACING here, unclamped. That
		turned every side step into a run: the body swung to point along its own
		travel, so a shuffle across the line was rendered as a footballer jogging
		forwards. Measured over one session, on every single side-step sample the
		body was aligned with its own velocity --

			goalAngle= 67.9  body fwd=+10.14 right=-0.11  -> bodyAngle= -0.6
			goalAngle=-94.6  body fwd=+16.00 right=-0.13  -> bodyAngle= -0.5
			goalAngle=-65.0  body fwd=+10.54 right=+1.48  -> bodyAngle= +8.0

		-- and the yaw reached 94 degrees, well outside the arc, because this
		branch returned before the clamp below could run.

		It also made jog-backwards unreachable by construction: if the body
		always points at its travel, no travel is ever backwards.

		Moving sideways and looking sideways are different things in football,
		and for a keeper they are almost never the same thing. Facing is now
		ball-tracking, clamped to the arc around pitchward, and movement does not
		touch it.

		This restores what an earlier pass removed for a real reason -- a keeper
		pinned to the arc edge could not look elsewhere. That is addressed by the
		arc itself (now 45 degrees, centred on the goal the keeper defends),
		not by handing facing to the movement stick.
	]]

	local football = getFootball()
	if not football then
		return
	end
	local current = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
		Vector3.zAxis
	)
	local toBall = BallControlMath.GetHorizontal(football.Position - rootPart.Position)
	if toBall.Magnitude <= 1e-3 then
		return
	end
	local desired = BallControlMath.SafeUnit(toBall, current)

	--[[
		BOUNDED TO AN ARC AROUND FACING OUT OF THE GOAL.

		Tracking the ball without a bound meant a ball behind the goal line
		turned the keeper to face their own net -- they lost sight of the goal
		they are defending at exactly the moment a corner is coming in. Clamping
		to a half-circle centred on pitchward keeps both posts, and everything
		between them, reachable, while the keeper stays oriented to the goal.

		If the server has not published the direction yet, the old free tracking
		stands rather than guessing an arc from the wrong reference.
	]]
	local pitchward = model:GetAttribute(GoalkeeperConfig.Attributes.Pitchward)
	local arcDegrees = GoalkeeperConfig.Human.MaximumFacingArcDegrees
	if typeof(pitchward) == "Vector3" and arcDegrees then
		local axis = BallControlMath.SafeUnit(BallControlMath.GetHorizontal(pitchward), desired)
		local limit = math.cos(math.rad(arcDegrees))
		if axis:Dot(desired) < limit then
			--[[
				Outside the arc: swing to its nearer edge rather than to the
				centre, so the keeper ends up looking at the post the threat is
				coming round instead of snapping back to straight ahead.
			]]
			local side = desired - axis * axis:Dot(desired)
			local lateral = BallControlMath.SafeUnit(side, axis:Cross(Vector3.yAxis))
			desired = BallControlMath.SafeUnit(
				axis * limit + lateral * math.sin(math.rad(arcDegrees)),
				axis
			)
		end
	end

	local alpha = 1 - math.exp(-GoalkeeperConfig.Human.FacingResponsiveness * deltaTime)
	local facing = BallControlMath.SafeUnit(current:Lerp(desired, alpha), desired)
	if currentHumanoid then
		currentHumanoid.AutoRotate = false
	end
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + facing, Vector3.yAxis)
	goalkeeperFacingActive = true
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

	-- Same rule as reception facing: the driven turn wins while it runs (§73).
	if animationOwnsRotation() then
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

--[[
	Speed multiplier from the server-authoritative injury state.
	Healthy footballers are unaffected.
]]
local function getInjurySpeedScale(): number
	local character = currentHumanoid and currentHumanoid.Parent
	local state = character and character:GetAttribute(MatchRulesConfig.Injury.StateAttributeName)
	if typeof(state) ~= "string" then
		return 1
	end
	local injury = MatchRulesConfig.Injury
	if state == injury.States.Knocked then
		return injury.KnockedSpeedScale
	elseif state == injury.States.Minor then
		return injury.MinorSpeedScale
	elseif state == injury.States.Moderate then
		return injury.ModerateSpeedScale
	end
	return 1
end

--[[
	Is movement forbidden right now?

	This used to test PreMatch alone, which covered the wait for START MATCH but
	nothing else. Every restart also has an arranging period -- Stoppage while
	the award is announced, then RestartSetup while the server places the taker,
	both teams, the officials and the ball -- and a human who can run during it
	is standing somewhere the arrangement did not put them by the time the
	whistle goes.

	The phase list is shared rather than spelled out here, so the client and the
	server cannot drift apart about when the pitch is being set.
]]
local function isMovementLocked(): boolean
	--[[
		A COMMITTED SLIDE IS ALSO A MOVEMENT LOCK.

		Once a slide has been launched the footballer is going where they were
		pointed and nowhere else. That commitment is the entire cost of the
		challenge -- a slide the player could steer, or pull out of, would simply
		be a standing tackle with extra reach and no downside.

		The window is written by the SERVER, which is what makes this binding:
		suppressing input here is presentation of a decision already made, not
		the decision itself, so a client that ignored this would still be unable
		to act, because the server's recovery is what gates further challenges.
	]]
	local character = localPlayer.Character
	local slidingUntil = character and character:GetAttribute(DefendingConfig.Slide.SlidingAttribute)
	if typeof(slidingUntil) == "number" and os.clock() < slidingUntil then
		return true
	end

	--[[
		SO IS GETTING UP FROM A DIVE.

		Reported as the keeper "moving backwards" after a dive. The roll was
		being unwound correctly, but movement stayed live throughout -- so the
		humanoid was walking the body around while the CFrame rotated it back
		upright, and the two fought each other. What that looked like was the
		keeper sliding away out of the dive.

		A keeper on the floor is committed exactly like a slide: the dive was the
		decision and the cost of it is the moment spent getting back up. Zeroing
		INPUT here rather than the move call keeps smoothing, coasting and the
		animation state machine all seeing the same thing.
	]]
	if os.clock() < diveInputLockUntil then
		return true
	end

	--[[
		A STANDING CHALLENGE IS COMMITTED TOO (Milestone 6.8).

		The same argument as the slide above, over a much shorter span. Once the
		contact window is open the leg is already going, and being able to keep
		running through it would make the challenge free -- which is exactly what
		the window was introduced to stop.

		GameplayFootball clears human input for both of its challenge types, not
		just the slide (`humancontroller.cpp:52-58`, Sliding OR Interfere).

		This is the change in 6.8 most likely to need tuning by feel rather than
		by measurement: the window is 0.36s, and Beyond 90 leans arcade. If it
		reads as sluggish, this guard is the one thing to relax -- the server-side
		commitment does not depend on it.
	]]
	local challengeUntil = character and character:GetAttribute(DefendingConfig.ContactWindow.CommittedAttribute)
	if typeof(challengeUntil) == "number" and os.clock() < challengeUntil then
		return true
	end

	--[[
		A DIVE IS THROWN, NOT STEERED.

		The server launches the keeper by setting AssemblyLinearVelocity and then
		owns the dive for its duration. Nothing here yielded to it, so this
		controller kept driving the humanoid every frame and cancelled the launch
		on the very next tick -- which is why a dive produced almost no travel.

		Exactly the same shape as the slide lockout above, for the same reason.
	]]
	local diving = character and character:GetAttribute(GoalkeeperConfig.Attributes.Diving)
	if diving == true then
		return true
	end

	--[[
		THE TAKER OF A RESTART DOES NOT WALK AWAY FROM IT.

		A restart is held, not carried (see RestartControl): the ball is on its
		spot and it belongs to the taker until they play it. Nothing was stopping
		the taker from simply jogging off, which left the football sitting on the
		centre spot with its owner twenty studs away -- and at kick-off that read
		as the kick-off never happening at all.

		Locking only the TAKER is the point. Everyone else is free to move into
		the shape they want before the whistle, exactly as they are in football.
		The lock lifts the instant the restart is played, because the server
		clears AwaitingAction at that moment and this reads the same attribute.
	]]
	if RestartControl.IsHeldBy(getFootball(), localPlayer.UserId) then
		return true
	end

	local folder = ReplicatedStorage:FindFirstChild(MatchRulesConfig.FolderName)
	if not folder then
		return false
	end
	local phase = folder:GetAttribute(MatchRulesConfig.StateAttributeName)
	return typeof(phase) == "string" and MatchRulesConfig.MovementLockedPhases[phase] == true
end

local function updateLocomotion(deltaTime: number)
	local humanoid = currentHumanoid

	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local rawInput = InputController.GetInputState()
	inputSource = rawInput.Source
	local now = os.clock()

	--[[
		A press that is still closing sprints (§37).

		Routed through the ordinary sprint request rather than by raising a speed
		cap, so the footballer accelerates, tires and is limited by the stamina
		ceiling exactly as if the player had held Sprint themselves. The player's
		own sprint input still wins -- this can only add sprint, never remove it.
	]]
	local pressWantsSprint = false
	if pressStateProvider then
		local pressState = pressStateProvider()
		pressWantsSprint = pressState ~= nil and pressState.ShouldSprint == true
	end
	local desiredSprint = rawInput.SprintRequested or pressWantsSprint
	if desiredSprint ~= sprintRequested then
		setSprintRequested(desiredSprint)
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
	local pressAssisting = false
	local keeperAssisting = false
	--[[
		A goalkeeper does not press, and does not chase loose balls the way an
		outfielder does, so the keeper assist replaces those rather than stacking
		on top of them.
	]]
	if goalkeeperStateProvider and goalkeeperStateProvider() then
		rawDirection, rawMagnitude, keeperAssisting = getGoalkeeperAssist(rawDirection, rawMagnitude)
	elseif receptionPhase == "" then
		rawDirection, rawMagnitude, pressAssisting = getPressAssist(rawDirection, rawMagnitude)
	end
	updateGoalkeeperFacing(deltaTime)
	updateReceptionFacing(deltaTime, receptionPhase)
	updateActionFacing(deltaTime)
	--[[
		NOTHING MOVES BEFORE THE MATCH STARTS (§25).

		The server holds every footballer at its assembled position as well, so
		this is the responsive half of a restriction that is genuinely enforced
		rather than the whole of it.
	]]
	if localPlayer:GetAttribute("Beyond90MenuOpen") == true or isMovementLocked() then
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
	elseif keeperAssisting then
		movementMode = "GoalkeeperAssist"
	elseif pressAssisting then
		movementMode = "PressAssist"
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

	--[[
		Injury slows the human footballer exactly as it slows AI (§72). The state
		is server-authoritative and replicated on the character; the client only
		reads it.
	]]
	--[[
		A DIVE IS DRIVEN, NOT LEFT ALONE.

		Third attempt at this, and the first two both failed for the same reason,
		recorded so it is not tried a third way:

		  1. Writing the velocity on the SERVER did nothing, because a player's
		     own character is network-owned by their client.
		  2. Applying it on the client and then RETURNING EARLY here still did
		     nothing, because a Humanoid keeps applying its last `Move` command
		     every physics step. Skipping the update does not stop the humanoid,
		     it just freezes it on `Move(zero)` with `WalkSpeed = 0` -- which is
		     an active brake, so the launch was cancelled on the next step.

		The humanoid cannot be bypassed, so it gets driven instead: for the
		duration of the dive it is told to walk, flat out, in the direction the
		server chose. That produces real lateral travel the player can see, and
		it cannot be fought by the character controller because it IS the
		character controller.

		The server still decides whether the dive happens, its direction and its
		duration; this only carries out the launch it published.
	]]
	local diveCharacter = humanoid and humanoid.Parent
	local diveVelocity = diveCharacter
		and diveCharacter:GetAttribute(GoalkeeperConfig.Attributes.DiveVelocity)
	if
		diveCharacter
		and diveCharacter:GetAttribute(GoalkeeperConfig.Attributes.Diving) == true
		and typeof(diveVelocity) == "Vector3"
		--[[
			THE BODY WAITS FOR THE CLIP.

			Both this and AnimationController react to the server's `Diving`
			attribute, in separate callbacks, so the body used to launch one or
			two frames before the dive was drawn -- the keeper sliding sideways
			while still standing up. The clip publishes when it begins and the
			launch waits for it, so they start together.
		]]
		and diveCharacter:GetAttribute(DIVE_STARTED_ATTRIBUTE) ~= nil
	then
		local flat = Vector3.new(diveVelocity.X, 0, diveVelocity.Z)
		if flat.Magnitude > 0.01 then
			--[[
				THE KEEPER LEAVES THE GROUND, AND THEN REACHES IT.

				This was an impulse: the published `DiveVelocity.Y` written once
				into `AssemblyLinearVelocity` at launch. Two faults, one cause.
				A thrown body's upward speed PEAKS on the first frame, so the
				visible motion was a hop at the instant of launch, before any
				lateral travel had accumulated. And a throw cannot finish below
				where it began, so the keeper never actually got to the floor --
				he rose, came back to standing height, and stood up from there.

				Driven instead, across the dive's own progress, so the arc can
				end 2.4 studs DOWN with the keeper lying on the grass. Horizontal
				stays on the Humanoid drive below; a Humanoid cannot be bypassed,
				only driven, and that part already works.
			]]
			local diveStartedAt = diveCharacter:GetAttribute("Beyond90GoalkeeperDiveAt")
			local diveElapsed = if typeof(diveStartedAt) == "number"
				then os.clock() - diveStartedAt
				else 0
			applyDiveHipOffset(
				humanoid,
				diveHipOffsetAt(
					math.clamp(diveElapsed / math.max(GoalkeeperConfig.Dive.Duration, 0.01), 0, 1)
				)
			)
			humanoid.WalkSpeed = flat.Magnitude
			humanoid:Move(flat.Unit, false)
			if jumpStartedAt > 0 and currentRootPart then
				jumpPeakY = math.max(jumpPeakY, currentRootPart.Position.Y)
			end
			return
		end
	end

	humanoid.WalkSpeed = locomotionState.SmoothedSpeed * getInjurySpeedScale()

	if shouldMove then
		--[[
			Steered around anyone in the way (FootballerSeparation).

			Applied to the direction the player has ALREADY chosen, and only
			while they are moving, so it bends a run around a body without
			touching where the run was going. Standing still stays standing
			still -- holding your ground is a football decision.

			Section 33 lists body-overlap avoidance among the assistance a
			controlled footballer may receive, and this is that: the player's
			intent, executed without walking through somebody.
		]]
		local separationRoot = currentRootPart
		humanoid:Move(
			if separationRoot
				then FootballerSeparation.Steer(
					locomotionState.SmoothedDirection,
					separationRoot.Position,
					getSeparationNeighbours(),
					localPlayer.UserId
				)
				else locomotionState.SmoothedDirection,
			false
		)
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
		bindDiveHipBaseline(nil)
		currentRootPart = nil
		return
	end

	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart or not rootPart:IsA("BasePart") then
		warnLog("Character missing HumanoidRootPart; movement settings were not applied")
		currentHumanoid = nil
		bindDiveHipBaseline(nil)
		currentRootPart = nil
		return
	end

	currentHumanoid = humanoid
	bindDiveHipBaseline(humanoid)
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
	bindDiveHipBaseline(nil)
	currentRootPart = nil
	actionProfileName = ""
	sprintRequested = false
	coastStartedAt = 0
	resetLocomotionState()
end

return MovementController
