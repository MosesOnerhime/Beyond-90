# Beyond 90 UI Design System

## 1. Visual philosophy

Beyond 90 combines:

- premium football-game presentation;
- sports-broadcast clarity;
- Roblox-native usability;
- restrained modern digital polish.

The interface should look contemporary and competitive without becoming sci-fi.

### Visual keywords

**athletic · bold · composed · stadium-lit · modern · broadcast · premium · clean**

### Avoid

**cyberpunk · holographic · hyper-glossy · overly glassy · neon-everywhere · tech-demo UI**

---

## 2. Working color tokens

These values are the current **design-direction tokens** derived from the approved mockup. If the codebase already contains canonical tokens, use those instead of duplicating them.

```text
Canvas              #030916
Stage               #081329

Surface 1           #0B1830
Surface 2           #102349
Hover Surface       #142B55

Primary Text        #F2F6FB
Secondary Text      #A6B2C6

Primary Blue        #2F8CFF
Bright Focus Blue   #5DB2FF
Cyan Highlight      #12C4FF
Ranked Violet       #8B5CF6

Success             #2ED67B
Warning             #F2B84B
Danger              #FF5A67
```

### Semantic rules

#### Blue

Use for:

- primary interaction;
- active navigation;
- focus;
- progress;
- key links;
- interactive emphasis.

Do not make every border blue.

#### Cyan

Use sparingly for:

- special highlight;
- broadcast accent;
- key data flourish;
- secondary emphasis.

#### Violet

Use selectively for:

- ranked/division;
- rare rewards;
- premium progression emphasis;
- special competitive states.

Do not make it a general-purpose accent equal to blue.

#### Red/amber/green

Preserve semantic meaning:

- red = destructive/error/critical;
- amber = warning/caution;
- green = success/ready/positive.

---

## 3. Surfaces

Most UI surfaces SHOULD be opaque or near-opaque dark navy/charcoal.

Preferred layering:

1. stadium/game world;
2. dark structural panel;
3. lighter hover/selected surface;
4. small accent line/border;
5. text and icon.

### Transparency

Semi-transparent surfaces MAY be used when they preserve readability over a stadium background.

Do not rely on transparency alone for depth.

When Roblox/player preferences indicate reduced transparency, backgrounds SHOULD become more opaque.

### Glassmorphism

Glassmorphism is **not** the default Beyond 90 style.

If used at all:

- use it only in small controlled moments;
- keep blur/glow restrained;
- ensure text remains high contrast;
- do not stack several transparent layers.

---

## 4. Borders and focus

Default cards SHOULD use subtle separation, not glowing outlines.

Selected/focused states MAY use:

- brighter border;
- controlled outer glow;
- accent strip;
- slight surface lift;
- scale increase of only a few percent when appropriate.

The focus state must be obvious on controller.

Avoid:

- 2–3 glowing strokes on every card;
- always-on neon outlines;
- pulsing focus unless the context truly needs attention.

---

## 5. Corner radius

Beyond 90 should use **moderate** rounding.

Recommended visual character:

- cards: medium radius;
- buttons: medium radius;
- compact chips/tags: smaller or pill only when semantically appropriate;
- large panels: medium-to-large radius, but not excessively soft.

Do not turn every control into a capsule.

If the repository already defines radius tokens, use them.

---

## 6. Typography

Use the project’s existing type system where available.

The target character is:

- bold sports headline;
- clear UI sans-serif body;
- strong numeric readability;
- high legibility at distance.

### Hierarchy

Use:

- Display / Hero
- Screen Title
- Section Heading
- Primary Label
- Body
- Secondary / Meta
- Caption

### Rules

- Scorelines and clocks should use stable, highly readable numerals.
- Do not use overly condensed display type for long text.
- Avoid very thin weights.
- Avoid all-caps paragraphs.
- All-caps MAY be used for short labels, tabs and sports/broadcast headings.
- Do not solve space problems by shrinking text until it is hard to read.

### 1080p visual reference

For essential normal text, design around at least:

- PC close-view: ~18 px equivalent;
- console/TV: ~26 px equivalent.

Treat this as a visual testing benchmark, not a one-size-fits-all Roblox `TextSize`.

---

## 7. Spacing

Use a consistent spacing rhythm rather than one-off gaps.

Recommended conceptual scale:

