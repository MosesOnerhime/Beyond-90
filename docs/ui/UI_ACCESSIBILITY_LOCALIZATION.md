# Beyond 90 Accessibility and Localization

Accessibility is part of production quality, not a separate visual mode.

---

## 1. Text readability

Essential text SHOULD target at least **4.5:1** contrast against its immediate background.

Large text and large meaningful graphics SHOULD target at least **3:1**.

Practical 1080p reference targets:

- close-view PC normal text: ~18 px equivalent;
- console/TV normal text: ~26 px equivalent.

These values are visual QA benchmarks, not a requirement to assign one universal Roblox `TextSize`.

Avoid:

- thin type;
- low-contrast grey on transparent navy;
- text over uncontrolled stadium lights;
- tiny stat labels;
- excessive uppercase body copy.

---

## 2. Text over gameplay

Live HUD text may need:

- opaque/semi-opaque backing;
- soft shadow;
- subtle stroke;
- controlled darkening panel.

Do not rely on the world behind the text remaining dark.

---

## 3. Color

Never rely on color alone to communicate:

- selected state;
- success/failure;
- warning;
- team/role distinction where confusion matters;
- locked/unlocked state.

Combine color with:

- text;
- icon;
- shape;
- border;
- label;
- pattern where appropriate.

---

## 4. Team differentiation

Team colors should remain distinguishable under common color-vision differences.

Where needed, combine:

- kit color;
- player marker shape;
- outline;
- icon;
- direction/label.

Avoid red-vs-green as the only distinction.

---

## 5. Focus

Controller/keyboard focus MUST be obvious.

A good focus state may combine:

- bright border;
- light surface shift;
- icon/text shift;
- small scale increase;
- accent bar.

The focus indicator should not disappear against a bright selected surface.

---

## 6. Motion

Respect reduced-motion preferences where the platform/API allows it.

Reduced-motion behavior SHOULD:

- remove decorative looping movement;
- replace large slides with fades or shorter transitions;
- suppress unnecessary scale/bounce;
- preserve essential state-change feedback.

Do not remove information just because motion is reduced.

---

## 7. Transparency

Roblox exposes player transparency preferences.

When the player prefers lower transparency, Beyond 90 SHOULD increase panel opacity where practical.

This is especially important for:

- settings;
- navigation;
- text-heavy cards;
- score/event overlays.

---

## 8. Audio feedback

Audio MAY reinforce:

- selection;
- confirmation;
- error;
- reward;
- match event.

Do not make sound the only indication that an action succeeded or failed.

Provide separate audio category controls where the broader game architecture supports them.

---

## 9. Input accessibility

Core menu workflows SHOULD be navigable by:

- mouse;
- keyboard where appropriate;
- controller;
- touch on touch devices.

Avoid requiring drag-only interactions for essential actions if a tap/button alternative can be provided.

---

## 10. Localization

UI must assume text length changes.

Do not design only for English.

### Use

- wrapping;
- `AutomaticSize`;
- max widths;
- flexible layout;
- parameterized strings;
- localization tables/APIs.

### Avoid

- concatenating sentence fragments in code;
- fixed boxes sized only for English;
- shrinking translated text to tiny sizes;
- truncating critical labels without an alternative.

---

## 11. Dynamic strings

Dynamic values should use parameterized localization.

Prefer a structure equivalent to:

```text
"Season ends in {days} days"
```

instead of manually joining independently translated fragments.

---

## 12. Pseudolocalization / long-string testing

Major screens SHOULD be tested with:

- longer-than-English strings;
- wide usernames;
- long club names;
- large numeric values;
- locale emulation/pseudolocalization where available.

Check that:

- buttons expand or reflow;
- labels wrap predictably;
- columns do not overlap;
- icon/text alignment survives.

---

## 13. Accessibility settings

Beyond 90's Settings should have a clear Accessibility section when the feature set supports it.

Potential options may include:

- text/UI scale;
- reduced motion;
- transparency/readability;
- color assistance;
- subtitles;
- menu narration where feasible;
- communication accessibility features where relevant.

Do not claim support for features that are not actually implemented.

---

## 14. Accessibility QA questions

Before shipping a major screen:

- Can essential text be read from a TV?
- Does the screen work without distinguishing colors perfectly?
- Is controller focus obvious?
- Can the primary action be completed without a mouse?
- Does reduced motion still communicate state?
- Does reduced transparency improve text-heavy surfaces?
- Do long strings break the layout?
- Are touch targets comfortably tappable?
