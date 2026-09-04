# Milestone 6.8 — Pressing, Tackling and Slide Tackling

This is the working prompt for the milestone. It revisits roadmap §54 / 5.4
("Defending, Tackling and Shielding") with the benefit of everything built
since, which `AGENTS.md` §54 explicitly allows.

---

## 0. Standing constraints

These carry over and are not negotiable.

- **Do not commit. Do not push. Do not stage files. DO NOT CREATE A GIT COMMIT.**
- **Local-first visual QA.** Do NOT create Roblox-hosted screenshots or QA
  assets. Do NOT use any Studio capture workflow that may create a persistent
  Roblox asset (`AGENTS.md` §57).
- **Reference material is development-only.** `ref/efootball pressing.mp4` and
  every other file in `ref/` must NOT be uploaded to Roblox, copied into a
  Roblox-hosted asset, or added to runtime assets.
- **Test in Roblox Studio.** `rojo build` only serialises — it does not compile
  Luau. Verify with a module-require probe and a real play session.
- **Beyond 90 leans arcade.** Prioritise mechanics that look and feel good over
  simulation accuracy.
- **Optimise for mobile as well as desktop.**
- **Do not make drastic changes to anything not asked for.**
- Be efficient with usage. If you approach a limit, finish the current atomic
  change, leave the tree buildable, and report: Completed / In Progress /
  Runtime Tests Completed / Remaining Work / Exact Continuation Point.

### Editing note learned the hard way

Write files **in place**. Do not replace a watched file's inode (no
`shutil.move`, no write-temp-then-rename). Doing so silently detaches the Rojo
file watcher: the edit lands on disk and in `final.rbxl`, but the running place
keeps the old source and every measurement afterwards is of stale code. If a
change appears not to take effect, diff the place's `ModuleScript.Source` length
against the file on disk before believing anything else.

---

## 1. What already exists — do not rebuild it

Read these before writing anything. A surprising amount is already here, and
the milestone is a **revamp**, not a greenfield build.

**Server — `src/server/Services/DefendingService.luau` (828 lines)**

| Symbol | Line | Notes |
| --- | --- | --- |
| `DefendingService.IsRecovering` | 102 | post-challenge recovery lockout |
| `reportFoulIfContact` | 136 | foul reporting with a severity scale |
| `DefendingService.PreviewTackle` | 202 | client-facing prediction |
| `DefendingService.AttemptTackle` | 235 | standing tackle |
| `updateInterceptions` | 460 | interception scoring loop |
| `DefendingService.AttemptSlideTackle` | 611 | **slide already exists** |
| `onDefensiveRequest` | 767 | remote entry point |

**Shared — `src/shared/Config/DefendingConfig.luau` (494 lines)**
`Tackle` and `Slide` blocks; `Slide` carries `ActionType`, `SlideSeconds`,
`MaximumBallDistance`, `MaximumOpponentDistance`, `MinimumFacingDot`,
`SuccessThreshold`, `PartialThreshold` and a `SlidingAttribute`.
`DefendingConfig.Slide.Evaluation` is cloned from `Tackle` at the bottom of the
file and then overridden — keep that pattern or replace it deliberately.

Interception scoring was retuned in 6.7 and is currently
`BaseReach 3.4`, `ClosenessWeight 0.95`, `FacingWeight 0.16`, `SkillWeight 0.18`,
`CleanThreshold 0.82`, `DeflectionThreshold 0.52`, `MinimumFacingDot 0.15`.
Treat those as a tuned baseline, not as free parameters.

**Client — `src/client/Controllers/DefendingController.luau`**
`requestSlideTackle` (285), double-tap detection for the slide (65, 488-492),
and a slide lockout read from the character attribute (305).
`MovementController.luau:1079` also respects that attribute.

**AI — `src/server/Services/AIService.luau`**
`getPressTarget` (386), `getSupportPressTarget` (503), `chooseDesignatedPlayer`
(524), `collectOpponents` (773), and — added in 6.7 — `computeTeamShape` with a
continuous `PossessionBias` on `teamModel.Shape`. The pressing work in this
milestone should build on `PossessionBias`, not reintroduce a discrete
in/out-of-possession flag.