```text
XS   4
S    8
M    12
L    16
XL   24
2XL  32
3XL  48
4XL  64
```

These are design units/reference values. The implementation may use scale-aware equivalents.

### Rules

- Related label/value pairs stay close.
- Separate unrelated sections with visibly larger spacing.
- A card should have enough internal padding to read cleanly on TV and touch.
- Dense data screens may tighten spacing, but should preserve scanability.

---

## 8. Icons

Icons should be:

- simple;
- bold enough to read at small size;
- consistent in stroke/fill style;
- semantically obvious;
- paired with text when ambiguity is likely.

Football-specific imagery is preferred over abstract tech imagery.

Good:

- trophy;
- crest;
- boot;
- ball;
- pitch;
- formation;
- whistle;
- card;
- player;
- team;
- calendar;
- settings.

Avoid using a futuristic glyph when a conventional sports icon communicates faster.

---

## 9. Imagery

Front-end hero imagery SHOULD reinforce:

- football;
- stadium scale;
- player identity;
- competition;
- season progression.

The approved menu mockup uses the stadium and a large footballer as atmosphere while the UI remains readable on top.

Rules:

- subject should not compete with important text;
- darken or grade the background when needed;
- keep text over predictable contrast zones;
- avoid unnecessary particles directly behind text.

---

## 10. Depth and glow

Depth hierarchy should come from:

- surface luminance;
- layering;
- spacing;
- subtle shadow;
- contrast;
- selective glow.

Glow is an accent.

Use it for:

- active focus;
- a rare premium/ranked highlight;
- selected main navigation;
- major hero moment.

Do not use it on every separator, icon and card.

---

## 11. Gradients

Gradients MAY be used for:

- brand hero treatment;
- progress;
- ranked/reward identity;
- background atmospheric transitions.

They SHOULD NOT be used merely because a flat fill looks "too simple."

Prefer dark-to-darker surface gradients over bright multi-color rainbow effects.

---

## 12. Data visualization

Football data should be easy to scan.

Prefer:

- bars;
- compact stat rows;
- simple radar/spider chart only when it adds real comparison value;
- formation diagrams;
- percentile/rating labels;
- tables with strong row separation.

Avoid:

- tiny dashboard widgets;
- decorative charts with no decision value;
- too many simultaneous accent colors.

---

## 13. Animation language

Routine UI:

- quick;
- controlled;
- minimal travel;
- responsive.

Hero moments may be more expressive.

Avoid:

- full 3D panel flips for normal navigation;
- constant floating;
- endless pulsing;
- menu camera shake;
- long transitions on repeated actions;
- unbounded particle effects.

---

## 14. Football-broadcast layer

Broadcast graphics should feel slightly more formal than front-end menus.

They may use:

- clean rectangular scorebugs;
- team crests;
- sharp typography;
- small accent strips;
- short entrance/exit motion;
- neutral dark backing;
- time-sensitive event cards.

They should not inherit excessive menu decoration.


---

## Selection And Focus: Edge Markers, Not Rings

**Decision (2026-09-01), replacing the previous outline-based states.**

Selection and gamepad focus are shown with a solid marker on the control's
LEADING EDGE, plus a small lift in the card's own surface. They are never shown
with a ring, halo, or glowing border around the control.

- **Selected** (the screen you are on): 4px accent-blue bar down the left edge,
  72% of the card's height, centred vertically.
- **Focused** (where the controller is sitting): the same bar in white — the
  same white selected labels use.
- **Primary buttons**, whose labels are centred and which have no leading edge to
  spare, use a 3px white underline across the middle 55% instead.
- **Hover**: surface lift only.

### Why

Rings were rejected in playtest ("I do not like the blue selector round
boxes/buttons in the menu"), and `AGENTS.md` §40 already lists *glowing borders
on every card* among the defaults to avoid. Three outlines were stacking at once
on the Home cards: a cyan halo on the selected card, a brightened stroke on it,
and a second ring on the focused one.

An edge marker is what sports broadcast and EA FC's own menus use. It reads at TV
distance, survives a bright stadium background behind a translucent panel, costs
one thin rectangle, and leaves the card's rectangle clean — which is what makes
the "strong rectangular navigation cards" of the approved mockup work.

### Rule

Every screen uses the same marker. If a control cannot take a leading-edge bar,
use the underline variant — do not reintroduce an outline for that one case, or
selection stops meaning the same thing from screen to screen.
