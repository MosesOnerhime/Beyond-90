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
local PositionConfig = require(Shared.Config.PositionConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local MatchRulesConfig = require(Shared.Config.MatchRulesConfig)
local FootballTeamEligibility = require(Shared.Football.FootballTeamEligibility)
local PassPlanner = require(Shared.Football.PassPlanner)
local ShotPlanner = require(Shared.Football.ShotPlanner)
local ThrowInPlanner = require(Shared.Football.ThrowInPlanner)
local BallControlService = require(script.Parent.BallControlService)
local FootballerRegistryService = require(script.Parent.FootballerRegistryService)
local GoalService = require(script.Parent.GoalService)
local MatchRulesService = require(script.Parent.MatchRulesService)
local PitchService = require(script.Parent.PitchService)
local RestartService = require(script.Parent.RestartService)

local FootballActionService = {}

local initialized = false
local requestRemote: RemoteEvent? = nil
local feedbackRemote: RemoteEvent? = nil
local developmentShootingSkillRemote: RemoteEvent? = nil
local lastActionAtByPlayer: { [Player]: { [string]: number } } = {}
local nextPassId = 0
local nextShotId = 0
local preparedShotsByPlayer = {}
local lastAIActionAtById = {}

local function getShootingSkill(player: Player): number
	local config = FootballActionConfig.Shoot.Skill
	local value = player:GetAttribute("Beyond90ShootingSkill")
	if typeof(value) ~= "number" then
		value = config.Default
	end
	--[[
		Position shapes the footballer (§43): a forward finishes better than a
		defender. It scales execution quality only -- it never decides whether or
		where to shoot, which stays entirely with the player.
	]]
	value *= PositionConfig.GetSkill(player:GetAttribute(PositionConfig.SlotAttributeName), "Shooting")
	return math.clamp(value, config.Minimum, config.Maximum)
end

local function log(message: string)
	print(string.format("%s[FootballAction] %s", GameConfig.LogPrefix, message))
end

local function warnLog(message: string)
	warn(string.format("%s[FootballAction] %s", GameConfig.LogPrefix, message))
end

--[[
	Is this request a SET PIECE being taken? (§28, §29)

	Returns the taker's footballer record and the restart kind when the player is
	the designated taker and `actionType` is a legal way to take that restart;
	nil otherwise. A restart take skips the possession requirement -- the ball is
	held on its spot, not dribbled -- but gains a much stricter action rule in
	exchange, so it is not a loophole.
]]
--[[
	Where the defending goalkeeper is standing.

	Handed to ShotPlanner so target selection can pick the side of the goal the
	keeper is NOT covering (§68). Assistance with execution, not with the
	decision: the player has already chosen to shoot.
]]
local function getDefendingGoalkeeperPosition(teamId: string?): Vector3?
	if not teamId then
		return nil
	end
	for _, actor in FootballerRegistryService.GetAll() do
		if actor.TeamId ~= nil
			and actor.TeamId ~= teamId
			and actor.Position == "Goalkeeper"
			and actor.RootPart
			and actor.RootPart.Parent
		then
			return actor.RootPart.Position
		end
	end
	return nil
end

--[[
	DEVELOPMENT SHOT INTENSITY (§18).

	A power multiplier for testing, independent of Shooting Skill. Returns 1
	unless a tester has moved the control, so ordinary play is untouched.
]]
local function getShotIntensityScale(player: Player): number
	local config = FootballActionConfig.DevelopmentShotIntensity
	local value = player:GetAttribute(config.AttributeName)
	if typeof(value) ~= "number" then
		return 1
	end
	return math.clamp(value, config.Minimum, config.Maximum) / math.max(config.Reference, 1e-3)
end

--[[
	Apply charge and the development intensity override to a finished plan, and
	record the curve so BallService can integrate it.

	One place, so power can never be applied twice or forgotten on one path.
]]
local function applyShotPower(plan, chargePower: number?, intensityScale: number)
	if typeof(plan.LaunchVelocity) ~= "Vector3" then
		return plan
	end
	local scale = intensityScale
	if typeof(chargePower) == "number" then
		plan.ChargePower = chargePower
		scale *= chargePower
	end
	if scale ~= 1 then
		plan.LaunchVelocity *= scale
		plan.LaunchSpeed = (plan.LaunchSpeed or plan.LaunchVelocity.Magnitude) * scale
		plan.VerticalLaunchSpeed = (plan.VerticalLaunchSpeed or 0) * scale
		plan.HorizontalLaunchSpeed = (plan.HorizontalLaunchSpeed or 0) * scale
		--[[
			Scaling the launch shortens the flight, so the curve must scale with
			it or the ball would bend by a different amount than it was aimed for.
			Time scales as 1/scale, and displacement goes as acceleration x time^2,
			so the acceleration scales as scale^2.
		]]
		if typeof(plan.CurveAcceleration) == "Vector3" then
			plan.CurveAcceleration *= scale * scale
		end
	end
	plan.ShotIntensityScale = intensityScale
	return plan
end

local function getRestartTake(player: Player, actionType: string)
	if not MatchRulesService.IsRestartActive() or not RestartService.IsAwaitingAction() then
		return nil, nil
	end
	local actor = FootballerRegistryService.GetHumanActor(player)
	if not actor then
		return nil, nil
	end
	if not RestartService.IsLegalRestartAction(actor, actionType) then
		return nil, nil
	end
	return actor, RestartService.GetActiveRestartKind()
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
		ReleasePosition = plan and plan.ReleasePosition or nil,
		LaunchVelocity = plan and plan.LaunchVelocity or nil,
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
		ChargePower = plan and plan.ChargePower or 1,
		--[[
			The curve the ball was actually given (§69, §71). The preview must use
			the same vector the server integrates, or the drawn line and the flight
			diverge -- which is exactly the regression §71 exists to prevent.
		]]
		CurveAcceleration = plan and plan.CurveAcceleration or nil,
		IsFinesse = plan and plan.IsFinesse or false,
		ShotIntensityScale = plan and plan.ShotIntensityScale or 1,
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
	if not plan or not plan.SelectedCandidate then
		return 0
	end
	return plan.SelectedCandidate.UserId or plan.SelectedCandidate.FootballerId or 0
end

local function handlePass(player: Player, actionType: string, payload)
	local ball = getFootball()
	local rootPart = getPlayerRoot(player)

	if not ball or not rootPart then
		rejectPass(player, actionType, 0, "passer-character-missing")
		return
	end

	--[[
		A set piece is taken WITHOUT possession: the ball is held on its spot by
		RestartService, so requiring possession here would make a legal kick-off
		impossible. In exchange the restart rules decide whether this action type
		is allowed at all (§29).
	]]
	local restartActor, restartKind = getRestartTake(player, actionType)

	if not restartActor and MatchRulesService.IsRestartActive() then
		rejectPass(player, actionType, 0, "restart-not-yours")
		return
	end

	if not restartActor and not BallControlService.IsControlledBy(player, ball) then
		rejectPass(player, actionType, 0, "passer-no-possession")
		return
	end

	local actionConfig = if actionType == "ThroughPass"
		then FootballActionConfig.ThroughPass
		elseif actionType == "LobPass"
		then FootballActionConfig.LobPass
		else FootballActionConfig.Pass

	local ballDistance = BallControlMath.GetHorizontal(ball.Position - rootPart.Position).Magnitude

	-- A restart taker stands beside the ball rather than controlling it, so the
	-- controlled-ball range test does not apply; the taker radius bounds them.
	local maximumBallDistance = if restartActor
		then MatchRulesConfig.GetTakerMovementRadius(restartKind) + 2
		else BallConfig.Control.HardControlDistance
	if ballDistance > maximumBallDistance then
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

	local receiverActor = FootballerRegistryService.GetActorById(requestedReceiverUserId)
	if not receiverActor then
		rejectPass(player, actionType, requestedReceiverUserId, "receiver-missing")
		return
	end
	local passerTeam = FootballTeamConfig.Normalize(player:GetAttribute(FootballTeamConfig.AttributeName))
	local eligible = receiverActor.Id ~= player.UserId and passerTeam ~= nil and receiverActor.TeamId == passerTeam
	local eligibilityReason = if eligible then "same-team" else "receiver-not-teammate"
	if receiverActor.Player then
		eligible, eligibilityReason = FootballTeamEligibility.AreTeammates(player, receiverActor.Player, FootballActionConfig.Targeting)
	end
	if not eligible then
		rejectPass(player, actionType, requestedReceiverUserId, eligibilityReason)
		return
	end
	local candidate = FootballerRegistryService.CreateCandidate(receiverActor)
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
	plan.ReleasePosition = ball.Position

	nextPassId += 1
	local passId = nextPassId
	local actionContext = {
		PassId = passId,
		IntendedReceiverUserId = getSelectedReceiverUserId(plan),
		IntendedReceiverName = plan.SelectedCandidate and plan.SelectedCandidate.Name or "",
		TargetPosition = plan.TargetPosition,
		TargetKind = plan.SelectedCandidate and plan.SelectedCandidate.Kind or "Space",
		EstimatedArrivalTime = plan.PredictedArrivalTime,
	}

	local released
	if restartActor then
		released = BallControlService.ReleaseForRestart(ball, restartActor, actionType, plan.LaunchVelocity, actionContext)
		if released then
			-- THIS is what restarts the match, not touching the ball.
			MatchRulesService.NotifyRestartAction(restartActor, actionType)
		end
	else
		released = BallControlService.ReleaseForFootballAction(
			ball,
			player,
			actionType,
			plan.LaunchVelocity,
			plan.ReleaseReacquireSuppression,
			plan.ReleaseReacquireExitDistance,
			actionContext
		)
	end

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

-- Is the football physically strikeable by this footballer right now? A shot may
-- only leave the foot when this is true, so a sprint touch that is still out in
-- front of the player defers the strike instead of swinging through nothing.
local function getShotContactState(player: Player, ball: BasePart)
	local contactConfig = FootballActionConfig.Shoot.Contact
	local rootPart = getPlayerRoot(player)
	if not rootPart then
		return "abandon", nil
	end
	local playerVelocity = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity)
	local speed = playerVelocity.Magnitude

	--[[
		WHERE THE FOOT WILL MEET THE BALL.

		Both bodies are moving, so the gap that matters is the gap a fraction of
		a second from now -- which is when the strike actually happens. Running
		onto the ball closes that gap; a ball genuinely running away opens it,
		and this correctly refuses that one.
	]]
	local lookahead = contactConfig.StrikeLookaheadSeconds
	local relativeVelocity = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity) - playerVelocity
	local toBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position) + relativeVelocity * lookahead
	local distance = toBall.Magnitude

	--[[
		The window opens with speed, spanning exactly the range the dribble
		carries the ball across, and comes from the SHARED helper so the client's
		local prediction cannot drift from this decision.
	]]
	local contactRadius, maximumForwardLead, maximumLateral =
		FootballActionConfig.GetShotContactWindow(speed)

	if distance > contactConfig.AbandonDistance then
		return "abandon", rootPart
	end
	--[[
		A BALL IS STRIKEABLE RELATIVE TO THE FOOT, NOT TO THE ROOT'S CENTRE.

		This single comparison is why shooting stopped working entirely --
		standing still, with the ball at the feet, on a stationary pitch.

		It measured the ball against the ROOT CENTRE and allowed
		`MaximumHeight + rootPart.Size.Y` = 1.9 + 2.0 = 3.9 studs. But the root
		centre of a standing footballer sits roughly hip height plus half the
		root above the ground, and once the forced 8.27-stud scaling was removed
		the rig reports hipHeight 4.064 with the root at Y 5.565-5.660. A ball
		resting on the turf has its centre at about 0.975. The gap is therefore
		~4.6 studs against a 3.9 allowance, so the test failed CONSTANTLY:

			playerSpeed=0.00  lead=2.25  phase=Settle  ->  shot-expired

		A ball perfectly at the player's feet, refused. Every shot then either
		waited out its window (`shot-expired`) or had the wait closed under it
		(`shot-contact-lost`).

		The allowance was never really about the root; it is about how high off
		the ground a footballer can strike a ball. So measure it from the SOLE.
		That is what MaximumHeight has always meant, it is scale-independent, and
		it cannot silently break again the next time the rig's proportions change
		-- which is exactly how it broke this time.
	]]
	local humanoid = rootPart.Parent and rootPart.Parent:FindFirstChildOfClass("Humanoid")
	local hipHeight = if humanoid then humanoid.HipHeight else 0
	local soleY = rootPart.Position.Y - hipHeight - rootPart.Size.Y * 0.5
	if ball.Position.Y - soleY > contactConfig.MaximumHeight + BallConfig.Radius then
		return "wait", rootPart
	end
	if distance > contactRadius then
		return "wait", rootPart
	end
	local controlDirection = BallControlMath.SafeUnit(
		playerVelocity,
		BallControlMath.GetHorizontal(rootPart.CFrame.LookVector)
	)
	local forwardLead = toBall:Dot(controlDirection)
	if forwardLead > maximumForwardLead or forwardLead < -contactConfig.MaximumBehindLead then
		return "wait", rootPart
	end
	local lateral = (toBall - controlDirection * forwardLead).Magnitude
	if lateral > maximumLateral then
		return "wait", rootPart
	end
	return "contact", rootPart
