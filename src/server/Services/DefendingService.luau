local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallConfig = require(Shared.Config.BallConfig)
local DefendingConfig = require(Shared.Config.DefendingConfig)
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local FoulEvaluator = require(Shared.Football.FoulEvaluator)
local MatchRulesConfig = require(Shared.Config.MatchRulesConfig)
local PositionConfig = require(Shared.Config.PositionConfig)
local InterceptionEvaluator = require(Shared.Football.InterceptionEvaluator)
local TackleEvaluator = require(Shared.Football.TackleEvaluator)

local AIAnimationService = require(script.Parent.AIAnimationService)
local BallControlService = require(script.Parent.BallControlService)
local FootballerRegistryService = require(script.Parent.FootballerRegistryService)
local MatchService = require(script.Parent.MatchService)
local MatchRulesService = require(script.Parent.MatchRulesService)
local InjuryService = require(script.Parent.InjuryService)

--[[
	Standing tackle / press, server-authoritative.

	A successful challenge makes the football LOOSE. It is never handed to the
	tackler -- both footballers then contest the recovery through the normal
	acquisition path.
]]
local DefendingService = {}

local initialized = false
local requestRemote: RemoteEvent? = nil
local feedbackRemote: RemoteEvent? = nil
local lastTackleAtById: { [number]: number } = {}
local recoveryUntilById: { [number]: number } = {}
local lastInterceptionAtById: { [number]: number } = {}
local lastSlideAtById: { [number]: number } = {}
--[[
	Challenges that have been COMMITTED but not yet resolved.

	id -> { Actor, ActionType, OpensAt, ClosesAt }. See DefendingConfig.ContactWindow
	for why a challenge occupies a span of time rather than resolving at the
	instant it was asked for.
]]
local pendingChallengeById: { [number]: any } = {}
--[[
	Where the football was at the end of the previous tick.

	Interception is judged over the SEGMENT the ball travelled, not from where it
	happens to be when the tick fires, so the previous sample is the other half of
	the evidence. See InterceptionEvaluator: a pass crosses a defender's reach in
	well under one tick, and a point sample misses it almost every time.
]]
local previousBallPosition: Vector3? = nil
local interceptionConnection: RBXScriptConnection? = nil

local function log(message: string)
	if DefendingConfig.DebugEnabled then
		print(string.format("%s[Defending] %s", GameConfig.LogPrefix, message))
	end
end

