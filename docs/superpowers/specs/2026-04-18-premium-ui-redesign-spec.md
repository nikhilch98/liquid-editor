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

**Export source:** always the original media. Proxies (§10.9) are for playback only and are never used as an export source. If an original is missing, export surfaces a blocking error and routes through the media-relink flow (§3.4 / F6-16) before retry.

### 5.6 Custom Export Preset Editor

**Entry:** Preset segmented control → **Custom** → **Customize…** inline link. On iPad, opens as a large-detent sheet alongside the ring preview so the user sees estimate changes live; on iPhone, full-screen.

**Form sections:**

1. **Preset header** — name input (for save-as) + amber **Save preset** / tertiary **Save as new…** / destructive **Delete preset** (if editing a named preset).
2. **Video**
   - Resolution: preset chips (720p / 1080p / 2K / 4K) + **Custom…** opens numeric W×H inputs.
   - Frame rate: 24 / 25 / 30 / 50 / 60 / 120 chips + **Custom…** numeric.
   - Codec: **H.264** / **HEVC (H.265)** / **ProRes** / **ProRes 422 HQ** chips.
   - Container: MP4 / MOV segmented.
   - Profile + Level (H.264/HEVC only): Baseline / Main / High + numeric level.
   - Bitrate mode: CBR / VBR / ABR segmented; **Target** numeric + **Max** numeric.
   - Keyframe interval (sec): numeric stepper.
   - B-frames: toggle.
3. **Audio**
   - Codec: AAC / AAC-LC / ALAC.
   - Bitrate: 128 / 192 / 256 / 320 kbps chips + **Custom…**.
   - Sample rate: 44.1 / 48 / 96 kHz.
   - Channels: Stereo / Mono.
4. **Color**
   - Color space: Rec. 709 / DCI-P3 / Rec. 2020 segmented.
   - HDR profile: SDR / HLG / HDR10 (PQ) / Dolby Vision chips (only valid options for the selected codec are enabled).
   - Pixel format: 8-bit / 10-bit / 12-bit (bounded by codec choice).
5. **Advanced**
   - Loop-safe (seamless) toggle (shared with §5.2).
   - Metadata: include location / include device / include app-attribution toggles.
   - Two-pass encoding: toggle.
   - Hardware acceleration: auto / force-hardware / force-software.

**Saved presets** appear in a “Saved” section of the top preset segmented control (alongside Quick / Social / Pro / Custom). Swipe-to-delete or tap-to-edit.

**Validation:** invalid combinations (e.g., HDR10 on H.264 8-bit) surface a red banner at the top of the editor with a “Fix” link that auto-picks valid defaults.

**Estimate:** the live size/bitrate estimator (S2-14) recomputes on every change; “Estimated size ≈ XX MB” pinned above the Save button.

---

## 6. Editor Tab Drill-Downs

### 6.1 Edit tab

| Tool | Panel | Controls |
|---|---|---|
| Split | no | Cuts at playhead. |
| Trim | full mode (§7.3) | — |
| Speed | yes | Presets (0.25×/0.5×/1×/2×/Curve…), rate slider, preserve-pitch. |
| Volume | yes | dB, fade, Mute/Duck/Denoise. |
| Duplicate / Copy / Cut / Paste / Delete | no | Immediate (Delete + Cut confirm per §2.2). |
| Reverse / Freeze frame | progress | Amber bar on clip; tap-to-cancel. |
| Replace | full mode | Opens Media Picker (§9.1). |
| Group / Ungroup | no | See §7.10. |
| **Compound / Break** | no | See §7.13 (⌘⌥G to compound). |
| **Link / Unlink** | no | See §7.16 (⌘L / ⇧⌘L). |
| **Match frame** | no | See §7.15 (`F`). |
| **Clip marker** | no | See §7.17 (`M`). |
| Transform (Flip / Rotate / Crop / Blend) | inline (§7.12) | Shared with Inspector on iPad. |
| Keyframes | inline (§7.2) | — |
| Animation | yes | Preset chips (§8.1.3 list). |
| Mask | full mode (§7.5) | — |

