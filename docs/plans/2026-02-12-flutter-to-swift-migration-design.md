# Flutter to Pure Swift/SwiftUI Migration Design

**Date:** 2026-02-12
**Status:** Reviewed (3-Pass Complete) — Ready for Implementation
**Scope:** Full migration of Liquid Editor from Flutter (258 Dart files, ~94k lines) + native Swift (48 files, ~20.5k lines) to pure SwiftUI + UIKit + Metal iOS application

---

## 1. Executive Summary

### Why Migrate?

1. **Zero latency** — Eliminate 29 platform channel round-trips (1-3ms each per call)
2. **Native Liquid Glass** — iOS 26 glassMorphism, vibrancy, and depth natively (no Flutter Cupertino approximations)
3. **Metal everywhere** — GPU-accelerated timeline rendering at 120fps, compute shaders for effects
4. **Binary size** — ~45MB → ~25MB (no Flutter engine overhead)
5. **Developer velocity** — Single language, single debugger, Xcode Instruments profiling
6. **App Store compliance** — Native accessibility, Dynamic Type, VoiceOver out of the box

### Key Decisions (Revised Post-Review)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | SwiftUI + UIKit | SwiftUI primary, UIKit for Metal views and complex gesture handling |
| Architecture | MVVM + Coordinator + Repository | Protocol-first, testable, clean dependency graph |
| State Management | `@Observable` (iOS 17+) | 1:1 replacement for ChangeNotifier, automatic view updates |
| Concurrency | Lock-protected classes + actors selectively | Actors for I/O-bound services only; `OSAllocatedUnfairLock` for hot-path (FrameCache, renderer) |
| Timeline Data | `final class PersistentTimeline` | Must be class (not struct) for reference-counted node sharing + Sendable |
| Timeline Renderer | Core Graphics first → Metal 3 upgrade | Incremental approach: prove gestures work, then optimize with Metal |
| Video Pipeline | AVFoundation + custom AVVideoCompositing | Preserve existing compositor, direct integration (no channels) |
| Effects Pipeline | Metal Compute + CIFilter | GPU compute for custom effects, CIFilter for standard ones |
| Persistence | Codable + explicit CodingKeys + JSON | Backward-compatible with Dart JSON via explicit key mapping |
| Min iOS | iOS 26 | Liquid Glass APIs, latest SwiftUI features, Metal 3 |
| Testing | XCTest + Swift Testing | Unit + UI + performance tests, 1:1 coverage parity |

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    SwiftUI Views Layer                       │
│  (Liquid Glass, NavigationStack, .sheet, .inspector)        │
├─────────────────────────────────────────────────────────────┤
│                 Coordinators (Navigation)                    │
│  (AppCoordinator, EditorCoordinator)                        │
├─────────────────────────────────────────────────────────────┤
│               @Observable ViewModels                         │
│  (SmartEditVM, TimelineVM, ExportVM, ColorGradingVM, ...)   │
├─────────────────────────────────────────────────────────────┤
│                   Core Engines                               │
│  (PersistentTimeline, FrameCache, ScrubController,          │
│   TransformInterpolator, AutoReframeEngine)                 │
├─────────────────────────────────────────────────────────────┤
│                  Repositories                                │
│  (ProjectRepo, MediaRepo, TrackingRepo, PeopleRepo, ...)   │
├─────────────────────────────────────────────────────────────┤
│                   Services                                   │
│  (TrackingService, EffectPipeline, CompositionBuilder,      │
│   AudioEffectsEngine, ColorGradingPipeline, ExportService)  │
├─────────────────────────────────────────────────────────────┤
│              Domain Models (Codable structs)                 │
│  (VideoClip, Track, MultiTrackState, MediaAsset, ...)       │
├─────────────────────────────────────────────────────────────┤
│                  Metal Layer                                  │
│  (TimelineRenderer, WaveformRenderer, EffectCompute,        │
│   TransitionRenderer, ThumbnailGenerator)                   │
└─────────────────────────────────────────────────────────────┘
```

### Review Findings Incorporated

The following critical issues from 3-pass review are now addressed:

1. **FrameCache**: Changed from `actor` to `final class: @unchecked Sendable` with `OSAllocatedUnfairLock` — actors serialize access and would miss 120fps scrubbing targets
2. **MetalTimelineRenderer**: Removed actor isolation — `MTLCommandBuffer` is not `Sendable` and cannot cross actor boundaries
3. **PersistentTimeline**: Changed from `struct` to `final class` — reference-counted `TreeNode` sharing cannot be value-type semantics
4. **TreeNode**: All properties made `let` (immutable) for true persistence and Sendable conformance
5. **Phase ordering**: Services now before Core Engines (Core depends on Services)
6. **Phase 0 added**: Audit existing Swift `*Native` structs before model migration
7. **CodingKeys**: All Codable models require explicit CodingKeys for Dart JSON compatibility
8. **CMTime**: Custom Codable as Double seconds (CMTime is not natively Codable)
9. **Timeline renderer**: Core Graphics fallback (Phase 6a) before Metal optimization (Phase 6b)
10. **Accessibility**: MTKView accessibility overlay required for App Store compliance
11. **Missing files**: 18+ models, 20+ core files, 49 timeline files added to phases
12. **Greenfield layers**: Repositories and ViewModels acknowledged as new architecture (not migrations)

---

## 2. Project Structure

```
LiquidEditor/
├── App/
│   ├── LiquidEditorApp.swift              # @main SwiftUI App
│   ├── AppCoordinator.swift               # Root navigation coordinator
│   ├── EditorCoordinator.swift            # Editor-specific navigation
│   └── DependencyContainer.swift          # Dependency injection container
│
├── Models/
│   ├── Protocols/
│   │   ├── TimelineItem.swift             # Protocol for all timeline items
│   │   ├── Identifiable+Extensions.swift  # ID-based protocols
│   │   └── Copyable.swift                 # Immutable copy protocol
│   ├── Timeline/
│   │   ├── VideoClip.swift                # Video clip on timeline
│   │   ├── AudioClip.swift                # Audio clip
│   │   ├── TextClip.swift                 # Text overlay clip
│   │   ├── StickerClip.swift              # Sticker overlay clip
│   │   ├── ImageClip.swift                # Still image clip
│   │   ├── ColorClip.swift                # Solid color clip
│   │   ├── GapClip.swift                  # Gap spacer for overlays
│   │   ├── Track.swift                    # Track metadata
│   │   ├── TrackType.swift                # Track type enum
│   │   ├── ClipTransition.swift           # Transition between clips
│   │   ├── TransitionType.swift           # Transition type enum
│   │   ├── Marker.swift                   # Timeline marker
│   │   ├── ViewportState.swift            # Timeline viewport math
│   │   ├── SelectionState.swift           # Selection state
│   │   ├── TimeTypes.swift                # TimeMicros, TimeRange
│   │   ├── Rational.swift                 # Rational number (frame rates)
│   │   ├── TimelineNode.swift             # AVL tree node (immutable class)
│   │   ├── VolumeKeyframe.swift           # Volume automation keyframe
│   │   ├── VolumeEnvelope.swift           # Volume envelope with interpolation
│   │   └── EditOperations.swift           # Edit operation types
│   ├── Compositing/
│   │   ├── MultiTrackState.swift          # Multi-track immutable state
│   │   ├── TrackCompositeConfig.swift     # Per-track composite config
│   │   ├── CompositeLayer.swift           # Layer at a point in time
│   │   ├── CompositeLayout.swift          # Layout enum (pip, split, etc.)
│   │   ├── NormalizedRect.swift           # 0-1 coordinate rect
│   │   ├── ChromaKeyConfig.swift          # Chroma key settings
│   │   ├── SplitScreenTemplate.swift      # Split screen templates
│   │   ├── BlendMode.swift                # 17 blend modes
│   │   └── OverlayTransform.swift         # Overlay positioning transforms
│   ├── Effects/
│   │   ├── VideoEffect.swift              # Single video effect
│   │   ├── EffectType.swift               # 30+ effect types with CIFilter names
│   │   ├── EffectChain.swift              # Sequential effect chain
│   │   ├── EffectParameter.swift          # Type-erased parameter
│   │   ├── EffectKeyframe.swift           # Animated effect param
│   │   ├── EffectPreset.swift             # Preset configuration
│   │   ├── ColorGrade.swift               # 12-stage color grading
│   │   ├── ColorKeyframe.swift            # Animated color grade
│   │   ├── FilterPreset.swift             # Color grade preset
│   │   ├── HSLAdjustment.swift            # Per-channel HSL
│   │   ├── CurveData.swift                # Tone curves with Hermite interpolation
│   │   └── LUTReference.swift             # LUT file reference
│   ├── Audio/
│   │   ├── AudioFade.swift                # Fade in/out config
│   │   ├── AudioEffect.swift              # Audio effect definition
│   │   ├── AudioEffectType.swift          # Audio effect type enum
│   │   ├── AudioDuckingConfig.swift       # Ducking configuration
│   │   ├── BeatMap.swift                  # Beat detection results
│   │   ├── NoiseProfile.swift             # Noise reduction profile
│   │   ├── WaveformData.swift             # Waveform samples
│   │   └── SoundEffectAsset.swift         # Sound effect asset
│   ├── Text/
│   │   ├── TextOverlayStyle.swift         # Text styling (font, color, shadow, etc.)
│   │   ├── TextAnimationPreset.swift      # Text animation types
│   │   ├── TextKeyframe.swift             # Text animation keyframe
│   │   ├── TextTemplate.swift             # Text templates
│   │   └── SubtitleEntry.swift            # Subtitle entry
│   ├── Sticker/
│   │   ├── StickerAsset.swift             # Sticker asset definition
│   │   ├── StickerKeyframe.swift          # Sticker animation keyframe
│   │   └── StickerCategory.swift          # Sticker categories
│   ├── Project/
│   │   ├── Project.swift                  # Project model (Codable)
│   │   ├── ProjectMetadata.swift          # Project metadata
│   │   ├── ProjectSettings.swift          # Project-level settings
│   │   ├── FrameRate.swift                # Frame rate types
│   │   ├── Resolution.swift               # Export resolution types
│   │   ├── SyncStatus.swift               # iCloud sync state
│   │   └── StorageUsage.swift             # Storage analytics
│   ├── Tracking/
│   │   ├── TrackingSession.swift          # Tracking session model
│   │   ├── TrackingResult.swift           # Tracking result data
│   │   ├── NormalizedBoundingBox.swift    # Normalized bbox
│   │   ├── BodyOutline.swift              # Body contour data
│   │   ├── PoseJoints.swift               # Body pose joints
│   │   └── Person.swift                   # Person identity model
│   ├── Export/
│   │   ├── ExportConfig.swift             # Export configuration
│   │   ├── ExportPreset.swift             # Export preset definitions
│   │   ├── ExportJob.swift                # Export job tracking
│   │   ├── ExportProgress.swift           # Progress reporting
│   │   ├── SocialPreset.swift             # Social media presets
│   │   └── FileSizeEstimator.swift        # Export file size estimation
│   ├── MediaAsset/
│   │   ├── MediaAsset.swift               # Imported media asset
│   │   ├── MediaType.swift                # Media type enum
│   │   └── ImportSource.swift             # Import source tracking
│   ├── Keyframe/
│   │   ├── Keyframe.swift                 # Transform keyframe
│   │   ├── VideoTransform.swift           # Scale/translate/rotate transform
│   │   ├── InterpolationType.swift        # 21 easing types
│   │   └── KeyframeTimeline.swift         # Keyframe container
│   ├── Mask/
│   │   ├── Mask.swift                     # Mask definition
│   │   └── MaskType.swift                 # Mask shape types
│   ├── Speed/
│   │   ├── SpeedConfig.swift              # Speed settings
│   │   └── SpeedRamp.swift                # Speed ramp keyframes
│   └── PanScan/
│       ├── PanScanConfig.swift            # Ken Burns effect config
│       └── PanScanRegion.swift            # Pan/scan viewport keyframes
│
├── Core/
│   ├── Timeline/
│   │   ├── PersistentTimeline.swift       # Persistent Order Statistic Tree (AVL) — FINAL CLASS
│   │   ├── TimelineState.swift            # Timeline + transitions (immutable)
│   │   ├── TimelineManager.swift          # @Observable single-track manager
│   │   ├── MultiTrackTimelineManager.swift # @Observable multi-track manager
│   │   └── TransitionController.swift     # Transition validation and management
│   ├── Playback/
│   │   ├── PlaybackEngine.swift           # AVPlayer-based playback
│   │   ├── CompositionManager.swift       # Double-buffered composition
│   │   ├── CompositionPlaybackController.swift # Playback coordination
│   │   ├── PlaybackEngineController.swift # Engine lifecycle
│   │   ├── ScrubController.swift          # Velocity-based scrubbing
│   │   └── FrameCache.swift              # LRU frame cache — LOCK-PROTECTED CLASS (not actor)
│   ├── Transform/
│   │   ├── TransformInterpolator.swift    # 21 easing types with LRU cache
│   │   ├── InterpolationUtils.swift       # Hermite spline utilities
│   │   ├── GestureCaptureEngine.swift     # Pinch/pan/rotate → transforms
│   │   └── AutoReframeEngine.swift        # Intelligent auto-crop
│   ├── Editing/
│   │   ├── EffectStore.swift              # Per-clip effect management
│   │   ├── AudioController.swift          # Audio operations coordinator
│   │   ├── ClipManager.swift              # Clip CRUD operations
│   │   ├── KeyframeManager.swift          # Keyframe CRUD
│   │   ├── TextClipManager.swift          # Text clip operations
│   │   ├── SubtitleManager.swift          # Subtitle management
│   │   ├── TextAnimationEvaluator.swift   # Text animation evaluation
│   │   └── ProjectStorage.swift           # Atomic save/load with auto-save
│   ├── Decoder/
│   │   └── DecoderPool.swift              # LRU video decoder pool
│   ├── Sticker/
│   │   ├── StickerFavoritesManager.swift  # Sticker favorites
│   │   ├── GifFrameCache.swift            # GIF frame caching
│   │   ├── StickerImageCache.swift        # Sticker image cache
│   │   └── StickerImportService.swift     # Sticker import pipeline
│   ├── Util/
│   │   ├── ContentHash.swift              # SHA-256 content hashing
│   │   └── UserPreferences.swift          # User preferences storage
│   └── Timeline/Editing/                  # Timeline editing controllers
│       ├── SnapController.swift           # Magnetic snap
│       ├── ClipboardController.swift      # Copy/cut/paste
│       ├── SplitController.swift          # Clip splitting
│       ├── SlipSlideController.swift      # Slip/slide editing
│       ├── RippleTrimController.swift     # Ripple trim
│       └── MarkerController.swift         # Marker management
│
├── Services/
│   ├── Protocols/
│   │   ├── TrackingServiceProtocol.swift
│   │   ├── EffectPipelineProtocol.swift
│   │   ├── CompositionServiceProtocol.swift
│   │   ├── AudioServiceProtocol.swift
│   │   └── ExportServiceProtocol.swift
│   ├── Tracking/                          # 11 files — actor for I/O-bound ops
│   ├── Effects/                           # 3 files — lock-protected for GPU ops
│   ├── ColorGrading/                      # 7 files (merged Dart + Swift)
│   ├── Audio/                             # 8 files (merged Dart + Swift)
│   ├── Export/                            # 9 files (merged Dart + Swift)
│   ├── Composition/                       # 4 files — keep existing Metal/AVF
│   ├── MediaImport/                       # 6 files (merged Dart + Swift)
│   ├── People/                            # 2 files
│   ├── Proxy/                             # 2 files
│   ├── Speed/                             # 1 file
│   ├── Project/                           # 7 files (NEW — from Dart services)
│   ├── Masking/                           # 2 files
│   ├── Haptics/                           # 1 file
│   └── Storage/                           # 1 file
│
├── Repositories/                          # NEW architecture layer (greenfield)
│   ├── ProjectRepository.swift
│   ├── MediaAssetRepository.swift
│   ├── TrackingRepository.swift
│   ├── PeopleRepository.swift
│   ├── PreferencesRepository.swift
│   └── ExportRepository.swift
│
├── ViewModels/                            # NEW MVVM layer (12 of 13 are greenfield)
│   ├── ProjectLibraryViewModel.swift
│   ├── SmartEditViewModel.swift           # Port of existing Dart ViewModel
│   ├── TimelineViewModel.swift
│   ├── TrackingViewModel.swift
│   ├── ExportViewModel.swift
│   ├── ColorGradingViewModel.swift
│   ├── AudioViewModel.swift
│   ├── TextEditorViewModel.swift
│   ├── StickerViewModel.swift
│   ├── CropViewModel.swift
│   ├── SpeedViewModel.swift
│   ├── TransitionViewModel.swift
│   └── SettingsViewModel.swift
│
├── Views/                                 # ~50+ SwiftUI views (decomposed)
│   ├── Library/                           # 7 views
│   ├── Editor/                            # 20+ views (decomposed from 5,403-line smart_edit_view.dart)
│   ├── Timeline/                          # 10+ views (gesture + rendering)
│   ├── ColorGrading/                      # 4 views
│   ├── Effects/                           # 3 views
│   ├── Export/                            # 4 views
│   ├── Text/                              # 6 views
│   ├── Sticker/                           # 3 views
│   ├── Audio/                             # 3 views
│   ├── Crop/                              # 2 views
│   ├── Speed/                             # 2 views
│   ├── Transition/                        # 2 views
│   ├── Tracking/                          # 2 views
│   ├── Settings/                          # 2 views
│   └── Components/                        # 6+ reusable glass components
│
├── Metal/
│   ├── Shaders/
│   │   ├── Timeline.metal
│   │   ├── Waveform.metal
│   │   ├── Transition.metal
│   │   ├── Effects.metal
│   │   └── Common.metal
│   ├── TimelineRenderer.swift             # NON-ACTOR, lock-protected
│   ├── WaveformRenderer.swift
│   ├── ThumbnailTextureCache.swift
│   ├── TexturePool.swift                  # Texture recycling (no per-frame alloc)
│   └── MetalContext.swift                 # Shared MTLDevice/CommandQueue + shader prewarming
│
├── DesignSystem/
│   ├── LiquidGlassTheme.swift
│   ├── Typography.swift
│   ├── Haptics.swift
│   └── Animations.swift
│
├── Extensions/
│   ├── CMTime+Extensions.swift            # CMTime helpers + normalization
│   ├── CMTime+Codable.swift               # Custom Codable (encode as Double seconds)
│   ├── CGRect+Extensions.swift
│   ├── Color+Extensions.swift
│   ├── UIImage+Extensions.swift
│   └── Task+Extensions.swift
│
├── Accessibility/
│   └── TimelineAccessibilityOverlay.swift # UIAccessibilityElement overlay for Metal MTKView
│
└── Tests/
    ├── ModelTests/                         # ~300 tests (1:1 parity with Dart)
    ├── CoreTests/                          # ~400 tests
    ├── ServiceTests/                       # ~200 tests
    ├── RepositoryTests/                    # ~100 tests (greenfield)
    ├── ViewModelTests/                     # ~200 tests (greenfield)
    ├── IntegrationTests/                   # ~50 tests
    ├── PerformanceTests/                   # ~50 tests (XCTMetric)
    └── CompatibilityTests/                 # ~100 tests (Dart JSON round-trip)
