# GameplayFootball Dribble Cycle

## Reference Revision

Repository: https://github.com/vi3itor/GameplayFootball.git

Branch: master

Commit: 68159a2f0f96eec8ebba26ab7820130f36b922a7

Date Researched: 2026-08-12

CONFIRMED FROM SOURCE: The commit above is `master` / `origin/master` in the vi3itor clone at `D:/repos/GameplayFootball`. The local working branch was not used as the reference; source was inspected explicitly at commit `68159a2f0f96eec8ebba26ab7820130f36b922a7`.

CONFIRMED FROM SOURCE: The exact commit metadata inspected was `68159a2f0f96eec8ebba26ab7820130f36b922a7`, dated `2021-07-20 16:31:54 +0900`.

## Scope

This document maps one complete human-controlled GameplayFootball dribble/control cycle to a future Roblox-native Beyond 90 implementation.

The goal is not to port C++ classes. The goal is to preserve the working behavioral relationships:

human input -> bounded ball-contact movement assistance -> valid next contact -> planned outgoing ball velocity -> physical ball travel -> prediction/possession refresh -> next contact.

This is research and architecture mapping only. It does not authorize production code changes.

## Full Dribble Cycle Overview

CONFIRMED FROM SOURCE: A normal human dribble cycle in GameplayFootball is not "keep the ball inside a bubble" and is not "push the ball every update." The ball remains independent, and control is recreated through repeated planned touches.

CONFIRMED FROM SOURCE: The high-level cycle is:

1. `HumanController::RequestCommand` reads HID input and stores input direction/velocity through `_SetInput`.
2. Human input velocity becomes one of the discrete movement intents: idle, dribble, walk, or sprint.
3. `PlayerController::_MovementCommand` creates the normal movement command. When this player is the relevant possession actor, it calls `AI_GetBallControlMovement`.
4. `AI_GetBallControlMovement` predicts where the ball will be around `250 + defaultTouchOffset_ms`, then creates assisted movement toward that predicted ball location.
5. `_MovementCommand` blends manual movement and automatic movement with `autoBias`.
6. `HumanController::RequestCommand` also queues `_BallControlCommand` and `_TrapCommand` during open play.
7. `_BallControlCommand` creates an `e_FunctionType_BallControl` command only for the match designated possession player or a plausible team designated duel player.
8. `Humanoid::Process` picks the first applicable command, runs `SelectAnim`, and selects a compatible ball-control/trap animation.
9. The selected animation carries a football extension with touch frame and touch position metadata.
10. Until the touch frame, humanoid movement and optional smuggle logic move the player toward a plausible contact.
11. When `currentAnim->touchFrame == currentAnim->frameNum`, the ball must be close enough to the animation touch point and height.
12. For a possession ball-control touch, `GetBallControlVector` calculates the desired post-contact ball momentum.
13. `Ball::Touch(touchVec)` sets ball momentum to that vector, recalculates ball prediction, updates the latest mental-image predictions, and refreshes team possession stats.
14. Match/team/player possession designation is recalculated over following process updates.

INFERENCE: The "dribble" is a loop of player contact planning plus post-contact momentum establishment, not a persistent ownership state.

## Source Call Chain

CONFIRMED FROM SOURCE: Primary source files and symbols traced:

- `src/onthepitch/player/controller/humancontroller.cpp`
  - `HumanController::RequestCommand`
  - `HumanController::Process`
  - `HumanController::_GetHidInput`
  - `HumanController::GetDirection`
  - `HumanController::GetFloatVelocity`
- `src/onthepitch/player/controller/playercontroller.cpp`
  - `PlayerController::Process`
  - `PlayerController::_Preprocess`
  - `PlayerController::_SetInput`
  - `PlayerController::_MovementCommand`
  - `PlayerController::_BallControlCommand`
  - `PlayerController::_TrapCommand`
  - `PlayerController::_CalculateSituation`
- `src/onthepitch/AIsupport/AIfunctions.cpp`
  - `AI_GetBallControlMovement`
  - `AI_GetToBallMovement`
  - `AI_GetTimeNeededForDistance_ms`
  - `AI_HasPossession`
- `src/onthepitch/player/player.cpp`
  - `Player::UpdatePossessionStats`
- `src/onthepitch/team.cpp`
  - `Team::UpdatePossessionStats`
  - `Team::SelectPlayer`
  - team designated possession switching in `Team::Process`
- `src/onthepitch/match.cpp`
  - `Match::CalculateBestPossessionTeamID`
  - match designated possession switching in `Match::Process`
  - `Match::UpdateLatestMentalImageBallPredictions`
- `src/onthepitch/player/humanoid/humanoid.cpp`
  - `Humanoid::Process`
  - `Humanoid::SelectAnim`
  - `Humanoid::NeedTouch`
  - `Humanoid::CalculateMovementSmuggle`
  - touch-frame handling
- `src/onthepitch/player/humanoid/humanoid_utils.cpp`
  - `GetFrontOfFootOffsetRel`
  - `GetDifficultyFactors`
  - `GetBallControlVector`
  - `GetTrapVector`
- `src/utils/animationextensions/footballanimationextension.cpp`
  - `FootballAnimationExtension::GetFirstTouch`
  - `FootballAnimationExtension::GetTouchCount`
  - `FootballAnimationExtension::GetTouch`
  - `FootballAnimationExtension::GetTouchPos`
- `src/onthepitch/ball.cpp` / `ball.hpp`
  - `Ball::Touch`
  - `Ball::SetMomentum`
  - `Ball::CalculatePrediction`
  - `Ball::Predict`
- `src/gamedefines.hpp`
  - movement speeds, prediction horizon, touch offset, distance-to-velocity multiplier.

## Human Input Flow

CONFIRMED FROM SOURCE: Raw human input enters in `HumanController::_GetHidInput`.

