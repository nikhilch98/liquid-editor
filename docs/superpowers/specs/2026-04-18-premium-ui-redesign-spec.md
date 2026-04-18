# Premium UI Redesign — Full Screen & Component Spec

**Date:** 2026-04-18
**Status:** Approved (visual direction); pending design-blocking resolutions in §12
**North star:** Instagram Edits × CapCut — dense, pro-feeling, dark canvas, amber accent, glass surfaces
**Direction locked:** Option A — **Timeline-Dominant on iPhone / Pro-Workstation on iPad**
**Mockups:** `.superpowers/brainstorm/41597-1776514658/content/*.html`

---

## 1. Purpose & Scope

Redesign LiquidEditor’s three primary screens (Editor / Project Library / Export) and all contextual sub-surfaces (tab drill-downs, deep tools, creative panels, supporting flows) in one coherent visual language. The spec is the source of truth for the implementation plan that follows.

**In scope:** visual layout, component structure, interaction model, iPhone + iPad adaptation, design-token usage, state models, accessibility, haptics, keyboard shortcuts, gestures, orientation & color-mode policy.

**Out of scope:** feature work beyond what the mockups imply, performance budgets (cross-referenced, not redefined), Metal compositor changes, persistent-timeline data-structure changes.

---

## 2. Shared Design Language

### 2.1 Color tokens

| Role | Token | Value | Status |
|---|---|---|---|
| App background | `LiquidColors.Canvas.base` | #07070A | existing |
| Raised surface | `LiquidColors.Canvas.raised` | #0F0F12 | existing |
| Elevated cell | `LiquidColors.Canvas.elev` | #1A1A1F | **NEW** |
| Primary text | `LiquidColors.Text.primary` | #F3EEE6 | existing |
| Secondary text | `LiquidColors.Text.secondary` | #9C9A93 | existing |
| Tertiary text | `LiquidColors.Text.tertiary` | #5A5852 | existing |
| Accent / CTA / in-progress | `LiquidColors.Accent.amber` | #E6B340 | existing |
| Accent glow | `LiquidColors.Accent.amberGlow` | 37% α | verify |
| Destructive-of-data | `LiquidColors.Accent.destructive` | #E5534A | verify |
| Success | `LiquidColors.Accent.success` | #6BCB77 | **add if missing** |
| Warning | `LiquidColors.Accent.warning` | #E5A14A | **add if missing** |
| Stroke hairline | — | rgba(255,255,255,0.06) | derive |
| Stroke prominent | — | rgba(255,255,255,0.12) | derive |

Clip colors use existing `LiquidColors.Timeline.video`, `.audio`, `.text`, `.sticker`, `.transition`. Verify all tokens against `LiquidColors.swift` before implementation; **add any missing before first view is built**.

### 2.2 Amber vs. destructive rule (resolves contradiction from v1)

- **Amber** = accent, CTA, active state, in-progress indicator, *cancel/stop a running process*. No data is lost by cancelling.
- **Destructive red** = *destroys user data* (delete clip, delete project, clear captions, reset grade).

Examples:
- Export cancel mid-render → amber (no data lost).
- Tracking **Stop** → amber.
- VO **Stop recording** → amber (recording is kept by default, see §9.2 state model).
- **Delete clip**, **Delete project**, **Discard recording** → red + confirmation dialog.

### 2.3 Motion tokens

- Sub-panel slide-up: `LiquidMotion.smooth`.
- Chip / tool selection: `LiquidMotion.snap`.
- Keyframe scrub, timeline zoom: `LiquidMotion.glide`.
- Context menu reveal: `LiquidMotion.bounce`.
- All spring animations fall back to `LiquidMotion.reduced` under **Reduce Motion**.
- **Reduce Transparency** fallback: replace `.ultraThinMaterial` / glass surfaces with `Canvas.raised` opaque fills.
- **Increase Contrast:** stroke hairline → `Text.tertiary`, stroke prominent → `Text.secondary`.

### 2.4 Haptics table

| Action | Haptic |
|---|---|
| Tab switch | `UISelectionFeedbackGenerator.selectionChanged()` |
| Tool / chip tap | `UIImpactFeedbackGenerator(.light)` |
| Split at playhead | `UIImpactFeedbackGenerator(.medium)` |
| Keyframe add / remove | `UIImpactFeedbackGenerator(.light)` |
| Snap acquisition on timeline | `UISelectionFeedbackGenerator.selectionChanged()` |
| Beat-marker crossed during scrub | `UISelectionFeedbackGenerator.selectionChanged()` |
| Track complete (success) | `UINotificationFeedbackGenerator(.success)` |
| Export complete | `UINotificationFeedbackGenerator(.success)` |
| Tracking failed / low-confidence | `UINotificationFeedbackGenerator(.warning)` |
| Destructive confirm | `UIImpactFeedbackGenerator(.medium)` |
| Delete executed | `UINotificationFeedbackGenerator(.warning)` |
| Recording armed (VO) | `UIImpactFeedbackGenerator(.heavy)` |

All haptics are guarded by a user-facing toggle in Settings → Accessibility.