### 6.2 Audio tab

Music │ SFX │ Record (→ §9.2) │ Extract │ Volume │ **Pan** (§7.12) │ **Normalize** (§7.12) │ **Beat detect** (§7.6) │ EQ │ Pitch │ **Reverb** (§7.18) │ **Delay** (§7.18) │ **Compression** (§7.18) │ **Gate** (§7.18) │ **Limiter** (§7.18) │ **Auto-mix** (§7.7).

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

### 7.10 Clip Grouping / Compound Clips

- **Entry:** select 2+ clips (lasso or shift-tap) → context menu → **Group** (⌘G).
- Grouped clips move / trim / delete / copy / duplicate as a single unit. Visual: a 2px amber bracket outlines the group with a group-label chip “Group · 3 clips” at top-left; individual clips keep their own styling inside.
- **Enter group** via double-tap or context “Edit group”: the group’s clips become individually selectable; all other clips dim to 40%; a breadcrumb “Project › Group” appears top-left.
- **Exit group** via Escape (iPad), swipe-down (iPhone), or tap breadcrumb root.
- **Ungroup** (context menu, ⇧⌘G): dissolves the group; inner clips remain in place.
- **Nesting:** groups may contain groups; up to 5 levels deep.
- **Data model:** `ClipGroup { id, name, memberIDs, color }` lives alongside `Clip` in `PersistentTimeline`. Grouping does **not** collapse the members into one render — each member renders independently. (True compound clips with flattened composition are deferred.)
- **Effects on a group:** applying a color grade, effect, mask, or keyframes to a group applies to the group as a layer rendered above member clips; intensity / bypass per-group.

### 7.11 Timeline Operations Catalog

All operations shown here are first-class timeline commands with keyboard shortcuts (§10.5), context-menu entries (§9.4), and undoable via §9.8.