local function getOrCreateRemote(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getFootball(): BasePart?
	local root = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local folder = root and root:FindFirstChild("Ball")
	local ball = folder and folder:FindFirstChild(BallConfig.Name)
	return if ball and ball:IsA("BasePart") then ball else nil
end

local function toEvaluatorRecord(actor)
	return {
		-- Execution quality only; legality is position-independent.
		TackleSkill = PositionConfig.GetSkill(actor.PositionSlotId, "Tackling"),
		Position = actor.RootPart.Position,
		Velocity = actor.RootPart.AssemblyLinearVelocity,
		FacingDirection = actor.RootPart.CFrame.LookVector,
	}
end

local function sendFeedback(actor, accepted: boolean, reason: string, result, actionType: string?)
	if not feedbackRemote or not actor.Player then
		return
	end
	feedbackRemote:FireClient(actor.Player, {
		-- Which challenge this was about, so the client can tell a rejected
		-- slide from a rejected standing tackle rather than logging both alike.
		ActionType = actionType or DefendingConfig.Tackle.ActionType,
		Accepted = accepted,
		Reason = reason,
		Outcome = result and result.Outcome or "Missed",
		Score = result and result.Score or 0,
	})
end

function DefendingService.IsRecovering(footballerId: number): boolean
	local until_ = recoveryUntilById[footballerId]
	return until_ ~= nil and os.clock() < until_
end

-- Shared by the human remote handler and the AI decision layer. `actor` is a
-- FootballerRegistryService actor record of either kind.
--[[
	Non-committal look at what a challenge by `actor` would produce right now.

	AI defenders use this to decide WHETHER to challenge. Without it the AI fired
	the moment it came within tackling range of the ball -- which, while chasing a
	carrier, is usually from behind -- and every attempt was correctly thrown out
	as `challenge-from-behind`, burning the cooldown and the recovery penalty for
	a tackle that never had a chance.

	This performs no state change: no cooldown, no recovery, no logging.
]]
--[[
	Score an unsuccessful challenge for a foul.

	Every term comes from geometry the tackle evaluator has already measured, so
	a clean front tackle can never produce a foul and a mistimed challenge from
	behind always does. A serious one may also injure the victim.
]]
--[[
	`severityScale` lets a slide carry more consequence for the same mistake.

	Deliberately a multiplier on the score the ordinary evaluation produces
	rather than a second set of rules: a slide is judged on exactly the same
	geometry as any other challenge -- mistiming, contact, angle, closing speed --
	and simply costs more when it is wrong, which is what the laws of the game
	say about it. Defaults to 1, so the standing tackle is unchanged.
]]
local function reportFoulIfContact(challenger, victim, result, severityScale: number?)
	if MatchRulesConfig.Foul.Enabled ~= true then
		return
	end
	if not challenger.RootPart or not victim.RootPart then
		return
	end
	local football = getFootball()
	if not football then
		return
	end

	local contactDistance = BallControlMath.GetHorizontal(
		challenger.RootPart.Position - victim.RootPart.Position
	).Magnitude
	local victimBallDistance = BallControlMath.GetHorizontal(
		football.Position - victim.RootPart.Position
	).Magnitude
	local relativeSpeed = BallControlMath.GetHorizontal(
		challenger.RootPart.AssemblyLinearVelocity - victim.RootPart.AssemblyLinearVelocity
	).Magnitude

	local decision = FoulEvaluator.Evaluate({
		WonBall = result.Outcome == "Won" or result.Outcome == "Partial",
		BehindDot = result.BehindDot or 0,
		ContactDistance = contactDistance,
		VictimBallDistance = victimBallDistance,
		RelativeSpeed = relativeSpeed,
		ContactRadius = DefendingConfig.Tackle.MaximumBallDistance,
	}, MatchRulesConfig.Foul)

	local scale = severityScale or 1
	if decision and scale ~= 1 then
		decision.Severity *= scale
		-- Re-read the seriousness band at the scaled severity: a slide that
		-- would have been an ordinary foul standing up can be a serious one.
		decision.Type = if decision.Severity >= MatchRulesConfig.Foul.Severity.SeriousThreshold
			then "SeriousFoul"
			else "Foul"
	end

	if not decision then
		--[[
			Not a foul, but a hard legal collision can still leave someone hurt
			(§71). Rare by design: the chance is small and scaled by how fast the
			challenger actually came in.
		]]
		if relativeSpeed >= MatchRulesConfig.Foul.RecklessRelativeSpeed
			and contactDistance <= DefendingConfig.Tackle.MaximumBallDistance
		then
			InjuryService.Consider(
				victim,
				"Collision",
				math.clamp(relativeSpeed / (MatchRulesConfig.Foul.RecklessRelativeSpeed * 2), 0, 1)
			)
		end
		return
	end

	MatchRulesService.ReportFoul(challenger, victim, decision)

	if decision.Type == "SeriousFoul" then
		InjuryService.Consider(victim, "SeriousFoul", math.clamp(decision.Severity - 1, 0, 1))
	end
end

function DefendingService.PreviewTackle(actor): any
	if not actor or not actor.RootPart or not actor.RootPart.Parent then
		return nil
	end

	local ball = getFootball()
	if not ball or ball:GetAttribute("State") ~= "Controlled" then
		return nil
	end
	if ball:GetAttribute("GoalkeeperHeld") == true then
		return nil
	end

	local carrierId = ball:GetAttribute("ControllerFootballerId")
	if typeof(carrierId) ~= "number" or carrierId == 0 or carrierId == actor.Id then
		return nil
	end
	local carrier = FootballerRegistryService.GetActorById(carrierId)
	if not carrier or not carrier.RootPart or not carrier.RootPart.Parent then
		return nil
	end
	if carrier.TeamId ~= nil and carrier.TeamId == actor.TeamId then
		return nil
	end

	return TackleEvaluator.Evaluate(
		toEvaluatorRecord(actor),
		toEvaluatorRecord(carrier),
		ball.Position,
		DefendingConfig.Tackle
	)
end

--[[
	THE CONTACT, resolved from the sweep rather than from the input.

	Everything below is unchanged from when this ran directly off the button; what
	changed is WHEN it runs. The eligibility checks that used to sit above it --
	match state, cooldown, recovery -- now happen once at commit, because by the
	time this executes the player is already committed and it is too late to
	decline. See DefendingService.AttemptTackle.
]]
local function performTackle(actor, now: number): (boolean, string, any)
	local ball = getFootball()
	if not ball then
		return false, "ball-missing", nil
	end
	if ball:GetAttribute("State") ~= "Controlled" then
		return false, "ball-already-loose", nil
	end

	-- Goalkeeper-held possession is not contestable by a standing tackle.
	if ball:GetAttribute("GoalkeeperHeld") == true then
		return false, "goalkeeper-held", nil
	end

	local carrierId = ball:GetAttribute("ControllerFootballerId")
	if typeof(carrierId) ~= "number" or carrierId == 0 or carrierId == actor.Id then
		return false, "no-valid-carrier", nil
	end
	local carrier = FootballerRegistryService.GetActorById(carrierId)
	if not carrier or not carrier.RootPart or not carrier.RootPart.Parent then
		return false, "carrier-invalid", nil
	end
	if carrier.TeamId ~= nil and carrier.TeamId == actor.TeamId then
		return false, "carrier-is-teammate", nil
	end

	local result = TackleEvaluator.Evaluate(
		toEvaluatorRecord(actor),
		toEvaluatorRecord(carrier),
		ball.Position,
		DefendingConfig.Tackle
	)

	if not result.Valid then
		recoveryUntilById[actor.Id] = now + DefendingConfig.Tackle.FailedRecoverySeconds
		--[[
			An illegal challenge that still made contact is a foul, not a no-op.
			This is the whole point: a defender who goes through the back of the
			carrier concedes a free kick rather than simply being ignored.
		]]
		reportFoulIfContact(actor, carrier, result)
		log(string.format("[Tackle] %s -> %s rejected=%s", actor.DisplayName, carrier.DisplayName, result.Reason))
		return false, result.Reason, result
	end

	if result.Outcome == "Missed" then
		reportFoulIfContact(actor, carrier, result)
	end

	if result.Outcome == "Missed" then
		recoveryUntilById[actor.Id] = now + DefendingConfig.Tackle.FailedRecoverySeconds
		log(string.format(
			"[Tackle] %s -> %s outcome=Missed score=%.2f exposure=%.2f",
			actor.DisplayName, carrier.DisplayName, result.Score, result.Exposure or 0
		))
		return false, "missed", result
	end

	--[[
		WHERE THE WON BALL GOES (§43).

		A clean win and a partial win are now genuinely different outcomes.

		  Won      -- the ball is poked into the TACKLER'S own control lane: a
		             short, gentle touch just in front of them. It is still a free
		             football that an opponent may reach first, but the tackler is
		             the one standing over it, so the ordinary Capture path picks
		             it up and the challenge reads as winning possession.

		  Partial  -- unchanged. The ball is knocked away with a random lateral
		             spread and is a genuine contest.

		Possession is never assigned directly. The tackler goes through exactly
		the same legal acquisition every other footballer uses, which is what
		keeps a tackle from being a possession-granting privileged API.
	]]
	local config = DefendingConfig.Tackle
	local won = result.Outcome == "Won"
	local launchVelocity

	if won then
		local control = config.WonBallControl
		local forward = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector),
			result.LooseDirection
		)
		--[[
			Blend the tackler's facing with the natural direction of the challenge
			so the touch still looks like it came off the contact rather than
			being magnetically redirected.
		]]
		local direction = BallControlMath.SafeUnit(
			forward * control.FacingWeight + result.LooseDirection * (1 - control.FacingWeight),
			forward
		)
		launchVelocity = direction * control.Speed + Vector3.yAxis * control.Lift
	else
		local speed = config.LooseBallPartialSpeed
		local lateral = Vector3.new(-result.LooseDirection.Z, 0, result.LooseDirection.X)
			* ((math.random() - 0.5) * 2 * config.LooseBallLateralSpread * speed)
		launchVelocity = result.LooseDirection * speed + lateral + Vector3.yAxis * config.LooseBallLift
	end

	local released
	if carrier.IsAI then
		released = BallControlService.ReleaseAIForFootballAction(
			ball, carrier, "Tackled", launchVelocity,
			{ TargetKind = "Loose" }
		)
	else
		released = BallControlService.ReleaseForFootballAction(
			ball, carrier.Player, "Tackled", launchVelocity,
			config.VictimAcquisitionSuppression, config.VictimExitDistance,
			{ TargetKind = "Loose" }
		)
	end

	if not released then
		recoveryUntilById[actor.Id] = now + DefendingConfig.Tackle.RecoverySeconds
		return false, "release-rejected", result
	end

	-- Play the reaction the challenge actually produced. A clean poke staggers
	-- the carrier; a heavier challenge from front or behind puts them down, and
	-- the clip's root motion carries the body in the right direction.
	if carrier.IsAI then
		local reaction = "TackledNormal"
		if result.Outcome == "Won" and result.Score >= config.SuccessThreshold + 0.15 then
			reaction = if (result.BehindDot or 0) > 0.25 then "TackledSlideBack" else "TackledSlideFront"
		end
		AIAnimationService.PlayAction(carrier, reaction)
		carrier.TackleRecoveryUntil = now + DefendingConfig.Tackle.RecoverySeconds
	end
	if carrier.Player then
		-- Humans animate their own reaction locally off this attribute.
		carrier.Character:SetAttribute("Beyond90TackledAt", now)
		carrier.Character:SetAttribute("Beyond90TackledOutcome", result.Outcome)
		carrier.Character:SetAttribute("Beyond90TackledBehindDot", result.BehindDot or 0)
	end

	--[[
		A CLEAN win is allowed to be collected; a PARTIAL win is not.

		Suppressing the tackler after a clean challenge was what made every
		successful tackle end with the ball rolling to somebody else. A partial
		challenge keeps the suppression, because that outcome is meant to be a
		contest rather than a turnover.
	]]
	if won then
		if actor.Player then
			BallControlService.RegisterReacquisitionClaim(
				actor.Player,
				config.WonBallControl.ClaimSeconds,
				config.WonBallControl.ClaimScoreBonus
			)
		else
			--[[
				The AI equivalent of that claim. AIService's designated-chaser
				selection already gives a head start to the footballer the ball was
				played to; a won tackle marks the tackler the same way, so the same
				one mechanism decides both without a bot-only priority path.
			]]
			ball:SetAttribute("LastFootballActionIntendedReceiverUserId", actor.Id)
			ball:SetAttribute("LastFootballActionIntendedReceiverName", actor.DisplayName)
		end
		--[[
			The tackler needs a moment on their feet before collecting. Shorter
			than the failed-challenge recovery, because they won it.
		]]
		recoveryUntilById[actor.Id] = now + config.WonBallControl.RecoverySeconds
	else
		if actor.Player then
			BallControlService.SuppressAcquisition(
				actor.Player,
				config.TacklerAcquisitionSuppression,
				config.TacklerExitDistance
			)
		end
		recoveryUntilById[actor.Id] = now + DefendingConfig.Tackle.RecoverySeconds
	end
	ball:SetAttribute("LastTackleWinnerFootballerId", actor.Id)
	ball:SetAttribute("LastTackleOutcome", result.Outcome)
	ball:SetAttribute("LastTackleTime", now)

	log(string.format(
		"[Tackle] %s -> %s outcome=%s score=%.2f exposure=%.2f facing=%.2f behind=%.2f",
		actor.DisplayName, carrier.DisplayName, result.Outcome,
		result.Score, result.Exposure or 0, result.FacingDot or 0, result.BehindDot or 0
	))
	return true, result.Outcome, result
