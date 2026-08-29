--!strict
-- Development-only tooling. Every request is Studio-gated on the server; none
-- of this is reachable from a production client.
local DevToolsConfig = {
	RemoteName = "Beyond90DevToolsRequest",
	FeedbackRemoteName = "Beyond90DevToolsFeedback",

	Actions = {
		AddAI = "AddAI",
		RemoveAI = "RemoveAI",
		ResetPlayer = "ResetPlayer",
		ResetBall = "ResetBall",
		SetDribblingSkill = "SetDribblingSkill",
		AddGoalkeeper = "AddGoalkeeper",
		RemoveGoalkeeper = "RemoveGoalkeeper",
		-- Match-rule testing (§81). These force a decision the referee would
		-- otherwise have to be provoked into making.
		ForceRestart = "ForceRestart",
		ForceInjury = "ForceInjury",
		--[[
			Test parameters (§18, §52). Both are deliberately separate axes:

				Shot Intensity   = raw physical power, so a strength can be repeated
				Goalkeeper Skill = how good the keeper actually is

			Testing one without being able to hold the other fixed is what made
			"are shots weak or is the keeper strong?" unanswerable.
		]]
		SetShotIntensity = "SetShotIntensity",
		SetGoalkeeperSkill = "SetGoalkeeperSkill",
	},

	-- Guard rails so DEV spawning cannot exceed what a mode actually supports.
	MaximumAIPerTeam = 6,
	RequestCooldown = 0.2,

	--[[
		Goalkeeper skill, 0-100, applied to every keeper on the pitch (§52).
		Stored 0-1 on the actor; presented 0-100 here and on the panel.
	]]
	GoalkeeperSkill = {
		Default = 72,
		Minimum = 0,
		Maximum = 100,
		Step = 10,
		AttributeName = "Beyond90DevGoalkeeperSkill",
	},

	DribblingSkill = {
		Default = 70,
		Minimum = 0,
		Maximum = 100,
		Step = 10,
		AttributeName = "Beyond90DribblingSkill",
	},
}

return DevToolsConfig
