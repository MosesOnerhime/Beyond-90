# GameplayFootball — the on-the-ball AI decision

Research for the Milestone 6.4 follow-up "the AIs are still pretty dumb, port
GameplayFootball's code closely".

## Source

| | |
| --- | --- |
| Repository | https://github.com/vi3itor/GameplayFootball.git |
| Branch | `windows` |
| Commit | `1dc1518abd0ffaa349c7e1a53ded6ba19213c73f` (2021-08-21) |
| Researched | 2026-08-28 |

Files and symbols inspected:

- `src/onthepitch/player/controller/elizacontroller.cpp`
  - `ElizaController::GetOnTheBallCommands` — the decision itself
  - `ElizaController::_GetPassingOdds` (both overloads) — interception model
  - `ElizaController::_AddPass`, `_AddPanicPass`
- `src/onthepitch/AIsupport/AIfunctions.cpp` — `AI_CalculateFreeSpace`
- `src/onthepitch/player/player.cpp` — `Player::_CalculateTacticalSituation`
- `src/base/math/bluntmath.hpp` — `curve()`
- `src/base/geometry/line.cpp` — `Line::GetDistanceToPoint`
- `src/gamedefines.hpp` — `pitchHalfW = 55`, `sprintVelocity = 8`

---

## The Beyond 90 problem this was researched to solve

CONFIRMED FROM BEYOND 90 RUNTIME. `AIService.decidePossession` selected an
action in a fixed order — clearance, then shoot, then pass — and the shot test
was a flat gate:

```lua
if toGoal.Magnitude <= AIConfig.Shooting.MaximumDistance   -- 82 studs
    and goalAlignment >= AIConfig.Shooting.MinimumGoalAlignment
```

On a 343-stud pitch, 82 studs permits a shot from inside the AI's own half. The
playtest log is a wall of them:

```
[AIShot] player=HOME_AI_1  distance=77.3  launchSpeed=138.8  result=OnTarget
[AIShot] player=HOME_AI_3  distance=78.2  launchSpeed=138.7  result=OnTarget
[AIShot] player=AWAY_AI_3  distance=79.3  launchSpeed=138.5  result=OnTarget
```

Because the shot was tested *before* the pass, a shot that was almost always
available also suppressed every pass the AI might have made. Carrying spells of
six to ten seconds in a straight line ending in a speculative shot were the
whole behaviour.

---

## CONFIRMED FROM SOURCE

### 1. Shooting is gated by POSITION, not distance

```cpp
float idealShotPosFactor = 1.0f - NormalizedClamp(
    (Vector3((pitchHalfW - 7.0f) * -team->GetSide(), 0, 0) - player->GetPosition()).GetLength(),
    0.0f, 16.0f);
idealShotPosFactor = curve(idealShotPosFactor, 1.0f);
if (idealShotPosFactor > 0.1f) { ... }
```

The reference measures distance from an *ideal shooting position* 7 m in front
of the goal, over a 16 m radius, and passes it through `curve()`
(`sin((x-0.5)*pi)*0.5+0.5`, an S). Below 0.1 **no shot is evaluated at all** —
the decision falls through to passing by itself rather than being ordered
around it.

### 2. The shot is scored by interception odds at three aim points

```cpp
odds1 = _GetPassingOdds(goal, -3.6f, e_FunctionType_Shot, ..., 3.0f);
odds2 = _GetPassingOdds(goal,  0.0f, ...);
odds3 = _GetPassingOdds(goal,  3.6f, ...);
// best of the three
odds = std::pow(odds, 0.5f);
if (odds + random(0.0f, 0.5f) > 0.5f) { /* shoot */ }
```

A shot is a pass to the back of the net, scored with the same model, at 3x ball
speed. The random term is load-bearing: without it a whole team in similar
positions reaches identical verdicts on the same frame.

### 3. Passing requires a team-mate to be BETTER PLACED

```cpp
if (mateTacticalRating > tacticalRating + tacticalImprovementThreshold) { ... }
```

This is the difference between a footballer and a ball-hog. The carrier rates
its own situation and only releases when someone genuinely improves it — not
merely when someone is open.

`Player::_CalculateTacticalSituation` gives three components:

| Component | Meaning | GF weight |
| --- | --- | --- |
| `forwardSpaceRating` | free space half a second's sprint ahead | 0.4 |
| `spaceRating` | free space where the player is now | 0.3 |
| `forwardRating` | progress to the opponent goal, `^1.5` | 2.0 + mindset·6 |

`AI_CalculateFreeSpace` advances each opponent by its own velocity *and then
runs it toward the point at sprint speed* for the remaining lookahead — so
"space" means space that will still exist when the ball arrives.

### 4. The interception model is a race, not a corridor

`_GetPassingOdds` compares, for every opponent, the time the opponent needs to
reach the nearest point on the pass line against the time the ball needs to get
there, and accumulates the shortfall. High passes only count opponents in the
middle of the flight, add 2.5 s of trapping time late, and take a flat 0.4
danger penalty so a lofted ball is not preferred when a ground pass would do.

### 5. Holding the ball lowers the bar for releasing it

