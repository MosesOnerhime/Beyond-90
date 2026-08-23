# GameplayFootball Locomotion and Dribbling Research

Reference clone: `temp/GameplayFootball/`

Commit: `68159a2f0f96eec8ebba26ab7820130f36b922a7`

The clone was reused, remains Git-ignored, is outside the Rojo source tree, and
is not a runtime dependency.

## CONFIRMED FROM SOURCE

- `animcollection.cpp` classifies locomotion by velocity tier and movement
  angle, including forward, diagonal, lateral, and backward regions.
- The animation selection rules reject some implausibly sharp high-speed
  transitions rather than treating every directional change identically.
- `humanoid_utils.cpp` increases fast-cornering bias with movement angle and
  velocity, and plans ball control using both physical ball state and desired
  player movement.
- Ball-control planning places the ball farther ahead when the next expected
  contact is later; its desired delay grows with movement speed.
- `humanoid.cpp` coordinates an animation touch frame with a physical
  `Ball::Touch`, while evaluating predicted ball position against usable touch
  positions.

## INFERENCE

The source's directional bins and transition legality are a practical reason
that one forward clip cannot represent football locomotion cleanly. Its
speed-dependent contact planning also supports longer sprint excursions than
jog excursions.

## USEFUL CONCEPT

- Project movement relative to body orientation.
- Blend neighboring directional presentations.
- Require stronger evidence for sharp transitions at high speed.
- Treat dribbling as repeated physical push, separation, chase, and recontact.
- Plan relative player-ball lead, not only world-space ball travel.

## ROBLOX LIMITATION

GameplayFootball owns a C++ character, animation, and ball-contact pipeline.
Beyond 90 uses Roblox Humanoids, replicated physics, client network ownership,
and server-authoritative possession. Its engine-specific animation selection
and contact execution cannot be copied directly.

## BEYOND 90 ADAPTATION

A1 uses local velocity projection and reusable weighted `AnimationTrack`
sets, while existing Roblox movement remains authoritative. Sprint turn and
180-degree clips are presentation only. Physical controlled touches remain in
`ControlledBallController`; animation consumes touch/reception evidence after
gameplay has decided it.