```

---

## 3. Migration Phases (Revised Order)

Tests are written alongside each phase (never deferred). Each phase produces a compilable, testable module.

**CRITICAL REVISION**: Phase order changed from original based on Review Pass 3 findings.
- Services BEFORE Core Engines (Core depends on Services)
- Core Graphics timeline BEFORE Metal (incremental de-risking)
- Phase 0 added for existing Swift model audit

### Phase 0: Swift Audit & Cleanup (~1 day)

**Goal:** Audit existing Swift `*Native` structs and plan merge strategy.

**Tasks:**
1. Inventory all existing native structs in `ios/Runner/`:
   - `TrackCompositeConfigNative` in `MultiTrackInstruction.swift`
   - `NormalizedRectNative` in `MultiTrackInstruction.swift`
   - `ChromaKeyConfigNative` in `MultiTrackInstruction.swift`
   - Other inline model definitions
2. Document merge strategy for each:
   - Replace `init(from dictionary: [String: Any])` with Codable
   - Map existing field names to Dart JSON keys
3. Identify platform channel methods that will be eliminated
4. Create complete platform channel inventory (all 29 channels)

**Tests:** None (documentation phase)

---

### Phase 1: Xcode Project Setup + Foundation Types (~2 days)

**Goal:** Create the Xcode project with SPM, Metal setup, and foundation types.

**Tasks:**
1. Create new Xcode project (iOS App, SwiftUI lifecycle, iOS 26 deployment target)
2. Configure Metal support (MTLDevice, shader compilation)
3. Configure Swift strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`)
4. Set up test targets (XCTest + Swift Testing)
5. Add SPM dependencies: `swift-collections`, `swift-algorithms`
6. Port foundation types:
   - `Rational` — Rational number with arithmetic (CMTime interop)
   - `TimeTypes` — `TimeMicros` typealias, `TimeRange` struct, conversions
   - `TimelineNode` — AVL tree node as `final class` with immutable `let` properties
   - `InterpolationType` — 21 easing types as enum with compute functions
   - `CMTime+Codable` — Custom Codable for CMTime (encode as Double seconds)

