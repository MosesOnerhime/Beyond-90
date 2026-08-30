local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AIConfig = require(Shared.Config.AIConfig)
local BallConfig = require(Shared.Config.BallConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local DefendingConfig = require(Shared.Config.DefendingConfig)
local GoalkeeperConfig = require(Shared.Config.GoalkeeperConfig)
local PositionConfig = require(Shared.Config.PositionConfig)
local MatchRulesConfig = require(Shared.Config.MatchRulesConfig)
local OffsideEvaluator = require(Shared.Football.OffsideEvaluator)
local PitchGeometry = require(Shared.Football.PitchGeometry)
local SetPieceFormation = require(Shared.Football.SetPieceFormation)
local MatchConfig = require(Shared.Config.MatchConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local AITacticalEvaluator = require(Shared.Football.AITacticalEvaluator)
local TrajectoryPredictor = require(Shared.Football.TrajectoryPredictor)

local AIAnimationService = require(script.Parent.AIAnimationService)
local BallService = require(script.Parent.BallService)
local BallControlService = require(script.Parent.BallControlService)
local CharacterAppearanceService = require(script.Parent.CharacterAppearanceService)
local FootballActionService = require(script.Parent.FootballActionService)
local FootballerRegistryService = require(script.Parent.FootballerRegistryService)
local GoalService = require(script.Parent.GoalService)
local GoalkeeperService = require(script.Parent.GoalkeeperService)
local DefendingService = require(script.Parent.DefendingService)
local MatchService = require(script.Parent.MatchService)
local MatchRulesService = require(script.Parent.MatchRulesService)
local PositionService = require(script.Parent.PositionService)
local RestartService = require(script.Parent.RestartService)
local InjuryService = require(script.Parent.InjuryService)
local StaminaService = require(script.Parent.StaminaService)
local PlayerService = require(script.Parent.PlayerService)

local AIService = {}

local active = false
local initialized = false
local ball: BasePart? = nil
local pitchState = nil
local heartbeatConnection: RBXScriptConnection? = nil
local goalConnection: RBXScriptConnection? = nil
local aiActors = {}
local aiKeepers = {}
-- Human-controlled goalkeepers. Registered with GoalkeeperService like any
-- keeper, but never driven, repositioned or destroyed by the AI code paths.
local humanKeepers = {}
local teams = {}
local perceptionAccumulator = 0
local teamAccumulator = 0
local individualAccumulator = 0
local movementAccumulator = 0
local debugAccumulator = 0
local lastControllerId = 0
local lastPossessionChangedAt = 0
local outOfPlaySince: number? = nil
local loggedCharacterSource = false

local tryAITackle
local roleOrder = { "Defender", "Support", "Forward" }
local humanRoleOrder = { "Support", "Defender", "Forward" }

local function log(message: string)
	print(string.format("%s[AI] %s", GameConfig.LogPrefix, message))
end

local function getTeamId(actor): string?
	if actor.IsAI then
		return actor.TeamId
	end
	return FootballTeamConfig.Normalize(actor.Player:GetAttribute(FootballTeamConfig.AttributeName))
end

local function refreshActor(actor): boolean
	if actor.IsAI then
		return actor.Character ~= nil and actor.Character.Parent ~= nil and actor.Humanoid.Health > 0
	end
	local refreshed = FootballerRegistryService.GetHumanActor(actor.Player)
	if not refreshed then
		return false
	end
	actor.Character = refreshed.Character
	actor.Humanoid = refreshed.Humanoid
	actor.RootPart = refreshed.RootPart
	actor.TeamId = refreshed.TeamId
	return true
end

local function getGoalsForTeam(teamId: string)
	local mapping = FootballTeamConfig.GetGoalMapping(teamId)
	local goals = GoalService.GetGoals()
	return mapping and goals[mapping.DefendedGoalId], mapping and goals[mapping.AttackingGoalId]
end

local function getAxes(teamId: string)
	local defendedGoal, attackingGoal = getGoalsForTeam(teamId)
	local attackDirection = if defendedGoal and attackingGoal
		then BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(attackingGoal.MouthCenter - defendedGoal.MouthCenter),
			pitchState.LengthAxis
		)
		else pitchState.LengthAxis
	local lateralAxis = BallControlMath.SafeUnit(Vector3.yAxis:Cross(attackDirection), pitchState.WidthAxis)
	return attackDirection, lateralAxis
end

local function clampToPitch(position: Vector3): Vector3
	local offset = BallControlMath.GetHorizontal(position - pitchState.Center)
	local lengthLimit = math.max(pitchState.Length * 0.5 - AIConfig.Locomotion.PitchBoundaryMargin, 1)
	local widthLimit = math.max(pitchState.Width * 0.5 - AIConfig.Locomotion.PitchBoundaryMargin, 1)
	local length = math.clamp(offset:Dot(pitchState.LengthAxis), -lengthLimit, lengthLimit)
	local width = math.clamp(offset:Dot(pitchState.WidthAxis), -widthLimit, widthLimit)
	return pitchState.Center + pitchState.LengthAxis * length + pitchState.WidthAxis * width
		+ Vector3.yAxis * (pitchState.GroundY - pitchState.Center.Y)
end

--[[
	The anchor and behaviour profile for a footballer's position.

	PositionConfig is the single source: the same anchor drives normal formation
	shape here and set-piece placement in RestartService, so a defender is a
	defender in both.
]]
local function getPositionProfile(actor)
	local position = PositionConfig.Get(actor.PositionSlotId)
	if not position then
		for _, candidate in PositionConfig.Positions do
			if candidate.AIRole == actor.Role then
				position = candidate
				break
			end
		end
	end
	return position
end

--[[
	Offside awareness (§63).

	An attacking AI holds its run just behind the opponents' offside line rather
	than running through it. Deliberately imperfect: the discipline is scaled by
	the position's run willingness and leaves a small margin, so AI still strays
	offside occasionally instead of behaving like an invisible wall.
]]
local function clampTargetForOffside(actor, teamModel, target: Vector3): Vector3
	local config = MatchRulesConfig.Offside
	if config.Enabled ~= true or not ball then
		return target
	end
	local teamId = actor.TeamId
	if not teamId then
		return target
	end

	local frame = RestartService.GetTeamFrame(teamId)
	if not frame then
		return target
	end

	local opponents = {}
	local opponentTeam = teams[if teamId == "Home" then "Away" else "Home"]
	if opponentTeam then
		for _, opponent in opponentTeam.Actors do
			if opponent.RootPart and opponent.RootPart.Parent then
				table.insert(opponents, { Id = opponent.Id, Position = opponent.RootPart.Position })
			end
		end
	end
	for _, keeper in aiKeepers do
		if keeper.TeamId ~= teamId and keeper.RootPart and keeper.RootPart.Parent then
			table.insert(opponents, { Id = keeper.Id, Position = keeper.RootPart.Position })
		end
	end

	local line = OffsideEvaluator.GetOffsideLine(frame, opponents, ball.Position)
	if not line then
		return target
	end

	local targetLongitudinal, targetLateral = PitchGeometry.ToNormalized(frame, target)
	-- Hold a little behind the line; the margin is what allows honest mistakes.
	local limit = line - config.RelaxRatio * 4
	if targetLongitudinal <= limit then
		return target
	end

	return PitchGeometry.FromNormalized(frame, limit, targetLateral, target.Y - frame.GroundY)
end

local function getFormationTarget(actor, teamModel): Vector3
	local position = getPositionProfile(actor)
	local role = if position
		then { Longitudinal = position.Anchor.Longitudinal, Lateral = position.Anchor.Lateral }
		else (AIConfig.Formation.Roles[actor.Role] or AIConfig.Formation.Roles.Support)
	local profile = position and position.AI
	local attackDirection, lateralAxis = getAxes(actor.TeamId)
	local ballOffset = BallControlMath.GetHorizontal(teamModel.PerceivedBallPosition - pitchState.Center)
	local ballLongitudinal = math.clamp(
		ballOffset:Dot(attackDirection) / math.max(pitchState.Length * 0.5, 1),
		-1,
		1
	)
	local ballLateral = math.clamp(
		ballOffset:Dot(lateralAxis) / math.max(pitchState.Width * 0.5, 1),
		-1,
		1
	)
	--[[
		How far the ball drags a footballer off its anchor is a property of the
		position (§44): a forward chases the play, a defender holds its line.
		HoldShape 1 means the anchor is absolute, 0 means follow the ball freely.
	]]
	local hold = if profile then math.clamp(profile.HoldShape, 0, 1) else 0.5
	local ballShift = AIConfig.Formation.BallShift * (1 - hold * 0.7)
	local longitudinal = role.Longitudinal + ballLongitudinal * ballShift

	if teamModel.State == "InPossession" then
		-- Only positions willing to break forward actually do.
		local runWillingness = if profile then math.clamp(profile.RunWillingness, 0, 1) else 0.5
		longitudinal += AIConfig.Formation.PossessionAdvance * (0.4 + runWillingness)
	elseif teamModel.State == "OutOfPossession" then
		longitudinal -= AIConfig.Formation.DefensiveRetreat
	end

	-- A position may never abandon its band entirely.
	if profile then
		longitudinal = math.clamp(longitudinal, profile.MaximumRetreat, profile.MaximumAdvance)
	end

	local lateral = role.Lateral + ballLateral * 0.12
	local target = pitchState.Center
		+ attackDirection * (longitudinal * pitchState.Length * AIConfig.Formation.LongitudinalScale)
		+ lateralAxis * (lateral * pitchState.Width * AIConfig.Formation.WidthScale)

	-- Only a footballer actually breaking forward can be caught offside.
	if teamModel.State == "InPossession" and profile and profile.RunWillingness > 0.5 then
		target = clampTargetForOffside(actor, teamModel, target)
	end

	return clampToPitch(target)
end

local function predictBallPosition(timeSeconds: number): Vector3
	if not ball then
		return pitchState.Center
	end
	if ball:GetAttribute("FootballGrounded") == true then
		return clampToPitch(ball.Position + BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity) * timeSeconds * 0.82)
	end
	return clampToPitch(TrajectoryPredictor.SamplePosition(ball.Position, ball.AssemblyLinearVelocity, timeSeconds))
end

local function estimateTimeToPoint(actor, point: Vector3): number
	local distance = BallControlMath.GetHorizontal(point - actor.RootPart.Position).Magnitude
	local currentSpeed = BallControlMath.GetHorizontal(actor.RootPart.AssemblyLinearVelocity).Magnitude
	local effectiveSpeed = math.max(AIConfig.Locomotion.JogSpeed, currentSpeed, AIConfig.Locomotion.SprintSpeed * 0.75)
	return AIConfig.Cadence.ReactionDelay + distance / effectiveSpeed
end

local function estimateTimeToBall(actor): (number, Vector3)
	local bestTime = math.huge
	local bestPoint = ball and ball.Position or pitchState.Center
	for _, predictionTime in AIConfig.LooseBall.PredictionTimes do
		local point = predictBallPosition(predictionTime)
		local reachTime = estimateTimeToPoint(actor, point)
		local scoreTime = math.max(reachTime, predictionTime)
		if scoreTime < bestTime then
			bestTime = scoreTime
			bestPoint = point
		end
	end
	return bestTime, bestPoint
