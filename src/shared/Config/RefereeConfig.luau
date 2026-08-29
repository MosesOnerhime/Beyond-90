--!strict
--[[
	The match referee.

	A visible official who follows play and whistles decisions. This is
	presentation and readability, not a rules authority: MatchRulesService already
	owns every decision, and the referee reacts to those decisions rather than
	making any of them. Nothing here may ever influence a competitive outcome.

	Real referees run a DIAGONAL, staying off the line of play and keeping the
	ball between themselves and an assistant. Beyond 90 has no assistants yet, so
	the referee holds a trailing diagonal offset from the ball: close enough to
	read as officiating, far enough never to be in the way.
]]
local RefereeConfig = {}

RefereeConfig.Enabled = true
RefereeConfig.Name = "Referee"
RefereeConfig.FolderName = "Officials"
RefereeConfig.DebugEnabled = true

--[[
	ASSISTANT REFEREES (§60-§63).

	Two officials, one per touchline, each responsible for one half of the pitch.
	They are physical, visual participants -- NOT rule authority. Offside is
	decided by OffsideEvaluator on the server exactly as before; an assistant
	merely stands level with the line that evaluation already produces, so a
	decision never depends on whether an NPC visually reached a spot (§62).
]]
RefereeConfig.Assistants = {
	Enabled = true,
	Count = 2,
	NameFormat = "AssistantReferee%d",
	DisplayName = "ASSISTANT",
	-- Outside the touchline, so they never enter the field of play.
	TouchlineOffset = 7,
	-- Never past either goal line.
	GoalLineMargin = 3,
	ArrivalRadius = 2,
	JogSpeed = 14,
	SprintSpeed = 22,
	SprintDistance = 16,
	AccelerationTime = 0.3,
	DecelerationTime = 0.45,
	--[[
		Bounded tracking rate (§102). The offside line is recomputed here at a
		much lower frequency than the rules use it; movement between updates is
		smoothed by the ordinary locomotion, so this reads as continuous.
	]]
	UpdateInterval = 0.15,
	--[[
		Each assistant covers the half containing its own end. Beyond 90 has no
		flag animation yet (§103 excludes it), so this is position only.
	]]
	KitColor = Color3.fromRGB(28, 32, 40),
	KitBlend = 0.8,
}

RefereeConfig.Animation = {
	Enabled = true,
	--[[
		Officials reuse the shared off-ball locomotion clips: idle, jog and run.
		They get NO football action animations (§58) -- a referee never passes,
		shoots or tackles, so loading those clips would only be a chance to play
		one by accident.
	]]
	IdleFadeSeconds = 0.15,
	MoveFadeSeconds = 0.12,
	-- Measured world-space speed thresholds, so the clip always matches the
	-- motion rather than the intent.
	IdleSpeedThreshold = 1,
	SprintSpeedThreshold = 17,
	JogReferenceSpeed = 14,
	SprintReferenceSpeed = 24,
	MinimumPlaybackSpeed = 0.55,
	MaximumPlaybackSpeed = 1.5,
}

RefereeConfig.Character = {
	-- The classic dark official's kit, so the referee is never mistaken for
	-- either side at a glance.
	KitColor = Color3.fromRGB(24, 26, 32),
	KitBlend = 0.82,
	AccentColor = Color3.fromRGB(240, 214, 66),
	DisplayName = "REFEREE",
}

RefereeConfig.Positioning = {
	--[[
		How far behind and to the side of the ball the referee holds.

		Lateral offset is applied along the pitch WIDTH axis and flipped to
		whichever side has more room, so the referee is pushed toward the middle
		when play hugs a touchline instead of being shoved off the pitch.
	]]
	TrailDistance = 26,
	LateralDistance = 20,
	-- Never closer than this to the football, so the official can never end up
	-- standing in a passing lane.
	MinimumBallDistance = 12,
	-- Stay this far inside the touchlines and goal lines.
	BoundaryMargin = 6,
	-- Anticipation: lead the ball by this fraction of a second of its velocity.
	BallLookAhead = 0.35,
	ArrivalRadius = 3.5,
	JogSpeed = 15,
	SprintSpeed = 26,
	SprintDistance = 22,
	AccelerationTime = 0.35,
	DecelerationTime = 0.5,
	-- Update at a bounded rate; an official has no need for per-frame decisions.
	UpdateInterval = 0.06,
}

