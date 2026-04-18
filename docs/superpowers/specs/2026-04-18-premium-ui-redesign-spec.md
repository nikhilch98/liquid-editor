# Premium UI Redesign — Full Screen & Component Spec

**Date:** 2026-04-18
**Status:** Approved (visual design)
**North star:** Instagram Edits × CapCut — dense, pro-feeling, dark canvas, amber accent, glass surfaces
**Direction locked:** Option A — **Timeline-Dominant on iPhone / Pro-Workstation on iPad**
**Mockups:** `.superpowers/brainstorm/41597-*/content/*.html`

---

## 1. Purpose & Scope

Redesign the three primary LiquidEditor screens (Editor / Project Library / Export) and all contextual sub-surfaces (tab drill-downs, deep-tool editors, creative panels, supporting flows) in a single coherent visual language.

**In scope:** visual layout, component structure, interaction model, iPhone + iPad adaptation, design-token usage.

**Out of scope:** new feature work not already implied by existing code, performance targets (tracked in `docs/PERFORMANCE.md`), Metal/compositor changes, timeline data structures.

---

## 2. Shared Design Language

### 2.1 Tokens (all already defined under `LiquidEditor/DesignSystem/Tokens/`)

| Role | Token |
|---|---|
| App background | `LiquidColors.Canvas.base` (#07070A) |
| Raised surface (timelines, shelves, settings groups) | `LiquidColors.Canvas.raised` (#0F0F12) |
| Elevated cell (tool button, segmented item) | `LiquidColors.Canvas.elev` (#1A1A1F) **— NEW token, add to `LiquidColors.swift`** |
| Primary text | `LiquidColors.Text.primary` (#F3EEE6) |
| Secondary text | `LiquidColors.Text.secondary` (#9C9A93) |
| Tertiary text / disabled | `LiquidColors.Text.tertiary` (#5A5852) |
| Accent / active / CTA | `LiquidColors.Accent.amber` (#E6B340) |
| Accent glow | `LiquidColors.Accent.amberGlow` (37% α) |
| Destructive | `LiquidColors.Accent.destructive` (#E5534A) |
| Stroke hairline | rgba(255,255,255,0.06) |
| Stroke prominent | rgba(255,255,255,0.12) |

Audio / text / video clip colors remain per the existing `LiquidColors.Timeline.*` family. Track gradient clips use the existing `CLIP-VIDEO`, `CLIP-AUDIO`, `CLIP-TEXT` tokens.

### 2.2 Motion

- Sub-panel slide-up: `LiquidMotion.smooth` (response 0.30, damping 0.85).
- Chip/tool selection highlight: `LiquidMotion.snap`.
- Keyframe scrub / timeline zoom: `LiquidMotion.glide`.
- Context menu reveal: `LiquidMotion.bounce`.
- All spring animations fall back to `LiquidMotion.reduced` under Reduce Motion.

### 2.3 Global interaction conventions

- Active state = 1px amber border + `rgba(230,179,64,0.10)` fill + amber label.
- Sub-panel appears between timeline and tool shelf; has amber 1px border + downward-pointing caret + 8px shadow. Dismiss via ✕ or tapping the tool again.
- Destructive actions: amber is forbidden; use `Accent.destructive` and confirmation dialog.
- Long-press anywhere (clip, card, media cell) reveals the floating glass context menu.
- Haptic: `.selection` on tab switch, `.impact(light)` on tool tap, `.impact(medium)` on destructive confirm.

### 2.4 Form-factor rules (`LiquidEditor/DesignSystem/Tokens/FormFactor.swift`)

- **Compact (iPhone, < 640pt):** single-column layout; sub-panels slide up as bottom sheets above the shelf.
- **Regular (iPad ≥ 640pt):** sub-panels live in the right-rail inspector (persistent, not modal). Bottom shelf is replaced by a left tool-rail + top toolbar.

---

## 3. Screen 1 — Editor

### 3.1 iPhone layout (top to bottom)

1. **Chrome bar** — Close (✕) │ Project chip (name ▾) │ Settings (⚙) │ Export (amber CTA).
2. **Preview** — flex-basis 32% of column height. 2K·60 pill top-right; playhead-time chip bottom-left with amber dot.
3. **Transport row** — undo │ redo │ central amber play button (22pt, glow) │ timecode chip │ fullscreen.
4. **Timeline** — flex-grow; 3 tracks visible by default (V1 │ V2 text overlay │ A1); track headers show mute/lock icons; playhead is a 1px amber line with a 7pt dot at top.
5. **Contextual sub-panel** — appears here when the active tool needs parameters.
6. **Tool shelf** — two rows: top = tool strip (5 buttons for active tab), bottom = 5-tab bar (Edit / Audio / Text / FX / Color).

### 3.2 iPad layout

1. **Top toolbar** — Close │ Project chip │ undo/redo │ (right) settings │ fullscreen │ Export.
2. **3-panel row (flex 0 0 45%):** Media browser (left 90pt) │ Preview (center, flex) │ Inspector (right 120pt). Inspector shows property values for the selected clip; media browser has its own tab bar (Clips / Audio / FX).
3. **Transport bar** — same controls, larger, floating glass panel.
4. **Timeline + tool rail row (flex 1):** multi-track timeline (4 tracks by default: V2 │ V1 │ A1 │ A2) plus a 36pt-wide vertical tool rail on the right with the 6 most-used tools.

---

## 4. Screen 2 — Project Library

### 4.1 iPhone

- **Header:** logo (“liquid.”) + search icon + avatar.
- **Search + filter row.**
- **Recent rail:** horizontal scroll of small thumbnail-only cards with duration overlay.
- **All-projects section:** 2-column grid of project cards (thumbnail 9:16, 4K/HDR badges, duration chip, title, relative timestamp).
- **FAB:** amber circular “+” bottom-right, stacked above tab bar.
- **Bottom tabs:** Projects │ Templates │ Drafts │ You.

### 4.2 iPad

- **Left sidebar (120pt):** Library sections (All / Recent / Starred / Drafts) with counts, Collections list, Templates, Trash.
- **Top bar:** logo + search input + grid/list segmented control + amber “+ New Project” CTA.
- **Main grid:** 4-column project cards with same meta as iPhone; selected card has amber border + glow.
- **Sort segment:** Recent / Name / Size inline above the grid.

---

## 5. Screen 3 — Export

### 5.1 Signature element (preserved from existing)

The existing `GradientProgressBorderView` (pink→red→orange→yellow conic gradient, -90° start) stays. It becomes the visual centerpiece: a ring around the video-preview thumbnail that animates during export.

### 5.2 iPhone

1. Chrome: back │ “Export” title │ ⚙.
2. Ring-bordered preview (90 × 140), centered, shows “2K / 1080×1920 · 60 fps” label inside.
3. Preset segmented control: Quick / Social / Pro / Custom.
4. Settings card with steppers: Resolution (720p / 1080p / 2K / 4K) │ Frame rate (24 / 30 / 60) │ Quality (Med / High / Max).
5. Toggle rows: HDR │ Audio only.
6. Sticky amber CTA: **“Export · ~ 38 MB”** (size is live-computed).

### 5.3 iPad

Two-column split:
- **Left (220pt):** ring preview (fills height) + live meta card (estimated size, duration, bitrate).
- **Right (flex):** preset segment + Video group (Resolution / FPS / Format / Quality) + Advanced (HDR, Rec.2020, Loop-safe, Audio-only) + Destination grid (Photos / Files / AirDrop / Share…).
- Full-width CTA at bottom: **“Export · 2K HDR HEVC · ≈ 38 MB”**.

---

## 6. Editor Tab Drill-Downs

Each of the 5 bottom tabs swaps the tool strip and may reveal a contextual sub-panel. Tools that are destructive or one-shot (Split, Duplicate, Delete) fire immediately; parametric tools open a sub-panel.

### 6.1 Edit tab

| Tool | Panel? | Controls |
|---|---|---|
| Split | No | Cuts at playhead |
| Trim | Yes (full mode) | See §7.3 |
| Speed | Yes | Preset chips (0.25× / 0.5× / 1× / 2× / Curve…), rate slider, preserve-pitch toggle |
| Volume | Yes | dB slider, fade in/out, Mute/Duck/Denoise chips |
| Duplicate / Copy / Delete | No | Immediate |
| Reverse / Freeze frame | Yes (progress) | Confirmation + render progress chip |
| Replace | Yes | Opens Media Picker (§10.1) |
| Keyframes | Yes | See §7.2 |
| Animation | Yes | In / Out / Loop preset chips |
| Mask | Yes (full mode) | See §7.5 |

### 6.2 Audio tab

Music │ SFX │ Record (opens Voice-over modal §10.2) │ Extract │ Volume │ Beat detect │ EQ │ Pitch │ Auto-mix.

### 6.3 Text tab

Text (opens Text Editor §8.1) │ Captions (opens Auto-captions review §10.3) │ Sticker │ Preset │ Font / Size / Color │ Stroke / Shadow / Background / Animation / Align.

### 6.4 FX tab

Filter │ Transition (opens Transition Picker §8.2) │ Effect (opens FX Browser §8.3) │ Stabilize │ Chroma key │ Mask │ **Tracking** (§7.4) │ Mirror / Freeze / Cutout.

### 6.5 Color tab

Preset │ LUT (opens LUT Grid §8.4) │ Wheels (opens 3-way Wheels §8.5) │ Curves │ Temp / Tint / Exposure / Contrast │ Highlights / Shadows │ Saturation / Vibrance │ HSL │ Scopes (iPad default-on).

---

## 7. Deep Tool UIs

### 7.1 Speed Ramp Curve (modal sheet)

- Bottom sheet over the editor with grabber + Cancel / Done.
- Preset chips: Linear / Custom / Ramp up / Bounce.
- Curve canvas: x = clip time (0 → duration), y = speed (0.1× log-to-10×). Draggable points; endpoint anchors are white, interior points are amber.
- Frame thumbnail strip below canvas; thumbnails under keyframe points are outlined amber (“pinned”).
- Preserve-pitch toggle.
- Persisted on clip via a speed-curve ramp array.

### 7.2 Keyframes (inline panel)

- Replaces the sub-panel area when the Keyframes tool is active.
- Property lanes (top to bottom): Scale / Position / Opacity / Rotation. Each lane is a 42pt-name column + mini lane + live value readout.
- Keyframe markers: amber diamond (linear) or amber circle (held). Current-frame marker is white.
- Toolbar: **+ Key** (amber primary) / **− Key** / prev-next key shuttle / ease picker (step / ease / linear thumbnails).
- Selecting a property in the lane swaps the main timeline view so the lane lives in-context under the clip.

### 7.3 Trim Precision (full mode)

- Enter on tool-tap or by long-pressing a clip edge.
- Preview shows IN/OUT timecode chips bottom corners.
- Zoomed frame strip (6 thumbnails) with amber L/R handles; duration center-labeled in amber.
- IN-trim and OUT-trim rows each have ±1 frame and ±1 second shuttle buttons.
- Ripple edit + Snap to playhead + Snap to beat markers toggles.

### 7.4 Motion Tracking (full-screen mode)

- HUD: amber “Tracking N%” pill with pulsing dot + frame-count chip (e.g., 14 / 34 frames).
- Preview overlay: 1.5px amber bounding box with 4 corner dots, a draggable center crosshair, “Subject · 94%” confidence label, motion trail line.
- Confidence chip bottom of preview: Strong / Medium / Weak (green / amber / red).
- Keyframe bar under preview: timecode range + tracked-frame dots + white current-frame marker.
- Controls surface: Track-type chips (Point / Object / Face / Body / Hand), Smoothing slider, Scale-match toggle, Rotation-match toggle.
- Actions: Stop (amber destructive-of-process) / Reset / ⋯ overflow.
- Mask “Track to subject” reuses this engine.

### 7.5 Mask Editor (full mode)

- Preview has a black overlay everywhere except inside the mask shape, revealed by a radial cutout.
- Dashed amber shape outline with 4 cardinal handles + dotted feather ring.
- Shape picker (5 options): Rectangle / Ellipse / Rounded / Star / Freehand (pen).
- Sliders: Feather (px) / Opacity (%) / Expand-Contract (± px).
- Chips: Invert / Animate / Track to subject (links to 7.4).

---

## 8. Creative Panels

### 8.1 Text Editor (full mode)

- Preview has a dashed amber bbox with 6 resize handles + 1 rotation handle 14pt above.
- 4 inline sub-tabs: **Text** / Effects / Animation / Align.
- Text tab: live text input card (amber border when focused) + 5-font pill row + size slider.
- Effects tab: 4-cell style grid (plain / stroke / shadow / filled background) + 7 circular color swatches (first is multi-color, opens full picker).
- Animation tab: chip sets for In / Out / Loop presets.
- Align tab: horizontal (L/C/R) + vertical (T/M/B) segmented.

### 8.2 Transition Picker

- Two-clip stage at top: two thumbnails side-by-side with an amber transparent gradient overlay between them; center badge shows active transition (e.g., “◇ Zoom”).
- Duration slider (seconds + frame count).
- 5 category chips: Popular / Cut-Fade / Motion / 3D / Morph.
- 4×2 grid of transition thumbnails.
- “Apply to all cuts” toggle at the bottom.

### 8.3 FX Browser

- Applied stack surface at top: list of currently-applied effects, each with name + intensity % + ✕ remove.
- Category chips: All / Filter / Glitch / Motion / AI.
- 3×3 grid of live-preview thumbnails (NEW and PRO badges).
- Active effect reveals a per-effect intensity slider below the grid.

### 8.4 LUT Grid

- Split-preview with “Before” (tertiary chip) / “After” (amber chip) markers; middle amber divider for split-compare mode.
- Compare segmented: A / B / Split.
- “Import .cube” entry (right-aligned amber link).
- Category chips: Cinematic / Film / Vintage / B&W.
- 3×3 LUT cards, each with name strip bottom; selected card shows amber checkmark top-right.
- Intensity slider.

### 8.5 Color Wheels (3-way)

- Mini waveform scope strip at top (filled amber curve, optional luma overlay).
- 3 wheels side by side: **Lift** (shadows) / **Gamma** (midtones) / **Gain** (highlights). Each wheel is a 52pt conic-gradient disc with white puck, luminance slider, numeric readout.
- Below the wheels: Temp slider (blue → amber gradient track), Tint slider (green → red gradient track), Saturation slider.
- Sibling tabs in the Color sub-panel host Curves and HSL.

---

## 9. Supporting Flows

### 9.1 Media Picker

- Source tabs: Photos / Videos / Files / Cloud.
- Smart filter chips: Today / ≤10s / 4K / HDR (configurable).
- Album header with count + “Albums ▾” dropdown.
- 3-column grid. Selected cells show a numbered amber pill in the top-left (1, 2, 3…) preserving import order.
- Per-cell badges: 4K / HDR / duration.
- Sticky bottom bar: “3 selected” count (amber) + amber “Add to project” CTA.

### 9.2 Voice-over Modal

- Ring-preview panel; below, a live waveform card with 10-cell peak meter (bottom 7 amber, 2 warn, 1 red at the top).
- Giant red circular record button in the center. Tap once to arm (amber), tap again to record (red).
- Recording time live-updates in the surface header (red “● 00:04.12”).
- Below: mini timeline shows existing video+audio clips plus a red bar at the playhead position indicating where the VO is being written.
- Actions: Cancel / Punch-in / Save.

### 9.3 Auto-captions Review

- Preview with word-pop style overlay: highlighted word has amber fill, others have translucent-black pill.
- 4 style templates: Word-pop / Line / Bar / Minimal.
- Segment list: timecode column + text; active segment has amber left border + amber text. Segments with low-confidence STT output are shown in destructive red.
- Per-segment action bar: Edit / Split / Merge / Delete.
- Sticky “Apply all” CTA in chrome.

### 9.4 Context Menu (long-press)

- Appears on long-press of a clip, a project card, or a media cell.
- Rest of UI dims to ≈60% brightness; menu floats as a glass surface with 20pt blur.
- Items: grouped by primary → secondary → destructive, divided by hairline rows.
- iPad-only: keyboard shortcut tokens right-aligned (S / ⌘C / ⌘D / ⌦).
- Clip menu: Split / Trim / Copy / Duplicate • Speed / Replace / Properties • Delete.
- Project-card menu: Open / Rename / Duplicate / Share / Move to collection • Delete.

### 9.5 Project Settings Sheet

- Header: thumbnail (with edit badge) + project name (inline-edit) + created date + clip count + duration.
- Grouped sections (inset list style):
  - **Canvas:** Aspect / Resolution / Frame rate.
  - **Color:** HDR toggle / Color space.
  - **Audio:** Sample rate / Master level.
  - **Other:** Snapshots · History (leads to history scrubber), Duplicate project.
- Footer: destructive **Delete project** row (red).

### 9.6 Empty States

Three variants, same template (hero illustration + title + subtitle + optional CTA + escape-hatch link):
- **Library empty:** amber “+” illustration, “No projects yet”, “+ New Project” CTA + “try a Template” link.
- **Timeline empty:** dashed drop zone with large “+”, “Drag media or tap to import” helper.
- **Search no results:** quoted query echo + “clear filters” amber link.

---

## 10. Implementation Notes

- **Token additions required:** `LiquidColors.Canvas.elev` (#1A1A1F) used for elevated cells. Verify all other tokens referenced above (`Accent.amberGlow`, `Accent.destructive`, `Timeline.*`) against `LiquidColors.swift` before implementation; add any missing.
- **Existing components to reuse:** `PlayheadWithChip`, `TransportButton`, `ToolButton`, `TabBarItem`, `GradientProgressBorderView`, `ProjectCardView` (extend with badge + numbered-select states).
- **New components required (tentative names):**
  - `ContextSubPanel` (animated sub-panel container with caret + dismiss).
  - `SpeedRampSheet`, `KeyframeLane`, `TrimPrecisionView`, `TrackingOverlay`, `MaskEditorView`.
  - `TextEditorSheet`, `TransitionPickerSheet`, `FXBrowserSheet`, `LUTPickerSheet`, `ColorWheelsPanel` (3 wheels share a `ColorWheelControl` primitive).
  - `MediaPickerSheet`, `VoiceOverModal`, `AutoCaptionsReviewView`, `GlassContextMenu`, `ProjectSettingsSheet`, `EmptyStateView`.
  - `InspectorPanel` (iPad right-rail replacing the iPhone sub-panel).
  - `ToolRail` (iPad vertical 36pt rail).
  - `MediaBrowser` (iPad left-rail tabbed browser).
- **ViewModels (`@Observable @MainActor`):** one per new sheet/modal; tracking + mask share state with `EditorViewModel` selection.
- **iPad adaptation:** sub-panels and modals map to `InspectorPanel`; full-screen modes (Tracking, Mask, Text Editor) still present as full surfaces but with persistent chrome.
- **Accessibility:** every tool strip button needs an `accessibilityLabel`; sliders expose value formatter; Dynamic Type respected in chip rows (wrap to multi-row if required).
- **Haptics:** `.selection` on chip-tap; `.impact(.medium)` on destructive confirm; `.impact(.light)` on keyframe toggle.
- **Reduce Motion:** all slide-up / bounce animations fall through `LiquidMotion.liquid(...)`.

---

## 11. Open Questions

1. **Tracking engine:** do we adopt Apple Vision `VNDetectObjectRequest` for the MVP Object mode, or roll a point-tracker? Decision needed before implementation planning.
2. **LUT import:** .cube file format support is drawn but requires a parser. Ship in v1 or defer?
3. **Auto-captions:** STT vendor decision (on-device `SFSpeechRecognizer` vs cloud). Affects UX latency of the review panel.
4. **Snapshots / history:** how many snapshots do we persist per project, and is the scrubber a separate sheet or inline in Project Settings?

---

## 12. References

- Editor layouts (iPhone + iPad, A/B/C): `.superpowers/brainstorm/41597-1776514658/content/editor-layouts-v2.html`
- Project + Export: `.superpowers/brainstorm/41597-1776514658/content/project-export.html`
- Tab drill-downs: `.superpowers/brainstorm/41597-1776514658/content/tab-drilldowns.html`
- Deep tool UIs: `.superpowers/brainstorm/41597-1776514658/content/deep-tools.html`
- Creative panels: `.superpowers/brainstorm/41597-1776514658/content/creative-panels.html`
- Supporting flows: `.superpowers/brainstorm/41597-1776514658/content/supporting-flows.html`
- Tokens: `LiquidEditor/DesignSystem/Tokens/` (LiquidColors, LiquidSpacing, LiquidTypography, LiquidRadius, LiquidElevation, LiquidMotion, LiquidMaterials, FormFactor)