**Dart → Swift mapping patterns established here:**
```swift
// Dart: @immutable class with copyWith
// Swift: struct (value type, automatic copy-on-write)
struct VideoClip: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let mediaAssetId: String
    var sourceInMicros: Int64
    var sourceOutMicros: Int64

    // REQUIRED: Explicit CodingKeys for Dart JSON compatibility
    enum CodingKeys: String, CodingKey {
        case id
        case mediaAssetId = "media_asset_id"
        case sourceInMicros = "source_in_micros"
        case sourceOutMicros = "source_out_micros"
    }
}

// Dart: ChangeNotifier
// Swift: @Observable (main-actor isolated, NOT actor)
@Observable
final class TimelineManager {
    private(set) var state: TimelineState
    private var undoStack: [TimelineState] = []
    // ...
}

// Dart: enum with methods
// Swift: enum with RawRepresentable + methods
enum TrackType: String, Codable, CaseIterable, Sendable {
    case mainVideo, overlayVideo, text, sticker, audio, music, voiceover
    var supportsVideo: Bool { ... }
}
```

**Tests:** ~60 tests for foundation types

---

### Phase 2: Domain Models (~6 days, +1 day for existing Swift model merge)

**Goal:** Port all ~85 Dart model files to Swift Codable structs. Merge existing `*Native` structs.