end

--[[
	COMMITTING TO A CHALLENGE.

	Pressing the button no longer decides anything. It spends the cooldown, starts
	the animation and opens a contact window; whether the challenge connects is
	settled over the following fraction of a second by the sweep below.

	That is the whole mechanic. A tackle asked for too early or too late now costs
	the defender exactly the same commitment and produces nothing, which is what
	makes timing a skill rather than a range check. It also means a challenge at
	empty grass is a real possibility with a real price -- previously it returned
	"no-valid-carrier" for free.

	Both sources agree on this shape; see DefendingConfig.ContactWindow.
]]
--[[
	The same question as PreviewTackle, asked against the SLIDE's geometry.

	A slide reaches further but is far less forgiving about direction, so the two
	challenges disagree about what is available from the same position. The AI
	needs to ask about the one it is actually considering.
]]
function DefendingService.PreviewSlideTackle(actor): any
	if not actor or not actor.RootPart or not actor.RootPart.Parent then
		return nil
	end
	local ball = getFootball()
	if not ball or ball:GetAttribute("State") ~= "Controlled" then
		return nil
	end
	if ball:GetAttribute("GoalkeeperHeld") == true then
		return nil
	end
	local carrierId = ball:GetAttribute("ControllerFootballerId")
	if typeof(carrierId) ~= "number" or carrierId == 0 or carrierId == actor.Id then
		return nil
	end
	local carrier = FootballerRegistryService.GetActorById(carrierId)
	if not carrier or not carrier.RootPart or not carrier.RootPart.Parent then
		return nil
	end
	if carrier.TeamId ~= nil and carrier.TeamId == actor.TeamId then
		return nil
	end
	return TackleEvaluator.Evaluate(
		toEvaluatorRecord(actor),
		toEvaluatorRecord(carrier),
		ball.Position,
		DefendingConfig.Slide.Evaluation
	)
