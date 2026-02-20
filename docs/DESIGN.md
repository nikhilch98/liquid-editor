# Liquid Editor - Design & Architecture

**A comprehensive guide to the design philosophy, architecture patterns, and technical decisions behind Liquid Editor.**

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Build & Development Commands](#build--development-commands)
3. [Project Structure](#project-structure)
4. [System Architecture](#system-architecture)
   - [Architecture Diagram](#architecture-diagram)
   - [MVVM + Coordinator + Repository](#mvvm--coordinator--repository)
   - [ServiceContainer DI](#servicecontainer-dependency-injection)
   - [Core Concepts](#core-concepts)
5. [Design System (Liquid Glass)](#design-system-liquid-glass)
6. [State Management](#state-management)
7. [Concurrency Model](#concurrency-model)
8. [Timeline Architecture](#timeline-architecture)
9. [GPU Rendering Pipeline](#gpu-rendering-pipeline)
10. [Architecture Decisions & Rationale](#architecture-decisions--rationale)
11. [Related Documentation](#related-documentation)

---

## Project Overview

**Liquid Editor** is a premium video editing app for iOS built entirely in **Swift/SwiftUI**. The app features keyframe-based video transformations, person tracking with Apple's Vision framework, multi-track timeline with persistent immutable data structures, Metal GPU rendering, and the iOS 26 Liquid Glass design system.

### Project Stats

- **Swift Source Files:** 185 files
- **Test Files:** 45 files
- **Total Tests:** 1,918 (all passing)
- **Architecture:** MVVM + Coordinator + Repository
- **State Management:** @Observable macro (Observation framework)
- **Concurrency:** Swift 6 strict concurrency (actors, @MainActor, Sendable)
- **Dependencies:** swift-collections, swift-algorithms (SPM)
- **Minimum iOS:** 18.0
- **Build System:** xcodegen (project.yml)

---

## Build & Development Commands

### Build & Test

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"

# Regenerate Xcode project after adding/removing files
xcodegen generate

# Build for iOS (no code signing)
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO

# Run all tests
xcodebuild test -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,id=C7A15E20-CAA1-4480-B2BA-392A94328930' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO

# Open in Xcode for debugging
open LiquidEditor.xcodeproj
```

### Xcodegen

The project uses `xcodegen` with `project.yml` to generate the Xcode project. **Always run `xcodegen generate` after adding or removing Swift files.**

---

## Project Structure

```
LiquidEditor/
├── LiquidEditor/
│   ├── App/
│   │   └── LiquidEditorApp.swift           # App entry point
│   ├── DesignSystem/
│   │   ├── Modifiers/
│   │   │   └── GlassEffect.swift           # Liquid Glass view modifier
│   │   └── Tokens/
│   │       ├── LiquidColors.swift          # Color palette
│   │       ├── LiquidSpacing.swift         # Spacing constants
│   │       └── LiquidTypography.swift      # Typography styles
│   ├── Extensions/
│   │   └── CMTime+Codable.swift            # CMTime serialization
│   ├── Metal/
│   │   └── Shaders/                        # Metal shader files
│   ├── Models/
│   │   ├── Audio/                          # AudioEffect, AudioFade, BeatMap, etc.
│   │   ├── Clips/                          # VideoClip, AudioClip, TextClip, GapClip, etc.
│   │   ├── ColorGrading/                   # ColorGrade, FilterPreset, LUTReference, etc.
│   │   ├── Common/                         # ARGBColor, ComparisonConfig
│   │   ├── Compositing/                    # MultiTrackState, TrackCompositeConfig, etc.
│   │   ├── Effects/                        # VideoEffect, EffectChain, EffectParameter
│   │   ├── Export/                         # ExportConfig, ExportJob, FileSizeEstimator
│   │   ├── Keyframe/                       # Keyframe, VideoTransform
│   │   ├── Markers/                        # MarkerStore
│   │   ├── Masking/                        # Mask
│   │   ├── Media/                          # MediaAsset
│   │   ├── PanScan/                        # PanScanConfig
│   │   ├── Person/                         # Person
│   │   ├── Project/                        # Project, ProjectSettings, ProjectTemplate
│   │   ├── Protocols/                      # Shared model protocols
│   │   ├── Speed/                          # Speed ramp models
│   │   ├── Sticker/                        # Sticker models
│   │   ├── Text/                           # Text overlay models
│   │   ├── Timeline/                       # PersistentTimeline, TimelineNode, Track, etc.
│   │   └── Tracking/                       # Tracking data models
│   ├── Navigation/
│   │   └── AppCoordinator.swift            # @Observable navigation coordinator
│   ├── Repositories/
│   │   ├── Protocols/                      # Repository protocol definitions
│   │   ├── ProjectRepository.swift         # Project persistence
│   │   ├── MediaAssetRepository.swift      # Media asset management
│   │   ├── PersonRepository.swift          # Person data
│   │   ├── DraftRepository.swift           # Draft management
│   │   ├── BackupRepository.swift          # Backup management
│   │   └── PreferencesRepository.swift     # User preferences
│   ├── Services/
│   │   ├── Animation/                      # Animation services
│   │   ├── Audio/                          # AudioEffectsEngine, AudioMixerService
│   │   ├── AutoReframe/                    # AutoReframeEngine
│   │   ├── ColorGrading/                   # ColorGradingPipeline (12-stage)
│   │   ├── Composition/                    # PersistentTimeline, CompositionManager, PlaybackEngine
│   │   ├── Effects/                        # EffectPipeline (CIContext + Metal)
│   │   ├── Export/                         # Export pipeline
│   │   ├── Masking/                        # Mask rendering
│   │   ├── MediaImport/                    # Media import service
│   │   ├── People/                         # Person management
│   │   ├── Project/                        # AutoSaveService, ProjectDuplicateService
│   │   ├── Protocols/                      # Service protocol definitions
│   │   ├── Speed/                          # SpeedProcessor
│   │   ├── Sticker/                        # Sticker services
│   │   ├── Subtitle/                       # SubtitleManager
│   │   ├── Tracking/                       # TrackingService, BoundingBoxTracker, KalmanFilter
│   │   ├── Transitions/                    # TransitionRenderer
│   │   ├── Utility/                        # HapticService, ContentHash, etc.
│   │   ├── VideoProcessing/               # VideoProcessingService, VideoConstants
│   │   └── ServiceContainer.swift          # DI container
│   ├── Timeline/
│   │   ├── Cache/                          # ThumbnailCache, WaveformCache, MemoryOptimizer
│   │   ├── Editing/                        # Split, Trim, Clipboard, Snap, Ripple controllers
│   │   ├── Features/                       # ClipThumbnailService, MagneticSnap, MultiSelect
│   │   ├── Gestures/                       # DragController, HitTesting, TrimController, Zoom
│   │   └── Rendering/                      # ClipsRenderer, PlayheadRenderer, RulerRenderer
│   ├── ViewModels/
│   │   ├── EditorViewModel.swift           # Main editor state
│   │   ├── ExportViewModel.swift           # Export state
│   │   ├── PlaybackViewModel.swift         # Playback state
│   │   ├── ProjectLibraryViewModel.swift   # Project list state
│   │   ├── SettingsViewModel.swift         # Settings state
│   │   └── TimelineViewModel.swift         # Timeline state
│   └── Views/
│       ├── Editor/                         # EditorView, VideoPreviewView, Overlays
│       ├── Onboarding/                     # OnboardingView
│       ├── Preview/                        # ComparisonView, FullscreenPreviewView
│       ├── ProjectLibrary/                 # ProjectLibraryView, ProjectCardView
│       ├── Settings/                       # SettingsView
│       ├── Sheets/                         # All modal sheets (Export, Color, Text, etc.)
│       └── Timeline/                       # TimelineView, PlaybackControlsView, ClipView
├── LiquidEditorTests/                      # 45 test files, 1,918 tests
│   ├── DesignSystem/
│   ├── Extensions/
│   ├── Models/                             # Tests for all model types
│   ├── Navigation/
│   ├── Repositories/
│   └── Services/                           # Tests for services and composition
└── project.yml                             # xcodegen configuration
```

---

## System Architecture

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                              │
├──────────────────────────────────────────────────────────────────┤
│  ProjectLibraryView ─── EditorView ─── TimelineView              │
│  ExportSheet ─── ColorGradingSheet ─── TextEditorSheet           │
│  PersonSelectionSheet ─── AutoReframePanel                        │
│       │                                                           │
│       │  @Observable ViewModels                                   │
│       ├─── ProjectLibraryViewModel                                │
│       ├─── EditorViewModel (main editor state)                    │
│       ├─── TimelineViewModel                                      │
│       ├─── PlaybackViewModel                                      │
│       ├─── ExportViewModel                                        │
│       └─── SettingsViewModel                                      │
└──────────────────────────────────────┬───────────────────────────┘
                                       │
                                       │  Services (via ServiceContainer)
                                       ▼
┌──────────────────────────────────────────────────────────────────┐
│                    ServiceContainer (DI)                           │
├──────────────────────────────────────────────────────────────────┤
│  Composition Layer:                                               │
│  ├─ CompositionManager        # AVComposition orchestration       │
│  ├─ PersistentTimeline        # Immutable AVL tree, O(log n)     │
│  └─ PlaybackEngine (actor)    # Playback, scrubbing, frame cache │
│                                                                   │
│  Processing Layer:                                                │
│  ├─ MultiTrackCompositor      # Metal GPU rendering               │
│  ├─ EffectPipeline            # CIContext + Metal effects         │
│  ├─ ColorGradingPipeline      # 12-stage color grading           │
│  ├─ AudioEffectsEngine        # Real-time audio effects          │
│  └─ SpeedProcessor            # Time remapping                    │
│                                                                   │
│  Tracking & Vision:                                               │
│  ├─ TrackingService           # Vision framework orchestrator     │
│  ├─ BoundingBoxTracker        # VNTrackObjectRequest              │
│  ├─ KalmanFilter              # Trajectory smoothing              │
│  ├─ AutoReframeEngine         # Auto-reframe algorithm            │
│  └─ PersonIdentifier          # Re-ID across scenes              │
│                                                                   │
│  I/O Layer:                                                       │
│  ├─ MediaImportService        # Video/audio/image import          │
│  ├─ ExportService             # Video export pipeline             │
│  ├─ ProjectRepository         # Project persistence (JSON)        │
│  ├─ MediaAssetRepository      # Media asset management            │
│  └─ AutoSaveService           # Auto-save with debounce          │
└──────────────────────────────────────────────────────────────────┘
                                       │
                                       │  Apple Frameworks
                                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  AVFoundation  │  Vision  │  Metal  │  CoreImage  │  Accelerate  │
└──────────────────────────────────────────────────────────────────┘
```

### MVVM + Coordinator + Repository

The app follows a strict **MVVM + Coordinator + Repository** architecture:

- **Models:** Pure Swift value types (structs) that are `Codable` and `Sendable`. Located in `Models/`.
- **Views:** SwiftUI views that observe ViewModels via the Observation framework. Located in `Views/`.
- **ViewModels:** `@Observable @MainActor` classes that hold UI state and orchestrate services. Located in `ViewModels/`.
- **Coordinator:** `AppCoordinator` manages navigation state as an `@Observable` class. Located in `Navigation/`.
- **Repositories:** Handle persistence (file I/O, JSON encoding/decoding). Located in `Repositories/`.
- **Services:** Stateless or actor-isolated business logic. Located in `Services/`.

### ServiceContainer Dependency Injection

All services are registered and resolved through `ServiceContainer`:

```swift
// Registration (at app startup)
@MainActor
final class ServiceContainer {
    static let shared = ServiceContainer()

    lazy var compositionManager = CompositionManager()
    lazy var trackingService = TrackingService()
    lazy var effectPipeline = EffectPipeline()
    lazy var colorGradingPipeline = ColorGradingPipeline()
    lazy var exportService = ExportService()
    // ... etc
}

// Usage in ViewModels
@Observable
@MainActor
final class EditorViewModel {
    private let services = ServiceContainer.shared

    func applyEffect(_ effect: VideoEffect) async {
        await services.effectPipeline.apply(effect, to: currentFrame)
    }
}
```

### Core Concepts

#### 1. PersistentTimeline (Immutable AVL Tree)

The timeline uses a persistent (immutable) order statistic tree for O(log n) operations:

- **Lookup:** Find clip at any time position in O(log n)
- **Insert/Delete:** O(log n) with path copying (structural sharing)
- **Undo/Redo:** O(1) pointer swap between immutable snapshots
- **Memory:** Only modified path nodes are copied; unchanged subtrees are shared

```swift
// Timeline operations return new trees, never mutate
let newTimeline = timeline.inserting(clip, at: position)
let afterSplit = timeline.splitting(clipId: id, at: splitPoint)
```

#### 2. Multi-Track State

`MultiTrackState` holds all tracks (video, audio, text, sticker) as immutable data:

- Track ordering and visibility
- Per-track `PersistentTimeline` instances
- Composite configurations (blend mode, opacity)
- Gap-based absolute positioning for overlay tracks

#### 3. Playback Engine

`PlaybackEngine` is an **actor** that manages playback lifecycle:

- AVPlayer management
- Frame cache with LRU eviction (120 frames)
- Predictive prefetch based on scrub direction
- Double-buffered AVComposition for zero-interruption editing

#### 4. Person Tracking System

Uses Apple Vision framework for detection and tracking:

- **BoundingBoxTracker:** VNDetectHumanRectanglesRequest + VNTrackObjectRequest
- **KalmanFilter:** Trajectory smoothing for jitter reduction
- **PersonIdentifier:** Re-identification across scenes using appearance features
- **AutoReframeEngine:** Automatic keyframe generation to keep subjects in frame

---

## Design System (Liquid Glass)

The app uses the iOS 26 **Liquid Glass** design system:

### Visual Style
- Glassmorphic panels with frosted blur backgrounds
- Dynamic translucency and vibrancy
- Subtle shadows and depth layers
- SF Symbols for all iconography
- San Francisco font family throughout

### Key SwiftUI Components
- `.glassEffect()` modifier for Liquid Glass surfaces
- `.ultraThinMaterial` / `.regularMaterial` for blur backgrounds
- `NavigationStack` with native iOS navigation
- `TabView` with native tab bar styling
- Native sheets, alerts, and action sheets

### Design Tokens
- **Colors:** `LiquidColors` -- system-adaptive color palette
- **Typography:** `LiquidTypography` -- predefined text styles
- **Spacing:** `LiquidSpacing` -- consistent spacing scale

### Haptic Feedback
- Selection changes: `UISelectionFeedbackGenerator`
- Impact events: `UIImpactFeedbackGenerator`
- Notifications: `UINotificationFeedbackGenerator`

---

## State Management

All state management uses the **Observation** framework (`@Observable` macro):

| ViewModel | Purpose | Key State |
|-----------|---------|-----------|
| `EditorViewModel` | Main editor orchestration | Current project, active tool, timeline state |
| `TimelineViewModel` | Timeline interaction | Clips, tracks, selection, zoom level |
| `PlaybackViewModel` | Playback control | Play/pause, current time, playback rate |
| `ProjectLibraryViewModel` | Project list | Projects, sort order, filter |
| `ExportViewModel` | Export pipeline | Export config, progress, status |
| `SettingsViewModel` | App settings | Preferences, storage info |

### Data Flow

```
User Action → View → ViewModel method → Service call → Model mutation
                                                            │
                              View update ← ViewModel state ←
```

SwiftUI views observe ViewModel properties via the Observation framework. When a ViewModel property changes, only views that read that specific property are invalidated.

---

## Concurrency Model

### Actor Isolation

- **@MainActor:** All ViewModels, all SwiftUI views, all UI-bound services
- **actor:** I/O-bound services (PlaybackEngine, export pipeline)
- **@unchecked Sendable + OSAllocatedUnfairLock:** GPU hot-path services (MultiTrackCompositor)
- **nonisolated:** Pure computation methods that do not access mutable state

### Task Management

- Use structured concurrency (`async let`, `TaskGroup`) where possible
- Avoid unstructured `Task {}` creation except at View-level (`task` modifier)
- Cancel tasks properly when views disappear

---

## Timeline Architecture

The timeline system is built on immutable data structures:

### PersistentTimeline (AVL Order Statistic Tree)

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Lookup at time | O(log n) | Tree traversal using subtree durations |
| Insert clip | O(log n) | Path copying + AVL rebalance |
| Delete clip | O(log n) | Path copying + AVL rebalance |
| Split clip | O(log n) | Delete + 2 inserts |
| Undo/Redo | O(1) | Pointer swap between snapshots |

### Clip Type Hierarchy

| Type | Purpose |
|------|---------|
| `VideoClip` | Source video segment with in/out points |
| `AudioClip` | Audio with volume and mute controls |
| `ImageClip` | Still image with configurable duration |
| `GapClip` | Empty space / overlay positioning spacer |
| `ColorClip` | Solid color generator |
| `TextClip` | Text overlay with styling and animation |
| `StickerClip` | Sticker overlay with position and scale |

### TimeMicros

All time values use `TimeMicros` (Int64 typealias) for microsecond precision. This avoids floating-point drift and provides exact frame-accurate positioning.

---

## GPU Rendering Pipeline

### Metal Shaders

Metal shaders handle real-time video compositing:

- Multi-layer compositing with blend modes
- Color grading (12-stage pipeline via CIContext + Metal)
- Real-time effects (blur, color adjustments, etc.)
- Efficient texture management

### Effect Pipeline

The `EffectPipeline` uses `CIContext` backed by a Metal device for GPU-accelerated image processing:

```swift
final class EffectPipeline {
    private let ciContext: CIContext
    private let metalDevice: MTLDevice

    func apply(_ effects: EffectChain, to image: CIImage) -> CIImage {
        var result = image
        for effect in effects.effects {
            result = effect.apply(to: result)
        }
        return result
    }
}
```

---

## Architecture Decisions & Rationale

### Why Pure Swift (Not Flutter)?

- **Full access** to all Apple frameworks (Vision, Metal, AVFoundation, CoreImage)
- **No platform channel overhead** -- direct API calls
- **Swift 6 strict concurrency** for compile-time data race prevention
- **SwiftUI** for native iOS 26 Liquid Glass design
- **Better performance** -- no cross-language bridge

### Why @Observable (Not ObservableObject)?

- **Fine-grained observation** -- only views reading changed properties are invalidated
- **No `@Published` boilerplate** -- properties are automatically observable
- **Better performance** -- SwiftUI only recomputes affected view bodies
- **Modern pattern** -- recommended by Apple for new projects

### Why Immutable Timeline (PersistentTimeline)?

- **O(1) undo/redo** via pointer swap (no state reconstruction)
- **Structural sharing** minimizes memory (only changed path is copied)
- **Thread safety** -- immutable data is inherently safe to share
- **Reliability** -- no partial mutation bugs

### Why Actors for I/O Services?

- **Compile-time safety** -- Swift enforces isolation boundaries
- **No manual locking** -- actor provides automatic serialization
- **Clear API** -- callers must `await` actor methods
- **Eliminates data races** at the language level

### Why ServiceContainer (Not SwiftUI @Environment)?

- **Testability** -- services can be mocked by replacing container entries
- **Lifecycle control** -- services persist beyond view hierarchy
- **Explicit dependencies** -- clear what each ViewModel depends on
- **Non-view code** -- services can access other services without SwiftUI

### Why Gap-Based Overlay Positioning?

- **Reuses PersistentTimeline** for overlay tracks (same O(log n) operations)
- **Unified undo/redo** across all track types
- **Simple model** -- GapClip spacers create absolute time positions
- **Acceptable trade-off** -- rebuild is O(n) per overlay track, but overlay tracks typically have < 50 items

---

## Related Documentation

- **[CODING_STANDARDS.md](CODING_STANDARDS.md)** -- Swift coding conventions and quality standards
- **[FEATURES.md](FEATURES.md)** -- Feature catalog and status
- **[APP_LOGIC.md](APP_LOGIC.md)** -- Implementation details and data flow
- **[PERFORMANCE.md](PERFORMANCE.md)** -- Performance targets and profiling
- **[TESTING.md](TESTING.md)** -- Testing framework and patterns
- **[WORKFLOW.md](WORKFLOW.md)** -- Development workflow
- **[Timeline Architecture V2](plans/2026-01-30-timeline-architecture-v2-design.md)** -- Detailed timeline design document

---

**Last Updated:** 2026-02-13
