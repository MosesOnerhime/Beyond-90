--!strict
-- Standing tackle / press. One rule set, used identically by humans and AI --
-- neither side gets a privileged possession-stealing path.
local DefendingConfig = {
	RemoteName = "DefensiveActionRequest",
	FeedbackRemoteName = "DefensiveActionFeedback",
	DebugEnabled = true,

	Tackle = {
		ActionType = "Tackle",
		-- Reach is measured tackler-root to ball, not tackler to opponent, so a
		-- tackle can only win a football that is genuinely exposed.
		MaximumBallDistance = 6.4,
		MaximumOpponentDistance = 8.5,
		-- The tackler must be facing the contest. This is what prevents a
		-- large invisible steal radius behind the defender.
		MinimumFacingDot = 0.35,
		-- Challenging from directly behind the carrier is far less likely to win
		-- the ball cleanly. 1.0 = directly behind, -1.0 = head on.
		MaximumBehindDot = 0.72,
		BehindPenalty = 0.45,

		-- Ball exposure: how far the football currently sits from its carrier.
		-- A ball tucked under the carrier's feet is much harder to take.
		MinimumExposure = 0.9,
		FullExposure = 4.2,
		ExposureWeight = 0.55,

		-- Closing speed helps, but only up to a point.
		ClosingSpeedFull = 14,
		ClosingSpeedWeight = 0.2,
		FacingWeight = 0.25,

		-- Above this combined score the challenge wins the ball.
		SuccessThreshold = 0.52,
		-- Between these two the ball is disturbed but not won outright.
		PartialThreshold = 0.34,

		Cooldown = 0.85,
		-- A missed challenge costs the defender a moment of recovery.
		RecoverySeconds = 0.6,
		FailedRecoverySeconds = 0.95,
		-- The tackler cannot instantly re-acquire what it just poked away, so the
		-- loose ball is genuinely contestable.
		TacklerAcquisitionSuppression = 0.34,
		TacklerExitDistance = 3.2,
		VictimAcquisitionSuppression = 0.5,
		VictimExitDistance = 4.6,

		--[[
			A CLEAN win (§43).

			Not a loose-ball impulse: a short controlled touch into the tackler's
			own path, followed by a reacquisition claim so the normal Capture
			path collects it. Possession is never assigned directly, so an
			opponent standing closer can still win the second ball.
		]]
		WonBallControl = {
			-- Gentle enough to stay inside the tackler's control lane.
			Speed = 7.5,
			Lift = 1.1,
			-- How much of the touch comes from the tackler's facing rather than
			-- from the geometry of the challenge.
			FacingWeight = 0.7,
			-- Priority while collecting. Comparable to the knock-on claim:
			-- meaningful, not decisive.
			ClaimSeconds = 1.6,
			ClaimScoreBonus = 1.1,
			-- Brief, because the challenge succeeded.
			RecoverySeconds = 0.22,
		},

		-- Loose-ball impulse applied on a PARTIAL poke.
		LooseBallSpeed = 17,
		LooseBallPartialSpeed = 9,
		LooseBallLift = 2.4,
		LooseBallLateralSpread = 0.35,
	},

	Press = {
		ActionType = "Press",
		-- Bounded assistance only. The human still chooses who to press and
		-- which direction to approach from.
		Enabled = true,
		--[[
			How far out holding V still counts as a press.

			26 studs was under half the distance a footballer covers in two
			seconds, so on a 343-stud pitch the assist refused to engage from most
			of the positions a defender actually presses from and holding V read
			as doing nothing. 44 is a genuine pressing distance without becoming
			"run anywhere on the pitch for me".
		]]
		MaximumDistance = 44,

		--[[
			HOLD-V ASSISTED PRESS (§41, §42).

			The assist runs toward a point GOAL-SIDE of the carrier, offset
			laterally so the approach is angled rather than straight into the
			carrier's back. Both numbers are small: this is help arriving in a
			useful position, not a defensive autopilot.
		]]
		GoalSideStandoff = 3.4,
		ApproachLateralOffset = 2.4,
		--[[
			Score the locally predicted challenge must reach before the assist
			commits. Above the server's own SuccessThreshold, so the assistance
			waits for a challenge that is likely to be WON rather than one that
			is merely legal -- a human tapping V can still take the marginal one.
		]]
		AutoTackleScore = 0.56,
		-- Assistance never drives the player faster than they could run.
		MaximumAssistSpeedScale = 1,

		--[[
			THE PRESS SPRINTS WHILE IT IS CLOSING (§37).

			The assist previously ran at whatever speed the player happened to be
			holding, so a press from any real distance was a jog and arrived far
			too late to be a press at all. Beyond SprintDistance the assist now
			requests sprint through the ordinary sprint path -- same top speed,
			same acceleration, same stamina cost a human pays. Inside that it
			drops back to a jockey so the defender can react to a change of
			direction instead of running past the carrier.
		]]
		SprintDistance = 11,
		--[[
			ROUTING AROUND, NOT THROUGH (§38).

			Dot of the approach direction against the carrier's heading above
			which the defender is genuinely behind them and must recover to a
			front-side point rather than charging through their back. Mirrors the
			AI's own defending model so both press the same way.
		]]
		BehindRecoveryDot = 0.3,
		-- How far down the carrier's path the recovery line aims, as a multiple
		-- of the current gap, bounded at both ends.
		RecoveryLeadScale = 1.25,
		MinimumRecoveryLead = 8,
		MaximumRecoveryLead = 30,
		-- Recover on the side the defender is already on; cutting across the
		-- carrier is the path that runs straight through them.
		RecoveryLateralOffset = 4.5,
		-- Assistance stops helping once inside this distance so the player is not
		-- driven into the carrier automatically.
		HoldDistance = 4.2,
		SlowDistance = 9,
		MaximumMoveMagnitude = 0.85,
		ManualOverrideMagnitude = 0.9,
		FacingResponsiveness = 11,
		Duration = 1.35,
	},

	AI = {
		Enabled = true,
		-- Only the designated presser challenges, so a team does not collapse
		-- onto one carrier.
		TackleDistance = 5.6,
		MinimumScoreToAttempt = 0.42,
		DecisionCooldown = 1.15,
		CommitmentSeconds = 0.45,
		-- Bounded reaction so AI does not challenge with zero latency.
		ReactionDelay = 0.2,
	},
}

return DefendingConfig
