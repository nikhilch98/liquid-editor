# LiquidEditor — Premium UI Redesign Task Backlog

**Spec:** `docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md`
**Created:** 2026-04-18
**Scheduling model:** Jira-style backlog — every task has an ID, size estimate, explicit upstream dependencies, and a target parallel stream. Tasks with no unresolved dependencies can start immediately.

---

## Legend

- **Size:** S (≤0.5 day) · M (1–2 days) · L (3–5 days) · XL (1–2 weeks)
- **Status:** `○ todo` · `◔ in-progress` · `● done` · `⧸ blocked`
- **Stream:** A–G — each is an independent work lane owned by one engineer. See §4 for assignments.
- **Depends:** upstream task IDs. Task is blocked until all listed dependencies are `● done`.
- **Spec:** section references into the design spec.

---

## 1. Summary & Critical Path

- **Epics:** 17 (Epic 0 Decisions → Epic 16 iPad Platform Extras).
- **Tasks:** 266 total.
- **Total estimated effort:** ~355 engineer-days.
- **Revision 2 (2026-04-18):** 142 → 174 (added domain models + iPad extras + export presets/destinations + creative engines + library CRUD + timeline extras + platform foundation).
- **Revision 3 (2026-04-18):** 174 → 208 after paragraph-by-paragraph spec audit. Added: Editor chrome buttons (project chip dropdown, app Settings, avatar menu, You tab, Drafts, New Project flow), preview gestures (pinch/pan/double-tap/overlays), compute engines behind specced UI (chroma key compute, curves/HSL pipelines, stabilization algorithms, dialog detection, speed-bake, .cube parser), per-clip data models for tracking + mask, timeline execution logic (Slip/Roll/Slide, multi-clip batch ops, track reordering, add/remove track, clip clipboard, Properties view), library search + URL import, content tasks (LUT library + font management), polish (effect-stack reorder, caption export SRT/VTT, export cancel cleanup, global snap settings, custom color picker).
- **Revision 4 (2026-04-18):** 208 → 218 after adding Proxy Rendering Pipeline (spec §10.9): `ProxyService` orchestrator, `ProxyGenerator` actor, storage manager with LRU, playback routing (proxy for preview, original for export), UI surfaces (PXY clip chip, App Settings Proxies section, Inspector per-clip override, import pill secondary line), and testing.
- **Revision 5 (2026-04-18):** 218 → 244 after adding timeline operations + custom export editor + clip grouping. Spec gains §5.6 Custom Export Preset Editor, §7.10 Clip Grouping / Compound Clips, §7.11 Timeline Operations Catalog, §7.12 Per-Clip Transform & Blend. Tasks added: custom preset editor, clip grouping + nesting, clip nudge, z-order (front/back), blend modes, select-all helpers, insert/overwrite mode, cut, collapse-gap, flip H/V, quick rotate, crop, auto-follow playhead, zoom-to-fit/selection, audio pan, audio normalize, new data models + inspector rows + keyboard shortcuts.
- **Revision 6 (2026-04-18):** 244 → 266 after adding true compound clips, source-monitor 3-point editing, match-frame, link/unlink, clip-level markers, and additional audio effects. Spec gains §7.13 True Compound Clips, §7.14 Source Monitor + 3/4-point Editing, §7.15 Match Frame, §7.16 Link/Unlink Clips, §7.17 Clip-Level Markers, §7.18 Additional Audio Effects (Reverb / Delay / Compression / Gate / Limiter). Tasks added: compound-clip render + shell, source monitor + 3/4-point commands, match-frame, link-group auto + manual + ripple traversal, clip markers (add/pip/label/navigate), five audio-effect panels + audio DSP chain, four new data models, inspector rows, keyboard shortcuts.
- **With 4 parallel streams:** critical path is **~7 weeks** (35 working days).
- **With 2 parallel streams:** ~10–12 weeks.

**Critical path (longest dependency chain):**

```
D0-1 (tracking engine decision)
  → P1-11 (audio waveform primitive)  [engine-independent, parallel]
  → E4-5 (Tracking Overlay)           [XL, blocked by D0-1]
  → E4-9 (Chroma Key refine flow)      [depends on Mask + Tracking]
  → I14-2 (end-to-end smoke)
```

Tracking-engine resolution (D0-1) is the single biggest schedule risk: resolving it on day 1 vs. day 10 slides the critical path by the same number of days.

---

## 2. Dependency Graph (high-level)

```
      ┌─▶ Epic 1: Shared Primitives ─┬─▶ Epic 2: Screen Skeletons ─▶ Epic 3: Tab Wiring ─┐
      │                               │                                                   │
Epic 0: ┤                               ├─▶ Epic 4: Deep Tools ─────┐                            │
Decisions                               ├─▶ Epic 5: Creative Panels ─┤                            │
+ Tokens                                ├─▶ Epic 6: Supporting Flows┤                            │
                                        ├─▶ Epic 7: Timeline Core ──┤                            │
                                        └─▶ Epic 8: Small Tools ────┤                            │
                                                                     │                            │
                                                  Epic 9: Inspector ─┤                            │
                                                                     │                            │
                                                                     ▼                            ▼
                                                           Epic 10: A11y Pass ─────▶ Epic 12: Perf ──▶ Epic 13: Tests ──▶ Epic 14: Integration
                                                           Epic 11: Keyboard ─────┘
```

---

## 3. Phase Plan (time-ordered)

| Phase | Weeks | Parallel Streams Active | Goal |
|---|---|---|---|
| **Phase 0** | 0–1 | A (decisions + tokens) | Unblock all dependent work |
| **Phase 1** | 1–2 | A, B, C, D, E (shared primitives + skeletons) | Platform ready for feature work |
| **Phase 2** | 2–4 | B, C, D, E, F (deep tools + creative panels + supporting flows in parallel) | Feature surface complete |
| **Phase 3** | 4–5 | B, C, D, E (tab wiring + timeline core + inspector sections) | End-to-end flows working |
| **Phase 4** | 5–6 | A, G (a11y + keyboard + performance + tests) | Quality bar |
| **Phase 5** | 6–7 | All (integration + polish + docs) | Ship-ready |

---

## 4. Stream Assignments (4-engineer plan)

| Stream | Owner | Primary focus | Epics |
|---|---|---|---|
| **A** | Platform lead | Decisions, tokens, shared primitives, a11y, keyboard, perf, integration | 0, 1, 10, 11, 12, 14 |
| **B** | Editor lead | Editor screen, deep tools, timeline core | 2.Editor, 4, 7 |
| **C** | Library/Export lead | Library, Export, Project Settings, supporting flows | 2.Library, 2.Export, 6 |
| **D** | Creative lead | Tabs, creative panels, small tools, inspector | 3, 5, 8, 9 |
| **E** | Media/capture lead (rotates into tests late) | Media picker, VO, captions, capture, onboarding, tests | 6 subset, 13 |

If only **2 engineers** are available, collapse A+D into one stream ("platform+creative") and B+C+E into another ("features").

---

## 5. Task Table