end

-- Re-solve the shot from where the football actually is at strike time. Planning
-- at request time and launching up to a touch-cycle later was also the dominant
-- source of local shot-trajectory prediction error.
local function replanPreparedShot(player: Player, prepared)
	local ball = prepared.Ball
	local rootPart = getPlayerRoot(player)
	if not rootPart then
		return prepared.Plan
	end
	local goals = GoalService.GetGoals()
	local goal = goals[prepared.GoalId]
	local defendedGoal = goals[prepared.DefendedGoalId]
	if prepared.Plan.ActionType == "Clearance" or not goal then
		local attackingDirection = if goal and defendedGoal
			then BallControlMath.SafeUnit(
				BallControlMath.GetHorizontal(goal.MouthCenter - defendedGoal.MouthCenter),
				prepared.AimDirection
			)
			else prepared.AimDirection
		local plan = ShotPlanner.PlanClearance(
			ball.Position,
			prepared.AimDirection,
			attackingDirection,
			FootballActionConfig.Shoot
		)
		if plan then
			plan.ClientActionId = prepared.ClientActionId
			plan.ReleasePosition = ball.Position
			applyShotPower(plan, prepared.ChargePower, getShotIntensityScale(player))
		end
		return plan or prepared.Plan
	end
	local teamId = FootballTeamConfig.Normalize(player:GetAttribute(FootballTeamConfig.AttributeName))
	local plan = ShotPlanner.Plan(
		ball.Position,
		prepared.AimDirection,
		goal,
		BallConfig.Radius,
		FootballActionConfig.Shoot,
		getShootingSkill(player),
		rootPart.CFrame.LookVector,
		getDefendingGoalkeeperPosition(teamId),
		prepared.ChargePower
	)
	if not plan then
		return prepared.Plan
	end
	plan.ClientActionId = prepared.ClientActionId
	plan.ReleasePosition = ball.Position
	-- Re-planning solves fresh geometry; re-apply the power chosen at request.
	return applyShotPower(plan, prepared.ChargePower, getShotIntensityScale(player))
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
	local plan = if FootballActionConfig.Shoot.Contact.Enabled == true and ball.Parent
		then replanPreparedShot(player, prepared)
		else prepared.Plan
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
			CurveAcceleration = plan.CurveAcceleration,
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

