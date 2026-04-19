# Liquid Editor - Implementation Details & Technical Logic

**Document Purpose:** Technical reference for data flow, state management, service interactions, and implementation patterns in the pure Swift Liquid Editor.

**Last Updated:** 2026-04-19

---

## Premium UI Redesign

The editor screen was restructured around the premium-UI spec
(`docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md`). Key
structural changes visible to code working on the editor surface:

- **Tab bar:** a 5-tab model (`EditorTabID.edit / audio / text / fx / color`)
  replaces the legacy Edit / FX / Overlay / Audio / Smart tabs. The legacy
  `EditorTab` enum is retained for source compatibility but the active tab
  is driven by `EditorViewModel.selectedTab`.
- **Tool strip:** each tab exposes exactly 6 tools via
  `EditorViewModel.currentTabTools`, which returns `ToolStripButton`
  arrays (`editTabTools`, `audioTabTools`, `textTabTools`, `fxTabTools`,
  `colorTabTools`). Tool closures route through existing methods or
  `setActivePanel(...)`.
- **Right-hand inspector:** inspector panels are composed per-tab and
  read from the currently selected clip. Panels use the
  `ActiveToolPanel` enum for sheet routing (`.colorGrading`,
  `.videoEffects`, `.crop`, `.transition`, `.audioEffects`,
  `.textEditor`, `.stickerPicker`, `.volume`, `.speed`,
  `.trackManagement`, `.keyframeEditor`, `.autoReframe`, `.personSelection`).
- **Centralized edit commands:** `TimelineCutCommand`,
  `TimelineDeleteCommand`, and `RippleEditController` mediate ripple vs
  non-ripple behavior for all destructive edits triggered from the
  tool strip.
- **Clipboard model:** `ClipboardStore` holds a single
  `TimelineClipboardEntry` for Cut / Copy / Paste across the tool strip.
- **ViewModel contract:** `EditorViewModel` remains the single
  `@Observable @MainActor` state owner; inspector panels observe its
  properties directly rather than owning their own state.

---

## Table of Contents