end

function DefendingService.AttemptTackle(actor): (boolean, string, any)
	if not MatchRulesService.AllowsFootballActions() then
		return false, "match-not-playing", nil
	end
	if not actor or not actor.RootPart or not actor.RootPart.Parent then
		return false, "challenger-invalid", nil
	end
	if DefendingService.IsRecovering(actor.Id) then
		return false, "recovering", nil
	end
	if pendingChallengeById[actor.Id] then
		return false, "already-committed", nil
	end

	local now = os.clock()
	local config = DefendingConfig.Tackle
	local lastAt = lastTackleAtById[actor.Id]
	if lastAt and now - lastAt < config.Cooldown then
		return false, "cooldown", nil
	end

	lastTackleAtById[actor.Id] = now
	local window = DefendingConfig.ContactWindow
	local opensAt = now + window.WindupSeconds
	local closesAt = opensAt + window.ContactWindowSeconds
	pendingChallengeById[actor.Id] = {
		Actor = actor,
		ActionType = config.ActionType,
		OpensAt = opensAt,
		ClosesAt = closesAt,
	}
	--[[
		Clients hold the challenge animation and suppress movement input for the
		duration. The server owns the commitment: a client that ignores the
		attribute gains nothing, because the recovery applied on resolution is what
		actually gates the next action.
	]]
	if actor.Character then
		actor.Character:SetAttribute(window.CommittedAttribute, closesAt)
	end
	-- Plays on COMMIT, not on resolution: the leg goes before anyone knows
	-- whether it connects, which is the whole point of the window.
	if actor.IsAI then
		AIAnimationService.PlayAction(actor, "StandingTackle")
	end
	return true, "committed", nil
