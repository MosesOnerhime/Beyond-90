local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local FootballTeamEligibility = require(Shared.Football.FootballTeamEligibility)
local PassPlanner = require(Shared.Football.PassPlanner)
local ShotPlanner = require(Shared.Football.ShotPlanner)
local BallControlService = require(script.Parent.BallControlService)
local GoalService = require(script.Parent.GoalService)

local FootballActionService = {}

local initialized = false
local requestRemote: RemoteEvent? = nil
local feedbackRemote: RemoteEvent? = nil
local developmentShootingSkillRemote: RemoteEvent? = nil
local lastActionAtByPlayer: { [Player]: { [string]: number } } = {}
local nextPassId = 0
local nextShotId = 0
local preparedShotsByPlayer = {}

local function getShootingSkill(player: Player): number
	local config = FootballActionConfig.Shoot.Skill
	local value = player:GetAttribute("Beyond90ShootingSkill")
	if typeof(value) ~= "number" then
		value = config.Default
	end
	return math.clamp(value, config.Minimum, config.Maximum)
end

local function log(message: string)
	print(string.format("%s[FootballAction] %s", GameConfig.LogPrefix, message))
end

local function warnLog(message: string)
	warn(string.format("%s[FootballAction] %s", GameConfig.LogPrefix, message))
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

local function getFootball(): BasePart?
	local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local ballFolder = rootFolder and rootFolder:FindFirstChild("Ball")
	local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)

	if ball and ball:IsA("BasePart") then
		return ball
	end

	return nil
end

local function getPlayerRoot(player: Player): BasePart?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if rootPart and rootPart:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return rootPart
	end

	return nil
end

local function getAimDirection(player: Player, payload): Vector3
	local rootPart = getPlayerRoot(player)
	local fallback = if rootPart
		then BallControlMath.SafeUnit(BallControlMath.GetHorizontal(rootPart.CFrame.LookVector), Vector3.new(0, 0, -1))
		else Vector3.new(0, 0, -1)
	local requested = payload and payload.AimDirection

	if typeof(requested) ~= "Vector3" then
		return fallback
	end

	local horizontal = BallControlMath.GetHorizontal(requested)

	if horizontal.Magnitude <= 0.05 then
		return fallback
	end

	return horizontal.Unit
end

local function createPlayerCandidate(player: Player)
	local rootPart = getPlayerRoot(player)
	if not rootPart then
		return nil
	end
	return {
		Kind = "Player",
		Name = player.Name,
		UserId = player.UserId,
		Instance = player,
		Position = rootPart.Position,
		Velocity = rootPart.AssemblyLinearVelocity,
		FacingDirection = BallControlMath.GetHorizontal(rootPart.CFrame.LookVector),
	}
end

local function isCooldownReady(player: Player, actionType: string, cooldown: number): boolean
	local now = os.clock()
	local playerTimes = lastActionAtByPlayer[player]

	if not playerTimes then
		playerTimes = {}
		lastActionAtByPlayer[player] = playerTimes
	end

	local lastActionAt = playerTimes[actionType]

	if lastActionAt and now - lastActionAt < cooldown then
		return false
	end

	playerTimes[actionType] = now
	return true
end