--[[
	A shot that TAKES a restart -- a penalty, a free kick, or a corner struck at
	goal (§29, §37).

	Deliberately not the prepared-shot flow. That flow exists to wait for the
	football to become strikeable while it is being dribbled; a restart ball is
	already stationary at the taker's feet, so waiting for a contact window that
	is permanently satisfied would only add latency. Everything else -- planning,
	Shooting Skill, charge -- is the ordinary shot path, so a penalty is struck by
	exactly the same rules as a shot from open play.
]]
local function handleRestartShot(player: Player, payload, restartActor, restartKind: string?)
	local ball = getFootball()
	local rootPart = getPlayerRoot(player)
	if not ball or not rootPart then
		sendFeedback(player, false, "shooter-character-missing", nil, "Shoot")
		return
	end
	if not isCooldownReady(player, "Shoot", FootballActionConfig.Shoot.Cooldown) then
		sendFeedback(player, false, "cooldown", nil, "Shoot")
		return
	end

	local goals = GoalService.GetGoals()
	local teamId = FootballTeamConfig.Normalize(player:GetAttribute(FootballTeamConfig.AttributeName))
	local mapping = FootballTeamConfig.GetGoalMapping(teamId)
	local goal = mapping and goals[mapping.AttackingGoalId]
	if not goal then
		sendFeedback(player, false, "goal-unavailable", nil, "Shoot")
		return
	end

	local chargeConfig = FootballActionConfig.Shoot.Charge
	local chargePower = chargeConfig.MaximumPower
	if chargeConfig.Enabled == true then
		local requested = if payload and typeof(payload.ChargePower) == "number" then payload.ChargePower else nil
		if requested then
			chargePower = math.clamp(requested, chargeConfig.MinimumPower, chargeConfig.MaximumPower)
		end
	end

	local aimDirection = getAimDirection(player, payload)
	local plan, reason = ShotPlanner.Plan(
		ball.Position,
		aimDirection,
		goal,
		BallConfig.Radius,
		FootballActionConfig.Shoot,
		getShootingSkill(player),
		rootPart.CFrame.LookVector,
		getDefendingGoalkeeperPosition(teamId),
		chargePower
	)
	if not plan then
		sendFeedback(player, false, reason or "goal-unavailable", nil, "Shoot")
		return
	end
	applyShotPower(plan, chargePower, getShotIntensityScale(player))
	plan.ReleasePosition = ball.Position

	local released = BallControlService.ReleaseForRestart(ball, restartActor, "Shoot", plan.LaunchVelocity, {
		IntendedReceiverUserId = 0,
		TargetPosition = plan.TargetPosition,
		TargetKind = "Goal",
		GoalId = plan.GoalId,
		EstimatedArrivalTime = plan.PredictedArrivalTime,
		CurveAcceleration = plan.CurveAcceleration,
	})
	if not released then
		sendFeedback(player, false, "shot-release-rejected", plan, "Shoot")
		return
	end
	MatchRulesService.NotifyRestartAction(restartActor, "Shoot")
	log(string.format(
		"[RestartShot] restart=%s player=%s goal=%s distance=%.1f launchSpeed=%.1f skill=%.0f result=%s",
		tostring(restartKind),
		player.Name,
		plan.GoalId,
		plan.Distance,
		plan.LaunchSpeed,
		(plan.ShootingSkill or 0) * 100,
		plan.Result or "Released"
	))
	sendFeedback(player, true, "", plan, "Shoot", "Released")
