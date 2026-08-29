local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local function sendFeedback(actor, accepted: boolean, reason: string, result)
	if not feedbackRemote or not actor.Player then
		return
	end
	feedbackRemote:FireClient(actor.Player, {
		ActionType = DefendingConfig.Tackle.ActionType,
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
local function reportFoulIfContact(challenger, victim, result)
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

	local now = os.clock()
	local lastAt = lastTackleAtById[actor.Id]
	if lastAt and now - lastAt < DefendingConfig.Tackle.Cooldown then
		return false, "cooldown", nil
	end

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

	lastTackleAtById[actor.Id] = now

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

local function onDefensiveRequest(player: Player, payload)
	local actionType = if typeof(payload) == "table" then payload.ActionType else payload
	if actionType ~= DefendingConfig.Tackle.ActionType then
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
	local accepted, reason, result = DefendingService.AttemptTackle(actor)
	sendFeedback(actor, accepted, reason, result)
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
	end)
end

return DefendingService
