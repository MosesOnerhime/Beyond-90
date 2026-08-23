# GameplayFootball Assisted Passing Research

Reference clone: `temp/GameplayFootball/`

Commit: `68159a2f0f96eec8ebba26ab7820130f36b922a7`

The clone was reused, remains ignored and outside the Rojo runtime tree, and is
not a Beyond 90 dependency.

## CONFIRMED FROM SOURCE

- `AI_GetPass` in `src/onthepitch/AIsupport/AIfunctions.cpp` selects an active
  teammate rather than treating every short pass as anonymous space.
- Candidate evaluation compares the player's input direction with directions
  toward teammates.
- Its target estimate advances a receiver by receiver movement multiplied by
  an estimated pass duration.
- Its automatic pass-power path derives power from target distance and blends
  assisted direction/power with human input according to configured biases.
- Human-controller code calls the same pass calculation with separate short-
  pass and through-pass assistance settings.

## INFERENCE

The source demonstrates that assisted passing can preserve the player's broad
directional decision while automating low-level receiver selection, lead, and
power. It does not imply that a launched ball should home toward the receiver.

## USEFUL CONCEPT

- Treat approximate input direction as the strongest receiver-selection cue.
- Predict a moving receiver at expected arrival rather than targeting the
  current position only.
- Derive useful pass power from distance and desired arrival behavior.
- Keep the intended receiver explicit through the action pipeline.

## ROBLOX LIMITATION

GameplayFootball runs player selection, movement, animation contact, and ball
physics inside one native engine. Beyond 90 must split local preview and
presentation from server validation and replicated Roblox physics.

## BEYOND 90 ADAPTATION

`PassTargetPresentationController` provides a local-only preview. The client
sends the selected receiver ID, but `FootballActionService` rebuilds eligible
candidates and requires `PassPlanner` to validate that same receiver. The
server launches one physical trajectory and replicates receiver/arrival
metadata. `MovementController` then provides bounded reception assistance; it
never teleports the receiver or reserves possession.
