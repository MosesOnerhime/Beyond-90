# Beyond 90 UI Research Sources

This file records the external guidance used to create the Beyond 90 UI rules. It is a rationale/reference document, not the first file an agent should read.

External sources are used for principles and platform constraints. They do **not** override the approved Beyond 90 visual direction.

---

## Roblox Creator Hub

### UI and UX design

https://create.roblox.com/docs/production/game-design/ui-ux-design

Why it matters:

- information should be prioritized and contextualized;
- size, color, spacing and proximity communicate hierarchy;
- genre conventions help players understand UI quickly;
- Roblox's own UI/UX material includes contextual gameplay-control thinking relevant to football.

Beyond 90 rule derived:

- show the player what matters in the current football context instead of displaying every possible control or statistic all the time.

---

### Adaptive design guidelines

https://create.roblox.com/docs/production/publishing/adaptive-design

Why it matters:

- Roblox is cross-platform;
- UI should adapt to different displays and accessibility preferences;
- readability must be maintained across phone, desktop and TV contexts.

Beyond 90 rule derived:

- desktop-only screenshots are not completion criteria;
- major screens must define smaller-screen behavior.

---

### Input

https://create.roblox.com/docs/input

### UserInputService / PreferredInput

https://create.roblox.com/docs/reference/engine/classes/UserInputService

Why it matters:

- Roblox supports mouse/keyboard, touch and gamepad;
- `PreferredInput` can reflect the player's likely primary input.

Beyond 90 rule derived:

- input prompts and touch/controller UI should adapt instead of showing every scheme at once.

---

### Console development guidelines

https://create.roblox.com/docs/production/publishing/console-guidelines

Why it matters:

- important UI should stay in TV-safe areas;
- controller navigation needs to be straightforward.

Beyond 90 rule derived:

- controller focus and TV readability are first-class requirements.

---

### Studio testing modes

https://create.roblox.com/docs/studio/testing-modes

Why it matters:

- Studio provides controller/device/locale emulation.

Beyond 90 rule derived:

- agents should test controller navigation and responsive/localized layouts rather than reasoning only from code.

---

### On-screen UI containers / safe insets

https://create.roblox.com/docs/ui/on-screen-containers

### ScreenInsets

https://create.roblox.com/docs/reference/engine/enums/ScreenInsets

Why it matters:

- Roblox provides safe-area handling for Core UI and device cutouts.

Beyond 90 rule derived:

- essential interactive UI must stay in safe areas while full-bleed stadium art may extend beyond them.

---

### List and flex layouts

https://create.roblox.com/docs/ui/list-flex-layouts

### AutomaticSize

https://create.roblox.com/docs/reference/engine/classes/GuiObject/AutomaticSize

### Size modifiers and constraints

https://create.roblox.com/docs/ui/size-modifiers

Why it matters:

- Roblox provides content-driven and constraint-based layout primitives.

Beyond 90 rule derived:

- use adaptive layout systems instead of manually repositioning every element for each resolution.

---

### UI styling / Style Editor

https://create.roblox.com/docs/ui/styling

https://create.roblox.com/docs/ui/styling/editor

Why it matters:

- Roblox supports reusable styling and design tokens.

Beyond 90 rule derived:

- semantic tokens and reusable components are preferred over scattered raw UI values.

---

### Accessibility

https://create.roblox.com/docs/production/publishing/accessibility

### PreferredTransparency

https://create.roblox.com/docs/reference/engine/classes/GuiService/PreferredTransparency

Why it matters:

- Roblox exposes player preferences including transparency, text size and reduced motion.

Beyond 90 rule derived:

- dark translucent sports panels should become more opaque when requested;
- decorative motion should reduce when requested.

---

### Localization

https://create.roblox.com/docs/production/localization

https://create.roblox.com/docs/production/localization/automatic-translations

https://create.roblox.com/docs/production/localization/auto-translate-dynamic-content

https://create.roblox.com/docs/production/localization/translate-dynamic-content

Why it matters:

- Roblox supports automatic/manual localization and dynamic translated content.

Beyond 90 rule derived:

- do not concatenate sentence fragments or design boxes only for English;
- dynamic football strings should use parameters and responsive layout.

---

## Microsoft / Xbox Accessibility Guidelines

### Text display

https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/101

Relevant reference guidance:

- normal console text: 26 px at 1080p;
- normal PC/VR text: 18 px at 1080p.

Beyond 90 use:

- these are used as visual QA reference targets for readable game UI, especially broadcast-camera gameplay and TV use;
- they are not direct Roblox `TextSize` values.

---

### Contrast

https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102

Beyond 90 use:

- important normal text should target 4.5:1 contrast;
- large text/meaningful large graphics should target 3:1.

---

### Input and UI navigation

https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107

https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/112

Why it matters:

- game UI should support robust digital/analog navigation and multiple input methods.

Beyond 90 rule derived:

- controller focus order, back behavior and modal containment are explicitly part of the design.

---

## W3C WCAG 2.2

### Contrast

https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum

### Target size quick reference

https://www.w3.org/WAI/WCAG22/quickref/

Why it matters:

- contrast and minimum-target guidance provide broadly tested accessibility baselines.

Beyond 90 use:

- reinforces the 4.5:1 / 3:1 contrast targets;
- WCAG's smaller pointer minimum is treated as a floor, while Beyond 90 prefers larger touch targets.

---

## Android accessibility guidance

https://developer.android.com/guide/topics/ui/accessibility/views/apps-views

https://developer.android.com/develop/ui/compose/accessibility/api-defaults

Relevant guidance:

- interactive touch targets are recommended around 48×48 dp.

Beyond 90 use:

- mobile/touch controls should provide roughly 48×48 dp-equivalent hit areas or larger.

---

## Nielsen Norman Group — response time and animation usability

https://www.nngroup.com/articles/response-times-3-important-limits/

https://www.nngroup.com/articles/animation-usability/

https://www.nngroup.com/articles/timing-exposing-content/

Why it matters:

- interaction feedback should begin very quickly;
- decorative motion can impede repeated navigation.

Beyond 90 rule derived:

- press/focus feedback should feel immediate;
- routine animations should be short;
- frequently repeated menu actions should not wait for long cinematic transitions.

---

## EA SPORTS FC accessibility resources

https://www.ea.com/able/resources/ea-sports-fc/fc-26

Why it matters:

- a current major football title treats features such as subtitles, color support and communication/menu accessibility as normal production features.

Beyond 90 use:

- this is a maturity reference, not a visual template;
- Beyond 90 should treat accessibility as part of the football-game settings experience rather than an afterthought.

---

## Approved Beyond 90 mockup

Primary visual reference supplied by the project owner.

Key traits extracted:

- dark night stadium;
- navy/charcoal UI surfaces;
- crisp white text;
- restrained electric blue selection;
- limited purple for ranked/player-card emphasis;
- large player/stadium imagery;
- strong rectangular navigation cards;
- clear sports hierarchy;
- subtle glow rather than glow everywhere;
- modern football presentation rather than sci-fi presentation.

This mockup takes precedence over older wording that described Beyond 90 UI as generally "futuristic."
