# Milestone 6.9 — Goalkeeper Mechanics

This is the working prompt for the milestone. It gathers **everything concerned
with keeper mechanics** into one body of work, rather than continuing to patch
the keeper one report at a time.

Note the numbering convention (`AGENTS.md` §56): `docs/milestones/` numbers are
assigned as work is commissioned and do **not** correspond to the roadmap in
§54. This is not §54's 6.9 (Ranked / Divisions / Seasons). The relevant roadmap
entry for dependency purposes is §54 / 5.5 "Goalkeeper Gameplay".

---

## 0. Standing constraints

These carry over and are not negotiable.

- **Do not commit. Do not push. Do not stage files. DO NOT CREATE A GIT COMMIT.**
- **Local-first visual QA.** Do NOT create Roblox-hosted screenshots or QA
  assets. Do NOT use any Studio capture workflow that may create a persistent
  Roblox asset (`AGENTS.md` §57).
- **Reference material is development-only.** `ref/EA FC 26 Pro Clubs goalkeeper
  pov.mp4` and every other file in `ref/` must NOT be uploaded to Roblox, copied
  into a Roblox-hosted asset, or added to runtime assets. Extract frames locally
  with ffmpeg and **look at them** before building anything meant to match them
  (`AGENTS.md`, "Read The Reference Before Reproducing It").
- **Test in Roblox Studio.** `rojo build` only serialises — it does not compile
  Luau. Verify with a module-require probe **and** by executing the changed
  logic with numeric assertions, then a real play session.
- **Beyond 90 leans arcade.** Prioritise mechanics that look and feel good over
  simulation accuracy.
- **Optimise for mobile as well as desktop.**
- **Do not make drastic changes to anything not asked for.**
- Be efficient with usage. If you approach a limit, finish the current atomic
  change, leave the tree buildable, and report: Completed / In Progress /
  Runtime Tests Completed / Remaining Work / Exact Continuation Point.
- GameplayFootball reference clone is at `/d/repos/GameplayFootball`, branch
  `windows`, commit `1dc1518abd0ffaa349c7e1a53ded6ba19213c73f`. **Do not
  re-clone it.** It must never enter `src/` or be mapped into Studio
  (`AGENTS.md` §27, "Runtime Separation").

---

## 1. Why this is a milestone and not three bug fixes

The keeper has now been patched across several sessions — dive tilt, dive
recovery, get-up clips, side-step thresholds, indicator arcs, re-handling grace,
distribution distances. Individually each change was defensible. Collectively
the keeper still does not work, and the failures keep returning in a different
costume.

That pattern is the signal. `AGENTS.md` §26 is explicit:

> If playtesting repeatedly demonstrates that the current abstraction is wrong,
> replace the smallest necessary part of that abstraction before adding more
> patches.

The keeper's problem is architectural, and section 3 states it precisely.

### Confirmed history worth not repeating

Three separate attempts to fix "the dive is broken" targeted the wrong layer:

1. The dive was written on the **server** as a velocity write — discarded,
   because a player's character is network-owned by their client.
2. It was applied on the client but the humanoid was **skipped** rather than
   driven — a `Humanoid` keeps applying its last `Move`, so skipping it froze a
   brake on.
3. The animation and the body roll were each recomputing the dive's side from a
   CFrame that the roll itself was rotating — a feedback loop.

Only the third was diagnosed correctly, and it was **still not the cause**. The
actual cause of the most recent failure was upstream:
`FootballerRegistryService.GetHumanActor` returns a **new table on every call**,
so every dive guard (`GoalkeeperDiveUntil`, recovery, cooldown) was written to a
throwaway and lost. For a human keeper `IsDiving` was permanently false and each
request launched a fresh dive on top of the running one.

**Lesson to carry into this milestone:** when keeper presentation flip-flops,
check whether the STATE it reads is flip-flopping before rewriting how it is
read. Two passes were spent downstream of a server that was genuinely restarting
the dive.

---

## 2. Reported symptoms (the acceptance list)

Each is a live player report. The milestone is not complete while any remains
true.

