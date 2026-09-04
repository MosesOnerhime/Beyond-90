--!strict
--[[
	Match officiating.

	Every distance here is a RATIO of the pitch, never a stud count. The values
	are converted from GameplayFootball's metre constants on a 110 x 72 m pitch
	and multiplied by Beyond 90's own measured bounds at use time, because
	1 GameplayFootball metre is not 1 Roblox stud.
	See docs/research/gameplay-football/match-rules-and-positions.md.
]]
local MatchRulesConfig = {
	Enabled = true,

	FolderName = "Beyond90MatchRules",
	StateAttributeName = "MatchRulesPhase",
	RestartAttributeName = "MatchRulesRestart",
	RestartTeamAttributeName = "MatchRulesRestartTeam",
	ClockAttributeName = "MatchClockSeconds",
	PeriodAttributeName = "MatchPeriod",
	AnnouncementRemoteName = "MatchRulesAnnouncement",
	--[[
		Incremented on a CHARACTER every time the rules authoritatively reposition
		it (§64). The Broadcast Camera watches this to tell an intentional
		teleport apart from a tracking error.
	]]
	RepositionEpochAttributeName = "Beyond90RepositionEpoch",

	--[[
		Match phases (§47). Restart TYPE is a separate axis from phase, exactly as
		GameplayFootball keeps `e_MatchPhase` and `e_SetPiece` separate -- a
		RestartSetup is a RestartSetup whether it is a corner or a penalty.
	]]
	Phases = {
		Idle = "Idle",
		--[[
			The field is fully assembled and everyone is standing in the kick-off
			shape, but the match has not been started yet (§23, §26). Nothing may
			move in this phase, so it is deliberately NOT `Playing`.
		]]
		PreMatch = "PreMatch",
		Playing = "Playing",
		Stoppage = "Stoppage",
		RestartSetup = "RestartSetup",
		RestartReady = "RestartReady",
		GoalCelebration = "GoalCelebration",
		InjuryStoppage = "InjuryStoppage",
		HalfTime = "HalfTime",
		FullTime = "FullTime",
	},

	--[[
		PHASES IN WHICH NOBODY MAY MOVE.

		The rule the player asked for is "nobody should be able to move until the
		match is started, and everything should be in place before and after it
		starts". PreMatch alone only covered the first half of that: after a goal
		or a foul the phase goes Stoppage -> RestartSetup while the server walks
		every footballer, the referee and the ball to their restart positions, and
		a human running around during that is the reason the restart never looked
		set.

		So the lock spans the whole period in which positions are being ARRANGED,
		and lifts at RestartReady -- the moment the restart is genuinely live and
		the taker may play it. AI footballers and the keeper already hold still
		for the same phases, so this is one rule applied to everyone rather than a
		client-side restriction on humans.

		Shared, so the client's responsive half and the server's authority read
		the same list.
	]]
	MovementLockedPhases = {
		PreMatch = true,
		Stoppage = true,
		RestartSetup = true,
		GoalCelebration = true,
		HalfTime = true,
		FullTime = true,
	},

	Restarts = {
		None = "None",
		Kickoff = "Kickoff",
		ThrowIn = "ThrowIn",
		CornerKick = "CornerKick",
		GoalKick = "GoalKick",
		FreeKick = "FreeKick",
		Penalty = "Penalty",
	},

	Periods = {
		FirstHalf = "FirstHalf",
		SecondHalf = "SecondHalf",
	},

	--[[
		RESTART CONTROL (§28).

		A stationary restart is NOT foot-dribble possession. Runtime evidence
		showed the kick-off being taken as an ordinary loose-ball acquisition:

			RestartReady -> Reception TakeInStride -> Controlled -> AI runs away

		which is not a legal kick-off. The fix is architectural rather than a
		velocity restriction: while a restart is pending nobody -- the taker
		included -- may acquire normal possession. The taker instead holds
		RestartControl, and the restart is only complete when a LEGAL RELEASE
		ACTION is played.

		`Actions` lists, per restart, the action types that legally take it.
		`Movement` bounds how far the taker may stray from the ball while it is
		theirs, so they can still orient and aim but cannot walk the ball away.
	]]
	RestartControl = {
		Enabled = true,
		-- Published so clients can present the restart honestly.
		ControlAttributeName = "MatchRestartTakerFootballerId",
		AwaitingAttributeName = "MatchRestartAwaitingAction",

		Actions = {
			-- A kick-off must be PASSED. It may not be dribbled away.
			Kickoff = { GroundPass = true, ThroughPass = true, LobPass = true },
			-- The keeper distributes; a driven or lofted ball are both legal.
			--[[
				A goal kick may be PLAYED SHORT or STRUCK LONG.

				`Shoot` was missing, so the keeper's kick-long key was refused
				with `restart-not-yours` on the one restart it most obviously
				belongs to -- the player was the taker, and the action was still
				rejected, because the rejection reads "this action is not legal
				here" and reports it as though the taker were someone else.

				A goal kick struck with this key is not a shot at goal: see
				`handleRestartShot`, which sends it long and high upfield.
			]]
			GoalKick = { GroundPass = true, ThroughPass = true, LobPass = true, Shoot = true },
			-- A corner may be crossed, played short, or struck at goal.
			CornerKick = { GroundPass = true, ThroughPass = true, LobPass = true, Shoot = true },
			FreeKick = { GroundPass = true, ThroughPass = true, LobPass = true, Shoot = true },
			-- A penalty is a shot, and only a shot.
			Penalty = { Shoot = true },
			-- A throw-in is thrown, never kicked.
			ThrowIn = { ThrowIn = true },
		},

		--[[
			How far the taker may move from the restart spot before the server
			pulls them back. Generous enough to turn, aim and take a short run-up;
			far too small to carry the ball anywhere.
		]]
		Movement = {
			Kickoff = 5,
			GoalKick = 7,
			CornerKick = 5,
			FreeKick = 7,
			Penalty = 6,
			ThrowIn = 4.5,
			Default = 6,
		},

		--[[
			Where the football sits while it is held for the restart.

			A throw-in genuinely starts above the thrower's head, so it must not be
			a ground ball at the taker's feet (§32).
		]]
		BallHeight = {
			ThrowIn = 7.4,
			Default = 0,
		},
		-- The ball is pinned to the spot; this is how hard.
		HoldStiffness = 24,
	},

	--[[
		Set-piece buffer timings, in seconds.

		Same stop -> prepare -> start shape as GameplayFootball's RefereeBuffer,
		shortened because Beyond 90 matches are much shorter than 90 minutes.
	]]
	Timing = {
		PrepareSeconds = 1.5,
		StartDelaySeconds = 1.4,
		-- After a goal, players need longer to reset.
		KickoffPrepareSeconds = 3,
		--[[
			CONFIRMED FROM SOURCE, and the detail everything else depends on: the
			ball is still outside the lines at the instant a throw-in is taken, so
			without a relax window the touchline test immediately awards another
			throw-in, forever.
		]]
		AfterRestartRelaxSeconds = 0.6,
		-- A taken restart that nobody touches must not hang the match.
		-- Must stay comfortably beyond HumanTakerGraceSeconds, or the restart
		-- abandons before the AI it was just handed to can play it.
		RestartAbandonSeconds = 30,
		-- How long a human designated as taker keeps the restart before an AI
		-- team-mate steps in and plays it.
		--[[
			How long a HUMAN taker keeps a restart before an AI team-mate takes
			it instead (§34).

			Four seconds was far too short. A player who presses Pass, finds no
			receiver, looks up, repositions and tries again is doing exactly what
			a footballer should do at a free kick -- and was losing the restart
			for it. Twenty seconds is long enough to actually think, and still
			short enough that an idle player cannot stall the match.
		]]
		HumanTakerGraceSeconds = 20,
	},

	--[[
		Pitch ratios.

		Longitudinal ratios are fractions of HALF the pitch length; lateral ratios
		are fractions of HALF the width, unless named otherwise.
	]]
	Pitch = {
		-- Whole ball must be past the line, plus the line's own width.
		OutOfPlayLineRatio = 0.0011,
		--[[
			MEASURED FROM THE STADIUM, not converted from metres.

			These were previously derived from GameplayFootball's 110 x 72 m pitch
			and did not match Beyond 90's own painted markings, so "outside the
			penalty area" put players visibly inside the painted box and the
			penalty spot sat short of the painted one.

			Measured from Workspace.StadiumDevelopment.stadium line parts
			(2026-08-27), on a pitch measuring 343 long x 241 wide with goal lines
			at longitudinal +/-1:

				penalty area front line   60 studs in from the goal line
				penalty area half width   68.5 studs
				six-yard box front line   21 studs in
				penalty spot              2/3 of the box depth = 40 studs in

			Expressed as ratios so a differently-sized pitch still works.
		]]
		PenaltyAreaDepth = 0.35,
		PenaltyAreaHalfWidth = 0.5685,
		SixYardBoxDepth = 0.1224,
		-- 40 studs of a 171.5 half-length; the painted spot.
		PenaltySpotDepth = 0.2332,
		-- 9.15 m of a 110 m length.
		KeepOutDistance = 0.0832,
		-- Goal kicks are taken from 0.92 of the half-length out from centre.
		GoalKickDepth = 0.92,
		-- Throw-ins are clamped this far in from each goal line.
		ThrowInLongitudinalInset = 0.011,
		-- Nobody may stand inside the centre circle at kick-off (9.4 m / 110 m).
		KickoffCentreKeepOut = 0.0855,
		-- How far in from the touchline a thrower actually stands.
		ThrowInLateralInset = 0.004,
	},

	--[[
		Offside (§60-63).

		The rule itself is GameplayFootball's verbatim: the line is the
		second-last opponent, or the ball if the ball is further forward.
	]]
	Offside = {
		Enabled = true,
		-- Normalized relax margin, from the source's 0.20 m tolerance.
		RelaxRatio = 0.0018,
		--[[
			A snapshot is only taken when the team genuinely played the ball, and
			only for teams with more than one active outfielder -- the source
			disables offside in its one-keeper debug mode for the same reason.
		]]
		MinimumTeammates = 2,
		--[[
			No restart can produce a direct offside (§62): the snapshot is simply
			not taken while a restart is pending, so throw-ins, corners and goal
			kicks are all exempt without needing a list of exceptions.
		]]
		-- An offside decision is dropped if the snapshot is older than this.
		SnapshotLifetime = 12,
	},

	--[[
		Fouls (§58-59).

		Beyond 90 has no slide tackle yet (§84 excludes it), so only the standing
		challenge is scored. The from-behind term is the one that matters most and
		is taken from the source's severity model.
	]]
	Foul = {
		Enabled = true,
		-- A challenge is only a foul if the victim genuinely had the ball.
		MaximumVictimBallDistance = 6.5,
		-- Dot of (victim -> challenger) against the victim's facing. Above this
		-- the challenge came from behind.
		FromBehindDot = 0.35,
		-- Closing speed above which a challenge is reckless.
		RecklessRelativeSpeed = 26,
		--[[
			Weights sum to 1.5, so that is the maximum a challenge can score: a
			mistimed contact (0.5) straight through the back (0.55) at full speed
			(0.45). SeriousThreshold must sit below that ceiling or the serious
			branch -- and the injury it can cause -- is unreachable.
		]]
		Severity = {
			FoulThreshold = 1,
			SeriousThreshold = 1.35,
			FromBehindWeight = 0.55,
			MistimingWeight = 0.5,
			SpeedWeight = 0.45,
		},
		--[[
			Advantage (§59), deliberately simple. If the fouled side still has the
			ball after this window, play continues and the foul is dropped.
		]]
		Advantage = {
			Enabled = true,
			EvaluateAfter = 0.6,
			AbandonAfter = 2.4,
		},
		-- One foul decision per challenge.
		Cooldown = 1.2,
	},

	--[[
		Injuries (§71-74). Deliberately rare: a competitive match must not keep
		stopping. Only a serious foul or a heavy collision can cause one.
	]]
	Injury = {
		Enabled = true,
		States = {
			Healthy = "Healthy",
			Knocked = "Knocked",
			Minor = "InjuredMinor",
			Moderate = "InjuredModerate",
		},
		StateAttributeName = "Beyond90InjuryState",
		-- Chance a qualifying event actually injures, by severity.
		SeriousFoulChance = 0.35,
		HeavyCollisionChance = 0.06,
		-- Recovery, seconds.
		KnockedSeconds = 4,
		MinorSeconds = 12,
		ModerateSeconds = 22,
		-- Speed multiplier while injured.
		KnockedSpeedScale = 0.85,
		MinorSpeedScale = 0.7,
		ModerateSpeedScale = 0.55,
		-- Only a moderate injury stops the match.
		StoppageState = "InjuredModerate",
		TreatmentSeconds = 4,
		-- Nothing can injure the same footballer twice in quick succession.
		Cooldown = 20,
	},

	--[[
		Goal celebration (§68-70). Long enough to read as a celebration, short
		enough not to stall a development match.
	]]
	Celebration = {
		Enabled = true,
		Seconds = 4.5,
		-- The scorer runs to a point this far toward its own supporters.
		RunDistance = 18,
	},

	--[[
		Clock (§48). Server-authoritative. Development matches are deliberately
		short; production duration is a single value, not scattered constants.
	]]
	Clock = {
		--[[
			A TEN MINUTE MATCH -- five minutes a half.

			Requested as "extend match time to 10 minutes", read as the whole
			match rather than each half: development was 240s a half (an eight
			minute match), so this is a modest extension rather than a jump to
			twenty. Say so if the intent was ten minutes EACH way and this
			doubles.

			Production and development are the same value now, so a development
			match is not quietly a different length from a real one.
		]]
		HalfSeconds = 300,
		-- Long enough to actually play through a development match and see
		-- several natural restarts, short enough to reach full time in testing.
		DevelopmentHalfSeconds = 300,
		UseDevelopmentDuration = true,
		HalfTimeSeconds = 5,
	},

	Debug = {
		Enabled = true,
	},
}

