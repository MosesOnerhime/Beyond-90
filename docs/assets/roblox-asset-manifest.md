# Beyond 90 — Roblox Asset Manifest

Traceability for every Roblox-hosted **production** asset, per `AGENTS.md` §57.

If a moderation notice ever arrives, this is how an asset ID is traced back to the
exact local source file and the config entry that references it.

---

## Milestone 6.4 uploads — 2026-08-27

Eight production UI images supplied by the user for Milestone 6.4 §8–§11.

**Pre-upload inspection (§2 / §57).** Every file below was opened and inspected
locally before upload and checked for: URLs, QR codes, email addresses, social
handles, Discord / YouTube / X / Twitch branding, watermarks, third-party
creator branding, embedded external-reference screenshots, and development or
debug text. **None were found in any of the eight.** No reference material from
FIFA, eFootball or any other title is embedded in them.

Uploaded through the Studio asset pipeline from a temporary loopback HTTP server
(`127.0.0.1`, stopped immediately afterwards). No mockups, QA captures or
reference imagery were uploaded — only these eight intended production assets.

| Roblox asset ID | Local source | Type | Purpose | Config entry | Moderation |
| --- | --- | --- | --- | --- | --- |
| `rbxassetid://94149095251371` | `assets/UI_assets/left_mouse_click.png` | Image | Keyboard footer "SELECT" prompt (§9) | `UIAssetConfig.Menu.LeftMouseClick` | **UNVERIFIED** |
| `rbxassetid://127883114740769` | `assets/UI_assets/esc_key.png` | Image | Keyboard footer "OPEN MENU" prompt (§9) | `UIAssetConfig.Menu.EscKey` | **UNVERIFIED** |
| `rbxassetid://137187938500810` | `assets/UI_assets/keyboard_image.png` | Image | Keyboard control-scheme card (§10) | `UIAssetConfig.ControlScheme.Keyboard` | **UNVERIFIED** |
| `rbxassetid://74060318259206` | `assets/UI_assets/gamepad_image.png` | Image | Gamepad control-scheme card (§10) | `UIAssetConfig.ControlScheme.Gamepad` | **UNVERIFIED** |
| `rbxassetid://71723106340650` | `assets/UI_assets/pitch_position_gk.png` | Image | GK position preview (§11) | `UIAssetConfig.PitchPositions.GK` | **UNVERIFIED** |
| `rbxassetid://132671397428450` | `assets/UI_assets/pitch_position_def.png` | Image | DEF position preview (§11) | `UIAssetConfig.PitchPositions.DEF` | **UNVERIFIED** |
| `rbxassetid://82318616333884` | `assets/UI_assets/pitch_position_mid.png` | Image | MID position preview (§11) | `UIAssetConfig.PitchPositions.MID` | **UNVERIFIED** |
| `rbxassetid://111013468900915` | `assets/UI_assets/pitch_position_fwd.png` | Image | FWD position preview (§11) | `UIAssetConfig.PitchPositions.FWD` | **UNVERIFIED** |

- Owner: the account running the Studio session (`mosesonerhime11@gmail.com`).
- Upload date: 2026-08-27.
- Moderation approval confirmed on: **not yet — see below.**

### Why these are marked UNVERIFIED

`AGENTS.md` §57 requires an asset's approved/usable state to be **confirmed**
before its ID is treated as production-ready. That confirmation could not be
made in this session: every image asset probed in this Studio session reported
`IsLoaded = false`, **including assets that have been live and working for
weeks** (for example `rbxassetid://95120414425732`, the Beyond 90 logo, and
`rbxassetid://126163821187806`, the minimap opponent marker). So `IsLoaded` is
currently measuring a session-wide asset-delivery problem rather than the
moderation state of any individual upload, and cannot distinguish the two.

Every one of the eight is therefore wired into the UI **behind a fallback**: if
the image does not resolve, the screen renders the previous drawn/procedural
presentation instead of an empty frame. Nothing breaks if moderation rejects
one, and nothing has to be re-plumbed once they are confirmed.

**To confirm:** open each ID in Studio (or the Creator Dashboard), check it
renders, then change its row to `Approved` and record the date here.

---

## Pre-existing production assets

The IDs already registered in `src/shared/Config/UIAssetConfig.luau` predate this
manifest. `UIAssetConfig.LocalSources` maps several of them back to their local
source files; the remainder have not been traced. They should be back-filled into
this table as they are touched.

### Known content issue

`rbxassetid://95120414425732` (`UIAssetConfig.Logo`, from
`assets/UI_assets/Beyond 90 transparent logo.png`) has repeatedly reported
`pending` from Roblox and has been observed never to resolve, twice per startup.
It previously blocked startup entirely through an unbounded `PreloadAsync`, and
it is why the Beyond 90 intro stage could appear to pop rather than fade — the
stage was fading a CanvasGroup that had no decoded image in it.

The intro now waits (bounded) for the image and falls back to a text wordmark, so
the fade is always visible. The underlying asset problem is unresolved and may
warrant a re-upload.

---

## Rules

- Only finalized, intentional production assets are uploaded (§57).
- Mockups, reference imagery, QA captures and temporary development artwork stay
  **local** and must never enter the Roblox asset pipeline.
- Every image is inspected locally before upload for off-platform destinations
  and unrelated branding.
- A new asset ID is not treated as production-ready until its moderation state is
  confirmed and recorded above.