CONFIRMED FROM SOURCE: `rawInputDirection = hid->GetDirection()`. If the input magnitude is below `analogStickDeadzone`, the direction falls back to the player's current direction and velocity becomes `idleVelocity`.

CONFIRMED FROM SOURCE: If input is above the deadzone, velocity is selected from button state:

- sprint button -> `sprintVelocity`
- dribble button -> `dribbleVelocity`
- switch button while the player is the match designated possession player -> `idleVelocity`
- otherwise -> `walkVelocity`

CONFIRMED FROM SOURCE: Values from `src/gamedefines.hpp`:

- `idleVelocity = 0.0`
- `dribbleVelocity = 3.5`
- `walkVelocity = 5.0`
- `sprintVelocity = 8.0`
- `idleDribbleSwitch = 1.8`
- `dribbleWalkSwitch = 4.2`
- `walkSprintSwitch = 6.0`
- `analogStickDeadzone = 0.75`

CONFIRMED FROM SOURCE: `HumanController::RequestCommand` calls `_GetHidInput`, then `_SetInput(rawInputDirection, rawInputVelocityFloat)`. `_SetInput` lives on `PlayerController` and stores `inputDirection` and `inputVelocityFloat`.

CONFIRMED FROM SOURCE: The human controller does not directly set final player velocity. It supplies movement intent. `PlayerController::_MovementCommand`, ball-control assistance, command queue selection, and animation/physics selection can modify the actual desired movement command.

CONFIRMED FROM SOURCE: Facing/look direction enters through command fields such as `desiredLookAt`. `_MovementCommand` creates a look direction based on the manual movement direction blended toward a short ball prediction; `_BallControlCommand` sets `desiredLookAt` from player position plus current movement plus desired direction.

CONFIRMED FROM SOURCE: Sprint input is preserved as a high desired velocity and also participates in knock-on when sprint and dribble buttons are both pressed.

## Possession Flow

CONFIRMED FROM SOURCE: `Player::UpdatePossessionStats` scans ball predictions up to `ballPredictionSize_ms = 3000` and finds earliest reachable samples. Prediction samples are normally 10 ms apart, with an optimization that can skip ahead before refinement.

CONFIRMED FROM SOURCE: For each predicted ball sample with height below `1.5`, it calls `AI_GetTimeNeededForDistance_ms(GetPosition(), GetMovement(), ball.Predict(ms).Get2D(), GetMaxVelocity(), precise, ms, debug)`.

CONFIRMED FROM SOURCE: `precise` is true for the team's designated possession player. That means the designated player gets the more expensive/refined time-to-ball estimate.

CONFIRMED FROM SOURCE: If an active touch animation has a pending touch, possession time can be reduced to the remaining animation touch time: `(touchFrame - currentFrame) * 10`.

CONFIRMED FROM SOURCE: If the resulting time-to-ball is under `defaultTouchOffset_ms`, it is remapped from the distance between the player projected by `defaultTouchOffset_ms` and the ball predicted at `defaultTouchOffset_ms`.

CONFIRMED FROM SOURCE: `AI_HasPossession` is strict close possession:

- Rejects if player is more than `5.0` from `ball->Predict(0)`.
- Rejects if current ball height is above `0.5`.
- Uses radius `1.0` around `player position + player movement * 0.05 + player direction * 0.1`.
- Rejects if the current predicted ball position is outside that radius.
- Computes ball movement from `Predict(10) - Predict(0)` multiplied by `100`.
- Rejects if that ball movement differs from player movement by more than `6.0`.

CONFIRMED FROM SOURCE: Team possession is aggregate. `Team::UpdatePossessionStats` updates active players, sets team possession true if any active player has possession, and stores the minimum player time-to-ball.

CONFIRMED FROM SOURCE: Team designated possession player switches in `Team::Process` only when the best player is meaningfully better. It compares `(bestPlayerTime + 500) / (designatedPlayerTime + 500)`, biases the rating for actual possession and human control, and switches when the rating is below `0.8`.

CONFIRMED FROM SOURCE: Match best possession team is the lower team time-to-ball unless a ball retainer exists. Equal times become no best team.

CONFIRMED FROM SOURCE: Match designated possession player switches to the best team's designated player only if `(candidateTime + 10) / (designatedTime + 10) < 0.85`. If a ball retainer exists, the retainer becomes designated possession.

INFERENCE: The minimal basic dribble loop needs close possession, time-to-ball, designated possession continuity, and last touch. It does not need full team tactics, off-ball strategy, keepers, retainers, or automatic player switching for the first Beyond 90 prototype.

## Time-To-Ball

CONFIRMED FROM SOURCE: `AI_GetTimeNeededForDistance_ms` is not raw distance divided by max speed.

CONFIRMED FROM SOURCE: Important algorithm inputs:

- current player position
- current player movement vector
- target predicted ball position
- max player velocity
- `precise`
- optional maximum time being tested

CONFIRMED FROM SOURCE: For far targets, it uses an optimized estimate:

`distance(targetPos, playerPos + playerMovement * 0.2) / (maxVelocity * 0.75) * 1000`

and subtracts `200` ms for optimistic time.

CONFIRMED FROM SOURCE: For nearer/precise targets, it simulates a 700 ms movement-change horizon in 10 ms steps. The current movement fades out over `changeTime_ms = 700`, reach radii grow from `0.28` usual and `0.9` optimistic, and effective max velocity is `maxVelocity * 0.94`.

CONFIRMED FROM SOURCE: It offsets the current position by a small front-foot amount. If the player is moving above `idleDribbleSwitch`, it offsets in movement direction by `0.1` and adds current movement for `0.01`; otherwise it offsets toward the target.

CONFIRMED FROM SOURCE: Outputs are `usual_ms` and `optimistic_ms`.