end

local function getControllerActor()
	if not ball or ball:GetAttribute("State") ~= "Controlled" then
		return nil
	end
	local id = ball:GetAttribute("ControllerFootballerId")
	return if typeof(id) == "number" then FootballerRegistryService.GetActorById(id) else nil
end

local function setTeamState(teamModel, requestedState: string, now: number, immediate: boolean?)
	if teamModel.State == requestedState then
		teamModel.PendingState = nil
		return
	end
	-- Winning the ball is unambiguous and authoritative; making the team wait
	-- out a reaction delay before admitting it has possession left the carrier's
	-- own teammates chasing a ball their side already controlled.
	if immediate then
		teamModel.State = requestedState
		teamModel.PendingState = nil
		return
	end
	if teamModel.PendingState ~= requestedState then
		teamModel.PendingState = requestedState
		teamModel.PendingSince = now
		return
	end
	if now - teamModel.PendingSince >= AIConfig.Cadence.ReactionDelay then
		teamModel.State = requestedState
		teamModel.PendingState = nil
	end
end

--[[
	Where a presser should actually run to.

	Sending the defender at the carrier's exact position means it arrives from
	whichever side it happened to start on -- almost always behind a carrier who
	is running away. Every such challenge is then correctly thrown out by the
	tackle evaluator as `challenge-from-behind` or `not-facing-contest`, so the
	AI pressed constantly and never won the ball.

	Defending goal-side instead: aim for a point a short standoff in front of
	the carrier on the line toward the goal being defended. The defender arrives
	between carrier and goal, facing the challenge, which is both how defending
	actually works and the geometry the evaluator is looking for.
]]
--[[
	Where the presser actually runs (§38, §39).

	The previous version aimed a short distance goal-side of the carrier, which is
	the right IDEA but produced the wrong behaviour when the defender was already
	behind: it routed straight THROUGH the carrier's back, which is both a foul
	and the body-clipping the playtest showed.

	A defender now reasons about the situation before choosing a point:

	    BEHIND the carrier
	        -> do not challenge. Run a RECOVERY line to a point goal-side of
	           where the carrier is heading, and only engage once in front.

	    GOAL-SIDE already
	        -> contain. Close the remaining gap, offset to the ball side so the
	           approach is angled rather than head-on into the carrier's chest.

	    SQUARE / arriving
	        -> take the interception point on the carrier's path rather than the
	           carrier's current position, so the defender arrives where the
	           carrier will be.

	Every branch targets a point that is NOT the carrier's root, which is what
	removes root-to-root overlap without making footballers pass through each
	other.
]]
local function getPressTarget(actor, targetActor, dwellSeconds: number?): Vector3
	local carrierPosition = targetActor.RootPart.Position
	local defendedGoal = getGoalsForTeam(actor.TeamId)
	if not defendedGoal then
		return carrierPosition
	end

	local toGoal = BallControlMath.GetHorizontal(defendedGoal.MouthCenter - carrierPosition)
	if toGoal.Magnitude <= 1e-3 then
		return carrierPosition
	end
	local goalDirection = toGoal.Unit
	local defending = AIConfig.Defending

	--[[
		Where the carrier is going. Their velocity is a better predictor than
		their facing while they are actually running, and their facing is the
		better one while they are nearly stationary.
	]]
	local carrierVelocity = BallControlMath.GetHorizontal(targetActor.RootPart.AssemblyLinearVelocity)
	local carrierHeading = if carrierVelocity.Magnitude > 3
		then carrierVelocity.Unit
		else BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(targetActor.RootPart.CFrame.LookVector),
			goalDirection
		)

	local fromCarrier = BallControlMath.GetHorizontal(actor.RootPart.Position - carrierPosition)
	local distance = fromCarrier.Magnitude
	local approach = BallControlMath.SafeUnit(fromCarrier, -goalDirection)

	--[[
		HOW TIGHT IS THIS PRESS? (see AIConfig.Defending, "containment must
		eventually become a challenge")

		Full standoff against a carrier at speed -- that is a jockey, and backing
		off is the right answer. Step right in against one who is standing still,
		because there is nothing to be beaten by.
	]]
	local carrierSpeed = carrierVelocity.Magnitude
	local containAlpha = math.clamp(carrierSpeed / math.max(defending.ContainSpeed, 1e-3), 0, 1)
	local standoffDistance = defending.StepInStandoff
		+ (defending.PressStandoff - defending.StepInStandoff) * containAlpha

	--[[
		DWELL: the carrier has been contained long enough. Go and get the ball.

		Aiming at the football rather than at a point relative to the carrier is
		what actually puts the defender inside tackle range; the challenge itself
		is still decided by the ordinary evaluation, so this creates the
		OPPORTUNITY to tackle rather than a tackle.
	]]
	if ball and dwellSeconds and dwellSeconds >= defending.CommitAfterSeconds then
		return Vector3.new(ball.Position.X, carrierPosition.Y, ball.Position.Z)
	end

	-- Positive when the defender is on the goal side of the carrier.
	local goalSide = fromCarrier:Dot(goalDirection)
	-- Positive when the defender is behind the carrier's direction of travel.
	local behind = -approach:Dot(carrierHeading)

	--[[
		BEHIND: recover, do not challenge.

		Aim well down the carrier's path toward goal so the defender runs a
		curved recovery line and re-enters play in front, rather than chasing
		into the back of a footballer it can never legally tackle.
	]]
	if goalSide < 0 and behind > defending.BehindRecoveryDot then
		local lead = math.clamp(distance * defending.RecoveryLeadScale, defending.MinimumRecoveryLead, defending.MaximumRecoveryLead)
		local recoveryPoint = carrierPosition + carrierHeading * lead + goalDirection * defending.PressStandoff
		--[[
			Bias the recovery to whichever side the defender is already on. Cutting
			across the carrier to reach the "ideal" side is exactly the path that
			runs through them.
		]]
		local lateralAxis = Vector3.new(-goalDirection.Z, 0, goalDirection.X)
		local side = if fromCarrier:Dot(lateralAxis) >= 0 then 1 else -1
		return recoveryPoint + lateralAxis * (side * defending.RecoveryLateralOffset)
	end

	--[[
		GOAL-SIDE: contain from an angle.

		Approaching exactly along the goal line puts the defender chest-to-chest;
		a small ball-side offset keeps the challenge legal and stops the two
		root parts trying to occupy the same space.
	]]
	local lateralAxis = Vector3.new(-goalDirection.Z, 0, goalDirection.X)
	local side = if fromCarrier:Dot(lateralAxis) >= 0 then 1 else -1
	local lateralOffset = lateralAxis * (side * defending.ContainLateralOffset)

	if goalSide > 0 then
		-- Already in front: close the gap without over-running the carrier.
		local standoff = math.min(standoffDistance, goalSide)
		return carrierPosition + goalDirection * standoff + lateralOffset
	end

	--[[
		SQUARE: intercept where the carrier is going.

		Estimate how long the defender needs, and aim at the carrier's position at
		that time rather than at where they are now.
	]]
	local closingSpeed = math.max(AIConfig.Locomotion.SprintSpeed, 1)
	local timeToArrive = math.clamp(distance / closingSpeed, 0, defending.MaximumInterceptLead)
	local predicted = carrierPosition + carrierVelocity * timeToArrive
	return predicted + goalDirection * standoffDistance + lateralOffset
end

--[[
	Where the SECOND defender stands.

	Behind and across from the first, so the two of them cover the ball and the
	way past it rather than standing on the same blade of grass. Support only --
	this defender does not challenge.
]]
local function getSupportPressTarget(actor, targetActor, primaryTarget: Vector3): Vector3
	local support = AIConfig.Defending.SupportPress
	local carrierPosition = targetActor.RootPart.Position
	local defendedGoal = getGoalsForTeam(actor.TeamId)
	if not defendedGoal then
		return carrierPosition
	end
	local toGoal = BallControlMath.GetHorizontal(defendedGoal.MouthCenter - carrierPosition)
	if toGoal.Magnitude <= 1e-3 then
		return carrierPosition
	end
	local goalDirection = toGoal.Unit
	local lateralAxis = Vector3.new(-goalDirection.Z, 0, goalDirection.X)
	-- Opposite side to the first presser, so between them both ways out are
	-- covered rather than one being doubled up.
	local primarySide = if (primaryTarget - carrierPosition):Dot(lateralAxis) >= 0 then 1 else -1
	return carrierPosition
		+ goalDirection * support.Standoff
		- lateralAxis * (primarySide * support.LateralOffset)
end

local function chooseDesignatedPlayer(teamModel, targetActor)
	local bestActor = nil
	local bestTime = math.huge
	local bestPoint = teamModel.PerceivedBallPosition
	local secondActor = nil
	local secondTime = math.huge

	--[[
		DWELL: how long has this team been containing THIS carrier?

		Reset whenever the carrier changes, so pressure earned against one player
		is not inherited by the next. It only accumulates while a presser is
		genuinely engaged -- a defender still sprinting in from thirty studs is
		not containing anybody, and letting that count would make the escalation
		fire before anyone had arrived.
	]]
	local now = os.clock()
	local carrierId = targetActor and targetActor.Id or 0
	if teamModel.PressCarrierId ~= carrierId then
		teamModel.PressCarrierId = carrierId
		teamModel.PressEngagedSince = nil
	end
	local dwellSeconds = 0
	if targetActor then
		local engaged = false
		for _, actor in teamModel.Actors do
			if actor.IsAI and refreshActor(actor) then
				local gap = BallControlMath.GetHorizontal(
					actor.RootPart.Position - targetActor.RootPart.Position
				).Magnitude
				if gap <= AIConfig.Defending.DwellEngageDistance then
					engaged = true
					break
				end
			end
		end
		if engaged then
			teamModel.PressEngagedSince = teamModel.PressEngagedSince or now
			dwellSeconds = now - teamModel.PressEngagedSince
		else
			teamModel.PressEngagedSince = nil
		end
	end
	teamModel.PressDwellSeconds = dwellSeconds

	for _, actor in teamModel.Actors do
		if refreshActor(actor) then
			local time, point
			if targetActor then
				point = getPressTarget(actor, targetActor, dwellSeconds)
				time = estimateTimeToPoint(actor, point)
			else
				time, point = estimateTimeToBall(actor)
				local intendedId = ball and ball:GetAttribute("LastFootballActionIntendedReceiverUserId")
				if intendedId == actor.Id then
					time -= AIConfig.LooseBall.IntendedReceiverBonusSeconds
				end
			end
			actor.TimeToBall = time
			actor.ReceptionTarget = point
			local isHumanActivelyClosing = not actor.IsAI
				and BallControlMath.GetHorizontal(actor.RootPart.AssemblyLinearVelocity).Magnitude >= 4

			--[[
				When choosing who presses, position matters as well as distance
				(§44). A defender a little further away is still the right presser
				over a forward who should be holding the line. Loose balls are
				pure races, so this only applies to pressing.
			]]
			local rankedTime = time
			if targetActor then
				local profile = getPositionProfile(actor)
				local willingness = if profile and profile.AI then math.clamp(profile.AI.PressWillingness, 0, 1) else 0.5
				rankedTime = time * (1.6 - willingness * 0.6)
			end

			--[[
				A human teammate can be the closest to the ball, and when they are,
				no AI should be sent to compete with them for it. But the previous
				form of this wrote `bestActor = nil` and kept the human's time as
				`bestTime`, which did not merely skip the human -- it also blocked
				every AI ranked behind them from ever becoming the designated
				presser. One team-mate jogging was enough to switch the whole
				team's press off.

				A human who is closest now simply CLAIMS the duty (nobody is
				designated) instead of poisoning the comparison for everyone else.
			]]
			if rankedTime < bestTime and (actor.IsAI or isHumanActivelyClosing) then
				if actor.IsAI then
					secondActor, secondTime = bestActor, bestTime
					bestActor = actor
					bestTime = rankedTime
					bestPoint = point
				else
					bestActor = nil
					bestTime = rankedTime
					bestPoint = point
				end
			elseif actor.IsAI and rankedTime < secondTime then
				secondActor = actor
				secondTime = rankedTime
			end
		end
	end
	local previous = teamModel.DesignatedActor
	if previous and previous ~= bestActor and previous.TimeToBall
		and previous.TimeToBall <= bestTime + AIConfig.LooseBall.DesignatedChaserHysteresis
	then
		bestActor = previous
		bestTime = previous.TimeToBall
		bestPoint = previous.ReceptionTarget or bestPoint
	end
	teamModel.DesignatedActor = bestActor
	teamModel.DesignatedTarget = bestPoint
	teamModel.DesignatedTime = bestTime

	--[[
		THE SECOND MAN (see AIConfig.Defending.SupportPress).

		Chosen only while pressing a carrier, never for a loose ball -- a loose
		ball is a race, and sending two players at it just means they collide.
		The support presser closes to a covering position and does not challenge.
	]]
	local support = AIConfig.Defending.SupportPress
	teamModel.SupportActor = nil
	teamModel.SupportTarget = nil
	if targetActor and support.Enabled == true and secondActor and bestActor then
		local travel = BallControlMath.GetHorizontal(
			secondActor.RootPart.Position - targetActor.RootPart.Position
		).Magnitude
		local defendedGoal = getGoalsForTeam(secondActor.TeamId)
		local carrierToGoal = if defendedGoal
			then BallControlMath.GetHorizontal(
				targetActor.RootPart.Position - defendedGoal.MouthCenter
			).Magnitude
			else math.huge
		if travel <= support.MaximumTravel and carrierToGoal <= support.MaximumDistanceFromGoal then
			teamModel.SupportActor = secondActor
			teamModel.SupportTarget = getSupportPressTarget(secondActor, targetActor, bestPoint)
		end
	end
end

local function updatePerception()
	if not ball then
		return
	end
	local controller = getControllerActor()
	local controllerId = controller and controller.Id or 0
	if controllerId ~= lastControllerId then
		lastControllerId = controllerId
		lastPossessionChangedAt = os.clock()
	end
	for _, teamModel in teams do
		teamModel.PerceivedBallPosition = predictBallPosition(AIConfig.Cadence.ReactionDelay)
		teamModel.PerceivedBallVelocity = ball.AssemblyLinearVelocity
		teamModel.Controller = controller
	end
end

local function updateTeams()
	local now = os.clock()
	local controller = getControllerActor()
	for _, teamModel in teams do
		local requestedState
		local owningTeam = false
		if controller then
			owningTeam = getTeamId(controller) == teamModel.TeamId
			requestedState = if owningTeam then "InPossession" else "OutOfPossession"
		else
			requestedState = "LooseBall"
		end
		-- Only the side that just lost the ball needs a transition beat. The side
		-- that won it commits immediately so its carrier is treated as a carrier.
		if not owningTeam
			and requestedState ~= "LooseBall"
			and now - lastPossessionChangedAt < AIConfig.Cadence.TransitionHoldSeconds
		then
			requestedState = "Transition"
		end
		local immediate = owningTeam and AIConfig.Cadence.PossessionCommitImmediate == true
		setTeamState(teamModel, requestedState, now, immediate)
		if requestedState == "LooseBall" then
			chooseDesignatedPlayer(teamModel, nil)
		elseif requestedState == "OutOfPossession" or requestedState == "Transition" then
			-- Press the opposing carrier only. Sending the designated player at a
			-- controller who is a team-mate made the possessing side converge on
			-- its own footballer.
			chooseDesignatedPlayer(teamModel, controller)
		else
			teamModel.DesignatedActor = nil
		end
		for _, actor in teamModel.Actors do
			if refreshActor(actor) then
				actor.FormationTarget = getFormationTarget(actor, teamModel)
			end
		end
	end
end

local function getNearestOpponentDistance(actor, point: Vector3): number
	local opponentTeam = teams[if actor.TeamId == "Home" then "Away" else "Home"]
	local nearest = math.huge
	for _, opponent in opponentTeam and opponentTeam.Actors or {} do
		if refreshActor(opponent) then
			nearest = math.min(nearest, BallControlMath.GetHorizontal(opponent.RootPart.Position - point).Magnitude)
		end
	end
	return nearest
end

--[[
	Everything the decision needs to know about the opposition, once.

	Built per decision rather than per candidate: the free-space and interception
	models each walk the whole opposition, and a 3v3 carrier rating itself plus
	two team-mates would otherwise rebuild this five times a tick (§102).
]]
local function collectOpponents(teamId: string): { any }
	local opponentTeam = teams[if teamId == "Home" then "Away" else "Home"]
	local list = {}
	for _, opponent in opponentTeam and opponentTeam.Actors or {} do
		if refreshActor(opponent) then
			table.insert(list, {
				Position = opponent.RootPart.Position,
				Velocity = opponent.RootPart.AssemblyLinearVelocity,
				IsGoalkeeper = opponent.Position == GoalkeeperConfig.Role,
			})
		end
	end
	return list
end

local function rateSituation(actor, opponents: { any })
	local decision = AIConfig.Decision
	local attackDirection = getAxes(actor.TeamId)
	local _, attackingGoal = getGoalsForTeam(actor.TeamId)
	local goalPosition = if attackingGoal
		then attackingGoal.MouthCenter
		else actor.RootPart.Position + attackDirection * pitchState.Length

	return AITacticalEvaluator.RateSituation(
		actor.RootPart.Position,
		actor.RootPart.AssemblyLinearVelocity,
		attackDirection,
		goalPosition,
		opponents,
		{
			SprintSpeed = decision.SprintSpeed,
			SafeDistance = decision.SafeDistance,
			CrowdedCount = decision.CrowdedCount,
			ForwardSpaceWeight = decision.ForwardSpaceWeight,
			SpaceWeight = decision.SpaceWeight,
			ForwardWeight = decision.ForwardWeight,
			PitchLength = pitchState.Length,
		}
	)
end

--[[
	Should this ball be given to someone else, and how?

	The reference's two-stage selection. First a team-mate must be in a
	genuinely better position than the carrier -- that is what makes this a
	football decision rather than "is anyone open" -- and only then is the pass
	itself scored for whether it would actually arrive.
]]
local function choosePass(actor, teamModel, opponents: { any }, selfRating, longPossessionFactor: number)
	local decision = AIConfig.Decision
	local origin = actor.RootPart.Position

	--[[
		Holding the ball for a long time lowers both bars (GameplayFootball's
		`longPossessionFactor`). A carrier who has been dribbling for five
		seconds becomes progressively readier to release it, which is what stops
		the six-to-ten-second straight-line carries seen in the playtest log.
	]]
	local passMinimum = decision.PassMinimum - longPossessionFactor * decision.LongPossessionMinimumRelief
	local passThreshold = decision.PassThreshold - longPossessionFactor * decision.LongPossessionThresholdRelief

	--[[
		HOW MUCH BETTER PLACED MUST A TEAM-MATE BE?

		Less and less, the longer the ball is held and the harder the carrier is
		being closed down -- see AIConfig.Decision.LongPossessionImprovementRelief
		for why a fixed bar meant the carrier never passed at all.

		The bar is allowed to go negative. That is deliberate: a footballer under
		pressure gives the ball to a team-mate who is no better placed than they
		are, because keeping it is the worse option. What still governs whether
		the ball actually goes is the ODDS test below, so relieving this cannot
		produce a pass straight to an opponent.
	]]
	local nearestOpponent = math.huge
	for _, opponent in opponents do
		nearestOpponent = math.min(
			nearestOpponent,
			BallControlMath.GetHorizontal(opponent.Position - origin).Magnitude
		)
	end
	local pressureFactor = 1 - math.clamp(nearestOpponent / math.max(decision.PressureDistance, 1e-3), 0, 1)
	local improvementBar = decision.TacticalImprovementThreshold
		- longPossessionFactor * decision.LongPossessionImprovementRelief
		- pressureFactor * decision.PressureImprovementRelief

	local bestTotal = 0
	local bestReceiver, bestActionType, bestOdds = nil, nil, 0

	for _, receiver in teamModel.Actors do
		if receiver.Id ~= actor.Id and refreshActor(receiver) then
			local mateRating = rateSituation(receiver, opponents)
			local mateTotal = mateRating.Total
			if receiver.Position == GoalkeeperConfig.Role then
				-- "don't like playing back to goalie" -- the reference's words.
				mateTotal *= decision.GoalkeeperReceiverPenalty
			end

			if mateTotal > selfRating.Total + improvementBar then
				local toReceiver = BallControlMath.GetHorizontal(receiver.RootPart.Position - origin)
				local distance = toReceiver.Magnitude

				-- Lead a moving receiver by roughly the flight time, capped at
				-- the time they would need to brake.
				local flightSeconds = 0.7 + distance * 0.03
				local target = receiver.RootPart.Position
					+ BallControlMath.GetHorizontal(receiver.RootPart.AssemblyLinearVelocity)
						* math.clamp(flightSeconds, 0, 0.5)

				local groundOdds = AITacticalEvaluator.GetPassingOdds(
					origin, target, opponents, decision.GroundBallSpeedMultiplier, decision.SprintSpeed, false
				)
				local odds, actionType = groundOdds, "GroundPass"

				-- A lofted ball is only worth considering over real distance.
				if distance >= decision.LoftedMinimumDistance then
					local loftedOdds = AITacticalEvaluator.GetPassingOdds(
						origin, target, opponents, decision.LoftedBallSpeedMultiplier, decision.SprintSpeed, true
					)
					if loftedOdds > odds then
						odds, actionType = loftedOdds, "LobPass"
					end
				end

				local total = (
					(mateTotal - selfRating.Total) * decision.TacticalDiffWeight
					+ odds * decision.PassWeight
				) / math.max(decision.TacticalDiffWeight + decision.PassWeight, 1e-4)

				if total > bestTotal and total > passThreshold and odds > passMinimum then
					bestTotal = total
					bestReceiver = receiver
					bestActionType = actionType
					bestOdds = odds
				end
			end
		end
	end

	--[[
		Commitment window (Beyond 90's own, kept). Positions change every frame
		and two candidates can trade places repeatedly; without this the carrier
		re-aims mid-windup and the pass reads as indecision.
	]]
	local now = os.clock()
	local committed = actor.CommittedReceiver
	if committed and committed ~= bestReceiver
		and now - (actor.CommittedReceiverAt or 0) < AIConfig.Passing.CommitmentSeconds
		and refreshActor(committed)
	then
		return committed, actor.CommittedActionType or "GroundPass", bestOdds, bestTotal
	end

	if bestReceiver then
		actor.CommittedReceiver = bestReceiver
		actor.CommittedReceiverAt = now
		actor.CommittedActionType = bestActionType
	else
		actor.CommittedReceiver = nil
	end

	return bestReceiver, bestActionType, bestOdds, bestTotal
end

--[[
	Is the shot on?

	SHOOTING IS A POSITION, NOT A DISTANCE. Closeness to an ideal shooting
	position in front of goal fades the willingness to shoot in and out along an
	S-curve, and outside that region no shot is evaluated at all -- so the
	decision falls through to passing by itself instead of being ordered around
	a shot that was always going to win.

	Inside it, three aim points across the goal are scored with the same
	interception model a pass uses (a shot is a pass to the net) and the least
	defended one wins. The small random term is the reference's: without it a
	whole team in similar positions reaches identical verdicts on one frame.
]]
local function shouldShoot(actor, opponents: { any }): boolean
	local shooting = AIConfig.Shooting
	local _, attackingGoal = getGoalsForTeam(actor.TeamId)
	if not attackingGoal then
		return false
	end

	local attackDirection, lateralAxis = getAxes(actor.TeamId)
	local goalCenter = attackingGoal.MouthCenter
	local idealSpot = goalCenter - attackDirection * shooting.IdealDistanceFromGoal
	local toIdeal = BallControlMath.GetHorizontal(idealSpot - actor.RootPart.Position).Magnitude

	local positionFactor = 1 - math.clamp(toIdeal / math.max(shooting.IdealRadius, 1e-3), 0, 1)
	-- GameplayFootball's curve(): an S, so the middle of the range is decisive
	-- rather than linear.
	positionFactor = math.sin((positionFactor - 0.5) * math.pi) * 0.5 + 0.5
	if positionFactor <= shooting.MinimumPositionFactor then
		return false
	end

	local origin = actor.RootPart.Position
	local best = 0
	for _, offset in { -shooting.AimHalfWidth, 0, shooting.AimHalfWidth } do
		local odds = AITacticalEvaluator.GetPassingOdds(
			origin,
			goalCenter + lateralAxis * offset,
			opponents,
			shooting.BallSpeedMultiplier,
			AIConfig.Decision.SprintSpeed,
			false
		)
		best = math.max(best, odds)
	end

	local odds = math.sqrt(math.max(best, 0))
	return odds + math.random() * shooting.OddsRandomRange > shooting.OddsThreshold
end

local function getPossessionMovementTarget(actor): Vector3
	local _, attackingGoal = getGoalsForTeam(actor.TeamId)
	local goalTarget = attackingGoal and attackingGoal.MouthCenter or actor.FormationTarget
	local direction = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(goalTarget - actor.RootPart.Position),
		actor.RootPart.CFrame.LookVector
	)
	local avoidance = Vector3.zero
	local opponentTeam = teams[if actor.TeamId == "Home" then "Away" else "Home"]
	for _, opponent in opponentTeam and opponentTeam.Actors or {} do
		if refreshActor(opponent) then
			local away = BallControlMath.GetHorizontal(actor.RootPart.Position - opponent.RootPart.Position)
			local distance = away.Magnitude
			if distance > 0 and distance < AIConfig.Possession.OpponentAvoidRadius then
				avoidance += away.Unit * (1 - distance / AIConfig.Possession.OpponentAvoidRadius)
			end
		end
	end
	local carryDirection = BallControlMath.SafeUnit(
		direction + avoidance * AIConfig.Possession.OpponentAvoidStrength,
		direction
	)
	return clampToPitch(actor.RootPart.Position + carryDirection * 24)
end

local function queueAction(actor, actionName: string, callback)
	if actor.ActionPending then
		return
	end
	actor.ActionPending = true
	actor.State = actionName
	actor.MovementTarget = actor.RootPart.Position
	AIAnimationService.PlayAction(actor, if actionName == "Pass" then "Pass" else "Shoot")
	task.delay(0.24, function()
		if actor.Character and actor.Character.Parent and active then
			callback()
		end
		actor.ActionPending = false
	end)
end

--[[
	What does a footballer in possession do?

	The order is GameplayFootball's, and the order is the point. It previously
	ran clearance -> shoot -> pass, so a shot was tested before a pass had ever
	been considered and, with the old distance gate, a shot was almost always
	available. That single ordering is why the AI shot from 77 studs instead of
	playing football.

		self rating   how good is MY situation?
		pass          is anyone GENUINELY better placed, and would it arrive?
		panic         am I deep, pressured, and out of options?
		shoot         am I actually in a shooting position?
		dribble       none of the above -- carry it

	Passing is resolved before shooting because the reference queues it first.
	It is not a bias toward passing: inside the box the carrier's own forward
	rating is near maximum, so a team-mate rarely clears the improvement
	threshold and the shot is what survives.
]]
local function decidePossession(actor, teamModel)
	local now = os.clock()
	actor.PossessionStartedAt = actor.PossessionStartedAt or now
	local possessionAge = now - actor.PossessionStartedAt

	-- Secure phase: hold a short, close, forward target instead of immediately
	-- driving 24 studs toward goal. Sprinting away from a just-trapped football
	-- is what pushed the ball outside the control envelope within a fraction of
	-- a second and caused the distance-exceeded releases.
	if possessionAge < AIConfig.Possession.SecureDurationSeconds then
		actor.State = "Secure"
		local forward = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector),
			pitchState.LengthAxis
		)
		actor.MovementTarget = clampToPitch(
			actor.RootPart.Position + forward * AIConfig.Possession.SecureLeadDistance
		)
		return
	end

	actor.State = "Possess"
	actor.MovementTarget = getPossessionMovementTarget(actor)
	if actor.ActionPending or possessionAge < AIConfig.Possession.MinimumDecisionAge then
		return
	end
	local defendedGoal, attackingGoal = getGoalsForTeam(actor.TeamId)
	if not defendedGoal or not attackingGoal then
		return
	end

	local decision = AIConfig.Decision
	local opponents = collectOpponents(actor.TeamId)
	local selfRating = rateSituation(actor, opponents)

	-- Squared, so willingness to release the ball builds slowly and then bites.
	local longPossessionFactor = math.clamp(
		possessionAge / math.max(decision.LongPossessionSeconds, 1e-3), 0, 1
	) ^ 2

	local receiver, actionType, passOdds = choosePass(
		actor, teamModel, opponents, selfRating, longPossessionFactor
	)

	--[[
		PANIC (GameplayFootball's `_AddPanicPass`).

		Deep in our own half, under pressure, and nothing constructive on. The
		reference only panics when the pass options have ALREADY been found
		wanting, which is why this now sits after the pass search rather than
		before it -- previously any pressured carrier in its own half cleared,
		even with a team-mate free.
	]]
	local attackDirection = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(attackingGoal.MouthCenter - defendedGoal.MouthCenter),
		actor.RootPart.CFrame.LookVector
	)
	local pressure = getNearestOpponentDistance(actor, actor.RootPart.Position)
	local pitchProgress = BallControlMath.GetHorizontal(actor.RootPart.Position - pitchState.Center):Dot(attackDirection)
		/ math.max(pitchState.Length * 0.5, 1)
	local desperate = pitchProgress <= AIConfig.Clearance.DefensiveProgressThreshold
		and pressure <= AIConfig.Clearance.PressureDistance
	--[[
		The carry ceiling. See AIConfig.Decision.MaximumCarrySeconds: relaxing the
		thresholds is not the same as guaranteeing a decision, and a carrier with
		uniformly poor options previously had none forced on it.
	]]
	if possessionAge >= decision.MaximumCarrySeconds then
		if receiver then
			queueAction(actor, "Pass", function()
				FootballActionService.ExecuteAIPass(actor, receiver, actionType or AIConfig.Passing.ActionType)
			end)
		else
			queueAction(actor, "Clearance", function()
				FootballActionService.ExecuteAIShot(actor, true)
			end)
		end
		return
	end

	if desperate and (not receiver or passOdds < decision.PanicPassOdds) then
		queueAction(actor, "Clearance", function()
			FootballActionService.ExecuteAIShot(actor, true)
		end)
		return
	end

	if receiver then
		queueAction(actor, "Pass", function()
			FootballActionService.ExecuteAIPass(actor, receiver, actionType or AIConfig.Passing.ActionType)
		end)
		return
	end

	if shouldShoot(actor, opponents) then
		queueAction(actor, "Shoot", function()
			FootballActionService.ExecuteAIShot(actor, false)
		end)
		return
	end

	-- Nothing on: carry it. MovementTarget is already the dribble target.
