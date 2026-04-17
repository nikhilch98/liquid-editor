# LiquidEditor — Premium UI Redesign (Sub-projects #1 + #2)

**Date:** 2026-04-18
**Status:** Approved design, ready for implementation plan
**Scope:** Sub-project #1 (design-system extension) + Sub-project #2 (editor shell).
Sub-projects #3–#6 (timeline surface, tool sheets, meta sheets, library/settings) are deferred to follow-up specs. They must consume the tokens and components defined here.

---

## Reference & direction

**Aesthetic reference:** Instagram *Edits* app — dark mobile-first NLE, pill-shaped controls, monospaced timecodes, mustard-amber active accent, heavy use of translucent chrome.

**Design direction:** *"Edits faithfully"* spine + *"iOS 26 Liquid Glass"* materials. Edits provides the visual language (palette, shape, type, haptics); iOS 26 Liquid Glass provides the material treatment for every floating surface (nav, toolbar, sheets, chips, playhead time chip). Dark-mode only.

**Adaptivity:** "Fluid native" — same view hierarchy across iPhone and iPad. No iPad-exclusive sidebar/inspector. Sizes, spacings, and zoom defaults adapt via a derived `formFactor: .compact | .regular` flag at the EditorView root. On iPad the timeline uses full canvas width; the nav bar and toolbar cap at `min(canvasWidth, 1180pt)` with symmetrical horizontal padding.

**Intentional YAGNI (out of scope for this spec):**
- iPad multi-pane layout / right-hand inspector.
- Light mode.
- Custom fonts (San Francisco family only).
- Stage Manager / multi-scene support.

---

## Section 1 — Design tokens

New token files added under `LiquidEditor/DesignSystem/Tokens/`:

- `LiquidMaterials.swift` — material styles keyed by role.
- `LiquidElevation.swift` — shadow tokens.
- `LiquidRadius.swift` — corner radius scale.
- `LiquidStroke.swift` — hairline + active stroke styles.

Existing token files (`LiquidColors`, `LiquidSpacing`, `LiquidTypography`) are extended, not replaced. Old values stay so existing views that don't get redesigned in this pass still compile. New views consume the new tokens.

### Canvas layers

| Token | Value | Usage |
|---|---|---|
| `canvas.base` | `#07070A` | App background behind chrome |
| `canvas.raised` | `#0F0F12` | Preview + timeline background |
| `canvas.chrome` | `.ultraThinMaterial` over canvas.base | Floating nav bars, toolbar, sheet headers |
| `canvas.float` | `.regularMaterial` + 14% white overlay | Sheets, popovers, tool chips |

### Text

| Token | Value | Usage |
|---|---|---|
| `text.primary` | `#F3EEE6` | Primary labels, titles, timecode |
| `text.secondary` | `#9C9A93` | Captions, inactive tabs |
| `text.tertiary` | `#5A5852` | Disabled, hints |
| `text.onAccent` | `#07070A` | Text on amber surfaces |

### Accent

| Token | Value | Usage |
|---|---|---|
| `accent.amber` | `#E6B340` | Active / selected (selected clip border, active tab icon, time chip fill, FAB, scrub indicator) |
| `accent.amber.glow` | `#E6B340` @ 37% alpha | Glow halos |
| `accent.destructive` | `#E5534A` | Delete confirmations only |

### Materials & elevation

- `.glassEffect()` applied to every floating surface (nav bar, toolbar, sheet header, tool panel, time chip, clip context menu, transport row background).
- Shadow tokens `float.sm` (4pt blur, 8% alpha), `float.md` (12pt, 14%), `float.lg` (24pt, 22%). Used sparingly — only where material alone is insufficient.

### Typography (San Francisco only)

| Token | Font / size / weight | Usage |
|---|---|---|
| `type.display` | SF Pro Rounded 28 semibold | Project name, sheet titles |
| `type.title` | SF Pro 17 semibold | Nav titles, primary labels |
| `type.body` | SF Pro 15 regular | Tool labels, menu items |
| `type.caption` | SF Pro 12 medium | Metadata, aspect chip |
| `type.mono` | SF Mono 13 medium | All timecodes (signature Edits cue) |
| `type.monoLarge` | SF Mono 18 semibold | Playhead time chip |

### Spacing (8 pt grid)

`xs` 4 / `sm` 8 / `md` 12 / `lg` 16 / `xl` 24 / `xxl` 32.
Minimum touch target 44 pt (iOS HIG). Toolbar tap targets 48 pt iPhone / 52 pt iPad.