INFERENCE: GameplayFootball distinguishes "the ball is currently away" from "the player can reach it by the relevant future sample" by scanning predicted ball positions and comparing each sample time against estimated reach time.

## Ball-Control Movement Assistance

CONFIRMED FROM SOURCE: `PlayerController::_MovementCommand` calls `AI_GetBallControlMovement` only in the branch where the player is treated as "the man of the moment" and `hasBestPossession` is true.

CONFIRMED FROM SOURCE: That branch applies to human-controlled players as well as AI players. For the direct `hasBestPossession` case, `autoBias` is set to `1.0`.

CONFIRMED FROM SOURCE: `AI_GetBallControlMovement` uses:

- `desiredTimeToBall_ms = 250 + defaultTouchOffset_ms`
- `defaultTouchOffset_ms = 80`
- effective ball control prediction target = `330 ms`
- `toBallMovement = mentalImage->GetBallPrediction(330).Get2D() - player->GetPosition()`
- `toBallDistance = length(toBallMovement)`

CONFIRMED FROM SOURCE: Automatic direction is toward the predicted ball. Manual direction inside this function is the player's current direction vector, not the raw desired direction.

CONFIRMED FROM SOURCE: Close-distance blending exists:

- `manualDirectionStartDistanceThreshold = 0.2`
- `manualDirectionEndDistanceThreshold = 0.4`
- default `autoDirectionBias = 1.0`
- if `toBallDistance < 0.4`, auto bias is `NormalizedClamp(toBallDistance, 0.2, 0.4)^0.5`
- below/near the start threshold, current/manual direction dominates to avoid artifacts

CONFIRMED FROM SOURCE: Desired velocity from assistance is initially `toBallDistance * distanceToVelocityMultiplier`, with `distanceToVelocityMultiplier = 2.6`.

CONFIRMED FROM SOURCE: If that speed is at least `dribbleVelocity`, it clamps the manual desired velocity into `[bestVelocity, bestVelocity + 8]`, then softly quantizes toward range velocity.

CONFIRMED FROM SOURCE: `AI_GetBallControlMovement` returns `player->GetTimeNeededToGetToBall_ms`, not the internally selected `330` ms.

INFERENCE: The movement-assist goal is to move the player toward the predicted next useful ball-contact area before the touch, while avoiding jitter when the ball is already extremely close.

## AutoBias

CONFIRMED FROM SOURCE: `_MovementCommand` initializes `autoBias = 0`.

CONFIRMED FROM SOURCE: `autoBias` becomes `1.0` for the direct `hasBestPossession` branch after calling `AI_GetBallControlMovement`.

CONFIRMED FROM SOURCE: `autoBias` also becomes `1.0` when `forceMagnet` is true. For humans, `forceMagnet` becomes true when a pressure button is held or while an action buffer exists.

CONFIRMED FROM SOURCE: Non-designated but plausible human cases can get partial assistance. If the player is not the match designated possession player but has last-touch bias, possession amount, same-direction factor, switch bias, and no opponent team possession, `autoBias` is computed from those factors and clamped.

CONFIRMED FROM SOURCE: If the input direction points toward the player's own half, the partial human magnet is reduced by `1.0 - inputDirIsOwnHalfFactor`.

INFERENCE: The full `autoBias = 1.0` path is football-contact assistance for the player most expected to control the ball. The partial cases mix football-contact assistance with player-switching and recovery logic. For Beyond 90 4.4B, the direct best-possession assist is the relevant baseline.

## Manual / Automatic Movement Blending

CONFIRMED FROM SOURCE: Final movement blending in `_MovementCommand` is:

`resultingMovement = manualMovement * (1 - autoBias) + autoMovement * autoBias`

Then:

- direction = normalized resulting movement, falling back to quantized input direction
- velocity = clamped movement length in `[idleVelocity, sprintVelocity]`
- if velocity is below `idleDribbleSwitch`, direction becomes `autoLookDirection`
- look-at is player position plus auto look direction multiplied by `10`

CONFIRMED FROM SOURCE: When `hasBestPossession` is true, `autoBias = 1.0`, so the final movement command comes fully from ball-control movement assistance.

INFERENCE: GameplayFootball preserves human agency mainly upstream: human input controls desired velocity mode and commands, but while the player is the expected controller, the actual locomotion direction can be strongly corrected toward the predicted ball-contact point.

## Player Agency Boundary

FOOTBALL-CONTACT ASSISTANCE - CONFIRMED FROM SOURCE:

- Moving the player toward a predicted ball contact point.
- Adjusting movement speed to arrive at the predicted ball.
- Adjusting look direction toward ball/control focus.
- Blending or fully replacing locomotion with contact-directed movement when the player is the best possession actor.
- Limiting sudden sprint turn direction through sticky run direction and animation selection.

AI TACTICAL DECISION-MAKING - CONFIRMED FROM SOURCE:

- AI dribble target selection such as `AI_GetBestDribbleMovement`.
- Off-ball defending/positioning strategies.
- Pass target choice.
- Shot direction selection.
- Team pressure and tactical shape decisions.
- Automatic selected-player switching.

RECOMMENDATION: Beyond 90 should port football-contact assistance closely enough to recreate the contact cycle, but must not port AI tactical decisions for human players. If the user aims forward-right, assist may bias the avatar slightly toward the next reachable contact. It may not decide forward is tactically better than backward or choose a pass/shot/route.

## Action And Animation Selection

CONFIRMED FROM SOURCE: `HumanController::RequestCommand` queues `_BallControlCommand` and `_TrapCommand` in normal open play before the movement command.

CONFIRMED FROM SOURCE: `_BallControlCommand` returns early if `ball.Predict(200)` is farther than `ballDistanceOptimizeThreshold`, or if a ball retainer exists.

