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

Every footballer on the pitch should be controlled by a real Roblox player
whenever the game mode allows it.

Do not introduce AI-controlled outfield players as a replacement for real
players unless explicitly requested.

AI may be used for:

- Matchmaking
- Training
- Practice environments
- Goalkeeper assistance where explicitly designed
- Referee systems
- Supporting systems
- NPCs outside competitive matches
- Football-contact assistance that preserves human intent

The default competitive experience should prioritize human players.

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

The game must NOT decide on behalf of the player:

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

---

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

Prioritize systems in this order unless explicitly instructed otherwise:

1. Core player movement
2. Ball physics
3. Ball interaction
4. Ball control / possession foundation
5. Dribbling / first-touch behavior
6. Camera foundation
7. Passing
8. Shooting
9. Tackling / defensive interactions
10. Team systems
11. Match flow
12. UI
13. Matchmaking
14. Progression
15. Clubs
16. Social systems
17. Monetization

This order is a development guideline, not a requirement to completely finish
one system before touching another.

Systems may be revisited as playtesting exposes dependencies.

In particular:

- Ball control must be stable enough before passing and shooting depend on it.
- Player movement and ball control may be revisited together when the reference
  behavior demonstrates that they are coupled.
- The Broadcast Camera should be prototyped early enough to influence gameplay
  readability, but it should not block development of the core football loop.
- Do not build complex progression or monetization systems before the core
  football experience is fun.

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
6. Inspect the actual GameplayFootball source when the feature is covered by
   the GameplayFootball Reference Strategy.
7. Avoid creating duplicate systems.
8. Preserve existing functionality that remains valid.
9. Explain significant architectural decisions.
10. Prefer incremental, testable changes.

Do not rewrite large parts of the project merely because another architecture
is aesthetically preferable.

However, do not preserve a failed gameplay abstraction merely because work has
already been invested in it.

If verified GameplayFootball behavior demonstrates that an existing Beyond 90
approach is solving the football problem poorly, replacing that approach is
allowed and may be preferable.

When GameplayFootball is relevant, do not invent a substantially different
football algorithm before first evaluating whether the verified reference
algorithm can be translated appropriately.

Research findings do not automatically authorize a refactor unless the task
explicitly includes implementation.

Do not modify production gameplay code during a research-only task unless
explicitly instructed to proceed with implementation.

---

# 20. Before Implementing A Feature

For any significant feature, AI should first identify:

- What system owns the feature?
- Is it client-side, server-side, or split?
- What existing modules interact with it?
- Does it need networking?
- Does it need configuration?
- Does it need UI?
- Does it affect multiple game modes?
- Does it need to work across PC/mobile/console?
- Does it affect the Broadcast Camera?
- Does it need to be scalable for 3v3 through 11v11?
- Is GameplayFootball relevant?
- If GameplayFootball is relevant, what verified reference behavior should act
  as the baseline?
- Which parts of that behavior are football logic?
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

For GameplayFootball-inspired mechanics, testing should evaluate both:

    DOES THE IMPLEMENTATION WORK?

and:

    DOES THE BEHAVIOR RESEMBLE THE VERIFIED REFERENCE BEHAVIOR WE INTENDED TO
    REPRODUCE?

When possible, compare Beyond 90 and GameplayFootball side-by-side for:

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

# 27. GameplayFootball Reference Strategy

GameplayFootball — specifically the vi3itor fork at:

    https://github.com/vi3itor/GameplayFootball.git

is the primary external football-gameplay reference and behavioral baseline for
Beyond 90 unless explicitly instructed otherwise.

GameplayFootball is used because it provides a working implementation of many
football-specific gameplay problems that Beyond 90 must also solve.

For fundamental football mechanics, verified GameplayFootball behavior should
normally be studied BEFORE inventing a different solution.

Relevant systems include, where appropriate:

- Player movement
- Acceleration/deceleration
- Orientation and turning
- Sprinting
- Ball physics
- Ball interaction
- Ball control
- Dribbling
- Possession
- First touches
- Passing
- Pass targeting
- Through balls
- Crosses
- Shooting
- Ball trajectories/spin
- Tackling
- Defensive interaction
- Headers
- Goalkeepers
- Player positioning
- Off-ball movement
- Match state
- Football rules/restarts
- Animation/gameplay coordination
- General football gameplay architecture

GameplayFootball is NOT:

- Beyond 90's runtime dependency
- Beyond 90's C++ architecture
- Beyond 90's engine
- A requirement to reproduce every GameplayFootball feature
- A reason to import AI tactical decision-making into human-controlled play

The goal is NOT technical similarity.

The goal is to avoid unnecessarily reinventing proven football behavior.

---

## GameplayFootball Behavioral Fidelity