| # | Symptom | Reported |
|---|---------|----------|
| K1 | Dive moves the keeper **backwards instead of sideways** | current |
| K2 | Dive "glitches" — body ends in a state it does not recover from cleanly | recurring |
| K3 | Moving **sideways** does not strictly play the side-step | 3x |
| K4 | Moving **backwards** does not play jog-backwards | current |
| K5 | Side-step and jog **flip-flop** at ~10 Hz during ordinary movement | current, log-confirmed |
| K6 | Keeper camera angle / framing (Pro Camera keeper variant) | previously reported |
| K7 | Ground indicators must match the EA FC reference | partially done |

### K5 is log-confirmed and is the thread to pull

```
22:03:40.735  JogForward      angle=-1.7  speed=16.0  forward=1.00 right=-0.03
22:03:40.809  KeeperSideStep              speed=14.2
22:03:40.961  JogForward      angle= 5.5  speed=16.0  forward=1.00 right=0.10
22:03:41.072  KeeperSideStep              speed=15.5
22:03:41.183  JogForward      angle=-5.4  speed=16.0  forward=1.00 right=-0.09
```

Five clip changes in 450 ms while the **input is essentially pure forward**
(`forward=1.00`, `right` about 0). The selector decomposes travel against
`rootPart.CFrame`, and the keeper's facing is overridden toward the ball
(`GoalkeeperConfig.Human.FacingOverrideThreshold`, `MaximumFacingArcDegrees`).
So body-relative "lateral" oscillates across the side-step threshold while the
player is doing nothing unusual.

**Leading hypothesis (INFERENCE, not yet confirmed):** keeper clip selection is
measured in a frame that is itself being rotated by the facing override. The
same shape of bug as the dive-roll feedback loop, one layer up.

**Confirm it before fixing it.** The keeper log line currently prints
`forward=0.00 right=0.00 angle=0.0` for every keeper state — the keeper branch
never populates them, which is why this went unseen across three attempts.
**Task 0 is to fix that diagnostic.**

---

## 3. The architectural finding — how GameplayFootball couples animation to mechanics

CONFIRMED FROM SOURCE. Repository `https://github.com/vi3itor/GameplayFootball.git`,
branch `windows`, commit `1dc1518abd0ffaa349c7e1a53ded6ba19213c73f`, read
2026-09-02.

### 3.1 The animation *is* the movement

`src/onthepitch/player/humanoid/humanoidbase.cpp:703-708` — the player's
position for a frame is:

```
animApplyBuffer.position = startPos
                         + currentAnim->actionSmuggleOffset
                         + currentAnim->actionSmuggleSustainOffset
                         + currentAnim->movementSmuggleOffset
                         + currentAnim->positions.at(currentAnim->frameNum);
```

`currentAnim->positions` is the clip's **baked root motion**, and it is the
primary term. There is no separate "move the character controller, then play an
animation on top" step. Direction, distance and cadence all come out of the clip.

### 3.2 Selection is by physical continuity, not by a state name

`SelectAnim` (`humanoidbase.cpp:1374`) builds a `CrudeSelectionQuery` keyed on
the body's **current physical state**, not on a gameplay state label:

- `query.incomingVelocity = spatialState.enumVelocity` (idle / dribble / walk /
  sprint), with `_Strict` and `ForceLinearity` set
- `query.incomingBodyDirection = spatialState.relBodyDirectionVec`, also strict
- `query.foot` — deliberately the **opposite** foot to the one currently planted,
  so strides alternate
- `incoming_special_state` / `outgoing_special_state` — a get-up can only follow
  something that ended in a fall

Quadrant and outgoing-angle scoring (`humanoidbase.cpp:1127-1228`) then narrows
the set. The question the engine asks is *"which clip can physically continue
from the body I have right now?"* — not *"what state am I in?"*.

### 3.3 The gap to football intent is closed by bounded "smuggle" offsets

`Humanoid::CalculateMovementSmuggle` (`humanoid.cpp:2326`) computes a correction
from the predicted ball position at `futureTime_ms` and the front-of-foot
offset, ramped in across the clip by

```
frameBias = (currentAnim->frameNum + 1) / (float)(anim->GetEffectiveFrameCount() + 1)
```

(`humanoidbase.cpp:688`). The clip supplies the motion; a bounded, gradually
applied offset bends it toward where football needs the player.

Critically it **refuses** (returns zero) when the player is not the designated
possession player, when the clip is on a touch frame, in any special state, out
of play, in a set piece, or when there is a ball retainer
(`humanoid.cpp:2330-2332`). Assistance is **off during committed actions**.

