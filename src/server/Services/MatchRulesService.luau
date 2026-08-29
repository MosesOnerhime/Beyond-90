--!strict
--[[
	The referee.

	Server-authoritative officiating: match phase, the clock, whether the ball is
	in play, who last touched it, and which restart a stoppage produces. It owns
	the DECISION; RestartService owns the geometry that carries it out.

	Structure follows GameplayFootball's `Referee::Process` closely, including the
	one ordering detail that matters: every ball-out branch defers to the foul
	check first, so a single event can never produce two decisions (§76).
	See docs/research/gameplay-football/match-rules-and-positions.md.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MatchConfig = require(Shared.Config.MatchConfig)
local MatchRulesConfig = require(Shared.Config.MatchRulesConfig)
local OffsideEvaluator = require(Shared.Football.OffsideEvaluator)
local PitchGeometry = require(Shared.Football.PitchGeometry)
local PositionConfig = require(Shared.Config.PositionConfig)

local FootballerRegistryService = require(script.Parent.FootballerRegistryService)
local GoalService = require(script.Parent.GoalService)
local MatchService = require(script.Parent.MatchService)
local PitchService = require(script.Parent.PitchService)
local RestartService = require(script.Parent.RestartService)
local InjuryService = require(script.Parent.InjuryService)
local StaminaService = require(script.Parent.StaminaService)

local MatchRulesService = {}

local Phases = MatchRulesConfig.Phases
local Restarts = MatchRulesConfig.Restarts

local initialized = false
local folder: Folder? = nil
local announcementRemote: RemoteEvent? = nil
local ball: BasePart? = nil
local connection: RBXScriptConnection? = nil

local phase = Phases.Idle
local period = MatchRulesConfig.Periods.FirstHalf
local clockSeconds = 0
local previousBallPosition: Vector3? = nil
local relaxUntil = 0

-- Pending restart, the equivalent of the source's RefereeBuffer.
local buffer: { [string]: any }? = nil

-- Last legitimate contact with the football (§51).
local lastTouch: { Id: number, TeamId: string?, Kind: string, At: number }? = nil
local previousTouch: { Id: number, TeamId: string?, Kind: string, At: number }? = nil

-- Offside snapshot, cleared and rebuilt on every touch.
local offsideSnapshot: { { Id: number, Position: Vector3 } } = {}
local offsideSnapshotAt = 0
local offsideSnapshotTeamId: string? = nil

-- Pending foul awaiting an advantage decision.
local pendingFoul: { [string]: any }? = nil
local lastFoulAt = 0
-- Which side kicked off the match; the other side kicks off the second half.
local kickoffTeamId = "Home"
-- Who is celebrating, so AI can run to a celebration space rather than standing
-- in formation through its own goal (§69).
local celebratingScorerId: number? = nil
local celebratingTeamId: string? = nil

local phaseChangedEvent = Instance.new("BindableEvent")
local announcementEvent = Instance.new("BindableEvent")

local function log(message: string)
	if MatchRulesConfig.Debug.Enabled then
		print(string.format("%s[Rules] %s", GameConfig.LogPrefix, message))
	end
end

--[[
	Publish a decision.

	Clients get it over the remote for the HUD; server-side presentation (the
	referee's whistle) gets it over the Bindable. Both are strictly downstream --
	a listener may react to a decision but can never change one.
]]
local function announce(kind: string, detail: string?, teamId: string?)
	local payload = { Kind = kind, Detail = detail, TeamId = teamId }
	if announcementRemote then
		announcementRemote:FireAllClients(payload)
	end
	announcementEvent:Fire(payload)
end

local function publish()
	if not folder then
		return
	end
	folder:SetAttribute(MatchRulesConfig.StateAttributeName, phase)
	folder:SetAttribute(MatchRulesConfig.ClockAttributeName, math.floor(clockSeconds))
	folder:SetAttribute(MatchRulesConfig.PeriodAttributeName, period)
	folder:SetAttribute(MatchRulesConfig.RestartAttributeName, buffer and buffer.Restart or Restarts.None)
	folder:SetAttribute(MatchRulesConfig.RestartTeamAttributeName, buffer and buffer.TeamId or nil)
end

local function setPhase(nextPhase: string)
	if phase == nextPhase then
		return
	end
	phase = nextPhase
	publish()
	phaseChangedEvent:Fire(phase)
	log(string.format("Phase -> %s", phase))
end

function MatchRulesService.SetBall(newBall: BasePart?)
	ball = newBall
	previousBallPosition = newBall and newBall.Position or nil
	RestartService.SetBall(newBall)
end

function MatchRulesService.GetPhase(): string
	return phase
end

function MatchRulesService.GetPeriod(): string
	return period
end

function MatchRulesService.GetClockSeconds(): number
	return clockSeconds
end

-- Server-side decision feed. See announce().
function MatchRulesService.GetAnnouncementEvent(): BindableEvent
	return announcementEvent
end

function MatchRulesService.GetPhaseChangedEvent(): BindableEvent
	return phaseChangedEvent
end

--[[
	The single question every gameplay system should ask.

	True only while the ball is genuinely live. During a restart the taker is
	allowed to play it -- RestartService.IsAuthorizedTaker decides that -- but
	nobody else may chase, press or shoot (§77, §78).
]]
function MatchRulesService.AllowsFootballActions(): boolean
	return MatchService.IsPlaying() and phase == Phases.Playing
end

--[[
	May anyone move at all right now? (§25)

	False before the user has started the match. This is a real gameplay
	restriction rather than a loading screen: humans, AI, goalkeepers and the
	officials all consult it, so nothing on the pitch drifts out of its kick-off
	shape while the START MATCH button is still on screen.
]]
function MatchRulesService.AllowsMovement(): boolean
	return phase ~= Phases.PreMatch and phase ~= Phases.Idle and MatchService.GetState() ~= "ReadyToStart"
end

function MatchRulesService.IsPreMatch(): boolean
	return phase == Phases.PreMatch
end

function MatchRulesService.IsRestartActive(): boolean
	return MatchRulesConfig.IsRestartPhase(phase)
end

function MatchRulesService.GetActiveRestart(): string?
	return buffer and buffer.Restart or nil
end

--[[
	Who scored the goal currently being celebrated, and for which side. Works for
	a human, an AI or an own goal (§69) -- the scorer id is whatever GoalService
	attributed, so nothing here assumes an AI.
]]
function MatchRulesService.GetCelebration(): (number?, string?)
	if phase ~= Phases.GoalCelebration then
		return nil, nil
	end
	return celebratingScorerId, celebratingTeamId
end

function MatchRulesService.GetLastTouch()
	return lastTouch
end

function MatchRulesService.GetPreviousTouch()
	return previousTouch
end

local function getTeamFrame(teamId: string)
	return RestartService.GetTeamFrame(teamId)
end

local function otherTeam(teamId: string?): string
	return if teamId == "Home" then "Away" else "Home"
end

--[[
	Offside snapshot (§60).

	Taken every time a team plays the ball: who was beyond the opponents' second
	last defender at that instant, and where. Never punishes anyone by itself.
]]
local function takeOffsideSnapshot(touchingActor)
	table.clear(offsideSnapshot)
	offsideSnapshotTeamId = nil

	local config = MatchRulesConfig.Offside
	if config.Enabled ~= true or not ball then
		return
	end
	-- Never directly from a restart (§62).
	if buffer ~= nil then
		return
	end

	local teamId = touchingActor.TeamId
	if not teamId then
		return
	end
	local frame = getTeamFrame(teamId)
	if not frame then
		return
	end

	local attackers, opponents = {}, {}
	for _, actor in FootballerRegistryService.GetAll() do
		if actor.RootPart and actor.RootPart.Parent then
			local record = {
				Id = actor.Id,
				Position = actor.RootPart.Position,
				IsGoalkeeper = PositionConfig.IsGoalkeeper(actor.PositionSlotId) or actor.Position == "Goalkeeper",
			}
			if actor.TeamId == teamId then
				table.insert(attackers, record)
			elseif actor.TeamId then
				table.insert(opponents, record)
			end
		end
	end

	offsideSnapshot = OffsideEvaluator.TakeSnapshot(
		frame,
		attackers,
		opponents,
		ball.Position,
		touchingActor.Id,
		config.RelaxRatio,
		config.MinimumTeammates
	)
	offsideSnapshotAt = os.clock()
	offsideSnapshotTeamId = teamId
end

local function clearOffsideSnapshot()
	table.clear(offsideSnapshot)
	offsideSnapshotTeamId = nil
end

MatchRulesService.ClearOffsideSnapshot = clearOffsideSnapshot

--[[
	Queue a restart. Mirrors the source's RefereeBuffer: stop now, position at
	`PrepareAt`, resume at `StartAt`.
]]
local function queueRestart(restart: string, teamId: string, context)
	if buffer then
		return false
	end

	local position = RestartService.ResolveBallPosition(restart, teamId, context)
	if not position then
		log(string.format("%s for %s could not be placed; ignoring", restart, teamId))
		return false
	end

	local now = os.clock()
	local prepareSeconds = MatchRulesConfig.Timing.PrepareSeconds
	if restart == Restarts.Kickoff then
		prepareSeconds = MatchRulesConfig.Timing.KickoffPrepareSeconds
	end

	buffer = {
		Restart = restart,
		TeamId = teamId,
		Position = position,
		PrepareAt = now + prepareSeconds,
		StartAt = now + prepareSeconds + MatchRulesConfig.Timing.StartDelaySeconds,
		Prepared = false,
		Context = context,
	}

	setPhase(Phases.Stoppage)
	clearOffsideSnapshot()
	publish()
	--[[
		ONE DECISION, ONE ANNOUNCEMENT (§35).

		An offside used to announce twice: this call said "FREE KICK" to the
		awarded team, and the offside branch separately said "OFFSIDE" naming the
		OFFENDING team. Two whistles, two banners, and the two banners disagreed
		about whose ball it was.

		The restart is still internally a free kick -- the award, the placement
		and the legal actions are unchanged. Only the presentation collapses to
		the decision a referee would actually signal.
	]]
	local announcedKind = (context and context.Announce) or restart
	announce(announcedKind, context and context.Reason or nil, teamId)
	log(string.format("%s awarded to %s", restart, teamId))
	return true
end

MatchRulesService.QueueRestart = queueRestart

--[[
	Ball out of play (§50).

	Whole-ball crossing from authoritative geometry, never `.Touched`. The
	touchline test is suppressed during the relax window after a restart, because
	the ball is still outside the lines at the instant a throw-in is taken and
	would otherwise immediately award another one -- the source hits exactly this
	and guards it the same way.
]]
--[[
	Is this crossing point actually inside a goal?

	Used to stand down the ball-out decision so GoalService, which remains
	authoritative for goals, is the only system that reacts to it.
]]
local function isInsideGoalMouth(position: Vector3): boolean
	if not ball then
		return false
	end
	local radius = ball.Size.X * 0.5
	for _, goal in GoalService.GetGoals() do
		local widthAxis = BallControlMath.SafeUnit(
			BallControlMath.GetHorizontal(goal.WidthAxis),
			Vector3.xAxis
		)
		local lateral = math.abs((position - goal.MouthCenter):Dot(widthAxis))
		local aboveFloor = position.Y >= (goal.BottomY or 0)
		local belowBar = goal.Height == nil or position.Y <= (goal.BottomY or 0) + goal.Height
		if lateral <= goal.Width * 0.5 + radius and aboveFloor and belowBar then
			return true
		end
	end
	return false
end

local function checkBallOut()
	if not ball then
		return
	end
	local pitchState = PitchService.GetState()
	if not pitchState then
		return
	end

	local frame = PitchGeometry.CreateFrame(pitchState, pitchState.LengthAxis)
	local exit = PitchGeometry.ClassifyBallExit(
		frame,
		previousBallPosition,
		ball.Position,
		ball.Size.X * 0.5,
		MatchRulesConfig.Pitch.OutOfPlayLineRatio
	)
	if not exit then
		return
	end

	local touchTeam = lastTouch and lastTouch.TeamId
	if not touchTeam then
		-- Nobody has touched it; give it to whoever is nearer their own half.
		touchTeam = "Home"
	end
	local awardTo = otherTeam(touchTeam)

	if exit.Kind == "Touchline" then
		if os.clock() < relaxUntil then
			return
		end
		queueRestart(Restarts.ThrowIn, awardTo, { Crossing = exit.Crossing, Reason = "out-of-play" })
		return
	end

	--[[
		A goal outranks every ball-out restart (§76).

		The source checks `IsGoalScored()` inside this same branch before deciding
		corner or goal kick. Without it a ball crossing INSIDE the goal mouth
		briefly awards a goal kick before GoalService reports the goal.
	]]
	if isInsideGoalMouth(exit.Crossing) then
		return
	end

	--[[
		Goal line. Corner or goal kick depends on which side the ball left
		relative to the LAST TOUCHER'S OWN goal, exactly as the source decides it:
		a defender putting it behind gives a corner, an attacker gives a goal kick.
	]]
	local touchFrame = getTeamFrame(touchTeam)
	if not touchFrame then
		return
	end
	local exitLongitudinal = PitchGeometry.ToNormalized(touchFrame, exit.Crossing)

	if exitLongitudinal < 0 then
		-- Went out over the last toucher's own goal line -> corner to the others.
		queueRestart(Restarts.CornerKick, awardTo, { Crossing = exit.Crossing, Reason = "behind-for-corner" })
	else
		-- Went out over the opponents' goal line -> goal kick to the others.
		queueRestart(Restarts.GoalKick, awardTo, { Crossing = exit.Crossing, Reason = "behind-for-goal-kick" })
	end
end

--[[
	Advantage (§59). A foul is held briefly; if the fouled side still has the
	ball when the window closes, play simply continues.
]]
local function resolvePendingFoul()
	if not pendingFoul then
		return false
	end
	local config = MatchRulesConfig.Foul.Advantage
	local elapsed = os.clock() - pendingFoul.At

	if config.Enabled == true and elapsed < config.EvaluateAfter then
		return false
	end

	if config.Enabled == true and elapsed < config.AbandonAfter then
		-- Still in the advantage window: if the victim's team has the football,
		-- let it run.
		local controllerId = ball and ball:GetAttribute("ControllerFootballerId")
		if typeof(controllerId) == "number" and controllerId ~= 0 then
			local controller = FootballerRegistryService.GetActorById(controllerId)
			if controller and controller.TeamId == pendingFoul.VictimTeamId then
				return false
			end
		end
	end

	local decision = pendingFoul
	pendingFoul = nil

	if config.Enabled == true and elapsed >= config.AbandonAfter then
		-- Advantage ran long enough; the foul is dropped entirely.
		log("Advantage played; foul dropped")
		return false
	end

	-- Penalty if the offence was inside the offending side's own penalty area.
	local defendingFrame = getTeamFrame(decision.OffenderTeamId)
	local isPenalty = false
	if defendingFrame then
		isPenalty = PitchGeometry.IsInsidePenaltyArea(
			defendingFrame,
			decision.Position,
			-1,
			MatchRulesConfig.Pitch.PenaltyAreaDepth,
			MatchRulesConfig.Pitch.PenaltyAreaHalfWidth
		)
	end

	if isPenalty then
		return queueRestart(Restarts.Penalty, decision.VictimTeamId, {
			Position = decision.Position,
			Reason = "penalty",
			OffenderId = decision.OffenderId,
		})
	end

	return queueRestart(Restarts.FreeKick, decision.VictimTeamId, {
		Position = decision.Position,
		Reason = decision.Type,
		OffenderId = decision.OffenderId,
	})
end

--[[
	Report a foul. FoulService/DefendingService call this; the referee decides
	whether it becomes a free kick, a penalty, or nothing because advantage ran.
]]
function MatchRulesService.ReportFoul(offender, victim, decision)
	if not MatchRulesService.AllowsFootballActions() then
		return
	end
	local now = os.clock()
	if now - lastFoulAt < MatchRulesConfig.Foul.Cooldown then
		return
	end
	if pendingFoul then
		return
	end
	lastFoulAt = now

	pendingFoul = {
		At = now,
		Type = decision.Type,
		Severity = decision.Severity,
		OffenderId = offender.Id,
		OffenderTeamId = offender.TeamId,
		VictimId = victim.Id,
		VictimTeamId = victim.TeamId,
		Position = victim.RootPart and victim.RootPart.Position or offender.RootPart.Position,
	}

	log(string.format(
		"Foul reported: %s on %s severity=%.2f type=%s",
		offender.DisplayName,
		victim.DisplayName,
		decision.Severity,
		decision.Type
	))
	announce("Foul", decision.Type, victim.TeamId)
end

--[[
	A legitimate contact with the football (§51).

	Everything that can move the ball reports here: control acquisition, passes,
	shots, tackles and goalkeeper saves. Last touch drives every restart decision,
	so it must not be inferred.
]]
--[[
	Are the match rules currently responsible for what happens to the ball?

	True whenever a match is running, in any phase -- including stoppages and
	restarts, because those ARE the rules doing their job. Used by systems that
	carry a legacy fallback so they can stand down rather than competing with
	the real rules (§36).
]]
function MatchRulesService.IsGoverningPlay(): boolean
	return phase ~= Phases.Idle
end

function MatchRulesService.NotifyTouch(actor, kind: string)
	if not actor or typeof(actor.Id) ~= "number" then
		return
	end

	-- Offside is judged on the touch BEFORE this one.
	if MatchRulesService.AllowsFootballActions() and MatchRulesConfig.Offside.Enabled == true then
		local offendingPosition = OffsideEvaluator.FindInvolvement(offsideSnapshot, actor.Id)
		local snapshotFresh = os.clock() - offsideSnapshotAt <= MatchRulesConfig.Offside.SnapshotLifetime
		if offendingPosition and snapshotFresh and offsideSnapshotTeamId == actor.TeamId then
			clearOffsideSnapshot()
			queueRestart(Restarts.FreeKick, otherTeam(actor.TeamId), {
				Position = offendingPosition,
				Reason = "offside",
				-- Presented as the offside it is, to the team it is awarded to.
				Announce = "Offside",
			})
			log(string.format("Offside against %s", actor.DisplayName))
			return
		end
	end

	previousTouch = lastTouch
	lastTouch = {
		Id = actor.Id,
		TeamId = actor.TeamId,
		Kind = kind,
		At = os.clock(),
	}

	--[[
		A restart is NOT completed by touching the ball.

		This used to resume play on any contact from the authorized taker, which
		included ordinary control acquisition -- so an AI simply ran onto the
		stationary kick-off ball, took it in its stride and dribbled away. A
		restart is now completed only by MatchRulesService.NotifyRestartAction,
		reached through a legal release action (§27, §29).
	]]
	if MatchRulesService.AllowsFootballActions() then
		takeOffsideSnapshot(actor)
	end
end

--[[
	The taker played a legal restart action. THIS is what restarts the match.

	Called by FootballActionService (and the AI equivalents) once an action has
	been validated and the ball has actually been released. Returns whether the
	restart was completed, so a caller can log an illegal attempt.
]]
function MatchRulesService.NotifyRestartAction(actor, actionType: string): boolean
	if not buffer or not buffer.Started then
		return false
	end
	if not RestartService.IsAuthorizedTaker(actor) then
		return false
	end
	if not MatchRulesConfig.IsRestartActionAllowed(buffer.Restart, actionType) then
		log(string.format(
			"%s is not a legal way to take a %s; rejected",
			actionType,
			buffer.Restart
		))
		return false
	end

	local restart = buffer.Restart
	buffer = nil
	RestartService.Clear()
	relaxUntil = os.clock() + MatchRulesConfig.Timing.AfterRestartRelaxSeconds
	setPhase(Phases.Playing)
	publish()
	log(string.format("%s taken by %s with %s", restart, actor.DisplayName, actionType))
	return true
end

--[[
	Is `actor` allowed to play `actionType` at this instant?

	Ordinary play: yes. During a restart: only the taker, and only with an action
	that restart permits.
]]
function MatchRulesService.IsActionPermitted(actor, actionType: string): (boolean, string?)
	if phase == Phases.PreMatch or phase == Phases.Idle then
		return false, "match-not-started"
	end
	if not buffer then
		return MatchRulesService.AllowsFootballActions(), "ball-not-in-play"
	end
	if not buffer.Started then
		return false, "restart-not-ready"
	end
	if not RestartService.IsAuthorizedTaker(actor) then
		return false, "not-the-taker"
	end
	if not MatchRulesConfig.IsRestartActionAllowed(buffer.Restart, actionType) then
		return false, "illegal-restart-action"
	end
	return true, nil
end

--[[
	A goal (§68). GoalService remains authoritative for whether it was one; this
	only runs the celebration phase and the kick-off that follows.
]]
function MatchRulesService.NotifyGoal(concededGoalId: string, scorerId: number?): boolean
	--[[
		Returns whether the referee took ownership of the restart. When it does,
		the legacy "teleport the ball back to centre" path must stand down, or the
		celebration is cut short by a ball reset (§68).
	]]
	if not MatchService.IsPlaying() or phase == Phases.FullTime then
		return false
	end
	if phase == Phases.GoalCelebration then
		return true
	end
	-- The team that scored is the one attacking the goal that was conceded.
	local scoringTeam = if concededGoalId == "Home" then "Away" else "Home"

	pendingFoul = nil
	clearOffsideSnapshot()
	buffer = nil
	RestartService.Clear()

	celebratingScorerId = scorerId
	celebratingTeamId = scoringTeam
	setPhase(Phases.GoalCelebration)
	announce("Goal", tostring(scorerId), scoringTeam)

	local celebrationSeconds = MatchRulesConfig.Celebration.Seconds
	task.delay(celebrationSeconds, function()
		if phase ~= Phases.GoalCelebration then
			return
		end
		celebratingScorerId = nil
		celebratingTeamId = nil
		-- Kick-off to the team that conceded.
		queueRestart(Restarts.Kickoff, otherTeam(scoringTeam), { Reason = "after-goal" })
	end)

	log(string.format("Goal for %s; celebration %.1fs", scoringTeam, celebrationSeconds))
	return true
end

--[[
	Period handling (§49). Half time swaps nothing about team identity -- the
	attacking direction is what changes, and that is derived from the goal
	mapping, so both halves already work without renaming teams.
]]
local function endPeriod()
	if period == MatchRulesConfig.Periods.FirstHalf then
		period = MatchRulesConfig.Periods.SecondHalf
		clockSeconds = 0
		setPhase(Phases.HalfTime)
		announce("HalfTime")
		StaminaService.ApplyHalfTimeRecovery()
		log("Half time")
		task.delay(MatchRulesConfig.Clock.HalfTimeSeconds, function()
			if phase ~= Phases.HalfTime then
				return
			end
			-- Second half kicks off with the side that did not start the match.
			queueRestart(Restarts.Kickoff, otherTeam(kickoffTeamId), { Reason = "second-half" })
		end)
	else
		setPhase(Phases.FullTime)
		announce("FullTime")
		log("Full time")
	end
	publish()
end

local function updateBuffer()
	if not buffer then
		return
	end
	local now = os.clock()

	if not buffer.Prepared and now >= buffer.PrepareAt then
		buffer.Prepared = true
		setPhase(Phases.RestartSetup)
		RestartService.Prepare(buffer.Restart, buffer.TeamId, buffer.Position)
	end

	if buffer.Prepared and not buffer.Started and now >= buffer.StartAt then
		buffer.Started = true
		buffer.StartedAt = now
		setPhase(Phases.RestartReady)
		RestartService.BeginControl()
		announce("RestartReady", buffer.Restart, buffer.TeamId)
	end

	-- The ball stays on its spot and the taker stays near it until it is played.
	if buffer.Prepared then
		RestartService.UpdateControl()
	end

	--[[
		A human taker who does nothing must not stall the match. They keep the
		restart for a grace period (§67); after that an AI team-mate takes it, and
		only if there is no AI at all does the restart eventually abandon.
	]]
	if buffer.Started and not buffer.Reassigned then
		local elapsed = now - (buffer.StartedAt or now)
		if elapsed > MatchRulesConfig.Timing.HumanTakerGraceSeconds then
			local taker = RestartService.GetTaker()
			if taker and not taker.IsAI then
				buffer.Reassigned = true
				RestartService.ReassignTakerToAI()
			end
		end
	end

	--[[
		A restart nobody takes must not hang the match. After the abandon window
		the ball is simply live again where it stands.
	]]
	if buffer.Started and now - (buffer.StartedAt or now) > MatchRulesConfig.Timing.RestartAbandonSeconds then
		log(string.format("%s abandoned; resuming play", buffer.Restart))
		buffer = nil
		RestartService.Clear()
		relaxUntil = now + MatchRulesConfig.Timing.AfterRestartRelaxSeconds
		setPhase(Phases.Playing)
		publish()
	end
end

local function step(deltaTime: number)
	--[[
		Stamina runs before every early return, because it must keep recovering
		during stoppages, half time and pre-match -- those are exactly when a
		footballer gets their breath back (§45).
	]]
	StaminaService.Update(deltaTime, phase)

	if not MatchService.IsPlaying() then
		--[[
			PRE-MATCH (§23-§26).

			Once the field has been assembled the players are already standing in
			their kick-off shape, so the phase must NOT be reset to Idle -- that
			would tear the arrangement down again every frame. PreMatch holds the
			assembled field, motionless, until the user presses START MATCH.
		]]
		if phase == Phases.PreMatch then
			-- Keep the ball on the centre spot, and everyone in their shape.
			RestartService.UpdateControl()
			RestartService.HoldAssembly()
			return
		end
		if phase ~= Phases.Idle then
			setPhase(Phases.Idle)
			buffer = nil
			pendingFoul = nil
			RestartService.Clear()
			clearOffsideSnapshot()
			clockSeconds = 0
			period = MatchRulesConfig.Periods.FirstHalf
			publish()
		end
		return
	end

	if phase == Phases.Idle or phase == Phases.PreMatch then
		--[[
			The match starts with a KICK-OFF, and the clock does not run until it
			has been taken (§26). The phase therefore goes to Stoppage here (via
			queueRestart), never straight to Playing -- the old code entered
			Playing first, which both started the clock early and briefly allowed
			ordinary football actions before anyone was in position.
		]]
		previousBallPosition = ball and ball.Position or nil
		local resumingFromPreMatch = phase == Phases.PreMatch
		if resumingFromPreMatch then
			-- The field is already assembled; go straight to the ready kick-off.
			setPhase(Phases.Stoppage)
		end
		kickoffTeamId = "Home"
		if buffer then
			-- Kick-off was queued during field assembly. Let it run.
			buffer.PrepareAt = math.min(buffer.PrepareAt, os.clock())
			buffer.StartAt = math.min(buffer.StartAt, os.clock() + MatchRulesConfig.Timing.StartDelaySeconds)
		else
			queueRestart(Restarts.Kickoff, kickoffTeamId, { Reason = "match-start" })
		end
	end

	if phase == Phases.FullTime then
		return
	end

	-- Clock only advances while the ball is live (§48).
	if phase == Phases.Playing then
		clockSeconds += deltaTime
		if clockSeconds >= MatchRulesConfig.GetHalfSeconds() then
			endPeriod()
			return
		end
	end

	updateBuffer()

	--[[
		THE SERVER HALF OF THE MOVEMENT LOCK.

		The client refuses to move during the phases in
		MatchRulesConfig.MovementLockedPhases, and this is what makes that a rule
		rather than a request: while the pitch is being ARRANGED, every footballer
		is held at the position the arrangement put them at, so a client that
		ignored the phase still cannot walk out of the restart shape.

		PreMatch is handled on its own path above (it returns early, because it
		must not fall through to the Idle reset). This covers the rest of the
		arranging period -- a restart being set up, and the pause after a goal.

		Cheap by design: HoldAssembly only acts on a footballer that has actually
		drifted, and only while a restart record exists to hold them to.
	]]
	if MatchRulesConfig.MovementLockedPhases[phase] == true then
		RestartService.HoldAssembly()
	end

	--[[
		Injury stoppage (§73). Only a moderate injury stops the match; a knock or
		a minor one is played through, which is what keeps a competitive match
		from stopping constantly.
	]]
	if phase == Phases.Playing and not buffer then
		local injuredId = InjuryService.GetStoppageCandidate()
		if injuredId then
			local injured = FootballerRegistryService.GetActorById(injuredId)
			if injured and injured.TeamId then
				-- One stoppage per injury; the player stays injured afterwards.
				InjuryService.MarkStoppageServed(injuredId)
				setPhase(Phases.InjuryStoppage)
				announce("Injury", nil, injured.TeamId)
				log(string.format("Injury stoppage for %s", injured.DisplayName))
				local restartPosition = injured.RootPart and injured.RootPart.Position or nil
				task.delay(MatchRulesConfig.Injury.TreatmentSeconds, function()
					if phase ~= Phases.InjuryStoppage then
						return
					end
					-- Play resumes with the injured side in possession.
					queueRestart(Restarts.FreeKick, injured.TeamId, {
						Position = restartPosition,
						Reason = "injury",
					})
				end)
				return
			end
		end
	end

	if phase == Phases.Playing then
		-- Fouls outrank ball-out decisions, matching the source's ordering (§76).
		if not resolvePendingFoul() then
			checkBallOut()
		end
	end

	if ball then
		previousBallPosition = ball.Position
	end

	publish()
end

--[[
	FIELD ASSEMBLY (§23, §24, §26).

	Called once every participant, goalkeeper and official exists, and BEFORE the
	client is allowed to reveal the pitch. It arranges the kick-off exactly as the
	referee would and then holds everything still in PreMatch.

	Returns false when the pitch is not ready to be arranged, so the caller can
	report which required actor was missing rather than revealing a half-built
	match.
]]
function MatchRulesService.PrepareMatch(): boolean
	if not initialized or MatchRulesConfig.Enabled ~= true then
		return false
	end
	if MatchService.IsPlaying() then
		-- A match already running is not re-assembled.
		return false
	end
	if phase == Phases.PreMatch and buffer then
		return true
	end

	buffer = nil
	pendingFoul = nil
	clearOffsideSnapshot()
	RestartService.Clear()
	clockSeconds = 0
	period = MatchRulesConfig.Periods.FirstHalf
	kickoffTeamId = "Home"
	StaminaService.Reset()

	local position = RestartService.ResolveBallPosition(Restarts.Kickoff, kickoffTeamId, nil)
	if not position then
		log("Field assembly deferred: pitch geometry not ready")
		return false
	end

	--[[
		Position everyone NOW rather than on a timer. The whole point of this
		phase is that the first visible frame is already correct, so the prepare
		delay a normal restart uses would defeat it.
	]]
	local taker = RestartService.Prepare(Restarts.Kickoff, kickoffTeamId, position)
	if not taker then
		log("Field assembly deferred: no kick-off taker available")
		return false
	end

	local now = os.clock()
	buffer = {
		Restart = Restarts.Kickoff,
		TeamId = kickoffTeamId,
		Position = position,
		PrepareAt = now,
		-- Not started until the user presses START MATCH; step() re-times this.
		StartAt = math.huge,
		Prepared = true,
		Started = false,
		Context = { Reason = "match-start" },
	}

	setPhase(Phases.PreMatch)
	publish()
	log(string.format("Field assembled; kick-off to %s, taker %s", kickoffTeamId, taker.DisplayName))
	return true
end

function MatchRulesService.Initialize()
	if initialized or MatchRulesConfig.Enabled ~= true then
		return
	end
	initialized = true

	local created = ReplicatedStorage:FindFirstChild(MatchRulesConfig.FolderName)
	if not created then
		created = Instance.new("Folder")
		created.Name = MatchRulesConfig.FolderName
		created.Parent = ReplicatedStorage
	end
	folder = created :: Folder

	local remote = created:FindFirstChild(MatchRulesConfig.AnnouncementRemoteName)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = MatchRulesConfig.AnnouncementRemoteName
		remote.Parent = created
	end
	announcementRemote = remote :: RemoteEvent

	publish()

	StaminaService.Initialize()
	connection = RunService.Heartbeat:Connect(step)
end

function MatchRulesService.Destroy()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	initialized = false
end

return MatchRulesService