### 2.5 Interaction conventions

- Active = 1px amber border + `rgba(230,179,64,0.10)` fill + amber label.
- Sub-panel appears between timeline and shelf; amber 1px border + downward caret + 8px drop shadow. Dismiss via ✕ or tap-tool-again.
- Long-press (≥0.45s) on clip / card / media cell → dim UI to ≈60% + float glass context menu.
- Drag-to-reorder after long-press lifts with shadow + scale 1.03; peer items shift.
- Double-tap preview → toggle zoom-fit / zoom-fill.
- **CTA terminology:** only “primary CTA.” Modifiers: **sticky** (pinned to bottom edge, survives scroll) or **inline** (in flow). “Footer CTA” is not used.

### 2.6 Form-factor rules

- **Compact** (iPhone, < 640pt): single-column; sub-panels slide up as bottom sheets above the shelf; modals use `.sheet` with medium detent by default.
- **Regular** (iPad ≥ 640pt): sub-panels live in the right-rail `InspectorPanel` (persistent, non-modal); modals use `.sheet` with custom-size detent so the timeline stays visible.

### 2.7 Orientation policy

- **iPhone:** portrait primary. Landscape supported for the **Editor screen only** (see §3.2). Project Library and Export are portrait-locked. Orientation lock is per-screen.
- **iPad:** landscape primary. Portrait supported; media-browser rail collapses into a drawer triggered by left-edge swipe.

### 2.8 Color mode

Dark only in v1. App sets `.preferredColorScheme(.dark)` at root. Light Mode is deferred to a future spec; token system is dark-locked.

---

## 3. Screen 1 — Editor

### 3.1 iPhone portrait (top to bottom)

1. **Chrome bar** — ✕ │ Project chip (name ▾) │ ⚙ │ sticky primary CTA **Export**.
2. **Preview** — flex 32%; 2K·60 pill top-right; time/dot chip bottom-left. Double-tap zoom; pinch 1×–5× + pan.
3. **Transport row** — undo │ redo │ amber Play (22pt, glow) │ timecode │ fullscreen.
4. **Timeline** — flex-grow; 3 tracks default (V1 │ V2 overlay │ A1). Gestures in §10.3; audio waveform in §10.8.
5. **Contextual sub-panel** — when active tool needs parameters.
6. **Tool shelf** — 5-button tool strip + 5 tabs.

### 3.2 iPhone landscape (Editor only)

- Top-left 58%: preview.
- Top-right 42%: `InspectorPanel` (§10.2).
- Bottom full-width: timeline (4 tracks).
- Left edge: vertical tool rail (6 icons).
- No bottom tab bar; tab switching via a top-left popover.
- Returning to portrait restores the last selected tab + tool.
- **Ship in v1?** See §12.6.

### 3.3 iPad landscape

1. **Top toolbar** — ✕ │ Project chip │ undo/redo │ (flex) │ ⚙ │ fullscreen │ amber **Export**.
2. **3-panel row** (flex 45%): Media browser (left 90pt) │ Preview (center) │ `InspectorPanel` (right 120pt).
3. **Transport bar** — floating glass panel.
4. **Timeline + tool rail** (flex 55%): 4-track timeline + vertical tool rail (36pt) with 6 tools (§10.4).

### 3.4 Editor screen states

| State | Visual |
|---|---|
| Empty project | Black preview + “Tap to import” ghost; dashed drop zone on tracks (see §9.6). |
| Importing media | Transient amber progress chip on clip tile while thumbnail decodes. |
| Analyzing (track/stabilize/beat) | Top-of-preview status pill “Tracking 42%” with pulsing dot. |
| Rendering (reverse/freeze/ramp bake) | Amber progress bar along clip tile bottom + lock icon; tap to cancel. |
| Playback | Amber Play → Pause glyph; playhead glides. |
| Error (missing / decode fail) | Red-striped clip + ⚠︎ + tap-to-relink row in Inspector. |

---

## 4. Screen 2 — Project Library

### 4.1 iPhone

- Header: logo “liquid.” │ search icon │ avatar.
- Search/filter row; search toggles an inline text field.
- **Recent rail** — horizontal scroll of thumbnail-only cards with duration chip.
- **All projects** — 2-col grid of project cards.
- FAB amber “+” above tab bar.
- Bottom tabs: Projects │ Templates │ Drafts │ You.

### 4.2 iPad

- Left sidebar (120pt): Library sections with counts, Collections, Templates, Trash.
- Top bar: logo + search + grid/list + amber **+ New Project**.
- Main grid: 4-col cards.
- Sort segmented: Recent / Name / Size.

### 4.3 Project card states

| State | Visual |
|---|---|
| Thumbnail loading | Skeleton + shimmer (§9.11). |
| Thumbnail failed | Tertiary placeholder “Preview unavailable” + retry glyph. |
| Cloud only (not downloaded) | Cloud glyph badge; tap → download with progress ring overlay. |
| Uploading | Progress ring + “Uploading…” subtitle. |
| Conflict (cloud newer) | Amber “Conflict” badge; tap opens merge sheet. |
| Locked / template | Small lock glyph bottom-left. |

