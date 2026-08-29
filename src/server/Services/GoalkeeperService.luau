local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GoalkeeperConfig = require(Shared.Config.GoalkeeperConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local GoalkeeperPositioning = require(Shared.Football.GoalkeeperPositioning)
local TrajectoryPredictor = require(Shared.Football.TrajectoryPredictor)

local AIAnimationService = require(script.Parent.AIAnimationService)
local BallControlService = require(script.Parent.BallControlService)
local FootballerRegistryService = require(script.Parent.FootballerRegistryService)
local GoalService = require(script.Parent.GoalService)
local MatchService = require(script.Parent.MatchService)
local MatchRulesService = require(script.Parent.MatchRulesService)
local RestartService = require(script.Parent.RestartService)

--[[
	Goalkeeper behaviour and the goalkeeper possession state.

	Every action here takes an actor record, never a Player -- an AI goalkeeper
	is only an intent provider, and a human goalkeeper can call the same
	Request* functions later without any code path testing IsAI.
]]
local GoalkeeperService = {}

local initialized = false
local ball: BasePart? = nil
local keepers: { [number]: any } = {}
local heldBy: any = nil
local heldSince = 0
local lastSaveAtById: { [number]: number } = {}
local lastLogAt = 0

local function log(message: string)
	if GoalkeeperConfig.Debug.Enabled then
		print(string.format("%s[GK] %s", GameConfig.LogPrefix, message))
	end
end

local function getDefendedGoal(actor)
	local mapping = FootballTeamConfig.GetGoalMapping(actor.TeamId)
	local goals = GoalService.GetGoals()
	return mapping and goals[mapping.DefendedGoalId]
end

local function getAttackingGoal(actor)
	local mapping = FootballTeamConfig.GetGoalMapping(actor.TeamId)
	local goals = GoalService.GetGoals()
	return mapping and goals[mapping.AttackingGoalId]
end

function GoalkeeperService.IsGoalkeeper(actor): boolean
	return actor ~= nil and actor.Position == GoalkeeperConfig.Role
end

function GoalkeeperService.IsHeld(): boolean
	return heldBy ~= nil
end

function GoalkeeperService.GetHolder()
	return heldBy
end

--[[
	DEV: set goalkeeper skill, 0-1 (§52).

	Applies to every keeper on `teamId`, or to all of them when no team is given,
	so a test can change the difficulty mid-session without respawning.
]]
function GoalkeeperService.SetSkill(skill: number, teamId: string?): number
	local clamped = math.clamp(skill, GoalkeeperConfig.Skill.Minimum, GoalkeeperConfig.Skill.Maximum)
	local count = 0
	for _, actor in keepers do
		if teamId == nil or actor.TeamId == teamId then
			actor.GoalkeeperSkill = clamped
			if actor.Character then
				actor.Character:SetAttribute(GoalkeeperConfig.Skill.AttributeName, clamped)
			end
			count += 1
		end
	end
	log(string.format("Goalkeeper skill -> %.0f for %d keeper(s)", clamped * 100, count))
	return clamped
end

function GoalkeeperService.GetSkill(teamId: string?): number
	for _, actor in keepers do
		if teamId == nil or actor.TeamId == teamId then
			return actor.GoalkeeperSkill or GoalkeeperConfig.Skill.Default
		end
	end
	return GoalkeeperConfig.Skill.Default
end

function GoalkeeperService.Register(actor)
	actor.Position = GoalkeeperConfig.Role
	actor.GoalkeeperSkill = actor.GoalkeeperSkill or GoalkeeperConfig.Skill.Default
	if actor.Character then
		actor.Character:SetAttribute(GoalkeeperConfig.RoleAttributeName, GoalkeeperConfig.Role)
		actor.Character:SetAttribute(GoalkeeperConfig.Skill.AttributeName, actor.GoalkeeperSkill)
	end
	keepers[actor.Id] = actor
end

function GoalkeeperService.Unregister(actorOrId)
	local id = if typeof(actorOrId) == "number" then actorOrId else actorOrId and actorOrId.Id
	if not id then
		return
	end
	if heldBy and heldBy.Id == id then
		GoalkeeperService.Release(heldBy, "keeper removed")
	end
	keepers[id] = nil
	lastSaveAtById[id] = nil
end

-- Secure goalkeeper possession. Deliberately NOT foot-dribble possession: the
-- football is constrained to the keeper rather than pushed/coasted/collected.
function GoalkeeperService.Hold(actor): boolean
	if not ball or heldBy or not actor or not actor.RootPart then
		return false
	end
	if BallControlService.GetActiveController() or BallControlService.GetActiveAIController() then
		return false
	end
	heldBy = actor
	heldSince = os.clock()
	ball:SetAttribute(GoalkeeperConfig.HeldAttributeName, true)
	ball:SetAttribute(GoalkeeperConfig.HolderAttributeName, actor.Id)
	ball:SetAttribute("State", "Controlled")
	ball:SetAttribute("ControllerKind", "Goalkeeper")
	ball:SetAttribute("ControllerFootballerId", actor.Id)
	ball:SetAttribute("ControllerUserId", if actor.Player then actor.Player.UserId else 0)
	pcall(function()
		ball:SetNetworkOwner(nil)
	end)
	log(string.format("%s secured the football", actor.DisplayName))
	return true
end

function GoalkeeperService.Release(actor, reason: string, launchVelocity: Vector3?): boolean
	if not ball or not heldBy or (actor and heldBy.Id ~= actor.Id) then
		return false
	end
	heldBy = nil
	heldSince = 0
	ball:SetAttribute(GoalkeeperConfig.HeldAttributeName, false)
	ball:SetAttribute(GoalkeeperConfig.HolderAttributeName, 0)
	ball:SetAttribute("State", "Free")
	ball:SetAttribute("ControllerKind", "")
	ball:SetAttribute("ControllerFootballerId", 0)
	ball:SetAttribute("ControllerUserId", 0)
	ball:SetAttribute("LastReleaseReason", reason)
	if launchVelocity then
		ball.AssemblyLinearVelocity = launchVelocity
		ball:SetAttribute("FootballFlightComplete", false)
		ball:SetAttribute("FootballGrounded", false)
		ball:SetAttribute("FootballBounceCount", 0)
		ball:SetAttribute("LastFootballAction", "GoalkeeperDistribution")
		ball:SetAttribute("LastFootballActionPlayerUserId", heldBy and heldBy.Id or 0)
		ball:SetAttribute("LastFootballActionTime", os.clock())
	end
	log(string.format("Release: %s", reason))
	return true
end

-- Keep a held football pinned in front of the keeper. This is the one place a
-- constrained ball is legitimate; it is not the foot-dribble servo.
local function updateHeldBall()
	if not heldBy or not ball then
		return
	end
	if not heldBy.RootPart or not heldBy.RootPart.Parent then
		GoalkeeperService.Release(heldBy, "keeper invalid")
		return
	end
	local root = heldBy.RootPart
	local forward = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(root.CFrame.LookVector),
		Vector3.zAxis
	)
	local target = root.Position + forward * GoalkeeperConfig.Possession.HoldOffset
		+ Vector3.yAxis * (GoalkeeperConfig.Possession.HoldHeight - root.Size.Y * 0.5)
	ball.CFrame = CFrame.new(target)
	ball.AssemblyLinearVelocity = root.AssemblyLinearVelocity
	ball.AssemblyAngularVelocity = Vector3.zero