CONFIRMED FROM SOURCE: If the player lacks close possession and lacks last-ditch permission, `_BallControlCommand` rejects attempts when vertical ball movement is too high or ball/player relative movement is too large.

CONFIRMED FROM SOURCE: A `BallControl` command is queued only if:

- the player is `match->GetDesignatedPossessionPlayer()`, or
- the player is `team->GetDesignatedTeamPossessionPlayer()` and `CouldWinABallDuelLikeliness() >= 0.25`

CONFIRMED FROM SOURCE: The command uses `inputDirection`, optional quantization, `inputVelocityFloat`, optional knock-on modifier, and `desiredLookAt`.

CONFIRMED FROM SOURCE: For sprinting with existing possession, sticky run direction limits sharp changes. If desired direction differs from current direction by more than `0.125*pi` but less than `0.7*pi`, the desired direction is clamped to a `0.125*pi` rotation from current direction.

CONFIRMED FROM SOURCE: `Humanoid::Process` asks the player controller for a command queue, then calls `SelectAnim` for each command until one is applicable.

CONFIRMED FROM SOURCE: `SelectAnim` builds a crude animation query by function type, incoming velocity, body direction, look-at side, incoming ball direction for trap/deflect/interfere, and other filters.

CONFIRMED FROM SOURCE: For `e_FunctionType_BallControl`, it keeps best body-direction animations and best direction animations; last-ditch relaxes strictness.

CONFIRMED FROM SOURCE: If the command is `BallControl`, `NeedTouch` decides whether an actual touch animation is needed. If not needed, no new ball-control animation is selected.

INFERENCE: Normal dribble is a feedback loop between movement animation, ball-control animation selection, and touch plausibility. A touch is requested only when geometry/velocity makes it useful.

## Touch Planning

CONFIRMED FROM SOURCE: Touch planning begins during `SelectAnim`, before the actual touch. `GetBestCheatableAnimID` evaluates candidate animation touch frames against predicted ball positions.

CONFIRMED FROM SOURCE: Candidate evaluation uses `animTouchFrame * 10` as the relevant ball prediction time. It compares the predicted ball position and movement against animation touch point/movement, body position, front-foot offset, and ball height.

CONFIRMED FROM SOURCE: The selected current animation stores:

- `touchFrame`
- `touchPos`
- `fullActionSmuggle`
- `actionSmuggle`
- `rotationSmuggle`
- `incomingMovement`
- `outgoingMovement`
- `originatingCommand`

CONFIRMED FROM SOURCE: `CalculateMovementSmuggle` can compute extra movement during eligible possession animations so the player reaches the predicted contact. It is allowed only when the player is both team and match designated possession player, no touch is already pending, the match is in play, no set piece, and no ball retainer.

INFERENCE: GameplayFootball plans both sides of the contact: where the player/body/foot should be at contact and what the ball should do after contact.

## Touch Timing

CONFIRMED FROM SOURCE: `FootballAnimationExtension` stores football touch keyframes by animation frame. `GetFirstTouch`, `GetTouch`, and `GetTouchPos` return touch position/frame metadata.

CONFIRMED FROM SOURCE: `Humanoid::Process` performs an authoritative touch only when `currentAnim->touchFrame == currentAnim->frameNum`.

CONFIRMED FROM SOURCE: At the touch frame it:

- gets desired animation touch position with `GetTouchPos`
- uses `touchableDistance = 0.4`
- computes full ball distance from current ball prediction to `currentAnim->touchPos + currentAnim->positionOffset`
- allows special retain states to force distance to valid
- computes `bumpyRideBias = fullBallDistance / touchableDistance`, clamped and curved
- requires full ball distance under `touchableDistance`
- requires ball height within `1.0` of desired ball height

CONFIRMED FROM SOURCE: This prevents uncontrolled repeated touches every update because a normal touch is tied to a specific animation frame. Requeue gates also prevent constantly replacing ball-control animations.

CONFIRMED FROM SOURCE: `NeedTouch` prevents idle control from touching every time when ball/player movement already match. It requires a touch if desired velocity is above idle-dribble threshold, ball speed is above `2.0`, outgoing angle is significant, distance deviation is at least `2.0`, velocity deviation is outside `[-1.4, 0.7)`, or moving direction dot is below `0.975`.

RECOMMENDATION: Beyond 90 4.4B should use temporary logical touch windows that mimic this semantic: planned future contact becomes valid only when player/ball geometry and timing line up. It should not be "touch every X seconds regardless of geometry."

## GetBallControlVector

CONFIRMED FROM SOURCE: `GetBallControlVector` computes the desired post-contact ball momentum vector.

CONFIRMED FROM SOURCE: Major inputs:

- current ball prediction and movement
- player possession state
- next player start position/angle/body angle
- outgoing animation movement
- originating command desired direction/velocity
- current controller velocity
- front-of-foot offset
- player technical stats
- closest opponent distance
- ball height
- current animation frame and effective frame count

CONFIRMED FROM SOURCE: `physicsBias` starts at `0.7`. If the player lacks possession it becomes `0.9`. If the outgoing animation velocity is idle it becomes `1.0`.

CONFIRMED FROM SOURCE: The desired movement vector uses originating command desired direction and a blend of originating desired velocity and current controller velocity:

`desiredMovement = desiredDirection * (desiredVelocity * 0.7 + controllerVelocity * 0.3)`

CONFIRMED FROM SOURCE: Sprint desired movement is stretched to the player's max velocity using `StretchSprintTo` rather than blindly using global sprint speed.

CONFIRMED FROM SOURCE: Desired velocity is clamped between outgoing animation movement speed and outgoing speed plus an overdrive allowance. Overdrive is zero under `dribbleWalkSwitch`, about `0.6` normally, and up to `1.2` for sprint desire, then reduced by alignment dot factors.

CONFIRMED FROM SOURCE: `GetFrontOfFootOffsetRel` computes a front-foot offset:

