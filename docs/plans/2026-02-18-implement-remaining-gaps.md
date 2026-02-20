# Implement Remaining Flutter→Swift Gaps — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement 5 remaining feature gaps between the Swift LiquidEditor and Flutter liquid-editor reference, achieving ~97% parity.

**Architecture:** 5 independent task groups with exclusive file ownership — no shared files, safe for parallel dispatch. All code follows MVVM + `@Observable` + `@MainActor` + Swift 6 strict concurrency (see CLAUDE.md).

**Tech Stack:** SwiftUI, AVFoundation, `@Observable` macro, `@MainActor`, Swift 6 strict concurrency, `Canvas` API

**Design doc:** `docs/plans/2026-02-18-implement-remaining-gaps-design.md`

---

## Pre-Flight Checks (Run Once Before Any Agent Starts)

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`. If it fails, stop and fix before proceeding.

---

## Task Group A — Editor Wiring

**Files:**
- Modify: `LiquidEditor/ViewModels/EditorViewModel.swift`
- Modify: `LiquidEditor/Views/Editor/EditorView.swift`

**Context:** EditorView.swift line 89 passes `trackingBoundingBoxes: []` hardcoded. Lines 527-542 show a placeholder instead of `KeyframeEditorSheet`. `isTrackDebugActive: Bool` exists in EditorViewModel but `TrackDebugSheet` is never presented.

---

### Task A1: Read both files to understand current structure

Read the full `EditorViewModel.swift` and `EditorView.swift`. Look for:
- Where `isTrackingActive`, `isTrackDebugActive`, `selectedClipId`, and `activePanel` are declared in EditorViewModel
- The signature of `VideoPreviewView` initialization (line ~89 in EditorView)
- The exact placeholder block at lines 527-542
- How `TrackingService` is accessed (via `ServiceContainer.shared.trackingService`)
- What methods `TrackingService` exposes for fetching results (look for `getAllResults`, `getInterpolatedResult`, or similar)

---

### Task A2: Add tracking state to EditorViewModel

In `EditorViewModel.swift`, add these properties near the existing `isTrackingActive` property:

```swift
// Tracking display state
var currentTrackingBoxes: [NormalizedBoundingBox] = []
var activeTrackingSessionId: String? = nil
```

Also add this method in EditorViewModel:

```swift
func updateTrackingBoxes(for timestampMs: Int) async {
    guard let sessionId = activeTrackingSessionId, isTrackingActive else {
        if !currentTrackingBoxes.isEmpty {
            currentTrackingBoxes = []
        }
        return
    }
    // Fetch all results and find the closest frame to current timestamp
    let allResults = await ServiceContainer.shared.trackingService.getAllResults(sessionId: sessionId)
    guard !allResults.isEmpty else { return }
    // Find closest frame by timestamp
    let closest = allResults.min(by: { abs($0.timestampMs - timestampMs) < abs($1.timestampMs - timestampMs) })
    currentTrackingBoxes = closest?.people.compactMap { $0.boundingBox } ?? []
}
```

> **Note:** If `TrackingService.getAllResults(sessionId:)` has a different name, read TrackingService.swift and use the correct method.

---

### Task A3: Wire tracking boxes in EditorView

In `EditorView.swift`, find the line (approximately line 89) that reads:

```swift
trackingBoundingBoxes: []
```

Replace with:

```swift
trackingBoundingBoxes: viewModel.currentTrackingBoxes
```

Then find where the playback time changes are observed (look for `.onChange(of: viewModel.currentTime)` or similar playback tick). Add a call to update tracking boxes:

```swift
.onChange(of: viewModel.currentTime) { _, newTime in
    let ms = Int(newTime * 1000)
    Task { await viewModel.updateTrackingBoxes(for: ms) }
}
```

If there is no `.onChange(of: viewModel.currentTime)`, add it to the main view body.

---

### Task A4: Connect KeyframeEditorSheet

Find the placeholder block in EditorView.swift around lines 527-542. It should look like:

```swift
// Something like:
Text("Select a keyframe to edit")
    .foregroundStyle(.secondary)
