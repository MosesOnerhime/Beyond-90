# GameplayFootball Ball Control Research

## Reference Revision

Repository: https://github.com/vi3itor/GameplayFootball.git

Branch: master

Commit: 68159a2f0f96eec8ebba26ab7820130f36b922a7

Date Researched: 2026-08-12

## Scope

This research covers ball control, possession, dribbling, player/ball coordination, reachability, touches, loss of control, prediction, and the comparison to Beyond 90 Milestone 4.1.

CONFIRMED FROM SOURCE: The reference clone was kept outside the Beyond 90 runtime source tree at an OS temp location and was not mapped through Rojo.

RECOMMENDATION: This document is research only. Do not treat it as approved Beyond 90 architecture.

## Beyond 90 Current State

CONFIRMED FROM SOURCE: `BallService` owns the server-created development football lifecycle. It creates or reuses `Workspace/Beyond90/Ball/DevelopmentFootball`, configures it as an unanchored physical ball, assigns `SetNetworkOwner(nil)`, initializes `BallControlService`, and drives ball interaction checks from `RunService.Heartbeat` at `BallConfig.BasicTouch.CheckInterval`.

CONFIRMED FROM SOURCE: `BallService` also owns free-ball basic touches. When `BallControlService.Update(ball)` returns true, free-ball touches are skipped. When control is absent, all players are scanned for basic touch eligibility.

CONFIRMED FROM SOURCE: `BallControlService` owns control state. It stores one `activeController`, writes ball attributes `State`, `ControllerUserId`, and `LastReleaseReason`, and uses string states `Free` and `Controlled`.

CONFIRMED FROM SOURCE: Control acquisition uses `AcquireDistance`, `MaximumControllableBallSpeed`, `ControlHeightTolerance`, minimum player speed, a dot product toward the ball, and a clear contact-path raycast. Candidate score is `towardBallDot * 2 - distance / AcquireDistance`, with an existing-controller score bonus.

CONFIRMED FROM SOURCE: Control retention uses a separate context with `ReleaseDistance`, `ControlRetentionMaxSpeed`, `ControlRetentionHeightTolerance`, no acquire movement requirement, and no clear-path requirement at context creation. The invalid-reason check can release for missing/dead controller, ball too high, ball too fast, distance exceeded, ball behind player, or contact path blocked. Soft invalid reasons use `ReleaseGracePeriod`.

CONFIRMED FROM SOURCE: Close control is impulse-based. The server updates a smoothed control direction, applies anti-overlap separation if the ball center is too close to the player, then, when the player is moving, periodically impulses the ball toward a forward target at either `ControlTargetDistanceWalk` or `ControlTargetDistanceSprint`.

CONFIRMED FROM SOURCE: Walking and sprinting differ by target distance and dribble strength, based on the server-side humanoid `SprintRequested` attribute.

CONFIRMED FROM SOURCE: The forward target is `rootPart.Position + controlDirection * targetDistance`. The impulse direction is from the current ball position toward that target. The impulse delta subtracts current ball speed in that target direction and clamps by `MaxDribbleImpulseDeltaSpeed`.

CONFIRMED FROM SOURCE: Anti-overlap correction compares horizontal player-ball distance against `ControlOriginRadius + BallConfig.Radius + MinimumControlSeparation`, then impulses along a blend of radial direction and current control direction.

CONFIRMED FROM SOURCE: If the player is nearly stationary, Beyond 90 retains the last control direction but returns before applying normal dribble impulses. Anti-overlap can still run.

CONFIRMED FROM SOURCE: Sharp turns are damped by `updateControlDirection`: if the new movement direction is too different from the last control direction, the previous direction is kept for that update. There is no predicted turn path or next-touch plan.

CONFIRMED FROM SOURCE: Beyond 90 currently does not use relative velocity for retention, predicted ball position, estimated time-to-ball, or recent control-touch history for control retention. It uses current horizontal distance, ball speed, ball height, direction/behind check, contact path, and controller validity.

CONFIRMED FROM SOURCE: Current networking boundary is server-authoritative football control. Sprint input is requested by the client but validated only as a boolean and applied server-side through `PlayerService`. The football remains unanchored and server-owned with `SetNetworkOwner(nil)`.

## Source Files Investigated

Beyond 90:

- `src/server/Services/BallService.luau`
- `src/server/Services/BallControlService.luau`
- `src/shared/Config/BallConfig.luau`
- `src/server/Services/PlayerService.luau`
- `src/client/Controllers/MovementController.luau`
- `src/server/ServerBootstrap.server.luau`
- `src/client/ClientBootstrap.client.luau`
- `src/shared/Config/PlayerConfig.luau`
- `docs/`

GameplayFootball:

- `src/onthepitch/ball.hpp`
- `src/onthepitch/ball.cpp`
- `src/onthepitch/match.hpp`
- `src/onthepitch/match.cpp`
- `src/onthepitch/team.hpp`
- `src/onthepitch/team.cpp`
- `src/onthepitch/player/player.hpp`
- `src/onthepitch/player/player.cpp`
- `src/onthepitch/player/playerbase.hpp`
- `src/onthepitch/player/playerbase.cpp`
- `src/onthepitch/AIsupport/AIfunctions.hpp`
- `src/onthepitch/AIsupport/AIfunctions.cpp`
- `src/onthepitch/AIsupport/mentalimage.hpp`
- `src/onthepitch/AIsupport/mentalimage.cpp`
- `src/onthepitch/player/controller/playercontroller.cpp`
- `src/onthepitch/player/controller/humancontroller.cpp`
- `src/onthepitch/player/controller/elizacontroller.cpp`
- `src/onthepitch/player/humanoid/humanoid.hpp`
- `src/onthepitch/player/humanoid/humanoid.cpp`
- `src/onthepitch/player/humanoid/humanoid_utils.hpp`
- `src/onthepitch/player/humanoid/humanoid_utils.cpp`
- `src/utils/animationextensions/footballanimationextension.hpp`
- `src/utils/animationextensions/footballanimationextension.cpp`
- `src/utils/animation.cpp`
- `src/gamedefines.hpp`
- relevant `data/media/animations/...` metadata referenced by source searches

Important symbols traced:

- `Ball::Predict`, `Ball::CalculatePrediction`, `Ball::Touch`, `Ball::Process`
- `MentalImage::UpdateBallPredictions`, `MentalImage::GetBallPrediction`
- `Player::UpdatePossessionStats`, `Player::HasPossession`, `Player::HasBestPossession`, `Player::HasUniquePossession`, `Player::AllowLastDitch`
- `Team::UpdatePossessionStats`, `Team::SetLastTouchPlayer`, `Team::GetDesignatedTeamPossessionPlayer`
- `Match::CalculateBestPossessionTeamID`, `Match::GetDesignatedPossessionPlayer`, `Match::GetBallRetainer`, `Match::CheckHumanoidCollisions`
- `AI_HasPossession`, `AI_GetTimeNeededForDistance_ms`, `AI_GetToBallMovement`, `AI_GetBallControlMovement`, `AI_GetBestDribbleMovement`
- `PlayerController::_MovementCommand`, `PlayerController::_BallControlCommand`
- `Humanoid::GetBodyBallDistanceAdvantage`, `Humanoid::CalculateMovementSmuggle`, `Humanoid::GetBestPossibleTouch`
- `GetBallControlVector`, `GetTrapVector`, `GetDifficultyFactors`, `GetFrontOfFootOffsetRel`
- `FootballAnimationExtension::GetTouchCount`, `GetTouch`, `GetTouchPos`, `GetFirstTouch`

## Confirmed GameplayFootball Behavior

CONFIRMED FROM SOURCE: GameplayFootball does not reduce possession to one strict ball owner. It maintains several related concepts:

- A physical ball with independent position, momentum, rotation, and prediction samples.
- Per-player possession booleans.
- Per-player time-needed-to-ball estimates.
- Per-team possession booleans and best time-to-ball.
- Match-level `bestPossessionTeamID`.
- Team-level `designatedTeamPossessionPlayer`.
- Match-level `designatedPossessionPlayer`.
- A separate `ballRetainer` for special hold/carry states such as keeper/retain animations.
- Last-touch player/team history with decaying bias.

CONFIRMED FROM SOURCE: The ball is predicted up to `ballPredictionSize_ms = 3000` with samples at 10 ms intervals. Prediction simulates gravity, drag, bounce, ground friction, rotation/ground effects, swerve, posts, and netting.

CONFIRMED FROM SOURCE: `Ball::Touch` sets ball momentum, recalculates prediction immediately, updates the latest mental-image predictions, and refreshes both teams' possession stats.