end

-- Bounded AI tackle decision. Reaction delay, cooldown and commitment prevent
-- an AI defender from spamming challenges the instant it is in range.
function tryAITackle(actor, teamModel)
	if DefendingConfig.AI.Enabled ~= true or not ball then
		return
	end
	local now = os.clock()
	if actor.TackleCommittedUntil and now < actor.TackleCommittedUntil then
		return
	end
	if actor.LastTackleDecisionAt and now - actor.LastTackleDecisionAt < DefendingConfig.AI.DecisionCooldown then
		return
	end
	if DefendingService.IsRecovering(actor.Id) then
		return
	end
	if ball:GetAttribute("State") ~= "Controlled" or ball:GetAttribute("GoalkeeperHeld") == true then
		actor.TackleIntentAt = nil
		actor.ContainingSince = nil
		return
	end
	local distanceToBall = BallControlMath.GetHorizontal(ball.Position - actor.RootPart.Position).Magnitude
	if distanceToBall > DefendingConfig.AI.TackleDistance then
		actor.TackleIntentAt = nil
		actor.ContainingSince = nil
		return
	end

	--[[
		CONTAIN FIRST, COMMIT SECOND.

		An AI defender that challenges the moment a tackle becomes legal is the
		same mistake the human press was making, and it is far more visible on
		the AI because there are ten of them doing it at once. Real defending
		looks like arriving, holding the carrier up, and then choosing a moment.

		So arriving in range starts a containment clock rather than a challenge.
		Until it expires the defender is present and in the way -- which is the
		pressure -- but does not dive in.

		The exception is a genuinely exposed ball. Patience is a response to a
		carrier who has the ball under control; a heavy touch is not a moment to
		be patient about, and OpportunistScore lets the AI take it.
	]]
	if not actor.ContainingSince then
		actor.ContainingSince = now
	end
	-- Human-like latency: the AI must see the opportunity briefly before acting.
	if not actor.TackleIntentAt then
		actor.TackleIntentAt = now
		return
	end
	if now - actor.TackleIntentAt < DefendingConfig.AI.ReactionDelay then
		return
	end

	--[[
		Only commit to a challenge that is actually available.

		Range alone is not a reason to tackle: a defender closing from behind is
		within range for the whole run-up, and every one of those challenges is
		illegal. Previewing the same evaluation the server will run means the AI
		keeps pressing until the geometry comes good, instead of spending its
		cooldown and recovery on attempts that cannot succeed.
	]]
	local preview = DefendingService.PreviewTackle(actor)
	if not preview or not preview.Valid or preview.Score < DefendingConfig.AI.MinimumScoreToAttempt then
		return
	end

	local contained = now - (actor.ContainingSince or now)
	local exposed = preview.Score >= DefendingConfig.AI.OpportunistScore
	if contained < DefendingConfig.AI.MinimumContainSeconds and not exposed then
		return
	end

	actor.LastTackleDecisionAt = now
	actor.TackleIntentAt = nil
	actor.ContainingSince = nil
	actor.TackleCommittedUntil = now + DefendingConfig.AI.CommitmentSeconds
	DefendingService.AttemptTackle(actor)