**Animation — `src/shared/Config/AnimationConfig.luau`**
Victim-side clips exist: `Tackled.Normal`, `Tackled.SlideFromFront`,
`Tackled.SlideFromBack`, with matching `RootMotion` entries
(`NormalTackled`, `SlideTackledFromFront`, `SlideTackledFromBack`).

> **The gap: there is no tackler-side animation at all.** Neither the standing
> tackle nor the slide has a clip for the player performing it. That is the most
> visible hole in the current feature and a required part of this milestone.

---

## 2. References

### 2.1 `ref/efootball pressing.mp4` — the behavioural target

**Study this first and describe what you actually see**, using the
OBSERVED FROM FOOTAGE / INTERPRETATION / RECOMMENDATION labels required by
`AGENTS.md` §28. Do not describe it from memory of football games in general.

At minimum, characterise:

- What the pressing player does versus what his team-mates do at the same moment.
- Whether pressing is one player closing down or several converging.
- The approach path — straight line, curved to show the attacker one side, or
  arriving square.
- What happens on arrival: commit to a tackle, jockey, or hold at a stand-off
  distance.
- Deceleration and body shape as the presser arrives.
- Distance at which the presser commits.
- How cover behind the presser is maintained.
- How the attacker beating the press is punished or recovered from.
- Slide tackles: when they are used, from what angle, and what follows.
- Recovery time after a slide, and how exposed the slider is.

The instruction is to **replicate this behaviour**, adapted to Beyond 90's
broadcast camera, human-per-footballer structure and arcade lean.

### 2.2 GameplayFootball — inspectable source

| | |
| --- | --- |
| Repository | `https://github.com/vi3itor/GameplayFootball.git` |
| Branch | `windows` |
| Commit | `1dc1518abd0ffaa349c7e1a53ded6ba19213c73f` |
| Clone | `/d/repos/GameplayFootball` — **already present, do not re-clone** |

Confirmed-relevant locations, verified at that commit:

| Behaviour | Location |
| --- | --- |
| Tackle collision detection | `src/onthepitch/match.cpp:1835-1838` |
| Sliding stat biasing the loose-ball outcome | `src/onthepitch/match.cpp:1606-1608` |
| Collision-animation gating | `src/onthepitch/match.cpp:1956-1978` |
| **Team pressure grant** | `src/onthepitch/teamAIcontroller.cpp:930-946` (`ApplyTeamPressure`) |
| Pressing licence consumed by the individual | `src/onthepitch/player/controller/elizacontroller.cpp:305-313` (`forceMagnet`) |
| Situation inputs for the decision | `src/onthepitch/teamAIcontroller.cpp:951-962` (`CalculateSituation`) |
| Closest-player selection | `src/onthepitch/AIsupport/AIfunctions.cpp` (`AI_GetClosestPlayer`) |
| Human input gating during a slide | `src/onthepitch/player/controller/humancontroller.cpp:53` |

Three findings from that source are already confirmed and worth carrying:

1. **Tackle contact is a frame window, not a moment.** A tackle registers only
   while the actor is in `e_FunctionType_Sliding` or `e_FunctionType_Interfere`
   *and* `GetFrameNum()` is between 5 and 28, with `distance < 2.0`. This is
   what makes a slide feel committed and mistimeable.
2. **Two simultaneous tacklers cancel.** `if (tackle == 3)` — both sides
   tackling is explicitly ignored rather than resolved.
3. **Pressing is a team-granted licence, not an individual decision.**
   `ApplyTeamPressure` grants a **500 ms** window to exactly one nominated
   player, chosen as closest to the opponent's *predicted* position
   (`opponentPos = opp->GetPosition() + opp->GetMovement() * 0.24f`), excluding
   the goalkeeper, and simultaneously assigns man-marking. Everyone else keeps
   their shape.

That third point is the structural idea of this milestone. Beyond 90 currently
lets defenders decide to press largely on their own.

### 2.3 Licence and porting permission