end

--[[
	RESOLVING COMMITTED CHALLENGES.

	Once the windup has elapsed, each tick asks whether contact is available --
	using the same preview the AI uses to decide, so the question the sweep asks
	and the question a defender asks are literally the same one. The first tick
	that says yes resolves the challenge. If none does, it resolves anyway when
	the window closes, and that resolution is the miss: recovery is applied and
	the ordinary foul check still runs, because a challenge that connected with a
	player and not the ball is exactly the case fouls exist for.
]]
local function updatePendingChallenges()
	local now = os.clock()
	for id, entry in pendingChallengeById do
		local actor = entry.Actor
		if not actor or not actor.RootPart or not actor.RootPart.Parent then
			pendingChallengeById[id] = nil
			continue
		end
		if now < entry.OpensAt then
			continue
		end

		local preview = DefendingService.PreviewTackle(actor)
		local contactAvailable = preview ~= nil and preview.Valid == true and preview.Outcome ~= "Missed"
		local expired = now >= entry.ClosesAt
		if not contactAvailable and not expired then
			continue
		end

		pendingChallengeById[id] = nil
		if actor.Character then
			actor.Character:SetAttribute(DefendingConfig.ContactWindow.CommittedAttribute, nil)
		end

		local accepted, reason, result = performTackle(actor, now)
		if not accepted then
			--[[
				The window closed with nothing won. performTackle only applies
				recovery on the paths it actually reached, so a challenge that found
				no carrier at all would otherwise cost nothing -- which is the free
				look this mechanic exists to remove.
			]]
			if (recoveryUntilById[id] or 0) <= now then
				recoveryUntilById[id] = now + DefendingConfig.Tackle.FailedRecoverySeconds
			end
			if reason == "no-valid-carrier" then
				reason = "no-contact"
			end
		end
		if actor.Player then
			sendFeedback(actor, accepted, reason, result, entry.ActionType)
		end
	end
end

