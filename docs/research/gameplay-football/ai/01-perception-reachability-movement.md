# GameplayFootball AI — perception, reachability and off-ball movement

Research for Milestone 6.7 §4. This document records what the source actually
does, what is inferred from it, and what is proposed for Beyond 90. It does not
authorise a refactor on its own (`AGENTS.md` §19).

## Provenance

| | |
| --- | --- |
| Repository | `https://github.com/vi3itor/GameplayFootball.git` |
| Branch | `windows` |
| Commit | `1dc1518abd0ffaa349c7e1a53ded6ba19213c73f` |
| Commit subject | "Update Visual Studio build with CMake (#8)" |
| Date researched | 2026-08-31 |
| Clone location | `/d/repos/GameplayFootball` (outside the Beyond 90 runtime tree, per `AGENTS.md` §27) |

### Files inspected

| File | Lines | Read |
| --- | --- | --- |
| `src/onthepitch/AIsupport/mentalimage.hpp` | 47 | in full |
| `src/onthepitch/AIsupport/mentalimage.cpp` | 106 | in full |
| `src/onthepitch/AIsupport/AIfunctions.hpp` | 48 | in full |
| `src/onthepitch/AIsupport/AIfunctions.cpp` | 1299 | `AI_GetForceFieldMovement`, `AI_GetTimeNeededForDistance_ms` |
| `src/onthepitch/teamAIcontroller.cpp` | 1042 | not yet — see Not Yet Researched |

### Symbols

`MentalImage`, `MentalImage::TakeSnapshot`, `MentalImage::GetPlayerImage`,
`MentalImage::GetTeamPlayerImages`, `MentalImage::GetBallPrediction`,
`AI_GetForceFieldMovement`, `AI_GetTimeNeededForDistance_ms`, `TimeNeeded`,
`ForceSpot`, `PlayerImage`.

### Licence

The repository is licensed **Apache-2.0** (`LICENSE`). Individual source file
headers additionally carry the original author's notice:

> written by bastiaan konings schuiling 2008 - 2015
> this work is public domain. the code is undocumented, scruffy, untested, and
> should generally not be used for anything important.

Both are recorded because they disagree, and the more restrictive of the two —
Apache-2.0 — is the one Beyond 90 should comply with. Apache-2.0 requires
retained notices and a statement of changes for distributed derivative works.

Per `AGENTS.md` §27, rewriting C++ into Luau does **not** discharge these
obligations. Any Beyond 90 file that closely translates an algorithm below must
carry an attribution comment naming the repository, the commit and the function,
and must state that it is an adaptation rather than a copy.

**Nothing in this document has been translated into `src/` yet.** No attribution
notices are required until it is.

---

## 1. MentalImage — bounded, delayed perception

### CONFIRMED FROM SOURCE

`MentalImage` is a **snapshot of the world as the AI is allowed to see it**,
deliberately degraded from reality in three ways.

`TakeSnapshot()` copies, for every active player on both teams: team id, side,
player id, position, direction vector, body direction vector, velocity,
movement, formation entry and dynamic formation entry. It then calls
`UpdateBallPredictions()`, which fills `ballPredictions[ballPredictionSize_ms/10]`
from the ball's own prediction array.

Two constants set in the constructor bound the error:

```cpp
maxDistanceDeviation = 2.5f; // if reality is this much (or more) off from mental image, enforce as maximum offset
maxMovementDeviation = walkVelocity;
```

`GetPlayerImage(playerID)` does not return the snapshot verbatim. It:

1. extrapolates the stored position forward by `movement * timeStampNeg_ms * 0.001`;
2. clamps that result to within `maxDistanceDeviation` of the player's **real**
   position, via `EnforceMaximumDeviation`;
3. clamps the stored movement to within `maxMovementDeviation` of the real
   movement.

`GetTeamPlayerImages` applies the identical treatment per player.

`GetBallPrediction(time_ms)` indexes the precomputed array at
`(time_ms + timeStampNeg_ms) / 10`, clamped to the array end, then clamps the
result to `maxDistanceDeviation` of the ball's true `Predict(time_ms)`.

The source states the reason for that last clamp in its own comment:

> when a ball gets a wholly new movement, this prediction is obviously far off
> reality, while some variables are not, like the player->gettimeneededtogettoball,
> since that is based on non-delayed vars.

### INFERENCE