end

local function handleShoot(player: Player, payload)
	local phase = if payload and typeof(payload.Phase) == "string" then payload.Phase else "Prepare"
	local clientActionId = if payload and typeof(payload.ClientActionId) == "string" then payload.ClientActionId else ""
	if phase == "Commit" then
		-- The animation marker supplies timing for an already-valid shot. It may
		-- not decide validity: if the football is not strikeable yet, the contact
		-- wait keeps running and releases on its own terms.
		local prepared = preparedShotsByPlayer[player]
		if prepared and prepared.ClientActionId == clientActionId
			and FootballActionConfig.Shoot.Contact.Enabled == true
		then
			local state = getShotContactState(player, prepared.Ball)
			if state ~= "contact" then
				return
			end
		end
		releasePreparedShot(player, clientActionId, "BallContact-marker")
		return
	end

	local restartActor, restartKind = getRestartTake(player, "Shoot")
	if restartActor then
		handleRestartShot(player, payload, restartActor, restartKind)
		return
	end
	if MatchRulesService.IsRestartActive() then
		sendFeedback(player, false, "restart-not-yours", nil, "Shoot")
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

	local holdDuration = if payload and typeof(payload.HoldDuration) == "number" then payload.HoldDuration else 0
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
	--[[
		Charge is resolved BEFORE planning now, because the plan uses it: a driven
		shot is kept low and does not bend, a placed one is lifted and does
		(§66, §69). It used to be applied afterwards as a bare velocity multiplier,
		which meant power could not influence the shot's shape at all.
	]]
	local chargeConfig = FootballActionConfig.Shoot.Charge
	local chargePower = chargeConfig.MaximumPower
	if chargeConfig.Enabled == true then
		local requested = if payload and typeof(payload.ChargePower) == "number" then payload.ChargePower else nil
		if requested then
			chargePower = math.clamp(requested, chargeConfig.MinimumPower, chargeConfig.MaximumPower)
		else
			-- Fall back to the server's own view of hold duration.
			local span = math.max(chargeConfig.MaximumHoldSeconds - chargeConfig.MinimumHoldSeconds, 1e-4)
			local alpha = math.clamp((holdDuration - chargeConfig.MinimumHoldSeconds) / span, 0, 1) ^ chargeConfig.CurveExponent
			chargePower = chargeConfig.MinimumPower + (chargeConfig.MaximumPower - chargeConfig.MinimumPower) * alpha
		end
	end

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
			rootPart.CFrame.LookVector,
			getDefendingGoalkeeperPosition(teamId),
			chargePower
		)
	end
	if not plan then
		sendFeedback(player, false, reason or "goal-unavailable", nil, "Shoot")
		return
	end
	plan.ReleasePosition = ball.Position
	nextShotId += 1
	if clientActionId == "" then
		clientActionId = string.format("%d:%d", player.UserId, nextShotId)
	end
	plan.ClientActionId = clientActionId

	-- Accuracy stays with Shooting Skill and body alignment: a fully charged
	-- shot is powerful, not precise.
	applyShotPower(plan, chargePower, getShotIntensityScale(player))

	local contactConfig = FootballActionConfig.Shoot.Contact
	preparedShotsByPlayer[player] = {
		ChargePower = chargePower,
		Ball = ball,
		Plan = plan,
		ClientActionId = clientActionId,
		GoalId = goalId,
		DefendedGoalId = mapping.DefendedGoalId,
		AimDirection = aimDirection,
		ExpiresAt = os.clock() + FootballActionConfig.Shoot.PreparedActionLifetime,
	}
	sendFeedback(player, true, "", plan, "Shoot", "Prepared")

	if contactConfig.Enabled ~= true then
		task.delay(FootballActionConfig.Shoot.ContactFallbackTime, function()
			releasePreparedShot(player, clientActionId, "configured-fallback")
		end)
		return
	end

	-- Hold the shot intent until the football is genuinely strikeable. Possession
	-- is retained throughout; only the physical release waits.
	task.spawn(function()
		local startedAt = os.clock()
		local deadline = startedAt + contactConfig.MaximumWaitSeconds
		while true do
			local prepared = preparedShotsByPlayer[player]
			if not prepared or prepared.ClientActionId ~= clientActionId then
				return
			end
			if not ball.Parent or not BallControlService.IsControlledBy(player, ball) then
				preparedShotsByPlayer[player] = nil
				sendFeedback(player, false, "shooter-no-possession", prepared.Plan, "Shoot")
				return
			end
			local state, rootPart = getShotContactState(player, ball)
			if state == "contact" then
				releasePreparedShot(player, clientActionId, string.format(
					"contact-window+%.0fms",
					(os.clock() - startedAt) * 1000
				))
				return
			end
			if state == "abandon" then
				preparedShotsByPlayer[player] = nil
				sendFeedback(player, false, "shot-contact-lost", prepared.Plan, "Shoot")
				log(string.format("[ShotContact] player=%s result=abandoned", player.Name))
				return
			end
			if os.clock() >= deadline then
				-- Bounded timeout. Release anyway so a queued shot can never hang,
				-- but re-plan from the current ball position first.
				releasePreparedShot(player, clientActionId, "contact-timeout")
				return
			end
			-- Bounded orientation assistance toward the football while waiting.
			if rootPart and contactConfig.FacingAssistDegreesPerSecond > 0 then
				local toBall = BallControlMath.GetHorizontal(ball.Position - rootPart.Position)
				if toBall.Magnitude > 0.5 then
					local current = BallControlMath.GetHorizontal(rootPart.CFrame.LookVector)
					local maxStep = math.rad(contactConfig.FacingAssistDegreesPerSecond * contactConfig.PollInterval)
					local blended = BallControlMath.SafeUnit(
						current.Unit:Lerp(toBall.Unit, math.min(maxStep, 1)),
						current
					)
					if blended.Magnitude > 0 then
						rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + blended)
					end
				end
			end
			task.wait(contactConfig.PollInterval)
		end
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
	-- Relative push scales with how fast the footballer is actually travelling.
	-- A flat clamp cannot separate from a sprint, which is why sprint knock-ons
	-- previously stayed under the player's feet.
	local scaling = actionConfig.VelocityScaling
	local minPush, maxPush = actionConfig.MinRelativeForwardSpeed, actionConfig.MaxRelativeForwardSpeed
	if scaling and scaling.Enabled == true then
		local speedAlpha = math.clamp(
			(math.max(playerHorizontalVelocity.Magnitude, initialForwardSpeed) - scaling.LowSpeed)
				/ math.max(scaling.SprintSpeed - scaling.LowSpeed, 1e-4),
			0,
			1
		)
		local scaledPush = scaling.LowRelativePush
			+ (scaling.SprintRelativePush - scaling.LowRelativePush) * speedAlpha
			+ anticipatedPlayerSpeed * scaling.PlayerSpeedCarry
		minPush = scaledPush
		maxPush = math.max(scaledPush, actionConfig.MaxRelativeForwardSpeed)
	end
	local relativePushSpeed = math.clamp(
		math.max(
			requiredForwardSpeed - anticipatedPlayerSpeed,
			minPush + actionConfig.LaunchSpeedPadding
		),
		minPush,
		maxPush
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

	--[[
		A knock-on stays a football the player is chasing, not one they lost.

		The football is genuinely free -- an opponent can win it -- but the
		originator keeps a short priority window so catching up to their own
		touch is a smooth reacquisition rather than a neutral contest.
	]]
	if released then
		local reacquisition = actionConfig.Reacquisition
		if reacquisition then
			BallControlService.RegisterReacquisitionClaim(
				player,
				reacquisition.ClaimSeconds,
				reacquisition.ScoreBonus
			)
		end
	end

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

--[[
	THROW-IN (§32-§35).

	The ball leaves the thrower's hands above their head and travels as a real
	arc to a team-mate. Hold duration chooses how far it is thrown; the player's
	own target selection chooses who it is thrown to.

	`taker` is a footballer record, so a human throw and an AI throw run through
	this identically -- an AI does not get an instant magic restart (§35).
]]
local function executeThrowIn(taker, aimDirection: Vector3, holdDuration: number, selectedReceiverId: number?): (boolean, string)
	local ball = getFootball()
	if not ball or not taker or not taker.RootPart or not taker.RootPart.Parent then
		return false, "thrower-character-missing"
	end
	local config = FootballActionConfig.ThrowIn

	-- The throw genuinely starts overhead, not at the ball's resting height.
	local origin = taker.RootPart.Position + Vector3.yAxis * config.ReleaseHeight

	local candidates = {}
	for _, actor in FootballerRegistryService.GetAll() do
		if actor.Id ~= taker.Id
			and actor.TeamId == taker.TeamId
			and actor.RootPart
			and actor.RootPart.Parent
		then
			table.insert(candidates, {
				Id = actor.Id,
				Name = actor.DisplayName,
				Position = actor.RootPart.Position,
				Velocity = actor.RootPart.AssemblyLinearVelocity,
			})
		end
	end

	local desiredDistance = ThrowInPlanner.GetDesiredDistance(holdDuration, config)
	local receiver = ThrowInPlanner.SelectReceiver(
		origin,
		aimDirection,
		candidates,
		desiredDistance,
		selectedReceiverId,
		config
	)

	local gravity = BallConfig.Flight and BallConfig.Flight.EffectiveGravity or Workspace.Gravity
	local plan, reason
	if receiver then
		plan, reason = ThrowInPlanner.Plan(origin, receiver.Position, receiver.Velocity, config, gravity)
	else
		--[[
			Nobody to aim at. Throwing the ball straight back over the same
			touchline would restart the loop forever, so it goes a short distance
			infield instead.
		]]
		local pitchState = PitchService.GetState()
		local infield = if pitchState
			then BallControlMath.SafeUnit(
				BallControlMath.GetHorizontal(pitchState.Center - ball.Position),
				Vector3.xAxis
			)
			else BallControlMath.SafeUnit(BallControlMath.GetHorizontal(taker.RootPart.CFrame.LookVector), Vector3.zAxis)
		plan, reason = ThrowInPlanner.PlanSafeFallback(origin, infield, config, gravity)
	end

	if not plan then
		return false, reason or "throw-in-unplannable"
	end

	--[[
		The ball is thrown FROM the hands, so it is moved there at release. It is
		never welded: this is a single placement immediately followed by a
		physical launch.
	]]
	ball.CFrame = CFrame.new(origin)

	local released = BallControlService.ReleaseForRestart(ball, taker, "ThrowIn", plan.LaunchVelocity, {
		IntendedReceiverUserId = receiver and receiver.Id or 0,
		IntendedReceiverName = receiver and receiver.Name or "",
		TargetPosition = plan.TargetPosition,
		TargetKind = if receiver then "Player" else "Space",
		EstimatedArrivalTime = plan.PredictedArrivalTime,
	})
	if not released then
		return false, "throw-in-release-rejected"
	end
	MatchRulesService.NotifyRestartAction(taker, "ThrowIn")

	log(string.format(
		"[ThrowIn] thrower=%s receiver=%s hold=%.2fs desired=%.1f actual=%.1f launchSpeed=%.1f vertical=%.1f flight=%.2fs",
		taker.DisplayName,
		receiver and receiver.Name or "(infield)",
		holdDuration,
		desiredDistance,
		plan.Distance,
		plan.LaunchSpeed,
		plan.VerticalLaunchSpeed,
		plan.PredictedArrivalTime
	))
	return true, ""
end

FootballActionService.ExecuteThrowIn = executeThrowIn

local function handleThrowIn(player: Player, payload, taker)
	local holdDuration = if payload and typeof(payload.HoldDuration) == "number" then payload.HoldDuration else 0
	local selectedReceiverId = if payload and typeof(payload.IntendedReceiverUserId) == "number"
		then math.floor(payload.IntendedReceiverUserId)
		else nil
	if selectedReceiverId == 0 then
		selectedReceiverId = nil
	end
	local aimDirection = getAimDirection(player, payload)
	local accepted, reason = executeThrowIn(taker, aimDirection, holdDuration, selectedReceiverId)
	if not accepted then
		sendFeedback(player, false, reason, nil, "ThrowIn")
		return
	end
	sendFeedback(player, true, "", nil, "ThrowIn", "Released")
end

local function onActionRequested(player: Player, payload)
	if typeof(payload) ~= "table" then
		warnLog(string.format("Rejected malformed action payload from %s", player.Name))
		return
	end

	local actionType = payload.ActionType

	--[[
		A throw-in is taken with the Pass input, because there is no separate
		throw button and adding one would break input parity across keyboard,
		gamepad and touch. The mapping is done HERE rather than on the client so
		that a client cannot decide for itself that a kick is a throw (§29).
	]]
	if (actionType == "GroundPass" or actionType == "ThroughPass" or actionType == "LobPass")
		and RestartService.GetActiveRestartKind() == MatchRulesConfig.Restarts.ThrowIn
	then
		local taker = getRestartTake(player, "ThrowIn")
		if taker then
			handleThrowIn(player, payload, taker)
			return
		end
	end

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

local function isAIActionReady(actor, actionType: string, cooldown: number): boolean
	local now = os.clock()
	local times = lastAIActionAtById[actor.Id]
	if not times then
		times = {}
		lastAIActionAtById[actor.Id] = times
	end
	local previous = times[actionType]
	if previous and now - previous < cooldown then
		return false
	end
	times[actionType] = now
	return true
end

function FootballActionService.ExecuteAIPass(actor, receiverActor, actionType: string?): (boolean, any)
	local ball = getFootball()
	local selectedActionType = actionType or "GroundPass"
	if not ball or not actor or not receiverActor or actor.TeamId ~= receiverActor.TeamId then
		return false, "invalid-AI-pass-context"
	end
	if not BallControlService.IsControlledByAI(actor, ball) then
		return false, "AI-passer-no-possession"
	end
	local candidate = FootballerRegistryService.CreateCandidate(receiverActor)
	if not candidate then
		return false, "AI-receiver-unavailable"
	end
	local actionConfig = if selectedActionType == "ThroughPass"
		then FootballActionConfig.ThroughPass
		elseif selectedActionType == "LobPass"
		then FootballActionConfig.LobPass
		else FootballActionConfig.Pass
	if not isAIActionReady(actor, selectedActionType, actionConfig.Cooldown) then
		return false, "AI-action-cooldown"
	end
	local aimDirection = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(candidate.Position - ball.Position),
		actor.RootPart.CFrame.LookVector
	)
	local plan, reason = PassPlanner.PlanForReceiver(
		ball.Position,
		aimDirection,
		0,
		selectedActionType,
		candidate,
		FootballActionConfig,
		1,
		FootballActionConfig.Targeting.RetentionConeDegrees
	)
	if not plan then
		return false, reason or "AI-pass-plan-failed"
	end
	plan.ReleasePosition = ball.Position
	nextPassId += 1
	local released = BallControlService.ReleaseAIForFootballAction(ball, actor, selectedActionType, plan.LaunchVelocity, {
		PassId = nextPassId,
		IntendedReceiverUserId = receiverActor.Id,
		IntendedReceiverName = receiverActor.DisplayName,
		TargetPosition = plan.TargetPosition,
		TargetKind = receiverActor.Kind,
		EstimatedArrivalTime = plan.PredictedArrivalTime,
	})
	if not released then
		return false, "AI-pass-release-rejected"
	end
	log(string.format(
		"[AIPass] passer=%s receiver=%s type=%s distance=%.1f launchSpeed=%.1f eta=%.2f",
		actor.DisplayName,
		receiverActor.DisplayName,
		selectedActionType,
		plan.Distance,
		plan.LaunchSpeed,
		plan.PredictedArrivalTime
	))
	return true, plan