| Operation | Trigger | Behavior |
|---|---|---|
| **Select** | tap clip | Single; populates Inspector. |
| **Multi-select** | shift-tap (iPad) / lasso (track empty area) | Adds to selection; Inspector shows consistent-only props with “Mixed” for inconsistent. |
| **Select all on track** | long-press track header → “Select all clips” | — |
| **Select all at playhead** | ⌘A (iPad) | Selects every clip intersecting the playhead across all tracks. |
| **Select forward / backward from playhead** | context menu | Everything after / before the playhead. |
| **Deselect all** | Escape / tap empty area | — |
| **Copy / Cut / Paste** | ⌘C / ⌘X / ⌘V | Cross-project paste supported (T7-14); paste drops at playhead. |
| **Duplicate** | ⌘D / context | Duplicated clip inserted immediately after source. |
| **Delete** | ⌦ / context | Per ripple-delete default (D0-5); non-ripple leaves a gap. |
| **Ripple-delete** | ⇧⌦ or toggle on | Deletes + closes gap regardless of default. |
| **Collapse gap** | context on empty track region | Removes empty space; all clips after shift left. |
| **Split at playhead** | S / ⌘S / context | Cuts clip under playhead; Split-all-tracks with ⇧S. |
| **Trim** | drag edge / Trim tool (§7.3) | — |
| **Slip / Roll / Slide** | Trim Precision chips (§7.3) | See T7-18. |
| **Nudge ±1 frame** | ⌥ ← / ⌥ → with clip selected | Shifts selected clip(s). |
| **Nudge ±1 second** | ⌥⇧ ← / ⌥⇧ → | — |
| **Insert mode / Overwrite mode** | I key toggle or transport segmented | Insert pushes existing clips forward at playhead; Overwrite replaces content under playhead. |
| **Replace** | Replace tool → Media Picker | Keeps duration + effects, swaps source. |
| **Group / Ungroup** | ⌘G / ⇧⌘G | See §7.10. |
| **Bring to front / Send to back** | context on overlay clip | Reorders z-index within overlay track (only relevant when multiple overlay clips overlap). |
| **Reverse / Freeze frame** | Edit tab tools | Background render with progress (see TD8-13). |
| **Detach audio** | context → “Extract audio” | Same as TD8-4. |
| **Zoom to fit / Zoom to selection** | `\` / ⌘⇧0 | Timeline zooms to show entire project or selected range. |
| **Auto-follow playhead** | toggle in transport | Scrolls timeline to keep playhead in view during playback. |

### 7.12 Per-Clip Transform & Blend Operations

Live in the Inspector Transform section (iPad) or Edit-tab “Transform” sub-panel (iPhone).

- **Flip horizontal** / **Flip vertical** — one-tap toggles.
- **Quick rotate** — 0° / 90° / 180° / 270° segmented. For free rotation, use the Inspector Transform row (§10.2).
- **Crop** — simple rect crop distinct from Mask (§7.5); top / right / bottom / left numeric fields + drag-handles on preview.
- **Blend mode** (video clip on overlay track) — Normal / Multiply / Screen / Overlay / Soft Light / Add / Subtract. Blend interacts with the track below it.
- **Opacity** — 0–100% slider (already in Inspector per §10.2).
- **Audio pan** (audio clip) — –1.0 (L) ↔ +1.0 (R) slider with center detent.
- **Audio normalize** (audio clip) — chips for target LUFS: –16 (streaming) / –14 (loud) / –23 (broadcast); applies across the clip.

### 7.13 True Compound Clips

Built on §7.10 Groups. Where a Group is a thin bracket around members (each rendering independently), a **Compound Clip** is a single rendered source produced by flattening a nested timeline.

- **Convert:** context menu on a Group → **Convert to Compound Clip** (⌘⌥G). Destructive only in the sense that per-member effect stacks are captured into the flattened render; Undo restores the Group unchanged.
- **Revert:** context menu on a Compound Clip → **Break to Group** restores the Group with all original members and their per-member settings.
- **Internal timeline:** double-tapping a Compound enters it; you see its own tracks, ruler, transport, and all tab drill-downs apply. Breadcrumb reads `Project › Compound — “Intro”`.
- **Rendering:** the compound’s internal timeline composites through the existing `MultiTrackCompositor` to a single video+audio source; that source is then treated as one clip in the parent timeline. The composited output is cached; re-rendered on internal edits.
- **Effects on a Compound:** grading, effects, masks, keyframes, blend modes apply **after** the internal composition, i.e., to the final compound output.
- **Nesting:** compounds may contain compounds. Soft cap at 10 levels with a warn banner; hard cap at 20 to protect the render pipeline.
- **Thumbnail:** compound tile in the parent timeline shows a rendered frame from the internal composition’s first second, with a small 🤵 compound glyph overlay.
- **Perf:** render cache per compound identified by `(compoundID, contentHash)`; invalidated when any descendant edit commits. Background re-render (low-QoS) with progress visible on the compound tile.

### 7.14 Source Monitor & Three-Point / Four-Point Editing

A pro workflow surface for building a cut from source material. Ships on **iPad only in v1**; iPhone adds a lightweight sheet variant.

- **Source Monitor** — second preview surface, distinct from the program preview. Displays whichever clip is currently “losaded”: tap a clip in the Media Browser, or `Shift`-tap a clip in the timeline to load its source.
- **Placement:** iPad docks the Source Monitor above the Inspector (right rail); the existing program Preview becomes the Destination Monitor. iPhone surfaces Source Monitor as a large-detent sheet when any three-point command fires.
- **Source markers:** independent IN (`I`) / OUT (`O`) markers on the source, separate from the timeline.
- **Destination markers:** use the timeline playhead for Destination IN (`⇧I`) and — for 4-point — Destination OUT (`⇧O`).
- **Commands** (buttons + shortcuts):
  | Command | Shortcut | Behavior |
  |---|---|---|
  | **Insert at playhead** | `,` | Inserts source IN→OUT at destination playhead; existing clips push forward. |
  | **Overwrite at playhead** | `.` | Replaces content under playhead for source IN→OUT length. |
  | **3-point edit** | `F9` | Source IN + OUT + destination IN → inserts or overwrites per mode; duration = source (OUT−IN). |
  | **4-point edit** | `F10` | Source IN + OUT + destination IN + OUT → fits source into destination window (may retime). |
  | **Replace at playhead** | `N` | Swaps content directly under playhead, preserving effects. |
- **J / K / L shuttle** works on the Source Monitor when focused.
- **Audio / video only** toggles: pick which tracks the insert/overwrite writes to.

### 7.15 Match Frame

- **Entry:** context menu on a timeline clip → **Match frame**, or `F` shortcut when clip is selected.
- **Effect:** opens the Media Browser (iPad) or source sheet (iPhone) with the source asset highlighted; loads it into the Source Monitor (§7.14) with its IN set at the exact source-frame that corresponds to the current playhead position in the timeline clip.
- **Use:** jump back to source to make a different cut of the same take without hunting in the browser.
- **Reverse direction:** when a source-browser clip is focused, **Match frame** jumps the timeline playhead to any place where that source is used (cycles through usages if multiple).

### 7.16 Link / Unlink Clips

Video+audio clips imported from the same source are auto-linked. A **Link Group** binds moves, trims, and deletes across members so sync stays intact.

- **Visual:** linked clips share a 1px amber underline along their bottom edges + a small 🔗 glyph on the leftmost member. Selecting one selects the group.
- **Auto-link on import:** any video asset with matching-duration embedded audio generates an implicit `LinkGroup { videoClipID, audioClipID }` at import.
- **Manual link:** select 2+ clips → context **Link selected** (⌘L). Must be same duration (snap to shortest warns).
- **Unlink:** context **Unlink** (⇧⌘L) or hold `⌥` while dragging a member to override link for that gesture only.
- **Ripple respect:** ripple operations traverse link edges — moving a linked video moves its audio in lock-step; ripple-delete removes the whole group.
- **Data model:** `LinkGroup { id, memberIDs, kind: .sync | .manual }` stored alongside `ClipGroup` in `PersistentTimeline`. Links are orthogonal to Groups: a clip can be in both a Group and a Link Group.

### 7.17 Clip-Level Markers

Distinct from timeline markers (§7.6 beat, user chapter). Clip markers live **inside** a clip tile and travel with the clip on move, trim, or group operations.

- **Add:** `M` shortcut while the clip has focus (timeline playhead inside it); or context menu → **Add marker at playhead**.
- **Visual:** small vertical pip (3pt wide × full-tile-height, amber at 40% opacity) inside the clip tile. Tap to seek + reveal a small pop-over with **Label** field and 6 color swatches.
- **Color-coding:** amber (default), red, green, blue, purple, white — for scene / review / take flags.
- **Editing:** long-press pip → menu **Rename / Recolor / Delete**. Drag to move within clip.
- **Navigation:** `⌘←` / `⌘→` jump playhead to prev/next clip marker (global across all clips by source-time order).
- **List view (iPad):** Inspector section **Markers** shows a compact list of all clip markers with color chips + labels + timecodes.
- **Data model:** each `Clip` gains an optional `[ClipMarker]` array; `ClipMarker { id, positionInClip: TimeMicros, label, color }`.

### 7.18 Additional Audio Effects

Extends the Audio tab beyond EQ / Pitch / Denoise / Volume / Pan / Normalize. Each is a per-clip effect in an audio effect chain; chain ordering matches the UI ordering (Reverb → Delay → Compression → Gate → Limiter by default), user-reorderable (drag in Inspector).

- **Reverb** — Room-preset chips (Room / Hall / Cathedral / Plate / Spring) + Size / Decay / Pre-delay / Mix sliders.
- **Delay** — Time (ms) / Feedback / Mix sliders + **Sync to beat** toggle (locks Time to project BPM from §7.6).
- **Compression** — Threshold (dB) / Ratio / Attack (ms) / Release (ms) / Makeup gain; mini amp-meter shows gain reduction.
- **Gate** — Threshold / Attack / Hold / Release sliders.
- **Limiter** — Ceiling (dB) + Auto-release toggle; output-peak indicator.

Sub-panel pattern: each tool’s sub-panel uses `ContextSubPanel` (§2.5). Bypass toggle + intensity (wet/dry) per effect. Effect chain persists in `AudioEffectChain` on the clip (`[AudioEffect]` codable array).

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
- **Proxy generation (§10.9)** kicks off automatically for eligible imports. Progress is shown as a secondary line on the import pill and as a thin bar along the clip tile until each proxy is ready.

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
| ⌘A | Select all at playhead |
| ⌘X | Cut clip (copy + remove; respects ripple) |
| ⌘G / ⇧⌘G | Group / Ungroup selection |
| ⌘⌥G | Convert Group → Compound Clip (§7.13) |
| ⌘L / ⇧⌘L | Link / Unlink selected (§7.16) |
| F | Match frame (§7.15) |
| M | Add clip marker at playhead (§7.17) |
| ⌘← / ⌘→ | Previous / next clip marker |
| , | Insert source at playhead (§7.14) |
| . | Overwrite source at playhead (§7.14) |
| F9 / F10 | 3-point / 4-point edit (§7.14) |
| N | Replace at playhead (§7.14) |
| ⌥ ← / → | Nudge selected clip(s) ±1 frame |
| ⌥⇧ ← / → | Nudge selected clip(s) ±1 second |
| `\` | Zoom to fit entire project |
| ⌘⇧0 | Zoom to selection |
| I | Toggle Insert ↔ Overwrite mode |
| Esc | Exit group / exit compound / deselect all / dismiss sub-panel |

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

### 10.9 Proxy Rendering Pipeline

Proxy rendering generates a low-resolution stand-in copy of each eligible source media on import. The editor plays back from the proxy for smooth scrubbing while the original is used at export. Optional and user-configurable; defaults aim at "just works" for 4K source on A15+ devices.

#### 10.9.1 Policy & defaults

| Setting | Default | User-overridable |
|---|---|---|
| Use Proxies (global) | On | Yes — App Settings › Proxies |
| Auto-generate threshold | Source > 1080p | Yes (Off / ≥1080p / ≥4K / Always) |
| Proxy resolution | 720p short-side, preserving aspect | No (baked v1) |
| Proxy codec / bitrate | H.264 `.avcMain`, 5 Mbps, same frame-rate, audio pass-through | No (baked v1) |
| Disk-quota cap | 5 GB | Yes (1 / 5 / 20 GB / Unlimited) |
| Eviction | LRU under cap + system low-storage | n/a |

Sources at or below 1080p skip proxy generation regardless of the toggle — no runtime benefit.

#### 10.9.2 Data model

`MediaAsset` gains four fields:

- `proxyURL: URL?` — file URL in the proxy cache directory if ready.
- `proxyStatus: ProxyStatus` — `.none | .pending | .generating(Double) | .ready | .failed(Error)`.
- `proxyGeneratedAt: Date?`
- `useProxyOverride: ProxyOverride?` — `.followProjectDefault | .alwaysOriginal | .alwaysProxy | .regenerate`.

All fields are `Codable` and persisted with the project file (proxy files themselves live in `~/Library/Caches/LiquidEditor/Proxies/` and may be re-generated after a cache purge).

#### 10.9.3 Generation pipeline

1. On import (§9.1 / §9.7), `ProxyService` evaluates each new `MediaAsset` against the auto-generate threshold.
2. If eligible, `ProxyService` enqueues a `ProxyGenerator` task (actor).
3. `ProxyGenerator` runs `AVAssetExportSession` with 720p preset + H.264 5 Mbps + matching frame-rate + audio pass-through; emits progress `[0…1]` via `AsyncStream`.
4. On completion the proxy is saved to the cache directory and `MediaAsset.proxyStatus = .ready`.
5. On failure: log, fall back to original, surface a non-blocking toast *"Proxy unavailable for clip — using original."* Failed assets do not re-attempt automatically.

#### 10.9.4 Playback routing

`PlaybackEngine` resolves an asset to a playback URL via:

```
if globalToggle == .off || override == .alwaysOriginal || proxyStatus != .ready {
    return originalURL
} else {
    return proxyURL!
}
```

Swap is atomic at seek boundaries — never mid-frame. The playback engine exposes a `usingProxy: Bool` on its current-state stream for the UI (§10.9.6).

#### 10.9.5 Export routing

**Export always uses originals.** `ExportEngine` explicitly ignores `proxyURL` and reads `originalURL`. If the original is missing (cloud-only placeholder, user-deleted, moved), the export surfaces a blocking error and drops into the media-relink flow (§3.4 / F6-16).

#### 10.9.6 UI surfaces

- **App Settings › Proxies** (subsection of §9.14 App Settings): master toggle, threshold picker (Off / ≥1080p / ≥4K / Always), cap selector (1 / 5 / 20 GB / Unlimited), live disk-usage readout, **Clear all proxies** destructive action.
- **Clip tile indicator**: small tertiary-text **PXY** chip in bottom-left of the clip tile when playback is currently resolving to a proxy. Invisible during export.
- **Inspector row** (iPad, video-clip selected): **Use proxy** — segmented (Follow project / Always on / Always off / Regenerate).
- **Import pill** (F6-8 extension): secondary line during proxy generation, e.g., *"Generating 2 proxies · 62%"*.
- **Per-clip proxy progress**: thin amber bar along the clip tile bottom while its proxy is generating; lock icon while busy.
- **Storage warning**: when disk cap hits 80%, a non-blocking toast with **Manage…** action opens App Settings › Proxies.

#### 10.9.7 Storage management

- Cap enforces LRU eviction (oldest-accessed proxies go first).
- System low-storage notification triggers aggressive eviction (drop usage to 50% of cap).
- **Clear all proxies** is destructive and confirmed (§9.10). After clearing, next playback uses originals until proxies regenerate lazily on demand.

#### 10.9.8 Performance targets

- Proxy generation runs on a **low-QoS** queue; must not block main and must not degrade the 60 FPS / <2ms cached-scrub budget.
- Scrubbing with proxy active: **<2ms cached / <20ms uncached** (tighter than originals — decode is cheaper).
- The UI never blocks waiting on a proxy. If a proxy isn't ready when playback starts, the original is used and the UI swaps silently once the proxy arrives at the next seek boundary.

#### 10.9.9 Accessibility

- **PXY** chip: `.accessibilityLabel("Playing with proxy")` + `.accessibilityHint("Export will use full-resolution original")`.
- Proxy-generation progress announced via VoiceOver at 10% intervals only (not every frame).
- Clear-all-proxies action has a confirmation dialog (per §9.10) with an explicit "this will not affect your videos" reassurance line.

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
- **Proxy pipeline (§10.9):** `ProxyService` (orchestrator), `ProxyGenerator` (actor running `AVAssetExportSession`), `ProxyStorageManager` (disk quota + LRU eviction), `ProxyStatusView` (clip-tile PXY chip + progress bar).
- **Clip operations (§7.10–7.12):** `ClipGroupView` (bracket + label + breadcrumb + nesting), `CustomExportPresetEditor` (full form + save-as + validation + live estimate), `TransformControls` (flip / rotate / crop / blend), `AudioPanControl`, `AudioNormalizePanel`, `TimelineOpsRegistry` (keyboard + context-menu + toolbar command registry).
- **Advanced clip operations (§7.13–7.18):** `CompoundClipShell` (internal timeline entry/exit + breadcrumb + render cache), `SourceMonitor` (second preview surface + IN/OUT + J/K/L), `ThreePointEditCommands` (insert/overwrite/3-point/4-point/replace), `MatchFrameAction`, `LinkGroupIndicator` (underline + glyph + ripple traversal), `ClipMarkerLayer` (pip rendering + label pop-over + color palette), `AudioEffectsShelf` (Reverb / Delay / Compression / Gate / Limiter).
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