GameplayFootball is **Apache-2.0** with per-file notices from the original
author (*"written by bastiaan konings schuiling 2008 - 2015"*); several files
additionally declare themselves public domain.

Close porting of algorithms is **permitted for this milestone** where it serves
the football (`AGENTS.md` §27, "What May Be Ported Closely"). If you translate
closely:

1. Review the applicable licence for the specific file.
2. Preserve required notices and record attribution.
3. Mark substantial translations where required.
4. Keep translated material identifiable.
5. Document the decision in the research doc.

Do **not** port the C++ class hierarchy, engine abstractions, or the frame-count
animation model literally. Constants transfer only as ratios — do not assume
1 GameplayFootball metre equals 1 Roblox stud.

---

## 3. Pressing revamp

> **CORRECTED AFTER MEASUREMENT.** The goal below was written on the assumption
> that Beyond 90 lacked a presser nomination and that defenders swarmed. Both
> were wrong: `chooseDesignatedPlayer` already nominated one presser plus one
> bounded support, and measured play showed 1 defender closing 52.9% of the
> time and never 3 or more.
>
> The real defect was the **approach**, not the nomination — the presser aimed
> at a containment point goal-side of the carrier and averaged 9.4 studs from a
> ball a tackle reaches at 5.6. See
> `docs/research/gameplay-football/ai/03-pressing-and-tackling.md`, "Revision".
>
> Keep the requirements below for the parts that were genuinely missing; ignore
> the framing that treats nomination as absent.

**Goal: pressing becomes a coordinated team behaviour with one committed
presser and real cover behind, rather than several defenders independently
converging on the ball.**

Required:

- A **team-level pressing licence**: exactly one nominated presser per team at a
  time, granted for a bounded window and re-evaluated at team cadence, not per
  frame. Build it on `teamModel.Shape.PossessionBias` from 6.7.
- Nomination by **time-to-ball against the opponent's predicted position**, not
  raw current distance. `AIService.estimateTimeToPoint` already returns a
  momentum-aware pair; use it.
- Everyone not nominated **holds shape and covers**. Their behaviour should be
  visibly different from the presser's.
- A **stand-off distance** the presser respects rather than running through the
  carrier, with commitment to a challenge as a separate decision.
- **Approach path** shaped to show the carrier a direction, per the footage.
- Press intensity should scale with team tactics/context, not be constant.
- Human-controlled defenders must get an equivalent *assist*, never an
  automatic decision. A human presses because the player asked to; assistance
  may shape the approach, never choose the target (`AGENTS.md` §2).

Explicitly out of scope: full man-marking assignment across the team. Nominate
the presser and let existing marking do the rest unless it demonstrably blocks
the milestone.

---

## 4. Standing tackle revamp

- Replace the current instantaneous evaluation with a **committed action with a
  contact window**, following the frame-window principle above. A tackle should
  be mistimeable.
- Outcomes need to be readable: clean win, deflection, partial contact, miss,
  and foul must look different, not just score differently.
- Preserve the retuned interception scoring; do not let a tackle revamp quietly
  regress interceptions.
- Recovery after a failed challenge must matter and be visible.

---

## 5. Slide tackling

Slide is **partly implemented** (§1). Finish and revamp it.

- Contact resolved over a window, with the slider genuinely committed and
  vulnerable through the recovery tail.
- Direction and angle of approach must affect the outcome — a slide from behind
  is not the same as one from the side.
- Two simultaneous tacklers: decide deliberately whether to adopt
  GameplayFootball's cancel rule and say why.
- Ball outcome should be a real physical result, not a possession flag flip.
- Fouls, and the severity scale already in `reportFoulIfContact`, must be wired
  through — a mistimed slide from behind is the canonical card.
- AI must use the slide, and use it **rarely and appropriately**, not as a
  default challenge.

---

## 6. Animation

This is a required part of the milestone, not a follow-up.

- **Tackler-side clips are missing entirely.** Add standing-tackle and
  slide-tackle animations for the player performing them, alongside the existing
  victim-side clips.
- Roblox animations do not move the `HumanoidRootPart`. Any clip reading as a
  slide or a fall needs a matching code-driven root offset — follow the existing
  `AnimationConfig.RootMotion` pattern used by `SlideTackledFromFront`/`Back`.
