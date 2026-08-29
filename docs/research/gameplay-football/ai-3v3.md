# GameplayFootball AI Research: Beyond 90 3v3 Foundation

## Revision And Scope

- Repository: `https://github.com/vi3itor/GameplayFootball.git`
- Local research clone: `temp/GameplayFootball` (ignored, outside Rojo runtime mapping)
- Upstream branch: `master`
- Local checkout: detached `HEAD` pinned to the revision below
- Commit: `68159a2f0f96eec8ebba26ab7820130f36b922a7`
- Commit date: `2021-07-20T16:31:54+09:00`
- Date inspected: `2026-08-25`
- License: Apache License 2.0. The repository has a root `LICENSE` and no root `NOTICE` file.
- Implication: source-derived distribution must retain the Apache license and applicable copyright/license notices, identify modifications, and preserve attribution notices. This milestone adapts football concepts and relationships into original Luau rather than copying the C++ engine architecture or source text.

## Exact Source Inspected

- `src/onthepitch/teamAIcontroller.cpp`
  - `TeamAIController::Process`
  - `TeamAIController::CalculateSituation`
  - `TeamAIController::GetAdaptedFormationPosition`
  - attacking-run and forward-support selection
  - pressure/designated possession selection
  - dynamic formation-role assignment and marking call chains
- `src/onthepitch/AIsupport/AIfunctions.cpp`
  - `AI_GetAdaptedFormationPosition`
  - `AI_CalculatePassingOdds`
  - `AI_GetPassRatings`
  - `AI_GetSituationRating`
  - `AI_CalculateFreeSpace`
  - `AI_GetTimeNeededForDistance_ms`
  - `AI_GetToBallMovement`
  - `AI_GetBallControlMovement`
  - `AI_GetBestDribbleMovement`
- `src/onthepitch/AIsupport/mentalimage.cpp`
  - `MentalImage::TakeSnapshot`
  - `MentalImage::GetPlayerImage`
  - `MentalImage::UpdateBallPredictions`
  - `MentalImage::GetBallPrediction`
- `src/onthepitch/AIsupport/mentalimage.hpp`
- `src/onthepitch/player/controller/playercontroller.cpp`
  - `PlayerController::Process`
  - `PlayerController::_Preprocess`
  - possession/time-to-ball state and defensive positioning
- `src/onthepitch/player/controller/elizacontroller.cpp`
  - off-ball strategy selection
  - force-field support movement
  - pass candidate tactical-improvement and lane scoring
  - shooting candidate/goal-lane evaluation
  - panic clearance behavior
- `src/onthepitch/player/controller/strategies/offtheball/default_def.cpp`
- `src/onthepitch/player/controller/strategies/offtheball/default_mid.cpp`
- `src/onthepitch/player/controller/strategies/offtheball/default_off.cpp`
- `LICENSE`

## Confirmed From Source

### Team reasoning and designated pressure

`CONFIRMED FROM SOURCE` `AI-SPECIFIC`: team AI calculates shared possession and time-to-ball context, then designates individual responsibility instead of sending every footballer directly to the ball.

`USEFUL CONCEPT`: a team-level layer owns possession state, pressure assignment, support/run assignment, and formation adaptation.

`BEYOND 90 DECISION` `PORT CLOSELY`: use one designated AI chaser/pressure player per team with time-to-ball hysteresis. Other footballers retain role shape.

### Time to ball and reachability

`CONFIRMED FROM SOURCE`: `AI_GetTimeNeededForDistance_ms` uses a near-distance acceleration simulation and a longer-distance velocity approximation. `AI_GetToBallMovement` tests future ball samples and chooses a reachable contact target, with previous-target bias to reduce oscillation.

`ENGINE-SPECIFIC`: GameplayFootball samples its own deterministic ball prediction array and player movement model in milliseconds.

`ROBLOX CONSIDERATION`: Roblox owns collision integration and Beyond 90 already has physical ball gravity, bounce, movement speeds, and server/client ownership boundaries.

`BEYOND 90 DECISION` `ADAPT`: sample future positions from Beyond 90 ball state and effective gravity, estimate travel using Beyond 90 speed/acceleration values, and retain the previous designated player inside a configurable hysteresis margin.