### Corner radii

`radius.sm` 6 / `md` 10 / `lg` 16 / `xl` 22 / `full` 999.

### Strokes

- `stroke.hairline` — 0.5 pt, `white.opacity(0.08)`. Replaces current `0.1`-opacity dividers.
- `stroke.active` — 1.5 pt amber with 6 pt glow halo. Selected clips, focused text fields only.

---

## Section 2 — Editor shell layout & adaptivity

The editor shell has six vertical regions. Each uses the Section 1 materials so the whole chrome floats over a single dark canvas instead of reading as stacked gray boxes.

### Regions

**1. Nav bar** — 52 pt, `.glassEffect()` over canvas, pinned to top safe area.
- Left: `xmark` close · vertical divider · project name with chevron (tap opens settings dropdown).
- Right: `...` more · resolution chip (`2K`/`4K` capsule with amber outline) · **Export** primary CTA (amber capsule, 96 pt wide).
- iPad: horizontal spacer absorbs extra width; project name centers with more breathing room.

**2. Preview area** — fills available height.
- Video rendered `.aspectRatio(.fit)`, subtle letterbox bars (`canvas.base`) when aspect differs.
- Top-left: aspect chip (`9:16`, `16:9` …) — 11 pt mono in a glass capsule.
- Top-right: comparison-mode toggle + fullscreen button, glass capsules. Auto-hide after 2 s while playing.
- Empty-project CTA: centered glass card, `film.stack` glyph 48 pt amber → "This project has no media" → PrimaryCTA.
- iPad: preview gets more height, overlays scale up, letterbox bars wider.

**3. Playback controls row** — 56 pt iPhone / 64 pt iPad, `.glassEffect()`.
- Layout: `[undo] [redo]    [skip-back] [play/pause 56 pt amber fill] [skip-forward]    [time display mono]`.
- Play/pause is the focal element: amber filled circle, `pause.fill` / `play.fill`. Tap springs scale to 0.94, haptic `.medium`.
- Time display uses `type.monoLarge`.
- iPad: extra padding, adds a small keyframe diamond button between skip-back and play when the clip has keyframes.

**4. Timeline / inline tool panel** — `.glassEffect()` card floating on canvas, 180 pt iPhone / 240 pt iPad.
- Timeline: ruler at top (14 pt, mono tick labels), track lanes below (56 pt / 72 pt per lane), playhead is a 2 pt amber line with a top-mounted time chip (solid amber fill, `text.onAccent` mono, floats with the line).
- Selected clip: 1.5 pt amber stroke + 6 pt glow, trim handles are 32×64 pt rounded amber tabs on each edge.
- Inline tool panel (shown when a tool tab is active): replaces timeline with horizontally-scrolling category chips → vertical slider rows. Same height so layout doesn't jump.

**5. Bottom toolbar** — `.glassEffect()`, two rows.
- Top row: horizontally-scrolling tool buttons (48×72 pt iPhone / 52×80 pt iPad). Vertical `[glyph, caption]` in a rounded-12 capsule.
- Bottom row: 5 icon-only tabs (Edit / FX / Overlay / Audio / Smart). Active tab: amber glyph + 4 pt pill indicator beneath.
- Rows separated by `stroke.hairline`.
- iPad: same two-row structure, tool buttons breathe wider.

**6. Safe-area + home indicator padding** — all regions respect safe-area insets.
- iPad: shell centers with `max-width: min(canvasWidth, 1180pt)` for nav + toolbar only; timeline stretches full canvas width.

### Adaptivity rules

- Single view hierarchy — no `@Environment(\.horizontalSizeClass)` branching for structure. Sizes and spacing adapt.
- `GeometryReader` at EditorView root computes a `formFactor: .compact | .regular` flag that drives font scale, tap targets, lane heights. Kept as a local derived value.
- Timeline zoom default: iPad starts at 2× iPhone's pixels-per-second so a typical 30 s clip shows full width without scrolling.
- Sheets: iPhone `.sheet` with `.medium` / `.large` detents; iPad `.sheet` with `.formSheet` detent — same content, SwiftUI handles presentation.

---

## Section 3 — Component library

New folder `LiquidEditor/DesignSystem/Components/`. Each component is a single SwiftUI `View` struct consumed by the editor and every follow-up sub-project.

### Atoms

**`GlassPill`** — base floating chip/capsule. `Capsule().fill(<material>).overlay(Capsule().stroke(stroke.hairline))`, optional amber active stroke. Slots: `leading`, `label`, `trailing`. Heights: 28 sm / 36 md / 44 lg. Used by resolution chip, aspect chip, time chip, rate chip, inline selection pills.

