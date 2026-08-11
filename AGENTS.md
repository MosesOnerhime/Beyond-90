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
3. Passing
4. Shooting
5. Tackling/interactions
6. Player possession
7. Team systems
8. Camera system
9. Match flow
10. UI
11. Matchmaking
12. Progression
13. Clubs
14. Social systems
15. Monetization

Do not build complex progression or monetization systems before the core
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

When implementing a feature, verify that it works across the supported
formats:

- 3v3
- 5v5
- 7v7
- 11v11

Do not assume 11v11.

If a feature is intentionally limited to a specific game mode, document
that limitation clearly.

---

# 22. Testing

After implementing a feature:

- Check for Luau errors
- Test server/client behavior
- Test multiple players where relevant
- Test different match sizes
- Test camera transitions
- Test edge cases
- Check performance
- Verify existing systems still work

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
    COMPETITIVE FAIRNESS
    ↓
    PERFORMANCE
    ↓
    SCALABILITY
    ↓
    POLISH

Do not sacrifice core gameplay quality for unnecessary features.

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