--[[
	INTERCEPTION SWEEP.

	Once per tick: take the segment the ball travelled and ask every footballer
	who is not carrying it whether it went through their reach.

	Deliberately automatic, and deliberately not an input. Being in the passing
	lane is the football decision, and the player already made it by standing
	there -- putting a leg out once the ball arrives is execution, which is the
	side of the line AGENTS.md places assistance on. An "intercept" button would
	also be unplayable: the window is under a tenth of a second.

	Runs for humans and AI through exactly the same evaluation. Neither side has
	a privileged path to the ball.
]]
local function updateInterceptions()
	local config = DefendingConfig.Interception
	if config.Enabled ~= true then
		return
	end
	local ball = getFootball()
	if not ball then
		previousBallPosition = nil
		return
	end

	local from = previousBallPosition
	local to = ball.Position
	previousBallPosition = to

	if not MatchRulesService.AllowsFootballActions() then
		return
	end
	-- A held or dribbled ball is not in flight, and a goalkeeper's ball is not
	-- contestable by a foot at all.
	if ball:GetAttribute("State") ~= "Free" or ball:GetAttribute("GoalkeeperHeld") == true then
		return
	end
	if not from then
		return
	end

	local velocity = ball.AssemblyLinearVelocity
	local now = os.clock()

	--[[
		Whoever last played the ball cannot intercept their own pass.

		Without this the passer is the single most likely interceptor of every
		ball they play: they are standing right next to it, facing it, at the
		moment it is fastest.
	]]
	local lastToucherId = ball:GetAttribute("LastFootballActionPlayerUserId")

	local best = nil
	local bestActor = nil
	for _, actor in FootballerRegistryService.GetAll() do
		if actor.RootPart and actor.RootPart.Parent and actor.Id ~= lastToucherId then
			local lastAt = lastInterceptionAtById[actor.Id]
			local recovering = DefendingService.IsRecovering(actor.Id)
			if not recovering and (not lastAt or now - lastAt >= config.Cooldown) then
				local result = InterceptionEvaluator.Evaluate(
					{
						Position = actor.RootPart.Position,
						Velocity = actor.RootPart.AssemblyLinearVelocity,
						FacingDirection = actor.RootPart.CFrame.LookVector,
						Skill = PositionConfig.GetSkill(actor.PositionSlotId, "Tackling"),
					},
					from,
					to,
					velocity,
					config
				)
				--[[
					Only ONE footballer may intercept a given ball on a given
					tick, and it is the one who met it best. Two defenders both
					touching the same ball in the same frame is not football, and
					whichever ran second would silently overwrite the first.
				]]
				if result.Valid and (not best or result.Score > best.Score) then
					best = result
					bestActor = actor
				end
			end
		end
	end

	if not best or not bestActor then
		return
	end

	lastInterceptionAtById[bestActor.Id] = now

	local direction = best.LooseDirection or Vector3.zAxis
	local launchVelocity
	if best.Outcome == "Controlled" then
		launchVelocity = direction * config.ControlledSpeed + Vector3.yAxis * config.ControlledLift
	else
		local retained = BallControlMath.GetHorizontal(velocity).Magnitude * config.DeflectionSpeedRetention
		launchVelocity = direction * retained + Vector3.yAxis * config.DeflectionLift
	end
	ball.AssemblyLinearVelocity = launchVelocity

	--[[
		The ball stays FREE. An interception is not a possession grant -- the
		ordinary acquisition rules decide who ends up with it, exactly as after a
		won tackle, so an opponent standing closer can still win the second ball.
	]]
	ball:SetAttribute("LastFootballAction", "Interception")
	ball:SetAttribute("LastFootballActionPlayerUserId", bestActor.Id)
	ball:SetAttribute("LastFootballActionTime", now)
	ball:SetAttribute("LastInterceptionOutcome", best.Outcome)

	if best.Outcome == "Controlled" then
		if bestActor.Player then
			BallControlService.RegisterReacquisitionClaim(
				bestActor.Player,
				config.ClaimSeconds,
				config.ClaimScoreBonus
			)
		else
			-- The AI equivalent of that claim, using the same designated-chaser
			-- mechanism a pass receiver gets rather than a bot-only priority.
			ball:SetAttribute("LastFootballActionIntendedReceiverUserId", bestActor.Id)
			ball:SetAttribute("LastFootballActionIntendedReceiverName", bestActor.DisplayName)
		end
		recoveryUntilById[bestActor.Id] = now + config.ControlledRecoverySeconds
	elseif bestActor.Player then
		-- A deflection is a genuine contest, so the deflector does not get to
		-- simply pick up what came off their shin.
		BallControlService.SuppressAcquisition(
			bestActor.Player,
			config.DeflectionSuppression,
			config.DeflectionExitDistance
		)
	end

	MatchRulesService.NotifyTouch(bestActor, "Interception")

	log(string.format(
		"[Interception] %s outcome=%s score=%.2f closeness=%.2f ballSpeed=%.1f",
		bestActor.DisplayName,
		tostring(best.Outcome),
		best.Score,
		best.Closeness or 0,
		BallControlMath.GetHorizontal(velocity).Magnitude
	))
end