- distance = `0.34 + velocity * defaultTouchOffset_ms * 0.001`
- mostly forward relative to body, with some body-angle contribution
- reduced for higher ball height

CONFIRMED FROM SOURCE: Planned ball positions:

- `desiredPlannedBallPos = nextStartPos + desiredMovement * desiredDelayTime + FFO`
- `physicsPlannedBallPos = nextStartPos + physicsMovement * physicsDelayTime + FFO`
- delay time is `NormalizedClamp(velocity, 0, sprintVelocity)^2 * 0.60 + 0.25`
- `plannedBallPos = physicsPlannedBallPos * physicsBias + desiredPlannedBallPos * (1 - physicsBias)`

CONFIRMED FROM SOURCE: Time-to-go includes remaining animation time, blended delay time, and `defaultTouchOffset_ms`:

`timeToGo = remainingAnimTime + blendedDelayTime + defaultTouchOffset_ms * 0.001`

CONFIRMED FROM SOURCE: It computes `toPlannedBall = plannedBallPos - ball->Predict(0).Get2D()`, then:

- divisor = `timeToGo * (0.38 + 0.02 * technical_dribble) * 1.1`
- power = `(length(toPlannedBall) / divisor)^0.7`
- direction = normalized `toPlannedBall`
- height = clamped `0.1 + 1.5 * (power / 10)^1.6`
- power multiplier increases slightly at high velocities and is reduced by `technical_ballcontrol`
- returned touch vector = `direction * power * powerMultiplier + Vector3(0,0,height)`

CONFIRMED FROM SOURCE: It also computes rotation values from a blend of FFO direction and touch vector direction, with backspin.

FOOTBALL LOGIC: Planned post-contact ball location, delay-based ball travel, front-foot offset, desired/physics movement blend, outgoing velocity as a direct outcome.

ANIMATION-SPECIFIC: next start position, next body angle, outgoing animation velocity/movement, effective frame count, touch frame, smuggle offsets.

ENGINE-SPECIFIC: C++ vector math, custom rotation and prediction model, stats-driven power/rotation, exact meters/second values.

4.4B ACTION: PORT CLOSELY for the conceptual algorithm. ADAPT the inputs because Beyond 90 lacks final football animations and uses Roblox Humanoids.

## GetTrapVector

CONFIRMED FROM SOURCE: `GetTrapVector` starts from `GetBallControlVector`, then blends it with current ball movement using difficulty factors.

CONFIRMED FROM SOURCE: `GetDifficultyFactors` increases difficulty from:

- player/body position offset
- relative player-ball movement
- ball being farther from player/body
- recent opponent touch bias
- player technical ball-control skill

CONFIRMED FROM SOURCE: Trap can preserve current ball movement through `ballMovementFactor`, and add vertical response through `heightFactor`.

RECOMMENDATION: For 4.4B, defer a full trap system. Normal control should borrow the idea that poor contact may preserve existing ball momentum, but full first-touch/trap behavior should be a later milestone.

## Ball::Touch Semantics

CONFIRMED FROM SOURCE: `Ball::Touch(const Vector3 &target)` calls `SetMomentum(target)`.

CONFIRMED FROM SOURCE: `SetMomentum(target)` replaces `momentum` with `target`. It does not add the target to current momentum.

CONFIRMED FROM SOURCE: `Ball::Touch` then recalculates prediction, updates latest mental-image ball predictions, and updates both teams' possession stats.

CONFIRMED FROM SOURCE: Ball rotation is not changed inside `Ball::Touch`; touch handlers call `SetRotation` separately after `Touch`.

CONFIRMED FROM SOURCE: After touch, the ball remains independent. `Ball::Process` continues physical simulation from the new momentum.

INFERENCE: The important semantic distinction is: GameplayFootball contact establishes desired post-contact momentum. It is not an extra force layered on top of current momentum.

## Ball Prediction During Dribbling

CONFIRMED FROM SOURCE: Full ball prediction is `ballPredictionSize_ms = 3000`, sampled every 10 ms.

CONFIRMED FROM SOURCE: Dribble-cycle consumers and times include:

| Consumer | Prediction Time | Purpose |
| --- | ---: | --- |
| `PlayerController::_MovementCommand` default look | 40 ms | Look/focus toward ball while moving |
| `AI_GetBallControlMovement` | `250 + defaultTouchOffset_ms` = 330 ms | Move player toward next useful control contact |
| `_BallControlCommand` optimization | 200 ms | Do not queue ball control if ball too far |
| `SelectAnim` optimization | 200 ms and `defaultTouchOffset_ms` | Reject impossible action if ball is too far or moving away |
| `GetBestCheatableAnimID` | `animTouchFrame * 10` | Match selected animation contact to predicted ball position |
| `NeedTouch` | 240/250 ms | Compare ball movement against current/anim movement |
| `CalculateMovementSmuggle` | max(animation time + 80 ms, time-to-ball) | Move body toward plausible contact |
| `Player::UpdatePossessionStats` | multiple samples 0-3000 ms | Find earliest reachable ball sample |

RECOMMENDATION: Beyond 90 4.4B does not need a 3000 ms prediction array. It needs minimum prediction for:

- near look/contact assistance, roughly 40-330 ms equivalent
- planned logical touch frame/time
- short post-touch expected next-contact planning
- possession/time-to-ball over a short competitive window

## Post-Touch Prediction / Possession Update

CONFIRMED FROM SOURCE: Immediately after `Ball::Touch`, GameplayFootball recalculates ball prediction and refreshes the latest mental image's ball predictions.

CONFIRMED FROM SOURCE: It then calls `UpdatePossessionStats` for both teams. Match-level designated possession is refreshed in the process loop after team possession stats and best team are recalculated.

INFERENCE: The touch result is immediately fed back into the next control cycle. This matters more than any one fixed threshold.