### 3.4 What this means for Beyond 90's keeper

Beyond 90 currently has **three independent authorities on where the keeper's
body goes during a dive**:

| Authority | Lives in | Decides from |
|---|---|---|
| Humanoid drive (`WalkSpeed` + `Move`) | `MovementController` | published `DiveVelocity` |
| Body roll (`rootPart.CFrame` write) | `MovementController` | published `DiveVelocity` + body facing |
| Clip choice (`KeeperDiveLeft`/`Right`) | `AnimationController` | published `DiveVelocity` + body facing |

The keeper dive clips have **no root motion** — stated by the animator: *"the
animations have no x or y movements"*. So unlike GameplayFootball the clip
contributes nothing to the motion, and the three authorities above must agree by
construction. They do not, and K1 ("moves backwards instead of sideways") is what
disagreement looks like.

This is the abstraction to replace. **Do not add a fourth corrector.**

---

## 4. Required reading before implementing

1. `AGENTS.md` in full — especially §2 (a held input is a decision), §11 (all the
   goalkeeper subsections), §32 / §33 (networking and assistance), §48 (shared
   execution).
2. These `AGENTS.md` lessons, all earned on this exact system:
   - "A Humanoid Cannot Be Bypassed, Only Driven"
   - "Server-Approved, Client-Applied Motion"
   - "Rotation The Code Applies, The Code Must Take Away"
   - "A Snapshot Cannot Hold State"
   - "A Value With Two Owners Has One Real Owner"
   - "Two Assists Must Not Fight Each Other"
   - "Read The Reference Before Reproducing It"
   - "A Goalkeeper Is Only A Goalkeeper Inside Their Own Area"
3. `ref/EA FC 26 Pro Clubs goalkeeper pov.mp4` — extract frames, look at them.
4. GameplayFootball source per §3. Record further findings under
   `docs/research/gameplay-football/` with commit SHA and date, per §28.

---

## 5. Work breakdown

### Task 0 — Make the keeper observable (do this first)

Non-negotiable prerequisite. The keeper animation log line currently reports
`forward=0.00 right=0.00 angle=0.0` for every keeper state, which is why K3 / K5
survived three fix attempts.

- Populate the keeper branch log with the **real** decomposition: body-relative
  forward and lateral speed, the travel angle, the frame it was measured in, and
  the facing-override state.
- Add the dive's published direction and the latched clip side to the dive log.
- Verify by reading a play-session log and confirming the numbers move when the
  keeper moves.

**Acceptance:** a 60-second keeper session log is sufficient to explain every
clip change without guessing.

### Task 1 — One authority for keeper body motion (K1, K2)

Decide explicitly which layer owns the dive's translation and rotation, and make
the others read from it rather than recompute it.

- Establish a single server-published dive frame (direction, side, start stamp,
  duration) that the client **reads and does not re-derive**.
- Drive translation through the Humanoid, per the existing lesson.
- Own the full rotation arc: apply it, and unwind it on a stated recovery,
  including `ChangeState(GettingUp)` if `FallingDown` was entered.
- Investigate K1 specifically: a keeper travelling **backwards** on a dive means
  the drive direction and the body frame disagree in sign or basis. Prove which
  with Task 0's diagnostics before changing anything.

**Acceptance:** a dive to the left travels left and a dive to the right travels
right, from any keeper facing; the body ends upright and controllable; no clip
change occurs mid-dive.

### Task 2 — Keeper locomotion clip selection (K3, K4, K5)

- Choose the measurement frame deliberately and document why. A frame the facing
  override rotates is not a stable basis for a left/right decision; the goal line
  is a candidate.
- Sideways travel plays the side-step. Backwards travel plays jog-backwards
  (sped up, per the existing convention). Forward travel plays jog / sprint.
- Add hysteresis so a borderline direction cannot alternate at frame rate.
  GameplayFootball's `_Strict` + `ForceLinearity` continuity constraints are the
  reference principle: the next clip must be able to continue from the current
  body, which inherently resists thrash.

**Acceptance:** holding a direction produces one clip and holds it; the K5 log
pattern (five changes in 450 ms on a steady input) cannot be reproduced.

### Task 3 — Reconcile the keeper's boundaries and defaults

Re-verify against `AGENTS.md` §11 that these still agree and none has drifted:

- Handling legality, keeper controls and keeper animation all read
  `IsInsideOwnPenaltyArea` against the same published pitch frame.