end

function FootballActionService.ExecuteAIShot(actor, clearance: boolean?): (boolean, any)
	local ball = getFootball()
	if not ball or not actor or not BallControlService.IsControlledByAI(actor, ball) then
		return false, "AI-shooter-no-possession"
	end
	if not isAIActionReady(actor, "Shoot", FootballActionConfig.Shoot.Cooldown) then
		return false, "AI-action-cooldown"
	end
	local mapping = FootballTeamConfig.GetGoalMapping(actor.TeamId)
	local goals = GoalService.GetGoals()
	local attackingGoal = mapping and goals[mapping.AttackingGoalId]
	local defendedGoal = mapping and goals[mapping.DefendedGoalId]
	if not attackingGoal or not defendedGoal then
		return false, "AI-goal-unavailable"
	end
	local attackingDirection = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(attackingGoal.MouthCenter - defendedGoal.MouthCenter),
		actor.RootPart.CFrame.LookVector
	)
	local plan, reason
	if clearance then
		plan = ShotPlanner.PlanClearance(ball.Position, attackingDirection, attackingDirection, FootballActionConfig.Shoot)
	else
		plan, reason = ShotPlanner.Plan(
			ball.Position,
			attackingGoal.MouthCenter - ball.Position,
			attackingGoal,
			BallConfig.Radius,
			FootballActionConfig.Shoot,
			actor.ShootingSkill or FootballActionConfig.Shoot.Skill.Default,
			actor.RootPart.CFrame.LookVector
		)
	end
	if not plan then
		return false, reason or "AI-shot-plan-failed"
	end
	plan.ReleasePosition = ball.Position
	local released = BallControlService.ReleaseAIForFootballAction(ball, actor, plan.ActionType, plan.LaunchVelocity, {
		TargetPosition = plan.TargetPosition,
		TargetKind = if clearance then "Space" else "Goal",
		GoalId = plan.GoalId,
		EstimatedArrivalTime = plan.PredictedArrivalTime,
		CurveAcceleration = plan.CurveAcceleration,
	})
	if not released then
		return false, "AI-shot-release-rejected"
	end
	log(string.format(
		"[AIShot] player=%s type=%s goal=%s distance=%.1f launchSpeed=%.1f eta=%.2f result=%s",
		actor.DisplayName,
		plan.ActionType,
		plan.GoalId,
		plan.Distance,
		plan.LaunchSpeed,
		plan.PredictedArrivalTime,
		plan.Result or "Released"
	))
	return true, plan
