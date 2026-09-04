# GameplayFootball AI — team shape, formation adaptation and free space

Research for Milestone 6.7 §4, continuing from
`01-perception-reachability-movement.md`. This document records what the source
actually does, what is inferred from it, and what is proposed for Beyond 90. It
does not authorise a refactor on its own (`AGENTS.md` §19).

## Provenance

| | |
| --- | --- |
| Repository | `https://github.com/vi3itor/GameplayFootball.git` |
| Branch | `windows` |
| Commit | `1dc1518abd0ffaa349c7e1a53ded6ba19213c73f` |
| Date researched | 2026-08-31 |
| Clone location | `/d/repos/GameplayFootball` (outside the Beyond 90 runtime tree, per `AGENTS.md` §27) |

### Files inspected

| File | Lines | Read |
| --- | --- | --- |
| `src/onthepitch/AIsupport/AIfunctions.cpp` | 1299 | `AI_GetAdaptedFormationPosition` (72-181), `AI_CalculateFreeSpace` (302-331), `AI_GetOffsideLine` (333-) |
| `src/onthepitch/teamAIcontroller.cpp` | 1042 | `GetAdaptedFormationPosition` (293-429), `CalculateDynamicRoles` (430-528) |
| `src/onthepitch/player/controller/strategies/offtheball/default_mid.cpp` | 59 | in full |
| `src/onthepitch/player/controller/strategies/offtheball/default_def.cpp` | 51 | in full |
| `src/onthepitch/player/controller/strategies/offtheball/default_off.cpp` | 71 | in full |

### Symbols

`AI_GetAdaptedFormationPosition`, `AI_CalculateFreeSpace`, `AI_GetOffsideLine`,
`TeamAIController::GetAdaptedFormationPosition`,
`TeamAIController::CalculateDynamicRoles`, `TeamAIController::ApplyOffsideTrap`,
`DefaultMidfieldStrategy::RequestInput`, `possessionBias`, `microFocus`,
`midfieldFocus`, `staticPositionBias`.

### Licence

Apache-2.0 (`LICENSE`), with per-file notices from the original author
("written by bastiaan konings schuiling 2008 - 2015"). Several files, including
the strategy sources, additionally declare themselves public domain. No source
is copied into Beyond 90; what follows are behavioural findings and Beyond 90
proposals expressed in Beyond 90's own terms.

---

## 1. The central finding: shape is a shared box, not per-player drift

**CONFIRMED FROM SOURCE.** GameplayFootball does not let each footballer decide
independently how far to drift from its anchor. The team computes **one bounding
box** per evaluation, and every player's normalised formation coordinate is
mapped into that box (`AIfunctions.cpp:99-103`):

```
xLength   = frontXBound - backXBound
position.x = backXBound + (position.x * 0.5 + 0.5) * xLength
yLength   = highYBound - lowYBound
position.y = lowYBound  + (position.y * -side * 0.5 + 0.5) * yLength
```

The box is built in `TeamAIController::GetAdaptedFormationPosition`
(`teamAIcontroller.cpp:355-377`) from a possession-weighted centre plus an
adapted depth and width:

```
adaptedDepth = depth * (offense_depthFactor * possessionBias
                      + defense_depthFactor * (1 - possessionBias))
backXBound   = centerX - adaptedDepth * pitchHalfW * -side
frontXBound  = centerX + adaptedDepth * pitchHalfW * -side
```

**INTERPRETATION.** This is why a GameplayFootball team compresses and slides as
a unit. Relative shape is preserved *by construction*: the formation coordinates
never change, only the box they are painted into. Compression and expansion of
the block are a single scalar each (depth, width) rather than an emergent
average of eleven independent decisions.

## 2. Possession is a continuous bias, not a state

**CONFIRMED FROM SOURCE** (`teamAIcontroller.cpp:329-339`). `possessionBias`
blends two signals, and — the interesting part — weights the second by how
*unclear* the first is:

```
possessionAmountBias = normalise(fadingTeamPossessionAmount - 0.5, 0.3, 0.7)
ballBias             = normalise((ballX / pitchHalfW) * -side, -0.7, 0.7)
ballBiasBias         = (1 - |possessionAmountBias * 2 - 1|) * 0.6
possessionBias       = possessionAmountBias * (1 - ballBiasBias)
                     + ballBias * ballBiasBias
```