- Wire semantic markers per `AGENTS.md` §39: `TackleContact`, `ActionCommit`,
  `Recover`.
- **Animation must not become the source of competitive truth.** Timing may
  determine *when* an already-valid action makes contact; it must never decide
  *whether* the action was valid.
- Any new animation asset follows §57: inspect locally, upload only finished
  production assets, wait for moderation, record in the asset manifest, and only
  then put the ID into config.

---

## 7. Networking and authority

- The server stays authoritative over possession changes, tackle outcomes,
  fouls and cards.
- The client may predict the *animation and local movement* of its own
  challenge; it may not decide the result.
- Validate every remote payload. A slide request is a request.
- Respect the controlled-ball ownership model in `AGENTS.md` §32: when a tackle
  takes the ball, the server reclaims ownership before it is handed on.

---

## 8. Cross-platform

- Touch: slide tackling needs a real control that does not collide with the
  existing action pads, and must clear the ~48 px touch target floor
  (`Theme.MinimumTouchTarget`).
- Controller: bindings and prompts.
- Keyboard: the current double-tap gesture should be reviewed — decide whether
  it survives the revamp and say why.
- HUD prompts are contextual: show defensive actions out of possession, not all
  controls all match (`AGENTS.md` §40).

---

## 9. Testing and acceptance

`rojo build` succeeding is not acceptance. Required evidence:

1. Module-require probe: 94 Beyond 90 modules, 0 failures.
2. A real play session with zero runtime errors.
3. A live 3v3 (`Quick3v3` — note that the `Development` mode assembles no AI
   outfielders, so AI work is invisible there).
4. Measured before/after for: tackle success rate, foul rate, interception rate
   (must not regress), and **how close the presser actually gets** — the share
   of samples where the nearest defender is inside tackle range of the ball.

   Counting *how many* defenders converge is the wrong metric and was the first
   pass's mistake: Beyond 90 already pressed with one man and it still felt
   passive, because that one man stood off. Distance-to-ball is the number that
   moved when the behaviour improved.
5. Slide tackle exercised by both a human and an AI.
6. Side-by-side comparison against `ref/efootball pressing.mp4` — does the
   *behaviour* resemble the reference principle, not just work?

Answer honestly: **does pressing now read as a team defending, or as several
footballers chasing a ball?**

---

## 10. Do not regress

- Interception tuning from 6.7 (§1).
- Team shape / `computeTeamShape` and the continuous `PossessionBias`.
- The offside clamp now applied to every attacking outfielder — offsides went to
  zero over a 120 s window and must stay low.
- Possession handoff health: `lostControl=0 (distance=0 unexpected=0)`.
- Restart and foul flow, referee whistles, card handling.
- Goalkeeper behaviour.
- Menu and HUD readability work from 6.7 (readability floor of 11 px, ~48 px
  touch targets, focus rings drawn only on the focused control).

---

## 11. Documentation

- Research goes in `docs/research/gameplay-football/ai/` as
  `03-pressing-and-tackling.md`, following the format of `01` and `02`:
  provenance table with commit SHA, files and line ranges inspected, symbols,
  CONFIRMED / INFERENCE / RECOMMENDATION labels, and a decision table using
  KEEP EXISTING / PORT CLOSELY / ADAPT / REPLACE / OMIT / DEFER.
- Footage findings use OBSERVED FROM FOOTAGE / INTERPRETATION / RECOMMENDATION.
  Never describe footage as source-confirmed behaviour.
- Stable architectural outcomes go in `docs/architecture/`.
- Record any close translation and its attribution.

---

## 12. Order of work

1. Study `ref/efootball pressing.mp4` and write up the observations.
2. Inspect the GameplayFootball locations in §2.2; trace complete call chains,
   not isolated functions.
3. Write `03-pressing-and-tackling.md` with decisions.
4. Read the existing Beyond 90 implementation in §1 in full.
5. Pressing licence and cover behaviour.
6. Standing tackle contact window.
7. Slide tackle completion and revamp.
8. Tackler-side animation and markers.
9. Fouls, cards, recovery.
10. Cross-platform controls.
11. Measure against §9. Report honestly.
12. **Stop.** Do not continue into the next milestone.


