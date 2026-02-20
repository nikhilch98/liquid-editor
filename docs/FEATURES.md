# Liquid Editor - Features & Status

> **Complete feature documentation for the pure Swift Liquid Editor**
>
> Last Updated: 2026-02-13

---

## Table of Contents

1. [Feature Status Summary](#feature-status-summary)
2. [Timeline & Composition](#timeline--composition)
3. [Playback Engine](#playback-engine)
4. [Video Effects](#video-effects)
5. [Color Grading](#color-grading)
6. [Audio System](#audio-system)
7. [Text & Titles](#text--titles)
8. [Stickers & Overlays](#stickers--overlays)
9. [Tracking & Auto-Reframe](#tracking--auto-reframe)
10. [Export System](#export-system)
11. [Media Import & Management](#media-import--management)
12. [Project Management](#project-management)
13. [Transitions](#transitions)
14. [UI & UX Features](#ui--ux-features)
15. [Development Recommendations](#development-recommendations)

---

## Feature Status Summary

| Feature | Status | Module |
|---------|--------|--------|
| **PersistentTimeline (AVL tree)** | Complete | Timeline |
| **O(1) Undo/Redo** | Complete | Timeline |
| **Multi-Track State** | Complete | Timeline |
| **Clip Types (Video, Audio, Text, Sticker, Gap, Color, Image)** | Complete | Models/Clips |
| **Playback Engine (actor)** | Complete | Services/Composition |
| **Frame Cache (LRU, 120 frames)** | Complete | Services/Composition |
| **Double-Buffered Composition** | Complete | Services/Composition |
| **Video Effects Pipeline** | Complete | Services/Effects |
| **Color Grading (12-stage)** | Complete | Services/ColorGrading |
| **Audio Effects Engine** | Complete | Services/Audio |
| **Audio Mixing** | Complete | Services/Audio |
| **Text Overlays** | Complete | Views/Sheets, Models/Text |
| **Sticker Overlays** | Complete | Views/Sheets, Models/Sticker |
| **Person Tracking (Vision)** | Complete | Services/Tracking |
| **Auto-Reframe** | Complete | Services/AutoReframe |
| **Person Re-ID** | Complete | Services/Tracking |
| **Export Pipeline** | Complete | Services/Export |
| **Media Import** | Complete | Services/MediaImport |
| **Project Persistence** | Complete | Repositories |
| **Auto-Save** | Complete | Services/Project |
| **Transitions** | Complete | Services/Transitions |
| **Speed Control** | Complete | Services/Speed |
| **Masking** | Complete | Services/Masking |
| **Keyboard Shortcuts** | Complete | Services/Utility |
| **iCloud Sync** | Complete | Services/Utility |
| **Test Coverage (1,918 tests)** | Complete | LiquidEditorTests |

---

## Timeline & Composition

### PersistentTimeline

**Location:** `LiquidEditor/Services/Composition/PersistentTimeline.swift`

The core timeline data structure is an immutable AVL order statistic tree:

- O(log n) lookup, insert, delete, split operations
- Structural sharing (path copying) for memory efficiency
- Subtree duration tracking for fast time-to-clip resolution

### Multi-Track State

**Location:** `LiquidEditor/Models/Compositing/MultiTrackState.swift`

Manages all tracks as immutable state:

- Main video track
- Audio tracks
- Text overlay tracks (with GapClip spacers for absolute positioning)
- Sticker overlay tracks
- Track ordering, visibility, lock state
- Per-track composite configuration (blend mode, opacity)

### Undo/Redo System

**Location:** `LiquidEditor/Services/Composition/CompositionManager.swift`

- O(1) pointer swap between immutable MultiTrackState snapshots
- 100-operation history limit
- Description strings for undo/redo feedback

### Clip Types

**Location:** `LiquidEditor/Models/Clips/`

| File | Type | Purpose |
|------|------|---------|
| `VideoClip.swift` | `VideoClip` | Source video with in/out points, keyframes |
| `AudioClip.swift` | `AudioClip` | Audio with volume, mute, fade |
| `TextClip.swift` | `TextClip` | Text overlay with style, animation |
| `StickerClip.swift` | `StickerClip` | Sticker with position, scale |
| `GapClip.swift` | `GapClip` | Empty space / overlay spacer |
| `ColorClip.swift` | `ColorClip` | Solid color generator |
| `ImageClip.swift` | `ImageClip` | Still image with duration |
| `TimelineItem.swift` | `TimelineItem` | Base protocol for all clip types |
| `TimelineClip.swift` | `TimelineClip` | Extended clip with timeline metadata |

### Timeline Editing Controllers

**Location:** `LiquidEditor/Timeline/Editing/`

| File | Purpose |
|------|---------|
| `SplitController.swift` | Split clips at playhead position |
| `ClipboardController.swift` | Cut, copy, paste clips |
| `SnapController.swift` | Magnetic snapping to playhead, clip edges, markers |
| `SlipSlideController.swift` | Slip (shift source) and slide (shift position) edits |
| `RippleTrimController.swift` | Ripple trim (shift subsequent clips) |
| `MarkerController.swift` | Timeline marker management |

### Timeline Rendering

**Location:** `LiquidEditor/Timeline/Rendering/`

| File | Purpose |
|------|---------|
| `ClipsRenderer.swift` | Renders clip rectangles with thumbnails |
| `PlayheadRenderer.swift` | Renders playhead indicator |
| `RulerRenderer.swift` | Time ruler with tick marks |
| `TrackLanesRenderer.swift` | Track lane backgrounds and separators |
| `SnapGuideRenderer.swift` | Snap alignment guides |
| `SelectionOverlayRenderer.swift` | Multi-select overlay |
| `StickerPreviewRenderer.swift` | Sticker preview on timeline |

---

## Playback Engine

### PlaybackEngine (Actor)

**Location:** `LiquidEditor/Services/Composition/PlaybackEngine.swift`

An actor-isolated playback service:

- AVPlayer management for video playback
- Play/pause, seek, rate control
- Frame-accurate scrubbing
- Double-buffered AVComposition for seamless multi-clip playback

### Frame Cache

**Location:** `LiquidEditor/Services/Composition/` (via CompositionManager)

- LRU eviction with 120-frame capacity
- Predictive prefetch based on scrub direction
- Responds to iOS memory pressure warnings
- < 2ms latency for cached frames

---

## Video Effects

### Effect Pipeline

**Location:** `LiquidEditor/Services/Effects/EffectPipeline.swift`

GPU-accelerated video effects using CIContext backed by Metal:

- Effect chain application (ordered list of effects)
- Per-effect keyframing for animated parameters
- Real-time preview at playback speed

### Effect Types

**Location:** `LiquidEditor/Models/Effects/`

| File | Purpose |
|------|---------|
| `VideoEffect.swift` | Individual effect definition |
| `EffectChain.swift` | Ordered chain of effects |
| `EffectParameter.swift` | Parameterized effect controls |
| `EffectKeyframe.swift` | Animated effect parameters |
| `EffectTypes.swift` | Effect type enumeration |

---

## Color Grading

### ColorGradingPipeline

**Location:** `LiquidEditor/Services/ColorGrading/ColorGradingPipeline.swift`

12-stage color grading pipeline:

- Exposure, contrast, highlights, shadows
- Temperature, tint, saturation, vibrance
- HSL per-channel adjustments
- Curves (RGB, Luma)
- LUT support (3D color lookup tables)
- Filter presets

### Models

**Location:** `LiquidEditor/Models/ColorGrading/`

| File | Purpose |
|------|---------|
| `ColorGrade.swift` | Complete color grade configuration |
| `ColorKeyframe.swift` | Animated color grading |
| `CurveData.swift` | RGB/Luma curve points |
| `FilterPreset.swift` | Built-in filter presets |
| `HSLAdjustment.swift` | Per-hue adjustments |
| `LUTReference.swift` | External LUT file reference |

---

## Audio System

### AudioEffectsEngine

**Location:** `LiquidEditor/Services/Audio/AudioEffectsEngine.swift`

Real-time audio effects processing:

- EQ, compression, reverb, delay
- Noise reduction
- Audio ducking
- Volume automation

### AudioMixerService

**Location:** `LiquidEditor/Services/Audio/`

Multi-track audio mixing:

- Per-track volume and pan
- Audio fades (in/out)
- Beat detection and beat mapping

### Models

**Location:** `LiquidEditor/Models/Audio/`

| File | Purpose |
|------|---------|
| `AudioEffect.swift` | Audio effect definitions |
| `AudioFade.swift` | Fade in/out configuration |
| `AudioDuckingConfig.swift` | Audio ducking settings |
| `BeatMap.swift` | Beat detection results |
| `NoiseProfile.swift` | Noise reduction profile |
| `SoundEffectAsset.swift` | Sound effect library |

---

## Text & Titles

### Text Overlay System

**Location:** `LiquidEditor/Views/Sheets/TextEditorSheet.swift`, `LiquidEditor/Models/Text/`

- Rich text editing with font, size, color, alignment
- Text animation (fade, slide, typewriter, etc.)
- Text templates with predefined styles
- Position handles for drag-to-position
- Text clips on dedicated timeline tracks

### Key Files

| File | Purpose |
|------|---------|
| `TextEditorSheet.swift` | Text editing UI |
| `TextStylePanel.swift` | Font and style controls |
| `TextAnimationPicker.swift` | Animation selection |
| `TextTemplatePicker.swift` | Template gallery |
| `TextPositionHandle.swift` | Drag-to-position handle |
| `TextRenderer.swift` | Text rendering engine |

---

## Stickers & Overlays

### Sticker System

**Location:** `LiquidEditor/Views/Sheets/StickerPickerSheet.swift`, `LiquidEditor/Models/Sticker/`

- Sticker picker with search
- GIF support with frame caching
- Position, scale, rotation controls
- Sticker clips on dedicated timeline tracks
- Favorites management

### Key Services

| File | Purpose |
|------|---------|
| `StickerImportService.swift` | Import custom stickers |
| `StickerImageCache.swift` | Sticker image caching |
| `GifFrameCache.swift` | Animated GIF frame caching |
| `StickerFavoritesManager.swift` | Favorites persistence |
| `StickerEditorPanel.swift` | Sticker property controls |
| `StickerPositionHandle.swift` | Drag-to-position handle |

---

## Tracking & Auto-Reframe

### TrackingService

**Location:** `LiquidEditor/Services/Tracking/TrackingService.swift`

Person tracking using Apple Vision framework:

- `VNDetectHumanRectanglesRequest` for detection
- `VNTrackObjectRequest` for frame-to-frame tracking
- Kalman filtering for trajectory smoothing
- Re-identification across scene breaks

### Tracking Components

| File | Purpose |
|------|---------|
| `TrackingService.swift` | Main tracking orchestrator |
| `BoundingBoxTracker.swift` | Vision-based bounding box tracking |
| `KalmanFilter.swift` | Trajectory smoothing |
| `PersonIdentifier.swift` | Person re-identification |
| `ReIDExtractor.swift` | Appearance feature extraction |
| `TrackingDataStore.swift` | Thread-safe tracking result storage |
| `MotionTracker.swift` | Motion prediction |
| `ColorHistogram.swift` | Color-based matching |
| `AppearanceFeature.swift` | Visual feature descriptors |
| `TrackArchive.swift` | Tracking session persistence |
| `TrackDebugInfo.swift` | Debug visualization data |
| `TrackReidentifier.swift` | Cross-scene re-identification |

### AutoReframeEngine

**Location:** `LiquidEditor/Services/AutoReframe/AutoReframeEngine.swift`

Automatic keyframe generation to keep subjects in frame:

- Dead zone system to prevent micro-adjustments
- Temporal smoothing (critically damped spring motion)
- Lookahead averaging for motion prediction
- Adaptive smoothing based on movement velocity
- Configurable zoom intensity, follow speed, safe zone padding

### Person Management

**Location:** `LiquidEditor/Services/People/`, `LiquidEditor/Views/Sheets/PersonSelectionSheet.swift`

- Person detection and thumbnail generation
- Multi-person selection UI
- Person detail view with tracking history
- Person repository for persistence

---

## Export System

### Export Pipeline

**Location:** `LiquidEditor/Services/Export/`

- Multi-format export (MP4, MOV, ProRes)
- Codec selection (H.264, H.265/HEVC, ProRes)
- Resolution presets (480p through 4K)
- Quality settings with bitrate control
- File size estimation
- Progress tracking with cancellation

### Models

**Location:** `LiquidEditor/Models/Export/`

| File | Purpose |
|------|---------|
| `ExportConfig.swift` | Export configuration (codec, resolution, quality) |
| `ExportJob.swift` | Export job state and progress |
| `FileSizeEstimator.swift` | Estimated output file size |

### Views

| File | Purpose |
|------|---------|
| `ExportSheet.swift` | Export configuration UI |
| `ExportDebugSheet.swift` | Debug export information |

---

## Media Import & Management

### MediaImportService

**Location:** `LiquidEditor/Services/MediaImport/`

- Photo library import (PHPickerViewController)
- Files app import
- Duplicate detection via content hashing
- Media asset registry with UUID + content hash

### MediaAsset

**Location:** `LiquidEditor/Models/Media/MediaAsset.swift`

- UUID-based identification
- Content hash for duplicate detection
- Source URL tracking with relink support
- Metadata extraction (duration, resolution, frame rate)

---

## Project Management

### Project Persistence

**Location:** `LiquidEditor/Repositories/ProjectRepository.swift`

- JSON-based project serialization
- Documents directory storage
- Auto-save with debounce

### Additional Services

| File | Purpose |
|------|---------|
| `AutoSaveService.swift` | Periodic auto-save |
| `ProjectDuplicateService.swift` | Duplicate project |
| `ProjectTemplateService.swift` | Project templates |
| `BackupRepository.swift` | Project backup management |
| `DraftRepository.swift` | Draft management |

### Models

**Location:** `LiquidEditor/Models/Project/`

| File | Purpose |
|------|---------|
| `Project.swift` | Main project model |
| `ProjectSettings.swift` | Frame rate, resolution, canvas settings |
| `ProjectMetadata.swift` | Name, dates, thumbnail |
| `ProjectTemplate.swift` | Template definitions |
| `BackupManifest.swift` | Backup metadata |
| `DraftMetadata.swift` | Draft metadata |
| `AspectRatio.swift` | Aspect ratio presets |

---

## Transitions

### TransitionRenderer

**Location:** `LiquidEditor/Services/Transitions/TransitionRenderer.swift`

- Cross-dissolve, wipe, slide, zoom transitions
- GPU-accelerated rendering via Metal
- Configurable duration and easing

---

## UI & UX Features

### Navigation

**Location:** `LiquidEditor/Navigation/AppCoordinator.swift`

`@Observable` navigation coordinator managing app-wide navigation:

- Project library, editor, settings flows
- Sheet presentation (export, color grading, text, etc.)
- Deep linking support

### Views

| File | Purpose |
|------|---------|
| `ProjectLibraryView.swift` | Project grid with thumbnails |
| `ProjectCardView.swift` | Individual project card |
| `EditorView.swift` | Main editor layout |
| `VideoPreviewView.swift` | Video preview with overlays |
| `TimelineView.swift` | Multi-track timeline |
| `PlaybackControlsView.swift` | Play/pause, time display |
| `SettingsView.swift` | App settings |
| `OnboardingView.swift` | First-launch onboarding |

### Utility Services

| File | Purpose |
|------|---------|
| `HapticService.swift` | Centralized haptic feedback |
| `ShortcutService.swift` | Keyboard shortcut handling |
| `StorageAnalysisService.swift` | Storage usage analysis |
| `iCloudSyncService.swift` | iCloud sync |
| `GesturePreferences.swift` | Gesture customization |

---

## Development Recommendations

### Immediate Priorities

1. **Device Testing** -- Comprehensive testing on physical devices for tracking, export, and performance validation
2. **Performance Profiling** -- Instruments profiling for memory, CPU, and GPU under real workloads
3. **Accessibility** -- VoiceOver support, Dynamic Type, and reduced motion

### Future Enhancements

1. **Pose Tracking** -- VNDetectHumanBodyPoseRequest for skeletal tracking
2. **Scene Detection** -- Automatic scene boundary detection
3. **AI-Powered Features** -- Smart trim, highlight detection
4. **Collaboration** -- Multi-device project sharing
5. **iPad Support** -- Optimized layout for larger screens

---

**Last Updated:** 2026-02-13
