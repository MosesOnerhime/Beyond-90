# Beyond 90 Responsive, Mobile and Input Guidance

Beyond 90 is not a desktop-first UI that is later reduced for phones. The same information architecture must adapt intentionally across input modes and screen sizes.

---

## 1. Required target classes

Major screens SHOULD be validated in at least these classes:

### Large landscape

- desktop monitor;
- high-resolution laptop;
- console/TV.

### Medium landscape

- smaller laptop;
- tablet landscape;
- lower-resolution desktop window.

### Phone landscape

- limited vertical space;
- touch controls may consume screen edges;
- Roblox Core UI and device cutouts reduce safe area.

### Controller focus mode

Test regardless of screen size.

---

## 2. Adaptation priority

When space becomes constrained:

1. preserve primary action;
2. preserve critical context;
3. preserve readable text;
4. preserve interactive target size;
5. reduce or move secondary content;
6. remove tertiary decoration.

Do **not** shrink every element proportionally until text and targets become tiny.

---

## 3. Layout transformation

Desktop:

```text
[Primary content] [Secondary panel]
[Large navigation row]
```

Smaller landscape may become:

```text
[Primary content]
[Compact secondary summary]
[Scrollable/stacked navigation]
```

Phone landscape may become:

```text
[Primary content]
[Bottom or side actions]
[Secondary content in tabs/drawer]
```

It is acceptable for the composition to change.

---

## 4. Safe areas

Interactive UI MUST respect Roblox/device safe areas.

Full-bleed background artwork MAY extend beyond safe areas.

Buttons, navigation, settings, match controls and essential text SHOULD remain inside safe regions.

Do not place critical controls directly under:

- Roblox top-bar controls;
- phone camera cutouts;
- home indicators;
- console/TV overscan-risk edges.

---

## 5. Touch targets

Interactive touch targets SHOULD provide an effective target around **48×48 dp-equivalent** or larger.

The visible icon may be smaller than the hit area.

Increase spacing between adjacent destructive or high-frequency controls.

Do not make mobile actions rely on tiny icon-only buttons.

---

## 6. Mobile gameplay controls

Touch gameplay UI should preserve the player's view of the pitch.

Rules:

- controls should sit near natural thumb zones;
- controls should not unnecessarily cover the controlled player/ball;
- frequently used actions should receive larger targets;
- contextual actions are preferred over showing every possible button;
- joystick/touchpad areas must not clip their visual feedback;
- avoid placing important HUD data behind touch controls.

Mobile HUD density SHOULD be lower than desktop.

---

## 7. Controller navigation

All major menu interactions SHOULD be available using:

- directional navigation;
- select/confirm;
- back/cancel.

### Focus

Focused controls MUST have a clear visible state.

Focus order MUST be deterministic.

Avoid relying entirely on automatic geometric selection when it produces unpredictable jumps.

### Modals

When a modal opens:

- focus moves inside;
- background controls are not reachable;
- close/confirm returns focus appropriately.

### Back behavior

Back SHOULD generally:

1. close the top modal;
2. go to previous section;
3. close the current menu;
4. return to gameplay when appropriate.

Do not use inconsistent back semantics between sibling screens.

---

## 8. Keyboard and mouse

Mouse hover is useful but MUST NOT be the only indicator of interactivity.

Keyboard navigation SHOULD follow the same logical structure as gamepad where practical.

Do not make a feature accessible only by precise mouse movement if it is a core player workflow.

---

## 9. Preferred input

Where the implementation supports it, Beyond 90 SHOULD react to the player's current preferred input.

Examples:

- show controller glyphs when gamepad becomes primary;
- show keyboard labels when keyboard/mouse becomes primary;
- show touch controls on touch devices;
- avoid showing all three input schemes at once.

Roblox `UserInputService.PreferredInput` is an appropriate signal for this behavior.

---

## 10. Input glyphs

Use familiar glyphs.

Do not hardcode Xbox glyphs for every controller if the project has a platform-aware glyph system.

Glyphs should:

- sit next to the action label;
- remain readable;
- update with preferred input;
- avoid replacing text when the meaning would be ambiguous.

---

## 11. TV / console

Console players may sit several feet from the display.

Therefore:

- body text should be larger than close-view desktop;
- important UI should stay inside TV-safe areas;
- focus should be very obvious;
- thin lines and tiny icons should be avoided;
- essential text should not depend on a high-density 4K display.

A practical 1080p visual benchmark for normal console text is around **26 px equivalent**.

---

## 12. Responsive text

Prefer:

- `AutomaticSize`;
- layout constraints;
- wrapping;
- max/min size constraints;
- content-driven containers.

Avoid:

- tiny `TextScaled` output;
- hardcoded single-resolution widths;
- clipping translated text;
- shrinking labels until unreadable.

---

## 13. Responsive data density

Desktop MAY show:

- summary plus secondary stats;
- description text;
- multiple cards in a row.

Phone MAY show:

- summary only;
- one card at a time;
- tabs;
- swipe/scroll;
- shortened metadata.

Do not remove information required to make a decision.

---

## 14. Testing checklist

For a major UI change, test:

- 1920×1080 desktop or equivalent;
- a smaller landscape viewport;
- phone landscape;
- controller emulator;
- touch/device emulator;
- safe-area behavior;
- hover vs focus distinction;
- back/cancel flow;
- modal focus;
- long player names;
- long translated strings;
- empty/loading/error states.