local function sendFeedback(player: Player, accepted: boolean, reason: string?, plan, actionTypeOverride: string?, stage: string?)
	local remote = feedbackRemote

	if not remote then
		return
	end

	remote:FireClient(player, {
		Accepted = accepted,
		Reason = reason or "",
		ActionType = actionTypeOverride or (plan and plan.ActionType) or "",
		TargetPosition = plan and plan.TargetPosition or nil,
		TargetName = plan and plan.SelectedCandidate and plan.SelectedCandidate.Name or "",
		TargetUserId = plan and plan.SelectedCandidate and plan.SelectedCandidate.UserId or 0,
		LaunchSpeed = plan and plan.LaunchSpeed or 0,
		Distance = plan and plan.Distance or 0,
		PredictedArrivalTime = plan and plan.PredictedArrivalTime or 0,
		PredictedArrivalSpeed = plan and plan.PredictedArrivalSpeed or 0,
		Intensity = plan and plan.Intensity or 1,
		RelativeForwardSpeed = plan and plan.RelativeForwardSpeed or 0,
		VerticalLaunchSpeed = plan and plan.VerticalLaunchSpeed or 0,
		Score = plan and plan.Score or 0,
		Stage = stage or (if accepted then "Released" else "Rejected"),
		GoalId = plan and plan.GoalId or "",
		ClientActionId = plan and plan.ClientActionId or "",
		Trajectory = plan and plan.Trajectory or "",
		ShootingSkill = plan and plan.ShootingSkill or 0,
		IntendedGoalTarget = plan and plan.IntendedGoalTarget or nil,
		FinalGoalTarget = plan and plan.FinalGoalTarget or nil,
		HorizontalError = plan and plan.HorizontalError or 0,
		VerticalError = plan and plan.VerticalError or 0,
		Result = plan and plan.Result or "",
		BodyAlignment = plan and plan.BodyAlignment or 0,
		AlignmentErrorAlpha = plan and plan.AlignmentErrorAlpha or 0,
	})
end

local function findPlayerByUserId(userId: number): Player?
	for _, candidate in Players:GetPlayers() do
		if candidate.UserId == userId then
			return candidate
		end
	end
	return nil
end

local function rejectPass(player: Player, actionType: string, receiverUserId: number, reason: string)
	log(string.format("[PassReject] passer=%s receiverUserId=%d action=%s reason=%s", player.Name, receiverUserId, actionType, reason))
	sendFeedback(player, false, reason, nil, actionType)
end

local function getHoldIntensity(actionConfig, holdDuration: number): number
	local minIntensity = actionConfig.MinIntensity or 1
	local maxIntensity = actionConfig.MaxIntensity or minIntensity
	local holdMaxTime = math.max(actionConfig.HoldMaxTime or 0.75, 0.05)
	local alpha = math.clamp(holdDuration / holdMaxTime, 0, 1)
	local intensity = minIntensity + (maxIntensity - minIntensity) * alpha
	local globalIntensity = FootballActionConfig.DevelopmentIntensity

	return math.clamp(intensity, globalIntensity.Min, globalIntensity.Max)
end

local function getSelectedReceiverUserId(plan): number
	if not plan or not plan.SelectedCandidate or plan.SelectedCandidate.Kind ~= "Player" then
		return 0
	end

	local instance = plan.SelectedCandidate.Instance

	if typeof(instance) == "Instance" and instance:IsA("Player") then
		return instance.UserId
	end

	return 0
end