For fundamental football mechanics where GameplayFootball behavior has been
verified from source and is desirable for Beyond 90, the default starting point
should be BEHAVIORAL FIDELITY.

This means Beyond 90 may closely translate verified:

- Algorithms
- Mathematical relationships
- State transitions
- Control logic
- Possession logic
- Ball-control logic
- Touch planning
- Movement-assistance logic
- Timing relationships
- Direction/orientation relationships
- Prediction relationships
- Player-ball coordination logic

when those systems contribute to the desired Beyond 90 experience.

"Do not port GameplayFootball directly" means:

    DO NOT PORT THE ENGINE/ARCHITECTURE LITERALLY.

It does NOT mean:

    REINVENT VERIFIED FOOTBALL ALGORITHMS FOR NO REASON.

The preferred process is:

    GameplayFootball behavior
        ↓
    Trace the exact source implementation
        ↓
    Understand the full call chain
        ↓
    Identify football logic
        ↓
    Identify AI-only logic
        ↓
    Identify animation-specific logic
        ↓
    Identify engine-specific logic
        ↓
    Preserve useful behavior/math/state relationships
        ↓
    Translate them into Roblox-native systems
        ↓
    Adapt only where Roblox or Beyond 90 requires it
        ↓
    Playtest against the reference behavior
        ↓
    Tune for Beyond 90

When a verified reference algorithm solves the exact football problem currently
being implemented, prefer translating that algorithm before designing a
different one.

If Beyond 90 later improves upon the reference through playtesting, that is
encouraged.

---

## What May Be Ported Closely

Where useful and legally compliant, Beyond 90 may closely reproduce verified:

- Football algorithms
- Mathematical formulas
- State relationships
- Possession conditions
- Time-to-ball logic
- Ball prediction concepts
- Touch-vector calculations
- Dribbling/control relationships
- Movement blending
- Contact-assistance rules
- Timing relationships
- Pass/shot targeting logic
- Other football-specific behavior

Exact constants may be used as INITIAL reference values only when:

1. Their meaning has been verified.
2. Units are understood.
3. They are converted appropriately for Beyond 90.
4. Their relationship to player scale/ball scale is understood.

Do not assume a GameplayFootball meter maps directly to a Roblox stud.

Prefer preserving meaningful ratios before preserving raw absolute numbers.

All resulting values should remain configurable where practical.

---

## What Must NOT Be Ported Blindly

Do NOT:

- Translate every C++ statement mechanically into Luau.
- Reproduce GameplayFootball's class hierarchy merely because it exists.
- Recreate GameplayFootball's engine architecture inside Roblox.
- Build a second custom physics engine when Roblox physics already provides the
  required simulation.
- Import AI tactical decision-making for human-controlled players.
- Reproduce desktop-only assumptions without evaluating mobile/console.
- Adopt network assumptions that do not apply to Roblox.
- Preserve reference behavior that is demonstrably worse for Beyond 90.
- Add unnecessary complexity merely for source fidelity.

The question is:

    "What behavior makes this football system work?"

not:

    "How do we make the Roblox source look like the C++ source?"

---

## Ball And Player Coordination

For dribbling and close control, Beyond 90 may actively coordinate the player
and the football.

Do not assume good football control must be achieved solely by pushing the
football and hoping the player's raw Roblox movement catches it.

GameplayFootball-style concepts such as:

- Predicting the next useful ball position
- Guiding the footballer toward a valid contact position
- Blending human movement with bounded ball-contact assistance
- Planning the outgoing ball trajectory
- Producing discrete meaningful touches
- Recalculating control after the touch

may be translated closely where appropriate.

The player and ball may cooperate.

The ball should still feel physically independent.

Do not create fake possession by:

- Welding the football to the character
- Attaching the football rigidly to the character
- CFrame-following the football every frame
- Teleporting the football continuously
- Treating the ball as a cosmetic object while controlled

A deliberate football contact may authoritatively change the ball's outgoing
velocity/momentum.

That is compatible with a physically simulated football.

---

## Human-Controlled Movement Assistance

GameplayFootball contains movement assistance that helps maintain useful
football contact.

Beyond 90 MAY use bounded movement assistance for human-controlled players.

The purpose of such assistance is:

    EXECUTION ASSISTANCE

not:

    TACTICAL DECISION-MAKING

Allowed examples:

- Slightly adjusting player movement toward the next intended ball contact
- Helping align the avatar with a reachable control position
- Blending manual direction with ball-contact direction
- Adjusting movement near the ball so a planned touch can occur
- Helping preserve a dribble while honoring the user's movement input

Not allowed by default:

- Choosing the player's attacking direction
- Choosing who to pass to
- Choosing when to pass
- Choosing when to shoot
- Choosing tactical positioning for the human player
- Automatically dribbling around opponents without player intent

