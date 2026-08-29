# Beyond 90 UI Agent Guide

This folder contains the authoritative UI/UX guidance for AI agents working on **Beyond 90**.

The visual north star is the approved Beyond 90 main-menu mockup: a **premium contemporary football game** presented with **sports-broadcast clarity**, not a futuristic/sci-fi interface.

## Read order

For any UI task, read these in order:

1. `UI_AGENT_DECISION_RULES.md`
2. `UI_DESIGN_SYSTEM.md`
3. The task-specific file:
   - `UI_COMPONENTS_AND_PATTERNS.md`
   - `UI_RESPONSIVE_INPUT.md`
   - `UI_ACCESSIBILITY_LOCALIZATION.md`
   - `UI_ROBLOX_IMPLEMENTATION.md`
4. `UI_RESEARCH_SOURCES.md` only when the rationale or external source needs to be checked.

## Authority

When guidance conflicts, use this priority:

1. Explicit user instruction for the current task.
2. Existing Beyond 90 production UI architecture and reusable components.
3. `UI_AGENT_DECISION_RULES.md`.
4. Other files in this folder.
5. External reference games and generic UI conventions.

Do not redesign unrelated systems just because a different solution seems aesthetically preferable.

## Beyond 90 visual target

Use these words to describe the intended UI:

**athletic · confident · broadcast · competitive · premium · clean · energetic · stadium-lit · modern**

Do **not** interpret Beyond 90 as:

**cyberpunk · holographic · hyper-neon · techno-industrial · crypto-dashboard · generic Roblox simulator · glassmorphism showcase**

The football identity should come from:

- the pitch and stadium;
- players, kits and squad numbers;
- club crests and divisions;
- scorelines and match clocks;
- football statistics;
- formations and roles;
- player cards;
- trophies and season progression;
- broadcast-style match events.

It should **not** come from adding more neon, sci-fi grids or decorative technology motifs.

## Project context the UI must support

Beyond 90 is a cross-platform Roblox football game with modes including:

- quick 3v3;
- 5v5 tournaments;
- 11v11 Clubs;
- training and practice;
- long-term profile, club, season and reputation progression.

Gameplay may use a broadcast-style camera. This means match UI must remain readable while the camera is pulled back and while players are visually small on screen.

Supported interaction modes include:

- keyboard + mouse;
- controller/gamepad;
- touch;
- phone;
- tablet;
- console/TV.

## Existing system first

Before creating a new component, an AI agent must inspect the repository and answer:

- Is there already a component that solves most of this?
- Is there already a token/style for this?
- Does an existing screen define the current navigation pattern?
- Does the codebase already have input-aware UI behavior?
- Does the codebase already have responsive breakpoints or layout utilities?

Prefer extending an existing solution over creating a parallel design system.

## Non-goals

Do not:

- remake the UI around a trendy web aesthetic;
- make every card translucent;
- use glow on every outline;
- overuse pill-shaped containers;
- turn menus into dashboards full of tiny stats;
- shrink desktop UI unchanged onto mobile;
- sacrifice readability for cinematic presentation;
- copy EA FC, eFootball or another game literally;
- introduce one-off colors, corner radii, shadows or animations when a token already exists;
- make large unrelated UI refactors during a focused task.

## Output expectation for AI agents

A UI change is not complete because it looks good in one desktop screenshot.

It should be validated for:

- visual hierarchy;
- brand fit;
- football identity;
- keyboard/mouse;
- gamepad focus and back behavior;
- touch;
- small landscape screens;
- safe areas;
- text readability;
- reduced motion/transparency preferences where relevant;
- empty/loading/error/disabled states;
- runtime performance.