**Critical Patterns:**

```swift
// 1. All models MUST have explicit CodingKeys matching Dart JSON
enum CodingKeys: String, CodingKey {
    case clipId = "clip_id"
    case trackId = "track_id"
    case startTime = "start_time"
}

// 2. CMTime fields encoded as Double seconds
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let durationSeconds = try container.decode(Double.self, forKey: .duration)
    duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
}

// 3. Nullable copyWith with clear flags
extension VideoClip {
    func with(name: String? = nil, clearName: Bool = false) -> VideoClip {
        var copy = self
        if clearName { copy.name = nil }
        else if let name { copy.name = name }
        return copy
    }
}

// 4. TimelineItemContent — Protocol-based (not enum, for scalability)
protocol TimelineItem: Codable, Sendable, Identifiable {
    var id: String { get }
    var durationMicros: Int64 { get }
    var itemType: TimelineItemType { get }
}

enum TimelineItemType: String, Codable {
    case video, audio, text, sticker, image, color, gap
}

// Type-erased container for Codable serialization
struct AnyTimelineItem: Codable, Sendable {
    let base: any TimelineItem
    // Custom Codable dispatches on itemType
}
```

**Tests:** ~300 tests — JSON round-trips with REAL Dart-exported JSON, equality, computed properties

---