end

local function updateIndividuals()
	if not ball then
		return
	end
	for _, teamModel in teams do
		for _, actor in teamModel.Actors do
			if not actor.IsAI or not refreshActor(actor) then
				continue
			end
			local hasPossession = BallControlService.IsControlledByAI(actor, ball)
			if hasPossession then
				decidePossession(actor, teamModel)
			else
				actor.PossessionStartedAt = nil
				actor.CommittedReceiver = nil
				if teamModel.State == "LooseBall" and teamModel.DesignatedActor == actor then
					actor.State = "ChaseBall"
					actor.MovementTarget = teamModel.DesignatedTarget
				elseif (teamModel.State == "OutOfPossession" or teamModel.State == "Transition")
					and teamModel.DesignatedActor == actor
				then
					actor.State = "Press"
					actor.MovementTarget = teamModel.DesignatedTarget
					-- Only the designated presser challenges, so a team cannot
					-- collapse onto one carrier with simultaneous tackles.
					tryAITackle(actor, teamModel)
				elseif (teamModel.State == "OutOfPossession" or teamModel.State == "Transition")
					and teamModel.SupportActor == actor
					and teamModel.SupportTarget
				then
					--[[
						The second man. Closes the space behind and across from the
						first presser, and deliberately does NOT call tryAITackle:
						pressure comes from two players being there, not from two
						challenges arriving at once.
					]]
					actor.State = "SupportPress"
					actor.MovementTarget = teamModel.SupportTarget
				elseif teamModel.State == "InPossession" then
					actor.State = if actor.Role == "Forward" then "MakeRun" else "Support"
					actor.MovementTarget = actor.FormationTarget
				else
					actor.State = if teamModel.State == "OutOfPossession" then "Recover" else "HoldShape"
					actor.MovementTarget = actor.FormationTarget
				end
			end
			actor.Character:SetAttribute(AIConfig.Attributes.State, actor.State)
			actor.Character:SetAttribute(AIConfig.Attributes.Decision, actor.State)
			actor.Character:SetAttribute(AIConfig.Attributes.MovementTarget, actor.MovementTarget)
			actor.Character:SetAttribute(AIConfig.Attributes.FormationTarget, actor.FormationTarget)
			actor.Character:SetAttribute(AIConfig.Attributes.TimeToBall, actor.TimeToBall or -1)
			actor.Character:SetAttribute(AIConfig.Attributes.Possession, hasPossession)
		end
	end
