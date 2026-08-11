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

The default competitive experience should prioritize human players.

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
- Server-authoritative gameplay
- Client-side presentation where appropriate

Avoid:

- Giant scripts
- Duplicate logic
- Magic numbers
- Unnecessary global state
- Tight coupling
- Temporary hacks presented as final architecture

---

# 17. Networking

Competitive gameplay must be server authoritative wherever practical.

The client should not be trusted for critical gameplay decisions such as:

- Goals
- Match results
- Currency
- Player statistics
- Competitive rankings
- Possession validation
- Important ball interactions

RemoteEvents and RemoteFunctions should be validated on the server.

Never assume that data sent by the client is trustworthy.

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

---

# 19. AI Development Rules

AI assistants such as Codex or Claude may assist with development.

Before modifying code:

1. Understand the existing architecture.
2. Inspect relevant files.
3. Determine how the requested feature fits into the existing systems.
4. Avoid creating duplicate systems.
5. Preserve existing functionality.
6. Explain significant architectural decisions.

Do not rewrite large parts of the project simply because a different
implementation is possible.

Prefer incremental changes.

When an external gameplay reference is relevant, research it before making
major architectural changes.

Do not modify production gameplay code during a research-only task unless
explicitly instructed to proceed with implementation.

Research findings do not automatically authorize a refactor.

Any reference-inspired architecture must still be justified against the
existing Beyond 90 architecture.

---

# 20. Before Implementing A Feature

For any significant feature, AI should first identify:

- What system owns the feature?
- Is it client-side or server-side?
- What existing modules interact with it?
- Does it need networking?
- Does it need configuration?
- Does it need UI?
- Does it affect multiple game modes?
- Does it need to work across PC/mobile/console?
- Does it affect the Broadcast Camera?
- Does it need to be scalable for 3v3 through 11v11?

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

Do not automate away decisions that should belong to the player.

Do not sacrifice competitive integrity simply to make a system easier to
implement.

Beyond 90 should first be an excellent football game.

Everything else comes after that.

# 26. MVP Development Rule

Beyond 90 should be developed as a sequence of small, playable milestones.

Do not implement future systems simply because they are mentioned in the
long-term vision.

At any given stage, prioritize the smallest playable version of the current
feature.

Each milestone should:
- Have a clearly defined goal.
- Be independently testable.
- Preserve existing functionality.
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


# 27. GameplayFootball Reference Strategy

The primary external football-gameplay reference for Beyond 90 is:

    GameplayFootball — vi3itor fork
    https://github.com/vi3itor/GameplayFootball.git

GameplayFootball is a RESEARCH AND REFERENCE SOURCE.

It is NOT:

- Beyond 90's codebase
- Beyond 90's architecture
- Beyond 90's specification
- A project to directly port from C++ to Luau

The purpose of studying GameplayFootball is to understand how another football
game solves football-specific gameplay problems and extract useful concepts.

The intended process is:

    GameplayFootball
        ↓
    Study the relevant system
        ↓
    Understand the football concept
        ↓
    Identify strengths and weaknesses
        ↓
    Evaluate Roblox constraints
        ↓
    Design the Beyond 90 equivalent
        ↓
    Implement incrementally
        ↓
    Playtest and tune

Technical similarity to GameplayFootball is NOT a goal.

Creating excellent football gameplay for Beyond 90 is the goal.

---

## Systems Where GameplayFootball May Be Relevant

GameplayFootball should be investigated where useful when designing systems
such as:

- Player movement
- Acceleration and deceleration
- Orientation and turning
- Sprinting
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
- Ball trajectories
- Tackling
- Defensive interactions
- Headers
- Goalkeepers
- Player positioning
- Off-ball movement
- Match state
- Football rules
- Restarts
- Animation/gameplay coordination
- General football gameplay architecture

Research only what is relevant to the current milestone.

Do not reverse-engineer the entire repository before continuing development.

---

## Do Not Port GameplayFootball Directly

Do NOT:

- Blindly translate C++ functions into Luau.
- Reproduce GameplayFootball's class hierarchy merely because it exists.
- Recreate its engine architecture inside Roblox.
- Make Beyond 90 dependent on GameplayFootball.
- Copy substantial implementation code without an explicit reason and license
  review.