### Phase 3: Services Layer — Refactor Existing Swift (~4 days)

**MOVED BEFORE Core Engines** (Core depends on Services).

**Goal:** Strip Flutter dependencies from 48 existing Swift files + port ~35 Dart service files. Add protocol abstractions.

**Approach:** For each existing Swift service file:
1. Remove `import Flutter`, `FlutterMethodChannel`, `FlutterEventChannel`, `FlutterResult`
2. Replace callback-based `FlutterResult` with `async throws -> T`
3. Add protocol conformance for testability
4. For I/O-bound services: Use `actor`
5. For GPU/hot-path services: Use `@unchecked Sendable` with `OSAllocatedUnfairLock`

**Key subsystems:**

| Subsystem | Files | Concurrency Model |
|-----------|-------|-------------------|
| Tracking (11 files) | TrackingService, BoundingBoxTracker, etc. | `actor` (I/O-bound Vision requests) |
| Composition (5 files) | CompositionBuilder, MultiTrackCompositor, etc. | Lock-protected (GPU-bound) |
| Effects (3 files) | EffectPipeline, VideoEffectsCache, CropCache | Lock-protected (`CIContext` not thread-safe for concurrent render) |
| ColorGrading (7 files) | Merge Dart + Swift into unified service | Lock-protected |
| Audio (8 files) | Merge Dart + Swift, add protocol | `actor` |
| Export (9 files) | Merge, use `AsyncStream` for progress | `actor` |
| MediaImport (6 files) | Merge, direct PHPicker integration | `actor` |
| Project (7 files) | NEW from Dart services | `actor` |

**Tests:** ~200 tests for service protocols and implementations

---

### Phase 4: Core Engines (~6 days)

**Goal:** Port the core engine classes that form the editing brain.

#### 4a. PersistentTimeline (Persistent Order Statistic Tree)
```swift
/// Persistent AVL tree with O(log n) ops and structural sharing
/// FINAL CLASS — not struct (reference-counted nodes require class semantics)
final class PersistentTimeline: @unchecked Sendable, Equatable {
    private let root: TimelineNode?  // TreeNode is immutable (all let properties)

    // Queries — O(log n)
    func itemAtTime(_ timeMicros: Int64) -> (item: any TimelineItem, startTime: Int64)?
    func startTimeOf(id: String) -> Int64?  // O(1) via cached index
    func getById(_ id: String) -> (any TimelineItem)?  // O(1)

    // Mutations — return NEW timeline, O(log n)
    func insertAt(_ timeMicros: Int64, item: any TimelineItem) -> PersistentTimeline
    func append(_ item: any TimelineItem) -> PersistentTimeline
    func remove(id: String) -> PersistentTimeline
    func updateItem(id: String, _ item: any TimelineItem) -> PersistentTimeline

    // Equatable — compare root identity (O(1) for structural sharing)
    static func == (lhs: PersistentTimeline, rhs: PersistentTimeline) -> Bool {
        lhs.root === rhs.root
    }
}

/// TreeNode — IMMUTABLE class for structural sharing + Sendable
final class TimelineNode: @unchecked Sendable {
    let left: TimelineNode?
    let right: TimelineNode?
    let item: any TimelineItem
    let size: Int
    let height: Int
    let totalDuration: Int64

    // All properties are let — no mutation after construction
    init(left: TimelineNode?, right: TimelineNode?, item: any TimelineItem, ...) { ... }
}
```
**Tests:** ~52 tests