end

--[[
	A goalkeeper controlled by a real player.

	This is the ONLY test of controller identity in the file. Everything below it
	is still expressed as "what does a keeper do"; being human changes who
	supplies the intent and which assistance applies, never what a save is.
]]
local function isHumanKeeper(actor): boolean
	return actor ~= nil and actor.Player ~= nil
end

--[[
	Skill, 0-1. One accessor so nothing reads the raw field and forgets to clamp.

	A human keeper is exempt: the skill model exists to make a BOT worse in
	football-legible ways (late reactions, bad positioning, misread crossing
	points, spilled handling), and applying it to a person would degrade their
	own reactions rather than model anything. Their difficulty comes from the
	dive envelope, which is not part of this number.
]]
local function getSkill(actor): number
	if isHumanKeeper(actor) then
		return GoalkeeperConfig.Human.Skill
	end
	return math.clamp(
		actor.GoalkeeperSkill or GoalkeeperConfig.Skill.Default,
		GoalkeeperConfig.Skill.Minimum,
		GoalkeeperConfig.Skill.Maximum
	)
end

--[[
	Interpolate a skill-scaled quantity.

	`atZero` is what a skill-0 keeper gets, `atOne` what a perfect keeper gets.
	Every skill effect goes through this, so "skill 100 has no error" is a
	property of the model rather than a special case sprinkled through the code.
]]
local function bySkill(skill: number, atZero: number, atOne: number): number
	return atZero + (atOne - atZero) * skill
end

--[[
	POSITIONING ERROR (§54).

	A weak keeper stands in the wrong place. The offset is held for a short
	interval rather than re-rolled every frame, so it reads as a keeper being
	badly positioned rather than as one vibrating.
]]
local function getPositioningError(actor, goal): Vector3
	local config = GoalkeeperConfig.Skill
	local skill = getSkill(actor)
	local magnitude = bySkill(skill, config.MaximumPositioningErrorStuds, 0)
	if magnitude <= 0.01 then
		return Vector3.zero
	end
	local now = os.clock()
	if not actor.GoalkeeperPositionErrorAt or now - actor.GoalkeeperPositionErrorAt >= config.PositioningErrorInterval then
		actor.GoalkeeperPositionErrorAt = now
		-- Along the goal line: being a yard off your near post is the error that
		-- actually matters, not standing a yard too deep.
		actor.GoalkeeperPositionErrorAlpha = (math.random() * 2 - 1)
	end
	local alpha = actor.GoalkeeperPositionErrorAlpha or 0
	return goal.WidthAxis * (alpha * magnitude)
end

--[[
	WHICH SAVE IS THIS? (§56)

	Decided from the intercept geometry -- how far across the keeper must go and
	how high the ball is -- not from a random pick. Returns the dive kind, the
	launch speed, the lift, and the semantic animation hook.
]]
local function classifySave(actor, goal, interceptPoint: Vector3)
	local dive = GoalkeeperConfig.Dive
	local root = actor.RootPart
	local toIntercept = BallControlMath.GetHorizontal(interceptPoint - root.Position)
	local lateral = toIntercept:Dot(goal.WidthAxis)
	local distance = toIntercept.Magnitude
	local height = interceptPoint.Y - root.Position.Y
	local rightward = lateral >= 0

	if distance <= dive.StandingReach then
		return "Standing", 0, 0, nil
	end
	if distance <= dive.LateralStepDistance then
		return "Step",
			dive.StepSpeed,
			0,
			if rightward then dive.Actions.StepRight else dive.Actions.StepLeft
	end
	if height <= dive.LowBallHeight then
		return "LowDive",
			dive.LowDiveSpeed,
			dive.LowDiveLift,
			if rightward then dive.Actions.DiveLowRight else dive.Actions.DiveLowLeft
	end
	return "HighDive",
		dive.HighDiveSpeed,
		dive.HighDiveLift,
		if rightward then dive.Actions.DiveHighRight else dive.Actions.DiveHighLeft
end