### Epic 0 — Decisions & Foundation (UNBLOCKS EVERYTHING)

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| D0-1 | Decide tracking engine: `VNDetectObjectRequest` vs. custom point tracker; lock ship-in-v1 track types | S | — | §12.1 | A | ○ |
| D0-2 | Decide .cube LUT import in v1 | S | — | §12.2 | A | ○ |
| D0-3 | Decide STT vendor: `SFSpeechRecognizer` on-device vs. cloud | S | — | §12.3 | A | ○ |
| D0-4 | Decide snapshot retention policy (count + aging cadence) | S | — | §12.4 | A | ○ |
| D0-5 | Decide ripple-delete default (on/off) | S | — | §12.5 | A | ○ |
| D0-6 | Decide iPhone landscape editor in v1 (ship / defer) | S | — | §12.6 | A | ○ |
| F0-1 | Audit `LiquidColors.swift` vs. §2.1 table; add `Canvas.elev`, `Accent.success`, `Accent.warning`; verify `amberGlow`, `destructive`, `Timeline.*` | M | — | §2.1, §11.1 | A | ○ |
| F0-2 | Build `HapticService` wrapper honoring the §2.4 table + master toggle; inject via `ServiceContainer` | M | F0-1 | §2.4, §10.6 | A | ○ |
| F0-3 | Add `os_signpost` instrumentation for scrub / export / waveform / scope; surface to `PERFORMANCE.md` checklist | S | — | §10.7 | A | ○ |
| F0-4 | Audit `LiquidMotion.swift`: verify `snap`, `smooth`, `bounce`, `glide`, `reduced` exist; add any missing per §2.3 | S | — | §2.3 | A | ○ |
| F0-5 | Set `.preferredColorScheme(.dark)` at app root; purge any Light Mode assumptions from existing code | S | — | §2.8 | A | ○ |
| F0-6 | Per-screen orientation-lock infrastructure: `UIViewController`-host wrapper + SwiftUI modifier; Editor allows landscape, Library/Export portrait-only | M | — | §2.7 | A | ○ |
| F0-7 | Localization pipeline: `Localizable.xcstrings` + helper `L("…")`; all user-facing strings use `String(localized:)` | M | — | global | A | ○ |
| F0-8 | Launch screen + status-bar appearance (dark canvas, amber accent mark) | S | F0-5 | global | A | ○ |
| F0-9 | App-level **Settings screen** (distinct from Project Settings): default export preset, haptics master toggle, analytics opt-in, show-welcome-tour, about/licenses/credits, diagnostics | M | F0-2 | §9.12, §10.6 | A | ○ |
| F0-10 | **Proxy defaults config**: feature flag + baked defaults (threshold > 1080p, 720p H.264 5 Mbps, 5 GB cap) wired into `ServiceContainer` | S | — | §10.9.1 | A | ○ |

### Epic 1 — Shared Primitives

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| P1-1 | `ContextSubPanel` container: amber-bordered, caret-pointed, slide-up with dismiss | M | F0-1 | §2.5, §6 | A | ○ |
| P1-2 | `InspectorPanel` shell with section slot API (iPad right-rail / iPhone landscape top-right) | M | F0-1 | §3.3, §10.2 | A | ○ |
| P1-3 | `ToolRail` (vertical, 6 slots, long-press-to-customize) | M | F0-1 | §3.3, §10.4 | A | ○ |
| P1-4 | `MediaBrowser` (iPad left-rail tabbed container) | M | F0-1 | §3.3 | A | ○ |
| P1-5 | `GlassContextMenu` (long-press floating menu w/ sections + kb-shortcut slot) | M | F0-1 | §9.4 | A | ○ |
| P1-6 | `ToastHost` + delete-with-undo pattern; 2-slot stack, swipe-to-dismiss | M | F0-1 | §9.9 | A | ○ |
| P1-7 | `SkeletonModifier` (shimmer + Reduce-Motion static fallback) | S | F0-1 | §9.11 | A | ○ |
| P1-8 | `EmptyStateView` (hero-glyph + title + subtitle + primary CTA + escape-hatch link) | S | F0-1 | §9.6 | A | ○ |
| P1-9 | `KeyboardShortcutProvider` root view (registers `UIKeyCommand`s from a registry) | M | F0-1 | §10.5 | A | ○ |
| P1-10 | `ColorWheelControl` primitive (conic disc + puck + luma slider + numeric readout) | M | F0-1 | §8.5 | D | ○ |
| P1-11 | `AudioWaveformView` + LRU cache (peak+RMS precompute, tile renderer, `CGImage` cache) | L | F0-1 | §10.8 | B | ○ |
| P1-12 | `BeatMarkerLayer` + `ChapterMarkerLayer` + shared tap/long-press behavior | M | F0-1 | §7.6, §10.3 | B | ○ |
| P1-13 | `RippleEditController` — central handler for ripple vs. non-ripple edits | M | D0-5 | §10.3 | B | ○ |
| P1-14 | Standardize `ConfirmationDialog` pattern (title / destructive action / cancel / iPad-anchor / iPhone-sheet) | S | F0-1 | §9.10 | A | ○ |
| P1-15 | `PermissionPrimerSheet` generic template (hero + rationale + grant + “not now”) | S | F0-1 | §9.13 | A | ○ |
| P1-16 | `SnapshotService`: capture thumbnail + diff-label at every committed edit; backing store for §9.8 history scrubber | L | D0-4 | §9.8 | A | ○ |
| P1-17 | **Custom color picker** (HSB + hex + eyedropper on preview + saved-colors row); used by Text §8.1, color swatches, chroma fill-behind | M | F0-1 | §8.1.2, §7.9 | A | ○ |

### Epic 2 — Screen Skeletons

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| S2-1 | Editor shell (iPhone portrait): chrome │ preview │ transport │ timeline │ sub-panel slot │ shelf | L | P1-1, P1-11, P1-12 | §3.1 | B | ○ |
| S2-2 | Editor shell (iPad landscape): chrome │ 3-panel │ transport │ timeline+rail | L | P1-2, P1-3, P1-4, P1-11 | §3.3 | B | ○ |
| S2-3 | Editor shell (iPhone landscape) — only if `D0-6 = ship` | M | D0-6, P1-2, P1-3 | §3.2 | B | ⧸ (pending D0-6) |
| S2-4 | Editor screen-state handling: empty / importing / analyzing / rendering / error variants | M | S2-1, S2-2 | §3.4 | B | ○ |
| S2-5 | Project Library (iPhone): logo + search + Recent rail + grid + FAB + tabs | M | P1-7, P1-8 | §4.1 | C | ○ |
| S2-6 | Project Library (iPad): sidebar + grid + sort + New-Project CTA | M | P1-7, P1-8 | §4.2 | C | ○ |
| S2-7 | Extend `ProjectCardView`: 4K/HDR/cloud/conflict/locked badges, numbered selection, loading/failed states | M | P1-7, P1-5 | §4.3, §4.4 | C | ○ |
| S2-8 | Export screen (iPhone): ring-preview + presets + steppers + toggles + sticky CTA | M | F0-1 | §5.2 | C | ○ |
| S2-9 | Export screen (iPad): left preview+meta, right settings, dest grid, full-width CTA | M | S2-8 | §5.3 | C | ○ |
| S2-10 | Export state model: idle / exporting / success / error / cancelled + success-sheet | L | S2-8 | §5.4 | C | ○ |
| S2-11 | Export queue pill + queue sheet | M | S2-10, P1-6 | §5.5 | C | ○ |
| S2-12 | Export preset definitions: Quick / Social / Pro / Custom → resolution / fps / format / bitrate mapping | S | S2-10 | §5.2, §5.3 | C | ○ |
| S2-13 | Export destination integrations: Photos (`PHPhotoLibrary`), Files (`UIDocumentPicker`), AirDrop / Share (`UIActivityViewController`) | L | S2-10 | §5.3 | C | ○ |
| S2-14 | Live size + bitrate estimator (drives CTA label, meta card on iPad); recomputes on every preset/toggle change | M | S2-10, S2-12 | §5.3 | C | ○ |
| S2-15 | Export error log + “Copy log” action (pasteboard) | S | S2-10 | §5.4 | C | ○ |
| S2-16 | Background export: `BGProcessingTaskRequest` + `UNUserNotificationCenter` for completion toast when backgrounded | L | S2-10 | §5.5 | C | ○ |
| S2-17 | Library template system: seeded `Template` model + Templates tab feed + “New from template” flow | L | S2-5, S2-6 | §4.1, §4.2 | C | ○ |
| S2-18 | **New-Project creation flow**: FAB / “+ New Project” → aspect-ratio picker (9:16, 16:9, 1:1, 4:5, custom) + resolution + frame-rate + optional template → initial timeline | M | S2-5, S2-6, M15-5 | §4.1, §4.2 | C | ○ |
| S2-19 | **Project chip dropdown** in editor chrome (name ▾): Properties / Rename / Switch project / Close editor | S | S2-1, F6-4, F6-10 | §3.1 | B | ○ |
| S2-20 | **Drafts** concept: auto-save in-progress work every 30s; Drafts tab feed; commit-to-project action | M | S2-5, S2-6, P1-16 | §4.1, §4.2 | C | ○ |
| S2-21 | **“You” tab** (iPhone bottom): profile header + links to App Settings (F0-9) + About + subscription status + sign-in (if any) | M | S2-5, F0-9 | §4.1 | C | ○ |
| S2-22 | **Avatar menu** in Library header (iPhone + iPad): quick access to App Settings, sign out, about | S | S2-5, S2-6, F0-9 | §4.1, §4.2 | C | ○ |
| S2-23 | Export cancel-mid-render cleanup: stop `AVAssetExportSession`, delete partial output, reset queue entry, clear error log | S | S2-10 | §5.4 | C | ○ |
| S2-24 | **App Settings › Proxies** section: master toggle, threshold picker (Off/≥1080p/≥4K/Always), cap selector (1/5/20 GB/Unlimited), live disk-usage readout, destructive **Clear all proxies** | M | F0-9, PP12-8, PP12-11 | §10.9.6 | A | ○ |
| S2-25 | **Custom Export Preset Editor**: full-form UI (Video/Audio/Color/Advanced sections), named-preset save/edit/delete, validation banner for invalid combos, live size estimator reuse (S2-14), saved-presets list in preset segmented | XL | S2-10, S2-12, S2-14, M15-9 | §5.6 | C | ○ |