### 4.4 Project-card context menu

1. Open
2. Rename
3. Duplicate
4. Share…
5. Move to collection…
6. Export…
7. (divider)
8. **Delete** (red + confirmation)

iPad keyboard shortcuts: Open ⏎, Rename F2, Duplicate ⌘D, Delete ⌦.

---

## 5. Screen 3 — Export

### 5.1 Signature ring

Existing `GradientProgressBorderView` (pink → red → orange → yellow conic) is preserved and surrounds the export-preview thumbnail.

### 5.2 iPhone layout

1. Chrome: back │ “Export” title │ ⚙.
2. Ring-bordered preview (90×140) with label inside.
3. Preset segmented: Quick / Social / Pro / Custom.
4. Steppers: Resolution / FPS / Quality.
5. Toggles: HDR / Audio-only.
6. Sticky primary CTA **Export · ~38 MB**.

### 5.3 iPad layout

- Left 220pt: ring preview + live meta card.
- Right flex: presets + Video group + Advanced + Destination grid.
- Full-width sticky primary CTA.

### 5.4 Export state model

| State | Ring | Inside ring | Controls | CTA |
|---|---|---|---|---|
| Idle | full gradient, static | “2K · 1080×1920 · 60 fps” | enabled | amber **Export** |
| Exporting | arc grows 0→100% clockwise; unfilled is tertiary stroke | large **%**; sub: ETA or frame n/N | disabled + dimmed | amber **Cancel** (not destructive, §2.2) |
| Success | full gradient, pulses once | checkmark + “Done · 00:45 · 38.4 MB” | re-enabled | amber **Share** + tertiary **Export again** |
| Error | full gradient, dimmed | red ⚠︎ + 1-line message | enabled | amber **Retry** + tertiary **Copy log** |
| Cancelled | full gradient | “Cancelled” | enabled | amber **Export** |

On Success: bottom sheet (medium detent) with thumbnail + share link + Save-to-Photos + Export-again. Dismiss returns to idle.

### 5.5 Export queue

Multiple exports allowed. While one runs, tapping Export on another queues it; a floating glass pill (“2 exporting”) lives in the Library and opens a queue sheet. Per-item cancel.

---

## 6. Editor Tab Drill-Downs

### 6.1 Edit tab

| Tool | Panel | Controls |
|---|---|---|
| Split | no | Cuts at playhead. |
| Trim | full mode (§7.3) | — |
| Speed | yes | Presets (0.25×/0.5×/1×/2×/Curve…), rate slider, preserve-pitch. |
| Volume | yes | dB, fade, Mute/Duck/Denoise. |
| Duplicate / Copy / Delete | no | Immediate (Delete confirms per §2.2). |
| Reverse / Freeze frame | progress | Amber bar on clip; tap-to-cancel. |
| Replace | full mode | Opens Media Picker (§9.1). |
| Keyframes | inline (§7.2) | — |
| Animation | yes | Preset chips (§8.1.3 list). |
| Mask | full mode (§7.5) | — |

### 6.2 Audio tab

Music │ SFX │ Record (→ §9.2) │ Extract │ Volume │ **Beat detect** (§7.6) │ EQ │ Pitch │ **Auto-mix** (§7.7).

### 6.3 Text tab

Text (→ §8.1) │ Captions (→ §9.3) │ Sticker │ Preset │ Font / Size / Color / Stroke / Shadow / Background / Animation / Align.

### 6.4 FX tab

Filter │ Transition (→ §8.2) │ Effect (→ §8.3) │ **Stabilize** (§7.8) │ **Chroma key** (§7.9) │ Mask │ Tracking (§7.4) │ Mirror │ Freeze │ Cutout.

### 6.5 Color tab

Preset │ LUT (→ §8.4) │ Wheels (→ §8.5) │ **Curves** (§8.6) │ Temp / Tint / Exposure / Contrast / Highlights / Shadows / Saturation / Vibrance │ **HSL** (§8.7) │ **Scopes** (§8.8).

---

## 7. Deep Tool UIs

### 7.1 Speed Ramp (bottom-sheet modal)

- **Detent:** medium (iPhone), custom 60% (iPad).
- Grabber + Cancel / Done; preset chips; draggable curve canvas (x=time, y=speed 0.1×–10× log); frame thumb strip (keyframe thumbs amber-outlined); preserve-pitch toggle.

### 7.2 Keyframes (inline panel)

- Replaces sub-panel. Lanes: Scale / Position / Opacity / Rotation.
- Markers: amber diamond (linear), amber circle (held), white (current).
- Toolbar: + Key (amber primary) / − Key / prev-next / ease picker (step/ease/linear).
- Selecting a lane swaps timeline view to show the lane under the clip.

### 7.3 Trim Precision (full mode)

- Zoomed frame strip (6 thumbs) + amber L/R handles; duration center-labeled.
- IN-trim / OUT-trim rows with ±1 frame, ±1 second shuttle.
- Ripple edit / Snap to playhead / Snap to beat markers toggles.
- **Pro edit modes** (iPad + landscape iPhone only): Roll / Slip / Slide segmented below shuttles.