end

--[[
	AI TAKES A SET PIECE (§80).

	The AI chooses the football decision -- which team-mate, how hard, whether to
	shoot -- and then executes it through exactly the same restart release a human
	uses. There is deliberately no bot-only shortcut: an AI kick-off is a pass, an
	AI throw-in is a throw, an AI penalty is a shot, and each of them completes the
	restart only because MatchRulesService accepted the action as legal.

	Returns (taken, reason).
]]
function FootballActionService.ExecuteAIRestart(actor, restartKind: string): (boolean, string)
	local ball = getFootball()
	if not ball or not actor or not actor.RootPart or not actor.RootPart.Parent then
		return false, "AI-restart-invalid-taker"
	end
	if not RestartService.IsAwaitingAction() then
		return false, "restart-not-ready"
	end
	if not RestartService.IsAuthorizedTaker(actor) then
		return false, "not-the-taker"
	end

	local restarts = MatchRulesConfig.Restarts

	-- A throw-in is thrown. Distance is chosen from the available team-mates
	-- rather than from a hold, since an AI has no button to hold.
	if restartKind == restarts.ThrowIn then
		local aim = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector),
			Vector3.zAxis
		)
		-- Mid-range hold: a sensible default throw rather than always short or long.
		local hold = FootballActionConfig.ThrowIn.HoldMaxTime * 0.45
		return executeThrowIn(actor, aim, hold, nil)
	end

	-- A penalty is a shot, and only a shot.
	if restartKind == restarts.Penalty then
		local accepted = FootballActionService.ExecuteRestartShot(actor)
		return accepted, if accepted then "" else "AI-penalty-shot-failed"
	end

	--[[
		Everything else is played to a team-mate. The AI picks the best available
		receiver by the same "furthest forward that is still reachable" reasoning
		it uses in open play, rather than simply the nearest body.
	]]
	local mapping = FootballTeamConfig.GetGoalMapping(actor.TeamId)
	local goals = GoalService.GetGoals()
	local attackingGoal = mapping and goals[mapping.AttackingGoalId]

	--[[
		A goal kick is played long; everything else is played on the ground. This
		is a football decision, so it belongs to the AI rather than to the restart
		rules -- both action types are legal for a goal kick.
	]]
	--[[
		A goal kick is hit long and a corner is CROSSED; everything else is played
		on the ground. Both are legal for their restart, so this is the AI making a
		football decision rather than the rules dictating one.

		The corner mattered in testing: played as a ground pass it used the ground
		pass's 88-stud range, and from a corner flag in a 3v3 there is frequently
		nobody inside that -- so the restart fell through to a clearance. A cross
		reaches the far post, which is what a corner is for.
	]]
	local actionType = if restartKind == restarts.GoalKick or restartKind == restarts.CornerKick
		then "LobPass"
		else "GroundPass"
	local actionConfig = if actionType == "LobPass" then FootballActionConfig.LobPass else FootballActionConfig.Pass

	--[[
		Range must come from the action actually being played. Using the ground
		pass's 88-stud limit for a LOB from the keeper's own goal line meant a
		goal kick could find nobody at all, and the restart was abandoned rather
		than taken.
	]]
	local best, bestScore = nil, -math.huge
	for _, candidate in FootballerRegistryService.GetAll() do
		if candidate.Id ~= actor.Id
			and candidate.TeamId == actor.TeamId
			and candidate.RootPart
			and candidate.RootPart.Parent
		then
			local distance = BallControlMath.GetHorizontal(candidate.RootPart.Position - ball.Position).Magnitude
			if distance >= actionConfig.MinDistance and distance <= actionConfig.MaxDistance then
				-- Prefer a team-mate who is forward, but not one so far away the
				-- pass has no chance of arriving.
				local progress = if attackingGoal
					then -BallControlMath.GetHorizontal(candidate.RootPart.Position - attackingGoal.MouthCenter).Magnitude
					else 0
				local score = progress * 0.02 - distance * 0.01
				if score > bestScore then
					best, bestScore = candidate, score
				end
			end
		end
	end

	--[[
		NOBODY IN RANGE.

		A restart must still be taken. A real keeper with no option simply hits it
		long, so the ball is cleared upfield through the ordinary clearance
		planner rather than the restart being abandoned and play resuming with a
		dead ball on the six-yard line.
	]]
	if not best then
		local defendedGoal = mapping and goals[mapping.DefendedGoalId]
		if not attackingGoal or not defendedGoal then
			return false, "AI-restart-no-receiver"
		end
		local upfield = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(attackingGoal.MouthCenter - defendedGoal.MouthCenter),
			actor.RootPart.CFrame.LookVector
		)
		local plan = ShotPlanner.PlanClearance(ball.Position, upfield, upfield, FootballActionConfig.Shoot)
		if not plan then
			return false, "AI-restart-no-receiver"
		end
		local released = BallControlService.ReleaseForRestart(ball, actor, actionType, plan.LaunchVelocity, {
			TargetPosition = plan.TargetPosition,
			TargetKind = "Space",
			EstimatedArrivalTime = plan.PredictedArrivalTime,
		})
		if not released or not MatchRulesService.NotifyRestartAction(actor, actionType) then
			return false, "AI-restart-clearance-rejected"
		end
		log(string.format("[AIRestart] %s cleared upfield by %s (no receiver in range)", restartKind, actor.DisplayName))
		return true, ""
	end

	local candidate = FootballerRegistryService.CreateCandidate(best)
	if not candidate then
		return false, "AI-restart-receiver-unavailable"
	end

	local aimDirection = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(candidate.Position - ball.Position),
		actor.RootPart.CFrame.LookVector
	)
	local plan, reason = PassPlanner.PlanForReceiver(
		ball.Position,
		aimDirection,
		0,
		actionType,
		candidate,
		FootballActionConfig,
		1,
		FootballActionConfig.Targeting.RetentionConeDegrees
	)
	if not plan then
		return false, reason or "AI-restart-plan-failed"
	end

	nextPassId += 1
	local released = BallControlService.ReleaseForRestart(ball, actor, actionType, plan.LaunchVelocity, {
		PassId = nextPassId,
		IntendedReceiverUserId = best.Id,
		IntendedReceiverName = best.DisplayName,
		TargetPosition = plan.TargetPosition,
		TargetKind = "Player",
		EstimatedArrivalTime = plan.PredictedArrivalTime,
	})
	if not released then
		return false, "AI-restart-release-rejected"
	end
	if not MatchRulesService.NotifyRestartAction(actor, actionType) then
		return false, "AI-restart-action-rejected"
	end

	log(string.format(
		"[AIRestart] %s taken by %s -> %s (%s, %.1f studs)",
		restartKind,
		actor.DisplayName,
		best.DisplayName,
		actionType,
		plan.Distance
	))
	return true, ""
