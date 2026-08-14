# World Scale And Avatar

## Canonical Scale

Beyond 90 uses a canonical footballer height of 180 cm.

| Reference | Value |
| --- | ---: |
| Canonical player height | 1.80 m |
| Canonical player height | 6.00 studs |
| Studs per metre | 3.3333333333 |
| Metres per stud | 0.30 |

This is the gameplay scale used for player metrics, ball sizing, pitch planning,
goal sizing, and future animation authoring.

## Canonical Pitch Reference

The full-size design reference is:

| Reference | Metres | Studs |
| --- | ---: | ---: |
| Pitch length | 105.00 | 350.00 |
| Pitch width | 68.00 | 226.67 |

These values are design references for future full-size 11v11 stadiums and
environments. Match formats may still use smaller pitch dimensions.

## Canonical Goal Reference

The full-size goal reference is:

| Reference | Metres | Studs |
| --- | ---: | ---: |
| Goal width | 7.32 | 24.40 |
| Goal height | 2.44 | 8.13 |

## Current Stadium Development Exception

The imported development stadium remains aligned by
`Workspace.StadiumDevelopment.PitchBounds`.

The current `PitchBounds` is approximately 343 x 241 studs. Under the canonical
scale this is approximately 102.9 x 72.3 metres.

Beyond 90 should not resize the imported stadium automatically. Runtime
gameplay reads the existing `PitchBounds` transform and dimensions when it is
present; canonical pitch dimensions remain the reference for future stadiums.

## Standardized R15 Gameplay Profile

Competitive footballers are standardized as R15 gameplay characters.

On spawn, Beyond 90:

- reads the player's currently applied `HumanoidDescription`
- keeps player identity values that are safe for gameplay readability
- normalizes R15 scale/build/proportion values
- removes silhouette-changing accessories and layered clothing accessory slots
- removes user animation-pack overrides
- scales the body to the 6.0-stud canonical footballer height where runtime
  character scaling is available
- records canonical gameplay attributes on the character for diagnostics and
  future animation/contact systems

Identity preserved by default:

- body colours
- head and face compatibility
- face decal
- hair accessory
- face accessories, for eyebrow/eyelash style identity where practical
- classic clothing until the jersey system replaces it

Not preserved by default:

- hats
- back accessories
- front accessories
- neck, shoulder, waist accessories
- layered clothing accessory slots
- oversized silhouette-changing accessories
- user animation packs

For exact platform-level consistency, Studio Avatar Settings should also be set
to R15, Consistent Gameplay, and Custom Scale with a 6.0-stud absolute height
range. Runtime standardization is the project safety net; Avatar Settings is the
preferred global enforcement path for published places.

## Canonical Player Metrics

The current gameplay profile exposes:

- `CanonicalPlayerHeight = 6.0`
- `CanonicalBodyRadius = 1.0`
- `CanonicalFootContactHeight = 0.25`
- `CanonicalFootForwardOffset = 1.25`

Ball-control code should use player-relative coordinates and these stable
profile concepts instead of arbitrary avatar package dimensions.

## Physics Ball Versus Visual Ball

The authoritative football is a simple spherical physics collider.

`DevelopmentFootball` remains:

- unanchored
- physically simulated
- the authoritative football assembly root
- the network-ownership target
- the collision owner

The visual football is separate:

```text
DevelopmentFootball
    FootballVisual
```

`FootballVisual` is visual only:

- `Massless = true`
- `CanCollide = false`
- `CanTouch = false`
- `CanQuery = false`

It may be welded to the football collider. This weld is only inside the football
assembly and must never connect the football to a player.

The preferred asset path is:

```text
ReplicatedStorage.Assets.FootballVisual
```

If that asset exists and is a supported `MeshPart`, `BasePart`, or `Model`,
Beyond 90 clones and scales it to the configured visual diameter. If it is
missing, Beyond 90 uses a simple temporary fallback visual so gameplay can
continue.

## Future Body Compatibility

Future custom Furreal athletic footballer bodies should remain R15-compatible
and preserve the same gameplay scale. Animation authoring should target the
6.0-stud canonical body and player-relative foot/contact offsets documented
here.