--[[
	DIVE (§55).

	Real physical movement toward the intercept: a bounded velocity impulse, then
	the keeper is committed for the duration. No teleport, no CFrame snap across
	the goal.

	Returns whether the keeper actually committed.
]]
function GoalkeeperService.RequestDive(actor, interceptPoint: Vector3, goal): boolean
	local dive = GoalkeeperConfig.Dive
	if dive.Enabled ~= true or not actor.RootPart or not actor.RootPart.Parent then
		return false
	end
	local now = os.clock()
	if actor.GoalkeeperDiveUntil and now < actor.GoalkeeperDiveUntil then
		-- Already committed. A dive cannot be re-steered mid-air.
		return true
	end
	if actor.GoalkeeperDiveRecoveryUntil and now < actor.GoalkeeperDiveRecoveryUntil then
		return false
	end

	local kind, speed, lift, action = classifySave(actor, goal, interceptPoint)
	if kind == "Standing" then
		return false
	end

	local toIntercept = BallControlMath.GetHorizontal(interceptPoint - actor.RootPart.Position)
	if toIntercept.Magnitude > dive.MaximumLateralReach then
		-- Genuinely out of reach. A keeper who dived here would only look silly.
		return false
	end

	--[[
		COMMITMENT (§54). A weak keeper sometimes stays on its feet and watches
		it go past -- a real goalkeeping error, and a readable one.
	]]
	local skill = getSkill(actor)
	local commitChance = bySkill(skill, GoalkeeperConfig.Skill.MinimumCommitChance, 1)
	-- A human who pressed dive has already made the decision. Rolling against it
	-- would be the game refusing an input, which is never a football error.
	if not isHumanKeeper(actor) and math.random() > commitChance then
		log(string.format("%s did not commit to the dive (skill=%.2f)", actor.DisplayName, skill))
		actor.GoalkeeperDiveRecoveryUntil = now + dive.RecoverySeconds * 0.5
		return false
	end

	local direction = BallControlMath.SafeUnit(toIntercept, goal.WidthAxis)
	actor.RootPart.AssemblyLinearVelocity = direction * speed + Vector3.yAxis * lift
	actor.GoalkeeperDiveUntil = now + dive.Duration
	actor.GoalkeeperDiveRecoveryUntil = now + dive.Duration + dive.RecoverySeconds
	actor.GoalkeeperDiveKind = kind
	actor.State = "GoalkeeperDive"

	--[[
		Presentation. The dive clips are not authored yet, so the semantic hook is
		recorded on the character -- a client or a future animation service can
		read it -- and the nearest existing reach clip is played meanwhile.
	]]
	if actor.Character then
		actor.Character:SetAttribute("Beyond90GoalkeeperDive", action or kind)
		actor.Character:SetAttribute("Beyond90GoalkeeperDiveAt", now)
		--[[
			A dive is server-driven physical movement. The owning client must stop
			steering for its duration, or the human's own locomotion immediately
			cancels the impulse it just asked for.
		]]
		actor.Character:SetAttribute(GoalkeeperConfig.Attributes.Diving, true)
		task.delay(dive.Duration, function()
			if actor.Character and actor.Character.Parent then
				actor.Character:SetAttribute(GoalkeeperConfig.Attributes.Diving, false)
			end
		end)
	end
	AIAnimationService.PlayAction(actor, dive.FallbackAction)

	log(string.format(
		"%s dives %s toward (%.1f, %.1f, %.1f) speed=%.0f",
		actor.DisplayName, kind, interceptPoint.X, interceptPoint.Y, interceptPoint.Z, speed
	))
	return true
end

function GoalkeeperService.IsDiving(actor): boolean
	return actor.GoalkeeperDiveUntil ~= nil and os.clock() < actor.GoalkeeperDiveUntil
end

