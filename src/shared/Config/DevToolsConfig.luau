--!strict
-- Development-only tooling. Every request is Studio-gated on the server; none
-- of this is reachable from a production client.
local DevToolsConfig = {
	RemoteName = "Beyond90DevToolsRequest",
	FeedbackRemoteName = "Beyond90DevToolsFeedback",

	-- How far in front of the feet GivePossession drops the ball. Roughly one
	-- controlled-touch lead, so it lands where a footballer would be carrying it
	-- rather than inside their own collision.
	GivePossessionLead = 2.4,

	Actions = {
		AddAI = "AddAI",
		RemoveAI = "RemoveAI",
		ResetPlayer = "ResetPlayer",
		ResetBall = "ResetBall",
		--[[
			GIVE ME THE BALL (§18). Puts the football at the requester's feet,
			dead, with any existing controller released -- so the ordinary
			acquisition path hands it straight to them.

			It exists because reaching a specific on-ball situation otherwise
			means waiting for the AI to concede possession in roughly the right
			place, which makes testing anything that starts with "while you have
			the ball" slow and unrepeatable.
		]]
		GivePossession = "GivePossession",
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
