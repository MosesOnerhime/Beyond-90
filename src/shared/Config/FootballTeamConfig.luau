local FootballTeamConfig = {
	AttributeName = "Beyond90FootballTeamId",
	AttackingGoalAttributeName = "Beyond90AttackingGoalId",
	DefendedGoalAttributeName = "Beyond90DefendedGoalId",
	ValidTeams = {
		Home = true,
		Away = true,
	},
	GoalMapping = {
		Home = {
			AttackingGoalId = "Away",
			DefendedGoalId = "Home",
		},
		Away = {
			AttackingGoalId = "Home",
			DefendedGoalId = "Away",
		},
	},
}

function FootballTeamConfig.Normalize(value): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local normalized = string.lower(value)
	if normalized == "home" then
		return "Home"
	elseif normalized == "away" then
		return "Away"
	end
	return nil
end

--[[
	The other side.

	Derived from the goal mapping rather than from a second table, so there is
	only one place that knows Home and Away are opposites: a team attacks the
	goal its opponent defends, which is exactly what AttackingGoalId already
	says. Returns nil for anything that is not a real team, so a caller cannot
	award a restart to a side that does not exist.
]]
function FootballTeamConfig.GetOpponent(teamId: string?): string?
	local mapping = teamId and FootballTeamConfig.GoalMapping[teamId]
	if not mapping then
		return nil
	end
	return FootballTeamConfig.Normalize(mapping.AttackingGoalId)
end

function FootballTeamConfig.GetGoalMapping(teamId: string?)
	return teamId and FootballTeamConfig.GoalMapping[teamId] or nil
end

return FootballTeamConfig