---

# Closing record — 2026-09-01

## Delivered

- Pressing rebuilt on GameplayFootball's structure: unconditional magnet to the
  ball for the nominated presser, and `TackleEvaluator.BallDuelLikeliness` as a
  close attributed port of `CouldWinABallDuelLikeliness()`.
- Slide tackle: committing window, server-owned lockout, AI slide, duel gate at
  a higher threshold than the standing challenge.
- Auto-challenge on a held press, with the reasoning recorded in AGENTS.md §2
  (`A Held Input Is Itself A Decision`).
- Contact window (windup + committed window) replacing the instant resolve.

## Corrections made after playtest

Each of these was a wrong call caught by runtime evidence, recorded so the same
mistake is not repeated:

1. **Bolting the duel gate ON TOP of the existing gates** cut tackles 3 -> 1.
   The reference has ONE gate; Beyond 90 briefly had three.
2. **Applying the duel angle to MOVEMENT as well as the challenge.** The
   reference's `forceMagnet` is unconditional. Pressing proximity only improved
   once movement was ungated.
3. **Judging pressing by "how many defenders converge".** The metric was wrong.
   The right one is how close the presser actually gets.
4. **`ContainRange = 13`** capped the defender at 72% speed from 13 studs out,
   so the whole approach ran at a jog. The curved recovery approach that gets a
   defender round to the front existed the entire time -- it was simply never
   run at pace. Now 8, just outside the standoff.

## Goalkeeper work folded in

- Dive is left mouse click; the side comes from the direction pressed within
  `DiveAimGraceSeconds` after the click. Tackle stays bound as a secondary.
- Dive motion is applied by the owning client from a server-published launch.
  See AGENTS.md `Server-Approved, Client-Applied Motion` -- this was the cause
  of dives that logged correctly and moved nothing.
- Carrying the ball out of the area is a handling offence.
- Outfield controls outside the area.
- Turn bounded to a half-circle centred on pitchward.
- Drop kick on Shoot while holding; the HUD had advertised this control for
  some time with nothing bound to it.
- Keeper locomotion clips speed up with movement instead of handing over to the
  outfield sprint set.

## Not done

- **Tackler-side and dive animation assets.** Blocked: cannot be authored here.
  The semantic hooks (`Beyond90GoalkeeperDive`, `ActionCommit`) are in place for
  when they exist.
- **Mutual-challenge cancel (T3).** Two players challenging in the same window
  should cancel; currently resolved independently.
- **Touch control for slide.** Desktop and gamepad only.
- **Cards.** Fouls are reported; no disciplinary consequence.
- **Slide ground time.** Reference is ~1.75s; Beyond 90 uses 0.55s. Deliberate
  arcade choice, revisit only if slides read as too cheap.

## Verification status

Static verification is complete: 95 modules require cleanly, and every config
relationship above was measured in a live Studio session.

Live gameplay verification of CLIENT-side behaviour was NOT possible from this
environment. Client gameplay controllers only initialise through the UI flow,
and firing the mode/position/kick-off remotes directly advances the match state
without assembling the AI. Everything client-side here -- the dive, the click
binding, the controls swap, the facing arc -- is implemented and loads cleanly
but is unverified in play. It needs a human session.


---

# Second playtest pass — 2026-09-01

Six defects reported, all traced to a specific cause rather than tuned around.

| Reported | Cause |
| --- | --- |
| Keeper dive invisible | A Humanoid keeps applying its last `Move` every step, so skipping its update froze it on an active brake. Now driven through the humanoid. |
| Keeper plays outfield sprint | Keeper clips handed over to outfield locomotion above 2.6 studs/s. Now kept inside the area at any speed, sped up instead. |
| Keeper indicators invisible | Placed at `PitchGroundY` (0.20) + 0.06. Measured: the rendered pitch surface is at **1.70**. They were 1.4 studs underground. Now raycast. |
| Everyone swarms the holding keeper | `getControllerActor()` reports nobody while a keeper HOLDS the ball, so the state fell to LooseBall and both sides were sent to chase. A held ball is now possession. |
| Cannot take a goal kick | `FootballActionController` refused every attacking action for anyone with the keeper role, and the keeper's own reroutes need the ball in hand. Both declined it, so the nominated taker had no way to kick a placed ball. Now only defers while actually holding. |
| Auto-press does nothing | The held press fired a tackle request every frame; the server refused all but the first. Rate-limited and gated on the committed window. |