local function handlePass(player: Player, actionType: string, payload)
	local ball = getFootball()
	local rootPart = getPlayerRoot(player)

	if not ball or not rootPart then
		rejectPass(player, actionType, 0, "passer-character-missing")
		return
	end

	if not BallControlService.IsControlledBy(player, ball) then
		rejectPass(player, actionType, 0, "passer-no-possession")
		return
	end

	local actionConfig = if actionType == "ThroughPass"
		then FootballActionConfig.ThroughPass
		elseif actionType == "LobPass"
		then FootballActionConfig.LobPass
		else FootballActionConfig.Pass

	local ballDistance = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude

	if ballDistance > BallConfig.Control.HardControlDistance then
		rejectPass(player, actionType, 0, "controlled-ball-out-of-range")
		return
	end

	local holdDuration = if payload and typeof(payload.HoldDuration) == "number" then payload.HoldDuration else 0
	local requestedReceiverUserId = if payload and typeof(payload.IntendedReceiverUserId) == "number"
		then math.floor(payload.IntendedReceiverUserId)
		else 0

	-- Studio multiplayer clients use negative temporary UserIds. Zero is the
	-- only sentinel for an absent receiver.
	if requestedReceiverUserId == 0 then
		rejectPass(player, actionType, requestedReceiverUserId, "receiver-missing")
		return
	end

	local receiver = findPlayerByUserId(requestedReceiverUserId)
	if not receiver then
		rejectPass(player, actionType, requestedReceiverUserId, "receiver-missing")
		return
	end
	local eligible, eligibilityReason = FootballTeamEligibility.AreTeammates(player, receiver, FootballActionConfig.Targeting)
	if not eligible then
		rejectPass(player, actionType, requestedReceiverUserId, eligibilityReason)
		return
	end
	local candidate = createPlayerCandidate(receiver)
	if not candidate then
		rejectPass(player, actionType, requestedReceiverUserId, "receiver-dead")
		return
	end
	local maxTargetRange = PassPlanner.GetMaximumTargetRange(FootballActionConfig)
	local receiverDistance = BallControlMath.GetHorizontal(candidate.Position - ball.Position).Magnitude
	if receiverDistance > maxTargetRange then
		rejectPass(player, actionType, requestedReceiverUserId, "receiver-out-of-range")
		return
	end
	if not isCooldownReady(player, actionType, actionConfig.Cooldown) then
		rejectPass(player, actionType, requestedReceiverUserId, "cooldown")
		return
	end

	local aimDirection = getAimDirection(player, payload)
	local intensity = 1
	local plan, reason = PassPlanner.PlanForReceiver(
		ball.Position,
		aimDirection,
		holdDuration,
		actionType,
		candidate,
		FootballActionConfig,
		intensity,
		FootballActionConfig.Targeting.RetentionConeDegrees
	)

	if not plan then
		local rejectionReason = if reason == "no valid receiver" then "invalid-target-position" else reason
		rejectPass(player, actionType, requestedReceiverUserId, rejectionReason or "invalid-target-position")
		return
	end

	nextPassId += 1
	local passId = nextPassId
	local released = BallControlService.ReleaseForFootballAction(
		ball,
		player,
		actionType,
		plan.LaunchVelocity,
		plan.ReleaseReacquireSuppression,
		plan.ReleaseReacquireExitDistance,
		{
			PassId = passId,
			IntendedReceiverUserId = getSelectedReceiverUserId(plan),
			IntendedReceiverName = plan.SelectedCandidate and plan.SelectedCandidate.Name or "",
			TargetPosition = plan.TargetPosition,
			TargetKind = plan.SelectedCandidate and plan.SelectedCandidate.Kind or "Space",
			EstimatedArrivalTime = plan.PredictedArrivalTime,
		}
	)

	if not released then
		sendFeedback(player, false, "release rejected", plan)
		return
	end

	log(string.format(
		"[Pass] type=%s player=%s receiver=%s userId=%d angle=%.1f intensity=%.2fx distance=%.1f launchSpeed=%.1f verticalSpeed=%.1f predictedArrivalSpeed=%.1f eta=%.2f trajectory=%s score=%.2f",
		actionType,
		player.Name,
		plan.SelectedCandidate.Name,
		plan.SelectedCandidate.UserId,
		plan.AngleDegrees or 0,
		plan.Intensity,
		plan.Distance,
		plan.LaunchSpeed,
		plan.VerticalLaunchSpeed or 0,
		plan.PredictedArrivalSpeed,
		plan.PredictedArrivalTime,
		plan.Trajectory or "Ground",
		plan.Score
	))
	sendFeedback(player, true, "", plan)
end

