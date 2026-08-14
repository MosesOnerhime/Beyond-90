# EA Football Controls Research

Research date: 2026-08-14

Primary official sources:

- EA FIFA 14 manual page: https://www.ea.com/news/fifa-14-xbox-360-ps3-pc-manual
- FIFA 14 web manual mirror for complete controls: https://dlassets-ssl.xboxlive.com/public/content/f04f7029-01ea-4d65-988b-56f583fb7f6c/GameManual/d9f7cb3d-531c-44ae-b8e3-1ccb82eaefa8/en-IE/index.html
- EA FIFA 14 advanced right stick moves: https://www.ea.com/en-gb/news/fifa-14-tips-advanced-right-stick-moves
- EA FIFA 22 Xbox Series X basic controls: https://www.ea.com/able/resources/fifa/fifa-22/xbox-series-x/basic-controls
- EA FIFA 22 PC customise controls settings: https://www.ea.com/able/resources/fifa/fifa-22/pc/customise-controls-settings
- EA FIFA Mobile advanced passing deep dive: https://www.ea.com/ea-originals/news/gameplay-advanced-passing
- EA FIFA Mobile gameplay controls guide: https://www.ea.com/en-gb/playtesting/news/gameplay-guide

## CONFIRMED FROM OFFICIAL EA DOCUMENTATION

- Ground pass is a primary attacking action. Modern EA documentation lists Ground Pass/Header as a simple attacking control.
- Through pass is a distinct primary attacking action. Xbox controls list Through Pass separately from Ground Pass.
- Advanced controls include driven ground pass, lofted ground pass, lofted through pass and lobbed through pass as pass variants.
- FIFA 22 control settings document Ground Pass Assistance and Through Pass Assistance. These settings determine how direction and power are assisted.
- FIFA 22 Shot Assistance determines whether shot direction is assisted toward goal; this is separate from pass assistance.
- FIFA Mobile button controls support holding Pass or Through. The documentation says longer hold increases pass travel and selects the corresponding receiver.
- FIFA Mobile differentiates ground pass to feet from through pass into space. Gesture controls treat tapping on/behind a player as pass to feet and tapping in front as pass into space.
- FIFA Mobile advanced passing includes driven ground passes, dinked ground passes, dinked through ground passes and driven lob passes.
- FIFA 14 documents First Touch / Knock-On as a movement control, and EA's FIFA 14 right-stick article describes regular and double Knock-On as pushing the ball farther ahead into space so a fast player can run onto it.

## OBSERVED / INTERPRETED BEHAVIOR

- EA's passing model separates the player's action choice from the assistance layer. The player chooses ground pass or through pass; assistance helps choose direction/power and receiver.
- Through passes are intended as passes into space, not merely passes to current feet position.
- Knock-On is a deliberate larger touch for open space and pace advantage, not ordinary sprint dribbling.

## BEYOND 90 CONTROL PROPOSAL

- Temporary PC controls for 5.1:
  - `E`: Ground Pass
  - `Q`: Through Pass
  - `R`: Knock-On
- Future controller proposal:
  - Face button for Ground Pass.
  - Separate face button for Through Pass.
  - Right-stick flick while sprinting for Knock-On / larger Knock-On variants.
- Future mobile proposal:
  - Pass and Through buttons with hold duration.
  - Tap/touch target or space selection later.
  - Knock-On as a contextual sprint-direction button or directional flick gesture.

## BEYOND 90 ASSISTANCE BOUNDARY

The player chooses action and rough intent. Beyond 90 may assist receiver selection, lead point and physical power, but the ball is released as a physical football and remains interceptable.

