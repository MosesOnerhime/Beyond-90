# GameplayFootball Research: Milestone 5.3B

Reference clone: `temp/GameplayFootball/`

Commit: `68159a2f0f96eec8ebba26ab7820130f36b922a7`

Files inspected:

- `src/onthepitch/AIsupport/AIfunctions.cpp`
- `src/onthepitch/player/controller/playercontroller.cpp`
- `src/onthepitch/player/humanoid/humanoid.cpp`
- `src/utils/animation.cpp`

## Confirmed Source Behavior

GameplayFootball evaluates future ball positions and player reachability before
choosing a control target. Assisted pass targets include receiver movement, and
the high-pass branch uses a materially larger vertical component than ordinary
passes. Ball-control and trap commands are separate from the physical collision
path, while animation application interpolates adjacent pose data.

## Inference

A receiver should stabilize around one predicted contact transaction instead of
starting a new control transaction whenever network ownership changes. Facing
the incoming trajectory near contact is more stable than following a stale
launch target.

## Useful Concept

- predict a reachable contact point from the live ball state;
- preserve one reception identity through approach, touch, and possession;
- distinguish an intentional lob from incidental driven-pass lift;
- preload presentation before exposing active footballers.

## Roblox Limitation

Roblox animation replication, network ownership, Humanoid movement, and physical
ball integration are separate systems. GameplayFootball's node animation and
continuous prediction structures cannot be used directly, and Roblox asset
loading can finish after a character has replicated unless the reveal is staged.

## Beyond 90 Adaptation

Beyond 90 keeps a server PassId and reuses the established ControlEpoch when the
same receiver transiently reacquires the same pass. Reception facing locks from
the live incoming horizontal velocity near contact. Lob Pass uses the same
assisted receiver identity as Ground Pass but launches one physical, non-homing
ball with a clearly higher vertical velocity. The Training loader preloads the
central animation set before gameplay presentation becomes visible.