The source comments this directly: *"if possessionBias is unclear (near 0.5),
take ballBias more seriously as indicator of possession"*, and caps
`ballBiasBias` at 0.6 so *"defenders somewhat keep watch when possession team is
unclear, even when the ball is forward"*.

`possessionBias` then drives essentially every other quantity — depth, width,
own-half offset, side-focus strength, micro-focus strength, midfield focus.

**INTERPRETATION.** A single continuous scalar drives the whole shape, so a
turnover slides the block rather than snapping it. Contested possession lands
mid-scale instead of forcing a binary choice.

## 3. Focus terms: three different ways the ball pulls the shape

**CONFIRMED FROM SOURCE.** Applied in order after the box mapping.

**yFocus** (`AIfunctions.cpp:113-121`) — lateral shift toward the ball's Y.
The bias falls off with distance from the ball's line *and* is scaled by how far
the ball is from the centre (`0.2 + 0.8 * |yFocus| / pitchHalfH`), so a ball in
the middle barely shifts anyone.

**midfieldFocus** (`AIfunctions.cpp:85-96`) — stretches the midfield forward or
back *without moving defenders or attackers*, via a stretch bias keyed on how
central the player's own formation X is:

```
stretchBias = clamp(1 - |position.x * 1.2|, 0, 1)   -- 1 for midfield, 0 for the lines
```

The `1.2` overstretch is commented as deliberately leaving defenders and
attackers alone, since their coordinates are rarely exactly ±1.

**microFocus** (`AIfunctions.cpp:127-178`) — the pull toward the actual action.
Distance to the focus is measured from the player's *pure* formation position,
not its live position, and Y is de-weighted (`homogeneousYInfluenceBias = 0.2`)
so *"players are more strictly keeping to their positions"*. The bias is then
shaped to be near-binary:

```
microFocusBias = curve(1 - dist, 0.3)      -- "more of a binary choice to come
                                           --  over completely or not at all"
microFocusBias += (1 - normalise(|dist - 0.15|, 0, 0.25)) * 0.1   -- short-range peak
```

**INTERPRETATION.** The near-binary curve is the notable choice. Rather than
every footballer drifting slightly ballward — which would collapse the shape
uniformly — a few commit to the action and the rest hold. That is what keeps the
block legible while still contesting the ball.

## 4. Free space is measured against *predicted* opponents

**CONFIRMED FROM SOURCE** (`AIfunctions.cpp:302-331`). `AI_CalculateFreeSpace`
does not measure current opponent distance. For each opponent it:

1. advances the opponent by `movement * 0.2` ("slowness");
2. adds a sprint toward the focus point for `futureTime - 0.2` seconds, clamped
   so it cannot overshoot the focus;
3. accumulates `1 - clamp(distance, 0, safeDistance) / safeDistance`;
4. returns `1 - normalise(total, 0, 2.5)`.

**INTERPRETATION.** Two details matter. The `2.5` denominator means space is
judged "gone" at roughly two and a half opponents' worth of pressure, not one —
a single nearby defender degrades a spot without eliminating it. And because
opponents are advanced *toward the focus*, the rating answers "will this space
still exist when the ball arrives", not "is it empty now".

Called from `player.cpp:569,575` for `forwardSpaceRating` and `spaceRating`,
with `safeDistance = 5.0` and `ignoreKeeper = true`.

## 5. Slot assignment is an optimal matching, not nearest-wins

**CONFIRMED FROM SOURCE** (`teamAIcontroller.cpp:430-528`). Dynamic roles are
computed with the **Hungarian algorithm** (vendored `libhungarian`, Cyrill
Stachniss 2004) over an 11×11 player-to-slot cost matrix, cost being distance
from the player's position *extrapolated by half a second of movement* to each
adapted formation position. Costs above a progressively relaxed cap are set to
50000 to forbid absurd swaps; the loop retries with a looser cap.

Off-ball strategies then blend the static and dynamic slot by distance to the
action (`default_mid.cpp:24-26`):

```
actionDistance     = normalise(distance to ball carrier, 15, 20)
staticPositionBias = curve(0.9 * actionDistance, 1)
desiredPosition    = static * bias + dynamic * (1 - bias)
```

**INTERPRETATION.** Role swapping is allowed *near the action*, where a defender
stepping into a vacated midfield slot is correct football, and suppressed far
from it, where it would just churn the shape.

## 6. The off-ball pipeline

**CONFIRMED FROM SOURCE** (`default_mid.cpp`, `default_def.cpp`,
`default_off.cpp` — same skeleton, different weights):

