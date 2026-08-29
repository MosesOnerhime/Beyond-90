# GameplayFootball — Officiating, Set Pieces, Offside, Positions

Research for Beyond 90 Milestone 6.3 (§45, §64).

## Source

- Repository: `https://github.com/vi3itor/GameplayFootball.git`
- Local research clone: `temp/GameplayFootball` (outside the Rojo tree; never a runtime dependency)
- Date researched: 2026-08-27
- Files inspected:
  - `src/onthepitch/referee.hpp` / `referee.cpp`
  - `src/onthepitch/teamAIcontroller.cpp` (`PrepareSetPiece`)
  - `src/onthepitch/AIsupport/AIfunctions.cpp` (`AI_GetOffsideLine`)
  - `src/gamedefines.hpp` (enums, pitch constants)
- Symbols: `Referee::Process`, `Referee::BallTouched`, `Referee::TripNotice`, `Referee::CheckFoul`,
  `Referee::PrepareSetPiece`, `RefereeBuffer`, `Foul`, `TeamAIController::PrepareSetPiece`,
  `AI_GetOffsideLine`, `e_SetPiece`, `e_MatchPhase`, `e_PlayerRole`

## Pitch constants — CONFIRMED FROM SOURCE

```
pitchHalfW = 55    // half LENGTH, goal-to-goal axis (x)
pitchHalfH = 36    // half WIDTH, touchline-to-touchline axis (y)
lineHalfW  = 0.06
```

So the pitch is 110 m × 72 m and **x runs goal to goal**.

Beyond 90's axes are transposed: **Z is the goal-to-goal axis, X is across**. Every ratio below is
therefore stored normalized (a fraction of the half-extent) and multiplied by Beyond 90's own
measured pitch bounds, never by a metre constant. `1 GF metre ≠ 1 stud`.

Derived ratios actually used:

| Quantity | GameplayFootball | Normalized |
| --- | --- | --- |
| Out-of-play margin | `pitchHalf + lineHalfW + 0.11` | half-extent + line + small epsilon |
| Penalty area depth | 16.5 m of 110 m | 0.15 of length |
| Penalty area half-width | 20.15 m of 36 m half | 0.5597 of half-width |
| Penalty spot | 11 m from line | 0.10 of half-length inward |
| Defensive wall / free-kick distance | 9.15 m | 0.0832 of length |
| Goal-kick spot | `pitchHalfW * 0.92` from centre | 0.92 of half-length |
| Throw-in x clamp | `pitchHalfW - 0.6` | half-length − 0.6 m equivalent |
| Kickoff centre-circle keep-out | 9.4 m | 0.0855 of length |

## Restart decision — CONFIRMED FROM SOURCE

`Referee::Process`, in this order:

1. **Phase end** — time exceeded AND `|ballPos.x| < 10` (ball near the middle). Long whistle,
   `KickOff`, `prepareTime = now + 3000`, next phase, `endPhase = true`.
2. **Goal line crossed** (`|x| > pitchHalfW + lineHalfW + 0.11`):
   - goal scored → `KickOff`, `prepare = now + 6000`, team = opposite of scorer
   - ball exited over the **last toucher's own** goal line → `Corner` to the other team,
     restart `(pitchHalfW * lastSide, ±pitchHalfH, 0)`
   - otherwise → `GoalKick` to the other team, restart `(pitchHalfW * 0.92 * -lastSide, 0, 0)`
3. **Touchline crossed** (`|y| > pitchHalfH + lineHalfW + 0.11`) → `ThrowIn` to the opposite of the
   last toucher, restart x clamped to `±(pitchHalfW - 0.6)`, y = `±pitchHalfH`.
4. `CheckFoul()` last.

Every branch calls `CheckFoul()` **first** and aborts if a foul is awarded — fouls outrank ball-out
restarts. This is the rule-priority ordering §76 asks for, taken directly from the source.