local function releasePreparedShot(player: Player, clientActionId: string, releaseReason: string)
	local prepared = preparedShotsByPlayer[player]
	if not prepared or prepared.ClientActionId ~= clientActionId then
		return
	end
	preparedShotsByPlayer[player] = nil
	if os.clock() > prepared.ExpiresAt then
		sendFeedback(player, false, "shot-expired", prepared.Plan, "Shoot")
		return
	end
	local ball = prepared.Ball
	local plan = prepared.Plan
	if plan.ActionType == "Shoot"
		and player:GetAttribute(FootballTeamConfig.AttackingGoalAttributeName) ~= plan.GoalId
	then
		sendFeedback(player, false, "attacking-goal-changed", plan, "Shoot")
		return
	end
	if not ball.Parent or not BallControlService.IsControlledBy(player, ball) then
		sendFeedback(player, false, "shooter-no-possession", plan, "Shoot")
		return
	end
	local released = BallControlService.ReleaseForFootballAction(
		ball,
		player,
		plan.ActionType,
		plan.LaunchVelocity,
		FootballActionConfig.Shoot.ReleaseReacquireSuppression,
		FootballActionConfig.Shoot.ReacquireExitDistance,
		{
			IntendedReceiverUserId = 0,
			TargetPosition = plan.TargetPosition,
			TargetKind = if plan.ActionType == "Clearance" then "Space" else "Goal",
			GoalId = plan.GoalId,
			EstimatedArrivalTime = plan.PredictedArrivalTime,
		}
	)
	if not released then
		sendFeedback(player, false, "shot-release-rejected", plan, "Shoot")
		return
	end
	log(string.format(
		"[Shot] player=%s type=%s goal=%s distance=%.1f intended=%s final=%s horizontalError=%.2f verticalError=%.2f bodyAlignment=%.2f alignmentError=%.2f launchSpeed=%.1f verticalSpeed=%.1f skill=%.0f result=%s contact=%s",
		player.Name,
		plan.ActionType,
		plan.GoalId,
		plan.Distance,
		tostring(plan.IntendedGoalTarget or plan.TargetPosition),
		tostring(plan.FinalGoalTarget or plan.TargetPosition),
		plan.HorizontalError or 0,
		plan.VerticalError or 0,
		plan.BodyAlignment or 0,
		plan.AlignmentErrorAlpha or 0,
		plan.LaunchSpeed,
		plan.VerticalLaunchSpeed,
		(plan.ShootingSkill or 0) * 100,
		plan.Result or "Released",
		releaseReason
	))
	sendFeedback(player, true, "", plan, "Shoot", "Released")
end