### 7.4 Motion Tracking (full mode)

- HUD: amber “Tracking N%” with pulsing dot + “14/34 frames” chip.
- Overlay: amber bbox + 4 corner dots + crosshair + confidence label + motion trail.
- Keyframe bar: tracked-frame dots + white current marker.
- Controls: track-type chips (Point / Object / Face / Body / Hand), Smoothing, Scale-match, Rotation-match.
- Actions: **Stop** (amber) / Reset / ⋯ overflow.

#### 7.4.1 State model

| State | HUD | Controls | Primary |
|---|---|---|---|
| Idle | “Ready” | enabled | amber **Analyze** |
| Analyzing | pulsing “Tracking %” | type locked, sliders locked | amber **Stop** |
| Complete | green “Done · strong” | enabled | amber **Apply** |
| Failed (low conf.) | red “Weak track” | enabled | amber **Retry** + tertiary **Edit manually** |
| Cancelled | “Cancelled” | enabled | amber **Analyze** |

### 7.5 Mask Editor (full mode)

- Preview darkened except inside mask (radial cutout).
- Dashed amber shape + 4 cardinal handles + dotted feather ring.
- Shape picker: Rect / Ellipse / Rounded / Star / Freehand (Apple Pencil).
- Sliders: Feather / Opacity / Expand-Contract.
- Chips: Invert / Animate / **Track to subject** (links to §7.4).

### 7.6 Beat Detect

- Entry: Audio tab → Beat detect. Runs analysis on selected audio clip (progress chip on clip edge).
- Result: **beat markers** on a dedicated “Markers” row above V1. Visual: amber triangle ▽ pointing down at each beat.
- Distinct from user **chapter markers** (blue flag ⊞ pointing right, added manually).
- Tap → seek; long-press → menu (Delete / Convert to chapter / Nudge ±1 frame).
- Post-analysis sub-panel: BPM readout + “Snap edits to beats” toggle + red **Remove markers**.

### 7.7 Auto-Mix

- Single-tap (Audio tab → Auto-mix). Runs in background: ducks music under detected dialog.
- Default: -12 dB duck, 0.3s attack/release.
- Post-run: toast “Mixed 3 dialog segments” + amber **Undo** chip.
- Advanced (iPad ⋯): duck / attack / release sliders.

### 7.8 Stabilize

- FX tab → Stabilize. Sub-panel: **Analyze** or **Re-analyze** button.
- Analysis progress on clip edge.
- Post-completion: Strength slider (0–100%), Method chips (Cinema / Handheld / Fast), Crop-to-hide-borders toggle.
- Preview: before/after split line with chips.

### 7.9 Chroma Key

- FX tab → Chroma key. Full mode; eyedropper cursor on preview.
- Tap-to-pick; swatch chip shows picked color.
- Sliders: Tolerance / Softness / Spill suppression / Edge thin.
- Toggles: Show alpha matte / Show holdout / Fill behind (color-picker if on).
- Action: **Refine…** opens Mask editor (§7.5) in refine mode.

---

## 8. Creative Panels

### 8.1 Text Editor (full mode on iPhone; inspector-embedded on iPad)

- Dashed amber bbox with 6 resize + 1 rotation handle (14pt above).
- Sub-tabs: Text / Effects / Animation / Align.

#### 8.1.1 Text tab — input card + 5-font pills + size slider.

#### 8.1.2 Effects tab — 4-cell style grid (plain / stroke / shadow / filled) + 7 color swatches (first opens full picker).

#### 8.1.3 Animation tab presets

| In | Out | Loop |
|---|---|---|
| Typewriter | Fade | Pulse |
| Fade | Slide-out | Shake |
| Pop | Zoom-out | Rotate |
| Slide-in | Blur-out | Wave |
| Zoom-in | — | Rainbow |
| Bounce | — | — |

Each preset animates its own chip on tap.

#### 8.1.4 Align tab — H (L/C/R) + V (T/M/B) + distribute (X/Y center) + numeric margin.

### 8.2 Transition Picker

- Two-clip stage + badge; Duration slider (seconds + frames); 5 categories; 4×2 thumb grid; Apply-to-all-cuts toggle.

### 8.3 FX Browser

- Applied-stack surface (name + intensity + ✕); 5 categories; 3×3 live-preview grid; intensity slider when active.

### 8.4 LUT Grid

- Split preview with Before/After chips + amber divider for Split mode.
- Compare: A / B / Split segmented.
- **Import .cube** link (v1/v2 per §12.2).
- 4 categories, 3×3 labeled LUT cards, checkmark on active, intensity slider.

### 8.5 Color Wheels (3-way)

- Mini waveform strip; 3 wheels (Lift / Gamma / Gain) with puck + luma slider + numeric; Temp (blue→amber) + Tint (green→red) + Saturation.

### 8.6 Curves