```
static/dynamic formation blend
        ↓  + support position (force field), weighted by attackBias
        ↓  + defensive component, weighted by (1.5 - mindset - possession)
        ↓  + offside trap clamp
        ↓
direction = normalise(desired - position)
velocity  = distance * distanceToVelocityMultiplier, then "laziness", clamped
```

Velocity is purely proportional to remaining distance. There is no arrival
easing beyond that and no separate "walk/jog/sprint" decision.

---

## Beyond 90 mapping and decisions

Beyond 90's `getFormationTarget` (`src/server/Services/AIService.luau:197`)
currently gives every footballer an independent drift: its own anchor, shifted by
ball position scaled by a per-position `HoldShape`, then a discrete
`InPossession` / `OutOfPossession` adjustment, then a per-position clamp.

| # | Behaviour | Decision | Reasoning |
| --- | --- | --- | --- |
| 1 | Shared team box; formation coordinates mapped into it | **ADAPT** | The single biggest structural difference. Beyond 90's independent per-player drift lets shape distort — low-`HoldShape` positions drift while high ones hold, opening gaps no one decided to open. A shared box makes compression a team property. Adapt rather than port: Beyond 90 has its own pitch frame and `LongitudinalScale`/`WidthScale` already. |
| 2 | Continuous `possessionBias` | **ADAPT** | Replaces the discrete team-state branch. Worth taking including the "biasception" idea — weighting ball position more when possession is unclear is exactly the contested case Beyond 90 handles worst today. |
| 3 | `midfieldFocus` stretch keyed on `1 - \|x * 1.2\|` | **ADAPT** | Cheap, and it solves a real problem: stretching the block without dragging the defensive line. Beyond 90's per-position `MaximumRetreat`/`MaximumAdvance` clamps overlap with this and should stay as the hard bound. |
| 4 | `microFocus` near-binary commit curve | **ADAPT** | Beyond 90 already has `refineOffBallTarget` and `solveForceField` from doc 01; the missing piece is that commitment should be near-binary rather than a uniform drift. Fold into the existing refinement rather than adding a parallel term. |
| 5 | `AI_CalculateFreeSpace` opponent prediction + 2.5 denominator | **ADAPT** | Beyond 90's `rateSituation`/`getNearestOpponentDistance` measure current positions only. Advancing opponents toward the focus before rating is the part worth having. |
| 6 | Hungarian slot assignment | **DEFER** | Genuinely elegant and cheap at n=11 (~O(n³) ≈ 1300 ops, run at tactical frequency). But it only pays off once positional rotation matters, which is 5.9 / 6.1 territory. Beyond 90 has no slot-swap mechanism to feed it yet. Revisit with match-format scaling. |
| 7 | Static/dynamic blend by distance to action | **DEFER** | Depends on #6 existing. |
| 8 | `velocity = distance * multiplier` with no arrival easing | **KEEP EXISTING** | Beyond 90's `resolveMovementSpeed` already does better — it has arrival behaviour and a sprint decision. GameplayFootball's version is cruder; adopting it would regress movement quality. |
| 9 | "Laziness" velocity damping | **OMIT** | A stamina/personality stand-in from a single-machine game. Beyond 90 has a real server-authoritative stamina model (§49); a second, hidden damping term would fight it. |
| 10 | Offside trap via `backXBound` clamp | **KEEP EXISTING** | Beyond 90's `clampTargetForOffside` already covers this, and the source itself flags its placement as unreliable ("maybe setting offside trap this way doesn't work too well"). |

### Roblox constraints

- The box computation is per-team, not per-player, so it belongs in the team
  update (`updateTeams`) at tactical frequency, not in each footballer's
  movement tick. `AGENTS.md` §53 asks exactly this layering.
- GameplayFootball works in a normalised pitch space with `pitchHalfW` /
  `pitchHalfH` constants. Beyond 90 has real stud dimensions from
  `pitchState`; ratios transfer, absolute constants do not (`AGENTS.md` §27).
- `side` in GameplayFootball is ±1 along X. Beyond 90 already has
  `getAxes(teamId)` returning an attack direction and lateral axis, which is the
  equivalent and is handedness-safe.

### Not researched here

`elizacontroller.cpp` (1147 lines) — the individual decision loop — and
`goalie_default.cpp` (286 lines) remain unread. The goalkeeper strategy is the
obvious next target if §1.6 (keeper collision) is ever reproduced.