- Adopt behavior simply because GameplayFootball uses it.

Instead, extract:

- Football concepts
- Algorithms
- Heuristics
- State relationships
- Gameplay principles
- Useful mathematical ideas
- Useful architectural lessons

Then determine how Beyond 90 should accomplish the same gameplay goal using
Roblox-native systems.


The GameplayFootball repository should remain external to the Beyond 90 runtime
source tree.

Do not vendor or copy the GameplayFootball repository into:

    src/

Do not make Rojo map any GameplayFootball files into Roblox Studio.

If a local clone is used for research, keep it outside the production runtime
tree or in another clearly separated development location.

GameplayFootball must never become a runtime dependency of Beyond 90.

---

# 28. Beyond 90 Takes Priority Over References

Whenever GameplayFootball's approach conflicts with Beyond 90's requirements,
Beyond 90 takes priority.

Beyond 90 is designed around:

- Human-vs-human multiplayer
- Real-player-controlled footballers whenever possible
- Competitive online play
- 3v3
- 5v5
- 7v7
- 11v11
- PC
- Mobile
- Console
- Roblox physics
- Roblox networking
- Latency tolerance
- Server authority
- Exploit resistance
- Performance
- Responsive controls
- Tactical football
- Football readability
- Player agency
- Accessible controls
- High skill ceiling

GameplayFootball was built for a different engine and architecture.

A concept must make sense for Roblox and Beyond 90 before it is adopted.

---

# 29. Gameplay Research Workflow

Before implementing a substantial football mechanic where GameplayFootball is
relevant:

1. Inspect the existing Beyond 90 implementation.
2. Identify which current Beyond 90 system owns the responsibility.
3. Inspect the relevant GameplayFootball source.
4. Trace the feature through enough functions/files to understand the complete
   behavior.
5. Separate confirmed behavior from inference.
6. Identify the football principle behind the implementation.
7. Identify weaknesses or assumptions that should not be reproduced.
8. Evaluate Roblox networking, physics, character, security and performance
   constraints.
9. Design the original Beyond 90 equivalent.
10. Define the smallest implementation milestone.
11. Implement incrementally.
12. Playtest.
13. Tune.
14. Document important conclusions.

Do not immediately modify Beyond 90 gameplay code simply because an interesting
reference implementation was discovered.

Understand the reference first.

---

# 30. GameplayFootball Research Documentation

Substantial GameplayFootball research should be stored under:

    docs/research/gameplay-football/

Examples:

    player-movement.md
    ball-control.md
    dribbling.md
    passing.md
    shooting.md
    tackling.md
    goalkeeping.md
    match-state.md
    player-positioning.md
    animation-gameplay.md

Research documents should use the following structure where appropriate:

## GameplayFootball Behavior

Describe behavior confirmed directly from the source.

## Interpretation

Explain why we believe the system was designed that way.

Clearly label inference as inference.

## Useful Concepts

Identify concepts that may be valuable to Beyond 90.

## Problems / Limitations

Identify behavior or architecture that should not be reproduced.

## Roblox Considerations

Consider:

- Networking
- Server authority
- Physics
- Character systems
- Animation
- Performance
- Security
- Mobile
- Console
- Replication
- Latency

## Beyond 90 Proposal

Describe the original Roblox-native system proposed for Beyond 90.

Research documentation explains what we learned.

It does NOT define how Beyond 90 works.

---

# 31. Architecture Documentation

Once research results in an actual Beyond 90 architectural decision, document
that separately under:

    docs/architecture/

For example:

    docs/research/gameplay-football/passing.md

may influence:

    docs/architecture/passing-system.md

The distinction is:

    Research documentation
        =
    What we learned

    Architecture documentation
        =
    How Beyond 90 works

Do not allow Beyond 90 architecture documentation to become documentation of
GameplayFootball.

---

# 32. Source Accuracy

When analyzing GameplayFootball, distinguish clearly between:

CONFIRMED FROM SOURCE
    Behavior directly demonstrated by inspected source code.

INFERENCE
    A conclusion inferred from interactions between systems.