local function handleShoot(player: Player, payload)
	local phase = if payload and typeof(payload.Phase) == "string" then payload.Phase else "Prepare"
	local clientActionId = if payload and typeof(payload.ClientActionId) == "string" then payload.ClientActionId else ""
	if phase == "Commit" then
		releasePreparedShot(player, clientActionId, "BallContact-marker")
		return
	end

	local ball = getFootball()
	local rootPart = getPlayerRoot(player)
	if not ball or not rootPart then
		sendFeedback(player, false, "shooter-character-missing", nil, "Shoot")
		return
	end
	if not BallControlService.IsControlledBy(player, ball) then
		sendFeedback(player, false, "shooter-no-possession", nil, "Shoot")
		return
	end
	local actionBallDistance = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude
	if actionBallDistance > math.max(FootballActionConfig.Shoot.ControlDistance, FootballActionConfig.Shoot.ControlledTouchAllowance or 0) then
		sendFeedback(player, false, "controlled-ball-out-of-range", nil, "Shoot")
		return
	end
	if not isCooldownReady(player, "Shoot", FootballActionConfig.Shoot.Cooldown) then
		sendFeedback(player, false, "cooldown", nil, "Shoot")
		return
	end

	local goals = GoalService.GetGoals()
	local aimDirection = getAimDirection(player, payload)
	local teamId = FootballTeamConfig.Normalize(player:GetAttribute(FootballTeamConfig.AttributeName))
	local mapping = FootballTeamConfig.GetGoalMapping(teamId)
	local configuredGoalId = player:GetAttribute(FootballTeamConfig.AttackingGoalAttributeName)
	local goalId = if mapping and configuredGoalId == mapping.AttackingGoalId then configuredGoalId else nil
	if not goalId then
		sendFeedback(player, false, "attacking-goal-unassigned", nil, "Shoot")
		return
	end
	local goal = goals[goalId]
	if not goal then
		sendFeedback(player, false, "goal-unavailable", nil, "Shoot")
		return
	end
	local goalDistance = if goal
		then BallControlMath.GetHorizontal(goal.MouthCenter - ball.Position).Magnitude
		else math.huge
	local defendedGoal = goals[mapping.DefendedGoalId]
	local attackingDirection = if defendedGoal
		then BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(goal.MouthCenter - defendedGoal.MouthCenter),
			BallControlMath.GetHorizontal(goal.MouthCenter - ball.Position)
		)
		else BallControlMath.SafeUnit(BallControlMath.GetHorizontal(goal.MouthCenter - ball.Position), aimDirection)
	local pitchCenter = if defendedGoal then (goal.MouthCenter + defendedGoal.MouthCenter) * 0.5 else goal.MouthCenter
	local attackingHalfProgress = BallControlMath.GetHorizontal(ball.Position - pitchCenter):Dot(attackingDirection)
	local plan, reason
	if attackingHalfProgress < (FootballActionConfig.Shoot.MinimumShotProgressStuds or 0)
		or goalDistance > FootballActionConfig.Shoot.MaximumAttackingDistance
	then
		plan = ShotPlanner.PlanClearance(ball.Position, aimDirection, attackingDirection, FootballActionConfig.Shoot)
		reason = nil
	else
		plan, reason = ShotPlanner.Plan(
			ball.Position,
			aimDirection,
			goal,
			BallConfig.Radius,
			FootballActionConfig.Shoot,
			getShootingSkill(player),
			rootPart.CFrame.LookVector
		)
	end
	if not plan then
		sendFeedback(player, false, reason or "goal-unavailable", nil, "Shoot")
		return
	end
	nextShotId += 1
	if clientActionId == "" then
		clientActionId = string.format("%d:%d", player.UserId, nextShotId)
	end
	plan.ClientActionId = clientActionId
	preparedShotsByPlayer[player] = {
		Ball = ball,
		Plan = plan,
		ClientActionId = clientActionId,
		ExpiresAt = os.clock() + FootballActionConfig.Shoot.PreparedActionLifetime,
	}
	sendFeedback(player, true, "", plan, "Shoot", "Prepared")
	task.delay(FootballActionConfig.Shoot.ContactFallbackTime, function()
		releasePreparedShot(player, clientActionId, "configured-fallback")
	end)
end

