# Football Action Assistance

Beyond 90 football actions follow this rule:

```text
HUMAN CHOOSES ACTION
        ↓
HUMAN PROVIDES DIRECTION / INTENT
        ↓
GAME SELECTS / REFINES VALID TARGET
        ↓
GAME COMPUTES PLAUSIBLE EXECUTION
        ↓
PHYSICAL BALL IS RELEASED
        ↓
WORLD CAN INTERFERE
```

## Current 5.1 Scope

Implemented action foundations:

- Assisted Ground Pass
- Assisted Through Pass
- Manual Knock-On

These actions use the existing input abstraction and pass through server validation. They do not create a second movement, possession or ball physics system.

## Assistance Philosophy

Assistance helps execute the player's existing intent. It may:

- score valid receivers inside the player's intent cone
- predict a short receiver lead
- convert hold duration into usable power
- choose a physical launch velocity
- reject invalid or implausible requests

Assistance must not:

- choose tactically unrelated receivers
- guarantee completion
- home the ball after release
- ignore defenders or physical obstruction
- decide whether the human should pass or shoot

## Physical Release

After a validated action:

- controlled possession is released
- the real football becomes free
- the server owns the football
- a single initial launch velocity is applied
- existing acquisition rules determine the next controller

This keeps passes and Knock-On actions interceptable.

## Receiving And First Touch

Milestone 5.2 adds the receiving side of the same philosophy:

- the ball remains physical after release
- any eligible player may reach the ball first
- the server validates low-ball reachability and controllability
- the first touch uses bounded physical velocity correction
- the new controller then receives normal controlled-ball ownership

The intended receiver from a pass is context, not a reservation. A defender or
teammate who reaches a controllable ball first may acquire it.

Current internal first-touch categories:

- `Settle`: slow or stationary reception into close control
- `TakeInStride`: moving reception that preserves forward momentum
- `Capture`: awkward but controllable incoming ball
- `Loose`: deferred/uncontrollable state where the ball remains Free

## Future Shooting Direction

Shooting is not implemented in 5.1.

Future assisted shooting should follow the same pattern:

- player chooses Shoot
- player supplies rough aim and strength
- the game assists goal target-zone selection and trajectory
- the shot remains a physical ball
- defenders, goalkeeper, posts and crossbar can affect the result

Assisted shooting must not mean guaranteed goals. Outcomes must include saves, blocks, misses, posts, crossbar impacts and deflections.

## Future Goal Metadata

The shooting milestone will likely need replicated goal metadata such as:

- `GoalBounds`
- `GoalMouthPlane`
- `LeftPost`
- `RightPost`
- `CrossbarHeight`
- `TargetZones`

Potential shot target zones:

- low left, low center, low right
- mid left, mid center, mid right
- high left, high center, high right

Goal metadata is deferred until the shooting/goal milestone.