#### 4b. FrameCache (Lock-Protected, NOT Actor)
```swift
/// Thread-safe LRU frame cache — synchronous access for 120fps scrubbing
/// OSAllocatedUnfairLock provides <0.1ms lock acquisition vs actor's 2-10ms scheduling
final class FrameCache: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<CacheState>()
    private let maxFrames: Int

    struct CacheState {
        var cache: [Int64: CachedFrame] = [:]  // Key: normalized microseconds
        var lruOrder: [Int64] = []
    }

    /// Synchronous read — <0.1ms (no async, no actor scheduling)
    func getFrame(assetId: String, timeMicros: Int64) -> CachedFrame? {
        lock.withLock { state in
            state.cache[timeMicros]
        }
    }

    /// Background prefetch — async, cancellable
    func prefetchInBackground(around timeMicros: Int64, radius: Int) -> Task<Void, Never> {
        Task.detached(priority: .utility) { [weak self] in
            for offset in -radius...radius {
                try? Task.checkCancellation()
                // decode frame, then lock.withLock { insert }
            }
        }
    }
}
```
**Tests:** ~41 tests (including concurrent access stress tests)

#### 4c-4h. Other Core Engines
- TimelineState, TimelineManager, MultiTrackTimelineManager
- TransformInterpolator (21 easing, LRU cache, simd_float4x4)
- ScrubController, PlaybackEngine, GestureCaptureEngine, AutoReframeEngine
- Timeline editing controllers (snap, clipboard, split, slip/slide, ripple trim, marker)
- All ported 1:1. `ChangeNotifier` → `@Observable`.

**Undo/redo history:** Capped at 100 entries (ring buffer) to prevent unbounded memory growth.

**Tests:** ~400 tests total for Phase 4

---

### Phase 5: Repositories (~2 days)

**Goal:** Create repository layer between ViewModels and Services.
**NOTE:** These are GREENFIELD implementations (no Dart equivalents exist).

```swift
/// Project persistence with atomic save, auto-save, and migration
actor ProjectRepository {
    func save(_ project: Project) async throws
    func load(id: String) async throws -> Project
    func loadAll() async -> [Project]
    func delete(id: String) async throws
    func scheduleAutoSave(_ project: Project, delay: Duration = .seconds(2))
}

/// Media asset registry with content-hash dedup
actor MediaAssetRepository {
    func register(_ asset: MediaAsset) -> (asset: MediaAsset, isNew: Bool)
    func getById(_ id: String) -> MediaAsset?
    func getByHash(_ hash: String) -> MediaAsset?
    func search(_ query: String) -> [MediaAsset]
}
```

**Tests:** ~100 tests for all 6 repositories

---

### Phase 6a: Core Graphics Timeline (NEW — ~3 days)

**Goal:** Prove timeline gesture logic with simple Core Graphics rendering before Metal.

**Tasks:**
1. Implement `TimelineCanvasView` (UIView with `draw(_:)`)
2. Render tracks, clips, playhead using Core Graphics
3. Wire up all 5+ gesture recognizers (pan, pinch, long press, drag, double-tap)
4. Implement hit testing with priority (playhead > ruler > trim > clip > marker)
5. Add accessibility overlay with `UIAccessibilityElement` for each clip/track

**Why this exists:** Review 3 identified that building a full Metal NLE timeline from scratch is severely underestimated. Core Graphics proves all interaction logic works before Metal optimization.

**Tests:** ~30 tests for gesture logic + hit testing

---

### Phase 6b: Metal Timeline Renderer (~8 days)

**Goal:** GPU-accelerated NLE timeline rendering at 120fps.

**Architecture:**
```
MTKView (UIViewRepresentable in SwiftUI)
    ├── TrackLanePass       → Track backgrounds (instanced)
    ├── ClipRectPass        → Clip rectangles with rounded corners (instanced)
    ├── ThumbnailPass       → Clip thumbnail textures (textured quads)
    ├── WaveformPass        → Audio waveform rendering (line strips)
    ├── TransitionPass      → Transition indicators
    ├── OverlayPass         → Selection highlights, snap guides
    ├── PlayheadPass        → Playhead line + time indicator
    └── TextPass            → Timecodes, clip labels (Core Text → MTLTexture)
```

**Critical implementation details:**
```swift
/// NON-ACTOR Metal renderer — MTLCommandBuffer is not Sendable
final class MetalTimelineRenderer: @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let texturePool: TexturePool     // Reuse textures (no per-frame alloc)
    private let lock = OSAllocatedUnfairLock()

    init?() {
        // Failable init — Metal unavailable on simulator
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        self.texturePool = TexturePool(device: device)

        // Prewarm all shaders at init
        prewarmShaders()
    }

    private func prewarmShaders() {
        // Compile all pipeline states upfront to avoid 50-200ms first-render stall
        Task.detached(priority: .utility) { [device] in
            let library = device.makeDefaultLibrary()!
            _ = try? device.makeRenderPipelineState(descriptor: clipPipelineDescriptor(library))
            _ = try? device.makeRenderPipelineState(descriptor: waveformPipelineDescriptor(library))
            // ... all 7 passes
        }
    }
}
```

**Accessibility:**
```swift
/// Invisible overlay providing VoiceOver access to Metal-rendered timeline
class TimelineAccessibilityOverlay: UIView {
    override var accessibilityElements: [Any]? {
        get {
            clips.map { clip in
                let element = UIAccessibilityElement(accessibilityContainer: self)
                element.accessibilityLabel = "\(clip.name), \(clip.trackName), \(clip.formattedDuration)"
                element.accessibilityFrame = clip.screenRect
                element.accessibilityTraits = .button
                return element
            }
        }
        set { }
    }
}
```

**Tests:** ~50 performance tests (render time < 2ms per frame at 1080p)

---

### Phase 7: ViewModels (~3 days)

**Goal:** Create `@Observable` ViewModels connecting Views to Core/Services.
**NOTE:** 12 of 13 ViewModels are GREENFIELD (only SmartEditViewModel exists in Dart).

