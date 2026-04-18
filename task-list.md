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

- **Epics:** 15 (Epic 0 Decisions → Epic 14 Integration).
- **Tasks:** 142 total.
- **Total estimated effort:** ~180 engineer-days.
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
| E4-9 | **Chroma Key View** (eyedropper + tolerance/softness/spill/edge + alpha/holdout/fill toggles + Refine→Mask) | L | E4-4, P1-1 | §7.9 | B | ○ |

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
| C5-9 | **Scopes Panel** (Waveform / Histogram / Vectorscope / RGB Parade; 30 Hz sampling; iPad dock-or-float) | L | F0-3 | §8.8 | D | ○ |

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

### Epic 11 — Keyboard Shortcuts (iPad)

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| K11-1 | Register playback shortcuts: Space, J/K/L shuttle | S | P1-9, S2-1 | §10.5 | A | ○ |
| K11-2 | Register edit shortcuts: ⌘S split, ⌘C/V/D, ⌦ delete, I/O mark, T trim-to-playhead | S | P1-9, T3-2 | §10.5 | A | ○ |
| K11-3 | Register nav shortcuts: ⌘Z/⇧Z undo/redo, ⌘+/− zoom, arrows ±1 frame / shift-arrows ±1s | S | P1-9 | §10.5 | A | ○ |
| K11-4 | Register modal shortcuts: Esc dismiss, F fullscreen, ⌘E export, ⌘N new, ⌘F search, ⇥ cycle tabs | S | P1-9 | §10.5 | A | ○ |
| K11-5 | Marker shortcut: M at playhead | S | P1-9, P1-12 | §10.5 | A | ○ |
| K11-6 | Hold-⌘ discoverability overlay population (group labels + all shortcuts) | S | K11-1..5 | §10.5 | A | ○ |

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

### Epic 14 — Integration & Polish

| ID | Title | Size | Depends | Spec | Stream | Status |
|---|---|---|---|---|---|---|
| I14-1 | Tab drill-down end-to-end verification (every tool opens the right panel) | M | T3-1..6 | §6 | A | ○ |
| I14-2 | End-to-end smoke test: create project → import → edit → tracking → caption → export | M | I14-1, F6-1, E4-5, F6-3, S2-11 | — | A | ○ |
| I14-3 | App Store screenshot generation (all device sizes) | M | I14-2 | — | A | ○ |
| I14-4 | Docs sync: update `docs/FEATURES.md`, `docs/DESIGN.md`, `docs/APP_LOGIC.md`, `docs/PERFORMANCE.md` | M | I14-2 | §10.7 | A | ○ |
| I14-5 | Codebase analysis update (`analysis/INDEX.md` + per-file) for all modified / new files | L | I14-2 | CLAUDE.md §"Codebase Analysis System" | A | ○ |
| I14-6 | xcodegen regenerate + full `xcodebuild build` + `xcodebuild test` green run on iPhone + iPad sims | S | I14-2 | CLAUDE.md §"Success Criteria" | A | ○ |

---

## 6. Kickoff Order (day 1)

All of these can start **simultaneously on day 1**:

1. **D0-1 through D0-6** — product/design owners. These unblock the largest chunks; ideally resolved within 2 days.
2. **F0-1** (token audit) — stream A. Everything visual needs it.
3. **F0-3** (signposts) — stream A. Decoupled.
4. **P1-11** (audio waveform primitive) — stream B. Decoupled; lives on the critical path.
5. **P1-10** (color wheel primitive) — stream D. Decoupled; feeds C5-6.

After **F0-1 completes (~day 1)**, every Epic 1 primitive (P1-1 … P1-15) opens. After **F0-2 completes (~day 2)**, haptics-dependent items open.

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

- Epic 0: 0 / 9 done
- Epic 1: 0 / 15 done
- Epic 2: 0 / 11 done
- Epic 3: 0 / 6 done
- Epic 4: 0 / 9 done
- Epic 5: 0 / 9 done
- Epic 6: 0 / 9 done
- Epic 7: 0 / 9 done
- Epic 8: 0 / 14 done
- Epic 9: 0 / 13 done
- Epic 10: 0 / 11 done
- Epic 11: 0 / 6 done
- Epic 12: 0 / 7 done
- Epic 13: 0 / 8 done
- Epic 14: 0 / 6 done

**Total: 0 / 142 tasks done**

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