end

local function moveToward(value: number, target: number, maximumDelta: number): number
	if value < target then
		return math.min(target, value + maximumDelta)
	end
	return math.max(target, value - maximumDelta)
end

--[[
	How fast should this footballer be running, and is it urgent? (§50, §51)

	The playtest complaint was that AI "looks too slow" even though it can
	physically reach 28 studs/s. The cause was here rather than in the speed
	constants: everything except ChaseBall and Press jogged unless it happened to
	be more than 24 studs from its target, so attacking runs, defensive recovery
	and transition all moved at 14 studs/s no matter how urgent they were.

	Raising the top speed would not have fixed that -- the top speed was never the
	limit. The state that is being executed is.

	Returns (speed, urgent). `urgent` lets a footballer spend its stamina reserve.
]]
local function resolveMovementSpeed(actor, distance: number): (number, boolean)
	local locomotion = AIConfig.Locomotion
	local defending = AIConfig.Defending
	local state = actor.State

	-- A loose ball is a pure race. Always flat out.
	if state == "ChaseBall" then
		return locomotion.SprintSpeed, true
	end

	--[[
		Pressing: sprint to close, then JOCKEY. Arriving at full speed is what
		makes a defender run straight past a carrier who changes direction, and
		is half of why challenges kept coming in from behind.
	]]
	if state == "Press" then
		if distance > defending.EngageDistance then
			return locomotion.SprintSpeed, true
		end
		return locomotion.JogSpeed * defending.JockeySpeedScale, false
	end

	--[[
		The second man closing. Sprints in like the first presser, then holds its
		covering position rather than jockeying -- it is not the one who has to
		react to a change of direction.
	]]
	if state == "SupportPress" then
		if distance > defending.EngageDistance then
			return locomotion.SprintSpeed, true
		end
		return locomotion.JogSpeed, false
	end

	-- Getting back into shape after losing the ball is urgent football.
	if state == "Recover" then
		return locomotion.SprintSpeed, true
	end

	-- An attacking run is meant to beat someone. It is not a jog.
	if state == "MakeRun" then
		return (if distance > locomotion.RunSprintDistance
			then locomotion.SprintSpeed
			else locomotion.JogSpeed), false
	end

	-- Support movement sprints only when there is real ground to make up.
	if state == "Support" then
		return (if distance > locomotion.SupportSprintDistance
			then locomotion.SprintSpeed
			else locomotion.JogSpeed), false
	end

	-- Holding shape is deliberately unhurried, unless a long way out of position.
	return (if distance >= locomotion.SprintDistance
		then locomotion.SprintSpeed
		else locomotion.JogSpeed), false
end

local function updateMovement(deltaTime: number)
	if not ball then
		return
	end
	for _, actor in aiActors do
		if not refreshActor(actor) then
			continue
		end
		local target = actor.MovementTarget or actor.FormationTarget or actor.RootPart.Position
		local toTarget = BallControlMath.GetHorizontal(target - actor.RootPart.Position)
		local distance = toTarget.Magnitude
		local direction = if distance > 0.05 then toTarget.Unit else Vector3.zero
		local targetSpeed = 0
		if not actor.ActionPending and distance > AIConfig.Locomotion.ArrivalRadius then
			local fullSpeed, urgent = resolveMovementSpeed(actor, distance)

			--[[
				STAMINA (§48). A tired footballer cannot hold top speed. The
				ceiling is the same curve the human client applies to itself, so
				neither side gains an advantage from being AI.

				Urgent situations spend the reserve: an AI must never look slow
				because it was saving energy during a loose-ball race (§51).
			]]
			if fullSpeed > AIConfig.Locomotion.JogSpeed then
				if StaminaService.CanSprint(actor.Id, urgent) then
					fullSpeed = math.min(fullSpeed, StaminaService.GetSprintCeiling(actor.Id))
				else
					fullSpeed = AIConfig.Locomotion.JogSpeed
				end
			end

			targetSpeed = fullSpeed * math.clamp(
				distance / AIConfig.Locomotion.SlowRadius,
				AIConfig.Locomotion.SlowMinimumScale,
				1
			)
		end

		-- A footballer in possession may never outrun its own controlled ball.
		-- Cap carry speed and scale it down further as the football trails behind,
		-- so the server servo always has a reachable relationship to restore.
		local hasBall = BallControlService.IsControlledByAI(actor, ball)
		if hasBall then
			local possession = AIConfig.Possession
			local maxSpeed = if actor.State == "Secure" then possession.SecureMoveSpeed else possession.CarryMaxSpeed
			local lead = ball:GetAttribute("CurrentBallLead")
			if typeof(lead) == "number" and lead < possession.CarryLeadSlowStart then
				local trailing = math.clamp(
					(possession.CarryLeadSlowStart - lead)
						/ math.max(possession.CarryLeadSlowFull - possession.CarryLeadSlowStart, 1e-4),
					0,
					1
				)
				local scale = 1 - (1 - possession.CarryLeadSlowMinScale) * trailing
				maxSpeed = math.min(maxSpeed, math.max(
					possession.CarryMaxSpeed * scale,
					BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity).Magnitude
						+ possession.CarryRecoverySpeedBonus
				))
			end
			targetSpeed = math.min(targetSpeed, maxSpeed)
		end
		-- An injured footballer is slower, AI or human alike (§72, §74).
		targetSpeed *= InjuryService.GetSpeedScale(actor.Id)

		-- Tell the stamina model what kind of work this actually is.
		if actor.State == "Press" then
			StaminaService.MarkPressing(actor.Id)
		elseif actor.State == "ChaseBall" then
			StaminaService.MarkChasing(actor.Id)
		end

		local responseTime = if targetSpeed > actor.CurrentSpeed
			then AIConfig.Locomotion.AccelerationTime
			else AIConfig.Locomotion.DecelerationTime
		actor.CurrentSpeed = moveToward(
			actor.CurrentSpeed,
			targetSpeed,
			AIConfig.Locomotion.SprintSpeed / math.max(responseTime, 0.05) * deltaTime
		)
		actor.Humanoid.WalkSpeed = actor.CurrentSpeed
		actor.Humanoid:SetAttribute("SprintRequested", actor.CurrentSpeed >= 19)
		actor.Humanoid:Move(direction, false)

		--[[
			A pressing defender watches the ball, not where its feet are going.

			AutoRotate turns the body along the movement direction, which while
			jockeying goal-side means facing its own goal with the carrier at its
			back -- the one orientation from which a challenge is never legal. So
			once inside pressing range, orientation is driven toward the football
			and handed straight back to AutoRotate on the way out.
		]]
		local pressing = actor.State == "Press"
			and BallControlMath.GetHorizontal(ball.Position - actor.RootPart.Position).Magnitude
				<= AIConfig.Defending.FaceBallDistance
		if pressing then
			local toBall = BallControlMath.GetHorizontal(ball.Position - actor.RootPart.Position)
			if toBall.Magnitude > 1e-3 then
				actor.Humanoid.AutoRotate = false
				local current = BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector)
				local desired = toBall.Unit
				local blended = if current.Magnitude > 1e-3
					then current.Unit:Lerp(desired, math.clamp(AIConfig.Defending.FaceBallResponsiveness * deltaTime, 0, 1))
					else desired
				if blended.Magnitude > 1e-3 then
					local position = actor.RootPart.Position
					actor.RootPart.CFrame = CFrame.lookAt(position, position + blended.Unit)
				end
			end
		elseif actor.Humanoid.AutoRotate == false then
			actor.Humanoid.AutoRotate = true
		end
		AIAnimationService.Update(actor)
		AIAnimationService.StepRootMotion(actor, deltaTime)

		if actor.State == "ChaseBall" and not actor.ActionPending
			and ball:GetAttribute("State") == "Free"
			and ball.Position.Y <= pitchState.GroundY + AIConfig.LooseBall.MaximumAcquisitionHeight
		then
			local distanceToBall = BallControlMath.GetHorizontal(ball.Position - actor.RootPart.Position).Magnitude
			if distanceToBall <= AIConfig.LooseBall.AcquisitionDistance then
				local acquired = BallControlService.TryAcquireAI(
					ball,
					actor,
					AIConfig.LooseBall.AcquisitionDistance,
					AIConfig.LooseBall.MaximumAcquisitionSpeed
				)
				if acquired then
					actor.PossessionStartedAt = os.clock()
					actor.State = "Receive"
					AIAnimationService.PlayAction(actor, "Receive")
				end
			end
		end
	end