**`TransportButton`** — play/pause-style circle, filled or unfilled. Sizes: 40 (secondary) / 56 (primary). Press: `scaleEffect(0.94)` + `motion.snap` + haptic `.medium`. Active = amber fill + `text.onAccent` glyph.

**`ToolButton`** — two-row toolbar cell. Vertical `[glyph 22 pt, spacer 4, caption 11 pt]` in 48×72 iPhone / 52×80 iPad. States: inactive (`text.secondary`), hover (+4% white bg), active (amber glyph + caption).

**`TabBarItem`** — bottom tab cell. 24 pt icon, 4 pt amber pill beneath when active (grows via `motion.bounce`). `.selectionChanged()` haptic.

**`PrimaryCTA`** — amber capsule button for major actions. 44 pt iPhone / 48 pt iPad, min-width 96, `type.title`, amber fill, `text.onAccent`. Disabled at 40% alpha.

**`IconButton`** — bare 20 pt glyph in a 44×44 tappable rectangle. `text.primary`.

### Composites

**`ClipCard`** — timeline clip. Rounded-10 container, background gradient per clip type (video: dark purple, audio: green, text: pink, sticker: yellow, image: teal), thumbnail strip / waveform / preview glyph layer, 2 pt type-color tint band at the top edge. Height: 56 iPhone / 72 iPad. Selected = `stroke.active`. Trim handles: 32×64 pt amber tabs with 3 grip lines (visible only when selected).

**`PlayheadWithChip`** — 2 pt amber vertical line + top-anchored `GlassPill` with amber fill and `type.monoLarge` time in `text.onAccent`. Both move as one. On scrub: chip scales 1.08 with soft outer glow.

**`SheetHeader`** — 56 pt, `.glassEffect()`. `[IconButton xmark]  [title centered]  [Apply PrimaryCTA or spacer]`. 0.5 pt hairline divider below.

**`EmptyStateCard`** — centered floating card. Rounded-16 `.regularMaterial`, 24 pt padding, max-width 320. `[glyph 48 pt amber, title, body text.secondary, PrimaryCTA]`.

**`ToolPanelRow`** — 52 pt. `[label, spacer, value type.mono text.secondary]` + control (slider / segmented / stepper). Slider track 4 pt `stroke.hairline`, amber fill to value, 24 pt amber thumb with `float.sm`.

### Feedback

**`BrandLoader`** — 36 pt amber `film.stack.fill` glyph (SF Symbol, hierarchical rendering), 2-phase opacity pulse 0.5 → 1.0 over 1.4 s `.easeInOut`. No rotation. Optional caption below in `type.caption` + `text.secondary`. Replaces every current `ProgressView()` inside the editor shell.

**`ErrorChip`** — inline error. `GlassPill` + `exclamationmark.triangle.fill` in `accent.destructive` + `type.caption` message. Slide-down spring entry, auto-dismiss in 4 s.

**`Toast`** — ephemeral notification. `.glassEffect()` capsule at top safe area, slides down, auto-dismiss 2 s. `.notification(.success)` haptic.

### iPad adjustments (all components)

- +4 pt vertical padding.
- Font sizes scale ~5% via the token Dynamic Type integration.
- Tap targets per Section 2 (48 → 52 etc.).

---

## Section 4 — Motion & haptics

Subtle, fast, springy. Most interactions < 180 ms; nothing > 300 ms. Every discrete action triggers a haptic.

### Spring tokens

| Token | Stiffness | Damping | Use |
|---|---|---|---|
| `motion.snap` | 500 | 24 | button tap, haptic-coupled flips |
| `motion.smooth` | 300 | 26 | panel swap, sheet present/dismiss |
| `motion.bounce` | 220 | 18 | tab pill indicator, selection ring appearance |
| `motion.glide` | 180 | 30 | timeline zoom, scroll snap-to-edge |
| `motion.ease.out` | `.easeOut(0.18)` | — | opacity fades, shimmer, auto-hide |

No linear, no default SwiftUI curves — always a token.

### Choreography