### `afterSetPieceRelaxTime_ms` — the detail that matters

The touchline test is skipped entirely while this timer is non-zero, and it is set to **400 ms**
after a set piece is taken. The source comment says it plainly: *"throw-ins cause immediate new
throw-ins, because ball is still outside the lines at the moment of throwing"*. Without this a
throw-in re-triggers itself forever.

## Set-piece lifecycle — CONFIRMED FROM SOURCE

`RefereeBuffer { active, desiredSetPiece, teamID, stopTime, prepareTime, startTime, restartPos, taker, endPhase }`

```
stopTime  = now
prepareTime = now + 2000     (6000 after a goal, 3000 at phase end, +10000 for a card)
startTime = prepareTime + 2000

stopTime + 300  -> short whistle (skipped for kick-off and phase ends)
prepareTime     -> ResetSituation(restartPos); both teams PrepareSetPiece(); pick taker
startTime       -> short whistle; StartPlay(); StartSetPiece()
taker touches   -> StopSetPiece(); relax timer = 400 ms; clear foul
```

## Set-piece positioning — CONFIRMED FROM SOURCE

The unifying idea, and the part worth porting closely: **every outfield position is the player's own
normalized formation position remapped into a per-set-piece bounded box, then pulled toward focus
points.** One function does all of it:

```
AI_GetAdaptedFormationPosition(match, player,
    backXBound, frontXBound, lowYBound, highYBound,
    xFocus, xFocusStrength, yFocus, yFocusStrength,
    focusPos, focusStrength, midfieldFocus, midfieldFocusStrength, ...)
```

Nobody is teleported to a hardcoded slot — a defender stays a defender inside the corner-kick box.
Goalkeepers are handled separately and always reset to `(pitchHalfW * side * 0.98, 0, 0)`.

Per set piece (taker team / defending team):

| Set piece | Taker team box | Defending team box |
| --- | --- | --- |
| Kick-off | formation × 0.6, halved in x, pushed to own half, ≥ 9.4 from centre | same |
| Goal kick | back `0.5`, front `-0.2` | back `0.4`, front `-0.1` |
| Corner | back `-0.2`, front `-0.96`, xFocus `0.85·front`, midfieldFocus `0.9` | back `0.98`, front `0.5`, xFocus `0.94·back`, midfieldFocus `0.1` |
| Throw-in | ±30/20 around ball, yFocus `ball.y·0.996` | ±30/15, xFocus pushed 16 goalward |
| Free kick | bounds scale with distance from own goal (`xOffset`) | same, plus 9.15 keep-out |
| Penalty | ball +50/−10, yFocus 0 | ball +11/−20, xFocus strength 1.0 |

Extra rules:
- **Wall**: defending team only, and only if the ball is within 40 m of goal — the 3 closest players
  are placed 9.15 m from the ball along the ball→goal vector, fanned by `(0, 1.0 - i, 0) * 0.07`.
- **Penalty**: everyone else outside the box (`x·side ≤ pitchHalfW − 16.5 − 0.5`) *and* outside the
  9.15 + 0.5 arc.
- **Taker** = closest player to the ball. Offsets: throw-in/kick-off `0.3`, free kick `2.3`,
  penalty `3.0`.
- Minimum distance from the ball: taker's team `2.0`, defending team `5.0`.

## Offside — CONFIRMED FROM SOURCE

Two halves, and the split is the important part.

**Snapshot, taken on every ball touch** (`Referee::BallTouched`):

```
offsidePlayers.clear()
offside = AI_GetOffsideLine(match, mentalImage, opponentTeamID)
for each active team-mate of the toucher, excluding the toucher:
    if player.x * side < offside * side - 0.20:   // 0.20 relax
        offsidePlayers[player] = player.position
```

**Punishment, on the *next* touch**: if the player who just touched the ball is in `offsidePlayers`,
it is offside — indirect free kick to the other team **at the position recorded in the snapshot**,
not where the ball was received.