RECOMMENDATION
    Something proposed specifically for Beyond 90.

Never state:

    "GameplayFootball does X"

unless that behavior has actually been verified from the relevant source.

If uncertain, inspect the source rather than guessing.

Avoid large copied code blocks.

Focus on understanding behavior and concepts.

When creating research documentation, record the exact reference revision used.

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

This prevents future changes to the external repository from making old
research ambiguous.

If later research uses a different revision, do not silently treat the new
behavior as if it were present in the previously researched version.

---

# 33. Human-Controlled Football

GameplayFootball contains systems intended for AI-controlled footballers.

Beyond 90 is fundamentally different because competitive footballers are
expected to be controlled primarily by real players.

When researching AI-related systems, separate:

    Football intelligence useful to game systems

from:

    Decision-making required only because an AI footballer must decide what to
    do

Useful football intelligence may include:

- Ball trajectories
- Reachability
- Space
- Pitch regions
- Passing lanes
- Pressure
- Orientation
- Relative movement
- Player distances
- Ball interception geometry

Do not automatically adopt AI decision-making such as choosing when or where a
human player should pass, shoot or move.

Do not automate away player skill.

---

# 34. Networking Principle

Beyond 90 should aim for:

    RESPONSIVE LOCALLY
            +
    AUTHORITATIVE GLOBALLY

Critical competitive state should remain server-authoritative wherever
practical.

Clients must not authoritatively determine:

- Goals
- Score
- Match results
- Ball ownership
- Critical possession changes
- Successful tackles
- Competitive statistics
- Rankings
- Currency
- Persistent progression

At the same time, responsiveness matters.

Where appropriate, investigate Roblox-native techniques such as:

- Client-side prediction
- Server reconciliation
- Interpolation
- Safe extrapolation
- Input buffering
- Latency compensation
- Visual prediction
- Server validation
- Network ownership strategies
- State replication

Do not sacrifice competitive integrity simply to make gameplay responsive.

Do not sacrifice responsiveness unnecessarily simply to make implementation
easier.

---

# 35. Gameplay Configuration

Football gameplay values should normally be configurable rather than scattered
throughout implementation code.

Examples may include:

- Ball control distances
- First-touch strength
- Dribble touch strength
- Dribble frequency
- Acceleration
- Deceleration
- Turn responsiveness
- Sprint behavior
- Pass strength
- Shot strength
- Ball spin
- Tackle ranges
- Input buffering
- Network tolerances

Values inspired by external research should NOT automatically be copied.

The principles behind those values matter more than the exact numbers.

Tune values specifically for Beyond 90 through playtesting.

---

# 36. Broadcast Camera Reference Exception

GameplayFootball may be studied for general camera ideas where useful.

However, GameplayFootball does NOT define Beyond 90's Broadcast Camera.

The Broadcast Camera is one of Beyond 90's defining systems.

Its vision remains:

> A football game that feels like playing inside a football broadcast.

The Broadcast Camera should prioritize:

- Elevated top-side-of-pitch perspective
- Tactical readability
- Passing-lane visibility
- Open-space visibility
- Player positioning
- Team shape
- Smooth tracking
- Smooth zoom
- Situational framing
- Match-size-specific presets
- Minimal unnecessary movement
- Football readability over cinematic spectacle

Modern football broadcasts and modern football games may also be used as
references.

The final camera must be designed specifically for Beyond 90.

---

# 37. External Reference Licensing And Originality

Respect the licenses of external reference projects.

Prefer conceptual extraction over copying implementation.

If substantial external code is ever intentionally reused:

1. Review its license first.
2. Determine attribution/notice requirements.
3. Document the decision.
4. Keep reused code clearly identifiable where appropriate.

Beyond 90 should maintain its own identity and architecture.

Legal permission to copy something does not automatically mean copying it is
the best engineering decision.

---

# 38. Gameplay Reference Principle

When working with external football-game references, remember:

> GameplayFootball teaches us how another developer solved the football problem.
>
> Roblox determines the technical constraints we must solve within.
>
> Beyond 90 determines what the final experience should become.

Study references aggressively.

Copy concepts selectively.

Question assumptions.

Build the final system specifically for Beyond 90.