# Pressing, tackling and slide tackling

Research for Milestone 6.8. Records what the footage shows, what the
GameplayFootball source actually does, what is inferred, and what is proposed
for Beyond 90. It does not authorise a refactor on its own (`AGENTS.md` §19).

## Provenance

### Footage reference

| | |
| --- | --- |
| File | `ref/efootball pressing.mp4` (local development reference only, never uploaded) |
| Duration | 73.35 s, 832×384, 60 fps |
| Title | eFootball — **mobile build** (on-screen touch controls present throughout) |
| Method | Frames extracted locally with ffmpeg into the session scratchpad; no Roblox asset created (`AGENTS.md` §57) |
| Segments examined | 9–16 s, 40–46 s (dense, 4 fps), 54–70 s |

### Source reference

| | |
| --- | --- |
| Repository | `https://github.com/vi3itor/GameplayFootball.git` |
| Branch | `windows` |
| Commit | `1dc1518abd0ffaa349c7e1a53ded6ba19213c73f` |
| Date researched | 2026-08-31 |
| Clone | `/d/repos/GameplayFootball` (outside the runtime tree, `AGENTS.md` §27) |

### Files inspected

| File | Read |
| --- | --- |
| `src/onthepitch/match.cpp` | 1600-1610, 1830-1850, 1950-1985 |
| `src/onthepitch/teamAIcontroller.cpp` | 924-962 (`ApplyTeamPressure`, `ApplyKeeperRush`, `CalculateSituation`) |
| `src/onthepitch/player/controller/elizacontroller.cpp` | 300-335 |
| `src/onthepitch/player/controller/playercontroller.cpp` | 388-415 (`_SlidingCommand`) |
| `src/onthepitch/player/controller/humancontroller.cpp` | 48-60, 196-212 |

### Symbols

`ApplyTeamPressure`, `teamPressurePlayer`, `endApplyTeamPressure_ms`,
`forceMagnet`, `_SlidingCommand`, `_InterfereCommand`,
`CouldWinABallDuelLikeliness`, `e_FunctionType_Sliding`,
`e_FunctionType_Interfere`, `GetFrameNum`, `oppTimeNeededToGetToBall`.

### Licence