### Perception and reaction

`CONFIRMED FROM SOURCE`: each player controller requests a `MentalImage` at a reaction-time offset. Snapshots extrapolate movement but clamp deviation from current reality. Ball prediction is similarly bounded against current prediction.

`USEFUL CONCEPT`: AI decisions should consume refreshed snapshots at a controlled cadence and should not react with zero delay to every state change.

`BEYOND 90 DECISION` `ADAPT`: centralized perception interval, reaction delay, team tick, and individual tick. Low-level steering remains more frequent than tactical reasoning.

### Adapted formation

`CONFIRMED FROM SOURCE`: formation positions are not fixed world coordinates. They are transformed through tactical bounds and blended toward a team focal point and ball microfocus, with role/mindset-dependent influence.

`INFERENCE`: the important behavior for 3v3 is the relationship between role anchor, ball position, possession, and tactical bounds, not GameplayFootball's 11-player constants.

`BEYOND 90 DECISION` `ADAPT`: normalized Defender, Support, and Forward anchors are converted through the authoritative pitch axes. The whole team-relative coordinate frame rotates for HOME/AWAY. Ball and possession shift the anchors while role spacing remains visible.

### Off-ball support and attacking runs

`CONFIRMED FROM SOURCE`: off-ball strategies blend static/dynamic formation positions with support positions. A selected attacking-run player receives additional forward intent. Opponent and boundary force fields influence support space.

`BEYOND 90 DECISION` `ADAPT`: use formation-based support plus one forward run state and bounded opponent repulsion. Do not send all in-possession teammates straight toward goal.

### Passing decisions

`CONFIRMED FROM SOURCE`: pass candidates must improve tactical value over the carrier by a threshold. Passing odds account for sampled opponent obstruction, forward progression, receiver situation/free space, body direction, and pass type. The nearest or furthest teammate is not automatically selected.

`BEYOND 90 DECISION` `PORT CLOSELY`: candidate scoring combines lane viability, receiver space, forward progression, and distance, with an absolute threshold, improvement threshold, cooldown, and commitment. Existing `PassPlanner` remains the physical executor.

### Shooting and defensive clearance

`CONFIRMED FROM SOURCE`: shooting is gated by field position and lane odds, samples goal areas, and includes imperfection. Low-mindset defenders under pressure may clear rather than force a normal pass.

`BEYOND 90 DECISION` `ADAPT`: gate AI shots by distance/alignment/pressure and use configured shooting skill. In defensive pressure contexts use Beyond 90's existing clearance planner.

## Architecture Classification

### Keep Existing

- `KEEP EXISTING`: human `MovementController`, input, client prediction, and player-owned controlled-ball path.
- `KEEP EXISTING`: `BallService`, `GoalService`, score-by-crossed-goal logic, `PassPlanner`, `ShotPlanner`, and football action launch physics.
- `KEEP EXISTING`: current bounce configuration; this milestone verifies long-pass behavior before any retune.
- `KEEP EXISTING`: current animation asset registry.

### Port Closely

- `PORT CLOSELY`: designated chaser/pressure responsibility.
- `PORT CLOSELY`: pass tactical-improvement threshold and obstruction/space/progression scoring relationships.
- `PORT CLOSELY`: future-ball samples combined with time-to-reach estimates and selection hysteresis.

### Adapt

- `ADAPT`: `MentalImage` into interval-based server snapshots and delayed state commitment suitable for Roblox replication.
- `ADAPT`: formation adaptation to three normalized roles and the current pitch transform.
- `ADAPT`: force-field support into bounded opponent avoidance and pitch clamping.
- `ADAPT`: movement execution through Humanoid movement with Beyond 90 acceleration, deceleration, and speed limits.
- `ADAPT`: ball control through the existing Beyond 90 contact model, with server ownership for AI.

### Replace

- `REPLACE`: GameplayFootball engine vectors, match/player pointers, command queues, and custom physics calls with Roblox Instances, actor records, and existing Beyond 90 services.
- `REPLACE`: single-machine authority assumptions with explicit server-owned AI possession and existing client-owned human possession.

