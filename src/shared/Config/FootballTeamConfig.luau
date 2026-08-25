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

function FootballTeamConfig.GetGoalMapping(teamId: string?)
	return teamId and FootballTeamConfig.GoalMapping[teamId] or nil
end

return FootballTeamConfig