## Walking Behavior

CONFIRMED FROM SOURCE: Human walk input maps to `walkVelocity = 5.0`. Dribble button maps to `dribbleVelocity = 3.5`.

CONFIRMED FROM SOURCE: `GetBallControlVector` at lower velocities has little or no overdrive, and planned delay time is lower because it depends on normalized velocity squared.

INFERENCE: Walking/dribble control should produce closer, lower-risk planned touches because desired/physics velocities are lower, front-foot offset is smaller, and delay time is shorter.

## Sprinting Behavior

CONFIRMED FROM SOURCE: Human sprint input maps to `sprintVelocity = 8.0`.

CONFIRMED FROM SOURCE: Sprint desired movement can receive larger overdrive, but it is alignment-limited and stretched to player max velocity.

CONFIRMED FROM SOURCE: `_BallControlCommand` sticky run direction limits sharp sprint steering when the player has possession, has best possession, desired velocity is above `walkSprintSwitch`, and current velocity is above `dribbleWalkSwitch`.

CONFIRMED FROM SOURCE: Holding Dribble plus Sprint adds a knock-on modifier. At touch, BallControl/Trap touch vector is multiplied by `1.35`.

INFERENCE: Normal sprint dribbling does not require knock-on; knock-on is a modifier for stronger touches. Sprint dribbling still uses ordinary BallControl, movement assistance, animation selection, and touch-vector planning.

## Turning Behavior

CONFIRMED FROM SOURCE: Turning is constrained by several systems:

- Human input direction can change, but movement command may be quantized.
- Sticky sprint control limits certain direction changes to `0.125*pi` from current direction.
- Animation selection filters by desired direction, body direction, incoming/outgoing movement.
- `CalculateBiasForFastCornering` and animation difficulty make high-speed turns harder.
- Ball redirection occurs through the next physical touch vector, not by rotating the ball trajectory every frame.

INFERENCE: A 90-degree turn should preserve ball momentum until a valid later contact redirects it. A 180-degree reversal may fail to produce a valid control touch if movement/animation/contact geometry cannot support it.

## Stopping Behavior

CONFIRMED FROM SOURCE: No-input below deadzone produces idle velocity and current facing direction.

CONFIRMED FROM SOURCE: `NeedTouch` avoids idle touches when the candidate idle outgoing animation, current movement, and ball movement already match sufficiently.

CONFIRMED FROM SOURCE: If the ball is still moving more than `2.0`, or deviations are large, a touch can still be required.

INFERENCE: Stopping does not mean continuous magnetism. If the ball settles compatibly, no touch is needed. If momentum carries the ball away or mismatch grows, action selection may seek a control/trap touch or possession may be lost.

## Knock-On Relationship

CONFIRMED FROM SOURCE: Human knock-on is enabled when Dribble and Sprint buttons are both held. `_BallControlCommand` and `_TrapCommand` receive the `knockOn` flag and set `e_PlayerCommandModifier_KnockOn`.

CONFIRMED FROM SOURCE: At the BallControl or Trap touch, the computed touch vector is multiplied by `1.35`.

RECOMMENDATION: Knock-on is OPTIONAL for 4.4B. It is useful, but straight walking dribble and ordinary sprint dribble should be implemented first. Add knock-on after the base contact cycle works.

## Football Logic vs AI Logic

FOOTBALL LOGIC - PORT/ADAPT:

- close possession based on ball near player and moving compatibly
- time-to-ball over predicted ball samples
- designated controller with hysteresis
- ball-contact movement assistance
- auto/manual movement blending for contact
- planned touch windows
- desired post-contact ball momentum
- prediction refresh after touch

AI LOGIC - OMIT/DEFER FOR HUMANS:

- tactical dribble route choice
- AI pass/shot target decisions
- force-field team movement
- defensive/off-ball strategies
- automatic team pressure behavior
- automatic selected-player switching

## Football Logic vs Animation-Specific Logic

FOOTBALL LOGIC:

- touch must be planned before contact
- touch happens at a specific time/contact window
- touch is valid only if the ball is near the planned contact point
- outgoing ball momentum is calculated from desired future ball state

ANIMATION-SPECIFIC:

- animation-authored touch frames
- animation touch positions
- animation quadrants
- body-part touch type
- movement/rotation/action smuggle
- animation difficulty and candidate filtering

RECOMMENDATION: 4.4B should create a logical touch abstraction that can later be synchronized to Roblox animation markers. It should not wait for final animations.

## Football Logic vs Engine-Specific Logic

FOOTBALL LOGIC:

- ball is independent between touches
- contact establishes post-contact momentum
- prediction informs movement and action selection
- possession updates after momentum changes

ENGINE-SPECIFIC:

- custom C++ ball physics and prediction
- fixed 10 ms prediction array
- custom humanoid animation system
- mental images and reaction-time histories
- player stat formulas

RECOMMENDATION: Beyond 90 should not recreate the C++ engine. It should create small Roblox-native equivalents for prediction, contact timing, and post-contact velocity.

## GameplayFootball -> Beyond 90 Behavioral Port Matrix