end

local function createAICharacter(name: string, teamId: string): Model?
	-- One shared footballer body for every non-player footballer; PlayerService
	-- owns it (see PlayerService.CloneFootballerTemplate).
	local character, source = PlayerService.CloneFootballerTemplate()
	if character and source == "GeneratedR15" then
		warn(string.format(
			"%s[AI] StarterPlayer.StarterCharacter unavailable; %s fell back to a generic R15 rig",
			GameConfig.LogPrefix,
			name
		))
	end
	if not character then
		warn(string.format("%s[AI] Could not create character for %s", GameConfig.LogPrefix, name))
		return nil
	end
	if not loggedCharacterSource then
		loggedCharacterSource = true
		log(string.format("Footballer template source=%s", source))
	end
	character:SetAttribute("Beyond90FootballerTemplateSource", source)
	character.Name = name
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		character:Destroy()
		return nil
	end
	CharacterAppearanceService.StandardizeNPC(name, character, humanoid)
	PlayerService.NormalizeFootballerPhysics(character)
	PlayerService.ApplyFootballerGrounding(character, humanoid)
	humanoid.DisplayName = name
	humanoid.AutoRotate = true
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.WalkSpeed = 0
	humanoid.AutomaticScalingEnabled = false
	local teamColor = AIConfig.Character.TeamColors[teamId]
	character:SetAttribute("Beyond90UsesHumanoidLocomotion", true)
	character:SetAttribute("Beyond90TeamColor", teamColor)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not part.Parent:IsA("Accessory") then
			part.Color = part.Color:Lerp(teamColor, AIConfig.Character.TeamColorBlend)
		end
	end
	return character
end

--[[
	Where a footballer stands when the teams are first put on the pitch.

	This is a KICK-OFF shape, not a normal in-play formation: every footballer
	belongs in their own half before the whistle, exactly as in a real match.
	Using the same kick-off box the restart itself uses means the pre-whistle
	line-up and the line-up at the whistle agree, instead of forwards standing in
	the opponents' half for the few seconds before kick-off and then being moved.
]]
local function getSpawnPosition(teamId: string, role: string, slotId: string?): (Vector3, Vector3)
	local attackDirection = getAxes(teamId)
	local temporaryActor = { TeamId = teamId, Role = role, PositionSlotId = slotId }
	local profile = getPositionProfile(temporaryActor)
	local frame = RestartService.GetTeamFrame(teamId)

	if profile and frame then
		local anchor = profile.Anchor
		--[[
			A goalkeeper is not remapped: its place is its own goal line, and
			squeezing it into the outfield kick-off band would put a keeper on the
			edge of its own penalty area before a ball had been kicked.
		]]
		if not PositionConfig.IsGoalkeeper(slotId or "") then
			local box = SetPieceFormation.GetBox("Kickoff", true, 0, 0)
			local target = SetPieceFormation.Resolve(frame, anchor, box)
			return Vector3.new(target.X, target.Y + AIConfig.Spawn.RootHeightAboveSurface, target.Z),
				attackDirection
		end
	end

	local teamModel = teams[teamId]
	local target = getFormationTarget(temporaryActor, teamModel)
	return target + Vector3.yAxis * AIConfig.Spawn.RootHeightAboveSurface, attackDirection
end

local function createAIActor(teamId: string, role: string, slotIndex: number, isGoalkeeper: boolean?, slotId: string?)
	local teamNumber = if teamId == "Home" then 91 else 92
	local id = -(teamNumber * 10000 + slotIndex)
	local name = string.upper(teamId) .. "_AI_" .. tostring(slotIndex)
	local character = createAICharacter(name, teamId)
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local actor = {
		Id = id,
		Kind = "AI",
		TeamId = teamId,
		Character = character,
		Humanoid = humanoid,
		RootPart = root,
		DisplayName = name,
		Player = nil,
		IsAI = true,
		Role = role,
		State = "HoldShape",
		CurrentSpeed = 0,
		ShootingSkill = AIConfig.Shooting.Skill,
		--[[
			The slot must be known BEFORE the spawn is resolved: the kick-off
			line-up is derived from the position's own anchor, so assigning it
			afterwards would place every AI from a role fallback instead.
		]]
		PositionSlotId = slotId,
	}
	FootballerRegistryService.RegisterAI(actor)
	local position, direction = getSpawnPosition(teamId, role, slotId)
	character:PivotTo(CFrame.lookAt(position, position + direction))
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			pcall(function() part:SetNetworkOwner(nil) end)
		end
	end
	--[[
		The role must be set BEFORE registering animations.

		AIAnimationService.Register decides whether to load the goalkeeper clip
		set by reading actor.Position. Assigning the role afterwards meant a
		keeper was always registered as an outfielder, so its idle, idle-with-
		ball, side-step, catch and throw tracks were never loaded at all and
		UpdateGoalkeeper returned immediately every frame.
	]]
	if isGoalkeeper then
		-- Keepers are footballers in the registry and on the minimap, but they do
		-- not take part in outfield formation or pressure assignment.
		actor.Position = GoalkeeperConfig.Role
		character:SetAttribute(GoalkeeperConfig.RoleAttributeName, GoalkeeperConfig.Role)
	end

	AIAnimationService.Register(actor)

	if isGoalkeeper then
		return actor
	end
	table.insert(aiActors, actor)
	table.insert(teams[teamId].Actors, actor)
	return actor
end

