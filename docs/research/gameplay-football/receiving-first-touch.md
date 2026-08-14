# GameplayFootball Receiving And First-Touch Research

Repository URL: https://github.com/vi3itor/GameplayFootball.git

Branch: `master`

Commit SHA: `68159a2f0f96eec8ebba26ab7820130f36b922a7`

Research date: 2026-08-14

Relevant source files:

- `src/onthepitch/AIsupport/AIfunctions.cpp`
- `src/onthepitch/player/controller/playercontroller.cpp`
- `src/onthepitch/player/controller/humancontroller.cpp`
- `src/onthepitch/player/controller/elizacontroller.cpp`
- `src/onthepitch/player/humanoid/humanoid.cpp`
- `src/onthepitch/player/humanoid/humanoid_utils.cpp`
- `src/onthepitch/player/player.cpp`
- `src/onthepitch/match.cpp`

Relevant functions/classes/symbols:

- `AI_GetTimeNeededForDistance_ms`
- `AI_GetToBallMovement`
- `AI_GetBallControlMovement`
- `AI_HasPossession`
- `PlayerController::_BallControlCommand`
- `PlayerController::_TrapCommand`
- `GetDifficultyFactors`
- `GetBallControlVector`
- `GetTrapVector`
- `Humanoid::Process`
- `Player::Process`
- `Match::CheckBallCollisions`

## CONFIRMED FROM SOURCE

- GameplayFootball predicts ball positions into the future and evaluates whether a player can arrive at a useful ball state in time, rather than requiring raw body collision at the current frame.
- `AI_GetTimeNeededForDistance_ms` models reachability using current player position, current movement, maximum velocity, a growing reachable radius and separate usual/optimistic times.
- `AI_GetToBallMovement` samples predicted ball positions and chooses a reachable future ball target. It rates options by time, desired movement, perpendicularity to the ball path and prior target stability.
- Ball height is explicitly filtered when choosing reachable ball-control movement; high balls are skipped for normal low-control movement.
- `AI_GetBallControlMovement` uses a short future ball prediction and blends automatic movement toward the ball with manual/controller direction once the player is close.
- `AI_HasPossession` requires distance, low ball height and movement similarity between player and ball. Possession is not only a circular radius check.
- `PlayerController::_TrapCommand` is used for incoming moving balls when the player/team is a plausible receiver and the opponent is not clearly winning the ball.
- `GetDifficultyFactors` makes traps harder when player/ball relative movement is large, the ball is far from the body, or an opponent recently touched it.
- `GetTrapVector` builds on `GetBallControlVector` but preserves a configurable amount of current ball movement and may add extra vertical response for difficult balls.
- `GetBallControlVector` plans a future ball position farther ahead of the player at higher movement velocity, computes a touch vector toward that planned state, and includes vertical lift and rotation/backspin.
- `Match::CheckBallCollisions` separately handles physical body-ball deflections, but controlled reception/trapping is not left solely to raw collision.

## INFERENCE

- GameplayFootball treats receiving as player-ball cooperation: predict the ball, move to a controllable future state, then apply a trap/ball-control touch.
- Interception is naturally supported because the player who can reach/control the incoming ball first can become the possession candidate.
- First touch quality is not binary. Relative speed, distance from the body, height and recent opponent touch all influence whether the next touch cushions, carries, bounces or stays loose.

## BALL REACHABILITY

- PORT CLOSELY: use future/reachable state concepts instead of requiring perfect physics collision.
- ADAPT: Beyond 90 uses server-side lightweight thresholds and current Roblox positions/velocities instead of GameplayFootball's full mental-image prediction array.
- DEFER: full future sampling over many predicted ball frames is deferred until richer receiving/AI milestones need it.

## POSSESSION ACQUISITION

- PORT CONCEPTUALLY: possession should require proximity, low ball height, controllable speed and movement compatibility.
- ADAPT: Beyond 90 arbitrates eligible Roblox players on the server and grants network ownership only after validation.
- KEEP EXISTING: player-owned controlled-ball architecture remains active after acquisition.

## FIRST-TOUCH LOGIC

- PORT CONCEPTUALLY: distinguish close settle, moving control, awkward capture and loose/uncontrollable cases.
- ADAPT: 5.2 uses bounded velocity correction and first-touch classification instead of animation-selected trap/ballcontrol clips.
- DEFER: animation frame contact timing, skill/rating modifiers and high aerial traps.

## INTERCEPTION CONCEPTS

- KEEP EXISTING: passes remain physical and not homing after release.
- ADAPT: any eligible player can acquire an incoming free ball; intended receiver context is a bonus for diagnostics/planning, not a reservation.
- DEFER: full defender lane evaluation and tackling.

## AI-ONLY LOGIC

- AI tactical choice of who should chase, pass, defend or intercept is not part of 5.2.
- Team possession strategy and Eliza tactical decision code are future AI/team systems.

## ANIMATION-SPECIFIC LOGIC

- Trap and ball-control animation searches, touch frames and requeue rules are not ported into 5.2.
- Future Beyond 90 animations should consume semantic receive/first-touch events rather than become the competitive authority.

## ENGINE-SPECIFIC LOGIC

- GameplayFootball's custom physics, `MentalImage`, geometry nodes, AABB body collision and C++ animation engine are not ported directly.
- Raw meter constants are not copied into Roblox studs.

## ROBLOX CONSIDERATIONS

- Roblox avatar collision is too coarse to be the sole receiving interface.
- Server must remain authoritative for possession assignment.
- Client-owned controlled-ball physics begins only after server grants possession.
- Ball visual and collider size should match closely so reception/contact reads correctly.

## BEYOND 90 PROPOSAL

- ADAPT: create `ReceptionPlanner` to evaluate low free-ball controllability and first-touch output.
- ADAPT: update `BallControlService` to arbitrate free-ball acquisition every heartbeat.
- ADAPT: use first-touch types `Settle`, `TakeInStride` and `Capture`; leave excessive/high cases Free.
- KEEP EXISTING: `ControlledBallController` handles normal dribbling after acquisition.
- REPLACE: old free-ball basic touch no longer substitutes for possession acquisition.
- DEFER: high-ball receiving, headers, chest control, custom animation timing, player ratings and tactical AI.