So a player in an offside position is never penalised for standing there; only for becoming the next
toucher. That is exactly §60/§61.

`AI_GetOffsideLine`:

```
deepest      = opponent furthest toward their own goal          (usually the keeper)
secondDeepest = next furthest, excluding `deepest`               // "one-but-deepest"
offsideLine  = secondDeepest.x
if ball is further forward than that: offsideLine = ball.x
```

The source comment is explicit: *"offside: we are actually looking for the one-but-deepest opponent
(association football rule!)"*. The ball clamp is the "level with the ball" rule.

**Set-piece exemption**: the punishment branch requires `buffer.active == false`, so offside can
never be given directly from a restart; and the snapshot is additionally skipped for throw-ins.

## Fouls — CONFIRMED FROM SOURCE

`Referee::TripNotice(tripee, tripper, tackleType)`

Standing tackle (type 2) is a foul when **all** hold:
- victim's team possession > 1.1 (they genuinely had it)
- tripper's function is Interfere or Sliding
- victim is within 2.0 m of the ball
- different teams

Sliding tackle (type 3) additionally scores **severity**:

```
severity  = pow(clamp(|touchFrame - currentFrame| / touchFrame, 0, 1), 0.7) * 0.5   // mistiming
severity += NormalizedClamp(|ball - touchPos|, 0, 2) * 0.5                          // missed the ball
severity += (tripee.pos - tripper.pos).normalized · tripee.direction * 0.5 + 0.5     // from behind

> 1.0 -> foul     > 1.4 -> yellow     > 2.0 -> red (no advantage)
```

**Advantage** (`CheckFoul`): a foul starts with `advantage = true`. After 600 ms it is evaluated;
past 3000 ms the foul is cancelled outright (advantage ran long enough); in between, if the victim's
team possession drops below 1.0 the advantage is revoked and the foul given.

**Penalty test**: `|foulPos.y| < 20.15 - lineHalfW` and `foulPos.x * -victimSide > pitchHalfW - 16.5 + lineHalfW`.
Spot at `((pitchHalfW - 11.0) * foulPlayerSide, 0, 0)`.

## Roles — CONFIRMED FROM SOURCE

`e_PlayerRole`: `GK, CB, LB, RB, DM, CM, LM, RM, AM, CF`.

`GetFormationEntry().position` is a **normalized** vector scaled by pitch half-extents at use time —
which is what makes one formation description work for any pitch size and any set piece.

## Beyond 90 decisions

| Behaviour | Decision | Note |
| --- | --- | --- |
| Restart decision tree | **PORT CLOSELY** | Same branch order and same last-touch/side test |
| `afterSetPieceRelaxTime` | **PORT CLOSELY** | Without it throw-ins self-retrigger |
| Set-piece timing buffer | **ADAPT** | Same stop/prepare/start shape, Beyond 90 durations |
| Normalized formation remap | **PORT CLOSELY** | The core idea of §65 |
| Wall / keep-out distances | **PORT CLOSELY** | As pitch-length ratios, not metres |
| Offside line (one-but-deepest + ball clamp) | **PORT CLOSELY** | Verbatim rule |
| Offside snapshot / involvement split | **PORT CLOSELY** | Exactly §60/§61 |
| Offside set-piece exemption | **PORT CLOSELY** | §62 |
| Foul severity model | **ADAPT** | Beyond 90 has no slide tackle yet (§84); the standing-tackle conditions and the from-behind term map onto the existing TackleEvaluator |
| Advantage | **ADAPT** | Simplified per §59: short window, no card memory |
| Cards | **OMIT** | §58/§101 — hooks only |
| Extra time / penalty shootout phases | **DEFER** | §49 asks only for halves |
| `MentalImage` perception layer | **OMIT** | Engine-specific; Beyond 90 reads authoritative state on the server |
| C++ class hierarchy | **OMIT** | §50 of AGENTS.md |