```

Read `LiquidEditor/Views/Sheets/KeyframeEditorSheet.swift` (first 30 lines) to get its exact init signature. Then replace the placeholder block with:

```swift
if let clip = viewModel.selectedClip {
    KeyframeEditorSheet(clip: clip)
} else {
    ContentUnavailableView(
        "No Clip Selected",
        systemImage: "film",
        description: Text("Select a clip to edit its keyframes")
    )
}
```

> Adjust the init parameters to match KeyframeEditorSheet's actual signature.

---

### Task A5: Add TrackDebugSheet presentation

In `EditorView.swift`, find any existing `.sheet(isPresented:)` or `.fullScreenCover` modifiers on the main view. Add this alongside them:

```swift
.sheet(isPresented: $viewModel.isTrackDebugActive) {
    TrackDebugSheet(
        sessionId: viewModel.activeTrackingSessionId ?? "",
        onClose: { viewModel.isTrackDebugActive = false }
    )
}
```

---

### Task A6: Build and verify

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`, zero errors, zero concurrency warnings.

Fix any errors before proceeding. Common issues:
- `NormalizedBoundingBox` not in scope → add `import` or check `Tracking.swift` for the module
- Sendable warning on `Task { await viewModel... }` → ensure `viewModel` is `@MainActor`-isolated

---

## Task Group B — Animated Transition Previews

**Files:**
- Modify: `LiquidEditor/Views/Sheets/TransitionPickerSheet.swift`

**Context:** The grid currently shows static SF Symbol icons per transition type. Flutter shows looping animated Canvas previews. We replicate this with a SwiftUI `TimelineView` + `Canvas` approach.

---

### Task B1: Read TransitionPickerSheet.swift

Read the full file. Identify:
- The `TransitionType` enum (or wherever transition types are defined — may be in a Models file)
- The existing grid cell view (look for a `View` displaying the SF Symbol icon)
- What data the grid cell receives (TransitionType value)
- The grid layout (likely `LazyVGrid` with columns)

---

### Task B2: Create TransitionPreviewCell

