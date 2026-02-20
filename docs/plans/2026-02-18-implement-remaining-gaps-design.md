# Design: Implement Remaining Flutter→Swift Gaps

**Date:** 2026-02-18
**Status:** Approved
**Approach:** 5 parallel agents, each with exclusive file ownership

---

## Background

The Flutter→Swift gap analysis (see `analysis/FLUTTER_SWIFT_GAP_ANALYSIS.md`) identified the following remaining gaps after achieving ~90% parity. Three missing files were already implemented (SlowMotionService, AspectRatioService, TrackDebugSheet). This design covers the remaining items.

---

## Agent 1 — Editor Wiring

**Files owned:** `LiquidEditor/Views/Editor/EditorView.swift`, `LiquidEditor/ViewModels/EditorViewModel.swift`

### 1a. Tracking Bounding Boxes
- Add `var currentTrackingBoxes: [NormalizedBoundingBox] = []` to `EditorViewModel`
- Add `var activeTrackingSessionId: String? = nil` to `EditorViewModel`
- In `EditorViewModel`, add a method `updateTrackingBoxes(timestampMs: Int)` that calls `TrackingService.getInterpolatedResult(sessionId:timestampMs:)` and writes to `currentTrackingBoxes`
- Trigger `updateTrackingBoxes` from the playback tick (observe `PlaybackEngine` time changes)
- In `EditorView.swift:89`, replace `trackingBoundingBoxes: []` with `viewModel.currentTrackingBoxes`

### 1b. KeyframeEditorSheet Connection
- Replace the placeholder block at `EditorView.swift:527-542` with `KeyframeEditorSheet` using the existing 632-line implementation
- Pass `selectedClip` and `selectedKeyframe` bindings from `EditorViewModel`

### 1c. TrackDebugSheet Presentation
- Add `.sheet(isPresented: $viewModel.isTrackDebugActive)` presenting `TrackDebugSheet(sessionId: viewModel.activeTrackingSessionId ?? "", onClose: { viewModel.isTrackDebugActive = false })`
- The `isTrackDebugActive` flag already exists in `EditorViewModel`

---

## Agent 2 — Animated Transition Previews

**Files owned:** `LiquidEditor/Views/Sheets/TransitionPickerSheet.swift`

### Design
- Extract grid cell into `TransitionPreviewCell` view
- Add `@State var animPhase: Double = 0.0` to each cell
- On `.onAppear`, start `withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { animPhase = 1.0 }`
- Each `TransitionType` case gets a unique `Canvas`-based animation:
  - **Cut**: instant swap (two half-rectangles, A/B colors)
  - **Dissolve**: opacity `A * (1 - animPhase) + B * animPhase`
  - **WipeLeft/Right/Up/Down**: sliding divider line
  - **Zoom**: scale from `1.0 → 1.3 → 1.0`
  - **Spin**: rotation `0 → 360`
  - **Blur**: blur radius pulse
  - **Slide**: translate A out, B in
- Preview dimensions: 60×40pt (matches Flutter grid cell thumbnail)

---

## Agent 3 — Text Effects Grid + Inline Variant

**Files owned:** `LiquidEditor/Views/Sheets/TextEditorSheet.swift`

### 3a. Text Effect Presets Grid
- Add `enum TextEffectPreset: CaseIterable` with 8 cases: `none`, `hardShadow`, `softShadow`, `blockOffset`, `neon`, `glow`, `halo`, `shimmer`
- Each preset maps to a `TextOverlayStyle` configuration closure
- Insert a `ScrollView(.horizontal)` row of 8 preset chips at top of Style tab
- Each chip: small preview thumbnail (text on colored bg) + label
- Selecting a preset writes to `viewModel.selectedClip.textStyle`

### 3b. Inline Panel Variant
- Add `var isInline: Bool = false` init parameter to `TextEditorSheet`
- When `isInline == true`: render as a `VStack` of height ≤260pt with compact tab headers (icons only, no labels), same content but collapsed spacing
- In `EditorView`, when `activePanel == .textEditor`, show the inline variant replacing the timeline area (matching how `CropSheet`, `VideoEffectsSheet`, and `SpeedControlSheet` present inline)

---

## Agent 4 — Library Secondary Features

**Files owned:** `LiquidEditor/Views/Library/ProjectLibraryView.swift`

### 4a. Drag-to-Reorder
- Add `@State private var isEditMode = false` and `EditButton()` / "Done" button in toolbar
- Add `.onMove { from, to in viewModel.moveProject(from: from, to: to) }` to `ForEach`
- Add `func moveProject(from: IndexSet, to: Int)` to `ProjectLibraryViewModel` that calls `ProjectRepository.reorderProjects(_:)`

### 4b. Batch Delete Mode
- Add `@State private var selectedIds: Set<String> = []`
- In edit mode, project cards show selection checkmarks; tap to toggle
- "Delete Selected (N)" button in bottom toolbar, `.confirmationDialog` before delete
- Calls `ProjectRepository.deleteProjects(ids:)`

---

## Agent 5 — Project Backup Service

**New file:** `LiquidEditor/Services/Project/ProjectBackupService.swift`

### Design
```swift
actor ProjectBackupService {
    static let shared = ProjectBackupService()

    // Creates a timestamped snapshot in Backups/<projectId>/<ISO8601>/
    func createBackup(for projectId: String) async throws -> BackupManifest

    // Lists all backups for a project, sorted newest-first
    func listBackups(for projectId: String) async -> [BackupManifest]

    // Restores a project directory from a backup manifest
    func restoreBackup(_ manifest: BackupManifest) async throws

    // Keeps only the N most recent backups, deletes the rest
    func pruneOldBackups(for projectId: String, keepCount: Int) async throws
}
```

- Uses existing `BackupManifest` model from `Models/Project/BackupManifest.swift`
- All I/O via `FileManager` on background thread (actor isolation)
- Register in `ServiceContainer` as `var projectBackupService: ProjectBackupService`

---

## Success Criteria

1. `xcodegen generate` succeeds after Agent 5 adds new file
2. `xcodebuild build` succeeds with zero errors and zero warnings
3. `xcodebuild test` passes 100%
4. Swift 6 strict concurrency — no data race warnings
5. All 5 changes visible and functional when app runs