--[[
	Save attempt. Controller-agnostic: an AI goalkeeper and a future human
	goalkeeper call this identically.
	Returns outcome: "Catch" | "Parry" | "Miss" | rejection reason
]]
function GoalkeeperService.RequestSave(actor, interceptPoint: Vector3): string
	if not ball or not actor or not actor.RootPart then
		return "invalid-keeper"
	end
	local config = GoalkeeperConfig.Save
	local now = os.clock()
	local lastAt = lastSaveAtById[actor.Id]
	if lastAt and now - lastAt < config.Cooldown then
		return "cooldown"
	end
	lastSaveAtById[actor.Id] = now

	--[[
		Once the whole ball is behind the goal line the goal has already happened.
		GoalService remains authoritative for that; the keeper simply must not be
		credited with a save afterwards, which would otherwise show up as a catch
		logged immediately before a goal for the same shot.
	]]
	local defendedGoal = getDefendedGoal(actor)
	if defendedGoal then
		local pitchward = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(defendedGoal.InwardDirection),
			Vector3.zAxis
		)
		local ballRadius = ball.Size.X * 0.5
		if (ball.Position - defendedGoal.MouthCenter):Dot(pitchward) < -ballRadius then
			return "already-conceded"
		end
	end

	local skill = getSkill(actor)
	local skillConfig = GoalkeeperConfig.Skill

	--[[
		REACH (§53). Skill buys a genuinely longer dive within a hard ceiling, so
		an elite keeper covers more of the goal -- but a shot placed outside that
		envelope still scores. 100 is not omnipotent.
	]]
	local toBall = ball.Position - actor.RootPart.Position
	local horizontalDistance = BallControlMath.GetHorizontal(toBall).Magnitude
	local reach = config.ReachRadius + bySkill(skill, skillConfig.MinimumDiveReach, skillConfig.MaximumDiveReach)
	if horizontalDistance > reach then
		return "out-of-reach"
	end
	if ball.Position.Y > actor.RootPart.Position.Y + config.MaximumSaveHeight then
		return "too-high"
	end

	--[[
		HANDLING (§54), not dice.

		A weak keeper's failure is concentrated at the EDGE of its reach, where a
		real keeper's is: a shot straight at a poor keeper is still saved, one
		into the corner is not. At skill 1 both terms are zero, so an elite keeper
		never spills a ball it actually reached.
	]]
	local reachAlpha = math.clamp(horizontalDistance / math.max(reach, 1e-3), 0, 1)
	local failureChance = bySkill(skill, config.BaseFailureChance, 0)
		+ reachAlpha * reachAlpha * bySkill(skill, 0.45, 0)
	if math.random() < failureChance then
		log(string.format("%s could not hold it (skill=%.2f, reach=%.2f)", actor.DisplayName, skill, reachAlpha))
		return "Miss"
	end

	local ballSpeed = ball.AssemblyLinearVelocity.Magnitude
	--[[
		Catch versus parry. A strong keeper catches what a weak one only pushes
		away, and stretching at full reach is always a parry regardless of skill.
	]]
	local catchChance = bySkill(skill, skillConfig.MinimumCatchChance, skillConfig.MaximumCatchChance)
		* (1 - reachAlpha * 0.5)
	-- How hard a shot this keeper can hold, rather than only push away (§53).
	local catchSpeedLimit = bySkill(skill, config.CatchMaximumBallSpeed, config.CatchMaximumBallSpeedAtFullSkill)
	local canCatch = ballSpeed <= catchSpeedLimit
		and ball.Position.Y <= actor.RootPart.Position.Y + config.CatchMaximumHeight
		and math.random() <= catchChance

	if canCatch and GoalkeeperService.Hold(actor) then
		-- The clip stumbles slightly to the keeper's right; root motion matches it.
		AIAnimationService.PlayAction(actor, "KeeperCatchStanding")
		log(string.format("%s caught the football (ballSpeed=%.1f)", actor.DisplayName, ballSpeed))
		return "Catch"
	end

	--[[
		Parry: deflect out onto the pitch, not into the net.

		InwardDirection already points from the mouth into the pitch, so it is
		used directly. Negating it here sent every parry backwards over the
		keeper's own goal line.
	]]
	local goal = defendedGoal
	local outward = if goal
		then BallControlMath.SafeUnit(BallControlMath.GetHorizontal(goal.InwardDirection), Vector3.zAxis)
		else BallControlMath.SafeUnit(BallControlMath.GetHorizontal(ball.Position - actor.RootPart.Position), Vector3.zAxis)
	--[[
		PARRY QUALITY (§54). A strong keeper pushes the ball firmly away from
		danger; a weak one only takes the pace off it, leaving a rebound.
	]]
	local parryQuality = bySkill(skill, GoalkeeperConfig.Skill.MinimumParryQuality, 1)
	local lateral = Vector3.new(-outward.Z, 0, outward.X) * ((math.random() - 0.5) * 2 * 0.6)
	local deflection = BallControlMath.SafeUnit(outward + lateral, outward) * (config.ParryDeflectionSpeed * parryQuality)
		+ Vector3.yAxis * (config.ParryLift * parryQuality)
	ball.AssemblyLinearVelocity = deflection
	ball:SetAttribute("FootballFlightComplete", false)
	ball:SetAttribute("FootballGrounded", false)
	--[[
		No dedicated dive or parry clip exists yet, so the standing catch is used
		as the nearest valid reach. The semantic hook is here: point this at a
		parry/dive asset when one is authored.
	]]
	AIAnimationService.PlayAction(actor, "KeeperCatchStanding")
	log(string.format("%s parried the football (ballSpeed=%.1f)", actor.DisplayName, ballSpeed))
	return "Parry"
end

-- Distribute a securely held football to a teammate, or clear upfield.
--[[
	Distribution, optionally AIMED.

	Without a hint this picks the nearest teammate, which is the right default
	for an AI keeper. A human keeper supplies the direction they are facing, and
	then the choice becomes "the best teammate in the direction I am throwing"
	rather than "whoever happens to be closest" -- so a keeper can deliberately
	start an attack down one side instead of always rolling it to the nearest
	centre-back. With a hint and nobody usable in that direction, the ball is
	cleared along the hint rather than at the far goal.
]]
function GoalkeeperService.RequestDistribution(actor, directionHint: Vector3?): boolean
	if not ball or not heldBy or heldBy.Id ~= actor.Id then
		return false
	end
	local config = GoalkeeperConfig.Distribution
	if config.Enabled ~= true then
		return false
	end

	local aim = nil
	if directionHint then
		local flat = BallControlMath.GetHorizontal(directionHint)
		if flat.Magnitude > 0.05 then
			aim = flat.Unit
		end
	end

	local best, bestScore = nil, -math.huge
	for _, candidate in FootballerRegistryService.GetAll() do
		if candidate.Id ~= actor.Id
			and candidate.TeamId == actor.TeamId
			and candidate.RootPart
			and candidate.RootPart.Parent
		then
			local offset = BallControlMath.GetHorizontal(candidate.RootPart.Position - actor.RootPart.Position)
			local distance = offset.Magnitude
			if distance >= config.MinimumDistance and distance <= config.MaximumDistance then
				local score
				if aim then
					-- Alignment first, then distance as the tie-breaker: a teammate
					-- behind the keeper is never the target of a forward throw.
					local alignment = offset.Unit:Dot(aim)
					score = if alignment < 0.25 then -math.huge else alignment - distance / config.MaximumDistance * 0.25
				else
					score = -distance
				end
				if score > bestScore then
					best, bestScore = candidate, score
				end
			end
		end
	end

	local attackingGoal = getAttackingGoal(actor)
	local direction
	if best then
		direction = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(best.RootPart.Position - actor.RootPart.Position),
			BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector)
		)
	elseif aim then
		direction = aim
	elseif attackingGoal then
		direction = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(attackingGoal.MouthCenter - actor.RootPart.Position),
			BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector)
		)
	else
		direction = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector),
			Vector3.zAxis
		)
	end

	-- Keeper steps into the throw and recovers ~70% of that distance.
	AIAnimationService.PlayAction(actor, "KeeperThrowPass")
	local launch = direction * config.ClearanceSpeed + Vector3.yAxis * config.ClearanceLift
	GoalkeeperService.Release(actor, "goalkeeper distribution", launch)
	if best then
		ball:SetAttribute("LastFootballActionIntendedReceiverUserId", best.Id)
		ball:SetAttribute("LastFootballActionIntendedReceiverName", best.DisplayName)
	end
	log(string.format("%s distributed to %s", actor.DisplayName, if best then best.DisplayName else "space"))
	return true