local function assignHumans(teamId: string)
	local teamModel = teams[teamId]
	local humans = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Beyond90SelectedGameMode") == AIConfig.ModeId
			and FootballTeamConfig.Normalize(player:GetAttribute(FootballTeamConfig.AttributeName)) == teamId
		then
			local actor = FootballerRegistryService.GetHumanActor(player)
			if actor then
				table.insert(humans, actor)
			end
		end
	end
	table.sort(humans, function(a, b) return a.Id < b.Id end)
	for index, actor in humans do
		if index > AIConfig.TeamSize then
			break
		end
		--[[
			The position the server reserved for this player wins. Join order is
			only a fallback for a player who reached the pitch without choosing.
		]]
		local slotId = PositionService.GetPlayerSlotId(actor.Player)
		if not slotId then
			slotId = PositionService.GetDefaultSlotId(teamId, AIConfig.ModeId)
			PositionService.Reserve(actor.Player, teamId, slotId, AIConfig.ModeId)
		end
		local position = PositionConfig.Get(slotId)
		actor.PositionSlotId = slotId
		actor.Role = position and position.AIRole or humanRoleOrder[index]
		actor.Player:SetAttribute(AIConfig.Attributes.Role, actor.Role)

		--[[
			CHOOSING GK ACTUALLY MAKES YOU THE GOALKEEPER.

			Reserving the GK slot used to change nothing except which spawn point
			the player got. `actor.Position` stayed whatever an outfielder's is, so
			every goalkeeper test in the project answered "no" for this player: the
			roster counted them as an outfielder, GoalkeeperService never saw them,
			and -- because the AI keeper loop below spawned a fixed number of
			keepers per team regardless -- the team ALSO got a bot keeper. Two
			goalkeepers, and the human was neither of them.

			Registering here is what makes the human a keeper everywhere at once:
			saves, secure possession, distribution, the keeper animation set and
			the AI keeper suppression below all key off the same registration.
		]]
		if PositionConfig.IsGoalkeeper(slotId) then
			GoalkeeperService.Register(actor)
			--[[
				Deliberately NOT `aiKeepers`. That list is torn down by destroying
				its characters and is walked by the AI restart loop, neither of
				which may ever be applied to a real player's footballer. This one
				exists only so the registration can be undone.
			]]
			table.insert(humanKeepers, actor)
		end

		table.insert(teamModel.Actors, actor)
		local spawnPosition, direction = getSpawnPosition(teamId, actor.Role, slotId)
		actor.Character:PivotTo(CFrame.lookAt(spawnPosition, spawnPosition + direction))
	end
	return math.min(#humans, AIConfig.TeamSize)
end

local function rebuildTeams()
	if not ball or not ball.Parent or not pitchState then
		return
	end
	if BallControlService.GetActiveAIController() then
		BallControlService.ReleaseAI(ball, "3v3 slots rebuilding")
	end
	for _, actor in aiActors do
		AIAnimationService.Unregister(actor)
	end
	for _, keeper in aiKeepers do
		GoalkeeperService.Unregister(keeper)
		AIAnimationService.Unregister(keeper)
	end
	for _, keeper in humanKeepers do
		GoalkeeperService.Unregister(keeper)
	end
	FootballerRegistryService.ClearAI()
	table.clear(aiActors)
	table.clear(aiKeepers)
	table.clear(humanKeepers)
	teams = {
		Home = { TeamId = "Home", State = "LooseBall", Actors = {}, PerceivedBallPosition = ball.Position },
		Away = { TeamId = "Away", State = "LooseBall", Actors = {}, PerceivedBallPosition = ball.Position },
	}
	for _, teamId in { "Home", "Away" } do
		local humanCount = assignHumans(teamId)

		--[[
			AI fills exactly the slots no human reserved (§40). Asking the position
			authority rather than counting roles here means a slot can never be
			double-filled, and a team is never left without a shape.
		]]
		local aiIndex = 0
		for _, slotKey in PositionService.GetUnoccupiedSlots(teamId, AIConfig.ModeId) do
			local slotId = PositionService.SlotIdFromKey(slotKey)
			local position = PositionConfig.Get(slotId)
			if position and not PositionConfig.IsGoalkeeper(slotId) then
				if #teams[teamId].Actors >= AIConfig.TeamSize then
					break
				end
				aiIndex += 1
				local actor = createAIActor(teamId, position.AIRole, humanCount + aiIndex, false, slotId)
				if actor then
					actor.PositionSlotId = slotId
					if actor.Character then
						actor.Character:SetAttribute(PositionConfig.SlotAttributeName, slotId)
					end
				end
			end
		end

		--[[
			The goalkeeper is an extra slot, so 3v3 keeps three outfield
			footballers per side plus a keeper -- but the AI only fills that slot
			if a human has NOT taken it.

			This loop previously ran `for 1, GoalkeepersPerTeam` unconditionally,
			which is why selecting GK still left an AI keeper standing on the same
			goal line. The outfield loop above has always asked the position
			authority which slots are free; the keeper loop now asks the same
			question instead of assuming the answer.
		]]
		local freeKeeperSlots = 0
		for _, slotKey in PositionService.GetUnoccupiedSlots(teamId, AIConfig.ModeId) do
			if PositionConfig.IsGoalkeeper(PositionService.SlotIdFromKey(slotKey)) then
				freeKeeperSlots += 1
			end
		end
		if AIConfig.GoalkeeperEnabled == true then
			for keeperIndex = 1, math.min(AIConfig.GoalkeepersPerTeam, freeKeeperSlots) do
				local keeper = createAIActor(teamId, GoalkeeperConfig.Role, 90 + keeperIndex, true, "GK")
				if keeper then
					keeper.PositionSlotId = "GK"
					if keeper.Character then
						keeper.Character:SetAttribute(PositionConfig.SlotAttributeName, "GK")
					end
					GoalkeeperService.Register(keeper)
					table.insert(aiKeepers, keeper)
				end
			end
		end
	end
	updatePerception()
	updateTeams()
	updateIndividuals()
	--[[
		Roster diagnostic (§78).

		This used to read `GetAll() - #aiActors` and label the result "humans",
		which counted the two AI GOALKEEPERS as human players -- so a session with
		one real player reported "humans=3". Each category is now counted for
		what it is.
	]]
	local humanCount, aiOutfieldCount, keeperCount = 0, 0, 0
	for _, actor in FootballerRegistryService.GetAll(AIConfig.ModeId) do
		if actor.Position == GoalkeeperConfig.Role then
			keeperCount += 1
		elseif actor.IsAI then
			aiOutfieldCount += 1
		else
			humanCount += 1
		end
	end
	log(string.format(
		"3v3 ready outfield=%d (human=%d AI=%d) goalkeepers=%d",
		humanCount + aiOutfieldCount,
		humanCount,
		aiOutfieldCount,
		keeperCount
	))
end

local function updateDebug()
	if not AIConfig.Debug.Enabled then
		return
	end
	local stats = BallControlService.GetAIPossessionStats()
	if stats.Acquisitions > 0 then
		--[[
			Losing the ball to a TACKLE is reported separately from losing control
			of it (§79). Counting an opponent winning the ball as a control
			failure made this metric describe the wrong thing entirely.
		]]
		log(string.format(
			"possession acquisitions=%d releases=%d lostControl=%d (distance=%d unexpected=%d) tackled=%d meanDuration=%.2fs lead=[%.2f, %.2f]",
			stats.Acquisitions,
			stats.Releases,
			stats.UnintendedReleases,
			stats.DistanceExceeded,
			stats.Unexpected,
			stats.Tackled,
			stats.MeanControlDuration,
			stats.MinLead,
			stats.MaxLead
		))
	end
	for _, teamModel in teams do
		local designated = teamModel.DesignatedActor and teamModel.DesignatedActor.DisplayName or "none"
		log(string.format(
			"team=%s state=%s controller=%s designated=%s timeToBall=%.2f",
			teamModel.TeamId,
			teamModel.State,
			teamModel.Controller and teamModel.Controller.DisplayName or "none",
			designated,
			teamModel.DesignatedTime or -1
		))
	end
end

--[[
	LEGACY CONTINUITY FALLBACK -- only where match rules are not running (§36).

	This predates the rules system. It existed so a 3v3 development match did
	not stall when the ball went out, by simply teleporting it back into play.
	Beyond 90 now has real throw-ins, corners and goal kicks, and two systems
	owning out-of-play recovery means the legacy one can fire first and skip the
	restart entirely -- which is what the runtime evidence showed.

	It now only runs when the match rules are NOT governing play, which is
	exactly the development/testing case it was written for.
]]
local function updateOutOfPlayRecovery()
	if MatchRulesService.IsGoverningPlay and MatchRulesService.IsGoverningPlay() then
		outOfPlaySince = nil
		return
	end
	if not ball or ball:GetAttribute("State") ~= "Free" then
		outOfPlaySince = nil
		return
	end
	local offset = BallControlMath.GetHorizontal(ball.Position - pitchState.Center)
	local padding = AIConfig.Recovery.OutOfPlayPadding
	local outside = math.abs(offset:Dot(pitchState.LengthAxis)) > pitchState.Length * 0.5 + padding
		or math.abs(offset:Dot(pitchState.WidthAxis)) > pitchState.Width * 0.5 + padding
	local stationary = BallControlMath.GetHorizontal(ball.AssemblyLinearVelocity).Magnitude
		<= AIConfig.Recovery.StationarySpeed
	if not outside or not stationary or ball:GetAttribute("FootballGrounded") ~= true then
		outOfPlaySince = nil
		return
	end
	outOfPlaySince = outOfPlaySince or os.clock()
	if os.clock() - outOfPlaySince >= AIConfig.Recovery.ResetDelay then
		log("Stationary out-of-play ball reset for 3v3 continuity")
		outOfPlaySince = nil
		BallService.Reset()
	end
end

--[[
	Goal celebration (§69).

	The scorer runs away toward the touchline; everyone else simply stops playing
	football. No AI continues normal tactics through a celebration.
]]
local function updateCelebration(deltaTime: number)
	local scorerId = MatchRulesService.GetCelebration()

	for _, actor in aiActors do
		if refreshActor(actor) then
			actor.ActionPending = false
			actor.State = if scorerId == actor.Id then "Celebrating" else "CelebrationHold"

			if scorerId == actor.Id and pitchState then
				-- Run toward the nearer touchline, which is where a scorer goes.
				local lateral = BallControlMath.GetHorizontal(actor.RootPart.Position - pitchState.Center)
					:Dot(pitchState.WidthAxis)
				local direction = pitchState.WidthAxis * (if lateral >= 0 then 1 else -1)
				local target = actor.RootPart.Position + direction * MatchRulesConfig.Celebration.RunDistance
				actor.MovementTarget = clampToPitch(target)
				local toTarget = BallControlMath.GetHorizontal(actor.MovementTarget - actor.RootPart.Position)
				if toTarget.Magnitude > AIConfig.Locomotion.ArrivalRadius then
					actor.CurrentSpeed = moveToward(
						actor.CurrentSpeed,
						AIConfig.Locomotion.SprintSpeed * 0.7,
						AIConfig.Locomotion.SprintSpeed / math.max(AIConfig.Locomotion.AccelerationTime, 0.05) * deltaTime
					)
					actor.Humanoid.WalkSpeed = actor.CurrentSpeed
					actor.Humanoid:Move(toTarget.Unit, false)
				else
					actor.CurrentSpeed = 0
					actor.Humanoid.WalkSpeed = 0
					actor.Humanoid:Move(Vector3.zero, false)
				end
			else
				actor.CurrentSpeed = 0
				actor.Humanoid.WalkSpeed = 0
				actor.Humanoid:Move(Vector3.zero, false)
			end

			AIAnimationService.Update(actor)
			AIAnimationService.StepRootMotion(actor, deltaTime)
			actor.Character:SetAttribute(AIConfig.Attributes.State, actor.State)
		end
	end
end

--[[
	Set-piece behaviour (§66).

	During a restart everyone holds the position RestartService placed them in --
	except the designated taker, who walks to the ball and plays it. The taker
	uses the ordinary acquisition and passing path, so a restart produces a real
	football action rather than a scripted ball teleport.
]]
local function updateRestartBehaviour(deltaTime: number)
	local taker = RestartService.GetTaker()
	local restartReady = MatchRulesService.GetPhase() == MatchRulesConfig.Phases.RestartReady

	-- Keepers are tracked separately but must take their own goal kicks, so the
	-- restart loop covers both lists.
	local participants = {}
	for _, actor in aiActors do
		table.insert(participants, actor)
	end
	for _, keeper in aiKeepers do
		table.insert(participants, keeper)
	end

	for _, actor in participants do
		if refreshActor(actor) then
			local isTaker = taker ~= nil and taker.Id == actor.Id
			actor.ActionPending = false
			actor.PossessionStartedAt = nil
			actor.CommittedReceiver = nil
			actor.State = if isTaker then "RestartTaker" else "RestartHold"

			if isTaker and restartReady and ball then
				-- Walk onto the ball; acquisition and the pass follow naturally.
				local toBall = BallControlMath.GetHorizontal(ball.Position - actor.RootPart.Position)
				local distance = toBall.Magnitude
				actor.MovementTarget = ball.Position
				if distance > AIConfig.Locomotion.ArrivalRadius * 0.5 then
					-- Walk to a nearby restart, but run to a distant one so a
					-- corner at the far end is still taken inside the window.
					local approachSpeed = if distance > AIConfig.Locomotion.SprintDistance
						then AIConfig.Locomotion.SprintSpeed
						else AIConfig.Locomotion.JogSpeed * 0.75
					actor.CurrentSpeed = moveToward(
						actor.CurrentSpeed,
						approachSpeed,
						AIConfig.Locomotion.SprintSpeed / math.max(AIConfig.Locomotion.AccelerationTime, 0.05) * deltaTime
					)
					actor.Humanoid.WalkSpeed = actor.CurrentSpeed
					actor.Humanoid:Move(toBall.Unit, false)
				else
					actor.CurrentSpeed = 0
					actor.Humanoid.WalkSpeed = 0
					actor.Humanoid:Move(Vector3.zero, false)

					--[[
						Take the restart with a LEGAL RESTART ACTION.

						This used to call BallControlService.TryAcquireAI, which is
						exactly how a kick-off ended up being taken as an ordinary
						TakeInStride reception followed by the AI dribbling away.
						An AI now takes a set piece the same way a human does: it
						plays a pass, a throw or a shot, and the restart completes
						because MatchRulesService accepted that action.
					]]
					local restartKind = RestartService.GetActiveRestartKind()
					if restartKind and not actor.RestartAttemptAt then
						-- A short beat before playing it, so a restart does not
						-- fire on the same frame the taker arrives.
						actor.RestartAttemptAt = os.clock() + AIConfig.Restart.TakeDelaySeconds
					end
					if restartKind and actor.RestartAttemptAt and os.clock() >= actor.RestartAttemptAt then
						local taken, reason = FootballActionService.ExecuteAIRestart(actor, restartKind)
						if taken then
							actor.RestartAttemptAt = nil
						else
							-- Retry on a bounded cadence rather than every frame.
							actor.RestartAttemptAt = os.clock() + AIConfig.Restart.RetrySeconds
							if AIConfig.Debug.Enabled and reason ~= "" then
								log(string.format("%s could not take the %s yet (%s)", actor.DisplayName, restartKind, reason))
							end
						end
					end
				end
			else
				-- Everyone else stands still exactly where they were placed.
				actor.RestartAttemptAt = nil
				actor.CurrentSpeed = 0
				actor.Humanoid.WalkSpeed = 0
				actor.Humanoid:Move(Vector3.zero, false)
			end

			AIAnimationService.Update(actor)
			AIAnimationService.StepRootMotion(actor, deltaTime)
			actor.Character:SetAttribute(AIConfig.Attributes.State, actor.State)
		end
	end
end

-- Before kickoff every footballer holds its formation anchor. Decisions,
-- ball pursuit and actions are all suppressed -- this is a real gate on the AI
-- decision layer, not a visual freeze.
local function updatePreMatchHold(deltaTime: number)
	--[[
		Once the field has been ASSEMBLED (§23) every footballer is already
		standing exactly where the kick-off requires. Seeking a formation anchor
		from there would visibly drag the whole team out of the shape the player
		is about to be shown, so PreMatch is a true freeze rather than a hold.
	]]
	local assembled = MatchRulesService.IsPreMatch()

	for _, actor in aiActors do
		if refreshActor(actor) then
			actor.State = if assembled then "AwaitingStart" else "AwaitingKickoff"
			actor.ActionPending = false
			actor.PossessionStartedAt = nil
			actor.CommittedReceiver = nil
			if assembled then
				actor.CurrentSpeed = 0
				actor.Humanoid.WalkSpeed = 0
				actor.Humanoid:Move(Vector3.zero, false)
				actor.Humanoid:SetAttribute("SprintRequested", false)
				AIAnimationService.Update(actor)
				actor.Character:SetAttribute(AIConfig.Attributes.State, actor.State)
				continue
			end
			actor.MovementTarget = actor.FormationTarget or actor.RootPart.Position
			local toTarget = BallControlMath.GetHorizontal(actor.MovementTarget - actor.RootPart.Position)
			local distance = toTarget.Magnitude
			if distance > AIConfig.Locomotion.ArrivalRadius then
				local direction = toTarget.Unit
				actor.CurrentSpeed = moveToward(
					actor.CurrentSpeed,
					AIConfig.Locomotion.JogSpeed * 0.6,
					AIConfig.Locomotion.SprintSpeed / math.max(AIConfig.Locomotion.AccelerationTime, 0.05) * deltaTime
				)
				actor.Humanoid.WalkSpeed = actor.CurrentSpeed
				actor.Humanoid:Move(direction, false)
			else
				actor.CurrentSpeed = 0
				actor.Humanoid.WalkSpeed = 0
				actor.Humanoid:Move(Vector3.zero, false)
			end
			actor.Humanoid:SetAttribute("SprintRequested", false)
			AIAnimationService.Update(actor)
			actor.Character:SetAttribute(AIConfig.Attributes.State, actor.State)
		end
	end
end

local function onHeartbeat(deltaTime: number)
	if not active then
		return
	end
	MatchService.Update()

	perceptionAccumulator += deltaTime
	teamAccumulator += deltaTime
	individualAccumulator += deltaTime
	movementAccumulator += deltaTime
	debugAccumulator += deltaTime

	-- Perception and formation targets stay warm so kickoff shape is correct,
	-- but nothing that can touch the football runs before Playing.
	--[[
		AI stops playing football during ANY stoppage, not just before kick-off:
		celebrations, restarts, injuries and half time all hold shape instead
		(§78). Set-piece positioning is RestartService's job, so nothing here
		needs to fight it.
	]]
	if not MatchRulesService.AllowsFootballActions() then
		if perceptionAccumulator >= AIConfig.Cadence.PerceptionInterval then
			perceptionAccumulator = 0
			updatePerception()
		end
		if teamAccumulator >= AIConfig.Cadence.TeamInterval then
			teamAccumulator = 0
			for _, teamModel in teams do
				for _, actor in teamModel.Actors do
					if refreshActor(actor) then
						actor.FormationTarget = getFormationTarget(actor, teamModel)
					end
				end
			end
		end
		if movementAccumulator >= AIConfig.Cadence.MovementInterval then
			local movementDelta = movementAccumulator
			movementAccumulator = 0
			if MatchRulesService.IsRestartActive() then
				updateRestartBehaviour(movementDelta)
			elseif MatchRulesService.GetPhase() == MatchRulesConfig.Phases.GoalCelebration then
				updateCelebration(movementDelta)
			else
				updatePreMatchHold(movementDelta)
			end
			-- Keepers position themselves but take no action before Playing.
			GoalkeeperService.Update(movementDelta)
		end
		individualAccumulator = 0
		debugAccumulator = 0
		return
	end

	if perceptionAccumulator >= AIConfig.Cadence.PerceptionInterval then
		perceptionAccumulator = 0
		updatePerception()
	end
	if teamAccumulator >= AIConfig.Cadence.TeamInterval then
		teamAccumulator = 0
		updateTeams()
		updateOutOfPlayRecovery()
	end
	if individualAccumulator >= AIConfig.Cadence.IndividualInterval then
		individualAccumulator = 0
		updateIndividuals()
	end
	if movementAccumulator >= AIConfig.Cadence.MovementInterval then
		local movementDelta = movementAccumulator
		movementAccumulator = 0
		updateMovement(movementDelta)
		GoalkeeperService.Update(movementDelta)
	end
	if debugAccumulator >= AIConfig.Cadence.DebugInterval then
		debugAccumulator = 0
		updateDebug()
	end
end

function AIService.Initialize(resolvedPitchState, activeBall: BasePart)
	if initialized then
		return
	end
	initialized = true
	pitchState = resolvedPitchState
	ball = activeBall
	FootballerRegistryService.Initialize()
	heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	goalConnection = GoalService.GetGoalScoredEvent().Event:Connect(function()
		GoalkeeperService.ResetForKickoff()
		for _, actor in aiActors do
			actor.State = "Recover"
			actor.ActionPending = false
		end
		task.delay(0.25, function()
			if active then
				updatePerception()
				updateTeams()
				updateIndividuals()
			end
		end)
	end)
end

--[[
	Return the model for `teamId`, creating an empty one if this mode never
	built a roster. Used by DEV tooling so AI can be added outside a 3v3 session.
]]
local function ensureTeamModel(teamId: string)
	if teamId ~= "Home" and teamId ~= "Away" then
		return nil
	end
	if not ball then
		return nil
	end
	local existing = teams[teamId]
	if existing then
		return existing
	end
	local model = {
		TeamId = teamId,
		State = "LooseBall",
		Actors = {},
		PerceivedBallPosition = ball.Position,
	}
	teams[teamId] = model
	-- AI added this way still needs the normal update loop to run.
	active = true
	return model
end

function AIService.Start3v3()
	if not initialized or not ball or not pitchState then
		return
	end
	active = true
	outOfPlaySince = nil
	lastPossessionChangedAt = os.clock()
	BallControlService.ResetAIPossessionStats()
	rebuildTeams()
end

function AIService.Refresh3v3()
	if active then
		rebuildTeams()
	end
end

function AIService.Stop()
	active = false
	outOfPlaySince = nil
	if ball and BallControlService.GetActiveAIController() then
		BallControlService.ReleaseAI(ball, "3v3 stopped")
	end
	AIAnimationService.Clear()
	for _, keeper in aiKeepers do
		GoalkeeperService.Unregister(keeper)
	end
	for _, keeper in humanKeepers do
		GoalkeeperService.Unregister(keeper)
	end
	FootballerRegistryService.ClearAI()
	table.clear(aiActors)
	table.clear(aiKeepers)
	table.clear(humanKeepers)
	table.clear(teams)
end


--[[
	DEV tooling: add or remove one AI goalkeeper on a team.

	Uses the same createAIActor / GoalkeeperService.Register path as normal
	spawning, so a keeper added this way is a real footballer in the registry,
	on the minimap and in the goalkeeper update loop. Removal tears down every
	one of those references rather than just destroying the model.
]]
function AIService.SetGoalkeeperEnabled(teamId: string, enabled: boolean): (boolean, string)
	if not initialized or not ball or not pitchState then
		return false, "ai-not-initialized"
	end
	if not ensureTeamModel(teamId) then
		return false, "invalid-team"
	end

	local existingIndex = nil
	for index, keeper in aiKeepers do
		if keeper.TeamId == teamId then
			existingIndex = index
			break
		end
	end

	if enabled then
		if existingIndex then
			return false, "already-present"
		end
		local keeper = createAIActor(teamId, GoalkeeperConfig.Role, 90 + 1, true)
		if not keeper then
			return false, "spawn-failed"
		end
		GoalkeeperService.Register(keeper)
		table.insert(aiKeepers, keeper)
		return true, "goalkeeper-added"
	end

	if not existingIndex then
		return false, "not-present"
	end

	local keeper = aiKeepers[existingIndex]
	-- Never leave a removed keeper holding the football.
	if BallControlService.IsControlledByAI(keeper, ball) then
		BallControlService.ReleaseAI(ball, "DEV removed goalkeeper")
	end
	GoalkeeperService.Unregister(keeper)
	AIAnimationService.Unregister(keeper)
	-- UnregisterAI destroys the character unless told otherwise.
	FootballerRegistryService.UnregisterAI(keeper)
	table.remove(aiKeepers, existingIndex)
	return true, "goalkeeper-removed"
end

function AIService.HasGoalkeeper(teamId: string): boolean
	for _, keeper in aiKeepers do
		if keeper.TeamId == teamId then
			return true
		end
	end
	return false
end

function AIService.IsActive(): boolean
	return active
end

function AIService.GetAICount(teamId: string): number
	local count = 0
	for _, actor in aiActors do
		if actor.TeamId == teamId then
			count += 1
		end
	end
	return count
end

--[[
	DEV tooling: add or remove one outfield AI on a team without rebuilding the
	whole roster. Goes through the same createAIActor / registry path as normal
	spawning, so nothing is left orphaned.
]]
function AIService.AdjustAICount(teamId: string, delta: number, maximumPerTeam: number): (boolean, string)
	if not initialized or not ball or not pitchState then
		return false, "ai-not-initialized"
	end
	--[[
		DEV tooling must work in Training, which never runs Start3v3 and so has no
		team models at all -- that is what previously failed as `team-not-active`.

		A team model is just a container for shape and possession state; it does
		not imply a competitive session or a full roster. Creating an empty one on
		demand lets a developer add a single AI teammate or defender to Training
		without turning Training into a 3v3 match.
	]]
	local teamModel = ensureTeamModel(teamId)
	if not teamModel then
		return false, "team-not-active"
	end

	if delta > 0 then
		local current = AIService.GetAICount(teamId)
		if current >= maximumPerTeam then
			return false, "team-full"
		end
		-- Prefer a role nobody on this team is filling yet.
		local usedRoles = {}
		for _, actor in teamModel.Actors do
			usedRoles[actor.Role] = true
		end
		local chosenRole = roleOrder[1]
		for _, role in roleOrder do
			if not usedRoles[role] then
				chosenRole = role
				break
			end
		end
		local slotIndex = current + 1
		local actor = createAIActor(teamId, chosenRole, slotIndex)
		if not actor then
			return false, "spawn-failed"
		end
		updatePerception()
		updateTeams()
		updateIndividuals()
		return true, string.format("%s x%d", chosenRole, AIService.GetAICount(teamId))
	end

	-- Remove the most recently added AI on that team.
	for index = #aiActors, 1, -1 do
		local actor = aiActors[index]
		if actor.TeamId == teamId then
			-- Release possession safely before the character disappears.
			if BallControlService.IsControlledByAI(actor, ball) then
				BallControlService.ReleaseAI(ball, "DEV removed AI")
			end
			AIAnimationService.Unregister(actor)
			table.remove(aiActors, index)
			for teamIndex = #teamModel.Actors, 1, -1 do
				if teamModel.Actors[teamIndex] == actor then
					table.remove(teamModel.Actors, teamIndex)
				end
			end
			if teamModel.DesignatedActor == actor then
				teamModel.DesignatedActor = nil
			end
			FootballerRegistryService.UnregisterAI(actor, true)
			return true, string.format("removed, %d left", AIService.GetAICount(teamId))
		end
	end
	return false, "none-to-remove"
end

return AIService
