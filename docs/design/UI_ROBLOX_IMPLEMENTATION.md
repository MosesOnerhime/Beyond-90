# Beyond 90 Roblox UI Implementation Rules

This file translates the Beyond 90 design direction into Roblox implementation practice.

---

## 1. Local source and project architecture

Follow the repository's existing UI architecture.

Before writing new UI code, inspect:

- shared components;
- theme/tokens;
- navigation;
- input abstraction;
- screen routing;
- animation helpers;
- device utilities;
- existing React/Roact/Fusion/native-instance conventions.

Do not introduce a new UI framework inside one feature.

---

## 2. Tokens and styling

Prefer shared semantic tokens over raw values scattered through components.

Examples:

```text
color.canvas
color.surface.1
color.surface.hover
color.text.primary
color.text.secondary
color.action.primary
color.rank.violet
color.semantic.success
color.semantic.warning
color.semantic.danger

space.s
space.m
space.l

radius.card
radius.button

motion.fast
motion.panel
```

If the project uses Roblox UI styling/StyleSheets, use that system rather than duplicating raw properties.

---

## 3. Layout primitives

Prefer Roblox layout systems over manual pixel positioning.

Use as appropriate:

- `UIListLayout`;
- flex/wrapping behavior;
- `UIPadding`;
- `UIGridLayout`;
- `AutomaticSize`;
- `UISizeConstraint`;
- `UITextSizeConstraint`;
- `UIAspectRatioConstraint`.

Manual absolute positioning MAY be used for intentionally composed hero/broadcast UI, but should not become the default for content-heavy responsive screens.

---

## 4. Scale vs offset

Use a deliberate combination.

Good general pattern:

- Scale for broad responsive placement/sizing.
- Offset for controlled minimum padding, icon sizes and small details.
- Constraints to prevent extremes.

Do not make entire screens depend on one fixed resolution.

---

## 5. `TextScaled`

Do not use `TextScaled` as a shortcut for responsive typography without constraints.

It can produce text that becomes too small.

Prefer:

- controlled `TextSize`;
- responsive tiering;
- `UITextSizeConstraint`;
- wrapping;
- content-driven sizing.

---

## 6. ScreenGui safe areas

Interactive `ScreenGui` content SHOULD respect appropriate safe insets.

Roblox `CoreUISafeInsets`/screen-inset handling should be used where suitable.

Full-bleed artwork MAY extend outside the interactive safe region.

---

## 7. Input awareness

Use the project's input abstraction.

Where direct Roblox input state is needed, `UserInputService.PreferredInput` is an appropriate signal for primary input mode.

Update:

- button glyphs;
- touch controls;
- hover/focus expectations;
- instructional prompts.

Do not permanently display keyboard, controller and touch prompts simultaneously.

---

## 8. Controller selection

Controller navigation must be intentionally tested.

Use Roblox selection/focus behavior and explicit next-selection links when automatic navigation is unreliable.

Rules:

- deterministic focus;
- obvious selected state;
- no focus leaks behind modals;
- sensible initial selection;
- restore prior selection after closing overlays.

Test with Studio's Controller Emulator.

---

## 9. Touch

Do not reuse small desktop hitboxes unchanged.

Touch targets SHOULD be around a 48×48 dp-equivalent effective area or larger.

The visible art may be smaller than the interactive button frame.

Touch controls should use safe zones and avoid overlap with Core UI.

---

## 10. Runtime updates

UI SHOULD update from state changes/events rather than unnecessary per-frame polling.

Per-frame work MAY be justified for:

- live reticles;
- smooth minimap transforms;
- time-sensitive gameplay indicators.

Even then:

- update only what must change;
- disconnect when hidden;
- avoid rebuilding large trees every frame.

---

## 11. Animation

Use the project's animation/tween helpers if available.

Routine interactions:

- short duration;
- limited properties;
- no perpetual loops unless information requires them.

Prefer animating:

- transparency;
- scale;
- position;
- subtle color/surface state.

Avoid expensive stacks of continuously animated gradients, strokes and particles.

---

## 12. Visibility

Hidden screens should not keep expensive effects active.

When a screen closes:

- disconnect temporary listeners;
- stop loops/tweens;
- release temporary resources;
- avoid invisible active interaction.

---

## 13. Z-order

Keep a consistent layer model.

Example:

```text
0–9   base screen
10–19 persistent HUD
20–29 temporary panels
30–39 modal dimmer/modal
40–49 toasts
50+   critical system overlay
```

Use the project's existing convention if one already exists.

Do not assign random high ZIndex values to fix stacking locally.

---

## 14. Reusable component contract

A reusable component SHOULD expose semantic properties rather than raw visual plumbing.

Prefer:

```text
variant = "primary"
state = "selected"
icon = ...
label = ...
disabled = ...
```

over passing ten unrelated color/transparency values from every caller.

---

## 15. Required component states

Reusable interactive components should support:

- default;
- hover;
- focused;
- pressed;
- selected where relevant;
- disabled;
- loading where relevant.

---

## 16. Loading and async actions

When an action takes noticeable time:

- disable duplicate submissions;
- show progress/loading state;
- preserve the current screen unless navigation is intentional;
- handle failure visibly.

Do not let repeated button presses create duplicate requests.

---

## 17. Localization implementation

Use Roblox localization systems or the project's wrapper.

Dynamic text SHOULD be parameterized.

Use locale emulation/pseudolocalization in Studio when validating major screens.

---

## 18. Accessibility preferences

Where available, respect Roblox player UI preferences such as:

- preferred transparency;
- text/UI scaling;
- reduced motion.

Do not hardcode decorative behavior that ignores user preferences.

---

## 19. Performance validation

For major UI changes:

- test on a lower-end supported device class when possible;
- inspect memory if large assets are added;
- avoid loading many high-resolution images at once;
- reuse atlases/assets where architecture supports it;
- avoid oversized off-screen trees.

---

## 20. Agent implementation workflow

For any non-trivial UI task:

1. Inspect current UI architecture.
2. Find nearest existing component/screen.
3. Identify tokens/layout/input helpers.
4. State the intended information hierarchy.
5. Implement the smallest coherent change.
6. Verify desktop.
7. Verify controller.
8. Verify touch/small landscape.
9. Verify loading/error/empty/disabled states.
10. Check that no unrelated UI was redesigned.
