# Beyond 90 Development Instructions

## 1. Project Identity

Beyond 90 is a competitive multiplayer football experience being developed by
Furreal Interactive under Furreal Productions.

The core vision is:

> The ultimate football platform on Roblox where every player on the pitch
> is controlled by a real player.

Beyond 90 is NOT intended to simply be another Roblox football game.

The game should emphasize:

- Real-player teamwork
- Position-based gameplay
- Tactical decision making
- Competitive progression
- Multiple match sizes
- Authentic football presentation
- Social experiences
- Long-term clubs and communities

Every major system should support this vision.

---

# 2. Core Gameplay Principle

Beyond 90 is **human-first**, not human-only.

The ideal competitive experience remains:

    ONE FOOTBALLER
        ↓
    ONE REAL ROBLOX PLAYER

whenever the game mode, player population and match conditions allow it.

However, AI-controlled footballers are an approved part of Beyond 90's
long-term product and development strategy.

AI footballers may be used for:

- Development testing when enough human testers are unavailable
- Training environments
- Tutorials
- Single-player modes
- Practice matches
- Filling incomplete teams where the ruleset allows it
- Temporarily replacing disconnected players where appropriate
- Goalkeeper roles where a mode permits or requires AI goalkeeping
- PvE or special modes
- Future offline-like or solo football experiences where technically feasible

The existence of AI must NOT change the core competitive identity of Beyond 90.
When enough real players are available, authentic competitive modes should
prefer real players over bots.

AI fill behavior may differ by ruleset. For example:

- Casual modes may freely fill empty team slots with AI.
- Training and single-player modes may rely heavily on AI.
- Ranked or serious club competition may use stricter human-only rules,
  limited AI fill, or temporary AI replacement depending on future design.

Do not assume every future competitive mode must allow AI fill simply because
the AI system exists.

AI footballers must use the same underlying football rules and gameplay
mechanics as human-controlled footballers wherever practical.

Avoid creating a separate "fake football" path where bots:

- Teleport into position
- Directly set impossible ball outcomes
- Ignore acceleration or collision rules
- Receive hidden physics advantages
- Shoot or pass through privileged APIs unavailable to human players
- Possess perfect reaction time merely because they are AI

AI may choose football decisions for the AI-controlled footballer.

Human-control assistance may NOT choose football decisions for the human.

This distinction is important:

    HUMAN PLAYER
        ↓
    chooses tactical / football intent
        ↓
    assistance helps execute that intent

while:

    AI FOOTBALLER
        ↓
    AI chooses tactical / football intent
        ↓
    the same gameplay execution systems carry it out

Human-controlled football does NOT require every low-level movement or
ball-contact correction to come directly from raw player input.

Bounded assistance may be used to help a human-controlled footballer execute
the football action the player is already attempting.

Examples may include:

- Subtle movement correction toward an intended ball contact
- Orientation assistance for a control touch
- Contact-position adjustment
- Touch timing assistance
- Input buffering
- Safe local prediction

Such assistance must preserve the player's tactical and directional intent.

For a human-controlled footballer, the game must NOT decide on behalf of the
player:

- Where they should attack
- Who they should pass to
- Whether they should pass
- Whether they should shoot
- Which tactical run they should make
- Which opponent they should defend

The distinction is:

    ASSIST EXECUTION OF PLAYER INTENT
                ≠
    CHOOSE THE PLAYER'S FOOTBALL DECISION

## A Held Input Is Itself A Decision

The list above bans the GAME from choosing. It does not ban the player from
choosing once and having that choice carried out over time.

A sustained input is a football decision the player has already made. When a
player holds a press input, they are not asking to stand near the carrier; they
are asking to win the ball back, and they keep asking for as long as they hold
it. Executing that request when the opportunity arrives is assistance, not
substitution.

So the following are explicitly ALLOWED:

- A held press that closes the carrier down and challenges when a legal
  challenge becomes available.
- A held charge that releases at a threshold the player set by holding.
- Any sustained input where releasing it stops the behaviour immediately.

The conditions are:

1. The behaviour only runs while the input is held.
2. Releasing the input ends it at once.
3. A discrete tap remains available for players who want to choose the exact
   moment themselves.
4. The assisted action is refused when it would be illegal or impossible, so
   the assistance cannot manufacture an outcome the player could not have
   produced.
5. The server still validates the result. Predicting the moment is allowed;
   awarding the outcome is not.

The test is whether the player can stop it. If letting go ends the behaviour,
the player is deciding continuously and the game is executing. If it continues
regardless, the game has taken the decision and that is forbidden.

Where a held input triggers an automatic action, prefer gating it on football
geometry rather than on a timer. A challenge that would have to travel through
an opponent's body should be refused whatever the input says, because that is
the difference between pressing and lunging.

For AI-controlled footballers, tactical decision-making is intentionally part
of the AI system, but the final physical execution should still respect Beyond
90's football mechanics, networking rules and competitive constraints.
---

# 3. Match Formats

Beyond 90 is designed around multiple match formats.

Initial planned formats include:

- 3v3
- 5v5
- 7v7
- 11v11

Do not design systems assuming that every match is 11v11.

Gameplay systems should be scalable according to:

- Number of players
- Pitch dimensions
- Camera requirements
- Player spacing
- Tactical requirements
- Match duration

A feature that works in 11v11 but breaks in 3v3 should be considered
incomplete.

---

# 4. CAMERA SYSTEM — CRITICAL

The camera system is one of Beyond 90's defining features.

The game must provide a strong football broadcast experience rather than
feeling like a standard Roblox third-person game.

## Broadcast Camera

The Broadcast Camera should be treated as a CORE GAMEPLAY AND PRESENTATION
SYSTEM.

It should resemble the camera perspective used when watching professional
football broadcasts.

The camera should:

- Look down toward the pitch from an elevated angle
- Maintain a readable view of the field
- Follow the active area of play
- Keep important players visible
- Provide strong awareness of teammates and opponents
- Make passing lanes readable
- Make tactical positioning readable
- Feel like watching an actual football broadcast
- Adapt to the size of the pitch
- Avoid unnecessary camera movement
- Remain smooth and cinematic
- Avoid feeling like a normal Roblox follow camera

The Broadcast Camera should NOT simply be:

    CameraType = Follow

or a basic camera attached directly behind the player's avatar.

It should be its own camera system.

---

## Broadcast Camera Philosophy

The player should feel like they are simultaneously:

1. Controlling their footballer
2. Reading the pitch
3. Watching a football broadcast

The camera should therefore prioritize:

    Football readability > Cinematic movement

Do not make the camera excessively cinematic if doing so makes gameplay
harder to understand.

Competitive players must be able to quickly determine:

- Where the ball is
- Where their teammates are
- Where opponents are
- Where space exists
- Where they are positioned
- Where they can pass
- Where they should move

---

# 5. Broadcast Camera Behavior

The Broadcast Camera should dynamically react to gameplay.

Potential behaviors include:

- Tracking the ball's general area
- Maintaining the controlled player's position within the frame
- Shifting its framing depending on possession
- Expanding the visible area when necessary
- Adjusting zoom based on field position
- Adjusting its angle based on pitch size
- Smoothly transitioning rather than snapping
- Maintaining consistent visual orientation
- Preventing important gameplay information from being hidden

Camera movement should feel deliberate.

Avoid:

- Violent camera snapping
- Constant zooming
- Excessive camera shake
- Sudden changes in perspective
- Obstructing the pitch
- Making players difficult to locate

---

# 6. Camera Presets By Game Mode

Different game modes may use different camera configurations.

Example:

3v3:
- Closer camera
- More zoom
- More emphasis on individual player control

5v5:
- Moderate zoom
- Balanced player awareness and individual control

7v7:
- Wider field awareness

11v11:
- Significantly wider Broadcast Camera
- Strong emphasis on tactical positioning
- Greater pitch visibility

These are starting guidelines, not fixed implementation requirements.

The final values should be determined through playtesting.

---

# 7. Other Camera Modes

Beyond 90 should also support alternative camera perspectives where
appropriate.

## Third Person

Third-person gameplay should provide a more direct avatar-control experience.

It should be useful when:

- Players want greater individual control
- A game mode benefits from closer gameplay
- Players are practicing
- Players are playing smaller-sided football

Third-person should still maintain good football readability.

## First Person

First-person should be optional.

It may be particularly useful for:

- Small-sided football
- Goalkeepers
- Immersive gameplay
- Specialized game modes

First-person should never be forced on players unless a specific game mode
explicitly requires it.

---

# 8. Camera Architecture

Keep camera logic modular.

Prefer a dedicated camera system such as:

    CameraController
    BroadcastCamera
    ThirdPersonCamera
    FirstPersonCamera

or an equivalent clean architecture.

Do not place all camera logic inside one giant LocalScript.

Camera modes should be switchable through a centralized system.

Example conceptual architecture:

    CameraController
        ├── BroadcastCamera
        ├── ThirdPersonCamera
        └── FirstPersonCamera

The implementation may differ, but the separation of responsibilities
should remain.

---

# 9. Camera Configuration

Avoid hardcoding camera values throughout multiple scripts.

Centralize configurable values such as:

- Camera distance
- Camera height
- Camera angle
- Field-of-view
- Camera smoothing
- Tracking strength
- Zoom limits
- Pitch-size adjustments
- Mode-specific settings

Prefer configuration modules/tables.

Example:

    CameraConfig

should contain tunable values rather than scattering numbers throughout
gameplay scripts.

This allows camera tuning without rewriting the system.

---

# 10. Camera Performance

The camera runs every frame and therefore must be performance-conscious.

Avoid expensive operations inside RenderStepped unless necessary.

Do not repeatedly:

- Search the entire Workspace
- Create/destroy Instances
- Perform unnecessary raycasts
- Allocate large tables
- Search for players repeatedly

Cache references whenever practical.

The Broadcast Camera must work smoothly on:

- PC
- Mobile
- Console

Performance is especially important on mobile devices.

---

# 11. Player Positioning

Beyond 90 is position-oriented football.

Players may eventually specialize in positions such as:

- Goalkeeper
- Centre Back
- Full Back
- Defensive Midfielder
- Central Midfielder
- Winger
- Attacking Midfielder
- Striker

Camera behavior should support positional awareness.

For example:

A midfielder needs to see passing options.

A defender needs to understand defensive shape.

A winger needs to understand space down the flank.

A goalkeeper needs a much wider understanding of the pitch.

Do not design camera systems exclusively around the striker's perspective.

## The Goalkeeper Opens In Pro Camera

The goalkeeper is the one outfield-facing role whose job is judging a ball
travelling toward them rather than reading the pitch from side on. A keeper
therefore DEFAULTS to the Pro Camera rather than to the Broadcast Camera.

This is a default, not a lock. A keeper who chooses a camera in Settings keeps
their choice; only the fallback differs by role.

The keeper's Pro Camera also uses its own framing, sitting higher and pitched
down harder than the outfield one. A keeper stands under their own crossbar, so
the ordinary framing puts the goal frame through the middle of the view and
hides the part of the pitch the keeper most needs to see. Any future change to
Pro Camera framing must keep the keeper variant clearing the goal frame.

How steep the keeper's view may go has an arithmetic answer, so use it rather
than guessing. The top edge of the frame sits at (Pitch - FOV/2) below
horizontal, and a ray at angle A from height H meets the ground at H/tan(A). The
pitch is about 341 studs between goal centres, so the far goal stays in shot for
as long as that reach exceeds it -- and if (Pitch - FOV/2) is negative the edge
is above the horizon and the whole pitch is in frame with room to spare. Check
this before and after changing either number; "steeper" and "still sees the
whole pitch" are not in tension until the edge crosses the horizon.

Do not "restore" the Broadcast default for goalkeepers on the grounds that the
Broadcast Camera is Beyond 90's core camera. It remains the core camera for
outfield play; this is a role-specific exception with a stated reason.

## A Ball In A Keeper's Hands Is Not A Loose Ball

Possession tests that ask "who is dribbling the ball" report nobody while a
goalkeeper is holding it. Treating that as a loose ball sends every footballer
on both sides to chase, and they converge on the keeper -- which is neither
football (nobody may challenge a keeper who has gathered it) nor playable.

A held ball is possession for the keeper's side: their team-mates shape up to
receive the distribution, the opposition drops into its defensive shape, and
neither side nominates anyone to go and get it.

## A Held Input Asks Once, Then Waits

An input held down should not re-send its request every frame. The auto-challenge
on a held press did, firing ~60 requests a second that the server refused as
`already-committed` or `recovering`, so the press looked broken while saturating
the remote.

A sustained input drives sustained BEHAVIOUR (closing the carrier down); the
discrete REQUEST it produces is rate-limited and gated on the state the server
already published. This does not weaken section 2's rule that a held input is a
decision -- the decision still stands for as long as it is held. It only stops
the same decision being transmitted sixty times.

## A Goalkeeper Is Only A Goalkeeper Inside Their Own Area

The keeper role is bounded by the penalty area, and the same boundary governs
three separate things, which must not be allowed to disagree:

- Handling is legal inside it. `GoalkeeperService.Hold` refuses a keeper who
  reaches for the ball outside it, and `updateHeldBall` penalises a keeper who
  gathered it legally and then carried it out. Both are handling offences.
- Keeper CONTROLS apply inside it. Outside, the player gets their ordinary
  outfield bindings back, because outside the box a keeper has no special
  actions available to them anyway.
- Keeper ANIMATION is chosen by DIRECTION OF TRAVEL, not by area and not by
  speed. Moving across the line plays the keeper's sidestep, sped up with pace;
  moving toward or away from the play plays ordinary jog and sprint, because a
  keeper closing a striker down is running. Gating this on speed alone made any
  quick movement play the outfield sprint; gating it on the penalty area made
  the sidestep the only clip that ever played.
- Keeper handling owns the attacking inputs only while the ball is actually IN
  HAND. With the ball on the grass -- a goal kick, a loose ball at their feet --
  a keeper passes and shoots exactly like any other footballer. Refusing those
  inputs for anyone wearing the gloves left the nominated taker unable to take
  their own goal kick.
- The keeper's turn is bounded to a half-circle centred on facing out of their
  own goal, so they can square up to an attacker at either post but never
  rotate to face their own net.

All three read the same test (`IsInsideOwnPenaltyArea`) against the same
published pitch frame. If a future change needs a different boundary for one of
them, state why the three should diverge rather than adding a second test.

## Read The Reference Before Reproducing It

`ref/` holds the footage a feature is meant to look like. Extract frames and
LOOK at them before building the thing, and cite what the frames show.

The goalkeeper ground indicators were built from a written description of the
reference rather than from the reference. The result had a 16-spoke ring, a
chevron and a second ring at the keeper's target position. The footage has one
thin continuous ring and a pair of coloured dive arcs that appear only during a
save — no spokes, no chevron, no second ring. The extra ring was what the player
saw as a "double circle" underneath the keeper.

Frames extract locally with ffmpeg and stay local. They are development
reference only: never import them into Roblox (section 57).

## Measure Against The Man, Not The Marker

Distances that stand for a football relationship must be measured to the thing
the relationship is about.

Press containment was gated on the distance to the press TARGET — a point
goal-side of the carrier — rather than to the carrier. A defender well away from
his opponent could be close to that point, get treated as jockeying, and be
capped below sprint for an entire chase. Jockeying range is a distance to the
MAN; interception range is a distance to the BALL; offside is a distance to the
LINE. Check that the quantity being compared is the one the rule is about.

## Never Trust A Height You Did Not Measure

The pitch publishes `PitchGroundY` on its bounds. It is **not** the height of the
grass a player stands on. On the development stadium the attribute reads 0.20
while a ray against the rendered pitch returns 1.70 -- a 1.5 stud difference,
which is enough to bury anything drawn on the ground completely.

The goalkeeper ground indicators were placed with a guessed constant, then with
that attribute, and were invisible both times for the same reason.

Anything that must sit ON the pitch surface -- ground markers, decals, restart
spots, placed props -- raycasts down for the surface and uses what it hits.
`PlayerService` already does this for foot placement. The bounds attribute
describes the pitch's reference frame and is fine for region maths, which is
what `PitchGeometry` uses it for; it is not a rendering height.

## A Humanoid Cannot Be Bypassed, Only Driven

A Roblox `Humanoid` keeps applying its last `Move` command every physics step.
Skipping its update does not neutralise it -- it freezes it on whatever it was
last told, and `Move(Vector3.zero)` with `WalkSpeed = 0` is an active brake.

Any server-decided movement of a player-controlled footballer -- a dive, a
launched slide, a knock-back -- must therefore be expressed THROUGH the humanoid
(set `WalkSpeed` and `Move` toward the intended direction) rather than as a raw
velocity write that the character controller will cancel on the next step.

The goalkeeper dive failed three times before this was understood: written on
the server (wrong owner), applied on the client then skipped (humanoid still
braking), and only worked once it drove the humanoid.

## Server-Approved, Client-Applied Motion

A player's own character is network-owned by THEIR CLIENT. A server-side write
to `AssemblyLinearVelocity` on a client-owned assembly is discarded on the next
replication tick, silently -- the state change, the attribute and the log line
all succeed while the body never moves.

The goalkeeper dive was built this way and did not move for human keepers for
exactly this reason, while working correctly for AI keepers, whose bodies the
server owns.

The pattern for any server-decided impulse on a player-owned body is therefore:

    SERVER decides whether it happens, and publishes the launch
            |
    OWNING CLIENT applies it