1. [MVVM Data Flow](#mvvm-data-flow)
2. [Navigation (AppCoordinator)](#navigation-appcoordinator)
3. [ServiceContainer Interactions](#servicecontainer-interactions)
4. [Timeline State Management](#timeline-state-management)
5. [Playback Engine Lifecycle](#playback-engine-lifecycle)
6. [Multi-Track Overlay Architecture](#multi-track-overlay-architecture)
7. [Tracking Pipeline](#tracking-pipeline)
8. [Auto-Reframe Pipeline](#auto-reframe-pipeline)
9. [Export Pipeline](#export-pipeline)
10. [Color Grading Pipeline](#color-grading-pipeline)
11. [Key File Locations](#key-file-locations)
12. [Dependencies](#dependencies)
13. [Known Issues & Resolved Issues](#known-issues--resolved-issues)

---

## MVVM Data Flow

### @Observable Property Observation

ViewModels use the `@Observable` macro. SwiftUI automatically tracks which properties each view reads and only recomputes view bodies when those specific properties change.

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI View                      │
│                                                      │
│  var body: some View {                               │
│      Text(viewModel.projectName)  // observes name   │
│      if viewModel.isPlaying {     // observes state  │
│          PlaybackIndicator()                         │
│      }                                               │
│  }                                                   │
│                                                      │
│  // Only re-evaluated when projectName or isPlaying  │
│  // changes, NOT when other ViewModel props change   │
└─────────────────────────┬───────────────────────────┘
                          │
                          │ reads @Observable properties
                          ▼
┌─────────────────────────────────────────────────────┐
│             @Observable @MainActor ViewModel         │
│                                                      │
│  var projectName: String = ""     // tracked         │
│  var isPlaying: Bool = false      // tracked         │
│  var currentTime: TimeMicros = 0  // tracked         │
│                                                      │
│  func play() {                                       │
│      isPlaying = true             // triggers update │
│      Task {                                          │
│          await playbackEngine.play()                 │
│      }                                               │
│  }                                                   │
└─────────────────────────┬───────────────────────────┘
                          │
                          │ calls services
                          ▼
┌─────────────────────────────────────────────────────┐
│              Services (via ServiceContainer)          │
│                                                      │
│  PlaybackEngine (actor)                              │
│  CompositionManager                                  │
│  TrackingService                                     │
│  EffectPipeline                                      │
│  ...                                                 │
└─────────────────────────────────────────────────────┘
```

### ViewModel Responsibilities

| ViewModel | Responsibilities |
|-----------|-----------------|
| `EditorViewModel` | Active project, active tool panel, undo/redo orchestration, clip/keyframe management |
| `TimelineViewModel` | Timeline zoom, scroll position, track visibility, clip selection, gesture handling |
| `PlaybackViewModel` | Play/pause state, current time, playback rate, loop mode |
| `ProjectLibraryViewModel` | Project list, sort/filter, project CRUD operations |
| `ExportViewModel` | Export configuration, progress, status, cancellation |
| `SettingsViewModel` | User preferences, storage analysis, app info |

### View-to-ViewModel Binding

Views access ViewModels either directly (created in the view) or via SwiftUI environment:

```swift
struct EditorView: View {
    @State private var viewModel = EditorViewModel()

    var body: some View {
        VStack {
            VideoPreviewView(viewModel: viewModel)
            TimelineView(viewModel: viewModel.timelineViewModel)
            PlaybackControlsView(viewModel: viewModel.playbackViewModel)
        }
    }
}
```

---

## Navigation (AppCoordinator)

### AppCoordinator

**Location:** `LiquidEditor/Navigation/AppCoordinator.swift`

The `AppCoordinator` is an `@Observable @MainActor` class that manages all navigation state:

```swift
@Observable
@MainActor
final class AppCoordinator {
    var currentRoute: AppRoute = .projectLibrary
    var presentedSheet: SheetType?
    var activeProject: Project?

    func openProject(_ project: Project) {
        activeProject = project
        currentRoute = .editor
    }

    func showExport() {
        presentedSheet = .export
    }

    func dismissSheet() {
        presentedSheet = nil
    }
}
```

### Navigation Flow

```
App Launch
    │
    ▼
ProjectLibraryView
    │ (tap project)
    ▼
EditorView
    │ (tap export)
    ▼
ExportSheet (presented as sheet)
    │ (dismiss)
    ▼
EditorView
    │ (back)
    ▼
ProjectLibraryView
```

### Sheet Presentation

All modal sheets (export, color grading, text editor, sticker picker, etc.) are managed via `AppCoordinator.presentedSheet`. The root view observes this property and presents the appropriate sheet.

---

## ServiceContainer Interactions

### Service Dependency Graph

```
EditorViewModel
    ├── CompositionManager
    │   ├── PersistentTimeline (immutable data)
    │   └── PlaybackEngine (actor)
    │       └── AVPlayer
    ├── TrackingService
    │   ├── BoundingBoxTracker (Vision)
    │   ├── KalmanFilter
    │   └── TrackingDataStore
    ├── EffectPipeline
    │   └── CIContext (Metal-backed)
    ├── ColorGradingPipeline
    │   └── CIContext (Metal-backed)
    ├── AutoReframeEngine
    │   └── TrackingService (reads results)
    ├── MediaImportService
    │   └── MediaAssetRepository
    ├── ExportService
    │   └── AVAssetExportSession
    └── ProjectRepository
        └── FileManager (JSON I/O)
```

### Service Lifecycle

1. **App Launch:** `ServiceContainer.shared` is initialized lazily
2. **Project Open:** `EditorViewModel` is created, accesses services from container
3. **Editing:** ViewModel methods call service methods (async when crossing actor boundaries)
4. **Project Close:** ViewModel is deallocated; services persist in container for next project
5. **App Background:** Auto-save triggers via `AutoSaveService`

---

## Timeline State Management

### PersistentTimeline Operations

**Location:** `LiquidEditor/Services/Composition/PersistentTimeline.swift`

All timeline operations return **new** `PersistentTimeline` instances. The original is never mutated:

```swift
// Insert a clip
let newTimeline = timeline.inserting(clip, at: position)

// Delete a clip
let newTimeline = timeline.removing(clipId: id)

// Split a clip at a time point
let newTimeline = timeline.splitting(clipId: id, at: splitPoint)

// Trim a clip's in/out points
let newTimeline = timeline.trimming(clipId: id, newInPoint: inPoint, newOutPoint: outPoint)
```

### Undo/Redo via Pointer Swap

**Location:** `LiquidEditor/Services/Composition/CompositionManager.swift`

The undo/redo system stores immutable `MultiTrackState` snapshots:

```
Undo Stack: [State_0, State_1, State_2]
Current:     State_3  <-- pointer
Redo Stack:  []

After Undo:
Undo Stack: [State_0, State_1]
Current:     State_2  <-- pointer swapped
Redo Stack:  [State_3]
```

Each undo/redo operation is a single pointer swap -- O(1) time. The immutable states share structure via path copying, so memory usage is proportional to the number of changed nodes, not the full timeline.

### TimeMicros

All time values are stored as `TimeMicros` (Int64 typealias) representing microseconds. This avoids floating-point drift and provides exact frame-accurate positioning:

```swift
typealias TimeMicros = Int64

// Convert from seconds
let timeMicros: TimeMicros = Int64(seconds * 1_000_000)

// Convert from CMTime
let timeMicros: TimeMicros = Int64(CMTimeGetSeconds(cmTime) * 1_000_000)
```

---

## Playback Engine Lifecycle

### PlaybackEngine (Actor)

**Location:** `LiquidEditor/Services/Composition/PlaybackEngine.swift`

The `PlaybackEngine` is an `actor` that manages AVPlayer lifecycle:

```
┌─────────────────────────────────────────┐
│           PlaybackEngine (actor)         │
│                                          │
│  States:                                 │
│  ├── idle       (no media loaded)        │
│  ├── loading    (setting up AVPlayer)    │
│  ├── ready      (paused, ready to play)  │
│  ├── playing    (actively playing)       │
│  └── seeking    (seeking to position)    │
│                                          │
│  Key Methods:                            │
│  ├── loadComposition(_:)                 │
│  ├── play()                              │
│  ├── pause()                             │
│  ├── seek(to:)                           │
│  ├── setRate(_:)                         │
│  └── currentTime -> TimeMicros           │
│                                          │
│  Frame Cache:                            │
│  ├── LRU eviction (120 frames)           │
│  ├── Predictive prefetch                 │
│  └── Memory pressure response            │
└─────────────────────────────────────────┘
```

### Playback Data Flow

```
User taps Play
    │
    ▼
PlaybackViewModel.play()
    │
    ▼
PlaybackEngine.play()  (actor call, awaited)
    │
    ▼
AVPlayer.play()
    │
    ▼
Time observer fires (periodic)
    │
    ▼
PlaybackViewModel.currentTime updated
    │
    ▼
SwiftUI views observing currentTime re-evaluate
    │
    ▼
Timeline playhead position updates
Video preview frame updates
Time display updates
```

### Double-Buffered Composition

When the timeline is edited during playback:

1. Edit occurs on current `MultiTrackState`
2. Background: New `AVMutableComposition` is built from updated state
3. Hot-swap: New composition replaces current in AVPlayer
4. Playback continues without interruption

---

## Multi-Track Overlay Architecture

### Gap-Based Absolute Positioning

Overlay tracks (text, sticker) use `GapClip` spacers to achieve absolute time positioning within the sequential `PersistentTimeline`:

```
Track Layout:
[Video Track  ] [===== clip1 =====][===== clip2 =====]
[Text Track   ] [--gap 5.2s--][text overlay 2.8s][--gap 4.5s--][text overlay 2.5s]
[Sticker Track] [----gap 10s----][sticker 3s][---gap 2s---]
```

### Overlay Operations

| Operation | Algorithm |
|-----------|-----------|
| Insert overlay at time T | Extract non-gap items with positions, add new item, sort by time, rebuild timeline with GapClip spacers |
| Remove overlay | Extract remaining non-gap items, rebuild with recalculated gaps |
| Move overlay to new time | Update item position, sort, rebuild with gaps |

### Serialization

The `Project` model supports dual-write serialization:

- **`multiTrackStateJson`**: Full multi-track state (authoritative source)
- **Legacy fields**: Backward-compatible overlay arrays

On load, `multiTrackStateJson` takes precedence when present.

---

## Tracking Pipeline

### End-to-End Tracking Flow

```
User starts tracking analysis
    │
    ▼
TrackingService.analyzeVideo(url:)
    │
    ▼
BoundingBoxTracker  ──→  VNDetectHumanRectanglesRequest
    │                         (initial detection)
    ▼
VNTrackObjectRequest  ──→  Frame-by-frame tracking
    │
    ▼
KalmanFilter.smooth()  ──→  Jitter reduction
    │
    ▼
TrackingDataStore.addResult()  ──→  Store normalized coordinates
    │
    ▼
Post-processing:
├── Integral smoothing (Gaussian temporal window)
├── Gap filling (constant-velocity prediction for ≤5 frame gaps)
└── Quality metrics calculation
    │
    ▼
Results available to:
├── TrackingOverlayView (bounding box rendering)
├── AutoReframeEngine (keyframe generation)
└── PersonSelectionSheet (person thumbnails)
```

### Coordinate System

All tracking results use **normalized coordinates** (0.0 to 1.0), making them resolution-independent. This allows the same tracking data to work with proxy videos, original resolution, and export resolution.

---

## Auto-Reframe Pipeline

### Keyframe Generation Flow

```
AutoReframeEngine.generateKeyframes(from: trackingResults)
    │
    ▼
For each time window (500ms intervals):
    │
    ├── Find closest tracking result
    ├── Compute averaged bounding box (lookahead 5 frames)
    ├── Compute target transform (scale + translation to center subject)
    ├── Apply dead zone filter (skip if change < threshold)
    ├── Apply temporal smoothing (exponential moving average)
    │   └── Adaptive smoothing based on movement velocity
    ├── Check significance (translation > 2% or scale > 5%)
    └── Create keyframe if significant
    │
    ▼
Return array of Keyframe objects with easeInOut interpolation
```

### Configuration

| Parameter | Range | Default | Purpose |
|-----------|-------|---------|---------|
| `zoomIntensity` | 0.8-2.5x | 1.2x | How tightly subjects are framed |
| `followSpeed` | 0.0-1.0 | 0.3 | Temporal smoothing (0 = smooth, 1 = instant) |
| `safeZonePadding` | 0.0-0.3 | 0.1 | Extra padding around bounding box |
| `maxZoom` | 1.0-5.0 | 3.0 | Maximum zoom level |
| `minZoom` | 0.5-1.0 | 1.0 | Minimum zoom level |

---

## Export Pipeline

### Export Flow

```
User configures export (ExportSheet)
    │
    ▼
ExportViewModel.startExport(config:)
    │
    ▼
ExportService.export(project:, config:)  (async)
    │
    ├── Build AVMutableComposition from timeline
    ├── Apply video effects via EffectPipeline
    ├── Apply color grading via ColorGradingPipeline
    ├── Mix audio via AudioMixerService
    ├── Render text/sticker overlays
    │
    ▼
AVAssetExportSession
    │
    ├── Progress updates → ExportViewModel.progress
    ├── Cancellation support → ExportViewModel.cancel()
    │
    ▼
Output file saved to Documents/Exports/
    │
    ▼
ExportViewModel.status = .completed(url:)
```

---

## Color Grading Pipeline

### 12-Stage Pipeline

```
Input Frame (CIImage)
    │
    ├── 1. Exposure adjustment
    ├── 2. Contrast adjustment
    ├── 3. Highlights recovery
    ├── 4. Shadows lift
    ├── 5. Temperature shift
    ├── 6. Tint adjustment
    ├── 7. Saturation
    ├── 8. Vibrance
    ├── 9. HSL per-channel adjustments
    ├── 10. RGB curves
    ├── 11. Luma curve
    └── 12. LUT application (optional)
    │
    ▼
Output Frame (CIImage)
```

All stages use `CIFilter` backed by a Metal `CIContext` for GPU acceleration.

---

## Key File Locations

### Models

| Directory | Key Files | Purpose |
|-----------|-----------|---------|
| `Models/Clips/` | `VideoClip.swift`, `AudioClip.swift`, `TextClip.swift`, `GapClip.swift`, `TimelineItem.swift` | Clip type hierarchy |
| `Models/Timeline/` | `PersistentTimeline` types, `Track`, `TimelineNode` | Timeline data structures |
| `Models/Compositing/` | `MultiTrackState.swift`, `TrackCompositeConfig.swift` | Multi-track state |
| `Models/Project/` | `Project.swift`, `ProjectSettings.swift` | Project model |
| `Models/Media/` | `MediaAsset.swift` | Media asset with UUID + hash |
| `Models/Keyframe/` | `Keyframe.swift`, `VideoTransform.swift` | Keyframe data |
| `Models/Export/` | `ExportConfig.swift`, `ExportJob.swift` | Export configuration |
| `Models/Effects/` | `VideoEffect.swift`, `EffectChain.swift` | Effect definitions |
| `Models/ColorGrading/` | `ColorGrade.swift`, `FilterPreset.swift`, `LUTReference.swift` | Color grading data |
| `Models/Audio/` | `AudioEffect.swift`, `AudioFade.swift`, `BeatMap.swift` | Audio data |

### Services

| Directory | Key Files | Purpose |
|-----------|-----------|---------|
| `Services/Composition/` | `PersistentTimeline.swift`, `CompositionManager.swift`, `PlaybackEngine.swift` | Timeline and playback |
| `Services/Effects/` | `EffectPipeline.swift` | GPU effect processing |
| `Services/ColorGrading/` | `ColorGradingPipeline.swift` | 12-stage color grading |
| `Services/Audio/` | `AudioEffectsEngine.swift` | Audio effects |
| `Services/Tracking/` | `TrackingService.swift`, `BoundingBoxTracker.swift`, `KalmanFilter.swift` | Vision tracking |
| `Services/AutoReframe/` | `AutoReframeEngine.swift` | Auto-reframe algorithm |
| `Services/Export/` | Export pipeline | Video export |
| `Services/MediaImport/` | Media import | Media import |
| `Services/` | `ServiceContainer.swift` | Dependency injection |

### ViewModels

| File | Purpose |
|------|---------|
| `ViewModels/EditorViewModel.swift` | Main editor state |
| `ViewModels/TimelineViewModel.swift` | Timeline interaction |
| `ViewModels/PlaybackViewModel.swift` | Playback control |
| `ViewModels/ProjectLibraryViewModel.swift` | Project list |
| `ViewModels/ExportViewModel.swift` | Export pipeline |
| `ViewModels/SettingsViewModel.swift` | App settings |

### Navigation

| File | Purpose |
|------|---------|
| `Navigation/AppCoordinator.swift` | @Observable navigation coordinator |

### Repositories

| File | Purpose |
|------|---------|
| `Repositories/ProjectRepository.swift` | Project persistence (JSON) |
| `Repositories/MediaAssetRepository.swift` | Media asset management |
| `Repositories/PersonRepository.swift` | Person data persistence |
| `Repositories/DraftRepository.swift` | Draft management |
| `Repositories/BackupRepository.swift` | Backup management |
| `Repositories/PreferencesRepository.swift` | User preferences |

---

## Dependencies

### Swift Package Manager (SPM)

| Package | Purpose |
|---------|---------|
| swift-collections | OrderedDictionary, Deque, and other efficient collections |
| swift-algorithms | Algorithmic utilities (chunked, combinations, etc.) |

### Apple Frameworks

| Framework | Purpose |
|-----------|---------|
| SwiftUI | UI framework |
| AVFoundation | Video playback, composition, export |
| Vision | Person detection, object tracking, segmentation |
| Metal | GPU rendering, shader execution |
| CoreImage | Image processing, filters, color grading |
| Accelerate | High-performance math (vDSP, vImage) |
| PhotosUI | Photo library picker |
| UniformTypeIdentifiers | File type identification |

---

## Known Issues & Resolved Issues

### Resolved Issues

*This section tracks previously discovered and fixed bugs.*

(No issues tracked yet for the pure Swift project. Add entries as bugs are discovered and fixed.)

### Known Issues

*This section tracks currently known issues.*

(No known issues tracked yet. Add entries as they are discovered.)

---

## Related Documentation

- **[DESIGN.md](DESIGN.md)** -- Architecture and design decisions
- **[FEATURES.md](FEATURES.md)** -- Feature catalog and status
- **[CODING_STANDARDS.md](CODING_STANDARDS.md)** -- Swift coding conventions
- **[TESTING.md](TESTING.md)** -- Testing framework and patterns
- **[WORKFLOW.md](WORKFLOW.md)** -- Development workflow
- **[PERFORMANCE.md](PERFORMANCE.md)** -- Performance targets
- **[Timeline Architecture V2](plans/2026-01-30-timeline-architecture-v2-design.md)** -- Detailed timeline design

---

**Last Updated:** 2026-02-13