| Item | GameplayFootball Behavior | Source File / Symbol | Beyond 90 Current Equivalent | 4.4B Action |
| --- | --- | --- | --- | --- |
| Human movement input | HID direction plus velocity mode from buttons | `HumanController::_GetHidInput` | Roblox Humanoid input plus sprint remote | ADAPT |
| Close possession | Ball within 1 m-ish moving with player | `AI_HasPossession` | `Controlled` active controller plus acquisition radius | PORT CLOSELY |
| Time-to-ball | Predicted sample scan with usual/optimistic times | `AI_GetTimeNeededForDistance_ms`, `Player::UpdatePossessionStats` | Lightweight 4.3.1 estimated time-to-ball | REPLACE with closer source relationship |
| Best possession | Team/player minimum time-to-ball | `Team::UpdatePossessionStats`, `Match::CalculateBestPossessionTeamID` | Candidate score by distance/dot | ADAPT |
| Designated possession | Hysteresis player selection | `Team::Process`, `Match::Process` | One active controller with score bonus | ADAPT |
| Control movement prediction | Ball at 330 ms | `AI_GetBallControlMovement` | 4.3.1 short/full endpoint retention | PORT CLOSELY |
| Movement assistance | Move player toward predicted ball | `AI_GetBallControlMovement`, `_MovementCommand` | None for avatar; ball impulses compensate | PORT CLOSELY, Roblox-bounded |
| AutoBias | Full for best possession; partial for recovery/switch cases | `_MovementCommand` | None | ADAPT |
| Manual/auto blending | Vector blend of movement commands | `_MovementCommand` | None | PORT CLOSELY for controller only |
| Look direction | Toward auto look/focus | `_MovementCommand`, `_BallControlCommand` | Roblox AutoRotate | ADAPT/DEFER |
| BallControl action | Queued only for designated/plausible players | `_BallControlCommand` | Server controlled state applies touch impulse | PORT CLOSELY |
| Touch planning | Animation contact matched to predicted ball | `SelectAnim`, `GetBestCheatableAnimID` | Fixed forward target | REPLACE |
| Touch timing | Specific animation touch frame | `Humanoid::Process`, `FootballAnimationExtension` | Timed interval | ADAPT with logical touch window |
| GetBallControlVector | Desired post-contact momentum to planned ball position | `humanoid_utils.cpp` | Delta impulse toward fixed target | PORT CLOSELY conceptually |
| Trap vector | Blend control vector with existing momentum by difficulty | `GetTrapVector` | None | DEFER, except bad-contact idea |
| Knock-on | Dribble+sprint modifier, 1.35x touch vector | `HumanController`, `Humanoid::Process` | Sprint stronger touch config | DEFER/OPTIONAL |
| Ball::Touch semantics | Replace momentum, recalc predictions and possession | `Ball::Touch`, `SetMomentum` | `ApplyImpulse` delta-like but target not source-derived | ADAPT |
| Ball prediction | 3000 ms / 10 ms array | `Ball::CalculatePrediction`, `Predict` | 2 endpoint estimates | ADAPT smaller |
| Possession update after touch | Recalculate teams after touch | `Ball::Touch` | Attributes/state update in loop | PORT CLOSELY |
| Loose-ball transition | Failed possession/designation/touch plausibility | multiple | Free state and release reasons | ADAPT |

## Roblox Unit / Scale Mapping

CONFIRMED FROM SOURCE: GameplayFootball uses meters-like units:

- default player height = `1.92`
- ball radius in prediction/collision code = `0.11`
- close possession radius = `1.0`
- dribble/walk/sprint speeds = `3.5 / 5.0 / 8.0`

CONFIRMED FROM SOURCE: Beyond 90 currently uses:

- `PlayerConfig.Movement.BaseSpeed = 16`
- `PlayerConfig.Movement.SprintSpeed = 23`
- `BallConfig.Radius = 1.4`
- pitch size = `180 x 110` studs

INFERENCE: Do not assume 1 meter equals 1 stud. Use ratios:

- GameplayFootball dribble/sprint ratio = `3.5 / 8.0 = 0.4375`.
- GameplayFootball walk/sprint ratio = `5.0 / 8.0 = 0.625`.
- Beyond 90 base/sprint ratio = `16 / 23 = 0.696`.
- GameplayFootball close possession radius/player height = `1.0 / 1.92 = 0.52`.
- GameplayFootball ball radius/player height = `0.11 / 1.92 = 0.057`.

RECOMMENDATION: For 4.4B, choose a Roblox-native scale from the actual Roblox character and ball, not raw meters. Derive contact radius, front-foot offset, and planned touch distances from avatar root/rig size plus ball radius. Preserve ratios and behavior, not exact units.

## Roblox Ball::Touch Equivalent

OPTION A: Set `ball.AssemblyLinearVelocity = desiredOutgoingVelocity`.

- Behavioral fidelity: closest to `SetMomentum` replacement.
- Roblox physics continuity: abrupt; may ignore current solver contact state.
- Server authority: simple.
- Maintainability: clear but can feel teleport-like in velocity space.

OPTION B: Apply impulse from delta velocity:

`deltaVelocity = desiredOutgoingVelocity - ball.AssemblyLinearVelocity`

`ball:ApplyImpulse(deltaVelocity * ball.AssemblyMass)`

- Behavioral fidelity: equivalent target if the solver applies it cleanly.
- Roblox physics continuity: better than arbitrary additive kicks because it is still a physical impulse.
- Server authority: fits current `SetNetworkOwner(nil)`.
- Maintainability: explicit "establish desired outgoing velocity" semantics.

OPTION C: Additive impulse/power without target velocity.

- Behavioral fidelity: poor for GameplayFootball control, because source `Ball::Touch` replaces momentum rather than adding momentum.

RECOMMENDATION: Use Option B for 4.4B. Treat the impulse as a velocity correction toward desired post-contact velocity, not as an extra kick. Clamp or validate the desired outgoing velocity before applying it.

## Roblox Networking Considerations

CONFIRMED FROM SOURCE: Beyond 90 currently keeps the football unanchored and server-owned with `SetNetworkOwner(nil)`. Milestone 4.4A does not change this.

INFERENCE: Server-only movement assistance would feel delayed because Roblox Humanoid input and visual movement are client-responsive by design.

INFERENCE: Client-only assistance would be exploitable if it directly decides possession or ball touch.