CONFIRMED FROM SOURCE: `Player::UpdatePossessionStats` estimates time-to-ball by scanning predicted ball positions. For each future sample with low enough height, it calls `AI_GetTimeNeededForDistance_ms` using player position, player movement, predicted ball position, max velocity, precision mode, and the candidate future time.

CONFIRMED FROM SOURCE: `AI_GetTimeNeededForDistance_ms` is not raw distance divided by speed only. It accounts for current player movement, a 700 ms movement-change horizon, reach radii, max velocity, an optimistic reach radius, and a current-movement offset.

CONFIRMED FROM SOURCE: `AI_HasPossession` is stricter than "best chance to reach the ball." It rejects players more than 5 m from the current ball, rejects balls higher than 0.5 m, requires the ball to be inside a 1 m radius around a center slightly ahead of the player, and requires the ball movement over the next 10 ms to be close to the player's movement.

CONFIRMED FROM SOURCE: `Team::UpdatePossessionStats` aggregates active players. A team has possession if any active player has possession; team time-to-ball is the minimum player time-to-ball.

CONFIRMED FROM SOURCE: `Match::CalculateBestPossessionTeamID` chooses the best team by lower team time-to-ball unless a `ballRetainer` exists. Match-level designated possession switches only when a candidate is meaningfully better, using a time ratio threshold.

CONFIRMED FROM SOURCE: `Team::Process` similarly switches `designatedTeamPossessionPlayer` only when a candidate is meaningfully better. The switch rating is biased by possession booleans and human-control status to reduce possession chaos.

CONFIRMED FROM SOURCE: Human and AI controller code can blend input with automatic movement toward predicted ball/control targets. `PlayerController::_MovementCommand` calls `AI_GetBallControlMovement` when the player has best possession, and `AI_GetToBallMovement` when the player is likely to contest/recover the ball. The final movement is a blend of manual and automatic movement.

CONFIRMED FROM SOURCE: `PlayerController::_BallControlCommand` queues an `e_FunctionType_BallControl` command only when the player is the match designated possession player or the team designated possession player with enough duel likelihood. It also blocks many non-possession ball-control attempts unless last-ditch is allowed and ball/player relative velocity is plausible.

CONFIRMED FROM SOURCE: Ball-control touches are discrete, animation-frame-based touches. Animation metadata exposes football touch positions and frames. When the active animation reaches its touch frame, the code checks current ball distance and height against the animation touch point, then calls `GetBallControlVector`, `GetTrapVector`, pass/shot functions, or collision vectors depending on the animation function type.

CONFIRMED FROM SOURCE: Ball-control touch vectors are planned around a future ball position. `GetBallControlVector` computes a planned ball location ahead of the next player start position using outgoing movement, desired/controller movement, front-of-foot offset, desired/physics delay times, player stats, and a physics-vs-desired bias. It then computes the touch vector needed to get the ball there.

CONFIRMED FROM SOURCE: Traps and poor contacts can preserve current ball movement. `GetTrapVector` blends a ball-control vector with existing ball movement based on difficulty factors. Difficulty factors include relative player-ball movement, current ball distance from the player/body, recent opponent touch bias, skill, and position offset.

CONFIRMED FROM SOURCE: Ordinary body-ball collision is a separate path in `Match::CheckHumanoidCollisions`. It is gated by recent opponent touch bias, excludes recent self-touch, checks animation function type, uses body AABBs, and may either trigger a controlled collision or produce an accidental bounce.

CONFIRMED FROM SOURCE: Animation selection uses predicted ball position at candidate touch frames. It checks football extension touch entries, predicted ball movement around the touch frame, ball height, body/foot reach geometry, velocity, incoming/outgoing movement, recent touch bias, and a deformed allowed reach area. It can reject touches that are too far or geometrically implausible.

CONFIRMED FROM SOURCE: `Humanoid::CalculateMovementSmuggle` can slightly adjust player movement during eligible possession animations so the body/foot reaches the predicted ball location. The source explicitly describes this as a tradeoff between visually touching the ball and physically correct movement.

## Possession Model

CONFIRMED FROM SOURCE: GameplayFootball possession is layered, not binary ownership.

CONFIRMED FROM SOURCE: `AI_HasPossession` answers "is the ball currently close and moving with this player?" It depends on distance, ball height, player movement, ball movement, and a center slightly ahead of the player.

