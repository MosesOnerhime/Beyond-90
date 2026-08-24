# GameplayFootball Research: Milestone 5.3

Reference clone: `temp/GameplayFootball/`

Commit: `68159a2f0f96eec8ebba26ab7820130f36b922a7`

Files inspected:

- `src/onthepitch/AIsupport/AIfunctions.cpp`
- `src/utils/animation.cpp`
- `tools/animator/src/animator.cpp`

## Confirmed Source Behavior

`AI_GetPass` builds an automatic target from a teammate's current position plus
their movement over an estimated pass duration. It scores candidate targets
against manual direction and distance, then blends assisted and manual target
direction/power. A forced target follows the same receiver-motion prediction.

`AI_GetAutoPass` derives power nonlinearly from target distance and adds a small
vertical direction component. Its high-pass branch increases the vertical
component and changes the power factor.

`AI_GetShotDirection` predicts a small amount of player movement, maps the
manual direction's deviation from the goal-center direction into a position
inside the goal width, and blends manual and assisted shot directions.

`Animation::Apply` interpolates adjacent keyframes and contains transition
smoothing based on prior node orientation/movement history. The animator tool
stores football contact data separately from ordinary skeletal keyframes.

## Inference

Receiver movement should influence the intended point before launch, but a
launched ball does not need target homing. A low vertical component on strong
passes can improve readability without turning every pass into a lob.

Animation continuity benefits from retaining prior pose/track state during a
transition. This does not imply GameplayFootball's node history implementation
maps directly to Roblox animation tracks.

## Useful Concept

- score player intent against eligible receiver movement;
- derive pass strength from travel distance rather than requiring exact manual
  power;
- assist the initial shot direction toward a safe goal-mouth target;
- keep contact metadata separate from possession and action legality;
- blend from existing presentation state rather than resetting the pose.

## Roblox Limitation

Roblox exposes `AnimationTrack` weights and markers rather than the source
engine's node-level animation application. Roblox ball travel is also affected
by assembly speed clamps, physical properties, contacts, and server ownership,
so GameplayFootball power constants cannot be copied.

## Beyond 90 Adaptation

Beyond 90 uses one receiver identity from client targeting through server
validation, predicts receiver motion, and launches one physical non-homing
ball. Distance-derived speed and low lift are calibrated in studs and validated
against actual `AssemblyLinearVelocity`. The former global ball speed cap of
`60 studs/s` was below planned long-pass speeds and invalidated ETA predictions;
the cap is now a safety ceiling above pass and shot launch ranges.

Shots resolve the Training attacking goal from input alignment, clamp targets
inside runtime goal bounds, and remain server-authoritative. Roblox track fades
and persistent loaded locomotion tracks provide transition behavior; the C++
animation engine is not ported.