### Epic 3 — Editor Tab Wiring

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| T3-1 | Tab bar selection + tool-strip swap + haptic on tab switch | M | S2-1, F0-2 | §6 | D | ○ |
| T3-2 | Edit tab strip + wiring (Split / Trim / Speed / Volume / ⋯) | M | T3-1, E4-1, E4-2, E4-3, E4-4, TD8-1 | §6.1 | D | ○ |
| T3-3 | Audio tab strip + wiring (Music / SFX / Record / Extract / Volume / Beat / EQ / Pitch / Auto-mix) | M | T3-1, E4-6, E4-7, F6-2, TD8-1..6 | §6.2 | D | ○ |
| T3-4 | Text tab strip + wiring (Text / Captions / Sticker / Preset / Font…) | M | T3-1, C5-1, F6-3, TD8-7..8 | §6.3 | D | ○ |
| T3-5 | FX tab strip + wiring (Filter / Transition / Effect / Stabilize / Chroma / Mask / Tracking / Mirror / Freeze / Cutout) | M | T3-1, E4-4, E4-5, E4-8, E4-9, C5-3, C5-4, TD8-9..10 | §6.4 | D | ○ |
| T3-6 | Color tab strip + wiring (Preset / LUT / Wheels / Curves / HSL / Scopes / dual sliders) | M | T3-1, C5-5, C5-6, C5-7, C5-8, C5-9, TD8-11..12 | §6.5 | D | ○ |

### Epic 4 — Editor Deep Tools

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| E4-1 | **Speed Ramp Sheet** (presets + curve canvas + thumb strip + preserve-pitch) | L | P1-1 | §7.1 | B | ○ |
| E4-2 | **Keyframe Lane** inline panel (4 property lanes + markers + +/−/shuttle + ease picker) | L | P1-1 | §7.2 | B | ○ |
| E4-3 | **Trim Precision View** (frame strip + amber handles + IN/OUT + shuttle + Ripple/Snap toggles + pro Roll/Slip/Slide on iPad) | L | P1-1, P1-13 | §7.3 | B | ○ |
| E4-4 | **Mask Editor** (shapes + handles + feather + expand + invert + Pencil freehand + "Track to subject" hook) | L | P1-1 | §7.5 | B | ○ |
| E4-5 | **Motion Tracking Overlay** + state model (Idle→Analyzing→Complete→Failed→Cancelled) | XL | D0-1, P1-1 | §7.4, §7.4.1 | B | ⧸ (pending D0-1) |
| E4-6 | **Beat Detect** analysis + marker placement + BPM readout + "Snap edits to beats" toggle | L | P1-12 | §7.6 | B | ○ |
| E4-7 | **Auto-Mix** dialog-ducking + post-run toast + iPad advanced sliders | M | P1-6 | §7.7 | B | ○ |
| E4-8 | **Stabilize Panel** (Analyze/Re-analyze + Strength + Method chips + Crop toggle + before/after preview) | L | P1-1 | §7.8 | B | ○ |
| E4-9 | **Chroma Key View** (eyedropper + tolerance/softness/spill/edge + alpha/holdout/fill toggles + Refine→Mask) | L | E4-4, P1-1, C5-14 | §7.9 | B | ○ |
| E4-10 | **Motion-track data model** on clip: stored per-frame or sparse keyframes with smoothing + transform targets; `Codable`; drives applied tracking at render | M | — | §7.4 | B | ○ |
| E4-11 | **Mask data model** on clip: shape type (rect/ellipse/rounded/star/freehand path), feather/opacity/expand, animate toggle, per-frame keyframes; `Codable` | M | M15-3 | §7.5 | B | ○ |
| E4-12 | **Speed-curve bake renderer**: when ramp exceeds real-time decode, background-bake a baked clip with progress UI (reuses clip-render queue pattern) | L | E4-1 | §7.1, §3.4 | B | ○ |
| E4-13 | **Source Monitor + Three/Four-Point Editing**: second preview surface; IN/OUT markers on source + destination; Insert / Overwrite / 3-point / 4-point / Replace commands; J/K/L shuttle; iPad docked, iPhone sheet variant | XL | S2-2, M15-10 | §7.14 | B | ○ |
| E4-14 | **Match Frame** action + reverse-direction variant (source-browser → timeline) | S | E4-13 | §7.15 | B | ○ |
| E4-15 | **Compound Clip shell**: enter/exit + breadcrumb + internal timeline view; render-cache invalidation on descendant edit; background re-render | XL | M15-10, T7-24 | §7.13 | B | ○ |
| E4-16 | **Link/Unlink indicator + gesture**: amber underline + 🔗 glyph; ripple traversal; `⌥`-drag override to move one member without link | M | M15-11 | §7.16 | B | ○ |