Find the existing grid cell view in TransitionPickerSheet.swift. Replace it (or the inner content) with a new `TransitionPreviewCell` struct. Add this struct at the bottom of the file (above the closing brace of the file if it's in an extension, or as a private struct below):

```swift
private struct TransitionPreviewCell: View {
    let transitionType: TransitionType  // use whatever the actual type name is
    let isSelected: Bool

    @State private var phase: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let p = phase  // 0...1

            switch transitionType {
            case .cut:
                // Instant swap: left half A color, right half B color (flips at 0.5)
                let colorA = p < 0.5 ? Color.blue : Color.orange
                let colorB = p < 0.5 ? Color.orange : Color.blue
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w / 2, height: h)), with: .color(colorA))
                ctx.fill(Path(CGRect(x: w / 2, y: 0, width: w / 2, height: h)), with: .color(colorB))

            case .dissolve, .fade:
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.blue))
                ctx.drawLayer { layerCtx in
                    layerCtx.opacity = p
                    layerCtx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.orange))
                }

            case .wipeLeft, .slideLeft, .push:
                let splitX = w * (1 - p)
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.blue))
                ctx.fill(Path(CGRect(x: splitX, y: 0, width: w - splitX, height: h)), with: .color(.orange))

            case .wipeRight, .slideRight:
                let splitX = w * p
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.blue))
                ctx.fill(Path(CGRect(x: 0, y: 0, width: splitX, height: h)), with: .color(.orange))

            case .wipeUp, .slideUp:
                let splitY = h * (1 - p)
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.blue))
                ctx.fill(Path(CGRect(x: 0, y: splitY, width: w, height: h - splitY)), with: .color(.orange))

            case .wipeDown, .slideDown:
                let splitY = h * p
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.blue))
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: splitY)), with: .color(.orange))

            case .zoom, .zoomIn:
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.blue))
                let scale = 0.3 + p * 0.7
                let inset = CGSize(width: w * (1 - scale) / 2, height: h * (1 - scale) / 2)
                ctx.fill(Path(CGRect(x: inset.width, y: inset.height,
                                     width: w * scale, height: h * scale)),
                          with: .color(.orange))

            default:
                // Fallback: crossfade
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.blue))
                ctx.drawLayer { layerCtx in
                    layerCtx.opacity = p
                    layerCtx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.orange))
                }
            }
        }
        .frame(width: 60, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}
```

> **Important:** The `switch` cases must match the actual `TransitionType` enum cases. Read the enum definition and update the switch accordingly. Remove cases that don't exist. Use `default:` as fallback.

---

### Task B3: Swap the static icon for TransitionPreviewCell

In the grid cell body, find where `Image(systemName: ...)` or similar static content is shown. Replace just that icon/thumbnail portion with:

```swift
TransitionPreviewCell(transitionType: transition, isSelected: selectedTransition == transition)
```

Keep the label text below it unchanged.

---

### Task B4: Build and verify

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`. Common issues:
- Switch not exhaustive → add `default:` case
- `Canvas` `drawLayer` closure → `ctx` must be `inout GraphicsContext` → use `var subCtx = ctx` pattern if needed:
  ```swift
  var subCtx = ctx
  subCtx.opacity = p
  subCtx.fill(...)
  ```

---

## Task Group C — Text Effects Grid + Inline Variant

**Files:**
- Modify: `LiquidEditor/Views/Sheets/TextEditorSheet.swift`

**Context:** TextEditorSheet.swift is 924 lines with 4 tabs (Style, Animation, Position, Templates). Style tab has individual effect toggles. Need to add: (1) 8-preset effects row at top of Style tab, (2) inline panel variant for use when `activePanel == .textEditor` in EditorView.

---

### Task C1: Read TextEditorSheet.swift

Read the full file. Find:
- The Style tab content builder (look for `"Style"` tab label or `case .style`)
- Where `hasShadow`, `hasOutline`, `hasBackground`, `hasGlow` are toggled
- The `TextOverlayStyle` type and how it's mutated (look for `viewModel.selectedClip?.textStyle` or similar binding)
- The sheet's init parameters (what it receives from the caller)
- How other sheets implement inline mode (read first 50 lines of `CropSheet.swift` or `VideoEffectsSheet.swift` to see the pattern)

---

### Task C2: Add TextEffectPreset enum

At the top of TextEditorSheet.swift (inside the file, outside the main struct), add:

```swift
private enum TextEffectPreset: String, CaseIterable, Identifiable {
    case none = "None"
    case hardShadow = "Hard Shadow"
    case softShadow = "Soft Shadow"
    case blockOffset = "Block Offset"
    case neon = "Neon"
    case glow = "Glow"
    case halo = "Halo"
    case shimmer = "Shimmer"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "textformat"
        case .hardShadow: return "shadow"
        case .softShadow: return "aqi.medium"
        case .blockOffset: return "rectangle.stack"
        case .neon: return "bolt"
        case .glow: return "rays"
        case .halo: return "circle.dashed"
        case .shimmer: return "sparkles"
        }
    }
}
```

---

### Task C3: Add preset application function

Inside the TextEditorSheet struct (or its ViewModel — wherever style mutations happen), add a method that applies a preset. Find what type `textStyle` is and how it is mutated. The method should update the relevant style properties:

```swift
private func applyPreset(_ preset: TextEffectPreset, to style: inout TextOverlayStyle) {
    // Reset effects first
    style.shadowRadius = 0
    style.shadowOffset = .zero
    style.shadowColor = .clear
    style.glowRadius = 0
    style.glowColor = .clear
    style.strokeWidth = 0

    switch preset {
    case .none:
        break  // already reset above
    case .hardShadow:
        style.shadowRadius = 0
        style.shadowOffset = CGSize(width: 4, height: 4)
        style.shadowColor = .black
    case .softShadow:
        style.shadowRadius = 8
        style.shadowOffset = CGSize(width: 2, height: 2)
        style.shadowColor = .black.opacity(0.6)
    case .blockOffset:
        style.shadowRadius = 0
        style.shadowOffset = CGSize(width: 6, height: 6)
        style.shadowColor = style.color  // same hue, offset block
    case .neon:
        style.glowRadius = 12
        style.glowColor = style.color
        style.strokeWidth = 1
    case .glow:
        style.glowRadius = 20
        style.glowColor = style.color.opacity(0.8)
    case .halo:
        style.shadowRadius = 16
        style.shadowOffset = .zero
        style.shadowColor = .white
    case .shimmer:
        // Shimmer is animated; set glow + stroke to indicate it
        style.glowRadius = 8
        style.glowColor = .white.opacity(0.9)
        style.strokeWidth = 0.5
    }
}
```

> **Adjust property names** to match the actual `TextOverlayStyle` struct fields. Read `TextOverlayStyle` definition if needed.

---

### Task C4: Add preset row to Style tab

In the Style tab content builder, at the very top (before the existing effect toggles), add:

```swift
// Text Effect Presets
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 10) {
        ForEach(TextEffectPreset.allCases) { preset in
            Button {
                if var style = viewModel.selectedClip?.textStyle {
                    applyPreset(preset, to: &style)
                    viewModel.selectedClip?.textStyle = style
                }
            } label: {
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(width: 52, height: 36)
                        Image(systemName: preset.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                    }
                    Text(preset.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 56)
                }
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
}
```

---

### Task C5: Add inline variant parameter

Find the struct declaration of `TextEditorSheet`. Add an `isInline` parameter:

```swift
struct TextEditorSheet: View {
    // Add this parameter with a default of false for backward compatibility
    var isInline: Bool = false
    // ... existing properties ...
```

In the `body` property, wrap the existing sheet content:

```swift
var body: some View {
    if isInline {
        inlinePanel
    } else {
        sheetContent
    }
}

private var sheetContent: some View {
    // Move the current body content here (or just use @ViewBuilder method)
    // existing body content
}

private var inlinePanel: some View {
    VStack(spacing: 0) {
        // Compact tab row - icons only
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // Tab buttons using same tab index as the full sheet
                // Use small icon-only tab buttons
                tabBar
                    .frame(height: 40)
            }
        }
        Divider()
        // Reuse the same tab content
        tabContent
            .frame(maxHeight: 200)
    }
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
}
```

> **Refactoring guidance:** The key is to extract the tab bar and tab content into named computed properties (or `@ViewBuilder` functions). Then both `sheetContent` and `inlinePanel` reuse them. Keep the logic identical — only the chrome (navigation bar, drag handle) differs between variants.

---

### Task C6: Build and verify

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`. Common issues:
- "Unable to type-check expression" → extract complex view bodies into `@ViewBuilder` computed properties
- Property name mismatch in `applyPreset` → read `TextOverlayStyle.swift` and use correct field names
- `inout TextOverlayStyle` in `@MainActor` function → mark `applyPreset` as `@MainActor` or `nonisolated`

