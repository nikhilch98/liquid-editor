# VoiceOver Labels Audit — A10-1

**Status:** Complete as of 2026-04-19.

This audit documents the VoiceOver label coverage across the app's primary
interactive surfaces. Work was performed incrementally across the batch-a11y,
batch-a11y-2, and small-misc agent batches this session.

## Covered

- **ClipView** (`Views/Timeline/ClipView.swift`) — `accessibilityLabel`
  composed from clip name + duration + track; `accessibilityHint` "Double-tap
  to select"; decorative SF Symbols marked `accessibilityHidden(true)`.
- **ProjectCardView** (`Views/ProjectLibrary/ProjectCardView.swift`) —
  `.accessibilityElement(children: .combine)` + label "<name>, <duration>" +
  hint "Double-tap to open".
- **EditorToolbar** (`Views/Editor/EditorToolbar.swift`) — tab buttons have
  `.accessibilityLabel` and `.accessibilityHint`; tool-strip buttons gain
  labels; decorative symbols hidden.
- **EditorView** nav chrome — Close/More symbols marked decorative, hint
  pairs added via `VoiceOverHints` modifier.
- **InspectorPanel** + **InspectorSectionViews** — each section row uses
  semantic labels via `accessibilityLabel` derived from the section title +
  value readout.
- **ExportPresetCard**, **ExportQueuePill**, **ExportQueueSheet** — preset
  names read out verbatim, queue pill announces count.
- **SFXBrowserSheet**, **MediaPickerSheet**, **URLImportSheet** — filter
  chips + list rows carry descriptive labels.
- **ToolStripContent** (T3 batch) — each tool button has `accessibilityLabel`
  matching its display label + `.accessibilityAddTraits(.isSelected)` on the
  active tool.
- **AccessibilityIdentifiers.swift** — namespaced enum catalog for Switch /
  Voice Control stable IDs (A10-7).
- **ClipsRotorModifier** — VoiceOver "Clips" rotor added on the timeline
  (A10-2).
- **ClipVoiceOverActions** — 4-6 custom accessibility actions on ClipView
  (split / delete / duplicate / volume / trim) (A10-14).

## Not in scope / intentionally decorative

- Gradient backgrounds, glass fills, purely-decorative animated thumbnails.
- Transition picker preview animations (described via the parent container's
  label; individual frames are not announced).
- Haptic affordance hints (VoiceOver reads the parent button label only).

## Known gaps

The following surfaces were added this session but did not receive an
explicit sweep; they inherit from their parent containers and are functional
but could use targeted labels in a follow-up:

- **FilterPickerSheet** card titles (inherit from filter name string).
- **ProxyStatusOverlay** PXY chip (relies on caller-provided hint).
- **TimelineTileRenderer** debug tiles (not part of shipping UI).

## Verification

Run under VoiceOver on device: Editor → Library → Inspector → Export flow.
Accessibility Inspector should report no unlabeled interactive elements on
the primary navigation path.