### Epic 5 — Creative Panels

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| C5-1 | **Text Editor Sheet** (text input + font pills + size + swatches + sub-tabs Text/Effects/Anim/Align + bbox w/ 6 resize + rotate handle) | L | P1-1, P1-2 | §8.1 | D | ○ |
| C5-2 | Text Animation presets library (13 presets per §8.1.3) | M | C5-1 | §8.1.3 | D | ○ |
| C5-3 | **Transition Picker Sheet** (two-clip stage + duration + 5 categories + 4×2 grid + apply-to-all) | M | P1-1 | §8.2 | D | ○ |
| C5-4 | **FX Browser Sheet** (applied stack + 5 categories + 3×3 live-preview grid + intensity slider) | L | P1-1 | §8.3 | D | ○ |
| C5-5 | **LUT Picker Sheet** (split/A/B compare + categories + 3×3 grid + intensity); add .cube importer if D0-2=yes | L | P1-1, D0-2 | §8.4 | D | ○ |
| C5-6 | **Color Wheels Panel** (3 wheels + Temp/Tint/Sat dual-gradient sliders) | L | P1-10 | §8.5 | D | ○ |
| C5-7 | **Curves Editor** (channel seg + interactive canvas + presets + mini histogram overlay + Pencil support) | L | P1-1 | §8.6 | D | ○ |
| C5-8 | **HSL Panel** (8 channel chips + H/S/L gradient sliders + eyedropper) | M | P1-1 | §8.7 | D | ○ |
| C5-9 | **Scopes Panel** (Waveform / Histogram / Vectorscope / RGB Parade; 30 Hz sampling; iPad dock-or-float) | L | F0-3, C5-12 | §8.8 | D | ○ |
| C5-10 | **Transition shader/animation implementations** (Fade / Dissolve / Zoom / Slide-L / Slide-R / Flip / Spin / Glitch / Morph) — Metal shaders or `AVMutableVideoCompositionInstruction` | L | — | §8.2 | D | ○ |
| C5-11 | **Individual FX implementations** (Glitch / Zoom-blur / Mirror / Prism / VHS / Bokeh / Shake / Neon / Chroma hue-shift) — Metal + CIFilter chains | XL | — | §8.3 | D | ○ |
| C5-12 | **Scope compute engines**: luma-waveform, RGB histogram, vectorscope (I/Q polar), RGB parade; sampled via `ColorGradingPipeline` taps | L | F0-3 | §8.8, §10.7 | D | ○ |
| C5-13 | **.cube LUT parser** + validator + error messaging (invalid dimension / out-of-range) — ships only if D0-2 = yes | M | D0-2 | §8.4 | D | ⧸ (pending D0-2) |
| C5-14 | **Chroma key compute**: Metal shader or CIFilter chain implementing key/tolerance/softness/spill/edge-thin in one pass | L | — | §7.9 | B | ○ |
| C5-15 | **Curves rendering pipeline**: extend `ColorGradingPipeline` to apply per-channel LUT derived from curve points (Luma/R/G/B) | M | — | §8.6 | D | ○ |
| C5-16 | **HSL rendering pipeline**: extend `ColorGradingPipeline` with 8-channel HSL shift; per-pixel hue-range masking | M | — | §8.7 | D | ○ |
| C5-17 | **Stabilization algorithms**: Cinema (VNTranslationalImageRegistrationRequest or Vision), Handheld (point-feature + smoothing), Fast (single-frame crop) | L | — | §7.8 | B | ○ |
| C5-18 | **Dialog detection service** (for Auto-Mix §7.7): analyze audio to identify speech segments; feed into duck envelope generator | L | — | §7.7 | B | ○ |
| C5-19 | **Effect-stack drag-to-reorder** inside FX Browser applied-stack list | S | C5-4, M15-1 | §8.3 | D | ○ |
| C5-20 | **Bundled LUT content**: 10–20 royalty-free .cube LUTs shipping with the app, categorized (Cinematic/Film/Vintage/B&W) | M | C5-13 (optional) | §8.4 | D | ○ |
| C5-21 | **Font management**: curated bundled fonts (SF Pro families + 4–6 display / serif / mono / rounded) + custom font import via `CTFontManagerRegisterFontsForURL` | M | F0-1 | §8.1 | D | ○ |
| C5-22 | **Reverb** sub-panel: preset chips (Room / Hall / Cathedral / Plate / Spring) + Size / Decay / Pre-delay / Mix sliders + bypass + wet/dry | M | M15-13, PP12-13 | §7.18 | D | ○ |
| C5-23 | **Delay** sub-panel: Time / Feedback / Mix sliders + **Sync to beat** toggle (reads project BPM from E4-6) | M | M15-13, PP12-13 | §7.18 | D | ○ |
| C5-24 | **Compression** sub-panel: Threshold / Ratio / Attack / Release / Makeup gain + gain-reduction meter | M | M15-13, PP12-13 | §7.18 | D | ○ |
| C5-25 | **Gate** sub-panel: Threshold / Attack / Hold / Release | S | M15-13, PP12-13 | §7.18 | D | ○ |
| C5-26 | **Limiter** sub-panel: Ceiling + Auto-release toggle + output-peak meter | S | M15-13, PP12-13 | §7.18 | D | ○ |

### Epic 6 — Supporting Flows

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| F6-1 | **Media Picker Sheet** (source tabs + filter chips + album dropdown + 3-col grid + numbered select + sticky Add CTA + all states) | L | P1-7, P1-8, P1-15 | §9.1, §9.6 | E | ○ |
| F6-2 | **Voice-over Modal** + 6-state machine (Idle→Armed→Recording→Review→Saving→Saved) + punch-in | L | P1-15, F0-2 | §9.2 | E | ○ |
| F6-3 | **Auto-Captions Review** + STT integration + 5-state machine; language picker; templates; edit/split/merge/delete | XL | D0-3, P1-7 | §9.3 | E | ⧸ (pending D0-3) |
| F6-4 | **Project Settings Sheet** (header card + Canvas/Color/Audio groups + snapshots entry + Delete) | M | P1-1, P1-14 | §9.5 | C | ○ |
| F6-5 | **Camera Capture View** (viewfinder + mode switch + controls + zoom strip + post-capture confirm) | L | P1-15 | §9.7 | E | ○ |
| F6-6 | **Undo History Scrubber** (horizontal snapshot timeline + preview + Restore / Branch) | L | D0-4, F6-4 | §9.8 | C | ⧸ (pending D0-4) |
| F6-7 | **Onboarding Sheet** (3 pages + permission primers + skip + re-entry) | M | P1-15 | §9.12 | E | ○ |
| F6-8 | **Global import progress pill** + expanded per-item sheet | M | P1-6 | §9.7 | E | ○ |
| F6-9 | Permission flows wiring (Photos limited + Mic + Camera + Notifications + Files) | M | P1-15 | §9.13 | E | ○ |
| F6-10 | Project rename flow (inline on card via long-press → sheet; inline header in Project Settings) | M | S2-7, F6-4 | §4.4, §9.5 | C | ○ |
| F6-11 | Project duplicate logic: deep-copy timeline + assets + grade/effect stacks; new ID; “… copy” name | M | M15-1, M15-2, M15-3 | §4.4 | C | ○ |
| F6-12 | Project share sheet wiring: share project file or last-export via `UIActivityViewController` | S | — | §4.4 | C | ○ |
| F6-13 | Collections CRUD + move-to-collection action (sidebar list + assign card to collection) | M | S2-6 | §4.2, §4.4 | C | ○ |
| F6-14 | Starred / favorite projects: star toggle on card context menu + sidebar filter | S | S2-7 | §4.2 | C | ○ |
| F6-15 | Trash flow: 30-day soft-delete retention + Restore + Empty Trash (destructive + confirmation) | M | P1-14 | §4.2, §9.10 | C | ○ |
| F6-16 | Media relink flow: detect missing assets on project open; Inspector row “Locate…” → file picker | M | S2-4 | §3.4 | C | ○ |
| F6-17 | **URL import flow**: paste-link sheet in Import tiles → validate URL → download with progress toast (via F6-8) → emit clip | M | F6-8 | §9.7 | E | ○ |
| F6-18 | **Library search implementation**: name match + date filter + tag-filter; debounced; empty/no-results states from P1-8 | M | S2-5, S2-6, P1-7 | §4.1 | C | ○ |
| F6-19 | **Caption export** as SRT + VTT sidecar: when captions exist, Export destination also writes `.srt` + `.vtt` next to the video | M | F6-3, S2-13 | §9.3 | E | ○ |
| F6-20 | **Proxy generation progress UI**: secondary line on the F6-8 import pill (“Generating 2 proxies · 62%”) + thin amber bar on each clip tile while its proxy generates + non-blocking fallback toast on failure | M | F6-8, PP12-8, PP12-9 | §10.9.3, §10.9.6 | E | ○ |