end

--[[
	A shot that takes a restart, for an AI taker. Shares ShotPlanner with the
	human path so a bot penalty is struck by the same model as a human one.
]]
function FootballActionService.ExecuteRestartShot(actor): boolean
	local ball = getFootball()
	local mapping = FootballTeamConfig.GetGoalMapping(actor.TeamId)
	local goals = GoalService.GetGoals()
	local goal = mapping and goals[mapping.AttackingGoalId]
	if not ball or not goal or not actor.RootPart then
		return false
	end
	local plan = ShotPlanner.Plan(
		ball.Position,
		goal.MouthCenter - ball.Position,
		goal,
		BallConfig.Radius,
		FootballActionConfig.Shoot,
		actor.ShootingSkill or FootballActionConfig.Shoot.Skill.Default,
		actor.RootPart.CFrame.LookVector
	)
	if not plan then
		return false
	end
	local released = BallControlService.ReleaseForRestart(ball, actor, "Shoot", plan.LaunchVelocity, {
		TargetPosition = plan.TargetPosition,
		TargetKind = "Goal",
		GoalId = plan.GoalId,
		EstimatedArrivalTime = plan.PredictedArrivalTime,
		CurveAcceleration = plan.CurveAcceleration,
	})
	if not released then
		return false
	end
	return MatchRulesService.NotifyRestartAction(actor, "Shoot")
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
