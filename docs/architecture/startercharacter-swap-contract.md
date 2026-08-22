# Beyond 90 StarterCharacter Swap Contract

This document defines the lightweight development contract for replacing the
test `StarterCharacter` during animation and character-proportion experiments.

The character model is visual/gameplay presentation only. Beyond 90 systems
remain responsible for movement, camera, ball control, possession, football
actions, and networking.

## Required Model Contract

A development `StarterCharacter` should:

- be a `Model` named `StarterCharacter`;
- be placed under `StarterPlayer`;
- contain a `Humanoid`;
- contain a `HumanoidRootPart`;
- use an R15-compatible body structure;
- include valid R15 `Motor6D` joints;
- include compatible R15 rig attachments;
- support an `Animator` under the `Humanoid` at runtime.
- have unanchored runtime body parts, especially `HumanoidRootPart`.
- have a valid `Humanoid.HipHeight` and foot-ground relationship on a flat
  pitch after centralized scaling.
- omit bundled/default `Animate` scripts unless they are explicitly being kept
  only as an inspectable reference outside the active player character.

The model should not require:

- its own movement system;
- its own ball system;
- its own camera system;
- its own possession system;
- its own football-action scripts;
- remote events or network authority;
- package scripts unrelated to character presentation.
- third-party or inaccessible animation asset IDs.

## Current Development Scale

The current accepted development target is approximately `8.27` studs. The
source of truth is:

```text
PlayerConfig.Appearance.DevelopmentFootballerTargetHeightStuds
```

`CharacterAppearanceService` may scale the spawned character model to the
target height using `Model:ScaleTo`. Do not manually resize individual limbs for
normal character experiments.

Grounding is also centralized under:

```text
PlayerConfig.Appearance.Grounding
```

Future character swaps must validate the neutral `Humanoid.HipHeight` and
foot-ground clearance after scaling. A single idle-frame measurement is not
enough: inspect Idle and at least one forward Jog loop so animation foot
trajectory does not hide pitch penetration.

The current A0.5 flat-pitch target is a small visual sole clearance of `0.18`
studs. This value was selected after sampling the Jog cycle, because lower
static clearances still allowed visible penetration during foot travel.
Grounding may apply one bounded HipHeight calibration after spawn settle and
one bounded late correction, followed by validation only. Do not introduce
per-frame vertical correction, mesh offsets, limb resizing, or foot IK for this
baseline.

## Swap Procedure

1. Save or duplicate the current `StarterCharacter` before replacing it.
2. Import the new character model outside runtime source folders.
3. Remove unrelated package scripts and effects.
4. Remove default or bundled `Animate` scripts from the active character path.
5. Verify `Humanoid` and `HumanoidRootPart`.
6. Verify R15-compatible body parts, attachments, and `Motor6D` joints.
7. Ensure imported character parts are not intentionally anchored.
8. Rename the model to `StarterCharacter`.
9. Place it under `StarterPlayer`.
10. Ensure only one `StarterCharacter` exists.
11. Keep development scaling centralized in `PlayerConfig`.
12. Verify measured height, `Humanoid.HipHeight`, both foot bottoms, and target
    foot clearance against the pitch ground surface.
13. Test custom animation loading.
14. Sample Idle and forward Jog grounding over multiple frames.
15. Test movement and sprint.
16. Test Broadcast and Third Person cameras.
17. Test possession and controlled dribbling.
18. Test passing and reception.
19. Test reset and respawn.
20. Test multiplayer visibility when practical.
21. Revert to the previous saved character if compatibility is unacceptable.

## Animation Authority

`AnimationController` owns custom Idle and Jog presentation. The active player
character should not depend on Roblox's default `Animate` script or bundled
third-party animation IDs.

Current owned prototype assets:

```text
B90_LOC_OffBall_Idle: rbxassetid://100655709305107
B90_LOC_OffBall_Jog_F: rbxassetid://107084636256080
```

Missing custom states such as Sprint, Jump, Fall, and Ball Jog use neutral
fallback presentation until Beyond 90-owned clips are authored. Do not stretch
the jog clip into sprint or add character-specific joint correction hacks.

Future possession jog work should add:

```text
B90_LOC_Ball_Jog_F
```

to `AnimationConfig.Assets.Locomotion.Ball.JogForward`. Until then,
`BallJogPlaceholder` is allowed to use the off-ball jog clip for visual testing
only.

The future possession jog should be authored as a football dribble posture:

- shorter stride than off-ball jog;
- slightly lower center of gravity;
- compact arm movement;
- ball-aware body posture;
- foot available for small controlled contacts;
- visible rhythm of step, contact, ball separation, and recovery.

The gameplay football remains physical and authoritative. Do not export a fake
gameplay ball as part of character animation.