end

--[[
	THE HUMAN GOALKEEPER TICK.

	Split out from UpdateKeeper rather than woven into it with `if actor.Player`
	branches, because the two are genuinely different jobs. The AI tick decides
	WHERE TO STAND and then walks there; this one never moves the footballer at
	all -- the player does that -- and instead does three things:

	  1. Publishes what the keeper can see (where the line is, whether a shot is
	     coming and when it arrives) so the client can assist positioning and
	     prompt the dive.
	  2. Performs the assisted half automatically: anything that arrives within
	     arm's length is gathered, and a loose ball in the six-yard box is
	     claimed, without an input.
	  3. Leaves the dive -- the decision, the direction and above all the moment
	     -- entirely to the player.

	Nothing here calls Humanoid:Move or writes the root CFrame. The client owns
	this character; a server that also steered it would fight the player every
	frame, which is the failure mode that makes networked keepers feel broken.
]]
local function updateHumanKeeper(actor, deltaTime: number, goal)
	local human = GoalkeeperConfig.Human
	local positioning = GoalkeeperConfig.Positioning
	local saveConfig = GoalkeeperConfig.Save
	local character = actor.Character
	local playing = MatchRulesService.AllowsFootballActions()
	local activeBall = ball :: BasePart
	local ballPosition = activeBall.Position
	local holding = heldBy ~= nil and heldBy.Id == actor.Id

	if character then
		character:SetAttribute(GoalkeeperConfig.Attributes.Holding, holding)
	end

	--[[
		Holding: pin the football and wait for the player to choose where it goes.
		Update() still force-distributes at MaximumHoldSeconds, so possession can
		never simply be parked in the keeper's hands.
	]]
	if holding then
		updateHeldBall()
		actor.State = "GoalkeeperHeld"
		if character then
			character:SetAttribute("Beyond90AIState", actor.State)
		end
		return
	end

	-- A dive is committed movement the server launched. Do not steer it; only
	-- allow the save it was launched for.
	if GoalkeeperService.IsDiving(actor) then
		actor.State = "GoalkeeperDive"
		local diveReach = BallControlMath.GetHorizontal(ballPosition - actor.RootPart.Position).Magnitude
		if diveReach <= saveConfig.ReachRadius + GoalkeeperConfig.Dive.StandingReach then
			GoalkeeperService.RequestSave(actor, ballPosition)
		end
		if character then
			character:SetAttribute("Beyond90AIState", actor.State)
		end
		return
	end

	actor.State = "GoalkeeperPosition"

	--[[
		Where the keeper SHOULD be standing -- published, never applied.

		The same angular-bisector resting position the AI keeper walks to, handed
		to the client so it can drift the player toward it when they are not
		steering. Assistance the player can always override by simply holding a
		direction.
	]]
	if character then
		local resting = GoalkeeperPositioning.GetRestingPosition(
			goal, ballPosition, positioning.DepthBias, positioning
		)
		character:SetAttribute(GoalkeeperConfig.Attributes.RestingPosition, resting)
	end

	if not playing then
		actor.GoalkeeperThreatPoint = nil
		actor.GoalkeeperThreatSeconds = nil
		if character then
			character:SetAttribute(GoalkeeperConfig.Attributes.ThreatActive, false)
			character:SetAttribute("Beyond90AIState", actor.State)
		end
		return
	end

	--[[
		IS A SHOT COMING?

		No reaction delay is applied -- the player's own reaction IS the delay.
		The result is published so the HUD can prompt, and remembered so a dive
		request has a real intercept to aim at instead of guessing from where the
		ball happens to be at the moment the key went down.
	]]
	local samples = TrajectoryPredictor.Sample(
		ballPosition,
		activeBall.AssemblyLinearVelocity,
		saveConfig.PredictionSeconds,
		saveConfig.PredictionSteps
	)
	local bound, interceptPoint, timeToGoal = GoalkeeperPositioning.IsBallBoundForGoal(
		goal, samples, saveConfig.PredictionSeconds, saveConfig.PanicWidthScale, saveConfig.MaximumSaveHeight
	)
	actor.GoalkeeperThreatPoint = if bound then interceptPoint else nil
	actor.GoalkeeperThreatSeconds = if bound then timeToGoal else nil
	if character then
		character:SetAttribute(GoalkeeperConfig.Attributes.ThreatActive, bound == true)
		if bound and interceptPoint and timeToGoal then
			character:SetAttribute(GoalkeeperConfig.Attributes.ThreatPoint, interceptPoint)
			character:SetAttribute(GoalkeeperConfig.Attributes.ThreatSeconds, timeToGoal)
		end
	end

	--[[
		THE ASSISTED HALF (1): anything within arm's length is handled.

		A keeper standing in the right place does not lose a shot struck straight
		at them because the player did not press anything. Restricted to a ball
		that is genuinely loose or genuinely on its way in, so the keeper is not a
		black hole that swallows every teammate's back-pass off the floor.
	]]
	local reach = BallControlMath.GetHorizontal(ballPosition - actor.RootPart.Position).Magnitude
	local ballIsFree = activeBall:GetAttribute("State") == "Free"
	if reach <= human.AssistedSaveRadius
		and ballPosition.Y <= actor.RootPart.Position.Y + saveConfig.MaximumSaveHeight
		and (bound or ballIsFree)
	then
		GoalkeeperService.RequestSave(actor, ballPosition)
		if character then
			character:SetAttribute("Beyond90AIState", actor.State)
		end
		return
	end

	--[[
		THE ASSISTED HALF (2): a slow loose ball in front of the keeper is
		gathered. The same region rule the AI keeper uses, so a human keeper's
		authority over their own six-yard box is identical to a bot's.
	]]
	if ballIsFree
		and not BallControlService.GetActiveController()
		and not BallControlService.GetActiveAIController()
	then
		local region = GoalkeeperConfig.Region
		local ballToGoal = BallControlMath.GetHorizontal(ballPosition - goal.MouthCenter).Magnitude
		if ballToGoal <= region.ClaimRadius
			and ballPosition.Y <= goal.BottomY + region.ClaimMaximumBallHeight
			and reach <= human.AssistedClaimRadius
		then
			GoalkeeperService.Hold(actor)
		end
	end

	if character then
		character:SetAttribute("Beyond90AIState", actor.State)
	end