CONFIRMED FROM SOURCE: `timeNeededToGetToBall_ms` answers "how soon can this player reach a future predicted ball sample?" It can keep a player competitively relevant even when the ball is not currently within close possession radius.

CONFIRMED FROM SOURCE: `designatedPossessionPlayer` answers "who should be treated as the current/main likely possession actor?" It is based on team and player time-to-ball, current designation, and hysteresis thresholds.

INFERENCE: GameplayFootball distinguishes "the ball is currently controlled close to the feet" from "this player is still the expected next controller." This is directly relevant to Beyond 90's distance-exceeded failure.

INFERENCE: A GameplayFootball player can remain the designated likely possession player while the ball is temporarily ahead, because designation and time-to-ball are not identical to `AI_HasPossession`.

## Ball Prediction

CONFIRMED FROM SOURCE: Ball prediction lives in `Ball::CalculatePrediction` and is accessed by `Ball::Predict`.

CONFIRMED FROM SOURCE: The prediction horizon is 3000 ms, sampled every 10 ms.

CONFIRMED FROM SOURCE: Prediction is consumed by possession stats, AI mental images, player movement, ball-control movement, animation selection, collisions, goalkeeping, off-ball logic, and presentation/radar-adjacent systems.

CONFIRMED FROM SOURCE: `MentalImage` stores prediction snapshots and clamps old mental predictions toward current real predictions to limit divergence.

INFERENCE: Prediction is central to GameplayFootball's model. It lets systems reason about where the ball will be when a player or animation can reach it, not only where the ball is now.

## Time-to-Ball / Reachability

CONFIRMED FROM SOURCE: `Player::UpdatePossessionStats` scans future ball predictions and finds the earliest future time where `AI_GetTimeNeededForDistance_ms` says the player can reach the predicted ball position by that time.

CONFIRMED FROM SOURCE: Reachability inputs include player position, player movement, target predicted ball position, player max velocity, current movement-change constraints, precision mode, target time, and low-ball height filtering.

CONFIRMED FROM SOURCE: The time-to-ball function has usual and optimistic outputs. `Player::AllowLastDitch` compares optimistic time against usual time to decide if a last-ditch attempt is plausible.

INFERENCE: GameplayFootball's time-to-ball estimate is a recoverability signal. It can say "the ball is far right now, but this player can still arrive in time."

RECOMMENDATION: Beyond 90 should evaluate a Roblox-native recoverability signal for retention and arbitration. It should be cheaper and simpler than GameplayFootball's C++ implementation.

## Player Movement During Control

CONFIRMED FROM SOURCE: GameplayFootball can influence player movement while controlling or chasing the ball.

CONFIRMED FROM SOURCE: `AI_GetBallControlMovement` targets the predicted ball at `250 + defaultTouchOffset_ms`, blends automatic direction toward the ball with manual/current direction at very short distances, and sets velocity from distance to ball.

CONFIRMED FROM SOURCE: `AI_GetToBallMovement` searches future predicted ball positions, rates reachable targets, chooses direction/velocity/look-at, and can prioritize haste.

CONFIRMED FROM SOURCE: `PlayerController::_MovementCommand` blends manual movement with auto movement using `autoBias`. In some human-controlled cases, recent touch bias, possession amount, same-direction factor, and switch bias can partially magnet the player toward the likely ball path.

INFERENCE: This is a player-ball coordination system. It keeps the footballer and ball aligned around future touches. It is not merely "move the ball to the player."

RECOMMENDATION: Beyond 90 should not copy human movement magnetism wholesale. Human players should keep directional agency. Useful pieces are reachability, target planning, and continuity, not autonomous football decisions.

## Ball-Control Touches

CONFIRMED FROM SOURCE: Control touches are discrete, not continuous impulses every physics update.

CONFIRMED FROM SOURCE: A touch happens when an animation's `touchFrame` equals the current frame and the ball is close enough to the animation's touch point. The ball is then touched through `Ball::Touch`, which sets momentum and recalculates prediction.

CONFIRMED FROM SOURCE: Touch timing is animation synchronized. Animation football extensions define one or more possible touch frames/positions, and animation variables also provide a default touch frame.

CONFIRMED FROM SOURCE: Player speed, desired velocity, player max velocity, outgoing animation movement, ball height, ball velocity, player direction, current body angle, player stats, opponent proximity, and recent-touch history can influence the final touch.