## Standing lesson

Four of the six were a wrong assumption about a value or a system boundary, not a
tuning error — a height that was not the height, a possession test that did not
cover possession, a role gate that was too broad, a request rate nobody bounded.
Measuring the value before trusting it would have caught all four. The pitch
surface case is now written into AGENTS.md, because it had already caused the
same bug twice.


---

# Third playtest pass — 2026-09-01

| Reported | Cause |
| --- | --- |
| Indicators wrong vs reference; double circle | Built from a description, not the footage. Frames show ONE thin ring plus two dive arcs; the build had 16 spokes, a chevron and a second ring at the resting position — the second ring is the double circle. Rebuilt from extracted frames. |
| Only the sidestep plays | Previous fix gated the handover on the penalty area, so the keeper never returned to outfield clips. Now chosen by direction of travel: across = sidestep, toward/away = jog and sprint. |
| Side dives don't work, forward does | The aim was re-read from input at SEND time, up to 0.2s after the click. A tapped A/D is already released by then, so it fell back to facing — which is forward. The window is now polled and the first direction seen is captured. |
| Press not fast enough, doesn't get in front | `Containing` measured distance to the press TARGET (goal-side of the carrier), not to the carrier, so a distant defender was flagged as jockeying and capped below sprint. Plus `SlowDistance = 9` bled speed off from 9 studs out, bottoming at 30%. |

Measured assist magnitude by gap to carrier (20/14/10/8/6/5 studs):

    before   1.0  1.0  0.7  0.6  0.3  0.2
    after    1.0  1.0  1.0  0.7  0.7  0.4

## Standing lesson

Every defect this pass was a wrong reference frame — a value measured against
the wrong thing, or a feature built against a description of the footage rather
than the footage. Both are now written into AGENTS.md.

---

# Fourth playtest pass — 2026-09-01

| Reported | Cause |
| --- | --- |
| Indicators still wrong | Third pass still drew a ring at the keeper's FEET; the footage has bare grass under him. Rebuilt again from the frames: a vertical hoop around the body (legs, over the head, legs), a ground ring at the resting position that hides when he is standing in it, and an arrow between them. |
| Keeper camera not steep enough | The keeper preset never reached the camera. With the mouse locked — the normal state — pitch was `mousePitch` alone, seeded from the OUTFIELD preset and moved only by mouse delta. Height, distance and FOV switched to the keeper rig; the angle never did. Re-seeded on rig change; 14° → 36° on-ball, 19° → 40° off-ball. |
| Drop kick / throw do nothing | Both fired correctly and the keeper re-caught the ball on the next frame: a distribution releases at the keeper's own hands, so for one tick it is a free ball inside the 6.4-stud assisted-save radius. Log shows the whole round trip in 2 ms. Added a release grace, lifted by anyone else's touch. Affected AI keepers too. |
| F does not kick a long goal kick | `Shoot` was absent from `GoalKick`'s allowed actions, so the key was refused with `restart-not-yours` on the restart it most belongs to. Allowed, and routed to a long clearance rather than the shot planner — the attacking goal is 341 studs away. |
| `goalkeepers 1/2` with a human keeper | The human actor table had no `Position` field, so `actor.Position == "Goalkeeper"` was false for humans and assembly counted a human keeper as an outfielder. |
| Players climb over each other | Humanoids step onto anything within step height, and a torso is inside it. Footballer↔footballer collision removed; separation steering added in its place. |
| Settings fonts and glow wrong | `UIStroke` defaults to `Contextual`, which outlines the GLYPHS of a text control rather than its border — fattening the letters into a different-looking typeface and haloing the selected row in `Theme.StrokeBright` blue. Pinned to `Border` in the shared helpers, which fixes all three named sections at once. |