end

--[[
	THE EARNED HALF: the player commits to a dive.

	Called from the keeper action remote. The timing is the whole skill, so this
	deliberately does NOT snap onto the ball:

	  * With a live shot, the keeper launches at the intercept it read. Press too
	    early and the dive is spent before the ball arrives; too late and the
	    committed duration cannot cover the distance. Both are misses the player
	    can see they caused.
	  * With no shot to read, the dive still happens -- in the direction asked
	    for, at a speculative point. Panicking has to cost something, or "always
	    be diving" would be the optimal strategy.

	`directionHint` comes from the player's own input, so diving the wrong way is
	possible and is a real mistake.
]]
function GoalkeeperService.RequestHumanDive(actor, directionHint: Vector3?): (boolean, string)
	if not ball or not actor or not actor.RootPart or not actor.RootPart.Parent then
		return false, "invalid-keeper"
	end
	if GoalkeeperConfig.Human.Enabled ~= true then
		return false, "human-keeper-disabled"
	end
	if not MatchRulesService.AllowsFootballActions() then
		return false, "ball-not-in-play"
	end
	if heldBy and heldBy.Id == actor.Id then
		return false, "holding-ball"
	end
	local goal = getDefendedGoal(actor)
	if not goal then
		return false, "no-goal"
	end

	local now = os.clock()
	if GoalkeeperService.IsDiving(actor) then
		return false, "already-diving"
	end
	if actor.GoalkeeperDiveRecoveryUntil and now < actor.GoalkeeperDiveRecoveryUntil then
		return false, "recovering"
	end
	if actor.GoalkeeperHumanDiveAt and now - actor.GoalkeeperHumanDiveAt < GoalkeeperConfig.Human.DiveCooldown then
		return false, "cooldown"
	end
	actor.GoalkeeperHumanDiveAt = now

	local human = GoalkeeperConfig.Human
	local interceptPoint = actor.GoalkeeperThreatPoint
	local timeToGoal = actor.GoalkeeperThreatSeconds

	--[[
		THE TIMING WINDOW. A read shot is only divable inside it; outside, the
		request becomes a speculative dive in the direction asked for, which is
		exactly what diving too early looks like.
	]]
	local timedWell = interceptPoint ~= nil
		and timeToGoal ~= nil
		and timeToGoal <= human.DiveEarliestSeconds
		and timeToGoal >= human.DiveLatestSeconds

	local target
	if timedWell then
		target = interceptPoint
	else
		local aim = nil
		if directionHint then
			local flat = BallControlMath.GetHorizontal(directionHint)
			if flat.Magnitude > 0.05 then
				aim = flat.Unit
			end
		end
		if not aim then
			aim = BallControlMath.SafeUnit(
				BallControlMath.GetHorizontal((ball :: BasePart).Position - actor.RootPart.Position),
				goal.WidthAxis
			)
		end
		target = actor.RootPart.Position + aim * human.SpeculativeDiveDistance
	end

	local dived = GoalkeeperService.RequestDive(actor, target, goal)
	if not dived then
		-- Close enough that a dive is the wrong action: take it standing.
		local outcome = GoalkeeperService.RequestSave(actor, (ball :: BasePart).Position)
		if outcome == "Catch" or outcome == "Parry" then
			return true, outcome
		end
		return false, outcome
	end
	return true, if timedWell then "Dive" else "SpeculativeDive"
end