--[[
	THE SLIDE TACKLE.

	Shares the standing tackle's evaluation, its foul reporting and its loose-ball
	handling, and differs only where a slide genuinely differs: it reaches
	further, it commits the body, and it fouls far more readily. See the long
	note on DefendingConfig.Slide for the trade this expresses.

	The commitment is the part worth being careful about. The tackler is given a
	single forward impulse along the way they were already facing and is then
	unable to act until the recovery expires -- there is no steering out of it and
	no cancelling it, because a slide that could be aborted would just be a
	better standing tackle with no downside.

	Server-authoritative, exactly like every other challenge: the client asks,
	this decides, and nothing about the outcome is taken on the client word.
]]
function DefendingService.AttemptSlideTackle(actor): (boolean, string, any)
	local config = DefendingConfig.Slide
	if config.Enabled ~= true then
		return false, "slide-disabled", nil
	end
	if not MatchRulesService.AllowsFootballActions() then
		return false, "match-not-playing", nil
	end
	if not actor or not actor.RootPart or not actor.RootPart.Parent then
		return false, "challenger-invalid", nil
	end
	if DefendingService.IsRecovering(actor.Id) then
		return false, "recovering", nil
	end

	local now = os.clock()
	local lastAt = lastSlideAtById[actor.Id]
	if lastAt and now - lastAt < config.Cooldown then
		return false, "cooldown", nil
	end

	local ball = getFootball()
	if not ball then
		return false, "ball-missing", nil
	end
	if ball:GetAttribute("GoalkeeperHeld") == true then
		return false, "goalkeeper-held", nil
	end

	local carrierId = ball:GetAttribute("ControllerFootballerId")
	local carrier = if typeof(carrierId) == "number" and carrierId ~= 0 and carrierId ~= actor.Id
		then FootballerRegistryService.GetActorById(carrierId)
		else nil

	lastSlideAtById[actor.Id] = now

	--[[
		THE BODY GOES, WHETHER OR NOT THERE IS ANYTHING TO WIN.

		Committing first and evaluating second is the whole point. A slide at
		nothing must still put the defender on the floor, or the input becomes a
		free look at whether the challenge would have come off.
	]]
	local facing = BallControlMath.SafeUnit(
		BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector),
		Vector3.zAxis
	)
	actor.RootPart.AssemblyLinearVelocity = facing * config.LaunchSpeed
		+ Vector3.yAxis * actor.RootPart.AssemblyLinearVelocity.Y
	if actor.Character then
		--[[
			Clients read this to suppress movement input and to play the slide.
			The server owns the commitment: a client cannot shorten its own slide
			by ignoring the attribute, because the recovery below is what actually
			gates further actions.
		]]
		actor.Character:SetAttribute(config.SlidingAttribute, now + config.SlideSeconds)
	end
	-- The tackler's own animation. A no-op until the clip exists; see
	-- AnimationConfig.Actions.SlideTackle.
	if actor.IsAI then
		AIAnimationService.PlayAction(actor, "SlideTackle")
	end

	if not carrier or not carrier.RootPart or not carrier.RootPart.Parent
		or (carrier.TeamId ~= nil and carrier.TeamId == actor.TeamId)
	then
		recoveryUntilById[actor.Id] = now + config.FailedRecoverySeconds
		log(string.format("[Slide] %s committed with no carrier to challenge", actor.DisplayName))
		return false, "no-valid-carrier", nil
	end

	local result = TackleEvaluator.Evaluate(
		toEvaluatorRecord(actor),
		toEvaluatorRecord(carrier),
		ball.Position,
		config.Evaluation
	)

	if not result.Valid or result.Outcome == "Missed" then
		recoveryUntilById[actor.Id] = now + config.FailedRecoverySeconds
		reportFoulIfContact(actor, carrier, result, config.FoulSeverityScale)
		log(string.format(
			"[Slide] %s -> %s failed=%s score=%.2f",
			actor.DisplayName, carrier.DisplayName,
			tostring(result.Reason or result.Outcome), result.Score or 0
		))
		return false, result.Reason or "missed", result
	end

	--[[
		A slide never ends with the tackler standing over the ball -- they are on
		the ground. So both outcomes send the ball away as a genuine loose ball,
		with a clean challenge simply putting more on it and in a more useful
		direction. This is the one place a slide is deliberately WORSE than a
		standing tackle: it wins the ball, it does not win possession.
	]]
	local won = result.Outcome == "Won"
	local speed = if won then config.LooseBallSpeed else config.LooseBallPartialSpeed
	local direction = BallControlMath.SafeUnit(result.LooseDirection, facing)
	local launchVelocity = direction * speed + Vector3.yAxis * config.LooseBallLift

	local released
	if carrier.IsAI then
		released = BallControlService.ReleaseAIForFootballAction(
			ball, carrier, "SlideTackled", launchVelocity, { TargetKind = "Loose" }
		)
	else
		released = BallControlService.ReleaseForFootballAction(
			ball, carrier.Player, "SlideTackled", launchVelocity,
			DefendingConfig.Tackle.VictimAcquisitionSuppression,
			DefendingConfig.Tackle.VictimExitDistance,
			{ TargetKind = "Loose" }
		)
	end
	if not released then
		recoveryUntilById[actor.Id] = now + config.RecoverySeconds
		return false, "release-rejected", result
	end

	-- The victim of a slide goes down. These reaction clips already exist and
	-- were authored for exactly this challenge.
	if carrier.IsAI then
		AIAnimationService.PlayAction(
			carrier,
			if (result.BehindDot or 0) > 0.25 then "TackledSlideBack" else "TackledSlideFront"
		)
		carrier.TackleRecoveryUntil = now + DefendingConfig.Tackle.RecoverySeconds
	end
	if carrier.Player and carrier.Character then
		carrier.Character:SetAttribute("Beyond90TackledAt", now)
		carrier.Character:SetAttribute("Beyond90TackledOutcome", result.Outcome)
		carrier.Character:SetAttribute("Beyond90TackledBehindDot", result.BehindDot or 0)
	end

	if actor.Player then
		BallControlService.SuppressAcquisition(
			actor.Player, config.TacklerAcquisitionSuppression, config.TacklerExitDistance
		)
	end
	recoveryUntilById[actor.Id] = now + config.RecoverySeconds

	--[[
		A won slide is still checked for a foul. Taking the ball first does not
		make a challenge legal if the follow-through went through the opponent,
		and FoulEvaluator already declines to punish a genuinely clean one.
	]]
	reportFoulIfContact(actor, carrier, result, config.FoulSeverityScale)

	ball:SetAttribute("LastTackleWinnerFootballerId", actor.Id)
	ball:SetAttribute("LastTackleOutcome", result.Outcome)
	ball:SetAttribute("LastTackleTime", now)

	log(string.format(
		"[Slide] %s -> %s outcome=%s score=%.2f behind=%.2f",
		actor.DisplayName, carrier.DisplayName, result.Outcome,
		result.Score, result.BehindDot or 0
	))
	return true, result.Outcome, result
