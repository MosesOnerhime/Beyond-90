local GoalConfig = {
	WorkspaceGoalBoundsPath = { "StadiumDevelopment", "GoalBounds" },
	Definitions = {
		Home = {
			BoundsName = "HomeGoalBounds",
			LineName = "HomeGoalLine",
		},
		Away = {
			BoundsName = "AwayGoalBounds",
			LineName = "AwayGoalLine",
		},
	},
	GoalScoredRemoteName = "GoalScored",
	TrainingAttackingGoalId = "Away",
	ResetBallAfterGoal = true,
	TrainingResetDelay = 1.5,
	GeometrySafetyMargin = 0.05,

	--[[
		How far in front of a goal line the ball must be before the "already
		scored" latch releases. Comfortably outside the six-yard box, so a ball
		bouncing around in the net cannot clear it, but any ball genuinely back
		in play does.
	]]
	LatchClearDistance = 6,
	DuplicateResetDistance = 2,
	DebugEnabled = true,
}

return GoalConfig
