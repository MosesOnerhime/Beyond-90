# Shooting, Goals, And Training Foundation

## Shooting Authority

Shoot input predicts only presentation. The client sends aim intent and an
action identifier; the server validates possession, ball distance, cooldown,
and runtime goal geometry. The server reconstructs a target safely inside the
selected goal mouth. A prepared shot releases at the owned animation's
`BallContact` marker when available, with a short server fallback so a missing
marker cannot stall gameplay. Once launched, the ball is physical and receives
no homing or steering.

Training currently fixes the attacking goal to `Away`, so every legal Training
shot resolves inside the Away goal mouth. A future team/match service can
publish the server-owned
`Beyond90AttackingGoalId` player attribute without changing `ShotPlanner`'s
target and launch contract.

Shooting accuracy is represented by the server-owned
`Beyond90ShootingSkill` attribute. Studio exposes a development-only control;
production clients cannot submit an authoritative skill value. Skill reduces
target dispersion and increases the safe post/crossbar inset. A Shoot request
farther than the configured attacking range becomes a physical `Clearance`
using the same temporary presentation, with no assisted goal target.

## Goal Geometry And Detection

`GoalGeometry` resolves `HomeGoalBounds`, `HomeGoalLine`, `AwayGoalBounds`, and
`AwayGoalLine` beneath `Workspace.StadiumDevelopment.GoalBounds`. It derives
the inward direction from each line toward the pitch center and derives mouth
width from the actual oriented bounds rather than assuming a fixed world axis.

`GoalService` consumes the authoritative pre-validation samples emitted by
`BallService`. This ordering lets the goal-line segment test run before an
out-of-bounds safety reset. Goal detection is independent of whether the last
action was a shot, pass, knock-on, clearance, deflection, or loose-ball touch. It
detects segment crossing of the goal-line plane at one ball radius beyond the
line, then validates that the whole ball is inside the post and crossbar
limits. A per-goal latch prevents duplicate events while the ball remains in
the goal. Match score and restart flow remain future systems.

The authoritative goal event drives a short client `GOAL` notification. In
Training, server composition resets the ball to the pitch center after `1.5`
seconds. The notification never decides whether a goal occurred, and the reset
does not implement match scoring or restart rules.

## Acquisition And Reception

Loose-ball assistance moves the local footballer toward a short predicted ball
position while the server keeps the ball free. Possession is granted only when
the physical player and ball enter the reception envelope; control-epoch and
deep-overlap CFrame rescues are disabled. Strong manual input overrides the
assist.

Intended pass reception uses a bounded high-speed window and a swept ball
segment test so a driven pass cannot skip through the receiver between server
steps. During the brake/receive phase, gameplay orientation faces against the
incoming ball velocity before the presentation animation plays. The first
touch remains server-owned ball physics.

## Training Mode

`GameModeService` publishes an extensible mode definition. `TrainingFree` is
the only complete mode in this milestone and supports the existing football
sandbox plus a validated reset-ball request. Disabled future modes are UI
placeholders, not simulated functionality. The contract is compatible with a
future menu-to-place `TeleportData` mode selection, but no place split or
matchmaking system is introduced here.

## UI And Progression

The client screen controller owns Loading, Home, Training, and Gameplay HUD
views. Essential owned animation assets are preloaded through
`ContentProvider`; a timeout allows noncritical asset failure without trapping
the player on Loading. Training entry closes the menu and restores movement.

Progression uses an explicit nonpersistent session state containing Level, XP,
XPToNextLevel, and Reputation. It is a binding contract for later persistence
and rewards, not a production economy and not a source of gameplay attributes.