local function handleKnockOn(player: Player, payload)
	local ball = getFootball()
	local rootPart = getPlayerRoot(player)

	if not ball or not rootPart then
		sendFeedback(player, false, "missing ball or character", nil)
		return
	end

	if not BallControlService.IsControlledBy(player, ball) then
		sendFeedback(player, false, "player does not control ball", nil)
		return
	end

	local actionConfig = FootballActionConfig.KnockOn

	if not isCooldownReady(player, "KnockOn", actionConfig.Cooldown) then
		sendFeedback(player, false, "cooldown", nil)
		return
	end

	local ballDistance = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude

	if ballDistance > math.max(actionConfig.ControlDistance, actionConfig.ControlledTouchAllowance or 0) then
		sendFeedback(player, false, "ball too far", nil)
		return
	end

	local holdDuration = if payload and typeof(payload.HoldDuration) == "number" then payload.HoldDuration else 0
	local requestedAimDirection = getAimDirection(player, payload)
	local intensity = getHoldIntensity(actionConfig, holdDuration)
	local playerHorizontalVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local sprintRequested = rootPart.Parent
		and rootPart.Parent:FindFirstChildOfClass("Humanoid")
		and (rootPart.Parent:FindFirstChildOfClass("Humanoid") :: Humanoid):GetAttribute("SprintRequested") == true
	local sprintSpeedThreshold = PlayerConfig.Movement.BaseSpeed
		+ (PlayerConfig.Movement.SprintSpeed - PlayerConfig.Movement.BaseSpeed) * 0.35
	local sprinting = sprintRequested or playerHorizontalVelocity.Magnitude >= sprintSpeedThreshold
	local predictionTime = if sprinting then actionConfig.SprintPredictionTime else actionConfig.JogPredictionTime
	local additionalLead = (if sprinting then actionConfig.SprintAdditionalLead else actionConfig.JogAdditionalLead) * intensity
	local targetSpeed = if sprinting then PlayerConfig.Movement.SprintSpeed else PlayerConfig.Movement.BaseSpeed
	local accelerationTime = if sprinting
		then PlayerConfig.Locomotion.SprintAccelerationTime
		else PlayerConfig.Locomotion.AccelerationTime
	local initialForwardSpeed = playerHorizontalVelocity:Dot(requestedAimDirection)
	local initialLateralVelocity = playerHorizontalVelocity - requestedAimDirection * initialForwardSpeed
	local accelerationRate = targetSpeed / math.max(accelerationTime, 0.05)
	local accelerationDuration = math.clamp(
		(targetSpeed - math.max(0, initialForwardSpeed)) / math.max(accelerationRate, 0.01),
		0,
		predictionTime
	)
	local forwardTravel = math.max(0, initialForwardSpeed) * accelerationDuration
		+ 0.5 * accelerationRate * accelerationDuration * accelerationDuration
		+ targetSpeed * (predictionTime - accelerationDuration)
	local predictedTravel = requestedAimDirection * forwardTravel
		+ initialLateralVelocity * predictionTime * actionConfig.PlayerLateralCarry
	predictedTravel = BallControlMath.ClampMagnitude(predictedTravel, actionConfig.MaximumPredictedPlayerTravel)
	local predictedPlayerPosition = rootPart.Position + predictedTravel
	local targetPosition = predictedPlayerPosition + requestedAimDirection * additionalLead
	local targetOffset = BallControlMath.GetHorizontal(targetPosition - ball.Position)
	local aimDirection = BallControlMath.SafeUnit(targetOffset, requestedAimDirection)
	local requiredVelocity = targetOffset / math.max(predictionTime, 0.1)
	local requiredForwardSpeed = requiredVelocity:Dot(requestedAimDirection)
	local anticipatedPlayerSpeed = math.clamp(
		math.max(0, initialForwardSpeed) + accelerationRate * predictionTime,
		0,
		targetSpeed
	)
	local relativePushSpeed = math.clamp(
		math.max(
			requiredForwardSpeed - anticipatedPlayerSpeed,
			actionConfig.MinRelativeForwardSpeed + actionConfig.LaunchSpeedPadding
		),
		actionConfig.MinRelativeForwardSpeed,
		actionConfig.MaxRelativeForwardSpeed
	)
	local launchForwardSpeed = anticipatedPlayerSpeed + relativePushSpeed
	local requiredLateralVelocity = requiredVelocity - requestedAimDirection * requiredForwardSpeed
	local launchHorizontal = requestedAimDirection * launchForwardSpeed + requiredLateralVelocity
	local relativeForwardSpeed = math.max(0, (launchHorizontal - playerHorizontalVelocity):Dot(aimDirection))
	local launchVelocity = launchHorizontal + Vector3.yAxis * actionConfig.VerticalVelocity
	local plan = {
		ActionType = "KnockOn",
		TargetPosition = targetPosition,
		LaunchVelocity = launchVelocity,
		LaunchSpeed = BallControlMath.GetHorizontal(launchVelocity).Magnitude,
		RelativeForwardSpeed = relativeForwardSpeed,
		PlayerForwardSpeed = initialForwardSpeed,
		VerticalLaunchSpeed = actionConfig.VerticalVelocity,
		Distance = targetOffset.Magnitude,
		PredictedArrivalTime = predictionTime,
		PredictedPlayerPosition = predictedPlayerPosition,
		Intensity = intensity,
		Score = 0,
	}

	local released = BallControlService.ReleaseForFootballAction(
		ball,
		player,
		"KnockOn",
		launchVelocity,
		actionConfig.ReleaseReacquireSuppression,
		actionConfig.ReacquireExitDistance,
		{
			IntendedReceiverUserId = 0,
			IntendedReceiverName = "",
			TargetPosition = plan.TargetPosition,
			TargetKind = "Space",
			PredictedCatchTime = predictionTime,
			PeakSeparation = additionalLead,
		}
	)

	if not released then
		sendFeedback(player, false, "release rejected", plan)
		return
	end

	log(string.format(
		"[KnockOnPredict] player=%s movementState=%s playerSpeed=%.1f initialVelocity=%s predictionTime=%.2f predictedPlayerPosition=%s target=%s launchSpeed=%.1f relativeForwardSpeed=%.1f peakLead=%.1f",
		player.Name,
		if sprinting then "Sprint" else "Jog",
		playerHorizontalVelocity.Magnitude,
		tostring(playerHorizontalVelocity),
		predictionTime,
		tostring(predictedPlayerPosition),
		tostring(targetPosition),
		plan.LaunchSpeed,
		plan.RelativeForwardSpeed,
		additionalLead
	))
	sendFeedback(player, true, "", plan)