```swift
@Observable
final class SmartEditViewModel {
    // Dependencies (injected)
    private let timelineManager: MultiTrackTimelineManager
    private let compositionManager: CompositionManager
    private let trackingService: TrackingServiceProtocol
    private let projectRepository: ProjectRepository

    // Published state
    var currentProject: Project?
    var isPlaying: Bool = false
    var playheadMicros: Int64 = 0
    var selectedClipId: String?
    var activeToolPanel: ToolPanel?

    // Actions
    func play() async { ... }
    func pause() { ... }
    func seek(to micros: Int64) async { ... }
    func undo() { timelineManager.undo() }
    func redo() { timelineManager.redo() }
}
```

**Tests:** ~200 tests for all 13 ViewModels

---

### Phase 8: SwiftUI Views with Liquid Glass (~10 days)

**Goal:** Build all UI screens with native iOS 26 Liquid Glass design.
**CRITICAL:** Decompose `smart_edit_view.dart` (5,403 lines) into 20+ small SwiftUI views.

**Decomposition plan for SmartEditView:**
```
SmartEditView.swift                    # Container (~100 lines)
├── EditorPreviewView.swift            # AVPlayer (UIViewRepresentable)
├── EditorToolbarView.swift            # Top toolbar with glass effect
├── EditorBottomBar.swift              # Bottom glass tab bar
├── EditorPlaybackControls.swift       # Play/pause/scrub
├── EditorTimelineContainer.swift      # Hosts Metal timeline
├── GestureOverlayView.swift           # Touch gesture capture
├── TrackingOverlayView.swift          # Bounding box overlay
├── KeyframeEditorSheet.swift          # Keyframe editing
├── KeyframeTimelineView.swift         # Keyframe timeline
├── VolumeControlSheet.swift           # Volume controls
├── SpeedControlSheet.swift            # Speed controls
├── PersonSelectionSheet.swift         # Person multi-select
├── AutoReframePanel.swift             # Auto-reframe controls
├── OverlayItemWidget.swift            # Text/sticker overlay
├── TrackDebugSheet.swift              # Debug overlay
├── EditorSidebar.swift                # Track management panel
├── FullscreenPreviewView.swift        # Fullscreen preview
├── ComparisonView.swift               # Before/after comparison
├── GridOverlayView.swift              # Composition grid
└── SafeZoneOverlayView.swift          # Safe zone guides
```

**Liquid Glass implementation:**
```swift
// iOS 26 native materials (no custom glass simulation needed)
NavigationStack {
    ProjectLibraryView()
        .navigationTitle("Projects")
        .toolbar { ... }
}

// Glass toolbar
struct EditorToolbar: View {
    var body: some View {
        HStack { /* tool buttons */ }
            .padding()
            .background(.regularMaterial)
            .clipShape(Capsule())
    }
}
```

**App Lifecycle:**
```swift
@main
struct LiquidEditorApp: App {
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            AppCoordinatorView()
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: autoSave()
                    case .inactive: pausePlayback()
                    default: break
                    }
                }
        }
    }
}
```

**Tests:** XCUITest for critical flows + snapshot tests

---

## 4. Dart → Swift Pattern Mapping

| Dart Pattern | Swift Equivalent |
|-------------|-----------------|
| `@immutable class` + `final` fields | `struct` (value type) |
| `copyWith({...})` | Custom method or `with()` extension |
| `factory fromJson(Map)` | `Codable` with explicit `CodingKeys` |
| `toJson() => Map` | `Codable` with explicit `CodingKeys` |
| `operator ==` + `hashCode` | `Equatable` conformance (auto-synthesized) |
| `ChangeNotifier` + `notifyListeners()` | `@Observable` (automatic, main-actor) |
| `Provider<T>` / `ChangeNotifierProvider` | `@Environment`, `@State`, `@Bindable` |
| `StatefulWidget` + `State<T>` | SwiftUI `View` with `@State` |
| `StatelessWidget` | SwiftUI `View` (struct) |
| `StreamController<T>` | `AsyncStream<T>` |
| `Future<T>` | `async throws -> T` |
| `Timer` | `Task.sleep` or `Timer.scheduledTimer` |
| `Uint8List` | `Data` or `[UInt8]` |
| `Float32List` | `[Float]` or `UnsafeBufferPointer<Float>` |
| `Map<String, dynamic>` | `[String: Any]` or typed struct |
| `List<T>` | `[T]` (Array) |
| `LinkedHashSet<T>` | `OrderedSet<T>` (swift-collections) |
| `SplayTreeMap<K, V>` | `SortedDictionary<K, V>` (swift-collections) |
| `compute()` isolate | `Task { }` on global executor |
| `MethodChannel` | Direct method call (no channel needed!) |
| `EventChannel` | `AsyncStream` |
| `Expando<T>` | `objc_setAssociatedObject` or computed cache |
| `CMTime` in JSON | Custom `Codable` — encode as `Double` seconds |
| `Offset` (dx, dy) | `CGPoint` with CodingKeys matching Dart field names |

---

## 5. Performance Targets

| Operation | Flutter (Current) | Swift (Target) | Approach |
|-----------|------------------|----------------|----------|
| App launch | < 2s | < 0.5s | No Flutter engine startup |
| Timeline render | 60fps | 120fps | Metal instanced rendering |
| Timeline scrub | < 50ms (uncached) | < 16ms | Metal + NVMe-optimized decode |
| Frame cache hit | < 2ms | < 0.1ms | Lock-protected direct memory (no actor scheduling) |
| Undo/redo | < 10μs | < 1μs | Same immutable pointer swap |
| Effect preview | ~16ms | < 8ms | Metal compute shaders |
| Composition build | < 20ms | < 10ms | Direct AVFoundation (no channel) |
| Channel overhead | 1-3ms/call | 0ms | Eliminated entirely |
| Memory (typical) | < 200MB | < 150MB | No Dart VM overhead |
| Binary size | ~45MB | ~25MB | No Flutter engine |
| Shader first render | N/A | < 5ms | Prewarmed at app launch |