---

## Task Group D — Library Secondary Features

**Files:**
- Modify: `LiquidEditor/Views/Library/ProjectLibraryView.swift`

**Context:** ProjectLibraryView.swift (482 lines) has a list of projects but no drag-to-reorder or batch delete. The ViewModel calls `ProjectRepository` methods.

---

### Task D1: Read ProjectLibraryView.swift

Read the full file. Find:
- The ViewModel type used (e.g., `ProjectLibraryViewModel`)
- How projects are stored and displayed (`ForEach` list)
- How individual delete works currently (look for `onDelete` or swipe actions)
- The ViewModel's method for deleting a project
- Whether `ProjectRepository` has a `reorderProjects` or `moveProject` method

Also read the first 50 lines of the ViewModel file if separate.

---

### Task D2: Add reorder capability to ViewModel

If the ViewModel has a `var projects: [Project]` array, add a `moveProject` method. If no reorder method exists in ProjectRepository, implement it locally:

```swift
// In ViewModel:
func moveProject(from source: IndexSet, to destination: Int) {
    projects.move(fromOffsets: source, toOffset: destination)
    // Persist the new order
    Task {
        await projectRepository.saveProjectOrder(projects.map(\.id))
    }
}
```

> If `ProjectRepository` doesn't have `saveProjectOrder`, add a simple persistence via `UserDefaults`:
> ```swift
> UserDefaults.standard.set(projects.map(\.id), forKey: "projectOrder")
> ```