Apache-2.0 with per-file notices ("written by bastiaan konings schuiling
2008 - 2015"); the controller and strategy files additionally declare themselves
public domain. Nothing is copied verbatim into Beyond 90. Where a rule is
translated closely below, it is identified as such and attributed.

---

## Part A — What the footage shows

Labels per `AGENTS.md` §28.

### A1. The defensive control set

**OBSERVED FROM FOOTAGE.** The touch control cluster swaps wholesale with
possession. In possession: **Through / Shoot / Pass / Dash**. Out of possession:
**Match-up / Tackle / Switch / Dash & Pressure**. The swap is immediate and
complete — no defensive control is shown while attacking, and vice versa.

**INTERPRETATION.** Four defensive verbs, not one. "Tackle" and
"Dash & Pressure" are separate buttons, so *closing down* and *challenging* are
distinct player decisions rather than one action with a distance check.
"Match-up" is a sustained containment stance, distinct from both.

**RECOMMENDATION.** Beyond 90 should treat close-down and challenge as separate
inputs too. This is also a direct confirmation of `AGENTS.md` §40's contextual
prompt rule, from the reference the section points at.

### A2. Only one defender engages

**OBSERVED FROM FOOTAGE.** Through the 40.5–43.5 s sequence, exactly one
light-kit defender carries the cyan controlled-player marker and closes on the
carrier. Other light-kit players are visible in frame throughout — one wide
lower-left, one upper-left, others right — and they **do not converge on the
ball**. They drift and hold relative positions while the engagement resolves.

**INTERPRETATION.** Pressing is one committed presser plus a held shape, not a
collective chase. This is the single most important behavioural difference from
Beyond 90 today.

**RECOMMENDATION.** Nominate one presser at team level; everyone else keeps
shape. See decision P1.

### A3. The engagement has duration

**OBSERVED FROM FOOTAGE.** At 4 fps: approach begins ≈42.3 s, the two players
physically overlap ≈42.55–43.05 s, separation with the ball won ≈43.3 s, and the
control set flips to attacking by 43.55 s. So roughly **1.0 s** from committed
approach to won ball, of which about **0.5 s** is contact.

**INTERPRETATION.** Winning the ball is a resolved struggle over time, not an
instantaneous test at a moment. This matches the frame-window model confirmed in
the source (B1) from an entirely independent direction.

**RECOMMENDATION.** A challenge in Beyond 90 should occupy a window of that
order, and be mistimeable within it.

### A4. The containment indicator

**OBSERVED FROM FOOTAGE.** The controlled defender carries a cyan ring at his
feet. During the engagement the ring **stretches into a curved sweep** that
wraps from the defender around the carrier's side, then collapses back to a
plain circle once the ball is won.

**INTERPRETATION.** Read as a containment/steering arc: the ground the defender
is currently denying. Its shape suggests the defender is being placed *across*
the carrier rather than driven straight at him. **This is inference from stills;
the exact semantics are not confirmed** and could also be a dash trail.

**RECOMMENDATION.** Do not copy the visual. Do take the underlying idea: the
presser occupies a side and steers, and the player is shown what he is denying.
Beyond 90's broadcast camera makes some ground indicator valuable, but it must
survive §40's readability constraints.

### A5. The match-up target is dynamic

**OBSERVED FROM FOOTAGE.** Two names are rendered: the controlled defender and
one opponent. Between 40.5 s and 41.0 s the named opponent changes from
"Lautaro Martinez" to "Lionel Messi" without a player switch, then the
controlled player itself changes to "Lisandro Martinez" at 41.5 s.

**INTERPRETATION.** The named opponent tracks the current immediate threat
rather than being a fixed pre-match marking assignment.

### A6. No slide tackle occurs in this clip

**OBSERVED FROM FOOTAGE.** Across all three out-of-possession spells (9–16 s,
36–48 s, 54–70 s) no slide tackle was observed. Every dispossession seen is a
standing engagement. The **Tackle** button exists throughout but no slide
animation appears.

**RECOMMENDATION.** Slide-tackle design cannot lean on this footage. It must
come from the GameplayFootball rules in B4 and from real football
(`AGENTS.md` §27). If the user has slide-tackle footage, it is worth supplying —
this milestone's §5 is otherwise the least reference-backed part.

---

## Part B — What the source does

### B1. Tackle contact is a frame window

**CONFIRMED FROM SOURCE** (`match.cpp:1835-1838`):

```
tackle += 1 if p1 is Sliding or Interfere and 5 < frameNum < 28
tackle += 2 if p2 is Sliding or Interfere and 5 < frameNum < 28
if (distance < 2.0 && tackle > 0 && tackle < 3) { ... }
```

Three separate facts. Contact registers only inside an **animation frame
window**, not at a moment. Proximity is a **hard 2.0 gate**, checked alongside
the window rather than scored. And `tackle == 3` — both players challenging —
is **explicitly ignored**, resolving to nothing.

**INTERPRETATION.** The window is what makes a challenge mistimeable: too early
or too late and no contact exists at all, regardless of position. The
cancel-on-mutual rule avoids arbitrating a symmetric case.

### B2. Pressing is a team-granted licence

**CONFIRMED FROM SOURCE** (`teamAIcontroller.cpp:930-946`):

```
endApplyTeamPressure_ms = now + 500
opponentPos = opp->GetPosition() + opp->GetMovement() * 0.24
teamPressurePlayer = AI_GetClosestPlayer(team, opponentPos + side * 1.0, true, goalie)
teamPressurePlayer->SetManMarkingID(opp->GetID())
```

A **500 ms** licence, granted to exactly one player, chosen closest to the
opponent's **predicted** position (a quarter-second of lead), offset one unit
toward the defending side, with the goalkeeper excluded. Man-marking is assigned
in the same call.

**CONFIRMED FROM SOURCE** (`elizacontroller.cpp:305-313`): the individual only
presses aggressively (`forceMagnet = true`) when it **is** the nominated
`teamPressurePlayer`, the ball is in play, it is not a set piece, the team does
not have best possession, it is not itself the possession player, and it is not
the goalkeeper.

**INTERPRETATION.** The licence is short and re-granted continuously, so the
nominated presser can change as the situation moves, but only ever one at a
time. The offset toward the defending side biases selection to a player who is
goal-side rather than one level with or beyond the carrier.

This is the mechanism behind observation A2, reached independently.

### B3. Human input is locked out during a challenge

**CONFIRMED FROM SOURCE** (`humancontroller.cpp:52-58`): while the function type
is `Sliding` or `Interfere` and no touch is pending, the action mode and input
buffers are cleared.

**INTERPRETATION.** Committing to a challenge costs the player control until it
resolves. That is the risk half of the risk/reward, and it is enforced on input
rather than only in the outcome.

### B4. The AI slide rule

**CONFIRMED FROM SOURCE** (`playercontroller.cpp:388-415`). Preconditions, in
order:

1. `team->GetHumanGamerCount() != 0` → **return**. AI never slides on a team
   containing a human player.
2. A ball retainer exists → return.
3. `CouldWinABallDuelLikeliness() < 0.7` → return.
4. Requires: not best possession, `possessionAmount < 0.6`, not the designated
   possession player, and the opponent team has possession.

Then, using predicted positions (ball at +200 ms, self and opponent at
+0.2 s of their own movement):

```
ballDist in (0.7, 1.6)  AND  oppTimeNeededToGetToBall > 260 ms
   OR
ballDist in (0.6, 1.8)  AND  opponent is shooting with a touch pending
```

Direction is toward the ball's predicted position offset by opponent movement;
velocity is sprint.

**INTERPRETATION.** Four things stand out. The slide fires only inside a
**narrow distance band with a lower bound** — too close is as invalid as too far,
which is what stops it being a default challenge. It requires a **time-to-ball
advantage**, not just proximity. The second clause is a distinct **shot block**
case with a wider band. And the AI is deliberately barred from sliding on a
human's team, presumably to avoid a bot spoiling a human's match.

Rule 1 does not transfer: Beyond 90's identity is mixed human/AI teams
(`AGENTS.md` §47), so a blanket ban would disable the behaviour in almost every
match. The *intent* — do not let AI slide recklessly around humans — should be
preserved as tuning instead.

### B5. The sliding stat biases the loose ball

**CONFIRMED FROM SOURCE** (`match.cpp:1606-1608`): a player with a touch pending
while `Sliding` shifts the ball's bounce bias by `0.1 + 0.4 * technical_slidingtackle`.

**INTERPRETATION.** The outcome of a slide is a *physical bias on a loose ball*,
not a possession transfer. That fits Beyond 90's controlled-ball model well.

---

## Part C — Beyond 90 mapping and decisions

Current state: `DefendingService` evaluates a tackle instantaneously against
scored thresholds; `AIService` has `getPressTarget` / `getSupportPressTarget`
per footballer with no team-level nomination; `AttemptSlideTackle` exists but
has no tackler-side animation.

| # | Behaviour | Decision | Reasoning |
| --- | --- | --- | --- |
| P1 | One nominated presser per team, short re-granted licence | **PORT CLOSELY** | Confirmed twice over (A2 observed, B2 in source). It is the structural fix for pressing reading as a chase. Port the shape of the rule; derive the window length and the goal-side offset for Beyond 90 rather than copying 500 ms / 1.0 unit. |
| P2 | Nominate by closest to the opponent's **predicted** position | **PORT CLOSELY** | Cheap and clearly right. `AIService.estimateTimeToPoint` already returns a momentum-aware pair; prefer time-to-ball over raw distance, which is a small improvement on the reference. |
| P3 | Goalkeeper excluded from nomination | **PORT CLOSELY** | Trivial, and Beyond 90 has `actor.Position == GoalkeeperConfig.Role`. |
| P4 | Non-nominated players hold shape | **ADAPT** | Beyond 90 already has the machinery: `computeTeamShape` from 6.7. Gate `getPressTarget` on nomination and let the shape do the rest. |
| P5 | Man-marking assigned with the licence | **DEFER** | Beyond 90 has no marking assignment system. Out of scope per the milestone brief; revisit with 5.9. |
| T1 | Contact resolved over a frame window | **ADAPT** | The principle transfers; the implementation must not. Roblox animation frames are not a reliable clock and animation must not decide validity (`AGENTS.md` §39). Use a server-timed contact window opened by the action, with the animation's `TackleContact` marker aligned to it for presentation. |
| T2 | Hard proximity gate alongside the window | **PORT CLOSELY** | Beyond 90 already has `MaximumBallDistance` / `MaximumOpponentDistance`; keep them as hard gates rather than folding them into the score. |
| T3 | Mutual challenge cancels | **ADAPT** | Adopt the principle — do not arbitrate a symmetric contest — but Beyond 90 should make the cancel *readable* (both players bounce off) rather than silently nothing. |
| T4 | Input lockout during a committed challenge | **PORT CLOSELY** | This is the risk half of the mechanic and Beyond 90 partly has it (`SlidingAttribute`, `IsRecovering`). Extend it to the standing tackle. |
| S1 | Narrow distance band with a lower bound | **PORT CLOSELY** | The lower bound is the non-obvious part and the reason slides stay rare. Convert the band to studs by ratio, not by assuming 1 m = 1 stud. |
| S2 | Requires a time-to-ball advantage | **PORT CLOSELY** | Beyond 90 already computes time-to-ball for both sides. |
| S3 | Separate shot-block case with a wider band | **ADAPT** | Good football and readable. Beyond 90 has shot detection; wire it in. |
| S4 | AI never slides on a human's team | **OMIT** | Does not fit Beyond 90's mixed human/AI teams (`AGENTS.md` §47). Preserve the intent through rarity tuning and the `CouldWinABallDuel` equivalent instead. |
| S5 | Slide outcome as a bounce bias on a loose ball | **ADAPT** | Fits the controlled-ball model in `AGENTS.md` §32 far better than a possession flag flip. |
| A1 | Separate close-down and challenge inputs | **ADAPT** | Confirmed from the footage's own control set. Beyond 90's current double-tap slide gesture should be re-examined against this. |
| A2 | Containment/steering arc indicator | **DEFER** | Semantics not confirmed (A4), and a ground indicator needs its own readability pass against the broadcast camera. Note it; do not guess it. |

### Roblox constraints

- Animation frame counts are not a clock. The contact window must be
  server-timed; the animation marker is presentation aligned to it.
- The presser nomination is per-team and belongs in the team tick alongside
  `computeTeamShape`, not in a per-footballer update (`AGENTS.md` §53).
- Human-controlled defenders get assistance shaping an approach they asked for;
  the target and the decision to challenge stay the player's (`AGENTS.md` §2).
- Distance constants transfer as ratios of pitch dimensions only.

### Not researched

`_InterfereCommand` (the AI's standing-challenge decision) was located but not
read in full. `goalie_default.cpp` remains unread. Neither blocks the decisions
above; both are the next stops if standing-tackle tuning or keeper behaviour
proves inadequate.

---

## Revision — corrections after implementation and playtest

Recorded rather than edited in above, because the errors are instructive and a
future reader should see what the first pass got wrong.

### Correction 1 — decision P1 was wrong about what was missing

The table above marks "one nominated presser" as **PORT CLOSELY** and treats it
as the headline gap. It was already implemented. `chooseDesignatedPlayer` in
`AIService` ranks candidates by time-to-point, weights by a per-position
`PressWillingness`, applies hysteresis, and nominates a single presser plus one
bounded support defender that is documented as never challenging.

Measured before changing anything, defenders closing on the carrier at once:

| defenders closing | share |
| --- | --- |
| 1 | 52.9% |
| 2 | 11.8% |
| 3 or more | 0% |

So the structure matched the reference already, and the initial conclusion
drawn from that — that pressing needed no change — was also wrong, because the
metric was measuring the wrong thing.

### Correction 2 — the actual gap was the approach, not the nomination

**CONFIRMED FROM SOURCE** (`playercontroller.cpp` `_MovementCommand`). For the
nominated presser, `forceMagnet` sets `haste = 1.0`, drives movement through
`AI_GetToBallMovement`, and sets `autoBias = 1.0` — a total override toward the
ball. There is no angle test, no dwell and no standoff anywhere on that path.

Beyond 90 instead aimed its presser at a containment point 3.2 studs goal-side
of the CARRIER and only went for the ball after a 1.1s timer. Measured, that
left the nearest defender averaging **9.4 studs** from a ball a tackle reaches
at 5.6 — on average permanently out of range of the challenge it was supposed
to be making. That, not the number of pressers, is what read as passive.

After magnetising the presser to the ball:

| | before | after |
| --- | --- | --- |
| nearest defender within tackle range | 37.8% | **47.4%** |
| within 3.2 studs | 10.7% | **17.3%** |

### Correction 3 — the reference's gate replaces Beyond 90's, it does not stack

First attempt added `CouldWinABallDuelLikeliness` on top of the existing
gates — score ≥ 0.42, contain ≥ 0.55s, reaction delay 0.2s. Tackles **fell from
3 to 1** across matched 100-second samples, because a challenge then had to
clear every one of them.

GameplayFootball has no such stack: `_InterfereCommand` refuses below 0.2 duel
likeliness and otherwise challenges, with no dwell, no score gate and no
reaction delay. Reducing Beyond 90's gates to match brought tackles to 5.

**The lesson generalises:** porting a reference's test without porting the
structure it sits in can invert the intended effect.

### Correction 4 — `CouldWinABallDuelLikeliness` is angle and nothing else

Worth stating plainly because the first pass assumed it was more. The whole
function is:

```
dot = OppBetweenBallAndMeDot() * 0.5 + 0.5
return 1 - dot
```

The authors tried folding relative ball distance in and abandoned it; the
attempt is still present, commented out, with "doesn't really seem to work all
too well". Ported as `TackleEvaluator.BallDuelLikeliness`.

---

## Second footage reference

`ref/efootball pressing and slide tackle.mp4` (87s, 832x384, 60fps, eFootball
mobile). Local frame extraction only; never uploaded.

**OBSERVED FROM FOOTAGE.** A slide at ~21.4s, then its aftermath:

- The slider is **on the ground for roughly 1.75 seconds** and remains a
  physical presence there.
- **Control switches away from the slider** to another defender while he
  recovers.

**INTERPRETATION.** The cost of a slide in the reference is mostly the time out
of the play, not the tackle's own duration.

**RECOMMENDATION.** Beyond 90's commitment attribute lasts `SlideSeconds`
(0.55), after which the AI resumes steering while still nominally recovering —
so a Beyond 90 slider gets up and runs almost immediately. Extending the
committed ground time toward the reference's is the outstanding change here.

The control switch does **not** transfer: Beyond 90 is one human per footballer
by design (`AGENTS.md` §2), so there is no second defender to switch to.

---

## Design decision — the held press challenges

Recorded here because this research was cited on both sides of it.

The automatic challenge on a held press was removed in an earlier revision,
partly on the strength of the first footage reference showing MATCH UP, DASH &
PRESSURE and TACKLE as three distinct controls. It has since been restored by
explicit design decision.

The footage observation stands; it was read too narrowly. A tap and a hold
remain distinct acts — the tap challenges at a moment of the player's exact
choosing — and nothing required the hold to be passive in order to stay
distinct from it.

The agency question is now settled in `AGENTS.md` §2 under "A Held Input Is
Itself A Decision": a sustained input is a choice the player is making
continuously, and releasing it ends the behaviour at once.

The lunging risk is handled by the duel-angle gate above rather than by
removing the feature, which is the same thing the reference does.