When assistance and raw input conflict, the player's tactical intent must
remain dominant.

The strength of assistance should be configurable and determined through
playtesting.

---

## Animation And Gameplay Logic

GameplayFootball coordinates many football contacts with animation timing.

Beyond 90 should study these relationships closely.

However, GameplayFootball's custom animation architecture should not be
recreated automatically.

Separate:

    FOOTBALL LOGIC
    ANIMATION TIMING
    ENGINE IMPLEMENTATION

If Beyond 90 does not yet have the required football animations, temporary
logical touch timing may be used.

The gameplay system should be designed so that later animations can synchronize
with already-defined logical football contacts rather than requiring the entire
football mechanic to be rebuilt.

Authoritative competitive ball outcomes must not depend solely on an
unvalidated client animation marker.

---

## GameplayFootball Research Documentation

Substantial GameplayFootball research should be documented under:

    docs/research/gameplay-football/

Examples:

    player-movement.md
    ball-control.md
    dribble-cycle.md
    dribbling.md
    passing.md
    shooting.md
    tackling.md
    goalkeeping.md
    match-state.md
    player-positioning.md
    animation-gameplay.md

Research documents should distinguish:

## GameplayFootball Behavior

Confirmed behavior from inspected source.

## Interpretation

Reasoning about why the reference behaves that way.

## Useful Concepts / Port Candidates

Algorithms, relationships, formulas or behavior worth translating.

## AI-Specific Logic

Behavior required because an AI footballer must make decisions.

## Animation-Specific Logic

Behavior tied specifically to GameplayFootball's animation system.

## Engine-Specific Logic

Behavior tied to GameplayFootball's engine or technical architecture.

## Roblox Considerations

Consider:

- Networking
- Replication
- Server authority
- Physics
- Network ownership
- Performance
- Security
- Input
- Animation
- Character systems
- Mobile
- Console
- Latency

## Beyond 90 Mapping

For each major reference behavior, state whether Beyond 90 should:

    KEEP EXISTING
    PORT CLOSELY
    ADAPT
    REPLACE
    OMIT
    DEFER

## Beyond 90 Proposal

Describe the Roblox-native implementation recommended for Beyond 90.

Research documentation describes what was learned and how it may map to
Beyond 90.

It does NOT automatically define final Beyond 90 architecture.

---

## Architecture Documentation

Important approved Beyond 90 architectural decisions should live separately
under:

    docs/architecture/

The distinction is:

    Research documentation
        =
    What GameplayFootball does and what we learned

    Architecture documentation
        =
    How Beyond 90 actually works

Architecture documentation may deliberately describe a close behavioral port
of GameplayFootball while still using a Roblox-native architecture.

Do not confuse behavioral similarity with architectural dependency.

---

## Existing Architecture Preservation Rule

Preserve existing Beyond 90 architecture where it continues to serve the
desired football behavior.

Do not create duplicate movement, ball, control, possession, camera or match
systems merely because GameplayFootball organizes them differently.

However:

    EXISTING CODE IS NOT SACRED.

If research and playtesting demonstrate that an existing Beyond 90 gameplay
abstraction is fundamentally producing worse football behavior, replacing it is
allowed.

Prefer replacing the smallest responsible abstraction rather than layering
increasing numbers of compensating thresholds, grace periods or patches onto a
failed model.

Do not preserve code purely because development time was already spent on it.

---

## Research Scope Rule

Research only what is relevant to the current milestone.

Do not reverse-engineer the entire repository before continuing development.

However, when researching one football mechanic, trace the reference through
enough callers/callees to understand the COMPLETE behavior.

Do not inspect one isolated function and treat it as the entire system.

For example, researching dribbling may require tracing:

    human input
        ↓
    movement controller
        ↓
    possession logic
        ↓
    ball-control movement
        ↓
    action/animation selection
        ↓
    touch timing
        ↓
    ball-control vector
        ↓
    Ball::Touch
        ↓
    prediction/possession update

This is still milestone-scoped research because the complete chain is required
to understand the mechanic.

---

## Runtime Separation

GameplayFootball must remain external to the Beyond 90 runtime source tree.

Do not vendor, copy or clone the GameplayFootball repository into:

    src/

Do not make Rojo map GameplayFootball files into Roblox Studio.

If a local clone is used for research, keep it outside the production runtime
tree or in another clearly separated development location.

GameplayFootball must never become a runtime dependency of Beyond 90.

Translated/adapted Beyond 90 implementation code should live normally within
the Beyond 90 project.

---

## Licensing And Originality

Respect the license and notice requirements of GameplayFootball and every
external reference project.