- Canvas 240×240 (iPhone) / 360×360 (iPad).
- Channel segmented: Luma / R / G / B.
- Tap to add a control point; drag; double-tap to remove.
- Preset chips: Linear / S-curve / Inverse / Crush / Film.
- Reset-channel + Reset-all links.
- On-canvas mini histogram (per selected channel) in tertiary color.

### 8.7 HSL

- 8 color-channel chips (Red / Orange / Yellow / Green / Aqua / Blue / Purple / Magenta).
- For active channel: Hue, Saturation, Luminance gradient-track sliders.
- “Pick” eyedropper → tap preview to auto-select a channel.
- Reset-channel link per-channel.

### 8.8 Scopes (iPad default-on)

- Tab segment: **Waveform** / **Histogram** / **Vectorscope** / **RGB Parade**.
- Sampled at 30 Hz from `ColorGradingPipeline` taps; falls back to 15 Hz under thermal pressure.
- iPad: docks above `InspectorPanel`; can be undocked to a floating glass window (drag by title).
- iPhone: opt-in via overflow; occupies preview overlay when enabled.

---

## 9. Supporting Flows

### 9.1 Media Picker

- Source tabs: Photos / Videos / Files / Cloud.
- Smart filters: Today / ≤10s / 4K / HDR.
- Album dropdown + count; 3-col grid with numbered amber selection pills; 4K/HDR badges; duration chips.
- Sticky primary CTA **Add to project** with count.
- States: Loading (skeleton grid), Empty (“No photos here” + source switch), Permission denied (grant row, §9.13).

### 9.2 Voice-over Modal

- Ring preview + live waveform card + 10-cell peak meter; big red circular record button; mini timeline with red write-position.
- Actions: Cancel / Punch-in / Save.

#### 9.2.1 State model

| State | Record btn | Waveform | Actions |
|---|---|---|---|
| Idle | red, static | empty | Save disabled |
| Armed | amber 3-2-1 ring | empty | Cancel |
| Recording | red pulsing | live bars + meter | amber **Stop** |
| Review | red outlined | scrubbable | Re-record (red, confirm) / Punch-in / **Save** |
| Saving | disabled | shimmer | — |
| Saved | — | — | auto-dismiss + toast “Voice-over added” with Undo |

#### 9.2.2 Punch-in — overwrites only selected range; playback starts 1s before range; auto-stops at range end.

### 9.3 Auto-Captions Review

- Preview with word-pop (highlighted amber pill, others translucent black).
- 4 templates: Word-pop / Line / Bar / Minimal.
- Segment list with timecode + text; active segment amber left-border; low-confidence STT segments are red.
- Per-segment: Edit / Split / Merge / Delete. Sticky primary CTA **Apply all**.

#### 9.3.1 State model

| State | UI |
|---|---|
| Not generated | CTA “Generate captions” + language picker + “Include filler words” toggle |
| Generating | Shimmer + chip “Transcribing 42%” |
| Ready | Reviewable list |
| Applied | Caption track on timeline (amber text variant) |
| Failed | Red banner “Transcription failed—tap to retry” |

### 9.4 Context Menu

- Long-press → dim + floating glass menu at touch point. Groups: primary, secondary, destructive — hairline divided.
- iPad shows keyboard shortcuts right-aligned.
- Clips (§6.1), project cards (§4.4), media-picker cells (subset: Preview / Add / Info).

### 9.5 Project Settings Sheet

- Header card: thumbnail (edit badge) + inline rename + created date + clip count + duration.
- Sections: Canvas / Color / Audio / Snapshots & History / Duplicate / **Delete** (red).

### 9.6 Empty States

Template: hero illustration + title + subtitle + optional primary CTA + escape-hatch link.
- Library empty, Timeline empty, Search no-results, Media picker empty (“No photos here” + link to change source), Export destinations empty (“Add a cloud destination” link to Settings).

### 9.7 Import / Capture

- Entry: Library FAB → sheet with tiles: Camera / Photos / Files / URL / AirDrop.
- **Camera mode:** full-screen viewfinder (SwiftUI `CameraCaptureView` over AVFoundation).
  - Mode switch: Video / Photo / Live Photo.
  - Controls: flash, front/back, ratio, exposure drag, zoom strip 0.5×/1×/2×.
  - Record: red circle, grows while held; tap-to-snap in photo mode.
  - Post-capture: thumbnail + **Use** (amber) / **Retake** / **Save + continue**.
- Files / URL → native picker → import progress toast.
- **Global import progress:** bottom-pinned floating glass pill “Importing 3 • 72%”; tap expands a per-item sheet with cancel.

### 9.8 Undo History Scrubber

- Entry: Project Settings → **Snapshots · History**.
- Full-screen (iPhone) / large detent (iPad).
- Top: horizontal timeline of snapshots (diamond marker + thumbnail + label + timestamp).
- Middle: non-interactive preview of that state.
- Bottom: primary amber **Restore to this state** + tertiary **Branch from here**.
- Restore = destructive (loses newer edits) → confirmation.
- Backed by `PersistentTimeline` undo-tree; UI surfaces up to 200 snapshots with aged thinning (§12.4).

### 9.9 Toast / Snackbar