RefereeConfig.Stoppage = {
	--[[
		During a stoppage the referee walks to the restart spot rather than
		continuing to trail the ball, which is what makes a decision readable.
	]]
	ApproachDistance = 7,
	Speed = 13,
}

RefereeConfig.Whistle = {
	Enabled = true,
	AssetId = "9125967307",
	Volume = 1,
	-- Heard across the stadium, so it is not a positional-only cue.
	RollOffMinDistance = 30,
	RollOffMaxDistance = 420,
	--[[
		How many blasts each decision gets, and how long between them. Real
		officiating uses whistle LENGTH and COUNT as language: one short blast for
		an ordinary offence, three for the end of a period.
	]]
	Patterns = {
		Kickoff = { Count = 1, Gap = 0, Speed = 1 },
		ThrowIn = { Count = 1, Gap = 0, Speed = 1.12 },
		CornerKick = { Count = 1, Gap = 0, Speed = 1.05 },
		GoalKick = { Count = 1, Gap = 0, Speed = 1.05 },
		FreeKick = { Count = 1, Gap = 0, Speed = 0.95 },
		Penalty = { Count = 2, Gap = 0.22, Speed = 0.9 },
		Foul = { Count = 1, Gap = 0, Speed = 0.92 },
		Offside = { Count = 1, Gap = 0, Speed = 1.08 },
		Goal = { Count = 1, Gap = 0, Speed = 1 },
		Injury = { Count = 2, Gap = 0.18, Speed = 1 },
		HalfTime = { Count = 2, Gap = 0.24, Speed = 0.95 },
		FullTime = { Count = 3, Gap = 0.22, Speed = 0.9 },
	},
	Default = { Count = 1, Gap = 0, Speed = 1 },
	-- Announcements that are informational rather than a decision. The referee
	-- does not whistle to say a restart is now ready to be taken.
	Silent = {
		RestartReady = true,
	},
}

--[[
	How each decision is presented on the HUD.

	Kept here rather than in the HUD so the referee and the notification can never
	describe the same decision differently.
]]
RefereeConfig.Announcements = {
	Kickoff = { Title = "KICK-OFF", Tone = "Neutral" },
	ThrowIn = { Title = "THROW-IN", Tone = "Neutral" },
	CornerKick = { Title = "CORNER KICK", Tone = "Neutral" },
	GoalKick = { Title = "GOAL KICK", Tone = "Neutral" },
	FreeKick = { Title = "FREE KICK", Tone = "Warning" },
	Penalty = { Title = "PENALTY", Tone = "Bad" },
	Foul = { Title = "FOUL", Tone = "Warning" },
	Offside = { Title = "OFFSIDE", Tone = "Warning" },
	Goal = { Title = "GOAL", Tone = "Good" },
	Injury = { Title = "INJURY", Tone = "Bad" },
	HalfTime = { Title = "HALF TIME", Tone = "Neutral" },
	FullTime = { Title = "FULL TIME", Tone = "Neutral" },
	RestartReady = { Title = "RESTART READY", Tone = "Neutral" },
}

RefereeConfig.Notification = {
	HoldSeconds = 2.6,
	FadeSeconds = 0.28,
}

function RefereeConfig.GetAnnouncement(kind: string)
	return RefereeConfig.Announcements[kind]
end

function RefereeConfig.GetWhistlePattern(kind: string)
	if RefereeConfig.Whistle.Silent[kind] then
		return nil
	end
	return RefereeConfig.Whistle.Patterns[kind] or RefereeConfig.Whistle.Default
end

return RefereeConfig