CONFIRMED FROM SOURCE: Walking/running/sprinting are conceptually different through velocity ranges, animation sets, outgoing velocities, sprint stretching, overdrive, and delay time. Sprinting can produce further/larger planned touches but is constrained by outgoing movement and player max velocity.

CONFIRMED FROM SOURCE: A poor touch can naturally remain loose because difficulty factors blend in existing ball movement, add height/distance error, and reduce clean control.

INFERENCE: GameplayFootball's controlled touch means "a planned animation-foot contact changes the independent ball's momentum toward a future controllable situation." It is not simply "the ball belongs to the player."

## Dribbling Behavior

CONFIRMED FROM SOURCE: AI dribble decision-making uses force fields from opponents, boundaries, and goal attraction to pick desired movement. This is AI decision logic, not a required ball-control primitive.

CONFIRMED FROM SOURCE: Once a dribble/control direction is chosen, ball-control movement and touch-vector planning aim to keep the ball reachable for another touch after a short delay.

INFERENCE: The useful football concept is repeated planned touches into reachable space, not the specific AI dribble route selection.

## Turning And Direction Changes

CONFIRMED FROM SOURCE: GameplayFootball does not instantly redirect the ball every frame. Direction changes happen through selected movement/control animations and their touch frames.

CONFIRMED FROM SOURCE: Animation selection evaluates predicted ball position and body/foot reach at the future touch frame, including incoming/outgoing movement and reach geometry.

CONFIRMED FROM SOURCE: `CalculateBiasForFastCornering` and animation/movement logic account for current movement vs desired movement changes, making sharp turns slower/harder than simple direction replacement.

CONFIRMED FROM SOURCE: `GetBallControlVector` blends physics movement with desired/controller movement and uses a physics bias. If the player does not have possession, physics bias is higher. Idle outgoing velocity uses full physics bias.

INFERENCE: On 90-degree or 180-degree turns, GameplayFootball tends to preserve momentum until a reachable animation touch changes it. The player may be adjusted toward the ball, but the ball is not teleported into the new direction.

## Loss Of Control

CONFIRMED FROM SOURCE: `AI_HasPossession` can become false because the ball is too far from the small possession center, too high, or moving too differently from the player.

CONFIRMED FROM SOURCE: A player can lose best/designated status when another player/team has a better time-to-ball by enough margin.

CONFIRMED FROM SOURCE: Touches can be degraded by difficulty factors from relative velocity, ball distance, recent opponent touch, position offset, and skill. Degraded touches preserve more existing ball movement and can become loose.

CONFIRMED FROM SOURCE: Ordinary collision can produce accidental touches and set last-touch history, separate from controlled touches.

CONFIRMED FROM SOURCE: There is no direct equivalent to Beyond 90's single `ReleaseDistance` deciding control. Distance appears in `AI_HasPossession`, reachability, animation selection, and collision gates, but it is not the only possession/control validity criterion.

INFERENCE: GameplayFootball's control loss is usually a change in likelihood/reachability/touch plausibility, not just exceeding a fixed radius.

## Multiple-Player Considerations

CONFIRMED FROM SOURCE: Every active player computes possession and time-to-ball stats.

CONFIRMED FROM SOURCE: Teams aggregate possession and minimum time-to-ball. The match chooses best possession team from team time-to-ball and then chooses a designated possession player with hysteresis.

CONFIRMED FROM SOURCE: Human-controlled players receive switching/magnet biases, but designated possession still depends on time-to-ball and possession status.

CONFIRMED FROM SOURCE: Another player can become the likely controller before any strict "owner" changes because best team/player designation is time-to-ball based.

RECOMMENDATION: Beyond 90's future human-vs-human arbitration should consider "who can realistically control the ball next" before binary ownership switches.

## Animation Relationship

CONFIRMED FROM SOURCE: Animation is directly involved in authoritative ball interaction in GameplayFootball. Touch frames and touch positions determine when and where a touch may occur.

CONFIRMED FROM SOURCE: Animation selection uses ball predictions at future touch frames. When touch frame arrives and checks pass, ball momentum is changed.

CONFIRMED FROM SOURCE: Player velocity/orientation affect animation selection, movement smuggle, touch vector, touch reachability, and touch quality.

