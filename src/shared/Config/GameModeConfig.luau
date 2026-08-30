local GameModeConfig = {
	ReplicatedFolderName = "Beyond90GameMode",
	RequestRemoteName = "GameModeRequest",
	ExitRemoteName = "GameModeExit",
	ResetBallRemoteName = "TrainingResetBall",
	PingRemoteName = "Beyond90Ping",
	ScoreFolderName = "Beyond90SessionScore",
	HomeScoreAttributeName = "HomeScore",
	AwayScoreAttributeName = "AwayScore",
	DefaultMode = "Development",
	Modes = {
		Development = {
			DisplayName = "Development",
			Enabled = true,
		},
		--[[
			FREE PRACTICE IS PRACTICE, NOT A MATCH.

			It was running the entire organised-match pipeline: pick a team, pick
			a position, wait for START MATCH, a referee and two assistants walking
			on, a kick-off, a match clock and the full rules layer. None of that
			belongs in "go and kick a ball about", and all of it stood between the
			player and the thing they asked for.

			The capabilities below say what a mode actually uses, so the services
			can ask instead of testing the mode id -- which is how officials ended
			up on a training pitch in the first place (RefereeService spawned them
			for any match state that was not Idle, with no notion of mode).
		]]
		TrainingFree = {
			DisplayName = "Free Practice",
			Enabled = true,
			AllowsBallReset = true,
			RequiresTeamSelection = false,
			RequiresMatchAssembly = false,
			RequiresStartMatch = false,
			UsesMatchClock = false,
			UsesMatchRules = false,
			UsesOfficials = false,
			UsesKickoff = false,
		},
		Quick3v3 = {
			DisplayName = "Quick 3v3",
			Enabled = true,
			AllowsBallReset = true,
		},
		Tournament5v5 = {
			DisplayName = "Tournament 5v5",
			Enabled = false,
		},
		Clubs11v11 = {
			DisplayName = "Clubs 11v11",
			Enabled = false,
		},
	},
	ResetCooldown = 1,
}

--[[
	Does `modeId` use `capability`?

	Defaults to TRUE, so an organised match keeps every system it has always had
	without each one having to be listed; only a mode that opts out needs to say
	so. Reading this rather than comparing mode ids is what stops a new mode from
	silently inheriting a referee.
]]
function GameModeConfig.Uses(modeId: string?, capability: string): boolean
	if typeof(modeId) ~= "string" then
		return true
	end
	local definition = GameModeConfig.Modes[modeId]
	if not definition then
		return true
	end
	return definition[capability] ~= false
end

return GameModeConfig
