# GameplayFootball Passing Research

Repository URL: https://github.com/vi3itor/GameplayFootball.git

Branch: `master`

Commit SHA: `68159a2f0f96eec8ebba26ab7820130f36b922a7`

Research date: 2026-08-14

Relevant source files:

- `src/gamedefines.hpp`
- `src/onthepitch/player/controller/humancontroller.cpp`
- `src/onthepitch/AIsupport/AIfunctions.cpp`
- `src/onthepitch/player/controller/elizacontroller.cpp`
- `src/onthepitch/player/humanoid/humanoid.cpp`
- `src/onthepitch/player/humanoid/humanoid_utils.cpp`

## CONFIRMED FROM SOURCE

- `gamedefines.hpp` defines separate function types for short pass, long pass, high pass and shot. It also defines `TouchInfo`, which carries input direction, input power, auto direction bias, auto power bias, desired direction, desired power, target player and optional forced target player.
- Human pass input is buffered in `HumanController::Process`. Short pass, long/through pass and high pass each convert hold duration into `inputPower` with a curve, then call `AI_GetPass`.
- Default assistance values are separate per pass type: short pass uses stronger auto direction than through pass, while both short and through pass use substantial auto power.
- Keyboard input is treated as a full-auto direction/power case inside `AI_GetPass`.
- `AI_GetPass` builds a manual target from player position, input direction and input power, then selects an automatic target among active teammates unless a forced target is supplied.
- `AI_GetPass` predicts receiver movement for a short pass duration. For long/through pass behavior it offsets the target farther in the attacking direction by a fraction of target distance.
- Direction and power are blended between the manual target and automatic target using the configured auto-direction and auto-power biases.
- At the pass contact moment, `Humanoid::Process` may recompute/refine pass direction and power. If the refined direction is within a limited angular deviation it is accepted; otherwise it is clamped or the original direction is retained.
- Pass execution ultimately applies one physical ball touch vector. The ball is not continuously homed toward the receiver after release.
- AI pass evaluation includes pass odds and opponent lane danger, but that is tactical AI decision logic, not required for human low-level pass execution.

## INFERENCE

- GameplayFootball treats passing assistance as target and initial-touch assistance. It assists the selected direction/power before contact and at contact, but the ball remains a physical result after the touch.
- Through balls are represented by a stronger lead/offset into attacking space, not by a separate homing behavior.
- The human player chooses pass type and rough direction; assistance resolves the playable target and practical power.

## USEFUL FOOTBALL LOGIC

- Keep the action-specific distinction between ground pass and through pass.
- Preserve the manual-target plus assisted-target blend concept.
- Predict receiver movement over a bounded short horizon.
- Lock or refine the selected target near action commit/contact, then release a physical ball.
- Use action hold duration as intent, but clamp and assist power so short passes stay usable.

## AI-ONLY LOGIC

- Eliza tactical pass choice, panic passing, teammate situation ratings and pass odds are AI decision-making. Beyond 90 5.1 does not port those choices for human players.
- Opponent danger scoring is useful future work, but a full lane evaluator is deferred until passing has more real players and receiving/interception behavior.

## ENGINE-SPECIFIC LOGIC

- C++ animation selection, touch frames, animation smuggling, and custom physics node architecture are not portable to Roblox directly.
- Raw meter constants and animation-driven power limits are not copied as Roblox constants.

## ROBLOX CONSIDERATIONS

- Beyond 90 must validate pass release on the server.
- Player-owned controlled-ball physics must transition cleanly to server-owned free-ball physics on pass release.
- Development pass targets are needed before full teams/AI exist.
- Assistance should not select unrelated targets outside the player's input cone.

## BEYOND 90 PROPOSAL

- ADAPT: `TouchInfo` maps to semantic client action payloads with action type, aim direction and hold duration.
- ADAPT: `AI_GetPass` maps to `PassPlanner`, which scores eligible receivers, predicts bounded receiver movement, computes target point and launch velocity.
- PORT CONCEPTUALLY: through pass uses extra lead into space ahead of the receiver.
- KEEP EXISTING: possession and network ownership remain in `BallControlService`.
- REPLACE: GameplayFootball animation contact timing is replaced for 5.1 by immediate server-validated physical release.
- DEFER: full receiving, first touch, defender lane scoring, tactical AI pass choice and shooting.