--[[
	Per-keeper decision + movement. Called from AIService's movement tick so the
	cadence stays bounded rather than running its own 60 Hz loop.
]]
function GoalkeeperService.UpdateKeeper(actor, deltaTime: number)
	if not ball or not actor.RootPart or not actor.RootPart.Parent then
		return
	end
	local goal = getDefendedGoal(actor)
	if not goal then
		return
	end
	local positioning = GoalkeeperConfig.Positioning
	local playing = MatchRulesService.AllowsFootballActions()

	--[[
		A human keeper is a different job entirely -- it is never steered from
		here -- so it branches before any of the movement logic below runs.
	]]
	if isHumanKeeper(actor) then
		updateHumanKeeper(actor, deltaTime, goal)
		return
	end

	--[[
		Nothing moves before the user starts the match (§25). The keeper has
		already been placed on its line by field assembly, so holding still here
		is what keeps the first visible frame correct.
	]]
	if MatchRulesService.IsPreMatch() then
		actor.Humanoid.WalkSpeed = 0
		actor.Humanoid:Move(Vector3.zero, false)
		actor.State = "AwaitingStart"
		if actor.Character then
			actor.Character:SetAttribute("Beyond90AIState", actor.State)
		end
		return
	end

	--[[
		A keeper taking its own goal kick must be left alone.

		Otherwise this drags it straight back onto its line every frame, and the
		goal kick it was chosen to take is never reachable -- which is exactly
		why goal kicks were being abandoned.
	]]
	if MatchRulesService.IsRestartActive() then
		local taker = RestartService.GetTaker()
		if taker and taker.Id == actor.Id then
			return
		end
	end

	-- Holding the ball: pin it, then distribute after a short beat.
	if heldBy and heldBy.Id == actor.Id then
		updateHeldBall()
		actor.Humanoid.WalkSpeed = 0
		actor.Humanoid:Move(Vector3.zero, false)
		actor.State = "GoalkeeperHeld"
		if playing and os.clock() - heldSince >= GoalkeeperConfig.Possession.HoldSeconds then
			GoalkeeperService.RequestDistribution(actor)
		end
		return
	end

	local ballPosition = ball.Position
	local distanceToGoal = BallControlMath.GetHorizontal(ballPosition - goal.MouthCenter).Magnitude
	local threatened = distanceToGoal < GoalkeeperConfig.Region.MaximumDistanceFromGoal
	local depthBias = if threatened then positioning.RushDepthBias else positioning.DepthBias
	local targetSpeed = positioning.MoveSpeed
	actor.State = "GoalkeeperPosition"

	--[[
		A COMMITTED DIVE OWNS THE KEEPER (§55).

		While airborne the keeper is not steered: no walk target, no facing
		correction. That is what makes diving the wrong way a real mistake rather
		than something the positioning logic quietly corrects.
	]]
	if GoalkeeperService.IsDiving(actor) then
		actor.State = "GoalkeeperDive"
		actor.Humanoid.WalkSpeed = 0
		actor.Humanoid:Move(Vector3.zero, false)
		-- Still allowed to make the save it dived for.
		local reach = BallControlMath.GetHorizontal(ballPosition - actor.RootPart.Position).Magnitude
		if reach <= GoalkeeperConfig.Save.ReachRadius + GoalkeeperConfig.Dive.StandingReach then
			GoalkeeperService.RequestSave(actor, ballPosition)
		end
		if actor.Character then
			actor.Character:SetAttribute("Beyond90AIState", actor.State)
		end
		return
	end

	if playing and GoalkeeperConfig.Save.Enabled == true and threatened then
		-- Is the football on its way into this goal?
		local saveConfig = GoalkeeperConfig.Save
		local samples = TrajectoryPredictor.Sample(
			ballPosition,
			ball.AssemblyLinearVelocity,
			saveConfig.PredictionSeconds,
			saveConfig.PredictionSteps
		)
		local skill = getSkill(actor)
		local skillConfig = GoalkeeperConfig.Skill
		local panic = saveConfig.PanicWidthScale + (1 - skill) * 0.1
		local bound, interceptPoint, timeToGoal = GoalkeeperPositioning.IsBallBoundForGoal(
			goal, samples, saveConfig.PredictionSeconds, panic, saveConfig.MaximumSaveHeight
		)

		if bound and interceptPoint and timeToGoal then
			--[[
				REACTION DELAY (§54). The keeper must SEE the shot before acting on
				it. Even a perfect keeper has the irreducible delay of a real one;
				a poor keeper adds far more, which is what makes a hard shot past a
				weak keeper feel earned rather than random.
			]]
			local now = os.clock()
			if actor.GoalkeeperThreatSince == nil then
				actor.GoalkeeperThreatSince = now
			end
			local reactionDelay = bySkill(skill, skillConfig.MaximumReactionDelay, skillConfig.MinimumReactionDelay)

			if now - actor.GoalkeeperThreatSince >= reactionDelay then
				actor.State = "GoalkeeperSave"
				targetSpeed = positioning.RushSpeed

				--[[
					INTERCEPT MISJUDGEMENT (§54). A weak keeper reads the crossing
					point wrong and goes to the wrong place -- a football error, and
					one the shooter can see they induced. Zero at skill 1.
				]]
				local interceptError = bySkill(skill, skillConfig.MaximumInterceptErrorStuds, 0)
				local judgedIntercept = interceptPoint
				if interceptError > 0.01 then
					judgedIntercept = interceptPoint
						+ goal.WidthAxis * ((math.random() * 2 - 1) * interceptError)
				end

				local savePoint = GoalkeeperPositioning.GetAchievableSavePoint(
					actor.RootPart.Position, judgedIntercept, timeToGoal, positioning.RushSpeed, 8
				)
				actor.GoalkeeperTarget = Vector3.new(savePoint.X, goal.MouthCenter.Y, savePoint.Z)

				local reach = BallControlMath.GetHorizontal(ballPosition - actor.RootPart.Position).Magnitude

				if reach <= saveConfig.ReachRadius then
					-- Close enough to stay on its feet.
					GoalkeeperService.RequestSave(actor, interceptPoint)
				elseif timeToGoal <= GoalkeeperConfig.Dive.MaximumInterceptTime then
					--[[
						Too far to reach standing, and the ball arrives soon: this is
						what a dive is for. The keeper physically launches toward the
						point it JUDGED, so a misjudgement sends it the wrong way.
					]]
					GoalkeeperService.RequestDive(actor, judgedIntercept, goal)
				end
			end
		else
			-- Threat gone; the reaction timer resets for the next one.
			actor.GoalkeeperThreatSince = nil
		end
	else
		actor.GoalkeeperThreatSince = nil
	end

	-- Claim a slow loose ball inside the keeper region.
	if playing and actor.State ~= "GoalkeeperSave"
		and ball:GetAttribute("State") == "Free"
		and not BallControlService.GetActiveController()
		and not BallControlService.GetActiveAIController()
	then
		local region = GoalkeeperConfig.Region
		local keeperToBall = BallControlMath.GetHorizontal(ballPosition - actor.RootPart.Position).Magnitude
		local ballToGoal = BallControlMath.GetHorizontal(ballPosition - goal.MouthCenter).Magnitude
		if ballToGoal <= region.ClaimRadius
			and ballPosition.Y <= goal.BottomY + region.ClaimMaximumBallHeight
		then
			actor.State = "GoalkeeperClaim"
			targetSpeed = positioning.RushSpeed
			actor.GoalkeeperTarget = Vector3.new(ballPosition.X, goal.MouthCenter.Y, ballPosition.Z)
			if keeperToBall <= GoalkeeperConfig.Save.ReachRadius * 0.7 then
				GoalkeeperService.Hold(actor)
				return
			end
		end
	end

	if actor.State == "GoalkeeperPosition" then
		--[[
			Skill-scaled positioning error (§54). A weak keeper stands off its
			near post; a perfect one is exactly where it should be.
		]]
		actor.GoalkeeperTarget = GoalkeeperPositioning.GetRestingPosition(
			goal,
			ballPosition,
			if playing then depthBias else positioning.DepthBias,
			positioning
		) + getPositioningError(actor, goal)
	end

	-- Move. Standard Humanoid locomotion, no teleporting.
	local target = actor.GoalkeeperTarget or actor.RootPart.Position
	local toTarget = BallControlMath.GetHorizontal(target - actor.RootPart.Position)
	local distance = toTarget.Magnitude
	if distance > positioning.ArrivalRadius then
		actor.Humanoid.WalkSpeed = targetSpeed
		actor.Humanoid:Move(toTarget.Unit, false)
	else
		actor.Humanoid.WalkSpeed = 0
		actor.Humanoid:Move(Vector3.zero, false)
	end

	-- Face the football so saves and distribution read correctly.
	local facing = BallControlMath.GetHorizontal(ballPosition - actor.RootPart.Position)
	if facing.Magnitude > 1 then
		local current = BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector)
		local blended = BallControlMath.SafeUnit(
			current.Unit:Lerp(facing.Unit, math.clamp(deltaTime * 8, 0, 1)),
			current
		)
		if blended.Magnitude > 0 then
			actor.RootPart.CFrame = CFrame.lookAt(actor.RootPart.Position, actor.RootPart.Position + blended)
		end
	end

	AIAnimationService.UpdateGoalkeeper(actor, heldBy ~= nil and heldBy.Id == actor.Id, deltaTime)

	if actor.Character then
		actor.Character:SetAttribute("Beyond90AIState", actor.State)
	end