end

local function onActionRequested(player: Player, payload)
	if typeof(payload) ~= "table" then
		warnLog(string.format("Rejected malformed action payload from %s", player.Name))
		return
	end

	local actionType = payload.ActionType

	if actionType == "GroundPass" then
		handlePass(player, actionType, payload)
	elseif actionType == "ThroughPass" then
		handlePass(player, actionType, payload)
	elseif actionType == "LobPass" then
		handlePass(player, actionType, payload)
	elseif actionType == "KnockOn" then
		handleKnockOn(player, payload)
	elseif actionType == "Shoot" then
		handleShoot(player, payload)
	else
		warnLog(string.format("Rejected unknown action '%s' from %s", tostring(actionType), player.Name))
	end
end

function FootballActionService.Initialize()
	if initialized then
		return
	end

	initialized = true
	local remotes = getOrCreateFolder(ReplicatedStorage, FootballActionConfig.RemotesFolderName)
	requestRemote = getOrCreateRemoteEvent(remotes, FootballActionConfig.RequestRemoteName)
	feedbackRemote = getOrCreateRemoteEvent(remotes, FootballActionConfig.FeedbackRemoteName)
	developmentShootingSkillRemote = getOrCreateRemoteEvent(
		remotes,
		FootballActionConfig.DevelopmentShootingSkillRemoteName
	)
	requestRemote.OnServerEvent:Connect(onActionRequested)
	developmentShootingSkillRemote.OnServerEvent:Connect(function(player, requestedSkill)
		if not RunService:IsStudio() or typeof(requestedSkill) ~= "number" then
			return
		end
		local config = FootballActionConfig.Shoot.Skill
		local skill = math.clamp(requestedSkill, config.Minimum, config.Maximum)
		player:SetAttribute("Beyond90ShootingSkill", skill)
		log(string.format("[ShotSkill] player=%s skill=%.2f", player.Name, skill))
	end)
	local function initializePlayer(player: Player)
		if typeof(player:GetAttribute("Beyond90ShootingSkill")) ~= "number" then
			player:SetAttribute("Beyond90ShootingSkill", FootballActionConfig.Shoot.Skill.Default)
		end
	end
	for _, player in Players:GetPlayers() do
		initializePlayer(player)
	end
	Players.PlayerAdded:Connect(initializePlayer)

	Players.PlayerRemoving:Connect(function(player)
		lastActionAtByPlayer[player] = nil
		preparedShotsByPlayer[player] = nil
	end)
end

return FootballActionService