### Epic 7 — Timeline Core Enhancements

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| T7-1 | Gestures: tap / double-tap / long-press + haptic feedback | M | S2-1, F0-2 | §10.3 | B | ○ |
| T7-2 | Pinch-to-zoom w/ 6 snap stops + two-finger pan | M | S2-1 | §10.3 | B | ○ |
| T7-3 | Drag-to-reorder + cross-track drop + shadow/scale lift animation | L | S2-1 | §10.3 | B | ○ |
| T7-4 | Clip-edge trim drag + snap-to-playhead + snap-to-beat (haptic) | M | S2-1, P1-12 | §10.3 | B | ○ |
| T7-5 | Lasso multi-select + shift-tap add-to-selection (iPad) | M | S2-1 | §10.3 | B | ○ |
| T7-6 | Drag from Media Browser to timeline (drop-target highlight) | M | S2-2, F6-1 | §10.3 | B | ○ |
| T7-7 | Ripple delete wired through `RippleEditController` | S | P1-13 | §10.3 | B | ○ |
| T7-8 | Track collapse/expand swipe | S | S2-1 | §10.3 | B | ○ |
| T7-9 | Scrub-with-audio toggle + playhead-drag behavior | S | S2-1 | §10.3 | B | ○ |
| T7-10 | Track mute + lock toggles on track header | S | S2-1 | §3.1, §10.3 | B | ○ |
| T7-11 | Track header long-press menu (Rename / Mute all / Lock / Delete track) | S | P1-5, T7-10 | §10.3 | B | ○ |
| T7-12 | Fullscreen preview mode (F key / ⛶ button; pinch-zoom + pan + swipe-down dismiss) | M | S2-1 | §3.1, §10.5 | B | ○ |
| T7-13 | Preserve existing Comparison mode toggle in both fullscreen + inline preview | S | T7-12 | existing feature | B | ○ |
| T7-14 | **Clip clipboard**: copy/paste clip + inherited effect stack / grade / keyframes; cross-project paste supported | M | M15-1, M15-2, M15-3 | §6.1 | B | ○ |
| T7-15 | **Multi-clip batch operations**: delete / duplicate / move / apply-effect / set-speed to selection from T7-5 lasso + shift-tap | M | T7-5 | §10.3 | B | ○ |
| T7-16 | **Vertical track reordering**: drag track header up/down to reorder tracks | M | S2-1 | §10.3 | B | ○ |
| T7-17 | **Add / remove track** action: insert new video / audio / text / caption track at chosen position; removing confirms if non-empty | M | S2-1, P1-14 | §10.3 | B | ○ |
| T7-18 | **Slip / Roll / Slide** edit execution: timeline operations backing the pro-edit chips in Trim Precision (E4-3) | L | E4-3 | §7.3 | B | ○ |
| T7-19 | **Clip Properties view** (from context menu “Properties”): metadata display (codec, resolution, fps, color space, duration, file path, bitrate) | S | S2-1 | §6.1 | B | ○ |
| T7-20 | **Global snap settings panel** (gear in transport row): toggles for snap-to-playhead, snap-to-beat, snap-to-marker, snap-to-grid | S | S2-1 | §10.3 | B | ○ |
| T7-21 | **Preview pinch-zoom (1×–5×) + pan-when-zoomed**: gesture handlers on preview surface; reset via double-tap | M | S2-1 | §3.1 | B | ○ |
| T7-22 | **Preview double-tap zoom** toggle (zoom-fit ↔ zoom-fill) | S | T7-21 | §3.1 | B | ○ |
| T7-23 | **Preview overlay toggles** (grid / safe-zone / center cross / action-safe); toggled from overflow in preview chrome; persisted per-project | S | S2-1, M15-5 | existing feature + §3.1 | B | ○ |
| T7-24 | **Clip grouping / compound clips**: Group (⌘G) + Ungroup (⇧⌘G), amber bracket + label, enter/exit via double-tap / Esc, nested groups up to 5 levels; move/trim/delete as unit | L | M15-7 | §7.10 | B | ○ |
| T7-25 | **Clip nudge by arrow keys**: ⌥← / ⌥→ ±1 frame on selected clip(s); ⌥⇧← / ⌥⇧→ ±1 second | S | T7-5 | §7.11, §10.5 | B | ○ |
| T7-26 | **Z-order on overlay tracks**: Bring-to-front / Send-to-back context actions; handles overlapping overlay clips | S | S2-1 | §7.11 | B | ○ |
| T7-27 | **Blend modes per clip**: Normal / Multiply / Screen / Overlay / Soft Light / Add / Subtract; applies only to overlay-track clips | M | M15-8 | §7.12 | B | ○ |
| T7-28 | **Select-all helpers**: Select all on track / at playhead / forward from playhead / backward from playhead; ⌘A shortcut | S | T7-5 | §7.11 | B | ○ |
| T7-29 | **Insert vs. Overwrite mode** toggle in transport row + `I` shortcut; Insert pushes existing clips forward, Overwrite replaces content under playhead | M | S2-1 | §7.11 | B | ○ |
| T7-30 | **Cut action** (⌘X): copy + remove; honors ripple setting (D0-5); places on clipboard for cross-project paste (T7-14) | S | T7-14, P1-13 | §7.11 | B | ○ |
| T7-31 | **Collapse gap**: context action on empty track region removes the gap and shifts following clips left | S | S2-1 | §7.11 | B | ○ |
| T7-32 | **Flip horizontal / Flip vertical**: one-tap toggles in Transform section / Edit tab | S | M15-8 | §7.12 | B | ○ |
| T7-33 | **Quick rotate**: 0° / 90° / 180° / 270° segmented in Transform section | S | M15-8 | §7.12 | B | ○ |
| T7-34 | **Crop tool**: rect crop (top/right/bottom/left numeric + drag-handle overlay on preview); distinct from Mask §7.5 | M | S2-1, M15-8 | §7.12 | B | ○ |
| T7-35 | **Auto-follow playhead** toggle in transport + Settings; when on, timeline auto-scrolls during playback to keep playhead in view | S | S2-1 | §7.11 | B | ○ |
| T7-36 | **Zoom to fit / Zoom to selection** actions (`\` / ⌘⇧0); smoothly animates timeline zoom + scroll | S | S2-1 | §7.11 | B | ○ |
| T7-37 | **Insert / Overwrite / 3-point / 4-point / Replace commands** wired to E4-13 Source Monitor; audio/video-only track scope toggles | L | E4-13, T7-29 | §7.14 | B | ○ |
| T7-38 | **Clip-level markers**: add via `M` when clip focused; pip rendering inside clip tile; label pop-over; 6 color swatches; drag-to-move within clip; `⌘←/→` prev/next navigation across all clips | M | M15-12, T7-1 | §7.17 | B | ○ |
| T7-39 | **Compound clip render**: flatten internal timeline through `MultiTrackCompositor` to single video+audio source; cache by `(compoundID, contentHash)`; invalidate on descendant commit | L | E4-15, M15-10 | §7.13 | B | ○ |
| T7-40 | **Compound-nesting perf guardrails**: warn banner at 10 levels; hard cap 20; disable further conversion when at cap | S | T7-39 | §7.13 | B | ○ |

### Epic 8 — Small Tools (leaf controls, highly parallel)

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| TD8-1 | Volume controls (dB slider + fade + Mute/Duck/Denoise chips) | S | P1-1 | §6.1–6.2 | D | ○ |
| TD8-2 | Music library browser sheet | M | F6-1 | §6.2 | D | ○ |
| TD8-3 | SFX browser sheet (categorized + preview) | M | F6-1 | §6.2 | D | ○ |
| TD8-4 | Extract audio action + new-audio-clip emit | S | — | §6.2 | D | ○ |
| TD8-5 | EQ panel (3-band + presets) | M | P1-1 | §6.2 | D | ○ |
| TD8-6 | Pitch slider (±12 semitones) | S | P1-1 | §6.2 | D | ○ |
| TD8-7 | Sticker picker (emoji / shape / GIF tabs) | M | P1-1 | §6.3 | D | ○ |
| TD8-8 | Text preset gallery (animated title templates) | M | C5-1 | §6.3 | D | ○ |
| TD8-9 | Filter picker grid (live-preview + intensity) | M | C5-4 | §6.4 | D | ○ |
| TD8-10 | One-shot FX actions (Mirror / Freeze / Cutout) | S | — | §6.4 | D | ○ |
| TD8-11 | Color Preset grid (live-preview thumbs + apply) | M | C5-5 | §6.5 | D | ○ |
| TD8-12 | Temp/Tint/Exposure/Contrast/Highlights/Shadows/Sat/Vibrance dual-slider rows | M | P1-1 | §6.5 | D | ○ |
| TD8-13 | Reverse + Freeze-frame render actions + progress UI | M | S2-4 | §3.4, §6.1 | B | ○ |
| TD8-14 | Animation (in/out/loop) preset chips for clip animation tool | S | C5-2 | §6.1 | D | ○ |
| TD8-15 | Tool-rail customization sheet (“Edit rail…” long-press menu; pick 6 of N tools; per-project persistence) | M | P1-3, M15-5 | §10.4 | D | ○ |
| TD8-16 | **Audio pan control** — –1.0 (L) ↔ +1.0 (R) slider with center detent; per-audio-clip; Inspector-embedded | S | M15-8 | §7.12, §6.2 | D | ○ |
| TD8-17 | **Audio normalize** — target-LUFS chips (–16 / –14 / –23); clip-level peak+LUFS calc and gain application | M | M15-8 | §7.12, §6.2 | D | ○ |

### Epic 9 — Inspector Matrix (iPad right-rail sections)

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| IM9-1 | Inspector VM: `@Observable` projection over `EditorViewModel.selection`; computes `sections: [InspectorSection]` | M | P1-2 | §11.4 | D | ○ |
| IM9-2 | Section: Clip header (name + duration + badges) | S | IM9-1 | §10.2 | D | ○ |
| IM9-3 | Section: Transform (position / scale / rotation) | S | IM9-1 | §10.2 | D | ○ |
| IM9-4 | Section: Speed (reuse Speed controls from E4-1) | S | IM9-1, E4-1 | §10.2 | D | ○ |
| IM9-5 | Section: Volume (reuse TD8-1) | S | IM9-1, TD8-1 | §10.2 | D | ○ |
| IM9-6 | Section: Opacity slider | S | IM9-1 | §10.2 | D | ○ |
| IM9-7 | Section: Text content + style (reuse C5-1 controls) | S | IM9-1, C5-1 | §10.2 | D | ○ |
| IM9-8 | Section: Caption style + language | S | IM9-1, F6-3 | §10.2 | D | ○ |
| IM9-9 | Section: Color grade (reuse C5-6/7/8 summary + expand) | S | IM9-1, C5-6 | §10.2 | D | ○ |
| IM9-10 | Section: Animation/keyframes (reuse E4-2) | S | IM9-1, E4-2 | §10.2 | D | ○ |
| IM9-11 | Section: Project meta (no selection) | S | IM9-1 | §10.2 | D | ○ |
| IM9-12 | Section: Playhead timecode + snap | S | IM9-1 | §10.2 | D | ○ |
| IM9-13 | Multi-select handling: show “Mixed” em-dash for inconsistent values | M | IM9-1 | §10.2 | D | ○ |
| IM9-14 | Section: **Clip Properties** (read-only metadata — codec / resolution / fps / color space / duration / path); replaces action sheet when accessed via inspector rather than context menu | S | IM9-1, T7-19 | §10.2, §6.1 | D | ○ |
| IM9-15 | Section: **Proxy controls** (video clip selected): `Use proxy` segmented — Follow project / Always on / Always off / Regenerate; status line (`ready` / `generating` / `failed`) | S | IM9-1, PP12-8 | §10.9.6 | D | ○ |
| IM9-16 | Section: **Blend mode** selector (video clip on overlay track): 7-option segmented | S | IM9-1, T7-27 | §10.2, §7.12 | D | ○ |
| IM9-17 | Section: **Flip + Quick Rotate + Crop** actions embedded in Transform section | S | IM9-3, T7-32, T7-33, T7-34 | §10.2, §7.12 | D | ○ |
| IM9-18 | Section: **Audio pan** slider (audio clip) | S | IM9-1, TD8-16 | §10.2, §7.12 | D | ○ |
| IM9-19 | Section: **Audio effects stack** (audio clip): Reverb / Delay / Compression / Gate / Limiter; drag-to-reorder; per-effect bypass + intensity | M | IM9-1, C5-22..C5-26 | §10.2, §7.18 | D | ○ |
| IM9-20 | Section: **Link Group** indicator + Link / Unlink action row (shows linked members + type sync/manual) | S | IM9-1, M15-11 | §10.2, §7.16 | D | ○ |
| IM9-21 | Section: **Clip Markers list** (audio/video clip): compact table of markers with color chip + label + timecode; tap to seek; swipe to delete | S | IM9-1, T7-38 | §10.2, §7.17 | D | ○ |

### Epic 10 — Accessibility Pass

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| A10-1 | VoiceOver labels sweep — all tools, chips, swatches, markers; templated via helpers | L | S2-1, S2-2, S2-5, S2-6, S2-8 | §10.6 | A | ○ |
| A10-2 | Custom “Clips” rotor on timeline | M | S2-1 | §10.6 | A | ○ |
| A10-3 | Dynamic Type: chip-row wrapping at XXL + tool-label hiding | M | P1-1 | §10.6 | A | ○ |
| A10-4 | Reduce Motion fallbacks across all springs / shimmers / lift animations | M | F0-2 | §2.3, §10.6 | A | ○ |
| A10-5 | Reduce Transparency fallbacks (glass → opaque Canvas.raised) | M | F0-1 | §2.3, §10.6 | A | ○ |
| A10-6 | Increase Contrast: stroke bumps + tertiary→secondary text promotion | S | F0-1 | §2.3, §10.6 | A | ○ |
| A10-7 | Switch/Voice Control: stable `accessibilityIdentifier` everywhere | M | A10-1 | §10.6 | A | ○ |
| A10-8 | AA contrast verification across amber on all surfaces; palette adjustments for failing cases | M | F0-1 | §10.6 | A | ○ |
| A10-9 | Accessibility-actions menus for multi-finger gestures (pinch, trim) | M | T7-2, T7-4 | §10.6 | A | ○ |
| A10-10 | Haptics master toggle in Settings → Accessibility | S | F0-2 | §2.4, §10.6 | A | ○ |
| A10-11 | Apple Pencil support verification for Mask freehand + Curves + text handles | M | E4-4, C5-7, C5-1 | §10.6 | A | ○ |
| A10-12 | **VoiceOver hints** (`accessibilityHint`) on complex controls: timeline clips ("double-tap to select, swipe up for actions"), transport buttons, gesture-heavy surfaces | M | A10-1 | §10.6 | A | ○ |

### Epic 11 — Keyboard Shortcuts (iPad)

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| K11-1 | Register playback shortcuts: Space, J/K/L shuttle | S | P1-9, S2-1 | §10.5 | A | ○ |
| K11-2 | Register edit shortcuts: ⌘S split, ⌘C/V/D, ⌦ delete, I/O mark, T trim-to-playhead | S | P1-9, T3-2 | §10.5 | A | ○ |
| K11-3 | Register nav shortcuts: ⌘Z/⇧Z undo/redo, ⌘+/− zoom, arrows ±1 frame / shift-arrows ±1s | S | P1-9 | §10.5 | A | ○ |
| K11-4 | Register modal shortcuts: Esc dismiss, F fullscreen, ⌘E export, ⌘N new, ⌘F search, ⇥ cycle tabs | S | P1-9 | §10.5 | A | ○ |
| K11-5 | Marker shortcut: M at playhead | S | P1-9, P1-12 | §10.5 | A | ○ |
| K11-6 | Hold-⌘ discoverability overlay population (group labels + all shortcuts) | S | K11-1..5 | §10.5 | A | ○ |
| K11-7 | **Clip-operation shortcuts**: ⌘A select-all-at-playhead, ⌘X cut, ⌘G / ⇧⌘G group/ungroup, ⌥←/→ nudge ±frame, ⌥⇧←/→ nudge ±sec, `\` zoom-fit, ⌘⇧0 zoom-selection, `I` toggle insert/overwrite | S | P1-9, T7-14, T7-24, T7-25, T7-29, T7-30, T7-36 | §10.5, §7.11 | A | ○ |
| K11-8 | **Source-monitor shortcuts**: J / K / L on source when focused; source `I` / `O` (IN/OUT); destination `⇧I` / `⇧O`; `,` insert, `.` overwrite, F9 3-point, F10 4-point, `N` replace | S | P1-9, E4-13 | §10.5, §7.14 | A | ○ |
| K11-9 | **Match frame + clip marker shortcuts**: `F` match frame, `M` add clip marker, `⌘←` / `⌘→` prev/next clip marker, `⌘⌥G` convert to compound, `⌘L` / `⇧⌘L` link/unlink | S | P1-9, E4-14, T7-38, E4-15, E4-16 | §10.5, §7.13–7.17 | A | ○ |

### Epic 12 — Performance

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| PP12-1 | `LazyVGrid` virtualization for Library + Media picker grids | M | S2-5, F6-1 | §10.7 | A | ○ |
| PP12-2 | Off-main thumbnail decode + LRU (100 Library, 200 Picker) | M | S2-7, F6-1 | §10.7 | A | ○ |
| PP12-3 | Audio waveform peak+RMS precompute on clip import; persisted sidecar | M | P1-11 | §10.7, §10.8 | A | ○ |
| PP12-4 | Tile-based timeline render (don’t re-layout full timeline on scroll) | L | S2-1 | §10.7 | B | ○ |
| PP12-5 | `CADisplayLink` for export ring animation (not SwiftUI `.animation`) | S | S2-10 | §10.7 | C | ○ |
| PP12-6 | Scopes throttling (30 Hz → 15 Hz on thermal pressure) | S | C5-9 | §10.7 | D | ○ |
| PP12-7 | Verify scrub budget <2ms cached / <50ms uncached + composition rebuild <20ms with Instruments | M | PP12-4 | §10.7 | A | ○ |
| PP12-8 | **`ProxyService`**: orchestrator — threshold evaluation on import, generation queue, proxy-cache registry, status-stream publication for UI | L | F0-10, M15-6 | §10.9.3, §10.9.4 | A | ○ |
| PP12-9 | **`ProxyGenerator`** actor: `AVAssetExportSession` 720p H.264 5 Mbps + frame-rate match + audio pass-through; `AsyncStream<Double>` progress; low-QoS dispatch | M | F0-10 | §10.9.3, §10.9.8 | A | ○ |
| PP12-10 | **Playback-engine proxy routing**: `PlaybackEngine` picks `proxyURL` vs. `originalURL` per policy; swap is atomic at seek boundaries; publishes `usingProxy` to UI | M | PP12-8 | §10.9.4 | A | ○ |
| PP12-11 | **`ProxyStorageManager`**: disk-quota enforcement + LRU eviction + system low-storage handler (drop to 50% cap); reports live disk-usage | M | PP12-8 | §10.9.7 | A | ○ |
| PP12-12 | **Clip-tile PXY chip** + per-clip proxy-progress bar (tertiary chip bottom-left when `usingProxy`; amber bar while generating) | S | PP12-10, F6-20 | §10.9.6 | B | ○ |
| PP12-13 | **Audio DSP pipeline extensions** for new effects: reverb IR conv (cached per preset), delay ring buffer, compressor envelope follower, gate & limiter state; integrate into existing `AudioEffectsEngine`; real-time capable in preview | L | M15-13 | §7.18, §10.7 | B | ○ |

### Epic 13 — Testing

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| TT13-1 | Snapshot tests: Editor (iPhone portrait + iPad landscape) × all states | L | S2-1, S2-2, S2-4 | §11.6 | E | ○ |
| TT13-2 | Snapshot tests: Library × states, Export × states | M | S2-5, S2-6, S2-10 | §11.6 | E | ○ |
| TT13-3 | Snapshot tests: All sub-panels (speed ramp, keyframes, trim, mask, tracking, text, transition, fx, lut, wheels, curves, hsl, scopes) | L | Epics 4, 5 | §11.6 | E | ○ |
| TT13-4 | Gesture XCUITests: tap / long-press / drag / pinch on timeline | L | T7-1..9 | §11.6 | E | ○ |
| TT13-5 | State-machine tests: Export / VO / Tracking / Captions | M | S2-10, F6-2, E4-5, F6-3 | §11.6 | E | ○ |
| TT13-6 | Accessibility audit in CI (XCTest Accessibility Audit per screen) | M | A10-1, A10-7 | §10.6, §11.6 | E | ○ |
| TT13-7 | Inspector matrix tests: every selection type × every section shown/hidden correctly | M | IM9-1..13 | §10.2 | E | ○ |
| TT13-8 | Keyboard shortcut coverage tests | S | K11-1..6 | §10.5 | E | ○ |
| TT13-9 | **Proxy tests**: generation succeeds → playback uses proxy, export always uses original, cache LRU eviction, failed-proxy falls back to original, policy overrides honored | M | PP12-8, PP12-9, PP12-10, PP12-11 | §10.9 | E | ○ |

### Epic 14 — Integration & Polish

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| I14-1 | Tab drill-down end-to-end verification (every tool opens the right panel) | M | T3-1..6 | §6 | A | ○ |
| I14-2 | End-to-end smoke test: create project → import → edit → tracking → caption → export | M | I14-1, F6-1, E4-5, F6-3, S2-11 | — | A | ○ |
| I14-3 | App Store screenshot generation (all device sizes) | M | I14-2 | — | A | ○ |
| I14-4 | Docs sync: update `docs/FEATURES.md`, `docs/DESIGN.md`, `docs/APP_LOGIC.md`, `docs/PERFORMANCE.md` | M | I14-2 | §10.7 | A | ○ |
| I14-5 | Codebase analysis update (`analysis/INDEX.md` + per-file) for all modified / new files | L | I14-2 | CLAUDE.md §"Codebase Analysis System" | A | ○ |
| I14-6 | xcodegen regenerate + full `xcodebuild build` + `xcodebuild test` green run on iPhone + iPad sims | S | I14-2 | CLAUDE.md §"Success Criteria" | A | ○ |

### Epic 15 — Domain Models (data-layer work, highly parallel; no UI dependencies)

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| M15-1 | `ClipEffectStack` model: ordered `[AppliedEffect]` per clip with intensity + bypass; `Codable`; JSON-persisted in project file | M | — | §7.9, §8.3 | B | ○ |
| M15-2 | `ClipColorGrade` model: lift/gamma/gain + curves + HSL + temp/tint/exp/contrast/hi/lo/sat/vibrance; `Codable` | M | — | §8.5, §8.6, §8.7 | B | ○ |
| M15-3 | Keyframe persistence: property-keyed map `[KeyframeProperty: [Keyframe]]` on clip; linear/held/cubic-bezier interpolation | M | — | §7.2, §10.2 | B | ○ |
| M15-4 | Text-clip model expansion: add stroke (color+width), shadow (offset+blur+α), background (fill/bubble/blur), animation (in+out+loop refs) fields | S | — | §8.1 | D | ○ |
| M15-5 | Per-project UI state: `ProjectUIState` codable blob (tool-rail config, last zoom bucket, last-selected tool, scope dock state, tab index) | M | — | §10.4 | A | ○ |
| M15-6 | **`MediaAsset` proxy fields**: add `proxyURL: URL?`, `proxyStatus`, `proxyGeneratedAt`, `useProxyOverride`; `Codable` migration for existing project files | S | — | §10.9.2 | A | ○ |
| M15-7 | **`ClipGroup` model**: `{ id, name, memberIDs, color }` with nesting support (up to 5 levels); `Codable`; lives alongside `Clip` in `PersistentTimeline` | M | — | §7.10 | B | ○ |
| M15-8 | **Clip transform + blend + audio-pan fields**: extend `Clip` with `blendMode`, `flipH`, `flipV`, `rotate90`, `cropRect`, `audioPan`, `audioNormalizeTarget?`; `Codable` migration | M | — | §7.12 | B | ○ |
| M15-9 | **`CustomExportPreset` model**: named preset with all §5.6 fields; stored in per-user defaults + Codable; swipe-to-delete / tap-to-edit list | S | — | §5.6 | C | ○ |
| M15-10 | **`CompoundClip` model**: extends `Clip` with its own internal `PersistentTimeline`; conversion back to Group; nesting state; render-cache key | L | M15-7 | §7.13 | B | ○ |
| M15-11 | **`LinkGroup` model**: `{ id, memberIDs, kind: .sync \| .manual }` alongside `ClipGroup` in `PersistentTimeline`; auto-link on matching-duration import | M | — | §7.16 | B | ○ |
| M15-12 | **`ClipMarker` model**: per-clip `[ClipMarker]` array; `{ id, positionInClip, label, color }`; Codable; travels with clip on trim/move/group | S | — | §7.17 | B | ○ |
| M15-13 | **`AudioEffectChain` + `AudioEffect` models**: per-clip chain of Reverb / Delay / Compression / Gate / Limiter with params + bypass + order; Codable | M | — | §7.18 | B | ○ |

### Epic 16 — iPad Platform Extras

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| IP16-1 | Pointer hover effects: `.pointerStyle(.link)` on tappable, `.horizontalText` on trim handles, `.grabIdle` on timeline scroll, `.rectangle` on lasso area | M | S2-2 | §10.6 | A | ○ |
| IP16-2 | System drag-drop receiver: `.onDrop(of:)` on timeline + media browser for Photos, Files, Safari URLs; type coercion + import pipeline | M | F6-1 | §9.7 | A | ○ |
| IP16-3 | Multitasking: verify Slide Over / Split View / Stage Manager layouts; auto-collapse to compact when width < 640pt | M | S2-2, S2-6, S2-9 | §2.6 | A | ○ |

---

## 6. Kickoff Order (day 1)

All of these can start **simultaneously on day 1**:

1. **D0-1 through D0-6** — product/design owners. These unblock the largest chunks; ideally resolved within 2 days.
2. **F0-1** (token audit) — stream A. Everything visual needs it.
3. **F0-3** (signposts) — stream A. Decoupled.
4. **F0-4** (motion-token audit) — stream A. Decoupled.
5. **F0-5** (dark color scheme) — stream A. Decoupled.
6. **F0-7** (localization pipeline) — stream A. Decoupled; should land early so all new copy lands localized from day 1.
7. **P1-11** (audio waveform primitive) — stream B. Decoupled; lives on the critical path.
8. **P1-10** (color wheel primitive) — stream D. Decoupled; feeds C5-6.
9. **M15-1, M15-2, M15-3** (domain models) — stream B. Fully decoupled from UI; parallelize.
10. **M15-4, M15-5** (text model expansion, project UI state) — streams D / A.
11. **C5-10** (transition shaders), **C5-11** (FX shaders) — stream D. Decoupled; XL items that should start earliest.
12. **C5-14** (chroma compute), **C5-15/16** (curves + HSL pipelines), **C5-17** (stabilization), **C5-18** (dialog detection) — stream B/D. Decoupled compute work; start early so feature UIs can wire in.
13. **C5-20** (LUT content) — content pipeline; decoupled, content team or outsourced.
14. **E4-10, E4-11** (tracking + mask data models) — stream B. Decoupled.
15. **F0-9** (App Settings screen) — stream A. Decoupled once F0-2 lands.
16. **F0-10** (Proxy defaults config), **M15-6** (MediaAsset proxy fields) — stream A. Decoupled; feed PP12-8 chain.
17. **PP12-9** (`ProxyGenerator` actor) — stream A. Can land on top of F0-10; fully decoupled from UI.
18. **M15-7, M15-8, M15-9** (ClipGroup, clip transform fields, custom export preset) — stream B/C. Pure data-model work, no UI deps.
19. **M15-11, M15-12, M15-13** (LinkGroup, ClipMarker, AudioEffectChain) — stream B. Pure data models.
20. **PP12-13** (audio DSP pipeline) — stream B. Extends existing AudioEffectsEngine.

After **F0-1 completes (~day 1)**, every Epic 1 primitive (P1-1 … P1-17) opens. After **F0-2 completes (~day 2)**, haptics-dependent items open.

---

## 7. Blocked Tasks (pending decisions)

Resolve these decisions ASAP; every day of delay slides the schedule by the same amount for the blocked chain:

| Decision | Blocks | Impact |
|---|---|---|
| **D0-1** tracking engine | E4-5, E4-9, T3-5, TT13-5 | Largest single blocker — on the critical path |
| **D0-2** .cube import | C5-5 (partial) | Scope only; not a hard block |
| **D0-3** STT vendor | F6-3, T3-4, TT13-5 | Schedule + privacy copy |
| **D0-4** snapshot policy | F6-6, F6-4 | Medium |
| **D0-5** ripple-delete default | P1-13, T7-7 | Small but user-facing |
| **D0-6** iPhone landscape | S2-3 | Scope toggle — drop if defer |

---

## 8. Completion Dashboard

Update the per-task `Status` column (`○ → ◔ → ●`) as work progresses. Quick counters to track manually:

- Epic 0: 0 / 16 done
- Epic 1: 0 / 17 done
- Epic 2: 0 / 25 done
- Epic 3: 0 / 6 done
- Epic 4: 0 / 16 done
- Epic 5: 0 / 26 done
- Epic 6: 0 / 20 done
- Epic 7: 0 / 40 done
- Epic 8: 0 / 17 done
- Epic 9: 0 / 21 done
- Epic 10: 0 / 12 done
- Epic 11: 0 / 9 done
- Epic 12: 0 / 13 done
- Epic 13: 0 / 9 done
- Epic 14: 0 / 6 done
- Epic 15: 0 / 13 done
- Epic 16: 0 / 3 done

**Total: 0 / 266 tasks done**

---

## 9. Done Definition

A task is only marked `● done` when **all** of these are true (per `CLAUDE.md` success criteria):

1. Code uses **pure SwiftUI** + `@Observable` + `@MainActor` per project standards.
2. `xcodegen generate` clean (if new files).
3. `xcodebuild build` passes with **zero warnings** (Swift 6 strict concurrency).
4. `xcodebuild test` 100% green on iPhone 16 Pro simulator (iOS 26.0).
5. Relevant section of `docs/*` updated.
6. `analysis/` files updated for any modified / new `.swift` files (per Epic 14.5 template).
7. Task's parent **epic-level integration test** (from Epic 13) passes.
8. Accessibility checks pass for any UI-bearing task (VoiceOver, Dynamic Type, Reduce Motion).

---

## 10. References

- Spec: `docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md`
- Coding standards: `docs/CODING_STANDARDS.md`
- Testing: `docs/TESTING.md`
- Performance budgets: `docs/PERFORMANCE.md`
- Codebase analysis system: `CLAUDE.md` §“Codebase Analysis System”
- Mockups: `.superpowers/brainstorm/41597-1776514658/content/`