end

function GoalkeeperService.Update(deltaTime: number)
	if not ball then
		return
	end
	-- A held ball cannot be held forever.
	if heldBy and os.clock() - heldSince >= GoalkeeperConfig.Possession.MaximumHoldSeconds then
		GoalkeeperService.RequestDistribution(heldBy)
	end
	for _, actor in keepers do
		if actor.Character and actor.Character.Parent and actor.Humanoid and actor.Humanoid.Health > 0 then
			GoalkeeperService.UpdateKeeper(actor, deltaTime)
		end
	end
end

function GoalkeeperService.ResetForKickoff()
	if heldBy then
		GoalkeeperService.Release(heldBy, "kickoff reset")
	end
	table.clear(lastSaveAtById)
end

--[[
	The human keeper's input channel.

	Deliberately a REQUEST, not a command: the client says "I am diving, roughly
	this way" and the server decides whether that dive happens, where it goes and
	whether it saves anything. Nothing the client sends can produce a save on its
	own -- the same rule that governs shooting and tackling.

	Everything off this remote is validated: that the sender is a footballer at
	all, that they are a REGISTERED goalkeeper (so a striker cannot dive), and
	that the direction is a real Vector3 rather than whatever the caller felt
	like sending.
]]
local function onKeeperAction(player: Player, action: unknown, directionHint: unknown)
	if typeof(action) ~= "string" then
		return
	end
	local actor = FootballerRegistryService.GetHumanActor(player)
	if not actor or not keepers[actor.Id] then
		return
	end
	if not isHumanKeeper(actor) then
		return
	end

	local hint = nil
	if typeof(directionHint) == "Vector3" then
		local flat = BallControlMath.GetHorizontal(directionHint)
		if flat.Magnitude > 0.05 and flat.Magnitude < 1e4 then
			hint = flat.Unit
		end
	end

	if action == "Dive" then
		local ok, reason = GoalkeeperService.RequestHumanDive(actor, hint)
		if not ok then
			log(string.format("%s dive rejected: %s", actor.DisplayName, reason))
		end
	elseif action == "Distribute" then
		if heldBy and heldBy.Id == actor.Id then
			GoalkeeperService.RequestDistribution(actor, hint)
		end
	end
end

function GoalkeeperService.Initialize(activeBall: BasePart)
	if initialized then
		return
	end
	initialized = true
	ball = activeBall
	ball:SetAttribute(GoalkeeperConfig.HeldAttributeName, false)
	ball:SetAttribute(GoalkeeperConfig.HolderAttributeName, 0)

	local remotes = ReplicatedStorage:FindFirstChild(FootballActionConfig.RemotesFolderName)
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = FootballActionConfig.RemotesFolderName
		remotes.Parent = ReplicatedStorage
	end
	local remote = remotes:FindFirstChild(GoalkeeperConfig.ActionRemoteName)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = GoalkeeperConfig.ActionRemoteName
		remote.Parent = remotes
	end
	assert(remote:IsA("RemoteEvent"), "GoalkeeperAction exists but is not a RemoteEvent")
	remote.OnServerEvent:Connect(onKeeperAction)
end

return GoalkeeperService
