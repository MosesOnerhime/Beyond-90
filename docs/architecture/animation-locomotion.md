# Animation Locomotion

Beyond 90 locomotion animation is client-side presentation. Movement code
continues to translate and rotate the character; animation tracks never apply
root motion or authorize football state.

## Authority

The temporary development stack is:

```text
MovementController / ControlledBallController
        -> gameplay state and physical touches
AnimationController
        -> weighted visual presentation
Animator
        -> Beyond 90-owned assets
```

Roblox's default `Animate` script is disabled or absent. Missing animation
families use a neutral presentation rather than inaccessible bundled assets.

## Eight-Way Jog

`AnimationController` projects horizontal root velocity into the character's
local forward/right basis and computes `atan2(right, forward)`. The resulting
angle addresses eight 45-degree sectors:

- Forward
- ForwardRight
- Right
- BackRight
- Backward
- BackLeft
- Left
- ForwardLeft

The two tracks bordering the current angle receive linear target weights. Their
weights are exponentially smoothed and the dominant diagnostic direction uses
hysteresis. Tracks are loaded once per character and reused. The accepted
forward-jog baseline is a `1.05` playback multiplier at `14 studs/s`;
per-direction multipliers remain configurable.

Locomotion presentation enters from movement intent as well as physical speed.
This lets Idle begin blending to Jog during acceleration instead of leaving the
character frozen in Idle until it reaches full jog speed. Actual horizontal
velocity still drives playback rate and sprint gait selection.

## Sprint

Sprint presentation activates immediately from the existing sprint request and
meaningful movement intent.
Straight sprint uses `SprintForward`. The signed angle from smoothed movement
to raw desired movement selects `SprintTurnLeft` or `SprintTurnRight` only
after a meaningful turn threshold. Sprint tracks blend by weight and return to
Forward below the exit threshold. Gameplay sprint speed is `28 studs/s`.
A visual latch prevents transient velocity samples from switching back to Jog
while sprint remains requested. After sprint release, Sprint remains visible
during high-speed deceleration and blends to Jog below its exit speed.

## Possession Direction Changes

The dedicated `DirectionChange180` clip is intentionally removed. Without the
ball, directional movement remains responsive. With controlled possession,
`MovementController` stores major input changes as a pending direction while
the player indicator immediately shows intent. Physical direction commits at a
gameplay-controlled touch/recontact window, or after an angle- and gait-based
maximum wait. Animation markers never authorize the turn or ball touch.

## Action Overlay And Exit Resolution

Locomotion tracks remain loaded and continue resolving the desired base gait
while a full-body Action-priority track is active. Near an action's end, the
action weight fades out toward the current base locomotion. The resolver uses
current speed, movement intent, sprint request, possession, and facing rather
than restoring the gait that preceded the action.

This shared path is used by `ReceivePass`, `Pass`, `Shoot`, and `Jump`. It
prevents stale gait restoration and avoids empty-pose frames between an action
and locomotion.

## Jump

Jump input flows through the existing input and movement controllers. The
Humanoid performs the physical jump; a bounded character-only `VectorForce`
temporarily offsets part of gravity to target a football jump near `0.76`
seconds without changing `Workspace.Gravity`. `AnimationController` starts the visual
Jump action only after the Humanoid enters `Jumping` or `Freefall`. On landing,
the action fades into whatever locomotion is currently desired. Animation
never controls root height.

## Pass

Ground Pass and Through Pass begin a predicted local presentation on release so
the player does not wait for a server round trip. The existing server remains
authoritative for possession, target, and ball velocity. Acceptance does not
restart the animation, while rejection fades it out through the shared action
exit path. The Shoot asset is preloaded and presented immediately after local
intent. The server validates possession and goal geometry, prepares the shot,
and releases on a `BallContact` marker when present or a short configured
fallback when absent.

In A1.2, normal passes require a selected eligible teammate. Local selection
previews a candidate, while the server independently rebuilds the candidate
set and validates the requested receiver, range, direction, possession, and
cooldown. No candidate means no animation, no release, and no pass. Launch
strength is derived from planned distance and desired travel time; the ball is
not homed after launch and remains interceptable.

`MovementController` owns reusable `Pass` and `ReceivePass` action movement
profiles. They brake and briefly plant the physical character while action
tracks play, then restore input early instead of locking movement for the full
clip. Reception assistance uses replicated intended-receiver metadata and
blends a bounded approach toward the receive point with manual input. For a
free pass, the target is updated from current ball velocity and estimated
airborne landing time rather than relying only on launch-time data.

## Coming To Rest

Physical coast and visual locomotion exit are separate. Jog begins fading to
Idle or the temporary possession trap near `2 studs/s`, while movement finishes
its final bounded coast. Sprint remains visible until actual horizontal speed
falls below the sprint exit envelope, then blends through Jog rather than
forcing Jog at near-sprint velocity.

## Possession Locomotion

`BallJogPlaceholder` intentionally reuses the off-ball directional jog set.
The placeholder name remains visible in diagnostics so these clips are not
mistaken for finished dribbling locomotion. Future `Ball.Jog` assets can use
the same eight directional keys and weighted-track path without changing
movement or ball authority.

`ControlledBallController` owns the physical Push, Coast, Collect cycle and
fires its local dribble-touch event after a valid touch begins.
`AnimationController` may consume that event for presentation diagnostics,
but animation markers cannot create possession or physical touches.

## Reception

The server confirms reception and increments the ball's `ControlEpoch`.
`AnimationController` observes the replicated epoch, receiver user ID, and
action type. It plays `ReceivePass` only for a confirmed local Ground Pass or
Through Pass reception. Possession is never delayed for the animation, and the
track exits through the same dynamic locomotion resolver as other actions.

## Diagnostics

Development attributes expose locomotion family, dominant direction, local
forward/right components, movement angle, directional weights, sprint turn,
playback rate, placeholder state, controlled-ball lead, dribble phase, and
expected recontact time. Logs are emitted on state changes rather than every
frame.