RECOMMENDATION: Beyond 90 should eventually sync animations with control touches, but Milestone 4.3 should not require a full animation-authored touch system. A small timed-touch abstraction can represent the same concept without blocking on final Roblox animations.

## GameplayFootball Strengths

CONFIRMED FROM SOURCE: It separates current close possession, best chance to reach, team possession, designated player, retained/caught ball, and last touch.

CONFIRMED FROM SOURCE: It uses short-term and medium-term ball prediction everywhere possession requires future reasoning.

CONFIRMED FROM SOURCE: It models reachability as time-to-ball rather than raw distance.

CONFIRMED FROM SOURCE: It makes touches discrete and planned, with animation timing and future ball/player coordination.

CONFIRMED FROM SOURCE: It allows bad contacts and contested situations to naturally become loose through relative velocity, recent touch, and reachability factors.

INFERENCE: These ideas work for football because football control is not constant ownership. A dribbled ball repeatedly leaves the foot and is recovered by the same player because the next touch remains likely.

## GameplayFootball Problems / Limitations

CONFIRMED FROM SOURCE: The reference itself warns the code is undocumented, scruffy, untested, and for inspiration.

CONFIRMED FROM SOURCE: Large parts of the system exist because most footballers are AI-controlled and must decide where to run, pass, shoot, or dribble.

CONFIRMED FROM SOURCE: The engine is C++ with custom physics, custom animation data, custom mental-image snapshots, custom humanoid movement, and no Roblox networking model.

INFERENCE: Directly copying the architecture would be inappropriate for Roblox Humanoids, server-owned assemblies, replication, mobile/console input, exploit resistance, and 22 human players.

RECOMMENDATION: Do not copy AI dribble route selection, movement magnetism strength, class hierarchy, exact constants, animation data format, or custom physics structure.

## Roblox Considerations

INFERENCE: Roblox Humanoid movement and server-owned ball physics create a different responsiveness problem than GameplayFootball's local C++ simulation. A server-owned football with `SetNetworkOwner(nil)` is authoritative but may feel delayed when impulses depend on replicated character state and server physics timing.

INFERENCE: A future Beyond 90 model must account for PC/mobile/console input, 3v3 through 11v11, up to 22 human players, and server performance. Time-to-ball cannot be an expensive per-player 3000 ms scan every frame.

RECOMMENDATION: Use a lightweight short-horizon prediction and recoverability check, likely over a few samples such as 100-500 ms, with cached per-player context. Keep final gameplay authority on the server.

RECOMMENDATION: Preserve player agency. Do not automate direction choices that should belong to humans.

## Comparison With Beyond 90 Milestone 4.1

| Topic | GameplayFootball | Beyond 90 Milestone 4.1 |
| --- | --- | --- |
| Possession definition | Layered: close possession, time-to-ball, designated players, team possession, retainer, last touch. | Binary `Free`/`Controlled` plus one `activeController`. |
| Control acquisition | Based on designated player, time-to-ball, possession status, touch/animation eligibility. | Current distance, ball speed, height, movement toward ball, clear contact path, score. |
| Control retention | Reachability, possession status, designated continuity, animation/touch plausibility. | Current controller validity, current distance, ball speed, height, behind check, path check. |
| Control loss | Loss of possession, worse time-to-ball, bad touch, collision, reach failure, retain state ending. | Release on invalid reason after grace; repeated issue is `distance exceeded`. |
| Player-ball distance | Used but across close possession, touch reach, and reachability. | Central retention gate through `ReleaseDistance`. |
| Player velocity | Used in time-to-ball, movement change, touch quality, animation selection. | Used mainly for movement direction and walking/sprinting state; not retention relative to ball. |
| Ball velocity | Used in prediction, possession movement match, touch quality, collision, reachability. | Used as max speed gate and impulse speed subtraction toward target. |
| Relative velocity | Direct possession and touch-quality input. | Not used for retention except indirect current target speed in impulse calculation. |
| Ball prediction | Central 3000 ms prediction array. | No ball prediction. |
| Reachability/time-to-ball | Core possession and arbitration signal. | No estimated time-to-ball. |
| Player movement coordination | Player movement can be blended toward predicted ball/control targets. | Human movement remains Roblox Humanoid input; ball is moved by server impulses. |
| Ball touches | Discrete animation-frame touches. | Periodic physics impulses while controlled. |
| Walking control | Different velocity/animation/control planning. | Shorter target distance and lower strength. |
| Sprint control | Longer/faster planned touches but constrained by animation/velocity. | Longer target distance and higher strength. |
| Turning | Requires reachable future touch/animation; momentum is not instantly replaced. | Control direction smoothing can hold old direction; impulses still target fixed forward point. |
| Stopping | Idle/low-speed anim/control can use physics bias; possession may continue if ball matches player. | Normal dribble impulse stops when player is stationary; anti-overlap may still run. |
| Ball becoming loose | Natural result of bad reach, bad touch, relative velocity, other player better, collision. | Mostly explicit release state or free-ball basic touch mode. |
| Multiple-player competition | Every player/team has time-to-ball and possession metrics. | Candidates are scored by distance/dot; one active controller has a bonus. |
| Animation involvement | Authoritative touch timing and reach checks depend on animation metadata. | No ball-control animation involvement yet. |
| Networking assumptions | Local/custom engine, no Roblox replication/security constraints. | Roblox server-authoritative ball with `SetNetworkOwner(nil)`. |

