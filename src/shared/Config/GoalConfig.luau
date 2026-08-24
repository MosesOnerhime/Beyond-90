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
	DuplicateResetDistance = 2,
	DebugEnabled = true,
}

return GoalConfig