---

### Task D3: Add edit mode state to ProjectLibraryView

In `ProjectLibraryView`, add state properties:

```swift
@State private var isEditMode: Bool = false
@State private var selectedProjectIds: Set<String> = []
@State private var showDeleteConfirmation: Bool = false
```

---

### Task D4: Add Edit/Done toolbar button

Find the toolbar or navigation bar in ProjectLibraryView. Add a trailing button:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button(isEditMode ? "Done" : "Select") {
            withAnimation(.spring(response: 0.3)) {
                isEditMode.toggle()
                if !isEditMode {
                    selectedProjectIds.removeAll()
                }
            }
        }
    }
    // Keep existing toolbar items (e.g., new project button)
}
```

---

### Task D5: Add .onMove to ForEach

Find the `ForEach` that renders project cards. Add `.onMove`:

```swift
ForEach(viewModel.projects) { project in
    ProjectCard(project: project, ...)  // existing content
        // In edit mode, add selection overlay:
        .overlay(alignment: .topTrailing) {
            if isEditMode {
                Image(systemName: selectedProjectIds.contains(project.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedProjectIds.contains(project.id) ? .accentColor : .secondary)
                    .padding(8)
            }
        }
        .onTapGesture {
            if isEditMode {
                if selectedProjectIds.contains(project.id) {
                    selectedProjectIds.remove(project.id)
                } else {
                    selectedProjectIds.insert(project.id)
                }
            } else {
                // existing tap action (open project)
            }
        }
}
.onMove { from, to in
    viewModel.moveProject(from: from, to: to)
}
```

---

### Task D6: Add batch delete bottom toolbar

When in edit mode with selections, show a delete bottom toolbar. Add to the main view body:

```swift
.overlay(alignment: .bottom) {
    if isEditMode && !selectedProjectIds.isEmpty {
        HStack {
            Spacer()
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete (\(selectedProjectIds.count))", systemImage: "trash")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.red.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.bottom, 32)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
.confirmationDialog(
    "Delete \(selectedProjectIds.count) project(s)?",
    isPresented: $showDeleteConfirmation,
    titleVisibility: .visible
) {
    Button("Delete", role: .destructive) {
        Task {
            await viewModel.deleteProjects(ids: selectedProjectIds)
            selectedProjectIds.removeAll()
            isEditMode = false
        }
    }
    Button("Cancel", role: .cancel) {}
}
```

Add `deleteProjects(ids:)` to ViewModel if it doesn't exist:

```swift
func deleteProjects(ids: Set<String>) async {
    for id in ids {
        try? await projectRepository.deleteProject(id: id)
    }
    await loadProjects()  // refresh the list
}
```

---

### Task D7: Build and verify

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

---

## Task Group E — Project Backup Service

**Files:**
- Create: `LiquidEditor/Services/Project/ProjectBackupService.swift`
- Modify: `LiquidEditor/Services/ServiceContainer.swift`
- Run: `xcodegen generate` after creating new file

**Context:** `BackupManifest.swift` already exists in `Models/Project/`. Read it to understand its properties before implementing.

---

### Task E1: Read existing BackupManifest

Read `LiquidEditor/Models/Project/BackupManifest.swift`. Note:
- All properties on `BackupManifest`
- Whether it's `Codable`
- What it tracks (projectId, timestamp, file paths, etc.)

Also read `LiquidEditor/Services/Project/AutoSaveService.swift` (first 60 lines) to understand how project file paths are structured.

---

### Task E2: Create ProjectBackupService.swift

Create `LiquidEditor/Services/Project/ProjectBackupService.swift`:

```swift
import Foundation

/// Manages versioned backup snapshots of projects.
/// Backups are stored at: <AppSupport>/Backups/<projectId>/<ISO8601-timestamp>/
actor ProjectBackupService {

    static let shared = ProjectBackupService()
    private init() {}

    private let fileManager = FileManager.default

    private var backupsRoot: URL {
        get throws {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupport.appendingPathComponent("Backups", isDirectory: true)
        }
    }

    private func backupDirectory(for projectId: String) throws -> URL {
        try backupsRoot.appendingPathComponent(projectId, isDirectory: true)
    }

    // MARK: - Public API

    /// Creates a timestamped backup snapshot of a project directory.
    func createBackup(for projectId: String, projectDirectory: URL) async throws -> BackupManifest {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupDir = try backupDirectory(for: projectId)
            .appendingPathComponent(timestamp, isDirectory: true)

        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try fileManager.copyItem(at: projectDirectory, to: backupDir.appendingPathComponent("project"))

        let manifest = BackupManifest(
            projectId: projectId,
            timestamp: Date(),
            backupPath: backupDir.path
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: backupDir.appendingPathComponent("manifest.json"))

        return manifest
    }

    /// Lists all backups for a project, sorted newest-first.
    func listBackups(for projectId: String) async -> [BackupManifest] {
        guard let backupDir = try? backupDirectory(for: projectId),
              let entries = try? fileManager.contentsOfDirectory(
                  at: backupDir,
                  includingPropertiesForKeys: [.creationDateKey],
                  options: .skipsHiddenFiles
              ) else { return [] }

        return entries.compactMap { dir -> BackupManifest? in
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) else { return nil }
            return manifest
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    /// Restores a project from a backup, overwriting the current project directory.
    func restoreBackup(_ manifest: BackupManifest, to projectDirectory: URL) async throws {
        let backupProjectDir = URL(fileURLWithPath: manifest.backupPath)
            .appendingPathComponent("project")

        // Remove current project content
        if fileManager.fileExists(atPath: projectDirectory.path) {
            try fileManager.removeItem(at: projectDirectory)
        }

        try fileManager.copyItem(at: backupProjectDir, to: projectDirectory)
    }

    /// Deletes old backups, keeping only the N most recent.
    func pruneOldBackups(for projectId: String, keepCount: Int = 5) async throws {
        let all = await listBackups(for: projectId)
        guard all.count > keepCount else { return }
        let toDelete = all.dropFirst(keepCount)
        for manifest in toDelete {
            let backupDir = URL(fileURLWithPath: manifest.backupPath)
            try? fileManager.removeItem(at: backupDir)
        }
    }
}
```

> **Adjust `BackupManifest` init** to match the actual struct's properties (read it in Task E1).

---

### Task E3: Register in ServiceContainer

Read `LiquidEditor/Services/ServiceContainer.swift`. Find where other services are declared as properties. Add:

```swift
let projectBackupService: ProjectBackupService = .shared
```

---

### Task E4: Run xcodegen and build

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodegen generate
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`. Common issues:
- `BackupManifest` init parameter names differ → fix to match actual struct
- `Codable` conformance missing → add `extension BackupManifest: Codable {}` if needed (but first check if it's already Codable)
- Actor isolation issue → all methods are `actor`-isolated, confirm no `@MainActor` calls from inside without `Task { @MainActor in ... }`

---

## Final Validation (Run After All Groups Complete)

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodegen generate
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
xcodebuild test -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

Both must succeed before declaring the task complete.

---

## Documentation Updates

After all tasks pass:

1. Update `docs/FEATURES.md` — mark "Animated transition previews", "Text effect presets", "Drag-reorder projects", "Batch delete projects", "Project backups", "Tracking bbox overlay", "KeyframeEditor connected" as ✅ Complete
2. Update `analysis/FLUTTER_SWIFT_GAP_ANALYSIS.md` — move all implemented items to "Resolved" section, update overall parity from ~90% to ~97%
3. Update `analysis/INDEX.md` — add 1 new file (ProjectBackupService), update statistics
