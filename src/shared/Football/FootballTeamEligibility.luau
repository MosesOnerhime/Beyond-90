local RunService = game:GetService("RunService")

local FootballTeamEligibility = {}

local TEAM_ATTRIBUTE_NAMES = {
	"Beyond90FootballTeamId",
	"Beyond90TeamId",
}

local function getTeamKey(player: Player): any
	for _, attributeName in TEAM_ATTRIBUTE_NAMES do
		local value = player:GetAttribute(attributeName)
		if value ~= nil then
			return value
		end
	end

	return if player.Team then player.Team.Name else nil
end

function FootballTeamEligibility.AreTeammates(passer: Player, receiver: Player, targetingConfig): (boolean, string)
	if passer == receiver then
		return false, "receiver-is-passer"
	end

	local passerTeam = getTeamKey(passer)
	local receiverTeam = getTeamKey(receiver)
	if passerTeam ~= nil and receiverTeam ~= nil then
		local sameTeam = passerTeam == receiverTeam
		return sameTeam, if sameTeam then "same-team" else "receiver-not-teammate"
	end

	if passerTeam == nil and receiverTeam == nil and targetingConfig.AllowUnteamedDevelopmentReceivers == true then
		return true, "development-unteamed"
	end

	if RunService:IsStudio() and targetingConfig.AllowPartiallyAssignedStudioReceivers == true then
		return true, "studio-partial-team"
	end

	return false, "receiver-not-teammate"
end

return FootballTeamEligibility