`timeStampNeg_ms` is a **reaction delay**: the AI reasons about a world that is
that many milliseconds stale, extrapolated forward by momentum. The deviation
clamps exist so a stale image can be wrong about *detail* but never absurdly
wrong about *where things are* — bounded error, not fog of war.

The author's comment implies the delayed and non-delayed systems are known to be
inconsistent with each other, and the clamp is a pragmatic patch rather than a
principled design. That is worth knowing before copying it wholesale.

### Beyond 90 mapping

Beyond 90 has **no equivalent**. `AIService` reads exact `RootPart.Position` and
`AssemblyLinearVelocity` every tick, and `rateSituation` / `choosePass` /
`DefendingService` all consume perfect, current values.

This is the specific gap `AGENTS.md` §49 names:

> Do not automatically give the AI perfect exploitation of every known value.
> The game engine may technically know exact states, but difficulty and fairness
> may require bounded reaction, awareness or prediction accuracy.

It is also the most plausible structural cause of two symptoms already observed
in playtesting: interceptions that felt superhuman before the §2 retune, and AI
that reacts to a pass on the frame it is struck.

### Decision: **ADAPT**

Port the *concept* — one shared, slightly stale, deviation-clamped snapshot that
all AI decisions read — not the class. Specifically:

- `PORT CLOSELY` the three-part rule: extrapolate by momentum, clamp position
  deviation, clamp movement deviation.
- `ADAPT` the storage: Beyond 90 already builds a per-tick team context; the
  snapshot belongs there rather than in a new object per AI.
- `OMIT` `ballPredictionSize_ms` fixed-array indexing. Beyond 90's ball
  prediction is a function call, not a precomputed 10ms table.
- `DEFER` per-difficulty `timeStampNeg_ms`. One honest reaction delay first;
  difficulty tiers once it is proven not to make the AI feel broken.

Expected benefit is **fairness and readability**, not performance — one shared
snapshot per tick also removes the repeated per-AI world reads `AGENTS.md` §53
warns about.

---

## 2. AI_GetTimeNeededForDistance_ms — two-tier reachability

### CONFIRMED FROM SOURCE

Returns a `TimeNeeded { usual_ms, optimistic_ms }` — **two** answers, not one.

Cheap path first: if the straight-line distance exceeds `optimizeDist`
(`16.0`, or `48.0` when `precise`), it returns a closed-form estimate

```cpp
(targetPos - (playerPos + playerMovement * 0.2f)).GetLength() / (maxVelocity * 0.75f) * 1000
```

with `optimistic_ms = usual_ms - 200`, and does not simulate.

Inside that distance it steps forward at `timeStep_ms = 10` with:

- `ffo = 0.1f` — an "in front of foot offset (ideal ball position)" added to the
  start position, along movement if moving faster than `idleDribbleSwitch`,
  otherwise toward the target;
- `bias = clamp(currentTime_ms / changeTime_ms, 0, 1)` with
  `changeTime_ms = 700` — momentum decays over 700ms, so existing velocity is
  shed gradually rather than instantly;
- two growing reach radii, `radius_usual = 0.28f` ("leg extension length") and
  `radius_optimistic = 0.9f`, both expanding by
  `adaptedMaxVelocity * bias * timeStep`;
- `adaptedMaxVelocity = maxVelocity * 0.94f`, commented as "the last part of that
  velo is very hard to attain (due to exponential air resistance)".

Once `bias >= 1` the remainder is solved analytically. `maxTime_ms` allows early
abandonment, in which case the result is deliberately pessimised to
`max(defaultOptimizedTime_ms, (currentTime_ms + 100) * 2)`.

### INFERENCE

The two radii encode **certainty**, not two different players: `usual` is the
time to get the ball under control at normal leg extension; `optimistic` is the
time at full stretch. Comparing players on `optimistic_ms` answers "who *could*
get there", on `usual_ms` "who gets there in control". That distinction is what
lets a team designate a chaser without every player lunging.

The 700ms momentum ramp is the reachability-side expression of the same
weight/inertia the locomotion model has. A player already sprinting the wrong way
is correctly penalised.

### Beyond 90 mapping

`AIService` computes a single `timeToBall` per actor (visible in the
`[AI] team=... timeToBall=` diagnostic). There is one answer, so the "who could
reach it at full stretch" question cannot be asked separately from "who reaches
it in control".