INFERENCE: Beyond 90 currently relies heavily on current distance plus a fixed forward target plus repeated impulses plus binary control validity. That conclusion is supported by `BallControlService` source and by the absence of prediction, relative velocity retention, reachability, and planned touch continuity.

## Analysis Of Beyond 90 Distance-Exceeded Failure

Observed failure:

```text
Control acquired
~0.75-1.1 seconds
Control released: distance exceeded
```

CONFIRMED FROM SOURCE: `distance exceeded` can only be produced when horizontal player-ball distance exceeds `Control.ReleaseDistance` during active-controller validation and remains invalid for `ReleaseGracePeriod`, unless another reason releases first.

CONFIRMED FROM SOURCE: Close-control impulses push the ball toward a forward target of 3.8 studs walking or 5.3 studs sprinting. Release distance is 6.8 studs. This leaves limited margin for impulse overshoot, rolling momentum, delayed server updates, and player deceleration/turning.

CONFIRMED FROM SOURCE: Control update cadence is tied to `BasicTouch.CheckInterval` at 0.08 seconds. Dribble impulses are limited by `DribbleTouchInterval` at 0.1 seconds, so in practice normal dribble impulses may occur only on alternating service updates depending on timing.

CONFIRMED FROM SOURCE: Retention does not ask whether the player can still reach the ball shortly. It asks whether the ball is currently within release distance, speed, height, behind, and contact-path limits.

CONFIRMED FROM SOURCE: The ball remains physically simulated and server-owned. It receives impulses but is not kinematically constrained to the player.

CONFIGURATION evidence:

- Target distances are relatively close to the release limit, especially sprint target 5.3 vs release 6.8.
- Dribble strength, max impulse delta speed, separation correction, and impulse cadence can produce overshoot.
- Grace period is short relative to the observed one-second failure and the 0.08 second update cadence.

PHYSICS evidence:

- The football is unanchored and physically simulated.
- Repeated impulses can accelerate the ball beyond the player's ability to keep up.
- Rolling momentum and server physics timing can keep carrying the ball after the player slows or turns.

CONTROL ARCHITECTURE evidence:

- Retention is binary and current-distance-heavy.
- There is no relative horizontal velocity retention check.
- There is no predicted ball location or reachability estimate.
- There is no planned next-touch relationship.
- The controller and football are coordinated only by impulses toward a fixed forward target.

NETWORKING evidence:

- The ball is server-owned with `SetNetworkOwner(nil)`.
- Player motion and sprint state are used server-side.
- INFERENCE: In live play, replicated character motion and server physics cadence can make close control less responsive than local visual movement, especially for sprinting or sharp turns.

INFERENCE: The failure is likely MIXED, with control architecture as the primary category and configuration/physics/networking as contributing categories. Tuning alone may hide the issue, but the source suggests the current model lacks the reachability and planned-touch concepts that make a ball temporarily ahead still controllable.

RECOMMENDATION: Do not simply increase `ReleaseDistance`. Investigate whether the ball is still realistically controllable by the player using short-term predicted ball location, relative velocity, movement direction, and recent valid control continuity.

## Useful Concepts For Beyond 90

RECOMMENDATION: Keep the football physically independent and server authoritative, but make control a relationship rather than strict ownership.