- **Button tap** — press: `scaleEffect(0.94)` + `motion.snap` + haptic `tapSecondary` (or `tapPrimary` for primary CTAs). Release: spring back. If release changes state: additionally fire `selection`.
- **Sheet present/dismiss** — slide up + material crossfade + 1.02 → 1.0 header scale in `motion.smooth` (~280 ms). Arrival haptic `.notification(.success)` lite. Dismiss mirror without haptic.
- **Tab switch** — pill slides + grows with `motion.bounce`. Haptic `.selection`.
- **Scrub** — playhead follows finger 1:1 (no spring). Start: `.light`. Release: `.rigid`. Time chip scales 1.0 → 1.08 during scrub.
- **Clip drag** — long-press pickup: `.impact(.medium)` + scale 1.03 + extra `float.md` shadow. Move with 40 ms `motion.glide` lag (weighted feel). Drop: `motion.bounce` settle + `.light`.
- **Trim handle** — finger-direct translation. Start: `.impact(.soft)`. Snap hit: `.selection`. Release: `.rigid` + composition rebuild (existing).
- **Pinch zoom** — direct during pinch. On release out-of-limits: elastic bounce-back `motion.glide`.
- **Selection ring** — stroke + glow fade + scale 1.05 → 1.0 via `motion.bounce`, 160 ms. Haptic `.selection`.
- **Tool tab swap** — old slides out left, new slides in from right, `motion.smooth` ~220 ms. Haptic `.selection`.
- **Empty → populated** — CTA scales 1.0 → 0.9 to empty, BrandLoader pulses, new clip flies in from canvas bottom into timeline with `motion.bounce`. Haptic `.notification(.success)` on completion.
- **Focused text field** — 1.5 pt stroke fades to amber over 120 ms + 1 pt `float.sm` lift.

### Haptic map

Routed through `HapticService.shared.play(.<kind>)` via new `HapticKind` enum. Enum cases use Swift-legal camelCase identifiers:

| Kind | UIKit generator | When |
|---|---|---|
| `tapPrimary` | `.impact(.medium)` | play/pause, export, primary CTA |
| `tapSecondary` | `.impact(.light)` | undo/redo/skip, IconButton |
| `selection` | `.selectionChanged()` | tab, tool chip, selection ring, snap |
| `pickup` | `.impact(.medium)` | clip long-press, drag start |
| `drop` | `.impact(.light)` | drag release, trim release |
| `boundary` | `.impact(.rigid)` | scrub release, zoom limit, trim release |
| `success` | `.notification(.success)` | sheet arrival, import/export complete |
| `warning` | `.notification(.warning)` | destructive confirmation |
| `error` | `.notification(.error)` | inline error, export failure |

### Accessibility — Reduce Motion

- All springs collapse to `motion.ease.out` or instant cross-fade. No scale, no slide.
- Haptics unchanged (users disable separately via Settings).
- `BrandLoader` pulse disabled; static amber glyph with `accessibilityLabel("Loading")`.
- Gated via `@Environment(\.accessibilityReduceMotion)` read once at EditorView root, passed down.

### Performance guardrails

- 60 FPS on iPad 12.9" M2 during concurrent scrub + rebuild (the gesture-gated rebuild wired in the previous session keeps this achievable).
- Haptics throttled — same kind cannot fire more than 1× per 40 ms (prevents scrub-spam).
- Spring `Animation` values are static constants — no allocation during interaction.

---

## Implementation note: phased rollout

This spec's sub-project #1 + #2 — adding tokens + redesigning the editor shell — is a single implementation cycle. Sub-projects #3–#6 will consume these tokens and components without further token work.

Existing views that aren't in this sub-project's scope keep their current styling. They will compile because the old tokens remain. They look inconsistent until their own sub-project lands — an accepted cost of phasing.

---

## Success criteria

- New token files exist, are referenced by the editor shell, and have no `// TODO` placeholders.
- EditorView, VideoPreviewView, PlaybackControlsView, EditorToolbar, PlayheadView all consume the new components and tokens.
- All discrete interactions in the editor shell trigger a haptic via `HapticService.shared.play(.<kind>)`.
- Reduce Motion path verified by running the app with Settings → Accessibility → Motion → Reduce Motion enabled.
- Visual check on iPhone 17 Pro Max simulator and physical iPad Pro 12.9"; layout adapts per Section 2 rules.
- `xcodegen generate` + `xcodebuild build` + `xcodebuild test` all green, no new warnings.

---

## Explicit non-goals (this spec)

- Redesign of timeline surface (clips, ruler, track lanes internals) — that's sub-project #3.
- Redesign of any sheet other than their shared `SheetHeader` component — sheet bodies are sub-projects #4 / #5.
- Redesign of ProjectLibrary, Settings, Onboarding — sub-project #6.
- Changing any playback / composition logic.
- Adding new features (this is a visual refresh, no new capability).