### Omit

- `OMIT`: fake Roblox `Player` objects for AI.
- `OMIT`: direct CFrame locomotion, teleport possession, privileged pass/shot physics, and perfect-reaction knowledge.
- `OMIT`: generic pitch pathfinding on the open football field.

### Defer

- `DEFER`: Hungarian dynamic role assignment; fixed 3v3 roles do not justify it yet.
- `DEFER`: goalkeepers, keeper AI, offside trap, set pieces, complete marking assignments, tackling, fouls, cards, and restart logic.
- `DEFER`: 5v5/7v7/11v11 formation constants and performance infrastructure beyond measured need.
- `DEFER`: difficulty UI and multiple AI profiles.

## Beyond 90 V1 Decision

The V1 implementation uses a lightweight server team model with `InPossession`, `OutOfPossession`, `LooseBall`, and `Transition`; a common human/AI actor record; one designated chaser or pressure AI; normalized role formations; paced individual decisions; server-owned AI controlled-ball simulation; and the existing pass, shot, clearance, bounce, goal, and score systems. Humans remain the source of their own tactical intent, and AI slots are removed as humans fill the 3v3 team.

---

# Milestone 6.1 Addendum — AI Possession Retention

Same repository/branch/commit as above (`68159a2f0f96eec8ebba26ab7820130f36b922a7`). Date inspected: `2026-08-26`.

## Additional Source Inspected

- `src/onthepitch/AIsupport/AIfunctions.cpp`
  - `AI_GetBallControlMovement`

## Confirmed From Source

`CONFIRMED FROM SOURCE`: while a footballer is controlling the ball, `AI_GetBallControlMovement` derives its movement velocity from the *ball relationship*, not from the tactical destination:

```text
toBallMovement  = ballPrediction(250ms + touchOffset) - playerPosition
toBallVelocity  = toBallDistance * distanceToVelocityMultiplier
bestVelocity    = clamp(desiredVelocity, toBallVelocity, toBallVelocity + 8.0)
```

`CONFIRMED FROM SOURCE`: the tactically desired velocity is admitted only up to a bounded margin above the ball-derived velocity. A carrier can therefore never accelerate arbitrarily far beyond what its own controlled football supports.

`CONFIRMED FROM SOURCE`: direction is blended toward the ball (`autoDirectionBias`) as the player closes on it, so contact geometry wins over tactical heading at short range.

## Beyond 90 Root Cause This Explains

Beyond 90's AI derived carry speed purely from the distance to its tactical target (a point ~24 studs toward goal), which selected sprint speed immediately after acquisition while the football was still travelling at first-touch speed. The relationship GameplayFootball enforces was absent, so the ball fell behind until `HardControlDistance` released possession.

A second, independent cause was Beyond 90-specific: `applyPlannedContact` was gated by `HandoffNoTouchDuration` (0.9s), which is harmless for humans because their client servo assumes control after ~0.13s, but left the server-simulated AI football with lateral-only correction for its entire first second of possession.

## Beyond 90 Decisions

`PORT CLOSELY`: bound AI carry speed by the current ball relationship with a small recovery margin (`AIConfig.Possession.CarryMaxSpeed`, `CarryLeadSlowStart/Full/MinScale`, `CarryRecoverySpeedBonus`). This is the `clamp(desired, ballDerived, ballDerived + margin)` relationship expressed in Beyond 90 units.

`ADAPT`: give the server an explicit AI controlled-ball servo (`BallControlService.applyAIPossessionControl`) using the existing `BallConfig.Control` carry-lead constants, so AI and human dribbling share one football model rather than two.

`ADAPT`: a short post-reception `Secure` state before tactical carry resumes. GameplayFootball achieves the equivalent through its continuous ball-relationship velocity clamp; Beyond 90 needs an explicit state because its AI tactical target is recomputed on a slower cadence.

`KEEP EXISTING`: `ReceptionPlanner` first-touch selection, `PassPlanner`, `ShotPlanner`, bounce/ground physics, goal and score logic.

`OMIT`: raising `HardControlDistance` to mask the symptom.
