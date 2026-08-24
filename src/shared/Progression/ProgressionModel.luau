local ProgressionModel = {}

function ProgressionModel.CreateSessionState(config)
	local source = config.DevelopmentSessionProfile
	return {
		Level = source.Level,
		XP = source.XP,
		XPToNextLevel = source.XPToNextLevel,
		Reputation = source.Reputation,
		Persistent = false,
	}
end

return ProgressionModel