### Decision: **ADAPT**

- `PORT CLOSELY` the two-tier `usual` / `optimistic` split and the 700ms momentum
  ramp — both are football logic and both are cheap.
- `ADAPT` the constants. `0.28` and `0.9` are metres of leg extension; Beyond 90
  is in studs on a deliberately exaggerated arcade scale, so these convert as
  *ratios of reach*, never as literals (`AGENTS.md` §27).
- `KEEP EXISTING` the far-field shortcut in spirit — Beyond 90 should keep a cheap
  estimate beyond a threshold rather than stepping the whole pitch.
- `OMIT` the `maxTime_ms` early-abandon pessimisation until profiling shows the
  simulation cost matters.

---

## 3. AI_GetForceFieldMovement — off-ball positioning

### CONFIRMED FROM SOURCE

Off-ball movement is a **normalised sum of attractors and repellers**, not a
path.

Each `ForceSpot` has an origin, a power, a scale, a decay type and a magnet type.
Intensity is either constant (`e_DecayType_Constant`) or falls off linearly with
distance over `scale`, optionally raised to `forceSpot.exp`:

```cpp
intensity = clamp(1.0f - distance / forceSpot.scale, 0.0f, 1.0f);
if (forceSpot.exp != 1.0f) intensity = std::pow(intensity, forceSpot.exp);
```

Repellers invert the direction. **Attractors are damped near the target** —
`if (distance < attractorDampingDistance) relativeOrigin *= distance / attractorDampingDistance`
— with `attractorDampingDistance` defaulting to `10`.

The result is a weighted average, not a sum:

```cpp
return (cumulVec / cumulForce) * sprintVelocity;
```

### INFERENCE

Dividing by `cumulForce` is the important detail. It means adding more spots
changes the *direction* a player runs but not how fast — the output is always
scaled to `sprintVelocity` and the field expresses preference, not urgency. A
naive sum would make crowded areas produce faster movement, which is backwards.

Attractor damping is what stops players oscillating around a target they have
reached. Repellers are deliberately undamped: you always want to be pushed away
from a crowd at full strength.

### Beyond 90 mapping

Beyond 90 positions AI off the ball with `getFormationTarget` — a single anchor
per actor. That produces correct shape but no reactive spacing: nothing pushes
two team-mates apart when they converge, and nothing pulls a player into space.

This is the most likely source of the "AI plays like a possession loop rather
than like footballers" framing in the milestone brief.

### Decision: **ADAPT**

- `PORT CLOSELY` the normalise-by-cumulative-force rule and the attractor damping.
  Both are small and both are the reason the technique works.
- `ADAPT` the field composition to Beyond 90's own tactical model: the formation
  anchor becomes one attractor among several rather than the only target.
- `DEFER` the full `ForceSpot` decay-type enumeration. Linear decay with an
  exponent covers what Beyond 90 needs now; constant-decay spots can wait for a
  demonstrated case.
- Must respect `AGENTS.md` §53 — the field is evaluated per AI, so spot
  construction has to be shared per tick, not rebuilt per footballer.

---

## Not yet researched

Required before the §4 rewrite proper, and deliberately not guessed at here:

- `teamAIcontroller.cpp` (1042 lines) — team-level tactics, role assignment,
  and how a side switches between attacking and defending shape.
- `strategies/offtheball/default_def|mid|off.cpp` — per-role positioning, which
  is where the force field is actually populated.
- `strategies/offtheball/goalie_default.cpp` — goalkeeper AI.
- `elizacontroller.cpp` — the AI player controller and its update cadence.
- `AI_CalculateFreeSpace`, `AI_GetAdaptedFormationPosition`,
  `AI_GetBestDribbleMovement`, `AI_GetPassRatings`, `AI_GetMindSet`.

## Behaviour that is explicitly NOT for Beyond 90

Per `AGENTS.md` §50, separated out so it is not ported by accident:

- **Team-control assumptions.** GameplayFootball has one user controlling a whole
  side, with `AI_GetBestSwitchTargetPlayer` for switching between players. Beyond
  90 is one human per footballer; player-switching logic has no meaning here.
- **Engine-specific.** `Vector3::coords[]` manual copies "to avoid temp vars",
  the fixed 10ms prediction table, and the C++ class hierarchy.