- Bottom-pinned floating glass pill; slide-up + fade-in with smooth motion.
- Auto-dismiss 4s; **with Undo**: amber chip, 8s; swipe-down dismisses early.
- Error toast: red left border + Retry action.
- Max 2 visible; older toasts slide away.
- Implemented as `ToastHost` view modifier at app root.

### 9.10 Confirmation Dialog

- Native `.confirmationDialog(...)` for Delete clip / Delete project / Clear captions / Reset grade / Discard recording.
- Title one sentence explaining consequence.
- Red destructive action + neutral Cancel.
- iPad: anchor to source element; iPhone: bottom sheet.
- Never use for reversible actions — always Toast + Undo instead.

### 9.11 Loading Skeletons

- Placeholder with shimmer (amber-tertiary → amber-secondary gradient sweep, 1.2s cycle).
- Applied to: project-card thumbnail, media-picker grid, auto-captions list, scopes warm-up.
- Reduce Motion: static tertiary fill.
- `SkeletonModifier` view modifier.

### 9.12 Onboarding / First-Run

- Single full-screen sheet on first launch. 3 swipeable pages with 3-dot indicator:
  1. Hero mark + “Liquid. Cut like a pro.” + amber **Get started**.
  2. Photos-permission primer + amber **Grant access** (native prompt).
  3. Microphone-permission primer (optional; deferrable) + amber **Continue**.
- Skippable via “Skip” top-right.
- Re-entry: Settings → About → “Show welcome tour”.
- No in-app tooltip tours; contextual help lives in empty states.

### 9.13 Permission Flows

- **Photos:** primer if unknown; “Limited Photos” row with “Expand access” link if limited.
- **Microphone:** primer on VO entry; deep-link to Settings if previously denied.
- **Camera:** primer on Camera-mode entry.
- **Notifications:** lazy-request after first successful export; toast “We can notify when exports finish” with amber **Enable** chip.
- **Files:** native `UIDocumentPicker` — no primer needed.
- Primer pattern: hero glyph + 2-sentence rationale + amber grant button + tertiary **Not now**.

---

## 10. Global Patterns

### 10.1 State inventory matrix

| Screen | Idle | Loading | In-progress | Success | Error | Empty |
|---|---|---|---|---|---|---|
| Editor | normal | transient clip chip | render / track / analyze bar on clip edge + HUD pill | transient green glyph on affected clip | red-striped clip + relink row | empty preview + dashed drop zone |
| Project Library | grid | skeleton cards | upload/download ring on card | toast + badge update | red toast + retry | hero illustration + CTA |
| Export | idle ring | — | animated arc + live % / ETA | pulse + success sheet | dim ring + red ⚠︎ + retry | disabled (“Add a clip to export”) |
| Media Picker | grid | skeleton grid | — | selection pills | permission-denied row | “No photos here” + source switch |
| Voice-over | idle | — | red pulsing + live waveform | saved toast | red banner + retry | — |
| Captions | not-generated CTA | shimmer list | “Transcribing %” | list populated | red banner retry | — |
| Tracking | ready | — | pulsing HUD + progress | green Done | red weak-track + retry/manual | — |

### 10.2 Inspector matrix (iPad right-rail)

Sections shown by selection type (● = shown, ○ = collapsed-by-default, blank = hidden):

| Section | Video clip | Text clip | Audio clip | Caption clip | Multi-select | No selection | Playhead only |
|---|---|---|---|---|---|---|---|
| Clip header (name, duration) | ● | ● | ● | ● | ● (N selected) | | |
| Transform (pos / scale / rot) | ● | ● | | | ○ | | |
| Speed | ● | | ● | | ○ | | |
| Volume | ● (if has audio) | | ● | | ○ | | |
| Opacity | ● | ● | | ● | ○ | | |
| Text content + style | | ● | | | | | |
| Caption style + language | | | | ● | | | |
| Color grade | ● | | | | ○ | | |
| Animation (keyframes) | ● | ● | | ● | ○ | | |
| Project meta (res, fps, duration) | | | | | | ● | ● |
| Playhead timecode + snap | | | | | | ○ | ● |
| Empty-state copy | | | | | | ● | |

Multi-select: only properties consistent across selection are editable; inconsistent values show em-dash + “Mixed” label.

### 10.3 Timeline gestures

| Gesture | Effect |
|---|---|
| Tap clip | Select; open Edit tab; populate Inspector. |
| Double-tap clip | Enter Trim Precision (§7.3). |
| Long-press clip | Context menu (§9.4). |
| Drag clip | After 0.45s long-press arm: lift shadow + scale 1.03; reorder; cross-track drop supported. |
| Drag clip edge | Trim in/out; snap-to-playhead & snap-to-beat emit selection haptic. |
| Pinch | Zoom timeline. Snap stops: 0.25s/frame, 0.5s/frame, 1s/frame, 2s/frame, 5s/frame, 10s/frame. |
| Two-finger pan | Scroll without zoom change. |
| Drag from media browser | Drop target highlights amber; drop creates clip at drop-time. |
| Swipe up on track | Collapse / expand track height. |
| Shift-tap (iPad + keyboard) | Add to selection. |
| Drag in empty track area | Lasso multi-select. |
| Tap playhead | Toggle scrub vs. seek cursor. |
| Drag playhead | Scrub with audio (toggle in Settings). |
| Tap beat marker | Seek. |
| Long-press beat marker | Menu (Delete / Convert to chapter / Nudge). |
| Ripple delete | Delete + close gap (toggle state controls whether gap closes). |