RECOMMENDATION: Add lightweight short-term ball prediction for control logic. This should be much smaller than GameplayFootball's 3000 ms array.

RECOMMENDATION: Add a recoverability/time-to-ball approximation for the active controller and nearby challengers.

RECOMMENDATION: Add relative horizontal velocity as a retention and touch-quality signal.

RECOMMENDATION: Add recent valid control touch/continuity history so one bad sample does not immediately mean "loose."

RECOMMENDATION: Replace continuous "push to fixed target" behavior with more discrete planned control touches, or at least make impulses represent planned next-touch outcomes.

RECOMMENDATION: Keep walking and sprinting different, but make sprinting produce farther recoverable touches rather than simply larger target offsets.

RECOMMENDATION: Later, when animations exist, align control touches with animation contact windows. For Milestone 4.3, a data-driven timed-touch approximation is enough.

## Concepts Beyond 90 Should NOT Adopt

RECOMMENDATION: Do not port GameplayFootball's C++ class hierarchy.

RECOMMENDATION: Do not automate human dribble decisions using force-field AI.

RECOMMENDATION: Do not fully magnet human player movement toward the ball in competitive play.

RECOMMENDATION: Do not run a 3000 ms, 10 ms sample prediction for every player every frame on Roblox servers.

RECOMMENDATION: Do not make authoritative ball touches depend on final Roblox animations before the MVP touch model is fun.

RECOMMENDATION: Do not assume GameplayFootball constants map to Roblox studs, Humanoid speeds, network timing, or mobile controls.

## Proposed Beyond 90 Direction

RECOMMENDATION: Milestone 4.3 should prototype a Roblox-native "control eligibility" model:

1. Keep server authority and `SetNetworkOwner(nil)` for now.
2. Keep one active controller for MVP clarity.
3. Treat `Controlled` as "this player is the current expected controller while the ball remains realistically recoverable," not "the ball must stay inside a strict close-distance bubble at all times."
4. Retain current distance as one signal, but combine it with relative velocity, short-term predicted ball position, movement direction, ball height, recent valid control touch, and simple controller continuity.
5. Use planned touches that push the ball to a next controllable location over a short time horizon.
6. Add challenger reachability only as much as needed to avoid unfair sticky control near opponents.

INFERENCE: This model best matches football. During dribbling, the ball is independent, sometimes ahead of the player, and still under control if the player is expected to make the next touch.

## Free / Controlled State Recommendation

RECOMMENDATION: Choose option B for Milestone 4.3: keep `Free` and `Controlled`, but redefine `Controlled` as a control eligibility/relationship rather than strict close-distance ownership.

RECOMMENDATION: Do not add an intermediate state yet. A recoverable/transition state may become useful later, but Milestone 4.3 should first test whether richer eligibility inside `Controlled` solves the close-control failure.

RECOMMENDATION: `Free` should mean no player currently has a valid control relationship and ordinary free-ball interaction/arbitration applies.

RECOMMENDATION: `Controlled` should mean one player currently has priority because the ball is close, recently touched, and/or predicted to remain recoverable in the short term.

## Networking Implications

INFERENCE: Server-owned ball simulation is secure but may be less responsive for close-control feel. The current model is especially sensitive because all corrective impulses and release checks happen on the server.

RECOMMENDATION: Later production versions should investigate client-side visual prediction, predicted local touches, server reconciliation, interpolation, controlled physics ownership, server-owned simulation, and hybrid approaches.

RECOMMENDATION: Do not change network ownership during Milestone 4.2 or as an automatic part of Milestone 4.3. First fix the conceptual control model under the current server-owned ball assumption.

## Open Questions

- How far ahead can the Roblox server-owned ball travel at walk/sprint speeds before players still perceive it as controlled?
- What short prediction horizon works best in Roblox: 100 ms, 200 ms, 350 ms, or 500 ms?
- How much relative velocity mismatch should still count as recoverable?
- Should sprint dribbling intentionally create loose-risk touches, and how much skill expression should that add?
- How should control behave when the player releases movement input and the ball is already ahead?
- How should 90-degree and 180-degree turns trade responsiveness against believable football momentum?
- How often should server control touches occur under Heartbeat without overloading 22-player matches?
- How much challenger reachability is needed before controlled possession becomes unfairly sticky?
- Whether future client-side prediction is needed for feel after the server-side control model improves.