RECOMMENDATION: Use a small Option C architecture for 4.4B: client predicts bounded movement assistance for the local humanoid using replicated authoritative ball/controller state, while the server validates possession and performs authoritative ball touches. Do not give the client football ownership or authoritative touch power.

## Human Movement-Assist Architecture

RECOMMENDATION: Smallest 4.4B architecture:

1. Server `BallControlService` owns authoritative possession/controller, touch validation, desired outgoing ball velocity, and actual ball touch.
2. Client `MovementController` applies bounded contact movement assistance only for the local player when replicated ball state says that player is the current controller.
3. Shared config defines assist horizons, maximum assist angle, maximum assist strength, contact window timing, and velocity limits.
4. Replicated ball attributes expose minimal state: `State`, `ControllerUserId`, and maybe planned contact timing/target for debugging.
5. Server rechecks player/ball geometry at logical touch time before applying the ball velocity correction.

WHAT ASSIST MAY CHANGE:

- Slightly adjust humanoid movement direction toward the next contact point.
- Modulate speed to avoid overrunning or missing the ball.
- Prefer the predicted contact route when the player is the current expected controller.

WHAT ASSIST MAY NOT CHANGE:

- It may not choose tactical direction.
- It may not force a player forward when their input is backward.
- It may not pass, shoot, tackle, or choose targets.
- It may not authorize ball touch from the client.

## Existing Beyond 90 Logic To Keep

KEEP:

- Physical independent football.
- `Anchored = false`.
- `SetNetworkOwner(nil)` for the 4.4B prototype.
- Server authoritative ball touch.
- `Free` / `Controlled` public states.
- `LastReleaseReason` diagnostics.
- Ball reset safety.
- Basic free-ball interaction when not controlled.
- Strict initial acquisition, though conditions should be revised.
- Server-side lightweight arbitration.

ADAPT:

- `Controlled` should mean current expected contact-cycle player, not recoverability threshold holder.
- Player arbitration should begin moving from distance/dot score toward close possession plus time-to-ball/designated-controller continuity.
- Anti-overlap should remain as safety, not dribble propulsion.

## Existing Beyond 90 Logic To Replace

REPLACE:

- Recoverability as the primary dribble mechanism.
- Repeated impulse touches toward a fixed forward target.
- Relative-away-speed retention patches.
- Prediction-envelope retention as the center of control.
- Recent-touch continuity windows used mainly to prevent self-invalidation.
- Fixed walk/sprint target offsets as the core dribble plan.

REMOVE LATER:

- Any 4.3.1 code whose only purpose is to preserve `Controlled` during threshold failures once the contact-cycle model owns control.

DEFER:

- Full multi-player time-to-ball scan for all 22 players every frame.
- Full animation marker integration.
- Full trap/first-touch system.
- Knock-on.
- Client prediction/reconciliation for ball ownership.

## Proposed Beyond 90 Module Map

RECOMMENDATION:

1. Authoritative possession: `BallControlService`.
2. Close possession evaluation: `BallControlService`, using source-inspired close possession plus current controller continuity.
3. Next useful contact prediction: `BallControlService` on server; a shared/pure helper module may be introduced if this becomes too large.
4. Movement assistance calculation: shared helper, consumed by client `MovementController` for feel and by server for validation.
5. Movement assistance execution: client for local Humanoid responsiveness, bounded by server replicated state.
6. Human input blending: `MovementController`, based on raw local input and assist vector.
7. Desired outgoing ball velocity: `BallControlService`, using source-inspired `GetBallControlVector` logic.
8. Authoritative ball touch: `BallControlService`, via delta-velocity impulse.
9. Temporary logical touch cadence: `BallControlService`, with a future animation-ready contact window model.
10. Replication: ball attributes for `State`, `ControllerUserId`, debug contact/release data.
11. Client presentation: movement assist, later animation synchronization, local prediction visuals.

RESPONSIBILITIES TO REMOVE FROM CURRENT `BallControlService`:

- It should no longer be primarily a recoverability-threshold evaluator.
- It should no longer apply periodic fixed-target control impulses.

RESPONSIBILITIES TO KEEP IN `BallControlService`:

- Server state.
- Acquisition/arbitration.
- Hard invalid release.
- Ball touch authority.
- Diagnostics.

## Milestone 4.4B Implementation Plan

RECOMMENDATION: Smallest valuable 4.4B implementation:

1. Keep `Free` / `Controlled`.
2. Replace 4.3.1 controlled touch logic with a logical contact cycle.
3. Add a source-inspired close possession check: ball near the player and movement-compatible.
4. Add a short time-to-ball estimate for current controller and nearby challengers.
5. Add a planned contact point/time based on human input and short ball prediction.
6. Add bounded movement assistance for the current controller.
7. When the contact window is valid, compute desired outgoing ball velocity using a simplified `GetBallControlVector` relationship:
   - current ball position
   - player position/movement
   - human desired movement
   - planned next-contact delay
   - front-foot offset
   - walk/sprint speed mode
8. Apply a delta-velocity impulse to establish desired outgoing ball velocity.
9. Recalculate/refresh control state after the touch.
10. Test straight walking dribble first, then steering, stopping, and sprinting.

Do not include passing, shooting, tackling, full traps, skill moves, final animations, client ball ownership, or full match systems.

## Open Questions

- What assist strength feels acceptable with Roblox Humanoids while preserving player agency?
- Should 4.4B use direct `Humanoid:Move` replacement, camera-relative input correction, or a lower-level movement target abstraction?
- How much client-side movement assistance can be allowed before server touch validation diverges visually?
- What short prediction horizons best match Roblox ball friction and server ownership?
- How should the temporary logical touch window expose animation-ready events later?
- What Roblox scale should define "front of foot" for R15 avatars and the current ball radius?
- Should sprint control initially support knock-on, or wait until straight sprint dribble is stable?
- How much multi-player time-to-ball scanning is needed before tackling/duels exist?