- Keeper defaults to Pro Camera; the keeper Pro Camera framing clears the goal
  frame (check the arithmetic in §11 before and after any change) — **K6**.
- A ball in a keeper's hands is possession, not a loose ball.
- A keeper cannot catch their own distribution.
- Attacking inputs belong to the keeper only while the ball is in hand.

### Task 4 — Indicators against the reference (K7)

Current state: three unequal arcs (`6-66`, `79-101`, `114-174` degrees, 13-degree
gaps) in `GoalkeeperConfig.Indicators.HoopArcs`, segments distributed by arc
length. Verify against extracted reference frames and close out the target ring
and the arrow.

### Task 5 — Animation assets (blocked, track only)

Cannot be authored or uploaded from here. Record what is needed:

- Jog-backwards for the keeper if the sped-up outfield clip proves inadequate.
- Nothing else is blocked on new assets — see the decision below.

---

## 5A. DECIDED — Beyond 90 does not adopt clip-authoritative motion

This closes the question §3.4 raises. Decided 2026-09-02; revisit only with new
evidence, not on preference.

**Take from GameplayFootball:**

- **One authority per committed action.** The real lesson of §3, and it needs no
  root motion whatsoever.
- **Continuity-based selection with hysteresis** — the next clip must be able to
  continue from the body that exists now (§3.2). This is what kills K5.
- **Assistance refused during committed actions** — the
  `CalculateMovementSmuggle` refusal list (§3.3). Beyond 90 already half-does
  this; making it explicit prevents another "Two Assists Must Not Fight Each
  Other".
- **A clip publishes its own duration** — already adopted for the keeper get-up,
  and it worked.

**Reject: clips authoritative over position.** Three reasons, in order of how
hard they are to argue with:

1. **Roblox has no root motion.** Animations drive `Motor6D` joints. Including
   the `HumanoidRootPart` in a clip displaces the RENDERED rig relative to its
   physical position; the physics capsule and the replicated position do not
   move, so the character snaps back. Root motion would have to be emulated in
   code regardless.
2. **Clips evaluate on the client.** The server sees "this AnimationId is
   playing", not a transform stream. Clip-determined position is
   client-determined position, which §17 and §32 rule out for competitive state.
3. **The library is far too small.** Beyond 90 loads 17 tracks
   (`tracks=17` in the session log). GameplayFootball indexes hundreds across
   velocity x body direction x foot x special state and STILL carries a
   "no applicable anim, fall back to idle" path. Continuity selection over 17
   clips would live in the fallback.

Root motion is also the largest single source of input-latency complaints in the
sports games that use it, and `AGENTS.md` §37 puts Beyond 90 on the arcade side
of that trade.

### The pattern to use instead: the clip is the REFERENCE, the code is the AUTHORITY

For the dive, and for any future committed keeper action:

- The code decides where the body goes (server-approved, client-applied, per
  §32 and the existing lesson).
- The CLIP supplies the number. Measure the clip's intended displacement once at
  load and derive the travel speed from it, rather than hand-tuning a config
  constant that has to agree with the animation by luck.

This is the same "one owner, published" shape that fixed the get-up
(`Beyond90KeeperGetUpUntil`), applied to distance instead of duration. Two
constants for one physical fact is how they drift apart — see "A Value With Two
Owners Has One Real Owner" and "A Clip Is A Better Authority Than A Timer".

Consequence for Task 1: zero-root-motion dive clips are **fine and are the
intended design**. Do not request re-authored clips to solve K1.

---

## 6. Out of scope

- AI keeper tactical behaviour beyond what is needed to test the human keeper.
- The separate open item: **AI collects the ball too easily, and pressing
  refinement** — its own GameplayFootball research pass; it does not belong here.
- Human shot launch speed (about 50 studs/s vs AI 127) — flagged, unrelated.
- Match-format scaling, clubs, ranked, progression.

---

## 7. Definition of done

- Every symptom K1-K7 is fixed or explicitly deferred with a stated reason.
- The keeper has one documented authority for body motion during committed
  actions, and the document says which.
- A play session log explains every keeper clip change without guessing.
- `AGENTS.md` gains any new lesson this milestone earns.
- Verified by module-require probe, executed-logic assertions, and a real play
  session on **desktop and mobile**.
- Nothing committed.
