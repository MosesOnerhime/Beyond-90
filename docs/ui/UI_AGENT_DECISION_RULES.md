# Beyond 90 UI Agent Decision Rules

This is the highest-priority UI decision file for Beyond 90.

Keywords:

- **MUST / MUST NOT** = hard rule unless the current task explicitly overrides it.
- **SHOULD / SHOULD NOT** = strong default; deviate only with a concrete reason.
- **MAY** = context-dependent option.

---

## 1. Start with player intent, not decoration

Before designing or modifying a screen, the agent MUST answer:

1. What does the player need to understand first?
2. What is the primary action?
3. What is the secondary action?
4. What information is supportive rather than essential?
5. What can disappear or move on a smaller screen?
6. Is this front-end UI, gameplay HUD, modal UI, or a transitional/broadcast moment?
7. Does an existing Beyond 90 component solve at least 80% of this problem?

Visual styling comes after these questions.

---

## 2. Preserve the Beyond 90 identity

Beyond 90 MUST feel like a premium modern football game, not a sci-fi product.

### MUST

- Use football, competition, players, club identity, scorelines, stadium atmosphere and broadcast composition as the main sources of character.
- Use dark navy/charcoal surfaces, bright neutral text and restrained blue/cyan accents.
- Reserve violet/purple for selected progression, ranked or reward emphasis rather than applying it everywhere.
- Keep visual hierarchy obvious at a glance.
- Keep active/focused states strong enough to read from a television or pulled-back gameplay camera.

### MUST NOT

Do not introduce these as a default visual language:

- holographic panels;
- circuit-board patterns;
- sci-fi grids;
- scanlines;
- chromatic aberration;
- glowing borders on every card;
- transparent glass everywhere;
- random cyan/purple gradients;
- unnecessary hexagonal UI;
- floating techno glyphs;
- continuous parallax panels;
- excessive bloom-like UI glow;
- cyberpunk typography;
- thin unreadable techno fonts.

### The "not futuristic" test

Ask:

> If I removed the football content, would this screen look like a spaceship, cyberpunk terminal, crypto dashboard or generic futuristic game menu?

If yes, simplify it.

Then ask:

> Does the football identity come from the sport, competition, players, stadium, statistics and broadcast composition?

If no, strengthen football-specific content instead of adding more neon.

---

## 3. Reuse before inventing

The agent MUST inspect existing components, tokens, styles and navigation patterns before adding a new one.

The agent SHOULD:

- extend an existing card, button, modal, tab, stat row or panel;
- add variants to an existing component;
- reuse current spacing, typography and semantic color tokens;
- preserve existing architecture.

The agent MUST NOT create a second parallel system merely because it is faster for one screen.

---

## 4. Hierarchy beats density

Each screen MUST have one clear dominant layer.

A typical priority stack:

1. Primary player decision or match-critical information.
2. Current state/context.
3. Supporting information.
4. Decorative or atmospheric information.

Do not give every element the same brightness, border strength or text weight.

### Strong default

- One hero element or dominant panel per major front-end screen.
- One primary CTA per decision context.
- Secondary actions visually quieter.
- Tertiary information may be reduced, collapsed or omitted on small screens.

---

## 5. Match UI is gameplay equipment

Gameplay UI MUST protect decision-making.

It MUST:

- remain readable against bright grass, dark crowds, stadium lights and kits;
- use backing, stroke, shadow or controlled contrast where needed;
- avoid large opaque areas that block play;
- avoid long animations during live play;
- prioritize score, clock, possession/action state and relevant prompts.

It MUST NOT:

- cover the central ball/player action unnecessarily;
- stack multiple large notifications over one another;
- leave persistent decorative panels on screen with no gameplay value;
- depend on tiny detail visible only on desktop.

---

## 6. Cross-platform is part of "done"

A major UI task is incomplete until the design has defined behavior for:

- large landscape desktop;
- console/TV;
- controller focus;
- phone/touch landscape;
- at least one constrained/small viewport.

Do not simply scale the same desktop layout down.

Responsive adaptation MAY include:

- hiding tertiary information;
- stacking columns;
- converting side panels to tabs or drawers;
- shortening labels;
- increasing hit areas;
- moving controls away from touch zones;
- changing information density.

---

## 7. Input behavior must be explicit

For every interactive screen, the agent MUST define:

- mouse hover/press;
- keyboard or controller focus;
- confirm/select behavior;
- back/cancel behavior;
- touch target behavior;
- disabled behavior.

Controller focus MUST be visually distinct from hover.

Modals MUST trap focus until dismissed.

Closing a modal SHOULD restore focus to the element that opened it.

---

## 8. Accessibility is a design constraint

The agent MUST NOT use color alone to communicate:

- success/failure;
- selected/unselected;
- team identity where ambiguity matters;
- warnings;
- role/state.

Important text SHOULD meet a contrast target of at least **4.5:1** against its immediate background. Large text and large meaningful graphics SHOULD meet at least **3:1**.

Routine body text SHOULD be designed to remain comfortably readable around the equivalent of:

- **18 px at 1080p** on close-view PC;
- **26 px at 1080p** on console/TV.

These are visual reference targets, not a rule to hardcode identical Roblox `TextSize` values across all devices.

Interactive touch targets SHOULD have an effective target around **48×48 device-independent-pixel equivalent** or larger.

---

## 9. Motion is feedback, not decoration

Routine interaction feedback SHOULD begin immediately.

Strong defaults:

- press/focus response: about 70–120 ms;
- small panel transition: about 140–220 ms;
- larger screen/hero transition: only as long as necessary.

Do not add long transitions to actions the player repeats frequently.

The UI MUST respect reduced-motion preferences where the implementation supports it.

---

## 10. States are part of the component

For every reusable component, consider:

- default;
- hover;
- focused;
- pressed;
- selected;
- disabled;
- loading;
- error;
- empty;
- unavailable/locked.

Do not ship only the happy-path visual.

---

## 11. Performance and maintainability matter

The agent SHOULD prefer:

- reused components;
- reused assets;
- tokenized values;
- layout primitives;
- predictable visibility;
- event-driven updates;
- limited animation scope.

The agent SHOULD NOT add expensive continuous UI work for purely decorative motion.

---

## 12. Major-screen completion rubric

Score each category from 0 to 2:

| Category | 0 | 1 | 2 |
|---|---:|---:|---:|
| Primary task | unclear | usable | immediately obvious |
| Hierarchy | flat/confusing | acceptable | strong |
| Football identity | generic | partially sport-specific | unmistakably Beyond 90 |
| Brand fit | off-direction | mostly aligned | clearly aligned |
| Readability | poor | acceptable | strong across backgrounds |
| Gamepad | broken/undefined | works | polished |
| Touch | broken/undefined | works | purposefully adapted |
| Responsiveness | desktop-only | partially adaptive | robust |
| Accessibility | major gaps | acceptable | intentionally supported |
| Restraint | overdesigned | mostly controlled | disciplined |

A major screen SHOULD NOT be considered complete below **16/20**, and no category may be `0`.

This rubric is a Beyond 90 project quality gate, not an external industry standard.