end

local function onDefensiveRequest(player: Player, payload)
	local actionType = if typeof(payload) == "table" then payload.ActionType else payload
	local isSlide = actionType == DefendingConfig.Slide.ActionType
	if actionType ~= DefendingConfig.Tackle.ActionType and not isSlide then
		return
	end
	local actor = FootballerRegistryService.GetHumanActor(player)
	if not actor then
		return
	end
	-- A footballer already in possession cannot tackle.
	local ball = getFootball()
	if ball and ball:GetAttribute("ControllerFootballerId") == actor.Id then
		return
	end
	local accepted, reason, result
	if isSlide then
		accepted, reason, result = DefendingService.AttemptSlideTackle(actor)
		sendFeedback(actor, accepted, reason, result, actionType)
	else
		accepted, reason, result = DefendingService.AttemptTackle(actor)
		--[[
			A standing tackle now reports twice as far as the player is concerned:
			nothing here on a successful commit, and the real outcome from the sweep
			when the contact window resolves. Only a REJECTED commit -- cooldown,
			recovery, match state -- answers immediately, because there is nothing
			still to come.
		]]
		if not accepted then
			sendFeedback(actor, accepted, reason, result, actionType)
		end
	end
end

function DefendingService.Initialize()
	if initialized then
		return
	end
	initialized = true
	local remotes = ReplicatedStorage:FindFirstChild(FootballActionConfig.RemotesFolderName)
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = FootballActionConfig.RemotesFolderName
		remotes.Parent = ReplicatedStorage
	end
	requestRemote = getOrCreateRemote(remotes, DefendingConfig.RemoteName)
	feedbackRemote = getOrCreateRemote(remotes, DefendingConfig.FeedbackRemoteName)
	requestRemote.OnServerEvent:Connect(onDefensiveRequest)

	Players.PlayerRemoving:Connect(function(player)
		lastTackleAtById[player.UserId] = nil
		recoveryUntilById[player.UserId] = nil
		lastInterceptionAtById[player.UserId] = nil
		lastSlideAtById[player.UserId] = nil
		pendingChallengeById[player.UserId] = nil
	end)

	--[[
		The interception sweep owns its own tick and its own previous-ball
		sample. It could have been folded into BallService's heartbeat, where the
		ball is already being stepped, but that would make the ball's physics
		module depend on the defending module purely to borrow one Vector3 --
		and this needs nothing from there that it cannot sample itself.
	]]
	interceptionConnection = RunService.Heartbeat:Connect(function()
		local ok, failure = pcall(updateInterceptions)
		if not ok then
			warn("[Beyond90][Server][Defending] Interception sweep failed: " .. tostring(failure))
		end
		-- Committed challenges resolve on the same tick; see updatePendingChallenges.
		local challengeOk, challengeFailure = pcall(updatePendingChallenges)
		if not challengeOk then
			warn("[Beyond90][Server][Defending] Challenge sweep failed: " .. tostring(challengeFailure))
		end
	end)
end

return DefendingService