**Measurement Strategy:**
- Device: iPhone 15 Pro (A17 Pro) or newer
- Timeline: 20 video clips, 3 tracks, 5 effects
- Tool: Instruments Metal System Trace
- GPU timing: `MTLCommandBuffer.gpuStartTime/gpuEndTime`
- Cache timing: `os_signpost` around cache lookup
- Timeline ops: `ContinuousClock.now` before/after

---

## 6. Test Migration Strategy

### Test count targets:

| Category | Dart Tests | Swift Tests (Target) | Notes |
|----------|-----------|---------------------|-------|
| Model tests | ~300 | ~300 | 1:1 port + CodingKeys tests |
| Core engine tests | ~400 | ~400 | 1:1 port + concurrency safety |
| Service tests | ~50 | ~200 | +150 new (services were behind channels) |
| ViewModel tests | 0 | ~200 | Greenfield (Dart had no ViewModel layer) |
| Repository tests | 0 | ~100 | Greenfield (Dart had no repository layer) |
| Compatibility tests | 0 | ~100 | Dart JSON round-trip with real project files |
| UI/Widget tests | ~15 | ~50 | XCUITest for critical flows |
| Performance tests | 0 | ~50 | XCTMetric for timing budgets |
| Integration tests | 0 | ~50 | End-to-end workflows |
| **Total** | **~765** | **~1,450** | **+89% more tests** |

---

## 7. Backward Compatibility

### Project file compatibility:
- Swift models use `Codable` with **explicit CodingKeys matching Dart `toJson()` keys**
- `CMTime` fields: encoded as `Double` seconds (custom `Codable`)
- `Optional` fields: explicit `nil` encoding (not missing key)
- `Date` fields: ISO8601 strategy matching Dart `DateTime.toIso8601String()`
- Enum raw values: match Dart `.toString()` output exactly
- Existing project.json files load without migration
- Version field preserved for future migrations

### Validation strategy:
- Export 10+ real projects from Flutter app
- Load in Swift prototype at Phase 2 completion
- 100+ JSON round-trip tests with real Dart-generated files

---

## 8. Dependencies

### Swift Package Manager:

| Package | Purpose | Replaces |
|---------|---------|----------|
| swift-collections | OrderedSet, SortedDictionary | LinkedHashSet, SplayTreeMap |
| swift-algorithms | Sequence algorithms | Dart collection utilities |

**Net dependency reduction:** 14 Flutter packages → 2 SPM packages

---

## 9. Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| SwiftUI limitations for complex gestures | UIKit gesture recognizers via UIViewRepresentable |
| Metal timeline rendering complexity | Phase 6a Core Graphics fallback before Phase 6b Metal |
| Project file compatibility | 100+ JSON round-trip tests with real Dart files |
| Performance regression during migration | XCTMetric benchmarks at every phase |
| Feature parity gaps | Comprehensive test migration ensures 1:1 coverage |
| Liquid Glass API availability | iOS 26 minimum, no fallback needed |
| Memory management | Instruments profiling at each phase |
| Concurrency bugs | `SWIFT_STRICT_CONCURRENCY = complete`, lock-protected hot paths |
| Actor deadlocks | I/O-bound only for actors; OSAllocatedUnfairLock for hot paths |
| Metal unavailable (simulator) | Failable init + Core Graphics fallback |
| Shader compilation stall | Prewarm all shaders at app launch |
| Texture allocation jank | TexturePool for recycling |
| MTKView accessibility | UIAccessibilityElement overlay for VoiceOver |
| 5,403-line SmartEditView | Decompose into 20+ small SwiftUI views |
| Existing *Native struct conflicts | Phase 0 audit + merge during Phase 2 |

---

## 10. Implementation Order Summary

```
Phase 0: Swift Audit & Cleanup (NEW)                    (~1 day)
Phase 1: Xcode Project + Foundation Types               (~2 days)
Phase 2: Domain Models (~85 files → Swift Codable)      (~6 days)
Phase 3: Services Refactor (48 Swift + 35 Dart files)   (~4 days)
Phase 4: Core Engines (8 engines + editing controllers) (~6 days)
Phase 5: Repositories (6 repos, greenfield)             (~2 days)
Phase 6a: Core Graphics Timeline (gesture proof)        (~3 days)
Phase 6b: Metal Timeline Renderer (120fps target)       (~8 days)
Phase 7: ViewModels (13 VMs, 12 greenfield)             (~3 days)
Phase 8: SwiftUI Views (50+ views, Liquid Glass)        (~10 days)
─────────────────────────────────────────────────────────────
Total estimated phases:                                  10 phases
Tests written alongside each phase:                      ~1,450 tests
```

---

## 11. Success Criteria

1. All 1,450+ tests pass
2. `xcodebuild build` succeeds with 0 warnings
3. All existing features work identically
4. Performance meets or exceeds targets in Section 5
5. Existing project.json files load correctly (100+ compatibility tests)
6. App launch < 0.5s
7. Timeline renders at 120fps (Metal) or 60fps (Core Graphics fallback)
8. Binary size < 25MB
9. Zero platform channel overhead
10. Full iOS 26 Liquid Glass aesthetic
11. VoiceOver accessibility for all screens including Metal timeline
12. No actor deadlocks under stress testing