```cpp
float longPossessionFactor = std::pow(
    NormalizedClamp(CastPlayer()->GetPossessionDuration_ms(), 0, 5000), 2.0f);
float passMinimum   = 0.2f * (...) - longPossessionFactor * 0.1f;
float passThreshold = 0.1f          - longPossessionFactor * 0.05f;
```

Squared over five seconds. This is the reference's answer to a carrier who will
not let go — it makes holding on progressively less attractive rather than
forbidding it.

### 6. Panic comes AFTER the pass search

`_AddPanicPass` fires only when `bestMateRating.player == 0 ||
bestMateRating.passRating < panicProneness * goalCloseness`. The reference
clears when the options have already been found wanting.

### 7. Order of resolution

Pass is pushed to the command queue before shot. Both may be queued; the pass
wins where both are viable.

---

## INFERENCE

Inside the penalty area a carrier's own `forwardRating` is near maximum, so a
team-mate rarely clears the improvement threshold there. Passing being resolved
first is therefore not a bias toward passing — it is a bias toward passing
*outside* shooting positions, which is the behaviour that was missing.

---

## Units

GameplayFootball works in metres on a 110 x 72 m pitch (`pitchHalfW = 55`).
Beyond 90's pitch measures 343 x 241 studs, half-length 171.5 — about
**3.1 studs per metre**. Times are real seconds in both, so the timing model
carries over unchanged. `sprintVelocity = 8 m/s` maps to Beyond 90's own
`PlayerConfig.Movement.SprintSpeed`, which is read rather than restated.

| GF | metres | Beyond 90 | studs |
| --- | --- | --- | --- |
| ideal shot position | 7 | `Shooting.IdealDistanceFromGoal` | 22 |
| shot radius | 16 | `Shooting.IdealRadius` | 50 |
| aim offset | ±3.6 | `Shooting.AimHalfWidth` | ±11 |
| free-space radius | 5 | `Decision.SafeDistance` | 15.5 |
| min lofted distance | 10 | `Decision.LoftedMinimumDistance` | 31 |

---

## A unit trap worth recording

`_GetPassingOdds` mixes seconds and distances, and two of its coefficients are
**per-metre quantities hidden inside the formula**:

```cpp
float oppToIntersect_sec  = (oppDistance + 1.0f) / sprintVelocity;   // +1 METRE
float ballToIntersect_sec = 0.7f + originToBallPos.GetLength() * u * 0.03f;
                                                          // 0.03 s per METRE
```

Converting the tuning constants in `AIConfig` while leaving these at their metre
values charged a 60-**stud** pass the flight time of a 60-**metre** one. The
danger term then saturated at its cap for almost every ground pass, and lofted
passes escaped only because their opponent window is narrower (`u` restricted to
0.2..0.65) — so the AI lobbed everything. Measured: mean ground odds `0.004`.

Both are now converted at 343 studs / 110 m in `AITacticalEvaluator`. The
resulting interception curve, one defender offset from a 60-stud lane:

| defender offset | ground odds |
| --- | --- |
| 4 studs | 0.00 |
| 8 studs | 0.05 |
| 15 studs | 0.30 |
| 25 studs | 0.66 |
| 40 studs | 1.00 |

Over 400 realistically-spaced 3v3 passes: ground preferred 38%, lofted 29%,
tied 33%.

This is the concrete case AGENTS.md §27 warns about — "do not assume 1
GameplayFootball meter = 1 Roblox stud". The trap is that it applies to
coefficients *inside* a ported formula, not only to the constants around it.

## Decisions

| Reference behaviour | Decision | Notes |
| --- | --- | --- |
| `AI_CalculateFreeSpace` | **PORT CLOSELY** | `AITacticalEvaluator.CalculateFreeSpace` |
| `_GetPassingOdds` | **PORT CLOSELY** | `AITacticalEvaluator.GetPassingOdds` |
| `_CalculateTacticalSituation` | **PORT CLOSELY** | `AITacticalEvaluator.RateSituation` |
| Two-stage pass selection | **PORT CLOSELY** | `AIService.choosePass` |
| `longPossessionFactor` | **PORT CLOSELY** | squared over 5 s |
| Position-gated shooting | **PORT CLOSELY** | replaces the distance gate entirely |
| Three-aim-point shot odds | **PORT CLOSELY** | `AIService.shouldShoot` |
| Panic pass | **ADAPT** | mapped onto Beyond 90's existing `Clearance`, moved after the pass search |
| Role "mindset" scaling | **ADAPT** | 3v3 footballers are all-rounders; a single mid-range `ForwardWeight` |
| `AI_GetBestDribbleMovement` | **KEEP EXISTING** | Beyond 90's `getPossessionMovementTarget` already does this and is tuned |
| Command-queue architecture | **OMIT** | engine-specific; Beyond 90 calls its own shared football actions |
| Pass-type odds for short/long/high | **ADAPT** | Beyond 90 has GroundPass / LobPass, not three tiers |
| Receiver commitment window | **KEEP EXISTING** | Beyond 90's own, prevents mid-windup re-aiming |

## Licensing

No GameplayFootball source is vendored into `src/`. The clone stays outside the
runtime tree. What was translated is algorithmic structure and weighting, which
is recorded here with its origin so the derivation is traceable; the
implementation is Roblox-native Luau written against Beyond 90's own data
model. `src/shared/Football/AITacticalEvaluator.luau` carries the same
attribution in its header.