This is section 32's split, not an exception to it: the client simulates the
motion, the server decides what the motion means. Validation, cooldowns,
direction and duration stay on the server. Before adding any new launched
movement for a human-controlled footballer, check which side owns the body.

## Measure The Clip Before Writing Code That Duplicates It

The keeper's dive rolled the ROOT 78 degrees in code, and unwound it again on
recovery. Both were wrong, because the authored clips already carry the fall.
Measured with `KeyframeSequenceProvider:GetKeyframeSequenceAsync`:

    DiveLeft    maxTorsoRot=107.9 deg   rootTranslations=0
    DiveRight   maxTorsoRot= 97.6 deg   rootTranslations=0
    GetUpLeft   maxTorsoRot=103.2 deg   rootTranslations=0
    GetUpRight  maxTorsoRot= 87.8 deg   rootTranslations=0

and across DiveLeft's own timeline the torso goes 17.7 -> 108 degrees:

    t=0.00  17.7    t=0.80   54.3    t=1.60  102.5
    t=0.27  23.4    t=1.07   86.7    t=1.87  107.9

So one dive tipped the keeper about 178 degrees: roughly 100 from the clip and
78 from the code. Applied twice, taken away twice. That is what the player saw
as "rolls around", and every previous pass treated it as a bug in HOW the roll
was applied rather than asking whether it should be applied at all.

The animator's note that "the animations have no x or y movements" was accurate
and was misread. It is a statement about TRANSLATION -- `rootTranslations` is 0
for all four clips -- not about rotation.

    THE CLIP OWNS THE BODY'S ATTITUDE.
    THE CODE OWNS ITS TRANSLATION AND ITS YAW.

Before writing code that poses a character, LOAD THE CLIP AND MEASURE IT. It is
a few lines and it is checkable; assuming is how the same 78 degrees survived
four separate fixes. The same applies to LENGTH: `Dive.Duration` was 0.78s
against a fall that takes 1.3s, so the keeper was cut off mid-fall and the get-up
started from a lying pose he had not reached. Scale the playback so the clip
completes inside the window the gameplay owns, rather than moving the window.

## Rotation The Code Applies, The Code Must Take Away

`Humanoid.AutoRotate` governs YAW ONLY. Nothing in a Humanoid returns a ROLLED
root part to upright -- so any code that tips a character over owns standing it
back up, and stopping writing the CFrame is not the same as undoing it.

The goalkeeper dive tipped the body 78 degrees and then simply released it. The
keeper stayed lying on the pitch for the rest of the match, and a tipped Humanoid
reports `FallingDown`, which the airborne test treats as airborne -- so the
animation flip-flopped between the keeper set and the airborne fallback
indefinitely, with the body sliding because a keeper on its side has no footing.

Any driven rotation needs a full arc: apply it, and unwind it on a stated
recovery. If the Humanoid may have entered `FallingDown` while tipped, put it
back with `ChangeState(GettingUp)` -- it does not leave that state on its own.

SUPERSEDED IN PART -- see "Measure The Clip Before Writing Code That Duplicates
It" above. The rule holds wherever code genuinely does rotate a body. It was
learned here on a 78 degree roll that should never have existed, because the
dive clip already lays the keeper down; the roll is now gone rather than
balanced. Correct rule, wrong place to have learned it.

## A Snapshot Cannot Hold State

`FootballerRegistryService.GetHumanActor` builds a NEW TABLE on every call. That
is fine for answering a question and fatal for anything that WRITES to the actor,
because the write lands on a throwaway that is discarded the moment the caller
returns.

Every goalkeeper dive guard stores its state on the actor -- committed-until,
recovery window, input cooldown. The keeper remote resolved its actor with
`GetHumanActor`, so for a HUMAN keeper all three were written and instantly lost:
`IsDiving` was permanently false and every request launched a brand-new dive on
top of the one already running, republishing the launch direction and resetting
the dive's start stamp so the body roll restarted from zero. The keeper thrashed
on the spot instead of travelling.

    19:59:11.696  runo dives LowDive toward (25.8, 4.5, 180.2)
    19:59:11.853  runo dives LowDive toward (27.7, 4.5, 178.4)   <- 157ms later
                  KeeperDiveRight -> KeeperDiveLeft

`Register` already keeps one long-lived table per keeper; the fix was to use it.

The general rule: before writing a field onto an actor, know whether that actor
is the REGISTERED one or a snapshot. If a function can hand back a different
table for the same footballer on two consecutive calls, it is a read-only view,
and per-footballer state does not belong on it.

Also note how this looked from outside: an animation flipping between two clips.
Two earlier passes tried to fix that flip inside the animation and the movement
roll -- both were downstream of a server that was genuinely restarting the dive.
When presentation flip-flops, check whether the STATE it is reading is
flip-flopping before rewriting how it is read.

## A Threshold In The Wrong Units Cannot Express The Rule

The keeper's side step was gated on `SideStepMinimumSpeed`, a threshold in
STUDS PER SECOND. But "sideways" is an ANGLE, and no speed can express it: the
faster the keeper travels, the smaller the deviation needed to clear a fixed
lateral speed.

    speed  6 -> side-steps from 15.5 deg off straight
    speed 16 -> side-steps from  5.7 deg off straight
    speed 24 -> side-steps from  3.8 deg off straight

At their 16 stud/s line pace a 5.7 degree wobble was "sideways". The diagnostic
showed every one of these playing the side step:

    travelAngle=  14.3  lat= 3.95   <- straight ahead
    travelAngle= 154.2  lat=10.38   <- BACKWARDS
    travelAngle=-159.0  lat=-6.21   <- BACKWARDS

One wrong unit, three reported symptoms: the strafe never read as a strafe
because it was always on, jog-backwards could never play because backwards
travel carries lateral too and the lateral test claimed it first, and the clip
thrashed against the outfield jog whenever the wobble crossed the line. Three
separate fix attempts moved the NUMBER; none questioned the UNIT.

Before tuning a threshold, ask what quantity the rule is actually about. Sectors
in degrees, with hysteresis, express "forward / sideways / backward" exactly.

## Measure Against Something That Does Not Move

The keeper's dive picked its side from the sign of the dive direction against
the BODY's right vector. A keeper may turn up to `MaximumFacingArcDegrees` off
the pitch, so that reference swings through 180 degrees -- and at the edge of the
arc a ball in front of goal is BEHIND the keeper:

    launchWorld= 90.0  frame= -1.3  ->  +91.3  lateral, fine
    launchWorld=-90.9  frame= 90.6  -> +178.5  BEHIND the keeper
    launchWorld= 89.4  frame=-75.2  -> +164.6  BEHIND the keeper

Two consequences, and only the second was visible. The clip side became a
coin-flip on where the body happened to point. And the body was driven along
that world direction, so it genuinely travelled BACKWARDS at 17-19 studs/s --
the reported "keeper dives backwards instead of sideways". No clip choice fixes
that; the motion really was backwards.

`Pitchward` -- out of the keeper's own goal, the published centre of their turn
arc -- does not move. Both the clip side and the dive's body orientation now
read it, so a shot-stopping dive is lateral by construction and the two agree.

A sign taken against a rotating reference is not a decision, it is a sample of
where something was pointing. Pick a reference the rule is actually about.

The same fault ran one layer up, in the keeper's LOCOMOTION sectors. Measured
against the body, the travel angle swung 17 degrees inside 41 milliseconds on a
steady input -- a 244 degree body-yaw span across one session -- and the
side-step/jog flip-flop followed it exactly. Sectors are now measured against
`Pitchward` too: 0 is off the line, +/-90 is across the goal (a side step),
+/-180 is back into the net (jog backwards). Those are the football meanings,
and they do not move.

That fix needs its partner: `MaximumFacingArcDegrees` went 90 -> 45. At 90 a
keeper may face fully ALONG their own goal line, where "across the goal" and
"straight ahead" are the same direction for the body -- so no clip choice can be
right, because a lateral shuffle and a forward jog describe the same motion.
Selecting in a stable frame while PLAYING in a rotating one only works if the
two agree; bounding the arc is what makes them agree.

## Moving Somewhere Is Not Looking Somewhere

Keeper facing was steered by the MOVEMENT stick, unclamped. The body therefore
pointed along its own velocity, and on every side-step sample measured in one
session the two were aligned:

    goalAngle= 67.9  body fwd=+10.14 right=-0.11  -> bodyAngle= -0.6
    goalAngle=-94.6  body fwd=+16.00 right=-0.13  -> bodyAngle= -0.5

Two reported faults, one cause. A shuffle across the line rendered as a
footballer jogging forwards, because the body had turned to face its travel. And
jog-backwards was unreachable BY CONSTRUCTION: if the body always points at the
travel, no travel is ever backwards. The yaw also reached 94 degrees against a
45 degree arc, because the steer branch returned before the clamp.

Moving sideways and looking sideways are different things in football, and for a
keeper they are almost never the same thing. Facing is ball-tracking clamped to
the arc; movement does not touch it.

Note what this replaced: an earlier pass had handed facing to the stick BECAUSE
a keeper pinned to the arc edge could not look elsewhere. That was a real
complaint with a real cause, and the fix addressed it in the wrong place. When a
constraint is too tight, widen the constraint -- do not hand the value to
whatever else happens to be to hand.

## Committed Movement Must Be Stopped, Not Just Ended

Clearing the flag that says a launched movement is over does not stop the body.
The keeper's dive drove the humanoid at `LowDiveSpeed`, and when the dive ended
nothing took the momentum away:

    KeeperGetUpLeft  speed=48.7   [Coast] slid 31.4 studs
    KeeperGetUpLeft  speed=48.2   [Coast] slid 32.4 studs

-- a keeper sliding thirty studs across his own box while the get-up clip plays
over the top. Reported as "glitches backwards after diving", and it is exactly
that: the body is still travelling in the dive's direction while the animation
says the dive is finished.

Any launched movement owns its own deceleration. Zero the HORIZONTAL component
only, so a body still in the air finishes falling rather than freezing mid-drop.
The owning client writes its own assembly -- section 32 forbids the SERVER
writing to a client-owned body, not the owner writing its own, which is how the
launch was applied in the first place.

Pairs with "Rotation The Code Applies, The Code Must Take Away": the same is
true of velocity.

## A Keeper's Dive Goes Across The Goal

Aiming a dive at the ball is not the same as diving. The human dive aimed along
the direction to the ball, so a ball up the pitch produced a dive up the pitch.
Three of eight dives in one session launched FORWARD off the line and one
launched BACKWARD into the net.

Squaring the keeper's body to the goal fixed the left/right CLIP, and that was
worth doing, but a clip cannot make a forward dive lateral -- the body genuinely
travelled that way. The dive is now projected onto the goal's width axis.

The player's input still chooses the side; the projection's sign comes straight
from their aim, so left stays left. What is removed is only the component that
was never a save. An aim with no meaningful side to it (the ball coming straight
at the keeper) is refused, and the save is taken standing -- which is the correct
football action, not a fallback.

This is §2's line exactly: assist the execution of the decision the player made,
do not make the decision, and do not carry out a request the geometry says is not
the action being asked for.

Related: `up:Cross(look)` is MIRRORED relative to `CFrame.RightVector`; the
correct order is `look:Cross(up)`. Verified in all four cardinal orientations
after getting it wrong once in this very fix.

## A Threshold Must Be Checked Against The Speeds It Will See

The keeper's side step was chosen by ANGLE (sideways relative to the body). That
was right. It was replaced with a pure SPEED cap after the log showed the shuffle
clip playing at 45 studs/s -- but the real cause of those readings was the body
still carrying dive velocity after `Diving` had gone false, not a genuine run.

The replacement cap was set to 9 studs/s. A keeper's own line pace is
`Positioning.MoveSpeed = 15` and their rush is 26, so the cap sat BELOW walking
pace: every piece of ordinary line work exceeded it and handed over to the
outfield jog, and the side step only played when the keeper was barely moving --
the exact opposite of the intent. Raising the cap then broke the other side,
because a keeper running out at 26 studs/s was neither lateral enough to side
step nor fast enough to clear the cap, and fell through to IDLE.

Two lessons, and the second is the general one:

- Before setting a threshold, look up the speeds, distances or angles the system
  actually produces and check the value against them. `MoveSpeed` and `RushSpeed`
  were both one grep away.
- When a symptom appears in one state, fix THAT state rather than replacing the
  rule that governs all of them. The 45 studs/s readings were a missing dive
  recovery state; the answer was to give the recovery its own state (the get-up
  clip), not to rewrite how every keeper movement is classified.

## A Clip Is A Better Authority Than A Timer

Code that unwinds a pose over a fixed duration is an animation written in the
wrong language. It cannot know when the body is actually ready, so it is always
approximately wrong, and the error shows as the character drifting out of the
movement.

The keeper's dive recovery was a 0.34s constant unwinding a 78-degree roll. With
a real get-up clip the CLIP became the authority: it publishes when it will
finish (`Beyond90KeeperGetUpUntil`), the roll unwinds across exactly that window,
and input returns on the same frame the keeper is animated as standing.

Where two systems must agree on a duration, ONE of them owns it and publishes it;
the other reads. Two constants for one event is how they drift apart. Keep the
constant as a fallback for the missing-asset case, so a clip that fails to load
degrades to the old behaviour rather than stranding the character.

## Two Assists Must Not Fight Each Other

Assistance systems are written one at a time against the case they are for, and
each is reasonable alone. Check every new one against the assists that already
exist, because the failure is silent: both run, neither logs anything wrong, and
the player simply cannot do the thing.

Body-overlap separation steers a footballer AWAY from anyone close. Pressing
steers a footballer TOWARD the man they are closing down. Added independently,
separation cancelled the last few studs of every press -- and the only visible
trace was the tackle being refused on distance:

    [Defending] [Tackle] runo -> AWAY_AI_2 rejected=ball-out-of-reach

The rule that resolves it: a deliberate player decision outranks an automatic
correction. The press is held down by the player, so the man being pressed is
exempt from separation while it lasts. When two assists disagree, the one
carrying an explicit input wins.

## Removing A Collision Is Not A Fix For A Collision Bug

Footballers were climbing over each other, so the footballer-versus-footballer
collision pair was removed. They then walked THROUGH each other, which is worse:
climbing is ugly, but passing through a defender is not football at all.

Collision is load-bearing for how a sport reads even when nothing competitive is
computed from it. Fix contact bugs by changing what is being contacted -- the
geometry, or how often bodies reach each other -- and treat deleting the contact
as the last resort it is. A Humanoid climbs LEDGES, and separate torso parts are
what make ledges; a single smooth collision capsule is the real answer if
steering is not enough.

## Where Two Driven Motions Meet, Match The RATE, Not Just The VALUE

The keeper's dive fell on a squared curve to the last frame of the dive, and the
get-up then raised him starting from rest. The two agreed on the VALUE at the
handover -- both said "2 studs down" -- and disagreed completely on the RATE: the
fall was descending fastest at the instant it stopped. That step change is felt
as an impact jolt, and no amount of adjusting the endpoint heights removes it.

Easing the fall so it meets the ground at zero rate, and holding the keeper flat
for the last stretch of the dive, makes the whole arc continuous from launch to
standing:

    p=0.830 rate=-1.18   p=0.845 rate=-0.30   p=0.850 rate=-0.02   p=1.000 +0.00

Whenever one driven motion hands over to another -- dive to get-up, run to stop,
carry to release -- check the derivative at the seam, not only the position.

## Gate EVERY Half Of A Commitment On The Same Edge

A committed action usually drives more than one thing. The keeper's dive drives
both a LAUNCH (velocity) and an ORIENTATION (squaring the body to `Pitchward`).
Gating only the launch on the animation's start left the orientation firing on
the server's `Diving` edge -- up to 45 degrees of yaw snap, ~39ms before the clip
was drawn, and because a per-frame CFrame write is integrated as motion, the snap
carried a translation with it.

The symptom ("moves slightly before the animation plays") was reported twice and
fixed once, because the first fix addressed the half that was easy to see. When
gating an action on a start signal, enumerate everything that action writes and
gate all of it.

## A Baseline Read From What You Are Writing To Is Not A Baseline

Code that offsets a property needs a rest value to offset FROM. Capturing that
lazily -- on the first frame that needs it -- means any path reaching the capture
while an offset is already applied records the OFFSET as the new rest value, and
every later offset stacks on top of it.

The keeper's dive drove `Humanoid.HipHeight` this way. Measured against a
calibrated 2.950:

    [Grounding] state=jog hipHeight=9.602 ... contactMax=18.129

with the keeper mid-get-up -- reported as "shoots up just after getting to the
floor". Each dive was adding roughly its own apex to the character's resting
height, and no single path was wrong; the loop was.