### 10.4 iPad tool rail (6 default tools)

Default order: Split / Trim / Speed / Mask / Keyframes / Tracking. User-customizable via long-press → “Edit rail…”. Persists per project.

### 10.5 Keyboard shortcuts (iPad)

| Shortcut | Action |
|---|---|
| Space | Play / Pause |
| J / K / L | Shuttle reverse / pause / forward (tap again = faster) |
| I / O | Mark in / Mark out |
| ⌘S | Split at playhead |
| ⌘C / ⌘V | Copy / Paste clip |
| ⌘D | Duplicate clip |
| ⌦ | Delete clip (confirm if lane breaks) |
| ⌘Z / ⌘⇧Z | Undo / Redo |
| ⌘+ / ⌘− | Zoom timeline in / out |
| M | Add marker at playhead |
| T | Trim to playhead (ripple) |
| F | Toggle fullscreen preview |
| ⌘E | Open Export |
| ⌘N | New project |
| ⌘F | Search (Library only) |
| Esc | Dismiss sub-panel / exit full mode |
| ← / → | Playhead ±1 frame |
| ⇧← / ⇧→ | Playhead ±1 second |
| ⇥ | Cycle tabs (Edit → Audio → Text → FX → Color) |

Exposed via `UIKeyCommand` in `KeyboardShortcutProvider`; discoverable via Hold-⌘ overlay.

### 10.6 Accessibility