-- During a restart the taker may play the ball, but nobody else may contest it.
function MatchRulesConfig.IsRestartPhase(phase: string?): boolean
	return phase == MatchRulesConfig.Phases.RestartSetup
		or phase == MatchRulesConfig.Phases.RestartReady
end

--[[
	May `actionType` legally take `restart`?

	This is the rule that stops a kick-off being "taken" by dribbling: control
	acquisition is not in any of these lists, so it can never complete a restart.
]]
function MatchRulesConfig.IsRestartActionAllowed(restart: string?, actionType: string?): boolean
	if not restart or not actionType then
		return false
	end
	local allowed = MatchRulesConfig.RestartControl.Actions[restart]
	return allowed ~= nil and allowed[actionType] == true
end

function MatchRulesConfig.GetTakerMovementRadius(restart: string?): number
	local movement = MatchRulesConfig.RestartControl.Movement
	return (restart and movement[restart]) or movement.Default
end

function MatchRulesConfig.GetRestartBallHeight(restart: string?): number
	local heights = MatchRulesConfig.RestartControl.BallHeight
	return (restart and heights[restart]) or heights.Default
end

function MatchRulesConfig.GetHalfSeconds(): number
	return if MatchRulesConfig.Clock.UseDevelopmentDuration
		then MatchRulesConfig.Clock.DevelopmentHalfSeconds
		else MatchRulesConfig.Clock.HalfSeconds
end

return MatchRulesConfig
