--!strict
-- Authoritative match lifecycle. Play must not begin until every active
-- participant's gameplay client has finished initializing, otherwise AI starts
-- contesting the football while the user is still inside ModeLoading.
local MatchConfig = {
	FolderName = "Beyond90Match",
	ReadyRemoteName = "MatchClientReady",
	StartRequestRemoteName = "MatchStartRequest",
	StateAttributeName = "MatchState",
	StartedAtAttributeName = "MatchStartedAt",
	ModeAttributeName = "MatchMode",
	--[[
		Set on the PLAYER once the whole match has been assembled and every
		footballer, goalkeeper and official is standing in the kick-off shape
		(§24). The client will not reveal the pitch before this is true, which is
		what stops participants visibly popping in after the reveal (§82).
	]]
	FieldReadyAttributeName = "Beyond90FieldReady",

	States = {
		Idle = "Idle",
		-- Participants are still initializing their gameplay clients.
		WaitingForPlayers = "WaitingForPlayers",
		-- Everyone is loaded. The match waits here until a player presses
		-- START MATCH; nothing begins on a timer.
		ReadyToStart = "ReadyToStart",
		-- START MATCH was pressed: whistle + presentation are playing.
		Starting = "Starting",
		Playing = "Playing",
	},

	-- A player who is still loading must not hold the match hostage forever.
	ClientReadyTimeout = 20,
	-- How long the whistle/presentation runs after the button is pressed.
	StartPresentationSeconds = 1.6,
	-- Guard against a duplicate readiness signal restarting an active match.
	MinimumRestartInterval = 1,

	Presentation = {
		Title = "START MATCH",
		FadeInSeconds = 0.28,
		HoldSeconds = 0.9,
		FadeOutSeconds = 0.42,
		-- Copy for the pre-match button and its waiting state.
		ButtonLabel = "START MATCH",
		WaitingLabel = "WAITING FOR PLAYERS",
		Hint = "PRESS TO KICK OFF",
	},
}

-- Play-affecting systems ask this rather than testing state strings inline.
function MatchConfig.AllowsPlay(state: string?): boolean
	return state == MatchConfig.States.Playing
end

return MatchConfig
