# Beyond 90 UI Components and Patterns

This file defines behavior and presentation defaults for recurring Beyond 90 UI.

---

## 1. Main hub / home screen

The home screen should communicate three things quickly:

1. Where the player is in the current season/progression.
2. The primary next action.
3. Their identity/status.

A strong Beyond 90 home composition may include:

- large stadium/player hero;
- current season/division block;
- primary navigation row or rail;
- compact currency/profile strip;
- one featured player/event card;
- restrained news/status ticker.

### MUST

- Make `Play` or the current primary mode unmistakable.
- Keep the navigation options large enough for controller and touch.
- Avoid turning the home screen into a dense grid of equal cards.
- Keep the main football imagery visually dominant but not in front of essential text.

---

## 2. Primary navigation cards

Use for major destinations such as:

- Play
- Training
- Clubs
- Profile
- Settings

Each card SHOULD have:

- icon;
- short title;
- one-line supporting description when space allows;
- clear selected/focused state.

On small screens, the description MAY disappear before the title or icon becomes too small.

### Selected state

A selected card may use:

- bright blue outline;
- brighter surface;
- subtle glow;
- icon/text lift;
- controlled scale change.

Do not animate all cards continuously.

---

## 3. Tabs

Tabs are for sibling views inside one section.

Good examples:

- Profile: Overview / Stats / History
- Clubs: Overview / Squad / Fixtures
- Settings: Gameplay / Controls / Audio / Accessibility

Rules:

- Use short labels.
- Keep active state obvious without relying only on color.
- On controller, left/right navigation should be deterministic.
- On narrow screens, tabs MAY become a horizontal scroll list or compact selector.

---

## 4. Buttons

### Primary button

Use for the current main action.

Examples:

- Play Match
- Ready
- Join
- Confirm
- Save

### Secondary button

Use for a meaningful alternative.

### Tertiary/text action

Use for low-priority navigation.

### Destructive

Use red semantics and explicit wording.

Rules:

- Every button must have focused, pressed and disabled states.
- Do not place two equally strong primary buttons side by side unless the decision genuinely has equal weight.
- Controller focus must be visually stronger than passive hover.

---

## 5. Player card

A player card MAY contain:

- overall rating;
- position;
- avatar/portrait;
- username/display name;
- key stats;
- rarity/progression frame where relevant.

Do not overload a small card with every available stat.

Use football-card language, not sci-fi circuitry.

---

## 6. Division / season panel

Prioritize:

- current division;
- current rating/points;
- progress to next threshold;
- next reward or promotion target;
- season remaining time.

Use violet sparingly for ranked/reward emphasis.

Progress should be immediately understandable.

---

## 7. Match scorebug

The scorebug MUST prioritize:

1. team identity;
2. score;
3. match time;
4. match phase/state if needed.

It SHOULD:

- sit in a stable safe region;
- have a dark backing;
- remain readable against stadium lighting;
- avoid unnecessary large animation.

It MAY show crests or short team names.

Do not add decorative data to the scorebug that is not needed during play.

---

## 8. Gameplay HUD

The HUD should be sparse.

Possible elements:

- scoreboard;
- stamina/sprint only if gameplay requires it;
- possession/action context;
- controlled-player indicator;
- contextual prompts;
- minimap;
- temporary match events.

### Contextual controls

When the player's available action changes, the UI SHOULD update the relevant prompt rather than displaying every possible control permanently.

Example:

- In possession: pass / shoot / knock-on / skill context.
- Out of possession: tackle / press / switch / jockey context.
- Set piece: set-piece-specific controls.

Do not show every control all match.

---

## 9. Minimap

The minimap must read quickly at broadcast-camera distance.

It SHOULD:

- use team-distinguishable shapes/colors;
- keep the controlled player obvious;
- preserve pitch orientation consistently;
- avoid tiny labels;
- stay visually quiet enough not to distract.

Do not rely on red-vs-green alone for team distinction.

---

## 10. Match event banner

Use for:

- goal;
- yellow/red card;
- substitution;
- kickoff/halftime/fulltime;
- player of the match;
- key tournament result.

The event banner SHOULD:

- enter quickly;
- present one dominant message;
- remain briefly;
- exit cleanly;
- avoid blocking live play longer than necessary.

A goal moment may be more expressive than a routine substitution.

---

## 11. Pause menu

Pause should provide a fast route to:

- Resume
- Settings
- Controls
- Leave/Forfeit where applicable

Match-critical context may remain visible but subdued.

On controller:

- opening pause establishes a clear first focus;
- back returns to match unless another modal is open.

---

## 12. Post-match screen

Recommended hierarchy:

1. final score/result;
2. outcome state;
3. player/team performance;
4. progression/rewards;
5. next action.

Do not lead with a giant wall of statistics.

Offer a clear next action such as:

- Continue
- Rematch
- Return to Club
- Next Match

---

## 13. Squad / formation screen

Should support:

- formation understanding;
- role/position clarity;
- player selection;
- substitutions;
- availability/status.

Use the pitch as a functional diagram.

Avoid placing tiny stat text on every player marker.

Use a side/bottom detail panel for deeper information.

---

## 14. Club screen

Prioritize:

- crest/name;
- division/record;
- members;
- upcoming fixture;
- club role/status;
- primary club action.

The screen should feel like a football club interface, not a generic social-group dashboard.

---

## 15. Training screen

Training should make the practice goal obvious.

Each drill card SHOULD explain:

- skill;
- objective;
- difficulty or recommended level if relevant;
- reward/progression if relevant;
- start action.

Avoid overwhelming new players with technical detail before the drill begins.

---

## 16. Settings

Use clear categories.

Recommended:

- Gameplay
- Controls
- Camera
- Audio
- Visual
- Accessibility
- Interface

Rules:

- Use labels plus current value.
- Sliders need readable numeric or semantic output.
- Toggles must clearly show on/off beyond color alone.
- Dangerous reset actions require confirmation.
- Settings should be fully controller navigable.

---

## 17. Modal / confirmation

Use modals for decisions that truly interrupt the current flow.

Examples:

- leave match;
- discard changes;
- purchase confirmation;
- irreversible club action.

A modal MUST:

- have one clear title;
- explain consequence concisely;
- have obvious primary/secondary actions;
- contain controller focus;
- close predictably.

Do not use modals for routine informational messages that could be a toast.

---

## 18. Toast / notification

Use for:

- saved;
- party joined;
- invite received;
- reward granted;
- connection state;
- minor error.

Toasts SHOULD:

- be short;
- avoid covering central gameplay;
- not stack indefinitely;
- disappear automatically unless action is required.

---

## 19. Loading state

Do not show an empty frozen screen.

Use one of:

- spinner/progress indicator;
- skeleton/loading placeholders;
- contextual status text.

If loading may take noticeable time, indicate that progress is still active.

Do not use elaborate long loading animations that obscure actual waiting state.

---

## 20. Empty state

An empty state should answer:

- what is empty;
- why it may be empty;
- what the player can do next.

Examples:

- No club invites
- No recent matches
- No saved formations

Avoid blank panels.

---

## 21. Error state

Errors should be:

- concise;
- actionable where possible;
- non-technical unless developer mode;
- visually distinct but not alarming beyond severity.

Examples:

- "Matchmaking failed. Try again."
- "Could not save settings."
- "Club invite expired."

Do not expose raw stack traces or internal IDs to players.