Bind the rest value ONCE, where the thing it describes is created (here, when the
character's humanoid is bound), before anything can have moved it. Releasing an
offset restores the value but must NOT clear the binding -- clearing it is what
lets a later capture read an offset value. Pairs with "A Value With Two Owners
Has One Real Owner": this is the same fault with the two owners being the same
line of code at two different times.

## A Rate That Sizes A Window Must Also Drive The Clip

`GetUpPlaybackRate` was used to compute how long the get-up window should last,
and never applied to the get-up track. The clip fell through to the generic
speed-scaled rate, which at a standstill clamps to `MinimumPlaybackRate` -- so a
keeper pushing up off the grass, who is by definition not moving, always got the
slowest clip in the set:

    State -> KeeperGetUpRight ... playback=0.80   (window sized as though 1.00)

The window and the clip then disagreed by exactly that ratio, and the body was
handed back before the animation finished standing up. One rate, used for both,
in the branch that owns the clip. Check any config value whose name says "rate"
is actually reaching the track, not only the arithmetic around it.

## A Require Cache Is Not A Sync Failure

`require()` caches a module's returned table per DataModel. Rojo replaces a
ModuleScript's `Source`, but an Edit session that already required that module
keeps handing out the ORIGINAL table forever. So a probe that requires a config
and reads a field reports the value from whenever the module was first required,
which may be hours and many saves ago.

This was misdiagnosed three rounds running as "AnimationConfig has not synced to
Studio", and nearly ended with the user being told to reconnect Rojo. Rojo was
fine. Reading the same instance's `Source` showed every edit present:

    require(...).DivePlaybackRate   -> 1     (cached at first require)
    Source match "DivePlaybackRate" -> 1.7   (what Rojo actually delivered)

A Play session builds a fresh DataModel, so playtests were running the NEW
values the whole time. The bug was in the measuring instrument.

When verifying that an edit reached Studio, read `Source`. Use `require` only to
check that a module still LOADS, or inside a Play session that started after the
edit. If a probe reports a stale value, confirm against `Source` before
concluding anything about the sync.

## A Value With Two Owners Has One Real Owner

When a value can be set from configuration AND accumulated at runtime, tuning
the configuration does nothing for as long as the accumulator is the one being
read. The tuning looks applied -- the file changed, the build succeeded -- and
the game ignores it.

The Pro Camera's pitch worked this way. With the mouse locked, which is the
normal gameplay state, pitch was `mousePitch` alone, seeded once from the
OUTFIELD preset and moved only by mouse delta thereafter. The goalkeeper preset
supplied height, distance and FOV, which visibly took effect, and an angle that
never did. Two passes of tuning the keeper's `Pitch` changed nothing on PC, and
the report each time was that the camera was still not angled correctly.

So before tuning any value, find every writer of it. If one of them is a
runtime accumulator, decide explicitly when the accumulator is re-seeded --
otherwise the configuration is documentation rather than behaviour.

## A Fall-Through Is Not An Error

`InputController.SetTouchFootballAction` dispatched on a list of action names --
`GroundPass`, `ThroughPass`, `KnockOn`, `Shoot` -- and `Tackle` was simply not on
it. The touch HUD sent it anyway, for two buttons: the outfield PRESS and the
goalkeeper's DIVE. Both did nothing on every touch device, silently, because a
name that matches no branch produces no error and no log line.

Section 22 already requires touch to be tested alongside keyboard. The narrower
rule this teaches: when one input path dispatches on a SET of names and another
path produces them, the two lists must be checked against each other. Prefer a
shared table of action names over two hand-written lists that can drift.

The same fix exposed a second layer. The keyboard `Tackle` binding sent a bare
`send("Dive")` with no aim -- acceptable while it was a secondary binding beside
the mouse click, and broken as soon as it became the ONLY way a phone player
dives, because a dive with no side is refused as `no-lateral-component`. A
control that is secondary on one device may be primary on another; check what
each entry point actually supplies before sharing it.

## Two Writers, One Part

`BallControlService` had no knowledge of the goalkeeper hold, so a gathered ball
-- stationary, two studs from its holder, the exact shape of a loose ball worth
collecting -- was claimed by the ordinary dribble acquisition, for the keeper
HOLDING IT:

    [GK] morhanzy caught the football (ballSpeed=125.1)
    [Reception] player=morhanzy type=Shoot distance=2.10 ballSpeed=0.00
    Ball network owner -> morhanzy
    [ControlledBall] epoch=23 initialized phase=Carry
    Control released: movement state invalid

`updateHeldBall` then pinned the ball to the keeper's chest on the SERVER every
frame while the newly network-owning CLIENT carried it at foot height. The part
ends up inside the keeper's own collidable torso and the solver ejects him --
reported as "glitches upwards when I try to move after catching a ball".

Whenever a part is positioned every frame by one system, every OTHER system that
can take ownership of that part needs a reason not to. The football rule and the
fix are the same sentence here: a keeper who has gathered the ball has
possession, and nobody -- the keeper included -- dribbles it.

Pairs with [[Do Not Let A Keeper Catch Their Own Distribution]]: same part, same
service boundary, different direction across it.

## A Timer That Releases The Ball Is A Decision The Player Did Not Make

`HoldSeconds` and `MaximumHoldSeconds` made a keeper throw the ball away 1.5s
after catching it, and force-distributed at 5s. For an AI keeper that IS the
decision and it must stay -- section 2 puts tactical choice on the AI side, and a
keeper who never distributes stalls the match. For a HUMAN keeper it is exactly
what section 2 forbids: the ball left their hands without them choosing to
release it.

The general shape: before adding a timer that performs a football action, ask
whose decision that action is. If a human controls the footballer, the timer may
prompt, warn, or penalise -- it may not act.

## Do Not Let A Keeper Catch Their Own Distribution

A goalkeeper's throw or kick releases the ball AT THE KEEPER'S HANDS, so for one
frame it is a free ball a fraction of a stud away -- which is precisely what the
assisted save and the assisted claim exist to pounce on. Both the AI keeper and
the human one were re-securing every ball they distributed, within milliseconds,
which read to the player as the control doing nothing at all.

Football already states the rule: having released the ball, a keeper may not
handle it again until another player has touched it. Implement it as a per-actor
block that lifts on anyone else's touch, with a timeout so a clearance reaching
nobody cannot strand the keeper.

The general form: any system that both RELEASES a ball and AUTOMATICALLY CLAIMS
one needs to know it was the releaser. Check the receiving/interception paths
whenever a new release is added.

## Bodies Do Not Climb Bodies

A Roblox `Humanoid` steps up onto anything within its step height, and another
footballer's torso is inside it -- so two footballers meeting shoulder to
shoulder ride up over one another, leaving one airborne and the other pinned.

No amount of steering fixes this alone: while the geometry is climbable, a hard
enough collision climbs it. Remove the thing being climbed (footballer against
footballer is a non-colliding pair) and replace it with steering separation,
which holds bodies apart before they meet. Section 33 already permits
body-overlap avoidance as assistance, so the steering is allowed for a
human-controlled footballer as well as an AI one.

If physical shielding is built later it wants its own deliberate contact model,
not Roblox's default one -- the default is what was climbing.

## A UIStroke Outlines Text Unless Told Otherwise

`UIStroke.ApplyStrokeMode` defaults to `Contextual`, and Contextual on a
`TextLabel` or `TextButton` strokes the GLYPHS, not the frame. Every text
control that gets a stroke therefore gets outlined letters, which fattens and
blurs them until they read as a different, wider typeface -- and any accent
colour becomes a halo around the text.

Beyond 90's shared stroke helpers now pin `ApplyStrokeMode = Border`. `Border`
is identical to `Contextual` on a Frame, so pinning it costs nothing and fixes
every text control at once. Any new stroke created directly rather than through
those helpers must set it too.

## A Human Actor Answers The Same Questions As An AI One

Human and AI footballers are described by actor tables that must support the
same queries, because shared systems query them identically. Where an AI actor
carries a field and a human actor does not, every test on that field silently
answers "no" for humans -- which is not an error anywhere, just a wrong answer
everywhere.

`actor.Position` was AI-only, so `actor.Position == "Goalkeeper"` was false for
a human goalkeeper. Match assembly counts keepers with exactly that test and
reported a complete side as a keeper short. When adding a field to one actor
kind, add it to both, or read it from the character attribute both kinds set.

---

# 12. Tactical Readability

The camera should make football tactics understandable.

Players should be able to recognize:

- Defensive lines
- Open space
- Passing lanes
- Runs
- Overloads
- Counterattacks
- Teammate positioning
- Opponent positioning

The camera is therefore part of the game's competitive design,
not merely a visual feature.

---

# 13. Broadcast Presentation

The Broadcast Camera should eventually support presentation systems such as:

- Match introductions
- Kickoff presentation
- Goal replays
- Celebration shots
- Scoreboard overlays
- Match clock
- Team information
- Player information
- Tournament presentation
- Replay cameras
- Highlight moments

These systems should be designed separately from the core gameplay camera
where possible.

A future replay/highlight system should be able to use the same camera
infrastructure.

---

# 14. Broadcast Camera Is A Differentiator

Treat the Broadcast Camera as one of Beyond 90's major differentiators.

When evaluating a feature, ask:

> Does this make Beyond 90 feel more like a real football experience?

If yes, prioritize it where appropriate.

If a camera implementation technically works but makes the game feel like
a standard Roblox football game, it should be reconsidered.

The goal is not simply:

    "A football game with a camera."

The goal is:

    "A football game that feels like playing inside a football broadcast."

---

# 15. Development Priorities

Beyond 90 should be developed in dependency order.

At a high level, prioritize:

1. Core player movement
2. Ball physics
3. Ball interaction
4. Ball control / possession foundation
5. Dribbling and first-touch foundations
6. Camera foundation
7. Passing
8. Receiving / first touch
9. Shooting / goal interaction
10. Tackling / defensive interactions / shielding
11. Goalkeeper gameplay
12. AI footballers for development testing and training
13. Teams, positions and match flow
14. Football rules and restarts
15. AI match integration / team behavior
16. Multiplayer and networking hardening
17. Match-format scaling
18. Custom football animation
19. Mature camera / presentation
20. Match HUD and core UI
21. Mobile and controller production support
22. Lobby / parties / matchmaking
23. Player identity and persistence
24. Clubs
25. Ranked / divisions / seasons
26. Progression / rewards
27. Audio / stadium atmosphere
28. Presentation polish
29. Safety / moderation / production backend
30. Optimization / compatibility / scale testing
31. Alpha and beta testing
32. Launch

A more explicit milestone roadmap is defined later in this document and should
be used for current development sequencing.

This order is a development guideline, not a requirement to completely finish
one system before touching another.

Systems may be revisited as playtesting exposes dependencies.

In particular:

- Ball control must be stable enough before passing and shooting depend on it.
- Player movement and ball control may be revisited together when reference
  behavior demonstrates that they are coupled.
- The Broadcast Camera should be prototyped early enough to influence gameplay
  readability, but it should not block development of the core football loop.
- AI footballers should be introduced once enough shared football actions exist
  for bots to become useful test participants rather than fake scripted movers.
- AI should then become a development multiplier: future team, rules, tactical,
  goalkeeper and match-flow systems should be testable without requiring a full
  group of human testers.
- Do not build complex progression, clubs, monetization or live-ops systems
  before the football experience is fun and structurally stable.
---

# 16. Code Quality

Write production-quality Luau.

Prefer:

- Modular systems
- Clear naming
- Small focused modules
- Explicit responsibilities
- Reusable functions
- Configuration modules
- Server-authoritative competitive state
- Responsive client-side execution where appropriate
- Client-side presentation where appropriate

Avoid:

- Giant scripts
- Duplicate logic
- Magic numbers without context
- Unnecessary global state
- Tight coupling
- Temporary hacks presented as final architecture
- Reimplementing proven reference behavior differently without a reason

A simpler implementation is not automatically better if it produces
substantially worse football behavior.

Likewise, a more complex reference algorithm should not be adopted unless its
complexity contributes meaningfully to gameplay.

---

# 17. Networking

Beyond 90 should aim for:

    RESPONSIVE LOCALLY
            +
    AUTHORITATIVE GLOBALLY

Critical competitive state must remain server-authoritative wherever practical.

The client must not authoritatively determine:

- Goals
- Score
- Match results
- Currency
- Player statistics
- Competitive rankings
- Critical possession changes
- Successful tackles
- Competitive ball outcomes
- Persistent progression

RemoteEvents and RemoteFunctions must be validated on the server.

Never assume data sent by the client is trustworthy.

However, server authority does NOT require every visible or movement-related
response to wait for a server round trip.

Where appropriate, investigate and use Roblox-native techniques such as:

- Client-side prediction
- Server reconciliation
- Interpolation
- Safe extrapolation
- Input buffering
- Latency compensation
- Visual prediction
- Locally responsive movement assistance
- Server validation
- Controlled network ownership strategies
- State replication

For human-controlled footballers, movement and football-contact assistance may
run locally when necessary for responsiveness, provided critical competitive
ball state remains authoritative and the server can validate relevant outcomes.

Do not sacrifice competitive integrity merely to make gameplay responsive.

Do not sacrifice responsiveness unnecessarily merely to simplify server
implementation.

---

# 18. Roblox + Rojo Workflow

The project uses Rojo to synchronize the local VS Code project with
Roblox Studio.

The preferred workflow is:

    VS Code
       ↓
     Rojo
       ↓
    Roblox Studio

Source code should primarily be edited in the local project rather than
being independently created inside Studio.

If a script is created directly inside Roblox Studio, do not assume it will
automatically appear in the VS Code project.

The source-of-truth should remain the Rojo project.

External research repositories must not be mapped into Roblox Studio.

---

# 19. AI Development Rules

AI assistants such as Codex or Claude may assist with development.

Before modifying code:

1. Read AGENTS.md completely.
2. Understand the existing Beyond 90 architecture.
3. Inspect relevant Beyond 90 files.
4. Determine which existing system owns the requested responsibility.
5. Inspect relevant external reference research where applicable.
6. Inspect actual GameplayFootball source when the feature is covered by the
   GameplayFootball source-level reference strategy.
7. Avoid creating duplicate systems.
8. Preserve existing functionality that remains valid.
9. Explain significant architectural decisions.
10. Prefer incremental, testable changes.

For any task that creates, modifies, reviews, audits or makes design decisions
about player-facing UI / UX, the agent must also use the dedicated Beyond 90 UI
guidance under:

    docs/ui/

Read:

    docs/ui/README_UI_AGENT.md
    docs/ui/UI_AGENT_DECISION_RULES.md
    docs/ui/UI_DESIGN_SYSTEM.md

and then the task-relevant files described by the UI README.

Do not require the full UI documentation set for tasks that have no UI / UX
impact.

`AGENTS.md` remains authoritative for project-wide architecture, gameplay,
networking, milestone scope, safety, moderation and asset-upload rules.

Within a UI / UX task, the dedicated `docs/ui/` documents are the authoritative
specialized guidance unless they conflict with this file or an explicit current
user instruction.

Do not rewrite large parts of the project merely because another architecture
is aesthetically preferable.

However, do not preserve a failed gameplay abstraction merely because work has
already been invested in it.

If verified reference behavior demonstrates that an existing Beyond 90
approach is solving the football problem poorly, replacing that approach is
allowed and may be preferable.

Research findings do not automatically authorize a refactor unless the task
explicitly includes implementation.

Do not modify production gameplay code during a research-only task unless
explicitly instructed to proceed with implementation.

Before selecting an external reference, identify the SYSTEM being designed.

Do not assume GameplayFootball, FIFA, eFootball, real football, or another
reference is automatically the best source for every problem.

Use the Beyond 90 System Reference Strategy defined later in this document.

For each substantial feature:

    identify system
        ↓
    identify strongest relevant reference(s)
        ↓
    inspect source where source is available
        ↓
    understand the principle / behavior
        ↓
    identify platform-specific assumptions
        ↓
    design the Beyond 90 equivalent
        ↓
    playtest and tune

Reference material is evidence and inspiration, not product specification.

Do not justify a design merely because:

    "FIFA does it."

    "eFootball does it."

    "GameplayFootball does it."

Explain WHY the referenced behavior works and WHY it is appropriate for
Beyond 90.

---

# 20. Before Implementing A Feature

For any significant feature, AI should first identify:

- What system owns the feature?
- Is it client-side, server-side, or split?
- What existing modules interact with it?
- Does it need networking?
- Does it need configuration?
- Does it need UI?
- If it needs UI, what must the player understand first?
- If it needs UI, what is the primary player action and what is secondary?
- If it needs UI, which existing Beyond 90 component / pattern already owns
  most of the interaction?
- If it needs UI, what changes across keyboard/mouse, controller and touch?
- If it needs UI, how does the layout adapt to small landscape screens,
  console / TV viewing distance and safe areas?
- If it needs UI, which `docs/ui/` files apply to the task?
- Does it affect multiple game modes?
- Does it need to work across PC/mobile/console?
- Does it affect the Broadcast Camera?
- Does it need to be scalable for 3v3 through 11v11?
- Which reference is strongest for this specific system?
- Are multiple references useful for different aspects of the system?
- What principle or behavior should be extracted from each reference?
- Is real football footage relevant?
- Is there inspectable GameplayFootball source relevant to the mechanic?
- Which reference assumptions do not apply to Roblox?
- Does the chosen behavior fit Beyond 90's desired balance of responsiveness,
  football authenticity and competitive readability?
- Which parts are football logic?
- Which parts are engine-specific?
- Which parts are animation-specific?
- Which parts are AI decision-making rather than human-control assistance?
- Which parts require Roblox-specific adaptation?

Only then should implementation begin.

---

# 21. Do Not Break Existing Game Modes

When implementing a feature, design it so it can scale across the planned
formats:

- 3v3
- 5v5
- 7v7
- 11v11

Where multiple formats are already implemented, verify that the feature does
not break them.

Do not require unavailable game modes to exist merely for testing a current
milestone.

Do not assume 11v11.

If a feature is intentionally limited to a specific game mode, document
that limitation clearly.

---

# 22. Testing

After implementing a feature, test where applicable:

- Luau/runtime errors
- Server/client behavior
- Multiple players where relevant
- Existing implemented match formats
- Edge cases
- Performance
- Regression of existing systems
- Comparison against intended reference behavior where applicable

For reference-inspired mechanics, testing should evaluate both:

    DOES THE IMPLEMENTATION WORK?

and:

    DOES THE BEHAVIOR RESEMBLE THE REFERENCE PRINCIPLE WE INTENDED TO REPRODUCE?

When possible, compare Beyond 90 with relevant references side-by-side for:

- Touch cadence
- Ball spacing
- Player-ball coordination
- Acceleration/deceleration
- Turning
- Possession behavior
- Loose-ball transitions
- First-touch behavior
- Relevant mechanic-specific behavior

Only test camera transitions when the feature interacts with or can affect the
camera system.

For camera changes specifically, test:

- Ball near the player
- Ball far from the player
- Ball near the goal
- Ball crossing midfield
- Possession changes
- Rapid direction changes
- Multiple players clustered together
- Empty space
- Goal situations
- Different pitch sizes

---


For UI / UX changes specifically, testing should also evaluate where applicable:

- Visual hierarchy and primary-action clarity
- Beyond 90 football identity and visual restraint
- 1920×1080 or equivalent large landscape layout
- A smaller landscape viewport
- Phone / touch landscape
- Console / TV readability
- Roblox safe-area behavior
- Keyboard / mouse interaction
- Controller focus order, confirm and back behavior
- Touch target size and overlap with gameplay controls
- Preferred-input prompt changes
- Long usernames / club names / translated strings
- Default, hover, focus, pressed, selected and disabled states
- Loading, empty and error states where relevant
- Reduced-motion / transparency preferences where supported
- UI performance and unnecessary continuous work

For major UI screens, apply the quality gate defined in:

    docs/ui/UI_AGENT_DECISION_RULES.md

A UI task is not complete merely because it looks correct in one desktop
screenshot.

# 23. Design Principle

Beyond 90 should feel:

- Competitive
- Authentic
- Social
- Responsive
- Polished
- Modern
- Easy to understand
- Difficult to master

Avoid unnecessary complexity.

Do not confuse "player agency" with "zero assistance."

Football games may require invisible low-level assistance to convert player
intent into believable football interactions.

Assistance is acceptable when it:

- Preserves the player's intended direction/action
- Improves physical contact reliability
- Improves responsiveness
- Makes football interactions readable
- Remains competitively consistent
- Leaves tactical decisions to the player

Every system should ultimately contribute to creating memorable football
moments.

---

# 24. Long-Term Vision

Beyond 90 is intended to become more than a single Roblox football match.

The long-term vision includes:

- Multiple game modes
- Competitive leagues
- Clubs
- Rankings
- Tournaments
- Player progression
- Social systems
- Community events
- Content creation
- Broadcast-style presentation
- Potential esports/community competition

The game should be architected so that these systems can be added over time
without requiring the entire project to be rewritten.

---

# 25. Golden Rule

When uncertain, prioritize:

    FUN
    ↓
    FOOTBALL READABILITY
    ↓
    PLAYER AGENCY / SKILL EXPRESSION
    ↓
    COMPETITIVE FAIRNESS
    ↓
    RESPONSIVENESS
    ↓
    NETWORK ROBUSTNESS
    ↓
    PERFORMANCE
    ↓
    SCALABILITY
    ↓
    POLISH

Do not sacrifice core gameplay quality for unnecessary features.

Do not automate tactical decisions that should belong to the player.

Bounded assistance that helps execute the player's existing football intent is
allowed and should not automatically be treated as a loss of player agency.

Do not sacrifice competitive integrity simply to make a system easier to
implement.

Beyond 90 should first be an excellent football game.

Everything else comes after that.

---

# 26. MVP Development Rule

Beyond 90 should be developed as a sequence of small, playable milestones.

Do not implement future systems simply because they are mentioned in the
long-term vision.

At any given stage, prioritize the smallest playable version of the current
feature.

Each milestone should:

- Have a clearly defined goal.
- Be independently testable.
- Preserve existing functionality that remains valid.
- Avoid unnecessary dependencies on future systems.
- Be committed to Git once stable.

Do not implement:

- Progression before the core football loop is fun.
- Monetization before progression is established.
- Clubs before the core multiplayer experience is stable.
- Complex matchmaking before matches themselves work.
- Advanced presentation systems before the basic camera and gameplay work.

When a future system is required architecturally, create only the minimal
interface or foundation needed for the current milestone.

Do not build the full future system prematurely.

Incremental development does NOT mean preserving an unsuccessful foundation.

If playtesting repeatedly demonstrates that the current abstraction is wrong,
replace the smallest necessary part of that abstraction before adding more
patches.

---

# 27. Beyond 90 Reference Strategy

Beyond 90 should NOT be built by copying one football game.

Different references solve different football-design problems well.

The correct reference depends on the system being designed.

The general process is:

    Reference game / real football / source code
                    ↓
    Understand the underlying principle
                    ↓
    Identify what makes it feel good or work well
                    ↓
    Identify assumptions that do not apply to Roblox
                    ↓
    Adapt to Beyond 90's design goals
                    ↓
    Implement an original Roblox-native system
                    ↓
    Playtest and tune

Beyond 90 should ultimately feel like its own football game.

It should NOT become:

- FIFA on Roblox
- eFootball on Roblox
- GameplayFootball ported to Roblox
- A clone of another Roblox football game

Reference behavior should be studied aggressively.

Reference implementations should be copied only where deliberately justified,
legally permitted and technically appropriate.

Beyond 90 remains the final design authority.

## Overall Reference Map

Use this high-level map:

                              BEYOND 90
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ↓                         ↓                         ↓
     FIFA 14                   FIFA 17                 eFootball
        │                         │                         │
 Fun / responsiveness       Broadcast camera          Ball physics
 Dribbling satisfaction     Match presentation        Player weight
 Shooting satisfaction      Physical movement         First touches
 Passing satisfaction       Shielding                 Football behavior
 Sprint touches             Stadium feel              Defensive movement

                                  +
                                  │
                                  ↓
                         GameplayFootball
                                  │
                         Core control logic
                         Possession concepts
                         Ball prediction
                         Touch generation
                         Player-ball cooperation
                         Source-level research

This is NOT a universal ranking.

The strongest reference depends on the system.

## System Reference Table

| Beyond 90 System | Primary Reference | Secondary Reference |
| --- | --- | --- |
| Core control logic | GameplayFootball source | eFootball |
| Possession concepts | GameplayFootball source | eFootball |
| Ball prediction | GameplayFootball source | Beyond 90 Roblox testing |
| Player-ball cooperation | GameplayFootball source | eFootball |
| AI individual football control | GameplayFootball source | eFootball + Beyond 90 testing |
| AI ball prediction / reachability | GameplayFootball source | Beyond 90 Roblox testing |
| AI tactical positioning | GameplayFootball source + real football | Beyond 90 original team design |
| AI decision execution | Beyond 90 shared gameplay systems | GameplayFootball concepts |
| Dribbling satisfaction | FIFA 14 | eFootball |
| Sprint touches | FIFA 14 | eFootball |
| Player weight | eFootball | FIFA 17 |
| Acceleration/deceleration | eFootball | Real football |
| First touch | eFootball | Real football |
| Passing feel | FIFA 14 + eFootball | GameplayFootball |
| Shooting feel | FIFA 14 + eFootball | Real football |
| Defensive movement | eFootball | Real football |
| Physical shielding | FIFA 17 | eFootball |
| Broadcast camera | FIFA 17 / modern EA FC | Beyond 90-specific design |
| Match presentation | Modern EA FC | FIFA 17 |
| Mobile camera/HUD | FC Mobile | Beyond 90 mobile testing |
| Touch controls | eFootball Mobile | FC Mobile |
| Animation biomechanics | Real football footage | eFootball |
| Animation responsiveness | FIFA 17 / modern EA FC | eFootball |
| UI visual polish | Modern EA FC | Leading Roblox experiences |
| UI usability | Leading Roblox experiences | FC Mobile |
| Player progression | EA FC Clubs | Beyond 90 original design |
| Retention/live ops | Leading Roblox experiences | Roblox football/anime titles |
| Ball/contact SFX | Real football + eFootball | Original recordings/libraries |
| Stadium audio | EA FC + real matches | Beyond 90 implementation |
| Future anime spectacle | Roblox anime football leaders | Beyond 90 original design |

This table provides starting references.

It does not prohibit researching additional games, real football footage,
technical papers or Roblox experiences when useful.

## GameplayFootball — Source-Level Reference

GameplayFootball, specifically:

    https://github.com/vi3itor/GameplayFootball.git

is Beyond 90's primary inspectable source-level football reference.

GameplayFootball is especially useful for:

- Player/ball cooperation
- Possession evaluation
- Ball prediction
- Movement toward controllable ball states
- Touch generation
- Dribbling as repeated physical contacts
- Pass/shot contact concepts
- Player movement logic
- Football control flow
- Physical-ball behavior
- Animation/contact coordination
- AI player movement and action selection where source is relevant
- AI positioning and reachability logic where source is relevant
- AI ball prediction and interception concepts
- AI possession / support / defensive behavior where source is relevant
- Other low-level football mechanics where source is relevant

A useful conceptual model is:

    input
      ↓
    predict future ball state
      ↓
    determine whether player can control/reach ball
      ↓
    coordinate player and ball toward a valid interaction
      ↓
    reach contact position
      ↓
    apply football contact
      ↓
    ball continues physically
      ↓
    repeat

GameplayFootball should NOT be simplified into:

    ball follows player

The player and physical football cooperate to create controlled football.

## GameplayFootball Behavioral Fidelity

When GameplayFootball contains a verified algorithm that solves the exact
football-control problem being implemented, Beyond 90 may closely preserve:

- Algorithms
- Mathematical relationships
- State transitions
- Control logic
- Possession logic
- Ball prediction
- Time-to-ball relationships
- Touch-vector concepts
- Movement blending
- Contact assistance
- Timing relationships
- Player-ball coordination

when those behaviors serve Beyond 90.

The instruction:

    DO NOT PORT GAMEPLAYFOOTBALL DIRECTLY

means:

    DO NOT PORT ITS ENGINE AND C++ ARCHITECTURE LITERALLY.

It does NOT mean:

    REINVENT VERIFIED FOOTBALL LOGIC WITHOUT REASON.

The preferred workflow is:

    GameplayFootball behavior
        ↓
    Trace exact implementation
        ↓
    Understand full call chain
        ↓
    Identify football logic
        ↓
    Separate AI-only logic
        ↓
    Separate animation-specific logic
        ↓
    Separate engine-specific logic
        ↓
    Preserve useful relationships
        ↓
    Implement Roblox-native equivalent
        ↓
    Playtest
        ↓
    Improve for Beyond 90

## What May Be Ported Closely

Where useful and legally compliant, Beyond 90 may closely translate verified:

- Football algorithms
- Mathematical formulas
- State relationships
- Possession conditions
- Ball prediction concepts
- Time-to-ball logic
- Touch-vector calculations
- Ball-control relationships
- Movement blending
- Timing relationships
- Pass/shot targeting concepts
- Contact-assistance rules

Exact reference constants may be used as INITIAL tuning values only when:

1. Their meaning is understood.
2. Their units are understood.
3. Their scale relationship is understood.
4. They are converted appropriately.
5. They remain configurable where practical.

Do not assume:

    1 GameplayFootball meter = 1 Roblox stud.

Prefer meaningful ratios over raw copied values.

## What Must Not Be Ported Blindly

Do NOT automatically reproduce:

- GameplayFootball's C++ class hierarchy
- Engine abstractions
- Memory-management patterns
- Custom engine architecture
- Single-machine assumptions
- AI tactical decision-making
- Desktop-only assumptions
- Networking assumptions inappropriate for Roblox
- Large source sections without understanding
- Reference behavior that produces worse Beyond 90 gameplay

Do not build a second physics engine merely because GameplayFootball has its
own simulation infrastructure.

The correct question is:

> What behavior makes this football mechanic work?

not:

> How do we make the Luau source resemble the C++ source?

## FIFA 14 — Satisfaction And Responsiveness Reference

Use FIFA 14 primarily to study:

- Immediate player response
- Satisfying dribbling
- Sprint touches
- Passing satisfaction
- Shooting satisfaction
- Readable ball movement
- Responsive direction changes
- Arcade-like exaggeration that still reads as football

FIFA 14 is especially useful when asking:

> Does this action feel good immediately?

Beyond 90 prioritizes player satisfaction over strict simulation.

It is acceptable to exaggerate things such as:

- Ball visibility
- Ball size
- Contact clarity
- Touch separation
- Response speed
- Feedback
- Timing

when doing so improves gameplay without harming competitive integrity.

## eFootball — Football Behavior Reference

Use modern eFootball especially for:

- Player weight
- Momentum
- Acceleration/deceleration
- Ball/player separation
- First touches
- Dribbling cadence
- Sprint dribbling
- Stopping with possession
- Turning with possession
- Pass weight
- Body preparation
- Defensive movement
- Jockeying
- Player orientation
- Physicality
- Running with versus without the ball

eFootball is especially useful when asking:

> Does this behave like football?

Do not inherit unnecessary sluggishness merely because it appears realistic.

Beyond 90 should generally sit between:

    eFootball's believable football behavior

and:

    FIFA 14's responsiveness and satisfaction.

## FIFA 17 / Modern EA FC — Camera And Presentation

Use FIFA 17 and modern EA SPORTS FC especially for:

- Broadcast framing
- Match presentation
- Camera anticipation
- Look-ahead
- Horizontal panning
- Zoom behavior
- Penalty-area framing
- Possession-change response
- Long-pass framing
- Stadium presentation
- Set pieces
- Replays
- Overlays
- Presentation transitions
- Physical shielding
- Responsive animation transitions

These games provide presentation references.

They do NOT define Beyond 90's final camera implementation.

## Real Football

Real football footage should be used whenever actual football biomechanics,
contact behavior or match context are important.

Real football is especially useful for:

- Animation
- Running mechanics
- Planting
- Balance
- Hip/torso rotation
- Foot contact
- First touches
- Passing
- Shooting
- Tackling
- Jumping
- Heading
- Shielding
- Falls
- Recovery steps
- Ball/contact audio
- Stadium ambience

Real football is the highest reference for animation biomechanics.

Game references determine how that physical truth may need to be adapted for
responsive gameplay.

## Reference Decision Rule

Before a major design decision, ask:

1. What system am I actually solving?
2. Which reference is strongest for that system?
3. Is GameplayFootball source relevant?
4. Is real football footage relevant?
5. What principle makes the reference work?
6. What assumptions do not apply to Roblox?
7. What changes are required for human-vs-human multiplayer?
8. What changes are required for networking/security?
9. What changes are required for keyboard/controller/mobile parity?
10. What changes improve Beyond 90's satisfaction?
11. How will the result be validated through playtesting?

Good reasoning:

> eFootball allows more visible sprint-ball separation, improving the feeling
> of momentum, while FIFA 14 returns the ball toward the player's next action
> sooner and therefore feels more responsive. Beyond 90 should test a middle
> ground.

Bad reasoning:

> FIFA does it, so copy FIFA.

## GameplayFootball Research Documentation

Substantial GameplayFootball research should be documented under:

    docs/research/gameplay-football/

Research documents should distinguish:

- Confirmed GameplayFootball behavior
- Interpretation
- Useful concepts / port candidates
- AI-specific logic
- Animation-specific logic
- Engine-specific logic
- Roblox considerations
- Beyond 90 mapping
- Beyond 90 proposal

For each major reference behavior, state whether Beyond 90 should:

    KEEP EXISTING
    PORT CLOSELY
    ADAPT
    REPLACE
    OMIT
    DEFER

Research documentation does NOT automatically define final Beyond 90
architecture.

## Architecture Documentation

Important approved Beyond 90 architectural decisions should live separately
under:

    docs/architecture/

Research documentation describes what references do and what we learned.

Architecture documentation describes how Beyond 90 actually works.

Do not confuse behavioral similarity with architectural dependency.

## Existing Architecture Preservation Rule

Preserve existing Beyond 90 architecture where it continues to serve the
desired football behavior.

Do not create duplicate movement, ball, control, possession, camera or match
systems merely because a reference organizes them differently.

However:

    EXISTING CODE IS NOT SACRED.

If research and playtesting demonstrate that an existing Beyond 90 gameplay
abstraction is fundamentally producing worse football behavior, replacing it is
allowed.

Prefer replacing the smallest responsible abstraction rather than layering
increasing numbers of compensating thresholds, grace periods or patches onto a
failed model.

Do not preserve code purely because development time was already spent on it.

## Research Scope Rule

Research only what is relevant to the current milestone.

Do not reverse-engineer an entire external repository before continuing
development.

However, when researching one football mechanic, trace enough callers/callees to
understand the COMPLETE behavior.

## Runtime Separation

GameplayFootball must remain external to the Beyond 90 runtime source tree.

Do not vendor, copy or clone the GameplayFootball repository into:

    src/

Do not make Rojo map GameplayFootball files into Roblox Studio.

If a local clone is used for research, keep it outside the production runtime
tree or in another clearly separated development location.

GameplayFootball must never become a runtime dependency of Beyond 90.

## Licensing And Originality

Respect the license and notice requirements of GameplayFootball and every
external reference project.

If algorithms or implementation are translated closely, or substantial code is
intentionally reused:

1. Review the applicable license.
2. Determine attribution requirements.
3. Determine notice requirements.
4. Preserve required notices.
5. Mark modifications where required.
6. Document the decision.
7. Keep copied/translated material identifiable where appropriate.

Do not assume that rewriting C++ syntax into Luau automatically removes
licensing obligations.

Beyond 90 should maintain its own identity and Roblox-native architecture.

---

# 28. External Reference Source Accuracy

When discussing an inspectable external reference, especially GameplayFootball,
explicitly distinguish:

CONFIRMED FROM SOURCE

    Behavior directly demonstrated by inspected source.

INFERENCE

    A conclusion inferred from interactions between source systems.

RECOMMENDATION

    Something proposed specifically for Beyond 90.

Footage-based references such as FIFA, EA FC and eFootball should not be
described as source-confirmed implementation behavior.

For footage references, use:

OBSERVED FROM FOOTAGE

    Behavior visibly demonstrated by supplied/reference gameplay footage.

INTERPRETATION

    Reasoning about why the observed behavior feels or functions as it does.

RECOMMENDATION

    The Beyond 90 implementation proposed from that observation.

Never claim:

    "GameplayFootball does X"

unless the relevant source has actually been inspected.

If uncertain, inspect the source rather than guessing.

Avoid unnecessarily copying large source blocks into research documentation.

For substantial source-level research, record:

- Repository URL
- Branch
- Commit SHA
- Date researched
- Relevant source files
- Relevant classes/functions/symbols

If implementation work is based on a specific researched revision, preserve
that revision in the relevant research documentation.

---

# 29. Reference-Informed Implementation Workflow

For substantial systems:

    1. Inspect current Beyond 90 implementation.

    2. Identify the exact system being solved.

    3. Select the strongest relevant reference(s).

    4. Read existing Beyond 90 research documentation.

    5. Inspect GameplayFootball source if relevant.

    6. Study reference footage where relevant.

    7. Study real football where relevant.

    8. Identify the principle/behavior being reproduced.

    9. Separate:
            football behavior
            player satisfaction behavior
            AI-only behavior
            animation behavior
            presentation behavior
            engine-specific behavior

       If the current milestone involves AI, additionally separate:
            perception / world-state gathering
            tactical decision-making
            individual action selection
            movement target generation
            ball reachability / prediction
            shared football-action execution
            team-level behavior
            difficulty tuning
            engine-specific AI code

    10. Map useful behavior to current Beyond 90 modules.

    11. Decide what should:
            KEEP
            PORT CLOSELY
            ADAPT
            REPLACE
            OMIT
            DEFER

    12. Evaluate Roblox:
            physics
            replication
            network ownership
            latency
            security
            performance
            mobile
            controller
            character systems

    13. Define the smallest playable implementation milestone.

    14. Implement the Roblox-native equivalent.

    15. Test in Roblox Studio.

    16. Compare against intended reference behavior.

    17. Tune for Beyond 90.

    18. Document stable architectural decisions.

Do not default to copying.

Do not default to reinventing.

Use the best available evidence and make a deliberate Beyond 90 decision.

---

# 30. Broadcast Camera Reference Strategy

The Broadcast Camera is a defining Beyond 90 system.

Primary presentation references include:

- FIFA 17
- Modern EA SPORTS FC titles
- Professional football broadcasts

GameplayFootball may be inspected for general camera ideas, but it does NOT
define Beyond 90's Broadcast Camera.

Traditional football-game cameras often assume one user controls whichever
player currently has team focus.

Beyond 90 has a different information problem because one real player may
remain responsible for one footballer throughout the match.

Therefore Beyond 90's Broadcast Camera must be designed specifically around:

- Controlled player
- Football
- Direction of play
- Attacking goal
- Defensive context
- Likely next-play space
- Teammates
- Opponents
- Possession
- Ball velocity
- Set-piece state
- Tactical readability
- Mobile screen size
- Match format

The camera should behave more like an intelligent football camera operator than
a fixed offset attached to the avatar.

Reference priorities remain:

- Elevated broadcast perspective
- Tactical readability
- Passing-lane visibility
- Open-space visibility
- Player positioning
- Team shape
- Camera anticipation
- Smooth tracking
- Smooth zoom
- Situational framing
- Match-size-specific presets
- Minimal unnecessary movement

The camera may borrow presentation principles from FIFA/EA FC.

It must not become a direct clone.

Beyond 90's unique human-per-footballer structure takes priority.

---

# 31. Reference Design Priority

When reference-derived solutions conflict, prioritize:

    FUN
    ↓
    FOOTBALL READABILITY
    ↓
    PLAYER AGENCY / SKILL EXPRESSION
    ↓
    COMPETITIVE FAIRNESS
    ↓
    RESPONSIVENESS
    ↓
    NETWORK ROBUSTNESS
    ↓
    PERFORMANCE
    ↓
    SCALABILITY
    ↓
    POLISH

Reference fidelity is a STARTING POINT, not a higher priority than Beyond 90's
gameplay goals.

If a verified reference behavior produces excellent football in Beyond 90,
preserve it.

If Roblox constraints require an implementation change, adapt the
implementation while attempting to preserve the football behavior.

If Beyond 90 playtesting demonstrates that changing the reference behavior
creates a better experience, Beyond 90 takes priority.

Technical similarity to any reference is NOT a goal.

Football-behavior quality is.

The governing principle is:

> GameplayFootball teaches us how a working football game solved inspectable
> control problems.
>
> FIFA 14 teaches us about immediate satisfaction and responsiveness.
>
> eFootball teaches us about believable football behavior.
>
> FIFA 17 and modern EA FC teach us about presentation and camera principles.
>
> Real football teaches us the physical and biomechanical truth.
>
> Roblox determines how all of these ideas must be implemented technically.
>
> Beyond 90 determines what should ultimately be preserved, adapted, improved
> or rejected.

Study references aggressively.

Trace complete behavior.

Port proven football logic closely where appropriate.

Adapt engine implementation deliberately.

Preserve human tactical agency.

Playtest against references.

Improve where Beyond 90 can do better.

Build the final system specifically for Beyond 90.

---

# 32. Current Controlled-Ball Networking Model

Beyond 90 currently uses a hybrid authority model for controlled football.

The current prototype direction is:

    FREE BALL
        ↓
    Server network ownership

and:

    CONTROLLED BALL
        ↓
    Possessing player's client may network-own
    the real physical football
        ↓
    Server validates the resulting state

This architecture exists to keep the football responsive to the human player
controlling it.

Client network ownership does NOT mean client authority over football rules.

While a player controls the football, the client may be responsible for
low-level physical simulation such as:

- Close-control velocity correction
- Dribble movement
- Touch impulses
- Ball rotation
- Player-relative control positioning
- Responsive direction changes

The server remains authoritative over:

- Whether possession exists
- Which player is the controller
- Possession acquisition
- Possession release
- Possession transfers
- Ball resets
- Competitive validation
- Goals
- Match state
- Tackles
- Pass/shot validation
- Statistics
- Rankings
- Other competitive outcomes

The principle is:

    CLIENT MAY SIMULATE THE MOTION

            ≠

    CLIENT DECIDES WHAT THE MOTION MEANS

While Controlled, the server should validate the football using plausible
constraints such as:

- Controller identity
- Network ownership
- Player-ball distance
- Ball speed
- Vertical velocity
- Displacement
- Pitch/world bounds
- Other action-specific limits

Validation should allow normal networking and physics variation.

Do not require the client's exact physics trajectory to match a second
server-side simulation frame-for-frame.

When the football becomes Free, reset, invalid, or otherwise no longer belongs
to that player:

    server reclaims network ownership.

The current player-owned model is a prototype architecture and may later be
replaced by stronger client prediction / server reconciliation or Roblox
server-authority systems if playtesting, security requirements or competitive
integrity justify the change.

Do not change this ownership strategy casually during unrelated milestones.

---

# 33. Controlled Possession Philosophy

Beyond 90 is NOT intended to be a hardcore football physics simulator.

During clear, uncontested possession:

    PLAYER INTENT
        >
    PRESERVATION OF OLD BALL MOMENTUM

The football should feel like it belongs to the player controlling it.

Normal possession may use invisible assistance to maintain a satisfying
player-ball relationship.

Allowed controlled-ball assistance includes:

- Position correction
- Velocity matching
- Relative-velocity damping
- Direction correction
- Front-of-foot targeting
- Speed-dependent ball lead
- Short recovery/capture assistance
- Body-overlap avoidance
- Input-responsive touch planning

If the player abruptly stops, the football does not need to continue rolling
away merely because its previous velocity says it physically should.

If the player changes direction sharply, previous ball momentum may be reduced
or redirected so the football remains part of the player's intended football
action.

If the player clearly possesses the ball:

    the player gets the benefit of the doubt.

This does NOT mean possession should be a rigid weld.

The ball should still:

- Move visibly
- Rotate
- Travel between touches
- React to player speed
- React to direction changes
- Have readable spacing
- Become genuinely loose when possession is lost
- Respond to future passes, shots, tackles and deflections

Gameplay satisfaction is more important than preserving perfectly realistic
inertia during ordinary close control.

---

# 34. Possession Stability Versus Dribble Presentation

Beyond 90 separates:

    POSSESSION STABILITY

from:

    DRIBBLE PRESENTATION

These systems may cooperate but should not be confused.

## Possession Stability

A continuous low-level control system may invisibly maintain the physical
football near the controlling player.

Its responsibilities may include:

- Player-relative control targeting
- Relative-velocity damping
- Preventing routine rear lag
- Maintaining close control during stops
- Responding to direction changes
- Preventing body overlap
- Short capture/recovery assistance

This system exists so normal uncontested possession is reliable.

## Dribble Presentation

Visible touch behavior should make the football look like it is actually being
played with the feet.

Presentation may include:

- Push
- Coast
- Collect / settle
- Speed-dependent touch distance
- Speed-dependent touch cadence
- Small vertical motion
- Ball rotation
- Slight lateral variation
- Future animation synchronization

The intended relationship is:

    continuous hidden assistance
        ↓
    keeps possession stable

while:

    discrete visible touch rhythm
        ↓
    makes possession look like football

Do not make visible touch rhythm responsible for the entire stability of
possession.

Do not let the hidden possession controller make the football look permanently
welded or slide along the grass at a constant offset.

Walking should generally produce tighter touches.

Faster movement should generally produce farther and more energetic touches.

The exact values must be tuned for Beyond 90 rather than copied directly from
any reference.

---

# 35. Player Input And Locomotion Principle

Player input, locomotion and ball control should use clearly separated concepts.

Prefer the pipeline:

    RAW PLAYER INTENT
            ↓
    FOOTBALL LOCOMOTION
            ↓
    PLAYER MOVEMENT
            ↓
    BALL-CONTROL COORDINATION

Do not use movement produced by Beyond 90 itself as though it were fresh raw
player input.

Use a centralized, supported, cross-platform input abstraction where
appropriate.

The input architecture should remain suitable for:

- Keyboard
- Gamepad
- Mobile

It should expose concepts such as:

    MoveDirection
    MoveMagnitude
    SprintRequested

without requiring unrelated gameplay systems to independently inspect physical
keyboard keys.

Movement should have weight without feeling sluggish.

Normal movement may include:

- Acceleration
- Deceleration
- Turn-speed response
- Direction-change speed loss
- Short reversal braking

However:

    RESPONSIVENESS > REALISTIC LOCOMOTION DELAY

A 180-degree reversal should not place the player into a long slow-motion state.

Small direction changes should react quickly.

Sharp direction changes may lose more speed.

Stopping should produce visible but short deceleration rather than an
instantaneous freeze or long skating motion.

For the current control philosophy:

    normal movement is non-sprint movement

and:

    explicit sprint input requests faster movement.

Exact movement speeds are tuning values and should remain configurable.

---

# 36. Ball Direction-Change Principle

The football should respond promptly to changes in human movement intent.

For ordinary possession:

45-degree turn:
    Fast response with minimal disruption.

90-degree turn:
    Ball begins entering the new control lane immediately while player movement
    turns smoothly.

180-degree reversal:
    Previous ball momentum may be cancelled aggressively, short capture
    assistance may be used, and the football should remain within the player's
    control area.

Do not require the football to finish an obsolete touch or trajectory after the
player has clearly changed direction.

The ball-control target may respond somewhat faster to raw player intent than
the avatar's full locomotion velocity.

Custom animations should later improve the visual quality of these actions.

However:

    ANIMATION MUST NOT BE USED TO HIDE BROKEN GAMEPLAY MECHANICS.

Direction changes should already function correctly before final animations are
added.

---

# 37. Gameplay Satisfaction Versus Simulation

When choosing between equally fair implementations, prioritize the one that
produces the better football-game experience.

Beyond 90 may deliberately exaggerate or assist:

- Ball size
- Touch spacing
- Touch lift
- Dribble responsiveness
- Ball rotation
- Movement responsiveness
- Possession retention
- Contact assistance

when doing so improves:

- Readability
- Responsiveness
- Satisfaction
- Competitive control
- Visual football feel

Real-world proportional accuracy is not automatically the goal.

The relevant question is:

> Does this feel convincing and satisfying as a competitive football game?

Beyond 90 is free to make behavior:

- More responsive
- More forgiving
- More readable
- More exaggerated
- More arcade-oriented

when playtesting demonstrates that the result is better.

The hierarchy in the Golden Rule remains authoritative.

Reference questions may be separated as:

    FIFA 14
        → Does it feel immediately satisfying?

    eFootball
        → Does it behave convincingly like football?

    GameplayFootball
        → How can the underlying football-control problem be solved?

    Real football
        → What is physically/biomechanically happening?

    FIFA 17 / modern EA FC
        → How should it be presented to the player?

Beyond 90 should combine those lessons rather than automatically choosing one.

---

# 38. Mobile Reference Strategy

Mobile football references should primarily influence mobile input, HUD and
small-screen adaptation.

They should NOT define the underlying football simulation solely because mobile
has fewer controls.

## FC Mobile

Study primarily for:

- Touch-friendly HUD
- Button layout
- Small-screen readability
- Camera readability
- Menu density
- Match overlays
- Mobile presentation

## eFootball Mobile

Study primarily for:

- Touch movement
- Contextual football controls
- Input simplification
- Mapping football intent to limited touch controls

For shared football mechanics:

    console/PC references
            +
    GameplayFootball source
            ↓
    shared football mechanic
            ↓
    cross-platform input layer

The underlying mechanic should then be exposed appropriately through:

- Keyboard/mouse
- Controller
- Touch

Mobile input limitations should not unnecessarily weaken football depth.

---

# 39. Animation Reference Strategy

Animation should follow this hierarchy:

    REAL FOOTBALL FOOTAGE
            ↓
    biomechanics / truth
            ↓
    eFootball
            ↓
    realistic movement converted to playable animation
            ↓
    FIFA 17 / modern EA FC
            ↓
    responsiveness / transitions / presentation
            ↓
    Blender
            ↓
    original Beyond 90 animation

Do not animate purely from memory.

Study real football for:

- Running
- Acceleration
- Deceleration
- Direction changes
- Planting
- Balance
- Hip rotation
- Torso rotation
- First touch
- Passing
- Shooting
- Tackling
- Heading
- Jumping
- Shielding
- Falling
- Recovery

Gameplay actions should support semantic animation markers such as:

- BallContact
- PlantFoot
- Footstep_L
- Footstep_R
- ActionCommit
- Recover
- Takeoff
- Landing
- TackleContact

Conceptually:

    player input
        ↓
    action validation
        ↓
    animation starts
        ↓
    windup
        ↓
    BallContact
        ↓
    approved gameplay interaction
        ↓
    follow-through
        ↓
    Recover

Animation timing may help determine WHEN an already valid football action
makes contact.

Animation must not independently determine WHETHER a competitive action is
valid.

Beyond 90's custom animation milestone may be deferred while gameplay
foundations are built.

Gameplay systems should preserve logical hooks so animations can be integrated
later without requiring complete mechanic rewrites.

---

# 40. UI / UX Reference Strategy

Beyond 90 has a dedicated UI guidance package under:

    docs/ui/

This package exists so AI agents do not improvise the product's visual language
from vague instructions such as "modern", "premium", "football" or "blue".

The approved Beyond 90 UI direction is:

> A premium contemporary football game presented with modern sports-broadcast
> clarity and Roblox-native usability.

It is NOT intended to become a sci-fi, cyberpunk or hyper-futuristic interface.

## UI Documentation Read Order

For any substantial UI / UX task, first read:

    docs/ui/README_UI_AGENT.md
    docs/ui/UI_AGENT_DECISION_RULES.md
    docs/ui/UI_DESIGN_SYSTEM.md

Then read the relevant task-specific guidance:

    docs/ui/UI_COMPONENTS_AND_PATTERNS.md
        → menus, HUD, scorebug, player cards, clubs, squad, settings,
          post-match, modals, toasts, loading / empty / error states

    docs/ui/UI_RESPONSIVE_INPUT.md
        → PC, console / TV, controller, touch, mobile, safe areas,
          responsive behavior and input adaptation

    docs/ui/UI_ACCESSIBILITY_LOCALIZATION.md
        → readability, contrast, focus, reduced motion / transparency,
          color use and localization

    docs/ui/UI_ROBLOX_IMPLEMENTATION.md
        → Roblox implementation, layout systems, constraints, input,
          reusable styling, performance and validation

Use:

    docs/ui/UI_RESEARCH_SOURCES.md

when the external rationale, platform documentation or research trail needs to
be checked. It does not need to be reread for every small UI edit.

## UI Authority

For UI-specific decisions, use this authority order:

    explicit current user instruction
            ↓
    AGENTS.md project-wide constraints
            ↓
    existing valid Beyond 90 production UI architecture / reusable components
            ↓
    docs/ui/UI_AGENT_DECISION_RULES.md
            ↓
    other task-relevant docs/ui/ files
            ↓
    external reference games and generic UI conventions

Do not create a parallel design system merely because a new component is faster
to implement in isolation.

Do not override gameplay, networking, milestone, moderation or asset-upload
rules from this `AGENTS.md` using a UI reference document.

## Approved Beyond 90 Visual Identity

The intended UI character is:

- Athletic
- Confident
- Competitive
- Premium
- Modern
- Clean
- Stadium-lit
- Broadcast-oriented
- Football-first

The football identity should come primarily from:

- Players
- Kits and shirt numbers
- Club crests
- Footballs and pitches
- Match clocks and scorelines
- Formations and positions
- Player cards
- Statistics
- Divisions / seasons / trophies
- Stadium imagery
- Broadcast-style match events

Do NOT make the football identity depend on generic futuristic decoration.

Avoid using these as the default visual language:

- Holographic panels
- Circuit-board patterns
- Sci-fi grids
- Scanlines
- Chromatic aberration
- Glowing borders on every card
- Transparent glass everywhere
- Excessive cyan / purple gradients
- Excessive pill-shaped controls
- Random hexagonal UI
- Floating techno glyphs
- Constant parallax
- Continuous decorative particles
- Cyberpunk / techno typography
- Thin unreadable fonts

Use glow, transparency, violet and cyan selectively rather than everywhere.

When uncertain, use the test defined in the UI decision rules:

> If the football content were removed, would this look like a spaceship,
> cyberpunk terminal, crypto dashboard or generic futuristic game menu?

If yes, simplify the technology styling and strengthen football-specific
presentation instead.

## Approved Mockup Direction

The approved Beyond 90 main-menu mockup should be treated as the current visual
north star unless a later approved direction replaces it.

Important traits include:

- Dark nighttime stadium atmosphere
- Deep navy / charcoal UI surfaces
- Bright white primary typography
- Restrained electric-blue interaction / selection states
- Limited violet for ranked, progression or special reward emphasis
- Large football-player imagery
- Strong rectangular navigation cards
- Clear information hierarchy
- Controlled glow rather than glow everywhere
- Premium sports presentation rather than sci-fi presentation

Do not copy one screenshot mechanically into every screen.

Preserve the visual principles while adapting layout and information hierarchy
to the task.

## Modern EA SPORTS FC

Use primarily for:

- Football-information hierarchy
- Player profiles
- Player cards
- Club pages
- Season / division presentation
- Lineups
- Statistics
- Match HUD
- Post-match presentation
- Rewards
- Broadcast polish

Do not inherit Ultimate Team-style menu complexity merely because it appears
premium.

Beyond 90 should aim for:

    EA FC-quality football presentation
                +
    Roblox-level speed and clarity
                +
    Beyond 90's own identity

EA FC is a reference, not a template.

## FIFA 17

Use primarily for:

- Clean football presentation
- Broadcast overlays
- Match-event graphics
- Score / clock presentation
- Stadium context
- Restrained sports framing

It may be especially useful when Beyond 90 needs a cleaner reference than a
more content-dense modern football-game menu.

## Leading Roblox Experiences

Study leading Roblox experiences for:

- Fast navigation
- Low-friction onboarding
- Mobile usability
- Controller navigation
- Responsive layout
- Clear interaction states
- Social UI
- Platform-native conventions
- Purchase-flow clarity where monetization is relevant

Do not copy generic Roblox simulator UI conventions that weaken Beyond 90's
premium football identity.

## FC Mobile

Use primarily for:

- Compact layouts
- Touch targets
- Small-screen hierarchy
- Mobile HUD readability
- Information reduction on constrained screens

Mobile should adapt the information architecture, not simply shrink the desktop
screen.

## Contextual Gameplay UI

Match UI should show what the player needs now.

Prefer contextual football prompts over permanently displaying every possible
control.

Conceptually:

    PLAYER CONTEXT
          ↓
    RELEVANT ACTIONS
          ↓
    CURRENT HUD / PROMPTS

For example:

- In possession → relevant attacking actions
- Out of possession → relevant defensive actions
- Set piece → set-piece controls
- Goalkeeper state → goalkeeper-relevant actions

Do not allow control-prompt density to obscure the pitch.

## Broadcast Camera Readability

Because Beyond 90 uses a broadcast-style camera, gameplay UI must remain useful
when the controlled footballer is visually small and the camera is pulled back.

Therefore:

- Critical match information must read quickly
- Controlled-player indicators must remain distinguishable
- Minimap information must be clear
- Text must survive stadium lighting and grass backgrounds
- Persistent HUD should remain sparse
- Large opaque panels must not block active play
- Mobile HUD density should be lower than desktop where necessary

The UI and Broadcast Camera should be designed as cooperating systems.

## Cross-Platform Requirement

A significant UI task is not complete after one desktop screenshot.

Where applicable, define and test behavior for:

- Keyboard / mouse
- Controller / gamepad
- Touch
- Phone landscape
- Tablet / medium landscape
- Desktop
- Console / TV

The same hierarchy does not require the same physical arrangement on every
device.

It is acceptable and often preferable to:

- Stack panels
- Hide tertiary information
- Convert side panels into tabs / drawers
- Shorten non-critical copy
- Increase touch targets
- Reposition controls away from thumb zones
- Reduce HUD density

Do not shrink the entire desktop UI proportionally until it becomes unreadable.

## Existing UI First

Before creating a UI component, inspect the repository for:

- Existing shared components
- Existing design tokens / theme values
- Existing navigation patterns
- Existing input-aware behavior
- Existing responsive helpers
- Existing animation helpers
- Existing modal / toast / state patterns

Prefer:

    REUSE
        ↓
    EXTEND
        ↓
    ADD VARIANT
        ↓
    CREATE NEW

in that order when practical.

Do not create duplicate button, panel, modal, card, tab, focus or input systems.

## UI Decision Workflow

For a substantial UI task:

    1. Read the required docs/ui guidance.

    2. Inspect the existing Beyond 90 UI architecture.

    3. Identify the player's primary task.

    4. Identify the information hierarchy.

    5. Identify existing reusable components.

    6. Determine desktop / controller / touch behavior.

    7. Determine responsive changes for constrained screens.

    8. Determine loading / empty / error / disabled states.

    9. Implement the smallest coherent change.

    10. Test in Roblox Studio where practical.

    11. Apply the UI quality gate.

    12. Stop before unrelated redesign or the next milestone.

Do not "improve" unrelated screens during a focused UI task unless explicitly
requested.

## UI Quality Gate

For major UI screens, use the rubric in:

    docs/ui/UI_AGENT_DECISION_RULES.md

At minimum, review:

- Primary task clarity
- Information hierarchy
- Football identity
- Beyond 90 brand fit
- Readability
- Gamepad usability
- Touch usability
- Responsiveness
- Accessibility
- Visual restraint

A screen that looks visually polished but fails controller, touch, readability
or hierarchy is not complete.

## UI Asset Safety

All UI work remains subject to the Roblox asset moderation and upload rules in
Section 57 of this file.

External screenshots, football-game references and UI inspiration images are
development references only.

Do not import external reference screenshots into Roblox merely to compare
visuals.

Do not create Roblox-hosted screenshots / visual-QA assets unless the artifact
itself is intentionally meant to become a real production asset.

Use local-first visual QA.


# 41. Progression And Competitive Integrity

EA FC Clubs is a strong conceptual reference for Beyond 90 because players
control their own footballer rather than an entire team.

Study concepts such as:

- Player identity
- Positions
- Match ratings
- Career statistics
- Club identity
- Club progression
- Divisions
- Leagues
- Seasonal competition
- Trophies
- Persistent history

However, Beyond 90 should remain skill-first.

Preferred progression philosophy:

    PLAY
      ↓
    PERFORM
      ↓
    GAIN XP / REPUTATION / STATUS
      ↓
    UNLOCK IDENTITY / PRESTIGE

Possible rewards include:

- Cosmetics
- Boots
- Gloves
- Hairstyles/accessories
- Celebrations
- Emotes
- Player-card designs
- Profile banners
- Titles
- Badges
- Safe animation variants
- Club cosmetics
- Tifos
- Stadium/locker-room identity
- Prestige indicators

A veteran player should look prestigious without automatically possessing
superior football fundamentals.

Serious competitive modes must avoid permanent paid advantages such as:

- Paid pace
- Paid stamina
- Paid shot power
- Paid tackling strength
- Paid curve
- Paid gameplay cooldown advantages

The human player's skill should remain the dominant source of competitive
performance.

---

# 42. Retention And Live-Ops References

Study successful Roblox experiences, including football and anime-football
titles where relevant, for:

- Daily reasons to return
- Weekly objectives
- Season cadence
- Limited events
- Cosmetic collection
- Social status
- Creator-driven launches
- Update communication
- Event rewards
- Progression pacing
- Reactivation
- Community hype

Extract retention psychology and live-ops lessons.

Do not automatically reproduce:

- Pay-to-win systems
- Excessive RNG
- Predatory monetization
- Gameplay-power monetization
- Mechanics inappropriate for Beyond 90's competitive core

Retention should support the football platform rather than distort the football.

---

# 43. Audio / SFX Reference Strategy

## Real Football

Use real football as the main truth source for:

- Boot/ball contact
- Ball bounce
- Net impact
- Post/crossbar impacts
- Whistles
- Player collisions
- Stadium ambience
- Crowd behavior

## eFootball

Study especially for differentiating football contacts such as:

- Light touch
- Dribble touch
- Short pass
- Driven pass
- Cross
- Normal shot
- Power shot
- Header
- Bounce
- Post
- Crossbar
- Net

Do not use one generic ball-hit sound for every interaction.

Sound intensity and timbre should communicate gameplay force.

## EA FC

Study for:

- Stadium atmosphere
- Layered crowds
- Broadcast ambience
- Attack anticipation
- Shot reactions
- Saves
- Misses
- Goals
- Fouls
- Cards
- Late-match intensity
- Celebrations

Future crowd behavior should react to match context.

Conceptually:

    normal possession
          ↓
    attack develops
          ↓
    dangerous situation
          ↓
    shot
          ↓
    save / miss / goal
          ↓
    appropriate crowd reaction

---

# 44. Future Anime-Inspired Expansion

Beyond 90's core competitive identity remains:

- Authentic football behavior
- Skill-first gameplay
- Human-controlled footballers
- Broadcast presentation
- Organized competition

The architecture should not unnecessarily prevent future ORIGINAL
anime-inspired football modes or expansions.

Future content may explore:

- Heightened abilities
- Stylized VFX
- Original football archetypes
- Dramatic skill animations
- Special presentation
- Themed progression
- Event stories
- Collectible identity
- Unique rulesets

Roblox anime-football experiences such as Blue Lock: Rivals, Azure Latch and
other successful titles may be studied for:

- Spectacle
- Ability readability
- VFX hierarchy
- Character identity
- Event cadence
- Collection
- Community hype
- Progression presentation
- Monetization presentation

These references must NOT redefine Beyond 90's authentic competitive core.

If an anime-inspired mechanic conflicts with authentic Ranked/Clubs gameplay,
keep it in a separate ruleset.

Conceptually:

    Beyond 90
        │
        ├── Authentic Football
        │      ├── Ranked
        │      ├── Clubs
        │      ├── 3v3 / 5v5
        │      ├── 7v7
        │      └── 11v11
        │
        └── Themed / Anime-Inspired Modes
               ├── Abilities
               ├── Special rules
               ├── VFX
               └── Themed progression

Do not copy protected anime IP without licensing.

Anime-inspired Beyond 90 content should use original:

- Names
- Characters
- Abilities
- Stories
- Terminology
- Visual language
- Designs

---

# 45. Roblox-Native Constraints Override References

No external reference is more important than the requirements of the actual
platform Beyond 90 runs on.

Every system must account for:

- Roblox physics
- Roblox replication
- Network latency
- Server authority
- Exploit resistance
- Network ownership
- Client prediction
- 22-player eventual match load
- Performance
- Mobile devices
- Controller
- Keyboard/mouse
- Character rigs
- Animation replication
- Roblox visual scale
- Maintainability
- Production complexity
- AI CPU cost
- AI update frequency
- AI path / target calculation cost
- Server load from multiple AI footballers
- Human-to-AI and AI-to-human handoff behavior

When an excellent reference behavior cannot be reproduced safely or
efficiently:

    preserve the INTENT

rather than mechanically preserving its implementation.

---

# 46. Beyond 90 Product Identity

The combined reference target is approximately:

    FIFA 14
        → satisfaction / responsiveness

    eFootball
        → believable football behavior

    GameplayFootball
        → inspectable football-control logic

    FIFA 17 + modern EA FC
        → camera / broadcast / presentation

    Real football
        → physical and animation truth

    EA FC Clubs
        → footballer / club progression concepts

    Leading Roblox experiences
        → platform UX / retention / live ops

    FC Mobile + eFootball Mobile
        → mobile adaptation

    Roblox anime-football leaders
        → future themed-mode lessons

                    ↓

                BEYOND 90

Beyond 90 must remain an original Roblox-native football platform.

The target is:

> Authentic enough to read as football, responsive enough to feel immediately
> satisfying, deep enough to reward mastery, fair enough to support serious
> competition, and flexible enough to grow into a broader football platform.

No individual reference supersedes this identity.

---

# 47. AI Footballer Product Direction

AI-controlled footballers are a planned Beyond 90 system.

They exist for two separate but related reasons:

    DEVELOPMENT UTILITY
            +
    PLAYER-FACING GAME FEATURES

Both purposes should share the same underlying AI footballer architecture where
practical.

## Development Utility

AI should eventually allow a developer to launch a test match without finding
many human players.

Important development uses include:

- Testing passing options
- Testing receiving
- Testing shooting under pressure
- Testing defending
- Testing goalkeeper interactions
- Testing possession changes
- Testing positioning
- Testing offside
- Testing restarts
- Testing team shape
- Testing the Broadcast Camera with multiple active footballers
- Testing networking with many footballers
- Testing match flow
- Testing tactical situations

This is why AI should not be postponed until every other system is finished.

Once the fundamental individual football actions exist, AI becomes a tool that
accelerates the rest of development.

## Player-Facing Uses

Planned player-facing AI use cases include:

- Training
- Tutorials
- Single-player play
- Practice matches
- Skill drills
- Incomplete-team filling where allowed
- Temporary disconnected-player replacement where appropriate
- Potential co-op versus AI modes
- Potential special / event modes

These use cases are approved future directions.

Do not implement all of them merely because the AI foundation exists.

Each mode still needs its own product design and fairness rules.

## Human-First Competitive Identity

Beyond 90's defining fantasy remains real-player football.

Therefore:

    ENOUGH HUMAN PLAYERS AVAILABLE
                ↓
    PREFER HUMAN FOOTBALLERS

AI is not an excuse to abandon the human-per-footballer identity.

Instead AI should solve availability, practice, testing and mode-specific needs.

Future serious competitive rules may choose among policies such as:

- Human-only
- Human-preferred with AI fill
- Temporary AI only after disconnect
- AI allowed below a certain matchmaking population
- AI allowed only in unranked modes

Do not hardcode one universal policy into low-level AI systems.

The match/rules layer should decide whether a slot may be occupied by AI.

---

# 48. AI Footballer Architecture Principles

AI should be designed as another **controller of a footballer**, not as a
separate category of physics object.

Conceptually prefer:

    HUMAN INPUT PROVIDER ─────┐
                              │
                              ↓
                      FOOTBALLER INTENT
                              ↓
                     SHARED GAMEPLAY SYSTEMS
                              ↓
                         PLAYER + BALL
                              ↑
                              │
    AI INTENT PROVIDER ───────┘

The exact module names may differ.

The architectural principle should remain.

## Shared Execution

Human-controlled and AI-controlled footballers should share, where practical:

- Locomotion
- Acceleration / deceleration
- Turning constraints
- Ball reachability rules
- Ball possession rules
- Dribble mechanics
- First-touch mechanics
- Passing mechanics
- Shooting mechanics
- Tackling mechanics
- Shielding mechanics
- Goalkeeper mechanics when applicable
- Animation action interfaces
- Collision rules
- Stamina rules if stamina is later implemented
- Competitive validation

AI should express intent through supported gameplay interfaces.

Avoid special bot-only shortcuts such as:

    AI wants pass
        ↓
    directly set ball velocity perfectly

when a human must instead use the normal validated passing mechanic.

Prefer:

    AI chooses pass target / power / type
        ↓
    shared passing action
        ↓
    normal contact / validation / ball result

This keeps AI useful for testing the actual game rather than a fake parallel
version of it.

## Controller Separation

Keep these concepts separate:

    WHO DECIDES?

from:

    HOW IS THE FOOTBALL ACTION EXECUTED?

Human input answers the first question for a human footballer.

AI decision logic answers the first question for an AI footballer.

Shared gameplay mechanics should answer the second question for both.

## AI Does Not Need To Emulate Keyboard Input

Do not force bots to press virtual WASD keys unless that is genuinely the clean
existing abstraction.

The preferred shared layer is football intent, for example concepts such as:

- DesiredMoveDirection
- DesiredMoveMagnitude
- SprintRequested
- DesiredFacingDirection
- RequestedAction
- RequestedPassTarget
- RequestedShotTarget

These are conceptual examples, not mandatory field names.

Human input may generate those intents from keyboard/controller/touch.

AI may generate them from decision logic.

## Server Authority

AI exists inside the trusted game runtime, but its actions must still obey the
same competitive state rules.

The server should remain authoritative over important outcomes such as:

- Possession
- Goals
- Score
- Tackles
- Match state
- Restarts
- Statistics
- Competitive outcomes

Do not weaken server validation merely because an action originated from a bot.

## AI Simulation Location

Do not decide prematurely that all AI logic must run every frame on the server.

When the AI milestone begins, determine deliberately:

- Which decisions must run server-side
- Which movement intent can be updated at lower frequency
- Which presentation work belongs on clients
- What data must replicate
- What can be predicted/interpolated
- How many active AI footballers must be supported

AI decisions generally do not require RenderStepped-style frequency.

Prefer bounded decision/update frequencies appropriate to the behavior.

For example, high-level decisions may update much more slowly than locomotion
execution.

Performance must account for eventual 11v11 matches.

---

# 49. AI Perception, Decisions And Fairness

AI behavior should be decomposed instead of implemented as one giant script.

A useful conceptual stack is:

    WORLD / MATCH STATE
            ↓
        PERCEPTION
            ↓
      SITUATION MODEL
            ↓
     TACTICAL DECISION
            ↓
   INDIVIDUAL ACTION CHOICE
            ↓
      MOVEMENT / ACTION INTENT
            ↓
   SHARED FOOTBALL EXECUTION

The exact architecture may differ after GameplayFootball research.

## Perception

AI may need awareness of:

- Ball position
- Ball velocity
- Predicted ball position
- Possession
- Teammates
- Opponents
- Goal locations
- Pitch boundaries
- Current position / role
- Team attacking direction
- Match state
- Offside line
- Open space
- Passing lanes
- Reachability
- Pressure

Do not automatically give the AI perfect exploitation of every known value.

The game engine may technically know exact states, but difficulty and fairness
may require bounded reaction, awareness or prediction accuracy.

## Decision Categories

AI decisions may eventually include:

- Hold position
- Move into support space
- Make a run
- Drop deeper
- Press
- Cover
- Mark
- Intercept
- Approach loose ball
- Receive
- Dribble
- Pass
- Shoot
- Clear
- Shield
- Tackle
- Goalkeeper action

These are AI decisions because the footballer itself is AI-controlled.

Do not confuse these with assistance for human footballers.

## No Superhuman AI By Accident

Do not create difficulty by secretly changing fundamental football physics.

Avoid giving higher-difficulty AI:

- Higher top speed than allowed human equivalents
- Stronger shots purely because it is AI
- Impossible turn rates
- Instant reaction to every input
- Perfect tackles through hidden rules
- Perfect first touches regardless of situation
- Impossible ball knowledge

Prefer difficulty tuning through football intelligence, for example:

- Decision quality
- Reaction delay
- Prediction quality
- Positional awareness
- Pass selection
- Risk tolerance
- Press timing
- Marking quality
- Shooting choice
- Error rates
- Tactical discipline

The underlying competitive rules should remain consistent.

## Reproducible Testing

Where useful, AI behavior should support deterministic or seeded test scenarios
so development issues can be reproduced.

Examples:

- Same kickoff setup
- Same player positions
- Same AI difficulty
- Same scripted opening intent

Do not make all normal gameplay deterministic.

This is a testing capability, not a requirement for live matches.

---

# 50. GameplayFootball AI Source-Level Reference Strategy

GameplayFootball is the primary inspectable source reference for Beyond 90's
future AI footballer work where its source actually covers the relevant
behavior.

Repository:

    https://github.com/vi3itor/GameplayFootball.git

Do NOT begin Beyond 90 AI implementation from assumptions about how
GameplayFootball works.

Inspect the source first.

## Required AI Research Questions

When the AI milestone begins, investigate at minimum:

- How players choose movement targets
- How players predict / approach the football
- How reachability is evaluated
- How possession affects decision-making
- How support positions are generated
- How defensive positioning works
- How marking / pressing / interception decisions are made
- How passing decisions are represented
- How shooting decisions are represented
- How dribbling decisions are represented
- How players cooperate with the ball-control system
- How team-level tactics influence individual players
- How roles / positions influence behavior
- How AI decides when to sprint
- How AI handles loose balls
- How AI handles transitions between attack and defense
- How goalkeeper AI works if relevant
- Which systems are generic football logic
- Which systems exist only because GameplayFootball controls an entire team
- Which systems are tightly coupled to GameplayFootball's animation system
- Which systems are engine-specific

Trace enough callers and callees to understand complete behavior.

Do not inspect isolated functions and guess at their meaning.

## Required Research Documentation

Substantial AI research should be documented under a path such as:

    docs/research/gameplay-football/ai/

or another clearly organized subdirectory within:

    docs/research/gameplay-football/

Each research document should record:

- Repository URL
- Branch
- Commit SHA
- Date researched
- Relevant files
- Relevant classes
- Relevant functions / symbols
- Confirmed behavior
- Inference
- AI-specific behavior
- Team-level behavior
- Animation-specific behavior
- Engine-specific behavior
- Useful mathematical / state relationships
- Roblox constraints
- Beyond 90 mapping
- Proposed decision for each relevant behavior

Use the established decision labels:

    KEEP EXISTING
    PORT CLOSELY
    ADAPT
    REPLACE
    OMIT
    DEFER

## Do Not Port The Engine

The AI project must not become an attempt to reproduce GameplayFootball's C++
architecture in Luau.

Do not port blindly:

- Class hierarchy
- Engine object model
- Threading assumptions
- Memory management
- Rendering architecture
- Desktop-only input assumptions
- Single-machine simulation assumptions
- AI logic that only makes sense when one user controls an entire team

Preserve football intelligence and mathematical relationships when useful.

Implement the result in a Roblox-native architecture.

## Licensing

The existing GameplayFootball licensing rules in this document apply equally
to AI research and implementation.

If algorithms or source are translated closely:

- Review the license
- Preserve required notices
- Record attribution decisions
- Mark substantial translations where required

Do not assume AI code is exempt from those requirements.

---

# 51. AI Development Stages

Do not attempt full professional football AI in one milestone.

Build it in stages.

## AI v1 — Development / Training Footballers

The first AI milestone should primarily make automated football matches useful
for development testing.

Likely capabilities include:

- Spawn into a valid team / position
- Move toward a target using normal locomotion
- Respect pitch boundaries
- Face useful directions
- Follow basic positional anchors
- Approach loose footballs
- Predict simple reachable ball states
- Receive using normal first-touch mechanics
- Dribble using normal controlled-ball mechanics
- Pass using normal passing mechanics
- Shoot using normal shooting mechanics
- Defend at a basic level
- Attempt interceptions
- Maintain enough spacing to create useful test scenarios
- Use existing goalkeeper systems if an AI goalkeeper is required for the test

AI v1 does not need sophisticated tactics.

Its success criterion is:

> Can AI footballers participate in the real Beyond 90 mechanics well enough
> that developers can test matches without assembling many humans?

## AI v2 — Match Integration And Team Behavior

After basic AI individuals work, add team-level football behavior such as:

- Formation positions
- Role-aware positioning
- Team shape
- Width / depth
- Support runs
- Passing options
- Defensive lines
- Press / cover relationships
- Marking
- Transition behavior
- Offside awareness
- Restart positioning
- Basic tactical instructions
- Human / AI mixed teams
- Safe human↔AI slot handoff
- Fill-in policy integration

This is the stage where AI becomes suitable for incomplete-team filling and
more complete single-player matches.

## AI v3 — Advanced Football Intelligence

Only after the core game is stable should advanced AI be considered.

Possible future work includes:

- Position-specific intelligence
- Tactical styles
- Different risk profiles
- Adaptive pressing
- Advanced combination play
- Overlaps / underlaps
- Runs behind
- Rotations
- Game-state awareness
- Score/time-aware risk
- Difficulty personalities
- Training drill behaviors

Do not implement these prematurely.

---

# 52. Human ↔ AI Team Slot Handoff

Future AI fill requires explicit ownership of a footballer slot.

Conceptually:

    TEAM SLOT
        ↓
    HUMAN OR AI CONTROLLER
        ↓
    SAME FOOTBALLER GAMEPLAY SYSTEMS

A slot should not need a completely different footballer implementation merely
because the controller changes.

## Human Replaces AI

When a real player becomes available, a mode that allows replacement should be
able to transfer an AI-controlled slot to the human safely.

Prefer safe handoff moments such as:

- Before kickoff
- Dead ball
- Restart
- Halftime
- Other controlled transition

An immediate live handoff may be supported later if it can be made reliable.

Do not create unfair teleportation or possession changes just to perform a
handoff.

## AI Replaces Disconnected Human

If a mode supports temporary AI replacement after disconnect:

- Preserve the team slot
- Preserve appropriate match state
- Prevent duplicated controllers
- Revoke the departed client's authority / network ownership
- Transfer control safely
- Allow reconnect / replacement according to mode rules

The match layer should own these policies.

Low-level AI logic should not decide whether a human should be replaced.

## Identification

Future UI should make AI-controlled players understandable where appropriate.

Do not intentionally disguise a bot as a human player in contexts where that
would mislead users.

Exact presentation can be designed later.

---

# 53. AI Performance And Scalability

AI must eventually scale to football scenarios with many active players.

Design for the possibility of:

    11v11
        ↓
    MANY OR ALL SLOTS TEMPORARILY AI

especially in development or single-player testing.

Do not assume every AI needs expensive logic every frame.

Use layered update frequencies where appropriate.

Conceptually:

    HIGH-LEVEL TACTICS
        slower updates

    LOCAL DECISIONS
        moderate updates

    MOVEMENT EXECUTION
        normal gameplay update path

    VISUAL PRESENTATION
        client rendering / animation path

Potential performance concerns include:

- Repeated Workspace searches
- Excessive raycasts
- Recomputing team data per AI
- Per-frame pathfinding
- Large temporary allocations
- Every AI independently rebuilding the same tactical state
- Full-precision prediction when a cheaper approximation is sufficient

Prefer shared cached match context where appropriate.

Never optimize by destroying football quality before profiling identifies the
actual bottleneck.

---

# 54. Development Milestone Roadmap

The roadmap below defines the current intended order from the present gameplay
prototype toward a launch-ready Beyond 90.

It is a **development sequence**, not a promise that every milestone will have
the same size.

Milestones may be split when implementation or playtesting proves that a scope
is too large.

Milestones may be revisited when a foundation proves inadequate.

Do not silently skip dependencies merely to reach later features faster.

The current principle is:

    BUILD
      ↓
    PLAYTEST
      ↓
    COMPARE TO REFERENCES
      ↓
    FIX THE FOUNDATION
      ↓
    THEN ADD THE NEXT DEPENDENCY

## Milestone 5.0A — Controlled-Ball / Broadcast Camera Foundation

Status at the time this roadmap was added:

    IMPLEMENTED / CURRENTLY UNDER PLAYTEST

Scope included:

- Controlled-ball Push / Coast / Collect changes
- Stationary Settle hysteresis
- Football visual asset integration
- R15 runtime diagnostics
- Initial Broadcast Camera architecture
- Pitch metadata for camera use
- InputAction-based development camera toggle

Do not assume 5.0A is permanently final.

Later playtesting may require changes to its controlled-ball constants or
camera behavior.

## Milestone 5.0B — Locomotion, Player Scale, Camera & Testability Pass

Current next milestone.

Primary scope:

- Faster football sprint speed
- FIFA 14-informed acceleration / sprint responsiveness
- Retuning controlled-ball sprint behavior for the faster player
- Auto Sprint toggle through the input abstraction
- Small player-height experiment around the current 6-stud baseline
- R15 structure / appearance verification
- Closer FIFA 17-informed Broadcast Camera framing
- Controlled-player-primary camera anchoring
- Smooth useful zoom
- Camera look-ahead
- Broadcast spawn/startup fix
- First Person testing camera
- Development camera UI
- Stadium streaming / distant-visibility investigation
- StyleLink warning investigation

Do NOT implement passing, shooting or AI footballers in 5.0B.

## Milestone 5.0C — Controlled-Ball Foundation Lock

Goal:

> Stabilize locomotion + possession enough that future football actions can
> safely depend on them.

Primary scope:

- Straight jogging control
- Straight sprint dribbling
- Sprint Push / Coast / Collect rhythm
- Ball-player separation
- Controlled stop
- Start / stop transitions
- 45° turns
- 90° turns
- 135° turns
- 180° reversals
- Capture behavior
- Loose-ball transition
- Possession acquisition / loss tuning
- Network-ownership validation under the current prototype model
- Ball visibility / player scale reevaluation after camera changes

Acceptance should compare Beyond 90 directly with intended FIFA 14,
eFootball and GameplayFootball-derived principles where relevant.

Do not build passing on top of obviously unstable possession.

## Milestone 5.1 — Passing Foundation

Primary scope:

- Short pass
- Basic pass direction
- Pass power / weight
- Ball release from possession
- Physical pass travel
- Server validation
- Client responsiveness
- Pass targeting assistance that preserves human choice
- Passing input abstraction across keyboard/controller/mobile architecture
- Initial driven-pass foundation if it fits scope

Reference priorities:

- FIFA 14 for satisfaction / responsiveness
- eFootball for football behavior / weight
- GameplayFootball for inspectable contact / targeting / cooperation concepts

Do not add large passing varieties before the core pass is excellent.

## Milestone 5.2 — Receiving And First Touch

Primary scope:

- Receive moving footballs
- Ball prediction
- Reachability
- Movement toward a valid contact state
- First-touch control
- Moving reception
- Directional first touch
- Poor / loose first-touch outcomes where justified
- Fast pass reception
- Sprint reception
- Player-ball cooperation during reception

Reference priorities:

- eFootball
- Real football
- GameplayFootball source

Receiving should not simply weld the incoming ball into possession.

## Milestone 5.3 — Shooting And Goals

Primary scope:

- Normal shot
- Shot direction
- Shot power
- Body / ball contact relationship
- Physical ball flight
- Ground / aerial shot behavior as appropriate
- Post / crossbar collision
- Net interaction foundation
- Server-authoritative goal detection
- Goal state transition

Reference priorities:

- FIFA 14 for satisfaction
- eFootball for football behavior
- Real football for contact truth
- GameplayFootball where useful for contact / targeting concepts

Do not build every shot type immediately.

## Milestone 5.4 — Defending, Tackling And Shielding

Primary scope:

- Defensive locomotion needs
- Standing tackle foundation
- Interceptions
- Possession contests
- Possession transfer
- Shielding
- Player-player physical interaction
- Fair server validation
- Recovery after failed tackle

Reference priorities:

- eFootball for defensive movement
- FIFA 17 for shielding / physical responsiveness
- Real football for contact behavior
- GameplayFootball for relevant possession / interception logic

## Milestone 5.5 — Goalkeeper Gameplay

Primary scope:

- Human goalkeeper control foundation
- Goalkeeper positioning assistance where appropriate
- Catching
- Parrying
- Diving
- Ground collection
- Distribution foundation
- Goalkeeper-specific camera requirements
- Goalkeeper action validation

AI goalkeeper behavior may be researched here only if required to test the
human goalkeeper mechanics, but the full AI footballer milestone remains 5.6.

## Milestone 5.6 — AI Footballers v1: Development And Training

This is the first dedicated AI-player implementation milestone.

Before implementation:

- Inspect GameplayFootball's relevant AI source
- Record branch / commit SHA / date
- Trace complete relevant call chains
- Document findings
- Separate football logic from engine / animation / AI-team assumptions

Primary implementation goal:

> Create useful AI footballers that participate in the real Beyond 90 football
> mechanics so developers can test matches without requiring many humans.

Likely scope:

- AI footballer controller / intent provider
- Basic positional target
- Basic ball approach
- Ball prediction / reachability
- Basic receiving
- Basic dribbling
- Basic passing
- Basic shooting
- Basic defending / interception
- Basic goalkeeper participation if needed
- Debug controls for spawning / configuring AI test footballers

Do not attempt advanced professional tactics yet.

## Milestone 5.7 — Teams, Positions And Core Match Flow

Primary scope:

- Teams
- Team assignment
- Footballer slots
- Player positions
- Attacking direction
- Kickoff
- Score
- Match clock
- Goal restart
- Halftime
- Full time
- Basic match state machine

This milestone should work with both human and AI-controlled slots where
appropriate.

## Milestone 5.8 — Football Rules And Restarts

Primary scope should be chosen incrementally from:

- Throw-ins
- Corners
- Goal kicks
- Free kicks
- Penalties
- Fouls
- Advantage if appropriate
- Offside
- Restart positioning

Do not implement obscure rules before common match flow is reliable.

Server authority is mandatory for competitive rule outcomes.

## Milestone 5.9 — AI Footballers v2: Match Integration

Primary scope:

- Team formation behavior
- Position-aware anchors
- Support movement
- Defensive shape
- Marking
- Press / cover
- Transition behavior
- Passing-option creation
- Offside awareness
- Restart positioning
- Human + AI mixed teams
- Incomplete-team filling
- Temporary disconnected-player replacement where allowed
- Safe human↔AI slot handoff
- Initial difficulty controls

GameplayFootball source remains a major reference, supplemented by real
football and Beyond 90-specific design.

## Milestone 6.0 — Multiplayer / Networking Hardening

Primary scope:

- Multi-client tests
- Latency tests
- Packet / replication behavior
- Controlled-ball reconciliation as needed
- Possession validation
- Pass / shot validation
- Tackle validation
- Network ownership transitions
- Disconnect handling
- Exploit resistance
- Remote validation
- Server performance
- AI + human mixed-network scenarios
- 22-player eventual-load preparation

The current controlled-ball ownership model may be replaced or strengthened if
testing proves that competitive integrity requires it.

Do not change architecture merely because another model is theoretically more
pure.

Use evidence.

## Milestone 6.1 — Match Format Scaling

Primary scope:

- 3v3
- 5v5
- 7v7
- 11v11

Adapt as needed:

- Pitch dimensions
- Spawn / position layout
- Camera presets
- Player spacing
- Match duration
- Team shape
- AI fill limits
- Rules
- Matchmaking constraints
- Mobile readability

A feature that only works in one format remains incomplete unless explicitly
mode-specific.

## Milestone 6.2 — Custom Football Animation

Custom animation should now replace temporary Standard R15 presentation where
appropriate.

Primary scope:

- Idle / football stance
- Jog
- Sprint
- Acceleration
- Deceleration
- Turns
- Reversals
- Dribble contacts
- First touch
- Passing
- Shooting
- Tackling
- Shielding
- Goalkeeper actions
- Falls / recovery where required

Use:

    REAL FOOTBALL
        ↓
    eFootball
        ↓
    FIFA 17 / modern EA FC
        ↓
    original Beyond 90 animation

Integrate semantic markers such as:

- BallContact
- PlantFoot
- Footstep_L
- Footstep_R
- ActionCommit
- Recover
- Takeoff
- Landing
- TackleContact

Animation should synchronize with already-valid gameplay actions.

Do not let animation become the source of competitive truth.

## Milestone 6.3 — Gameplay Camera V2 And Match Presentation

Primary scope:

- Mature Broadcast Camera
- Match-size presets
- Player / ball / play-context framing
- Better anticipation
- Long-pass framing
- Penalty-area framing
- Goalkeeper camera refinements
- Set-piece cameras
- Goal presentation
- Replay / highlight camera foundation
- Presentation transitions

Reference priorities:

- FIFA 17
- Modern EA SPORTS FC
- Real football broadcasts
- Beyond 90 human-per-footballer readability

## Milestone 6.4 — Match HUD And Core UI / UX

Primary scope:

- Score
- Clock
- Team identity
- Player / position indicator
- Possession / action feedback where required
- Match notifications
- Pause / settings access where supported
- Core match menus

Visual reference:

- Modern EA FC
- FIFA 17
- Leading Roblox experiences

All work in this milestone must also follow the dedicated guidance under:

    docs/ui/

Do not copy Ultimate Team menu complexity.

## Milestone 6.5 — Mobile And Controller Production Pass

Primary scope:

- Touch movement
- Sprint controls
- Passing
- Shooting
- Tackling
- Contextual controls where appropriate
- Camera controls / toggles
- HUD scaling
- Small-screen Broadcast Camera tuning
- Controller bindings
- Controller UI navigation
- Input parity tests

References:

- eFootball Mobile
- FC Mobile
- Leading Roblox mobile experiences

Underlying football mechanics should remain shared across platforms.

## Milestone 6.6 — Lobby, Parties And Matchmaking

Primary scope:

- Lobby flow
- Join friends
- Party system
- Queue selection
- Match format selection
- Region / latency considerations
- Team-size requirements
- Server allocation
- Reconnect handling
- AI-fill policy hooks

Do not let matchmaking policy leak into low-level football mechanics.

## Milestone 6.7 — Player Identity And Persistence

Primary scope:

- Player profile
- Footballer identity
- Position preferences
- Career statistics
- Match history foundation
- Avatar / football customization hooks
- Persistent data architecture
- Data migration / failure handling

Do not introduce competitive stat advantages through persistence.

## Milestone 6.8 — Clubs And Organized Teams

Primary scope:

- Club creation
- Club identity
- Club roster
- Roles / permissions
- Club statistics
- Club history
- Club matchmaking hooks
- Organized competitive team play

Reference EA FC Clubs conceptually, not literally.

## Milestone 6.9 — Ranked, Divisions And Seasons

Primary scope:

- Skill rating
- Ranked queues
- Divisions / tiers
- Seasonal competition
- Leaderboards
- Promotion / relegation concepts where appropriate
- Competitive rewards
- Match integrity requirements
- AI policy for ranked modes

AI participation policy must be explicit for every ranked ruleset.

Do not allow hidden AI advantages to affect competitive integrity.

## Milestone 7.0 — Progression And Rewards

Primary scope:

- XP / reputation
- Objectives
- Challenges
- Seasonal progression
- Cosmetic rewards
- Prestige
- Player-card / profile presentation

Keep gameplay skill dominant.

Do not introduce permanent paid competitive advantages.

## Milestone 7.1 — Audio And Stadium Atmosphere

Primary scope:

- Ball-contact SFX
- Touch-strength differentiation
- Pass / shot differentiation
- Bounce
- Post / crossbar
- Net
- Tackles / collisions
- Whistles
- Crowd ambience
- Attack anticipation
- Goal / save / miss reactions
- Broadcast ambience

Use real football as the primary truth reference for physical audio.

## Milestone 7.2 — Presentation And Polish

Primary scope may include:

- Player cards
- Team introductions
- Match intros
- Broadcast overlays
- Goal presentation
- Celebrations
- Post-match screens
- Awards
- Replay polish
- Stadium polish
- Loading transitions

Do not allow presentation work to hide broken football mechanics.

## Milestone 7.3 — Safety, Moderation And Production Backend

Primary scope:

- Reporting
- Moderation hooks
- Abuse prevention
- DataStore resilience
- Analytics
- Error telemetry
- Match telemetry
- Operational diagnostics
- Admin / support tooling where appropriate
- Recovery from service failures

Follow current Roblox platform requirements when this milestone begins.

## Milestone 7.4 — Optimization And Compatibility

Primary scope:

- Low-end PC
- Mobile
- Console
- 22-player scenarios
- AI-heavy scenarios
- Streaming
- Memory
- CPU
- Physics
- Network bandwidth
- Rendering
- Animation cost
- UI performance
- Stadium performance

Profile before optimizing.

Do not destroy football quality to optimize hypothetical bottlenecks.

## Milestone 7.5 — Closed Alpha

Primary goals:

- Real-player testing
- Multi-player football balance
- Input issues
- Camera readability
- Network behavior
- AI fill behavior
- Exploit discovery
- Match flow
- Onboarding
- UX friction
- Device compatibility
- Telemetry validation

Playtesting should drive reprioritization.

## Milestone 7.6 — Open Beta

Primary goals:

- Larger population
- Matchmaking health
- Server scaling
- Queue health
- Retention
- Progression pacing
- Ranked balance
- Club behavior
- AI-fill policy testing
- Economy / reward stability
- Live-ops readiness

Treat Beta as production validation, not as an excuse to leave fundamental
football problems unresolved.

## Milestone 8.0 — Public 1.0 Launch

A launch-ready Beyond 90 should have a stable version of the product pillars
chosen for 1.0.

The intended full-product direction includes:

- Excellent football movement
- Physical, readable ball behavior
- Satisfying dribbling
- Passing
- Receiving
- Shooting
- Defending
- Goalkeeping
- Human-controlled footballers
- AI testing / training / fill support
- Multiple match formats
- Broadcast presentation
- Cross-platform input
- Match flow
- Matchmaking
- Player identity
- Competitive structure
- Clubs
- Progression
- Audio
- Production reliability

Not every long-term idea must ship in 1.0.

A feature should be deferred rather than rushed if it is not necessary for a
strong launch.

Future anime-inspired modes, advanced live ops, additional competitions and
other expansions may continue after launch.

---

# 55. Milestone Execution Rules

The milestone roadmap exists to prevent uncontrolled scope growth.

For each milestone:

1. Read this `AGENTS.md` completely.
2. Identify the current milestone.
3. Inspect the existing Beyond 90 implementation.
4. Inspect relevant research documentation.
5. Inspect external source / footage appropriate to the system.
6. Define the smallest testable implementation.
7. Implement only that milestone.
8. Build / run static verification.
9. Playtest in Studio where possible.
10. Compare against the intended reference behavior.
11. Report remaining problems honestly.
12. Stop before the next milestone.
13. Let playtest evidence determine whether the milestone is accepted,
    revised or split.
14. Commit once the milestone is actually stable according to the project's
    chosen Git workflow.

Do not automatically proceed into the next milestone merely because code
builds.

A milestone is not complete simply because:

- Rojo builds
- Luau has no syntax error
- A module exists
- A button works

Gameplay milestones must also answer:

> Does the behavior actually feel and function closer to the intended football
> target?

When the user supplies new gameplay footage or runtime logs, treat those as
important playtest evidence and be willing to revise the implementation.

Do not defend prior code merely because it was previously marked complete.

---

# 56. Current Development State Rule

At the time this roadmap was added:

    5.0A
        ↓
    IMPLEMENTED / PLAYTESTED
        ↓
    5.0B
        ↓
    NEXT MILESTONE

The immediate focus is therefore:

    LOCOMOTION
        +
    PLAYER SCALE EXPERIMENT
        +
    CONTROLLED-BALL RETUNING
        +
    BROADCAST CAMERA
        +
    TESTABILITY

AI footballers are an approved future system but are **not part of 5.0B**.

The first dedicated AI implementation milestone is planned for:

    5.6 — AI Footballers v1: Development And Training

and broader match/team integration is planned for:

    5.9 — AI Footballers v2: Match Integration

If future playtesting changes milestone dependencies, update this document
explicitly rather than silently drifting from the roadmap.

## The Above Is Historical. Current State Follows.

The 5.0A / 5.0B text above describes where the project stood when the roadmap
was written and is kept for context. It is **not** the current position.

### Working milestone numbers are not roadmap numbers

Day-to-day work is tracked by milestone briefs under:

    docs/milestones/

Those briefs use their own numbering, assigned as work is commissioned, and it
does **not** correspond to the roadmap in section 54. "Milestone 6.8" in
`docs/milestones/` is pressing, tackling and slide tackling; section 54's 6.8 is
Clubs. Do not assume a brief and a roadmap entry with the same number are the
same body of work.

Section 54 remains authoritative for **dependency order** — what must be stable
before what. The briefs are authoritative for **what is actually being built
now**.

### Roughly where things stand

Substantially implemented and playtested: core locomotion, controlled ball,
passing, receiving, shooting and goals, defending and interceptions, human and
AI goalkeepers, AI footballers with team shape and formation positioning, match
flow, restarts and offside, menus and match HUD, player identity and the
footballer/avatar choice.

Known incomplete, and the most useful things to know before planning:

- **Animation is the largest gap.** There is no clip for a player performing a
  tackle or a slide, none for a goalkeeper dive, and no on-ball locomotion set
  at all — a footballer dribbling is animated as one running with no ball.
- Only 3v3 assembles AI. `Tournament5v5` and `Clubs11v11` are `Enabled = false`,
  and the `Development` mode fields no AI outfielders, so AI work is invisible
  in it. Use `Quick3v3` to observe AI behaviour.
- Match-format scaling, clubs, ranked and progression are not started.

Update this subsection when that stops being true, rather than leaving a future
reader to infer the state from the code.

---

# 57. Roblox Asset Moderation, Upload Safety And Visual QA

Beyond 90 development must avoid creating unnecessary Roblox-hosted assets during
visual testing and must proactively prevent moderation violations caused by UI
images, screenshots, temporary mockups or other uploaded media.

This section applies to AI coding agents, developers, visual-QA workflows and any
automation that can create or upload Roblox assets.

## Local-First Visual QA

For development screenshots, UI comparisons and visual verification:

- Prefer **local operating-system screenshots or local video captures**.
- Prefer Luau geometry/runtime assertions where visual proof can be obtained
  without an upload.
- Prefer Roblox Studio inspection through supported tooling when it does not
  create a persistent Roblox-hosted asset.
- Do **not** use Roblox Studio capture/upload integrations for routine QA when
  they may create persistent uploaded assets.
- Until the user explicitly confirms that a Studio capture workflow is safe,
  assume Studio-generated capture uploads are **not approved for Beyond 90 QA**.
- Keep temporary visual-test artifacts local and out of Roblox moderation
  pipelines.

A screenshot should not be uploaded merely because it is convenient for an AI
agent to inspect later.

## Pre-Upload Image Inspection

Before any production image is uploaded to Roblox, inspect the actual final
local file first.

Check for:

- URLs or URL-like text
- QR codes
- Email addresses
- Social-media handles
- Discord branding or invite references
- YouTube branding or channel references
- X / Twitter branding or handles
- Twitch branding or handles
- Other off-platform service branding or destinations
- Text that OCR could reasonably misread as a link or off-platform destination
- Watermarks or unrelated creator branding
- External-reference screenshots or artwork accidentally embedded in the asset
- Development notes, debug text or temporary labels that should not ship

If there is uncertainty about whether visible text or imagery could trigger
moderation, do not upload it until it has been reviewed and cleaned.

## External References Must Stay Outside Roblox

External reference material is for development research only.

Examples include:

- eFootball screenshots
- FIFA / EA SPORTS FC screenshots
- Other Roblox game screenshots
- UI inspiration boards
- External website captures
- Third-party mockups
- Reference videos and frame grabs

These should remain in local/reference storage and must **not** be imported into
Roblox Studio merely for comparison.

Do not include reference material inside:

- Roblox image assets
- uploaded screenshots
- production UI textures
- decals
- thumbnails
- temporary Studio captures that may persist as uploaded assets

When comparing Beyond 90 against a reference, keep the reference outside Roblox
and compare locally.

## Upload Only Finalized Production Assets

Roblox should receive only assets that are intentionally meant to exist on the
platform.

Do not upload:

- temporary mockups
- WIP screenshots
- visual-QA captures
- debugging captures
- reference composites
- placeholder screenshots
- iteration snapshots

unless the user explicitly requests that the specific asset be uploaded.

Before upload, the asset should be:

1. Final or intentionally production-ready.
2. Cropped correctly.
3. Free from unrelated reference material.
4. Checked for prohibited/off-platform text and branding.
5. Associated with a clear Beyond 90 purpose.

## Roblox Asset Manifest

Maintain a traceable manifest for Roblox-hosted production assets.

If an existing asset manifest is present, update it rather than creating a
competing manifest.

If no manifest exists when production uploads begin, create an appropriate
project document such as:

    docs/assets/roblox-asset-manifest.md

For each uploaded production asset, record at minimum:

- Roblox asset ID
- Local source filename
- Asset type
- Purpose / where it is used
- Upload date
- Roblox owner/group where relevant
- Moderation status
- Date moderation approval was confirmed
- Config/module that references the asset ID

This allows any future moderation notice to be traced quickly to the exact
source asset and usage.

## Moderation Approval Before Runtime Configuration

Do not immediately place a newly uploaded asset ID into production configuration.

For new image/audio/media uploads:

    local final asset
        ↓
    inspect locally
        ↓
    upload intentionally
        ↓
    wait for Roblox moderation / processing
        ↓
    confirm approved / usable state
        ↓
    record in asset manifest
        ↓
    add asset ID to production configuration

For UI images specifically, do not add the ID to `UIAssetConfig` or an
equivalent production registry before its approved/usable status is confirmed.

If the moderation state cannot be verified, mark the asset:

    UNVERIFIED

and do not treat it as production-ready.

## Off-Platform Destinations And Social Links

Do not place genuine off-platform destinations inside Beyond 90 UI images,
ordinary in-game text, screenshots or decorative assets.

This includes destinations or identifiers for services such as:

- Discord
- YouTube
- X / Twitter
- Twitch
- external websites
- email destinations
- other social platforms

Where Beyond 90 legitimately needs an external destination, use Roblox's
supported **Social Links / Social Networks configuration** and any applicable
Roblox-supported policy mechanism rather than embedding the destination inside
ordinary UI or image assets.

Current Roblox Community Standards should be treated as the governing platform
policy and re-checked when moderation/upload behavior changes:

    https://en.help.roblox.com/hc/en-us/articles/203313410-Roblox-Community-Standards

Do not assume that an off-platform reference is permitted merely because it is:

- only visible during development;
- intended for testing;
- inside a private/unpublished experience;
- embedded in an image rather than plain text;
- temporary;
- created by an AI agent.

## AI-Agent Upload Rule

AI coding agents such as Codex or Claude must not create Roblox-hosted visual QA
captures merely to prove that a UI change worked.

Preferred verification order:

    runtime / geometry checks
            ↓
    Studio inspection
            ↓
    local OS screenshot / local recording
            ↓
    user visual review

Only use a Roblox upload when the artifact itself is intended to become a real
production asset.

If a tool or integration may silently create a Roblox-hosted asset, treat that
operation as an upload and avoid it unless explicitly required.

## Moderation-Safety Rule

When there is a conflict between development convenience and avoiding an
unnecessary moderation risk:

    KEEP THE ARTIFACT LOCAL

is the default decision.

Visual QA does not require a Roblox-hosted asset.

Reference material does not require a Roblox-hosted asset.

Temporary development work does not require a Roblox-hosted asset.

Only intentional, inspected and approved production assets should enter the
Roblox asset pipeline.