- **Animation-specific.** `AI_GetShotDirection`'s stated purpose is picking an
  animation before the exact direction is resolved; Beyond 90 resolves direction
  in the shared action systems instead.

---

## 4. The force field's composition — `ElizaController::GetSupportPosition_ForceField`

Added after the initial pass. §3 above documents the *solver*; this documents
what is actually fed into it, which is the half that carries the football
meaning.

**File:** `src/onthepitch/player/controller/elizacontroller.cpp`, lines 610-800.
**Symbol:** `ElizaController::GetSupportPosition_ForceField`.

### CONFIRMED FROM SOURCE

Six categories of spot are pushed into one field, then solved and clamped:

| # | Spot | Magnet | Decay | Power | Scale | Exp |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Formation base position | Attract | Constant | `0.7 x (0.3 + 0.7 x clamp(dist,0..20))` | — | — |
| 2 | Make-run target | Attract | Constant | `2.0` | — | — |
| 3 | 3 closest opponents | Repel | Variable | `0.3 x role` | `5.0` | `0.7` |
| 4 | 6 closest team-mates | Repel | Variable | `0.4` | `14 x 0.75` | `1.0` |
| 5 | Ball at +200/350/500/650ms | Repel | Variable | `1.0` | `2.0` | `0.5` |
| 6 | Carrier — attract AND repel | both | Variable | `0.45` each | `28 x 0.75` / `16 x 0.75` | `1.0` |

Role multipliers on the opponent repel (#3):
`CB/LB/RB x2.2`, `DM x2.0`, `CM/LM/RM x1.6`, `AM x1.2`, `CF x1.0`.

Gates: #4 applies only when `GetFadingTeamPossessionAmount() >= 1.02`; #5 and #6
only when the player is not the designated carrier, #5 additionally at `>= 1.06`.

Result: `currentPos + AI_GetForceFieldMovement(forceField, currentPos, 7)`, then
clamped behind the offside line and inside the pitch.

Two details are load-bearing and easy to miss:

```cpp
// #1 -- the farther away from this position, the more we are attracted to it
spot.power *= 0.3f + 0.7f * NormalizedClamp((spot.origin - currentPos).GetLength(), 0.0f, 20.0f);

// #3 -- anti-magnet behind opponent, because the pass-way must be cleared
spot.origin = oppPos + (oppPos - mainManPos).GetNormalized(0) * 2.0f;
```

### INFERENCE

- #1's distance-scaled power makes the shape **self-restoring**: drift is cheap
  near the anchor and expensive far from it, so players roam locally but the team
  shape does not dissolve.
- #3's offset origin is the cleverest part. Repelling from the opponent's own
  position pushes a supporting player *anywhere* away. Repelling from a point
  2m **behind** the opponent, measured from the carrier, pushes them
  preferentially **sideways out of the shadow the opponent casts** — which is
  exactly into the passing lane. The comment says as much.
- #6 being an attract and a repel at the same origin with different scales is a
  **ring**: attracted from beyond ~21m, repelled within ~12m, so a supporting
  player settles at a support distance instead of either drifting away or
  crowding the carrier. This is a much simpler mechanism than a target distance
  with a deadzone, and it composes with everything else in the field.
- The role multipliers encode a real football idea: defenders prioritise not
  being near an opponent, forwards do not mind being marked.

### Beyond 90 mapping

`AIService.getFormationTarget` produces a single anchor per actor and nothing
else acts on off-ball position. There is no team-mate separation, no lane
clearing, no support ring, and no ball avoidance — which is why team-mates
converge and why the shape reads as static.

### Decision: **ADAPT**

- `PORT CLOSELY`: the six categories, the ring (#6), the distance-scaled anchor
  power (#1), and the behind-opponent offset (#3). These are the football.
- `ADAPT`: the constants are metres and must be re-derived at Beyond 90's stud
  scale and pitch size (`AGENTS.md` §27); the role table maps onto Beyond 90's
  `DEF/MID/FWD/GK` slots, not GameplayFootball's eleven roles.
- `OMIT`: the commented-out sine "flank flow" variant (dead code), and the
  `GetForwardSupportPlayer` special case until Beyond 90 has that concept.
- `DEFER`: the make-run spot (#2). Runs in behind need the offside line wired in
  first, and §1.3/§1.8 own restarts and offside.
- Must be built from the per-tick shared context, not per actor (`AGENTS.md` §53).
