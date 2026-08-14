# GameplayFootball Camera Research

## Reference

Repository: https://github.com/vi3itor/GameplayFootball.git

Branch: master

Commit: 68159a2f0f96eec8ebba26ab7820130f36b922a7

Research date: 2026-08-14

The reference clone was inspected outside the Beyond 90 Rojo tree.

## Relevant Source

- `src/onthepitch/match.cpp`
  - `Match::UpdateIngameCamera`
  - `Match::PreparePutBuffers`
  - `Match::FetchPutBuffers`
  - `Match::Put`
- `src/gamedefines.hpp`
  - default camera user parameters

## License

The inspected GameplayFootball repository contains an Apache License 2.0 license file. Milestone 5.0D closely adapts camera-behavior mathematics and relationships from the wide-camera branch, not C++ engine architecture or source text.

## CONFIRMED FROM SOURCE

`Match::UpdateIngameCamera` builds the main camera focus from a strong possession-player contribution and a smaller ball contribution. The source uses a `playerBias` value of `0.6`, blends current ball prediction with `GetDesignatedPossessionPlayer()->GetPosition()`, then adds the possession player's facing direction.

The camera target also receives attacking-direction anticipation from fading team possession and team side.

The computed focus is clamped against pitch-relative maximum width and height extents before camera placement.

The source stores recent camera target samples in `camPos`, computes a weighted average, and uses that smoothed average for camera placement.

In the wide camera path, the camera node position is not fixed. It is derived from the smoothed target average in both horizontal axes, plus a configured broadcast offset and height. Rotation and FOV are then calculated as secondary presentation values.

Camera orientation, node orientation, node position, and FOV are written into buffers and later fetched for presentation. This separates simulation-side camera target calculation from rendered camera placement.

The reference also contains alternate birds-eye, tele, and scorer-camera paths, but the ordinary wide camera is the relevant model for Beyond 90's Broadcast Camera foundation.

In the wide-camera branch, `fov`, `zoom`, and `height` are derived from user camera parameters, then transformed into a wide broadcast relationship. The smoothed target average contributes to camera node translation on both horizontal axes. The final camera also applies a strong elevated Z/height offset, then computes camera rotation and FOV after node placement.

The source reduces vertical target influence before camera placement and treats the camera as a moving rig rather than a fixed sideline point.

The source uses target clamping proportional to pitch half-width and half-height before pushing samples into the smoothing buffer.

## INFERENCE

GameplayFootball's useful camera behavior is not a single fixed sideline tripod looking at the ball. It treats the camera as a moving rig whose physical world position follows the active play target.

The possession player is important enough to stabilize the framing, while the ball and attacking direction provide contextual influence. This maps well to Beyond 90 because the local human-controlled footballer should remain the primary anchor.

Across-pitch displacement affects camera position in the source. This is the key correction for Beyond 90's 5.0B issue where the player shrank when moving far from the camera and the camera relied too much on pitch/rotation.

## USEFUL CONCEPTS

- Build a broadcast target from controlled player, ball influence, and anticipation.
- Smooth the target before placing the camera.
- Move the camera's world position from the target, not only its rotation.
- Let both pitch axes influence physical camera translation.
- Treat FOV and rotation as framing refinement after the rig position is correct.

## ROBLOX CONSIDERATIONS

Roblox's `Workspace.CurrentCamera` can be controlled directly with `CameraType.Scriptable`, but the system must restore native camera behavior for testing modes.

Beyond 90's pitch can be rotated, so the camera must use replicated pitch metadata rather than world X/Z assumptions.

The camera must remain performant on RenderStepped: use cached character/ball/pitch references where practical and avoid scene scans.

## BEYOND 90 PROPOSAL

For 5.0C, keep the existing `CameraController`, `BroadcastCamera`, and `CameraConfig` architecture.

Update `BroadcastCamera` so the smoothed active-play target drives camera translation along both pitch length and pitch width axes. Keep controlled player as the primary anchor, use bounded ball influence, and use movement/attacking look-ahead for anticipation.

Add diagnostics for camera-player distance and approximate screen-space player height so near-side versus far-side scale consistency can be evaluated during playtests.

For 5.0D, preserve the same module architecture but translate the wide-camera relationships more directly into Roblox-native pitch axes:

- build a target from controlled player position, bounded ball influence, movement look-ahead, and attacking-direction look-ahead;
- clamp that target to pitch-relative extents;
- smooth target/focus and camera position separately;
- derive camera rig translation from the smoothed pitch-relative target along both length and width axes;
- keep FOV mostly stable during ordinary locomotion;
- solve near/far player scale primarily with physical camera translation;
- constrain the rig to a pitch-relative safe corridor so it does not enter stadium seating.