Added, not fixed: keeper dive clips (left 85231153864936, right 108977133363146),
chosen from the approved dive velocity and excluded from the outfield handover —
a forward dive at 27 studs/s was being animated as a sprint. The clips carry no
translation, so the fall is a code-driven roll about the travel axis, verified to
tip the keeper the way they dive from three different facings. Backward sprint
for the keeper now plays the backward jog clip sped up rather than the
forward-only sprint clip.

## Standing lesson

The two that had been reported before were not tuning misses. The camera had a
second owner for the value being tuned, and the indicators had been built from a
description of the footage twice running. Both failure modes are now written into
AGENTS.md: find every writer before tuning, and open the reference before
reproducing it.

The drop kick is the pass's best catch: it had been "working" all along — the
log said so, on every attempt — and the thing that undid it happened two
milliseconds later, on a different code path.

---

# Fifth playtest pass — 2026-09-02

| Reported | Cause |
| --- | --- |
| Keeper glitches after diving | The dive tipped the body 78° and released it. `AutoRotate` is yaw only and nothing unrolls a Humanoid, so the keeper stayed lying down; a tipped Humanoid reports `FallingDown`, which reads as airborne, so the animation flip-flopped `KeeperIdle`/`AirborneFallback` for eleven seconds after one dive while the body slid. Now unwound over a stated stand-up window, with `ChangeState(GettingUp)` to leave the fallen state. |
| Dive covers too little ground | 27 studs/s over 0.62s is ~9 studs against a standing reach of 3.2 — committing bought almost nothing. 38 over 0.78s is ~16. |
| Pro cam too far | 25 studs back at 78° field made the keeper a speck. 16/14 at 70°, keeping the downward angle from the previous pass. Far-goal check still holds (top edge +1°, reach 802 studs against a 341 stud pitch). |
| Keeper can't rotate near a post | Facing was pinned to the ball unconditionally and the arc clamp is centred on pitchward, so a ball near a post held the keeper against the edge of the arc. Steering now overrides tracking and tracking resumes on release. |
| Forward dives | Removed. A bare click now commits to the side the danger is on — the published threat point, else the ball — resolved across the goal line only. |
| Keeper doesn't open in Pro Cam | A stored Settings default outranked the role, and the late-role watcher was gated on there being no stored choice, so a player with any saved camera could never get it by either path. Role now wins. |
| No way to drop/pick up the ball | Added R as a toggle. Drops with no launch velocity, so the re-handling grace (which only opens on a distribution) does not block picking it straight back up. |
| Goal kick too short | It was borrowing the drop kick's 96/34 — 33 studs of carry, bouncing 0.3s after the foot. Sized from the pitch instead: 125/100 carries 127 studs with 1.02s of airtime, landing 30 studs short of halfway at 125 studs/s and rolling into the far half. |
| Side step too fast | Playback was pinned at its 2.30 ceiling almost permanently. Reference speed 7 → 11 and ceiling 2.3 → 1.45. |
| Ghosting through players | Removing the collision pair was the wrong fix and is reverted. Separation widened (3 → 4.2) and strengthened (0.45 → 0.6) so contacts are rarer instead. |
| V still not working | Separation was steering the presser away from the man being pressed — the two assists fought, and the only trace was `rejected=ball-out-of-reach`. The press target is now exempt from separation while the key is held. |
| Hoop should be three parts | Split into three arcs at 78% fill, per the reference. |
| Arrows should be actual arrows | Replaced the dash run with chevrons — two angled bars meeting at a point, stacked along the line. |

## Standing lesson

Two of these were self-inflicted by the previous pass, and both were the same
kind of mistake: a fix written against one case without checking it against the
systems already in place. Removing collision fixed climbing and broke contact;
separation fixed overlap and broke pressing. Neither logged anything wrong.

Both are now written into AGENTS.md, along with the Humanoid roll rule — a
Humanoid will not undo a rotation the code applied, and assuming it does leaves
the character lying on the pitch.