- **VoiceOver labels:** every tool-strip button, chip, swatch, keyframe marker has `accessibilityLabel`. Example: keyframe diamond → “Keyframe at 00:03.12, scale 1.2×. Double-tap to select.”
- **VoiceOver rotor:** custom **“Clips”** rotor on the timeline; rotor items are clips in visual order; swipe down navigates clip-by-clip.
- **Dynamic Type:** chip rows and tool labels respect Dynamic Type up to XXL. At XXL+, chip rows wrap multi-row; tool-strip labels hide (icons only); long strings truncate with pointer-hover tooltip on iPad.
- **Reduce Motion:** springs → `.linear(0.12)`; shimmer skeletons → static fill.
- **Reduce Transparency:** `.ultraThinMaterial` → `Canvas.raised` opaque; glass context menu → opaque card + 1px stroke.
- **Increase Contrast:** strokes bumped per §2.3; tertiary text → secondary.
- **Bold Text:** system-font uses inherit `.fontWeight(.semibold)` minimum.
- **Switch Control / Voice Control:** every interactive element has stable `accessibilityIdentifier`; no multi-finger-only gestures without a single-tap alternative (Trim handle + pinch-zoom have “Accessibility actions” menu fallbacks).
- **AA contrast verification:** amber (#E6B340) on `Canvas.base` passes AAA large / AA small; all small-text cases verified; failing cases fall back to `Text.primary`.
- **Haptics toggle:** Settings → Accessibility exposes a master haptics toggle.
- **Apple Pencil:** supported for Freehand mask, Curves canvas, text handle manipulation.

### 10.7 Performance cross-references (see `docs/PERFORMANCE.md`)

- Project-card grid: virtualized (`LazyVGrid`); thumbnail decode off-main via detached `Task`; LRU 100.
- Media-picker grid: same pattern, LRU 200.
- Timeline scroll: tile-based rendering; clip waveforms pre-rendered to `CGImage` cached by (clipID, zoomBucket).
- Audio waveform (§10.8): 6 samples-per-point per zoom bucket; peak+RMS computed once on clip import and persisted.
- Export ring animation: `CADisplayLink` at 60 Hz; avoid SwiftUI `.animation` re-renders.
- Scopes: 30 Hz from `ColorGradingPipeline` taps; 15 Hz under thermal pressure.
- Budget adherence: scrub <2ms cached / <50ms uncached, frame-cache <300MB, composition rebuild <20ms (existing targets).

### 10.8 Audio waveform render spec

- Rendered directly on the audio-clip tile.
- Amber-accented peak line (opacity 0.9) + symmetric mirror below (opacity 0.4) against `Timeline.audio` gradient.
- Downsampling: bucket = `max(1, sampleCount / clipWidthInPx)`; peak + RMS per bucket.
- Cached as `CGImage` per (clipID, zoomBucket) in an `OSAllocatedUnfairLock`-protected LRU; invalidated on clip edit.
- Fallback during cache miss: tertiary placeholder.
- Accessibility: `.accessibilityHidden(true)` on the image; clip title/duration remain readable.

---

## 11. Implementation Notes

### 11.1 Token additions

- `LiquidColors.Canvas.elev` (#1A1A1F).
- `LiquidColors.Accent.success` (#6BCB77) if missing.
- `LiquidColors.Accent.warning` (#E5A14A) if missing.
- Verify `Accent.amberGlow`, `Accent.destructive`, and all `Timeline.*` against `LiquidColors.swift`; **add any missing before first view is built**.

### 11.2 Existing components to reuse / extend

`PlayheadWithChip` · `TransportButton` · `ToolButton` · `TabBarItem` · `GradientProgressBorderView` · `ProjectCardView` (extend with badge, numbered-select, cloud / conflict / locked states).

### 11.3 New components

- **Chrome & containers:** `ContextSubPanel`, `InspectorPanel`, `ToolRail`, `MediaBrowser`, `GlassContextMenu`, `ToastHost`, `SkeletonModifier`.
- **Deep tools:** `SpeedRampSheet`, `KeyframeLane`, `TrimPrecisionView`, `TrackingOverlay`, `MaskEditorView`, `BeatDetectControls`, `StabilizePanel`, `ChromaKeyView`, `AutoMixControls`.
- **Creative panels:** `TextEditorSheet`, `TransitionPickerSheet`, `FXBrowserSheet`, `LUTPickerSheet`, `ColorWheelsPanel` (`ColorWheelControl` primitive), `CurvesEditor`, `HSLPanel`, `ScopesPanel`.
- **Supporting:** `MediaPickerSheet`, `VoiceOverModal`, `AutoCaptionsReviewView`, `ProjectSettingsSheet`, `EmptyStateView`, `OnboardingSheet`, `PermissionPrimerSheet`, `CameraCaptureView`, `UndoHistoryScrubber`.
- **Timeline internals:** `AudioWaveformView`, `BeatMarkerLayer`, `ChapterMarkerLayer`, `RippleEditController`.

### 11.4 View models

- One `@Observable @MainActor` VM per sheet/modal.
- Tracking + Mask share state with `EditorViewModel` selection.
- Caption generation VM wraps `SFSpeechRecognizer` (pending §12.3); recognizer itself not MainActor-bound.
- Inspector VM is an `@Observable` projection over `EditorViewModel.selection`; recomputes `sections: [InspectorSection]` on selection change.

### 11.5 Sheet detents

| Sheet | iPhone | iPad |
|---|---|---|
| Speed Ramp | .medium | .custom(60%) |
| Text Editor | full-screen | inspector-embedded |
| Transition Picker | .medium | .custom(55%) |
| FX Browser | .large | .custom(70%) |
| LUT Grid | .large | inspector-embedded |
| Media Picker | .large | .custom(70%) |
| Voice-over Modal | .large | .custom(60%) |
| Auto-Captions Review | full-screen | .custom(80%) |
| Project Settings | .medium | .custom(50%) |
| Undo History Scrubber | full-screen | .large |
| Onboarding | full-screen | .large |

### 11.6 Testing

- Snapshot tests per screen per major state (idle / in-progress / error / empty) using Swift Testing + image diff.
- Gesture tests for timeline (tap, long-press, drag, pinch) via native XCUITest for gesture-specific paths.
- Accessibility audit in CI: `XCTest` Accessibility Audit against each screen's preview.

---

## 12. Design-Blocking Decisions (must resolve before implementation plan)

1. **Tracking engine.** `VNDetectObjectRequest` vs. custom point-tracker for Object mode. Determines which of Point / Object / Face / Body / Hand ship in v1 and the §7.4.1 Failed copy.
2. **.cube LUT import in v1?** Blocks §8.4 UI (Import link is drawn).
3. **STT vendor.** On-device `SFSpeechRecognizer` vs. cloud. Affects §9.3.1 timing, offline behavior, privacy copy in §9.13.
4. **Snapshot policy.** Retained count + aged-thinning cadence for §9.8 history scrubber. Spec currently assumes 200.
5. **Ripple-delete default.** Ripple-on-delete toggle default (on/off). Affects muscle memory and every Delete.
6. **iPhone landscape.** Ship §3.2 in v1 or defer? Affects scope of `InspectorPanel` and alternate-layout code (~10% of editor layout).

---

## 13. References

- Editor layouts (iPhone + iPad): `.superpowers/brainstorm/41597-1776514658/content/editor-layouts-v2.html`
- Project + Export: `.superpowers/brainstorm/41597-1776514658/content/project-export.html`
- Tab drill-downs: `.superpowers/brainstorm/41597-1776514658/content/tab-drilldowns.html`
- Deep tools: `.superpowers/brainstorm/41597-1776514658/content/deep-tools.html`
- Creative panels: `.superpowers/brainstorm/41597-1776514658/content/creative-panels.html`
- Supporting flows: `.superpowers/brainstorm/41597-1776514658/content/supporting-flows.html`
- Tokens: `LiquidEditor/DesignSystem/Tokens/` (LiquidColors, LiquidSpacing, LiquidTypography, LiquidRadius, LiquidElevation, LiquidMotion, LiquidMaterials, FormFactor)
- Performance budgets: `docs/PERFORMANCE.md`
- Timeline internals: `docs/DESIGN.md` (Timeline), `docs/APP_LOGIC.md` (Composition)