Conceptual extraction does not require copying source text.

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

Legal permission to reproduce behavior or code does not automatically mean that
doing so is the best gameplay or engineering decision.

Beyond 90 should maintain its own identity and Roblox-native architecture.

---

# 28. GameplayFootball Source Accuracy

When discussing GameplayFootball, explicitly distinguish:

CONFIRMED FROM SOURCE

    Behavior directly demonstrated by inspected source.

INFERENCE

    A conclusion inferred from interactions between source systems.

RECOMMENDATION

    Something proposed specifically for Beyond 90.

Never claim:

    "GameplayFootball does X"

unless the relevant source has actually been inspected.

If uncertain, inspect the source rather than guessing.

Avoid unnecessarily copying large source blocks into research documentation.

Focus on:

- Behavior
- Algorithms
- Relationships
- Formulas
- State transitions
- Call chains
- Important constants
- Design intent where inferable

For substantial research, record the exact reference revision used.

At minimum include:

- Repository URL
- Branch
- Commit SHA
- Date researched
- Relevant source files
- Relevant classes/functions/symbols

Example:

    Reference:
    Repository: https://github.com/vi3itor/GameplayFootball.git
    Branch: master
    Commit: <commit SHA>
    Researched: <date>

If later research uses a different revision, do not silently treat behavior
from the newer revision as though it existed in the previously researched
version.

If implementation work is based on a specific researched revision, preserve
that revision in the relevant research documentation so later source changes do
not silently alter the behavioral baseline.

---

# 29. GameplayFootball Implementation Workflow

When implementing a substantial GameplayFootball-relevant football mechanic,
use this workflow unless explicitly instructed otherwise:

    1. Inspect current Beyond 90 implementation.

    2. Read existing research documentation.

    3. Inspect the exact GameplayFootball source revision.

    4. Trace the complete relevant behavior/call chain.

    5. Identify football logic.

    6. Separate AI-only decision-making.

    7. Separate animation-specific behavior.

    8. Separate engine-specific behavior.

    9. Identify algorithms/state relationships to preserve.

    10. Map reference behavior to existing Beyond 90 modules.

    11. Decide what should:
            KEEP
            PORT CLOSELY
            ADAPT
            REPLACE
            OMIT
            DEFER

    12. Determine Roblox networking/security implications.

    13. Define the smallest playable implementation milestone.

    14. Implement the Roblox-native equivalent.

    15. Test in Roblox Studio.

    16. Compare behavior with the reference where possible.

    17. Tune Beyond 90-specific values.

    18. Document approved architecture after behavior stabilizes.

Do not default to inventing a different football model merely because a
reference algorithm requires adaptation.

Do not default to copying a reference algorithm merely because it exists.

Use verified reference behavior as the baseline, then make deliberate changes
for Beyond 90.

---

# 30. Broadcast Camera Reference Exception

GameplayFootball may be researched for general camera concepts where useful,
but it does NOT define Beyond 90's Broadcast Camera.

The Broadcast Camera remains a Beyond 90-specific defining feature.

Its priorities remain:

- Elevated broadcast-style perspective
- Tactical readability
- Passing-lane visibility
- Open-space visibility
- Player positioning
- Team shape
- Smooth tracking
- Smooth zoom
- Smooth situational framing
- Match-size-specific presets
- Minimal unnecessary camera movement
- Football readability over unnecessary cinematic movement

Modern football broadcasts and modern football games may also be used as
references where useful.

GameplayFootball behavioral-fidelity rules for fundamental football mechanics
do NOT require the Broadcast Camera to imitate GameplayFootball.

The final Broadcast Camera must be designed specifically for Beyond 90.

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

Behavioral fidelity to GameplayFootball is a STARTING POINT, not a higher
priority than Beyond 90's gameplay goals.

If a verified GameplayFootball behavior produces excellent football in
Beyond 90, preserve it.

If Roblox constraints require an implementation change, adapt the
implementation while attempting to preserve the football behavior.

If Beyond 90 playtesting demonstrates that changing the reference behavior
creates a better experience, Beyond 90 takes priority.

Technical similarity to GameplayFootball is NOT a goal.

Football-behavior quality is.

The governing principle is:

> GameplayFootball teaches us how a working football game solved the football
> problem.
>
> Preserve those proven football behaviors when they serve Beyond 90.
>
> Roblox determines how those behaviors must be implemented technically.
>
> Beyond 90 determines where the reference should ultimately be preserved,
> adapted, improved or rejected.

Study references aggressively.

Trace complete behavior.

Port proven football logic closely where appropriate.

Adapt engine implementation deliberately.

Preserve human tactical agency.

Playtest against the reference.

Improve where Beyond 90 can do better.

Build the final system specifically for Beyond 90.