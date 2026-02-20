# Export & Sharing Enhancements - Design Document

**Date:** 2026-02-06
**Status:** Design
**Author:** Claude Opus 4.6
**Review Count:** 3/3 (Final)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Current State Analysis](#2-current-state-analysis)
3. [Social Media Direct Share](#3-social-media-direct-share)
4. [Platform-Specific Presets](#4-platform-specific-presets)
5. [Frame Grab Export](#5-frame-grab-export)
6. [Audio-Only Export](#6-audio-only-export)
7. [Background Export](#7-background-export)
8. [AirDrop Sharing](#8-airdrop-sharing)
9. [Project Sharing](#9-project-sharing)
10. [Batch Export](#10-batch-export)
11. [Burn-in Subtitles](#11-burn-in-subtitles)
12. [Render Preview](#12-render-preview)
13. [Export Progress](#13-export-progress)
14. [Export Queue](#14-export-queue)
15. [Native Export Pipeline Analysis](#15-native-export-pipeline-analysis)
16. [Edge Cases & Error Handling](#16-edge-cases--error-handling)
17. [Performance Budget](#17-performance-budget)
18. [Implementation Plan](#18-implementation-plan)

---

## 1. Overview

### Purpose

This document designs 12 features that transform Liquid Editor's export system from a single-format, foreground-only renderer into a professional-grade export pipeline with social sharing, background processing, batch operations, and a managed queue. The design spans both the Flutter UI layer and the native Swift AVFoundation layer.

### Guiding Principles

1. **Native-first rendering.** All video/audio processing uses AVFoundation on background `DispatchQueue`s. Flutter never touches pixel buffers.
2. **Non-blocking UI.** Every export operation runs asynchronously. The user can continue editing or queue additional exports.
3. **Deterministic progress.** Each export reports frame-level progress, ETA, and current phase (preparing, rendering, encoding, saving).
4. **Graceful degradation.** Low disk, thermal throttling, and memory pressure cause quality reduction before failure, never data loss.
5. **iOS 26 Liquid Glass UI.** All new UI uses native `CupertinoNavigationBar`, `CupertinoButton`, `CupertinoAlertDialog`, `CNTabBar`, `CNButton.icon` with `CNButtonStyle.glass`, and `CupertinoActionSheet`. No Material widgets.

### Scope

| In Scope | Out of Scope |
|----------|-------------|
| 12 export/sharing features listed | Cloud upload (YouTube, TikTok APIs) |
| Native AVFoundation pipeline upgrades | Server-side transcoding |
| Liquid Glass export UI redesign | Android platform support |
| Platform channel protocol extensions | Hardware encoder configuration UI |
| Comprehensive error recovery | DRM/watermark protection |

---

## 2. Current State Analysis

### 2.1 Flutter Export Layer

**File:** `lib/views/export/export_sheet.dart` (1464 lines)

Current capabilities:
- Single export sheet presented as modal popup
- Manual mode with resolution slider (540p, 720p, 1080p, 2.7K, 4K), FPS slider (24, 25, 30, 50, 60), bitrate slider (1-150 Mbps)
- Auto mode (hides resolution/FPS/bitrate controls)
- Audio-only toggle (outputs M4A)
- HDR toggle
- Export progress with gradient border animation and live frame preview
- Debug export mode (renders first frame for comparison)
- Cancel/restart dialog during export
- Progress reported via `EventChannel('com.liquideditor/video_processing/progress')`
- Final output saved to Photos via `Gal.putVideo()`

Current data flow:
```
ExportSheet._startExport()
  -> _buildClipsPayload()          // Build clips with 100ms-interval keyframes
  -> MethodChannel.invokeMethod('renderComposition', {...})
  -> EventChannel receives progress (0.0 - 1.0)
  -> Gal.putVideo(outputPath)      // Save to Photos library
```

Current limitations:
- **Foreground-only.** Export blocks the UI; user sees "don't close the app" warning.
- **Single format.** One export at a time, one format per export.
- **No share sheet.** After save, no option to share to Messages, Mail, AirDrop, etc.
- **No presets for social media.** No aspect ratio auto-crop (9:16, 1:1, etc.).
- **No frame grab.** Cannot export current frame as still image.
- **No queue.** Cannot stack multiple exports.
- **No subtitle burn-in.** No text overlay during render.
- **No render preview.** Must render full video to check output quality.
- **Basic progress.** Percentage only; no ETA, no phase labels, no file size tracking.
- **Uses Material widgets.** `Slider`, `Switch.adaptive`, `IconButton`, `Icons.*` in several places (must be migrated to Cupertino/Liquid Glass).

### 2.2 Native Export Layer

**File:** `ios/Runner/VideoProcessingService.swift` (912 lines)

Current capabilities:
- `renderComposition()` - Multi-clip export via AVMutableComposition + AVAssetExportSession
- `renderVideo()` - Single-video export with keyframe transforms
- `exportAudioOnly()` / `exportCompositionAudioOnly()` - M4A audio export
- `renderFirstFrame()` - Debug frame extraction via AVAssetImageGenerator
- `extractFirstFrame()` / `extractFrameAtProgress()` - Frame extraction for previews
- `selectExportPreset()` - Maps resolution/bitrate to AVAssetExportSession presets
- HDR color space configuration (BT.2020, HLG)
- Progress reporting via Timer polling `exportSession.progress` at 100ms intervals

**File:** `ios/Runner/VideoTransformCalculator.swift` (207 lines)
- Handles preferredTransform (video rotation) and user transforms (scale, translate, rotate)
- Computes CGAffineTransform for AVMutableVideoCompositionLayerInstruction

**File:** `ios/Runner/VideoConstants.swift` (84 lines)
- Centralized constants for thumbnail sizes, compression quality, timing, export defaults, resolution thresholds

Current limitations:
- **AVAssetExportSession only.** Cannot control per-frame encoding, cannot burn in subtitles, cannot add watermarks. AVAssetWriter needed for advanced features.
- **No cancellation signal.** Native code has no mechanism to cancel an in-progress export.
- **No background task registration.** Export stops if app is backgrounded.
- **Single event sink.** One progress stream for all exports; no multiplexing for batch/queue.
- **No disk space checks.** Export can fail mid-way on low storage.
- **No thermal throttle detection.** No quality downgrade under thermal pressure.

### 2.3 Platform Channel Protocol

**Method Channel:** `com.liquideditor/video_processing`

| Method | Direction | Purpose |
|--------|-----------|---------|
| `renderComposition` | Flutter -> Swift | Multi-clip export |
| `renderVideo` | Flutter -> Swift | Single-video export |
| `renderFirstFrame` | Flutter -> Swift | Debug frame render |
| `extractFirstFrame` | Flutter -> Swift | Extract frame at t=0 |
| `extractFrameAtProgress` | Flutter -> Swift | Extract frame at progress |
| `generateThumbnail` | Flutter -> Swift | Single thumbnail |
| `generateTimelineThumbnails` | Flutter -> Swift | Batch timeline thumbnails |
| `generateProxy` | Flutter -> Swift | 1080p proxy generation |

**Event Channel:** `com.liquideditor/video_processing/progress`
- Single `Double` value (0.0 to 1.0)
- No export ID, no phase, no ETA

---

## 3. Social Media Direct Share

### 3.1 Data Models

```dart
/// Represents a share destination with platform-specific metadata.
@immutable
class ShareDestination {
  final String id;
  final String displayName;
  final String sfSymbolName;
  final SharePlatform platform;
  final AspectRatio recommendedAspect;
  final Resolution maxResolution;
  final int maxDurationSeconds;
  final int maxFileSizeMB;
  final String containerFormat;    // 'mp4', 'mov'
  final String recommendedCodec;  // 'h264', 'hevc'

  const ShareDestination({...});
}

enum SharePlatform {
  instagram,
  tiktok,
  youtube,
  twitter,
  snapchat,
  facebook,
  messages,
  mail,
  airdrop,
  files,
  custom,
}

/// Result from native share operation.
@immutable
class ShareResult {
  final bool didShare;
  final String? activityType;     // e.g., 'com.apple.UIKit.activity.AirDrop'
  final String? errorMessage;

  const ShareResult({...});
}
```

### 3.2 Architecture

```
Flutter (ExportSheet)
  |
  | MethodChannel: 'shareVideo' / 'shareImage' / 'shareAudio'
  v
Swift (ShareService)
  |
  | UIActivityViewController (native iOS share sheet)
  v
iOS Share Sheet -> AirDrop, Messages, Mail, Instagram, etc.
```

### 3.3 Native Implementation (Swift)

```swift
/// New file: ios/Runner/ShareService.swift
final class ShareService {

    /// Present UIActivityViewController for a file.
    /// - Parameters:
    ///   - filePath: Absolute path to exported file
    ///   - fileType: UTType string ('public.mpeg-4', 'public.png', etc.)
    ///   - excludedTypes: Activity types to exclude
    ///   - sourceRect: For iPad popover positioning (from Flutter widget bounds)
    ///   - result: Flutter result callback with ShareResult JSON
    func shareFile(
        filePath: String,
        fileType: String,
        excludedTypes: [UIActivity.ActivityType]?,
        sourceRect: CGRect?,
        result: @escaping FlutterResult
    ) {
        let url = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found", details: nil))
            return
        }

        DispatchQueue.main.async {
            let activityVC = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )

            activityVC.excludedActivityTypes = excludedTypes

            // iPad requires sourceView/sourceRect for popover
            if let sourceRect = sourceRect,
               let rootVC = UIApplication.shared.connectedScenes
                   .compactMap({ $0 as? UIWindowScene })
                   .flatMap({ $0.windows })
                   .first(where: { $0.isKeyWindow })?.rootViewController {

                activityVC.popoverPresentationController?.sourceView = rootVC.view
                activityVC.popoverPresentationController?.sourceRect = sourceRect
            }

            activityVC.completionWithItemsHandler = { activityType, completed, _, error in
                let shareResult: [String: Any?] = [
                    "didShare": completed,
                    "activityType": activityType?.rawValue,
                    "errorMessage": error?.localizedDescription,
                ]
                result(shareResult)
            }

            // Present from the topmost view controller
            if let topVC = Self.topViewController() {
                topVC.present(activityVC, animated: true)
            } else {
                result(FlutterError(code: "NO_VC", message: "No view controller", details: nil))
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}
```

### 3.4 UI Design

After export completes, instead of dismissing the sheet, present a success state with:

1. **Checkmark animation** (Lottie or custom) - 1 second
2. **"Saved to Photos"** confirmation label
3. **Share button row** using `CupertinoButton` icons:
   - Share (system share sheet via UIActivityViewController)
   - AirDrop (pre-selects AirDrop activity)
   - Messages
   - Copy Link (copies file URL to clipboard)
4. **Done button** to dismiss

All buttons use `CupertinoButton` with `CupertinoIcons` or SF Symbols via `CNSymbol`.

### 3.5 Edge Cases

- **File deleted before share.** Check file exists before presenting share sheet; show `CupertinoAlertDialog` if missing.
- **Share cancelled.** `completionWithItemsHandler` reports `completed: false`; do not dismiss export sheet.
- **iPad popover.** Must provide `sourceRect` for `UIActivityViewController` on iPad or it crashes. Calculate from the share button's global position via `RenderBox.localToGlobal`.
- **Large file sharing.** Files over 100MB may fail via some share targets (Messages). Show warning in UI.
- **Temp file cleanup.** Exported files in tmp/ may be cleaned by iOS. Move to Caches/ with 7-day retention for share window.

---

## 4. Platform-Specific Presets

### 4.1 Data Models

```dart
/// Aspect ratio configuration for platform presets.
@immutable
class AspectRatioConfig {
  final String name;              // '9:16', '1:1', '16:9', '4:5'
  final double widthRatio;
  final double heightRatio;

  const AspectRatioConfig({...});

  double get ratio => widthRatio / heightRatio;
  bool get isPortrait => heightRatio > widthRatio;
  bool get isLandscape => widthRatio > heightRatio;
  bool get isSquare => widthRatio == heightRatio;

  /// Calculate output dimensions preserving short side from source.
  ({int width, int height}) outputDimensions({
    required int sourceWidth,
    required int sourceHeight,
    required int targetShortSide,
  }) {
    if (isPortrait) {
      final w = targetShortSide;
      final h = (w / ratio).round();
      return (width: (w ~/ 2) * 2, height: (h ~/ 2) * 2);
    } else if (isSquare) {
      return (width: targetShortSide, height: targetShortSide);
    } else {
      final h = targetShortSide;
      final w = (h * ratio).round();
      return (width: (w ~/ 2) * 2, height: (h ~/ 2) * 2);
    }
  }
}

/// Platform export preset with all constraints.
@immutable
class PlatformPreset {
  final String id;
  final String name;
  final String sfSymbolName;
  final SharePlatform platform;
  final AspectRatioConfig aspectRatio;
  final int maxWidth;
  final int maxHeight;
  final int maxFps;
  final double maxBitrateMbps;
  final int maxDurationSeconds;
  final int maxFileSizeMB;
  final String codec;           // 'h264', 'hevc'
  final String container;       // 'mp4', 'mov'
  final bool supportsHdr;

  const PlatformPreset({...});
}

/// Auto-crop configuration for aspect ratio conversion.
@immutable
class AutoCropConfig {
  /// How to handle aspect ratio mismatch.
  final CropStrategy strategy;

  /// Focal point for crop (0.0-1.0, default center 0.5, 0.5).
  /// Can be set from tracked person position.
  final Offset focalPoint;

  /// Background color for letterbox/pillarbox.
  final Color backgroundColor;

  /// Whether to use blur fill instead of solid color.
  final bool useBlurFill;

  const AutoCropConfig({...});
}

enum CropStrategy {
  /// Crop to fill target aspect ratio (may lose edges).
  cropToFill,

  /// Letterbox/pillarbox to fit within target ratio (adds bars).
  fitWithBars,

  /// Blur-fill: fit video and fill bars with blurred version.
  blurFill,

  /// Smart crop: use person tracking data to center crop on subject.
  smartCrop,
}
```

### 4.2 Built-in Presets

```dart
static const List<PlatformPreset> builtInPresets = [
  // Instagram
  PlatformPreset(
    id: 'instagram_reels',
    name: 'Instagram Reels',
    sfSymbolName: 'camera.on.rectangle',
    platform: SharePlatform.instagram,
    aspectRatio: AspectRatioConfig(name: '9:16', widthRatio: 9, heightRatio: 16),
    maxWidth: 1080, maxHeight: 1920, maxFps: 30,
    maxBitrateMbps: 25, maxDurationSeconds: 90, maxFileSizeMB: 250,
    codec: 'h264', container: 'mp4', supportsHdr: false,
  ),
  PlatformPreset(
    id: 'instagram_feed',
    name: 'Instagram Feed',
    sfSymbolName: 'square',
    platform: SharePlatform.instagram,
    aspectRatio: AspectRatioConfig(name: '1:1', widthRatio: 1, heightRatio: 1),
    maxWidth: 1080, maxHeight: 1080, maxFps: 30,
    maxBitrateMbps: 15, maxDurationSeconds: 60, maxFileSizeMB: 250,
    codec: 'h264', container: 'mp4', supportsHdr: false,
  ),
  PlatformPreset(
    id: 'instagram_story',
    name: 'Instagram Story',
    sfSymbolName: 'rectangle.portrait',
    platform: SharePlatform.instagram,
    aspectRatio: AspectRatioConfig(name: '9:16', widthRatio: 9, heightRatio: 16),
    maxWidth: 1080, maxHeight: 1920, maxFps: 30,
    maxBitrateMbps: 20, maxDurationSeconds: 15, maxFileSizeMB: 30,
    codec: 'h264', container: 'mp4', supportsHdr: false,
  ),
  // TikTok
  PlatformPreset(
    id: 'tiktok',
    name: 'TikTok',
    sfSymbolName: 'music.note',
    platform: SharePlatform.tiktok,
    aspectRatio: AspectRatioConfig(name: '9:16', widthRatio: 9, heightRatio: 16),
    maxWidth: 1080, maxHeight: 1920, maxFps: 60,
    maxBitrateMbps: 30, maxDurationSeconds: 180, maxFileSizeMB: 287,
    codec: 'h264', container: 'mp4', supportsHdr: false,
  ),
  // YouTube
  PlatformPreset(
    id: 'youtube_landscape',
    name: 'YouTube (16:9)',
    sfSymbolName: 'play.rectangle',
    platform: SharePlatform.youtube,
    aspectRatio: AspectRatioConfig(name: '16:9', widthRatio: 16, heightRatio: 9),
    maxWidth: 3840, maxHeight: 2160, maxFps: 60,
    maxBitrateMbps: 68, maxDurationSeconds: 43200, maxFileSizeMB: 128000,
    codec: 'h264', container: 'mp4', supportsHdr: true,
  ),
  PlatformPreset(
    id: 'youtube_shorts',
    name: 'YouTube Shorts',
    sfSymbolName: 'play.rectangle.fill',
    platform: SharePlatform.youtube,
    aspectRatio: AspectRatioConfig(name: '9:16', widthRatio: 9, heightRatio: 16),
    maxWidth: 1080, maxHeight: 1920, maxFps: 60,
    maxBitrateMbps: 30, maxDurationSeconds: 60, maxFileSizeMB: 250,
    codec: 'h264', container: 'mp4', supportsHdr: false,
  ),
  // Twitter/X
  PlatformPreset(
    id: 'twitter',
    name: 'X (Twitter)',
    sfSymbolName: 'bubble.left',
    platform: SharePlatform.twitter,
    aspectRatio: AspectRatioConfig(name: '16:9', widthRatio: 16, heightRatio: 9),
    maxWidth: 1920, maxHeight: 1200, maxFps: 60,
    maxBitrateMbps: 25, maxDurationSeconds: 140, maxFileSizeMB: 512,
    codec: 'h264', container: 'mp4', supportsHdr: false,
  ),
  // Facebook
  PlatformPreset(
    id: 'facebook_feed',
    name: 'Facebook Feed',
    sfSymbolName: 'person.2',
    platform: SharePlatform.facebook,
    aspectRatio: AspectRatioConfig(name: '4:5', widthRatio: 4, heightRatio: 5),
    maxWidth: 1080, maxHeight: 1350, maxFps: 30,
    maxBitrateMbps: 16, maxDurationSeconds: 240, maxFileSizeMB: 4096,
    codec: 'h264', container: 'mp4', supportsHdr: false,
  ),
];
```

### 4.3 Auto-Crop Architecture

**Native Implementation (Swift):**

The auto-crop operates at the AVMutableVideoComposition level by adjusting `renderSize` and `layerInstruction` transforms.

```swift
/// Extension to VideoTransformCalculator for auto-crop.
extension VideoTransformCalculator {

    /// Create a transform that crops the source to a target aspect ratio.
    func createCropTransform(
        targetAspect: CGFloat,    // width / height
        focalX: CGFloat,          // 0.0-1.0, default 0.5
        focalY: CGFloat,          // 0.0-1.0, default 0.5
        strategy: String          // "cropToFill", "fitWithBars", "blurFill"
    ) -> CGAffineTransform {
        let sourceAspect = sourceWidth / sourceHeight

        switch strategy {
        case "cropToFill":
            return createCropToFillTransform(
                sourceAspect: sourceAspect,
                targetAspect: targetAspect,
                focalX: focalX,
                focalY: focalY
            )
        case "fitWithBars":
            return createFitWithBarsTransform(
                sourceAspect: sourceAspect,
                targetAspect: targetAspect
            )
        default:
            return createBaseTransform()
        }
    }
}
```

For `smartCrop`, the focal point is derived from person tracking data at each frame. The auto-reframe engine (`lib/core/auto_reframe_engine.dart`) already produces per-frame focal points. These are passed as additional keyframe data alongside the existing scale/translate/rotation keyframes.

### 4.4 UI Design

The preset selector is presented as a horizontal scrollable row of platform icons at the top of the export sheet, above the existing preview. Each icon is a `CupertinoButton` with the platform's SF Symbol. Selecting a preset auto-configures resolution, FPS, bitrate, aspect ratio, codec, and shows a crop preview overlay.

### 4.5 Edge Cases

- **Source video shorter than platform max duration.** No issue; just export as-is.
- **Source video longer than platform max duration.** Show `CupertinoAlertDialog`: "This video is X:XX. Instagram Reels allows up to 1:30. Trim your video first."
- **Source video already matches target aspect ratio.** No crop needed; skip crop transform.
- **Portrait source to landscape target (or vice versa).** Show crop preview with draggable focal point.
- **File size exceeds platform limit.** After export, check file size. If over limit, show option to re-export at lower bitrate with estimated new size.
- **Codec not supported by platform.** Force H.264 for platforms that do not support HEVC.

---

## 5. Frame Grab Export

### 5.1 Data Models

```dart
/// Configuration for still frame export.
@immutable
class FrameGrabConfig {
  final Duration timestamp;           // Frame to capture
  final FrameFormat format;
  final double quality;               // 0.0-1.0 for JPEG/HEIF
  final int? maxWidth;                // null = full resolution
  final int? maxHeight;
  final bool applyTransforms;         // Apply keyframe transforms to output
  final bool includeOverlays;         // Include tracking overlays, subtitles
  final String? watermarkText;

  const FrameGrabConfig({...});
}

enum FrameFormat {
  png,      // Lossless, large files
  jpeg,     // Lossy, small files, universal
  heif,     // Lossy, smaller than JPEG, iOS-native
  tiff,     // Lossless, professional
}
```

### 5.2 Architecture

```
Flutter (FrameGrabSheet)
  |
  | MethodChannel: 'extractFrameGrab'
  v
Swift (VideoProcessingService.extractFrameGrab)
  |
  | AVAssetImageGenerator (with videoComposition for transforms)
  v
UIImage -> encode to PNG/JPEG/HEIF/TIFF
  |
  | Return path to encoded file
  v
Flutter: Gal.putImage() or shareFile()
```

### 5.3 Native Implementation

```swift
/// Extract a high-quality frame at a specific timestamp with transforms applied.
func extractFrameGrab(
    videoPath: String,
    clips: [[String: Any]],
    timestampMs: Int,
    format: String,          // "png", "jpeg", "heif", "tiff"
    quality: Double,         // 0.0-1.0
    maxWidth: Int?,
    maxHeight: Int?,
    applyTransforms: Bool,
    result: @escaping FlutterResult
) {
    // 1. Build AVMutableComposition from clips
    // 2. Build AVMutableVideoComposition with transforms (if applyTransforms)
    // 3. Use AVAssetImageGenerator with .videoComposition set
    // 4. Set maximumSize if maxWidth/maxHeight provided
    // 5. Extract CGImage at timestamp
    // 6. Encode to requested format
    // 7. Write to temp file and return path
}
```

### 5.4 UI Design

The frame grab feature is accessible from:
1. **Export sheet** - "Export Frame" option in a `CupertinoActionSheet`
2. **Editor toolbar** - Camera icon button that captures current playhead position
3. **Long press on video preview** - Context menu via `CupertinoContextMenu`

The frame grab sheet uses `CupertinoSegmentedControl` for format selection (PNG/JPEG/HEIF) and a `CupertinoSlider` for quality.

### 5.5 Edge Cases

- **Timestamp in gap.** If playhead is on a gap clip, show `CupertinoAlertDialog`: "Cannot capture frame from an empty gap."
- **Black frame.** Some videos have black first/last frames. Allow user to scrub to desired frame before capture.
- **Transforms produce off-screen content.** If the user has zoomed/panned, the exported frame should match what they see in the preview, not the full source frame.
- **Very high resolution source (8K).** Cap output at source resolution. Do not upscale.
- **HEIF not available on older devices.** HEIF encoding requires iOS 11+. Since our min target is iOS 18, this is always available.

---

## 6. Audio-Only Export

### 6.1 Data Models

```dart
/// Configuration for audio-only export.
@immutable
class AudioExportConfig {
  final AudioFormat format;
  final AudioQuality quality;
  final int? sampleRate;        // null = source sample rate
  final int? channels;          // null = source channels
  final int? bitrate;           // kbps, null = default for format
  final Duration? trimStart;    // Optional trim range
  final Duration? trimEnd;

  const AudioExportConfig({...});
}

enum AudioFormat {
  wav,      // Uncompressed, lossless
  aac,      // Compressed, good quality, small files (M4A container)
  alac,     // Apple Lossless (M4A container)
  mp3,      // Compressed, universal compatibility
  flac,     // Compressed, lossless, open standard
}

enum AudioQuality {
  low,       // 96 kbps AAC
  medium,    // 192 kbps AAC
  high,      // 256 kbps AAC
  maximum,   // 320 kbps AAC / lossless for WAV/ALAC/FLAC
}
```

### 6.2 Architecture

Current state already supports M4A export via `exportAudioOnly()` and `exportCompositionAudioOnly()` in `VideoProcessingService.swift`. This feature extends support to WAV, MP3, FLAC, and ALAC.

**AVAssetExportSession limitations:**
- Only supports M4A (AAC) and CAF output.
- Cannot produce WAV, MP3, or FLAC directly.

**Required approach for non-AAC formats: AVAssetWriter.**

```swift
func exportAudioWithFormat(
    composition: AVMutableComposition,
    format: String,           // "wav", "aac", "alac", "mp3", "flac"
    sampleRate: Int?,
    channels: Int?,
    bitrate: Int?,
    result: @escaping FlutterResult
) {
    // For AAC/ALAC: Use AVAssetExportSession (existing code)
    // For WAV: Use AVAssetWriter with kAudioFormatLinearPCM
    // For FLAC: Use AVAssetWriter with kAudioFormatFLAC
    // For MP3: Not natively supported by AVFoundation.
    //          Option A: Export WAV then convert via lame (adds dependency)
    //          Option B: Use AudioToolbox ExtAudioFile with kAudioFormatMPEGLayer3
    //          Option C: Drop MP3 support, offer AAC instead (recommended)
}
```

**Recommendation:** Drop MP3 support. AAC is universally supported, smaller, and better quality at the same bitrate. iOS cannot natively encode MP3. Exposing WAV, AAC, ALAC, and FLAC covers all professional and consumer use cases.

### 6.3 UI Design

Audio export is integrated into the existing export sheet. When "Export Audio Only" toggle is enabled, the UI transforms:

- Video preview hides
- Waveform visualization appears (future enhancement, placeholder for now)
- Format selector: `CupertinoSegmentedControl` with WAV / AAC / ALAC / FLAC
- Quality selector: `CupertinoSegmentedControl` with Low / Medium / High / Max
- Sample rate selector: `CupertinoPicker` with 22050, 44100, 48000, 96000
- Estimated file size updates in real-time

### 6.4 Edge Cases

- **No audio track in source video.** Show `CupertinoAlertDialog`: "This video has no audio track."
- **Multi-source with different sample rates.** Resample all tracks to the highest sample rate or user-selected rate.
- **WAV files over 4GB.** WAV format has a 4GB file limit (32-bit header). For very long audio, warn user or switch to W64/RF64. Practically unlikely for a mobile video editor.
- **Clips with gaps.** Gaps should produce silence in the audio output (zero samples at the target sample rate).

---

## 7. Background Export

### 7.1 Data Models

```dart
/// Represents an export that can run in the background.
@immutable
class BackgroundExportTask {
  final String id;
  final ExportConfig config;
  final BackgroundExportState state;
  final double progress;        // 0.0-1.0
  final String? outputPath;
  final DateTime startedAt;
  final Duration? estimatedRemaining;
  final String? errorMessage;

  const BackgroundExportTask({...});
}

enum BackgroundExportState {
  queued,
  preparing,
  rendering,
  encoding,
  saving,
  completed,
  failed,
  cancelled,
  paused,
}
```

### 7.2 Architecture

iOS background processing requires:

1. **`UIApplication.beginBackgroundTask()`** - Grants ~30 seconds of background execution.
2. **`BGProcessingTaskRequest`** (iOS 13+) - For long-running tasks, but only runs when device is charging and idle. Not suitable for user-initiated exports.
3. **Foreground Service / Audio Session trick** - Keep a silent audio session active to prevent suspension. Unreliable and violates App Store guidelines.

**Recommended approach: "Continue in background" with time limit.**

```swift
/// Register background task when export starts.
var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

func startBackgroundExport() {
    backgroundTaskId = UIApplication.shared.beginBackgroundTask(
        withName: "VideoExport"
    ) { [weak self] in
        // Time is about to expire
        self?.pauseExportAndNotify()
        UIApplication.shared.endBackgroundTask(self?.backgroundTaskId ?? .invalid)
        self?.backgroundTaskId = .invalid
    }
}
```

**User experience:**
- Export starts in foreground as usual.
- If user leaves the app (home button, switch apps), export continues for up to 30 seconds.
- If export completes within 30s, send local notification: "Export complete."
- If export cannot complete in 30s, save progress and notify: "Export paused. Return to Liquid Editor to resume."
- When user returns, export resumes from where it left off (using AVAssetWriter's ability to append samples).

**For true background continuation (>30s):**
- Use `AVAssetWriter` instead of `AVAssetExportSession`. AVAssetWriter allows incremental writing and can be paused/resumed.
- Write frames to disk as they are rendered.
- Track the last successfully written frame index.
- On resume, seek to the last frame and continue.

### 7.3 Native Implementation

```swift
/// Manages background export lifecycle.
final class BackgroundExportManager {
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var currentWriter: AVAssetWriter?
    private var lastWrittenFrameIndex: Int = 0
    private var isPaused: Bool = false

    func beginBackgroundExport(config: ExportConfig) {
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(
            withName: "LiquidEditorExport"
        ) { [weak self] in
            self?.handleBackgroundTimeExpiring()
        }
    }

    private func handleBackgroundTimeExpiring() {
        // Pause the writer gracefully
        isPaused = true
        // Finalize the partially written file
        // Store resume metadata
        // Schedule local notification
        scheduleResumeNotification()
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }

    func resumeExport() {
        // Read resume metadata
        // Re-open AVAssetWriter in append mode (or create new writer from last frame)
        // Continue rendering from lastWrittenFrameIndex
        isPaused = false
    }

    private func scheduleResumeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Export Paused"
        content.body = "Return to Liquid Editor to continue your export."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "export_paused",
            content: content,
            trigger: nil  // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

### 7.4 UI Design

- When export starts, show a **mini progress indicator** in the navigation bar (persistent across screens).
- User can navigate back to editor, library, or any other screen.
- Mini indicator shows: progress percentage, current phase icon, tap to expand.
- Tapping the mini indicator opens a `CupertinoActionSheet` with:
  - View progress details
  - Cancel export
  - Priority: High/Normal/Low (for queue ordering)

### 7.5 Edge Cases

- **App terminated during export.** Export data is lost. AVAssetWriter does not survive process termination. Partially written file is deleted on next launch.
- **Memory pressure during background export.** iOS may terminate background apps. Same as app termination. Consider writing fewer frames to memory before flushing.
- **Multiple background exports.** Only one export runs at a time (see Export Queue). Others wait in queue.
- **Device locked during export.** Background task continues for 30s, then pauses.
- **Low battery.** iOS may aggressively terminate background tasks. Export pauses and notifies.
- **Thermal throttle in background.** Lower rendering quality automatically (reduce resolution to next tier down, reduce FPS).

---

## 8. AirDrop Sharing

### 8.1 Architecture

AirDrop is a subset of `UIActivityViewController`. No separate implementation needed.

```swift
func shareViaAirDrop(filePath: String, result: @escaping FlutterResult) {
    shareFile(
        filePath: filePath,
        fileType: "public.mpeg-4",
        excludedTypes: UIActivity.ActivityType.allCases
            .filter { $0 != .airDrop },  // Only show AirDrop
        sourceRect: nil,
        result: result
    )
}
```

However, this approach is fragile (Apple may add new activity types). Better approach: use `UIActivityViewController` normally but with a `preferredAirDropTarget` hint (iOS 17+), or simply let the user pick AirDrop from the standard share sheet.

### 8.2 UI Design

AirDrop gets a dedicated button in the post-export success state (section 3.4). It uses `CNSymbol('airplayaudio')` or `CNSymbol('wave.3.right')` as its icon. Tapping it opens the standard share sheet pre-filtered to nearby AirDrop devices.

### 8.3 Edge Cases

- **AirDrop disabled in Settings.** `UIActivityViewController` will not show AirDrop option. No crash, just not visible.
- **No nearby devices.** AirDrop shows "Looking for people..." indefinitely. This is iOS standard behavior.
- **Large files (>5GB).** AirDrop has a theoretical 5GB limit but may time out on slow connections. Files from a mobile video editor are unlikely to exceed this.
- **File format not recognized by receiver.** ProRes files may not be playable on non-Apple devices. Show info tooltip: "ProRes files are best shared with Mac or other iOS devices."

---

## 9. Project Sharing

### 9.1 Data Models

```dart
/// Represents a packaged project bundle for sharing.
@immutable
class LiquidProjectBundle {
  final String projectId;
  final String projectName;
  final int version;                // Bundle format version
  final ProjectManifest manifest;
  final String bundlePath;          // Path to .liquidproject file

  const LiquidProjectBundle({...});
}

/// Manifest describing bundle contents.
@immutable
class ProjectManifest {
  final String appVersion;
  final String minAppVersion;       // Minimum app version to open
  final DateTime exportedAt;
  final int totalSizeBytes;
  final List<BundledAsset> assets;
  final ProjectData projectData;    // Serialized Project JSON

  const ProjectManifest({...});
}

/// Reference to a media file included in the bundle.
@immutable
class BundledAsset {
  final String assetId;             // MediaAsset UUID
  final String relativePath;        // Path within bundle
  final String contentHash;         // For integrity verification
  final int sizeBytes;
  final MediaType type;

  const BundledAsset({...});
}
```

### 9.2 Bundle Format

```
MyProject.liquidproject/          (actually a ZIP file with custom extension)
  manifest.json                   Project metadata
  project.json                    Full Project serialization
  media/
    asset_uuid1.mp4              Source video files
    asset_uuid2.mp4
    asset_uuid3.wav
  thumbnails/
    project_thumb.jpg            Project thumbnail
    clip_thumb_0.jpg             Per-clip thumbnails
  proxies/                       (optional, excluded by default to save space)
    proxy_uuid1.mp4
```

### 9.3 Architecture

```
Flutter (ProjectBundleService)
  |
  | 1. Serialize Project to JSON
  | 2. Collect all referenced media files
  | 3. Copy media to temp staging directory
  | 4. Create manifest.json
  | 5. ZIP everything with .liquidproject extension
  |
  | MethodChannel: 'createProjectBundle' / 'importProjectBundle'
  v
Swift (ProjectBundleNativeService)
  |
  | Uses Foundation's FileManager for file operations
  | Uses Compression framework for ZIP
  v
Result: path to .liquidproject file
```

### 9.4 Native Implementation

```swift
/// Creates and imports .liquidproject bundles.
final class ProjectBundleService {

    /// Create a .liquidproject bundle from a project.
    func createBundle(
        projectJson: [String: Any],
        mediaFiles: [[String: String]],    // [{assetId, sourcePath}]
        thumbnailPath: String?,
        includeProxies: Bool,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("bundle_\(UUID().uuidString)")

            do {
                // Create directory structure
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(
                    at: tempDir.appendingPathComponent("media"),
                    withIntermediateDirectories: true
                )

                // Write project.json
                let projectData = try JSONSerialization.data(withJSONObject: projectJson)
                try projectData.write(to: tempDir.appendingPathComponent("project.json"))

                // Copy media files
                var bundledAssets: [[String: Any]] = []
                var totalSize: Int64 = 0

                for mediaFile in mediaFiles {
                    guard let assetId = mediaFile["assetId"],
                          let sourcePath = mediaFile["sourcePath"] else { continue }

                    let sourceURL = URL(fileURLWithPath: sourcePath)
                    let destFilename = "\(assetId).\(sourceURL.pathExtension)"
                    let destURL = tempDir.appendingPathComponent("media/\(destFilename)")

                    try FileManager.default.copyItem(at: sourceURL, to: destURL)

                    let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
                    let fileSize = (attrs[.size] as? Int64) ?? 0
                    totalSize += fileSize

                    bundledAssets.append([
                        "assetId": assetId,
                        "relativePath": "media/\(destFilename)",
                        "sizeBytes": fileSize,
                    ])
                }

                // Write manifest.json
                let manifest: [String: Any] = [
                    "version": 1,
                    "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "1.0",
                    "minAppVersion": "1.0",
                    "exportedAt": ISO8601DateFormatter().string(from: Date()),
                    "totalSizeBytes": totalSize,
                    "assets": bundledAssets,
                ]
                let manifestData = try JSONSerialization.data(withJSONObject: manifest)
                try manifestData.write(to: tempDir.appendingPathComponent("manifest.json"))

                // ZIP the directory
                let bundleName = (projectJson["name"] as? String ?? "Project") + ".liquidproject"
                let bundlePath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(bundleName)

                // Remove existing file if present
                try? FileManager.default.removeItem(at: bundlePath)

                // Use NSFileCoordinator for ZIP creation
                try self.zipDirectory(at: tempDir, to: bundlePath)

                // Clean up staging directory
                try? FileManager.default.removeItem(at: tempDir)

                DispatchQueue.main.async {
                    result(bundlePath.path)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "BUNDLE_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }
}
```

### 9.5 Import Flow

1. User receives `.liquidproject` file (via AirDrop, Files, Messages).
2. iOS opens Liquid Editor via registered UTType handler.
3. App extracts ZIP to temp directory.
4. Validates manifest version compatibility.
5. Copies media files to app's Documents directory.
6. Registers MediaAssets in the registry.
7. Deserializes `project.json` and creates a new Project.
8. Opens the project in the editor.

### 9.6 UTType Registration

In `Info.plist`:
```xml
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key>
    <string>com.liquideditor.project</string>
    <key>UTTypeDescription</key>
    <string>Liquid Editor Project</string>
    <key>UTTypeConformsTo</key>
    <array>
      <string>com.pkware.zip-archive</string>
    </array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <array>
        <string>liquidproject</string>
      </array>
      <key>public.mime-type</key>
      <string>application/x-liquidproject</string>
    </dict>
  </dict>
</array>

<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key>
    <string>Liquid Editor Project</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>com.liquideditor.project</string>
    </array>
    <key>LSHandlerRank</key>
    <string>Owner</string>
  </dict>
</array>
```

### 9.7 Edge Cases

- **Bundle from newer app version.** Check `minAppVersion` in manifest. Show `CupertinoAlertDialog`: "This project requires Liquid Editor X.Y or newer."
- **Missing media files in bundle.** Some assets may have been removed. Mark them as unlinked in the MediaAssetRegistry and show a relink dialog.
- **Duplicate media (same contentHash).** Use existing asset instead of importing duplicate.
- **Bundle > 4GB.** ZIP64 extension needed. NSFileCoordinator handles this automatically.
- **Disk space insufficient for extraction.** Check available space before extracting. Show error if insufficient.
- **Corrupted ZIP.** Handle extraction errors gracefully. Show `CupertinoAlertDialog` with specific error.
- **Bundle contains non-media files (malicious).** Validate all extracted files against manifest. Ignore unknown files. Never execute extracted code.

---

## 10. Batch Export

### 10.1 Data Models

```dart
/// Configuration for a batch of exports.
@immutable
class BatchExportConfig {
  final String batchId;
  final List<ExportJobConfig> jobs;
  final BatchStrategy strategy;

  const BatchExportConfig({...});
}

enum BatchStrategy {
  /// Run all exports sequentially (lower memory, slower).
  sequential,

  /// Run exports in parallel where possible (higher memory, faster).
  /// Limited to 2 simultaneous on devices with < 4GB RAM.
  parallel,
}

/// Individual export job within a batch.
@immutable
class ExportJobConfig {
  final String jobId;
  final String label;              // "Instagram Reels", "YouTube 4K", etc.
  final PlatformPreset? preset;    // null = custom settings
  final int width;
  final int height;
  final int fps;
  final double bitrateMbps;
  final String codec;
  final String container;
  final bool enableHdr;
  final AutoCropConfig? cropConfig;
  final AudioExportConfig? audioConfig;  // null = include original audio

  const ExportJobConfig({...});
}

/// Status of a batch export.
@immutable
class BatchExportStatus {
  final String batchId;
  final int totalJobs;
  final int completedJobs;
  final int failedJobs;
  final List<ExportJobStatus> jobStatuses;
  final Duration elapsed;
  final Duration? estimatedRemaining;

  const BatchExportStatus({...});

  double get overallProgress =>
      totalJobs > 0 ? completedJobs / totalJobs : 0.0;
}

@immutable
class ExportJobStatus {
  final String jobId;
  final String label;
  final BackgroundExportState state;
  final double progress;           // 0.0-1.0 for individual job
  final String? outputPath;
  final int? fileSizeBytes;
  final String? errorMessage;

  const ExportJobStatus({...});
}
```

### 10.2 Architecture

Batch export reuses the single-export pipeline but adds an orchestration layer:

```
Flutter (BatchExportController)
  |
  | For each job in batch:
  |   MethodChannel: 'renderComposition' with job-specific params
  |   EventChannel: job-specific progress
  v
Swift (BatchExportOrchestrator)
  |
  | Sequential: one AVAssetExportSession at a time
  | Parallel: up to 2 concurrent AVAssetExportSessions
  v
Results accumulated, reported to Flutter per-job
```

**Key challenge: progress multiplexing.**

Current event channel sends a single `Double`. For batch export, we need per-job progress.

**Solution: Structured progress events.**

```swift
/// Updated event sink to send structured progress.
struct ExportProgressEvent {
    let exportId: String
    let progress: Double        // 0.0-1.0
    let phase: String           // "preparing", "rendering", "encoding", "saving"
    let framesRendered: Int
    let totalFrames: Int
    let bytesWritten: Int64
    let estimatedTotalBytes: Int64

    func toDictionary() -> [String: Any] {
        return [
            "exportId": exportId,
            "progress": progress,
            "phase": phase,
            "framesRendered": framesRendered,
            "totalFrames": totalFrames,
            "bytesWritten": bytesWritten,
            "estimatedTotalBytes": estimatedTotalBytes,
        ]
    }
}
```

The event channel now sends `Map<String, Any>` instead of `Double`. The Flutter side deserializes and routes to the correct job's progress stream.

### 10.3 UI Design

The batch export UI is a multi-step sheet:

**Step 1: Format Selection**
- Grid of platform preset cards (Instagram, TikTok, YouTube, etc.)
- Each card is a `CupertinoButton` with checkbox
- "Custom" card for manual settings
- User checks multiple formats

**Step 2: Configuration Review**
- List of selected formats with estimated file sizes
- Total estimated size and time
- "Start Batch Export" button

**Step 3: Progress**
- Vertical list of jobs with individual progress bars
- Each job shows: label, progress %, phase, estimated time remaining
- Overall progress bar at top
- Jobs that complete show checkmark with file size
- Jobs that fail show error icon with retry button

### 10.4 Edge Cases

- **All jobs fail.** Show summary dialog with error details for each job.
- **Disk space runs out mid-batch.** Stop remaining jobs. Report partial success. Clean up temp files for failed jobs.
- **User cancels batch.** Cancel running job(s). Remove queued jobs. Keep completed exports.
- **Mixed HDR/SDR in same batch.** Each job independently configures HDR. No cross-job dependency.
- **Memory pressure with parallel jobs.** Monitor `os_proc_available_memory()`. If below 200MB, downgrade from parallel to sequential.
- **Same output filename collision.** Append job index to filename: `composition_uuid_0.mp4`, `composition_uuid_1.mp4`.

---

## 11. Burn-in Subtitles

### 11.1 Data Models

```dart
/// Subtitle entry for burn-in rendering.
@immutable
class SubtitleEntry {
  final String id;
  final Duration startTime;       // Timeline time
  final Duration endTime;
  final String text;
  final SubtitleStyle style;

  const SubtitleEntry({...});

  Duration get duration => endTime - startTime;
}

/// Visual style for burned-in subtitles.
@immutable
class SubtitleStyle {
  final String fontFamily;        // SF Pro Display, SF Mono, etc.
  final double fontSize;          // Points (scaled to output resolution)
  final Color textColor;
  final Color? backgroundColor;  // null = no background
  final double backgroundOpacity;
  final Color? outlineColor;     // Text stroke color
  final double outlineWidth;
  final SubtitlePosition position;
  final double marginBottom;     // Percentage of frame height (0.0-1.0)
  final TextAlign alignment;
  final bool bold;
  final bool italic;

  const SubtitleStyle({...});
}

enum SubtitlePosition {
  top,
  center,
  bottom,
  custom,
}
```

### 11.2 Architecture

**AVAssetExportSession cannot burn in subtitles.** This requires `AVAssetWriter` with `AVVideoCompositionCoreAnimationTool`.

```
Flutter
  |
  | MethodChannel: 'renderWithSubtitles'
  | Sends: clips + keyframes + subtitles array
  v
Swift (SubtitleRenderer)
  |
  | 1. Build AVMutableComposition (existing)
  | 2. Create CATextLayer for each subtitle
  | 3. Create CALayer animation for timing (opacity 0->1->0)
  | 4. Use AVVideoCompositionCoreAnimationTool to composite text over video
  | 5. Export via AVAssetExportSession with videoComposition
  v
Output: video with burned-in text
```

### 11.3 Native Implementation

```swift
/// Renders subtitles onto video using Core Animation layers.
final class SubtitleRenderer {

    func buildSubtitleLayers(
        subtitles: [[String: Any]],
        videoSize: CGSize,
        videoDuration: CMTime
    ) -> CALayer {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)

        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: videoSize)

        for subtitleData in subtitles {
            guard let text = subtitleData["text"] as? String,
                  let startMs = subtitleData["startTimeMs"] as? Int,
                  let endMs = subtitleData["endTimeMs"] as? Int,
                  let style = subtitleData["style"] as? [String: Any]
            else { continue }

            let textLayer = createTextLayer(
                text: text,
                style: style,
                videoSize: videoSize
            )

            // Animate visibility
            let startTime = CMTime(value: CMTimeValue(startMs), timescale: 1000)
            let endTime = CMTime(value: CMTimeValue(endMs), timescale: 1000)

            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0.0
            fadeIn.toValue = 1.0
            fadeIn.beginTime = CMTimeGetSeconds(startTime)
            fadeIn.duration = 0.2
            fadeIn.fillMode = .forwards
            fadeIn.isRemovedOnCompletion = false

            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.beginTime = CMTimeGetSeconds(endTime) - 0.2
            fadeOut.duration = 0.2
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false

            textLayer.opacity = 0
            textLayer.add(fadeIn, forKey: "fadeIn")
            textLayer.add(fadeOut, forKey: "fadeOut")

            overlayLayer.addSublayer(textLayer)
        }

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        return parentLayer
    }

    private func createTextLayer(
        text: String,
        style: [String: Any],
        videoSize: CGSize
    ) -> CATextLayer {
        let textLayer = CATextLayer()
        let fontSize = (style["fontSize"] as? Double ?? 24.0) * (videoSize.height / 1080.0)

        let font = CTFontCreateWithName(
            (style["fontFamily"] as? String ?? "SF Pro Display") as CFString,
            fontSize,
            nil
        )

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.cgColor,
        ]

        textLayer.string = NSAttributedString(string: text, attributes: attributes)
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale

        // Position at bottom with margin
        let marginBottom = (style["marginBottom"] as? Double ?? 0.1) * videoSize.height
        let textHeight = fontSize * 1.5
        textLayer.frame = CGRect(
            x: videoSize.width * 0.1,
            y: marginBottom,
            width: videoSize.width * 0.8,
            height: textHeight
        )

        return textLayer
    }
}
```

Then integrate with export:

```swift
// In renderComposition, after building videoComposition:
if let subtitles = args["subtitles"] as? [[String: Any]], !subtitles.isEmpty {
    let subtitleRenderer = SubtitleRenderer()
    let animationLayer = subtitleRenderer.buildSubtitleLayers(
        subtitles: subtitles,
        videoSize: finalOutputSize,
        videoDuration: totalDuration
    )

    // The video layer is the second sublayer (index 1)
    let videoLayer = animationLayer.sublayers![0]
    let animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer,
        in: animationLayer
    )
    videoComposition.animationTool = animationTool
}
```

### 11.4 Edge Cases

- **No subtitles.** Skip subtitle rendering entirely. No performance cost.
- **Subtitle overlaps.** Multiple subtitles at the same time are stacked vertically.
- **Very long subtitle text.** Wrap text within 80% of frame width. Truncate with ellipsis if more than 3 lines.
- **RTL text (Arabic, Hebrew).** Use `NSAttributedString` with `.writingDirection` attribute.
- **Emoji in subtitles.** Core Animation handles emoji via `CTFontCreateWithName`.
- **Subtitle timing outside clip range.** Clamp to composition duration. Ignore subtitles entirely outside range.
- **Core Animation layer timing vs video time.** `CAAnimation.beginTime` uses `AVCoreAnimationBeginTimeAtZero` (0.0 = start of composition). Must use `CMTimeGetSeconds()` for accurate mapping.

---

## 12. Render Preview

### 12.1 Data Models

```dart
/// Configuration for render preview.
@immutable
class RenderPreviewConfig {
  final Duration startTime;        // Preview segment start
  final Duration duration;         // Preview duration (default 5s)
  final int width;                 // Preview resolution (lower than export)
  final int height;
  final int fps;
  final bool includeAudio;
  final bool includeSubtitles;
  final AutoCropConfig? cropConfig;

  const RenderPreviewConfig({...});

  /// Default: 5-second preview at 720p from current playhead.
  factory RenderPreviewConfig.quick({
    required Duration playheadPosition,
    required int sourceWidth,
    required int sourceHeight,
  }) {
    return RenderPreviewConfig(
      startTime: playheadPosition,
      duration: const Duration(seconds: 5),
      width: 1280,
      height: 720,
      fps: 30,
      includeAudio: true,
      includeSubtitles: true,
    );
  }
}
```

### 12.2 Architecture

Render preview uses the existing `renderComposition` pipeline but with a time range filter and lower quality settings for speed.

```swift
// In renderComposition, add optional timeRange parameter:
func renderComposition(
    // ... existing parameters ...
    previewStartMs: Int?,        // nil = full export
    previewDurationMs: Int?      // nil = full export
) {
    // If preview range specified:
    if let startMs = previewStartMs, let durationMs = previewDurationMs {
        // Only insert clips that overlap with preview range
        // Adjust clip in/out points to match preview window
        // Use lower resolution and bitrate for speed
    }
}
```

### 12.3 UI Design

"Preview Export" button is placed next to the main "Export" button. It uses a `CupertinoButton` with `CupertinoIcons.play_circle`.

After render preview completes (typically 2-5 seconds), the result plays in an inline video player within the export sheet, replacing the static preview. The user can:
- Play/pause the preview
- Scrub through the 5-second segment
- Compare with the original by toggling a split-screen view
- Adjust settings and re-preview

### 12.4 Edge Cases

- **Preview segment starts in a gap.** Advance to the next clip start automatically.
- **Preview segment shorter than 1 second.** Minimum preview duration is 1 second.
- **Preview segment extends past end of timeline.** Clamp to timeline end.
- **Preview at 4K settings.** Force downscale to 720p for preview regardless of export resolution. Preview is for visual correctness, not resolution verification.
- **Preview with HDR on SDR display.** Show tone-mapped SDR preview. Note: iOS handles HDR-to-SDR tone mapping automatically in AVPlayer.

---

## 13. Export Progress

### 13.1 Data Models

```dart
/// Detailed export progress information.
@immutable
class ExportProgress {
  final String exportId;
  final ExportPhase phase;
  final double overallProgress;     // 0.0-1.0

  // Phase-specific progress
  final int framesRendered;
  final int totalFrames;
  final int bytesWritten;
  final int estimatedTotalBytes;

  // Time tracking
  final DateTime startedAt;
  final Duration elapsed;
  final Duration? estimatedRemaining;

  // System metrics
  final double? cpuUsage;           // 0.0-1.0
  final int? memoryUsageMB;
  final double? thermalState;       // 0=nominal, 1=fair, 2=serious, 3=critical
  final int? availableDiskMB;

  const ExportProgress({...});

  String get etaString {
    if (estimatedRemaining == null) return 'Calculating...';
    final seconds = estimatedRemaining!.inSeconds;
    if (seconds < 60) return '${seconds}s remaining';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes}m ${remainingSeconds}s remaining';
  }

  String get fileSizeString {
    final mb = bytesWritten / (1024 * 1024);
    final totalMb = estimatedTotalBytes / (1024 * 1024);
    if (totalMb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} / ${(totalMb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} / ${totalMb.toStringAsFixed(0)} MB';
  }
}

enum ExportPhase {
  preparing,      // Building composition, allocating resources
  rendering,      // Encoding frames (longest phase)
  encoding,       // Finalizing container, writing metadata
  saving,         // Saving to Photos / Files
  sharing,        // UIActivityViewController active
  completed,
  failed,
  cancelled,
}
```

### 13.2 Native Implementation

Replace the current `Timer`-based progress polling with a structured event system:

```swift
/// Enhanced progress reporting for exports.
final class ExportProgressReporter {
    weak var eventSinkProvider: EventSinkProvider?

    private var startTime: Date?
    private var totalFrames: Int = 0
    private var exportId: String = ""

    func startTracking(exportId: String, totalFrames: Int) {
        self.exportId = exportId
        self.totalFrames = totalFrames
        self.startTime = Date()
    }

    func reportProgress(
        session: AVAssetExportSession?,
        framesRendered: Int,
        bytesWritten: Int64
    ) {
        let progress = session?.progress ?? Float(framesRendered) / Float(max(totalFrames, 1))
        let elapsed = Date().timeIntervalSince(startTime ?? Date())

        // ETA calculation: time_elapsed / progress_so_far * remaining_progress
        var estimatedRemainingMs: Int64 = 0
        if progress > 0.01 {
            let totalEstimated = elapsed / Double(progress)
            let remaining = totalEstimated - elapsed
            estimatedRemainingMs = Int64(remaining * 1000)
        }

        // System metrics
        let thermalState: Int
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = 0
        case .fair: thermalState = 1
        case .serious: thermalState = 2
        case .critical: thermalState = 3
        @unknown default: thermalState = 0
        }

        let availableDiskBytes = try? FileManager.default
            .attributesOfFileSystem(forPath: NSTemporaryDirectory())[.systemFreeSize] as? Int64

        let event: [String: Any] = [
            "exportId": exportId,
            "progress": Double(progress),
            "phase": "rendering",
            "framesRendered": framesRendered,
            "totalFrames": totalFrames,
            "bytesWritten": bytesWritten,
            "estimatedTotalBytes": bytesWritten > 0 && progress > 0
                ? Int64(Double(bytesWritten) / Double(progress))
                : 0,
            "elapsedMs": Int64(elapsed * 1000),
            "estimatedRemainingMs": estimatedRemainingMs,
            "thermalState": thermalState,
            "availableDiskMB": (availableDiskBytes ?? 0) / (1024 * 1024),
        ]

        DispatchQueue.main.async { [weak self] in
            self?.eventSinkProvider?.eventSink?(event)
        }
    }
}
```

### 13.3 UI Design

The export progress UI replaces the current simple percentage display:

1. **Large percentage** - Centered, 56pt font (existing)
2. **Phase indicator** - Below percentage: "Rendering frame 423/1800"
3. **ETA** - "About 2m 15s remaining"
4. **Progress details row:**
   - File size: "45.2 / 128.0 MB"
   - Elapsed: "1:23"
   - Speed: "1.2x realtime"
5. **System health indicators** (optional, shown when concerning):
   - Thermal: orange/red chip when thermalState >= 2
   - Disk: red chip when available disk < 500MB
   - Memory: orange chip when memory usage > 350MB
6. **Animated gradient border** (existing) with smooth progress

All text uses `AppTypography` styles. System health chips use `IndicatorChip` from `glass_styles.dart`.

### 13.4 Backward Compatibility

The event channel must handle both old (Double) and new (Map) progress formats during migration:

```dart
_progressSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
  if (event is double) {
    // Legacy format
    _handleLegacyProgress(event);
  } else if (event is Map) {
    // New structured format
    _handleStructuredProgress(ExportProgress.fromMap(event));
  }
});
```

### 13.5 Edge Cases

- **ETA fluctuates wildly at start.** Do not show ETA until progress > 5%. Show "Calculating..." instead.
- **Thermal throttle causes slowdown.** ETA recalculates automatically. Show thermal warning chip.
- **Export stalls (no progress for 30s).** Show warning: "Export may be stalled. Tap to retry or cancel."
- **Very fast export (< 2 seconds).** Skip detailed progress; show indeterminate spinner then jump to completion.

---

## 14. Export Queue

### 14.1 Data Models

```dart
/// Manages a queue of export operations.
class ExportQueueManager extends ChangeNotifier {
  final List<QueuedExport> _queue = [];
  QueuedExport? _currentExport;
  int _maxConcurrent = 1;

  List<QueuedExport> get queue => List.unmodifiable(_queue);
  QueuedExport? get currentExport => _currentExport;
  bool get isRunning => _currentExport != null;
  int get pendingCount => _queue.where((e) => e.state == QueueState.pending).length;

  /// Add an export to the queue.
  String enqueue(ExportJobConfig config, {QueuePriority priority = QueuePriority.normal}) {
    final id = const Uuid().v4();
    _queue.add(QueuedExport(
      id: id,
      config: config,
      state: QueueState.pending,
      priority: priority,
      enqueuedAt: DateTime.now(),
    ));
    notifyListeners();
    _processNextIfIdle();
    return id;
  }

  /// Cancel a queued or running export.
  void cancel(String exportId) { ... }

  /// Reorder queue.
  void reorder(int oldIndex, int newIndex) { ... }

  /// Retry a failed export.
  void retry(String exportId) { ... }

  void _processNextIfIdle() { ... }
}

@immutable
class QueuedExport {
  final String id;
  final ExportJobConfig config;
  final QueueState state;
  final QueuePriority priority;
  final DateTime enqueuedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final double progress;
  final String? outputPath;
  final String? errorMessage;

  const QueuedExport({...});
}

enum QueueState {
  pending,
  running,
  completed,
  failed,
  cancelled,
}

enum QueuePriority {
  high,
  normal,
  low,
}
```

### 14.2 Architecture

```
ExportQueueManager (Flutter, ChangeNotifier)
  |
  | Maintains ordered list of QueuedExport
  | Processes one at a time (sequential by default)
  | Listens to export progress via EventChannel
  |
  | For each job:
  |   1. Set state to 'running'
  |   2. Call MethodChannel 'renderComposition'
  |   3. Listen to progress events
  |   4. On completion: set state to 'completed', process next
  |   5. On failure: set state to 'failed', process next
  v
VideoProcessingService (Swift)
  |
  | Processes one render at a time
  | Reports progress with exportId
```

### 14.3 Persistence

The queue survives app restart by serializing to UserDefaults or a JSON file:

```dart
/// Serialize queue state for persistence.
Map<String, dynamic> toJson() => {
  'queue': _queue.map((e) => e.toJson()).toList(),
  'maxConcurrent': _maxConcurrent,
};

/// Restore queue from persistence.
void fromJson(Map<String, dynamic> json) {
  _queue.clear();
  final items = (json['queue'] as List)
      .map((e) => QueuedExport.fromJson(e))
      .where((e) => e.state == QueueState.pending || e.state == QueueState.running)
      .toList();
  // Reset running items to pending (app was killed)
  for (final item in items) {
    _queue.add(item.state == QueueState.running
        ? item.copyWith(state: QueueState.pending)
        : item);
  }
}
```

### 14.4 UI Design

The export queue is accessible from:
1. **Mini indicator** in the navigation bar (when exports are queued/running)
2. **Queue sheet** - Full-screen Liquid Glass sheet showing all queued exports

Queue sheet layout:
- **Currently exporting:** Large progress card with live preview
- **Up next:** Reorderable list (drag handles) of pending exports
- **Completed:** Collapsible section with share/delete actions
- **Failed:** Section with retry buttons

Built with `CupertinoListSection` and `CupertinoListTile`.

### 14.5 Edge Cases

- **Queue empty.** Hide the mini indicator entirely.
- **App killed with pending queue.** On relaunch, restore pending items and show "X exports waiting. Resume?"
- **Export in queue references deleted project.** Mark as failed: "Project no longer available."
- **Disk fills up mid-queue.** Pause queue. Alert user. Do not attempt next job until disk space is freed.
- **Settings changed after queuing.** Each queued export stores a snapshot of settings at enqueue time. Changes to export settings do not affect queued jobs.

---

## 15. Native Export Pipeline Analysis

### 15.1 AVAssetExportSession vs AVAssetWriter

| Capability | AVAssetExportSession | AVAssetWriter |
|-----------|---------------------|---------------|
| **Ease of use** | High (preset-based) | Low (manual frame handling) |
| **Subtitle burn-in** | Via AVVideoCompositionCoreAnimationTool | Via direct pixel composition |
| **Per-frame control** | No | Yes |
| **Cancellation** | `cancelExport()` | `cancelWriting()` |
| **Resume support** | No | Yes (append to existing file) |
| **Bitrate control** | Indirect (preset + fileLengthLimit) | Direct (AVVideoAverageBitRateKey) |
| **Hardware encoding** | Automatic | Manual (kVTCompressionPropertyKey_RealTime) |
| **Progress accuracy** | session.progress (0.0-1.0) | Frame count / total frames |
| **Multi-pass encoding** | Yes (automatic) | Manual |
| **HDR support** | Yes | Yes (with explicit config) |
| **Memory usage** | Managed by system | Developer-managed |
| **Error recovery** | Limited | More granular |

### 15.2 Recommended Strategy

**Phase 1-2:** Continue using `AVAssetExportSession` for all current features. It handles:
- Multi-clip composition via AVMutableComposition
- Keyframe transforms via AVMutableVideoCompositionLayerInstruction
- HDR color space
- Audio mixing
- Progress reporting

Add `AVVideoCompositionCoreAnimationTool` for subtitle burn-in (works with AVAssetExportSession).

**Phase 3-4:** Migrate to `AVAssetWriter` for:
- Background export with pause/resume
- Precise bitrate control
- Frame-level progress
- Custom watermarks (future)

The migration is incremental. Both pipelines can coexist:

```swift
protocol ExportPipeline {
    func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition?,
        outputURL: URL,
        config: ExportConfig
    ) async throws -> URL
}

final class ExportSessionPipeline: ExportPipeline { ... }
final class AssetWriterPipeline: ExportPipeline { ... }
```

### 15.3 Cancellation Protocol

Current limitation: no native cancellation.

Add to `VideoProcessingService`:

```swift
private var currentExportSession: AVAssetExportSession?

func cancelCurrentExport() {
    currentExportSession?.cancelExport()
    currentExportSession = nil
}
```

Add method channel handler:

```swift
case "cancelExport":
    service.cancelCurrentExport()
    result(nil)
```

### 15.4 Temp File Management

Exports produce temp files that must be cleaned up:

```swift
/// Clean up old export temp files on app launch.
static func cleanupOldExports() {
    let tempDir = FileManager.default.temporaryDirectory
    let fileManager = FileManager.default

    guard let contents = try? fileManager.contentsOfDirectory(
        at: tempDir,
        includingPropertiesForKeys: [.creationDateKey],
        options: []
    ) else { return }

    let cutoff = Date().addingTimeInterval(-7 * 24 * 3600) // 7 days

    for url in contents {
        let filename = url.lastPathComponent
        guard filename.hasPrefix("rendered_") ||
              filename.hasPrefix("composition_") ||
              filename.hasPrefix("audio_") ||
              filename.hasSuffix(".liquidproject")
        else { continue }

        if let attrs = try? url.resourceValues(forKeys: [.creationDateKey]),
           let created = attrs.creationDate,
           created < cutoff {
            try? fileManager.removeItem(at: url)
        }
    }
}
```

---

## 16. Edge Cases & Error Handling

### 16.1 Interrupted Exports

| Interruption | Detection | Recovery |
|-------------|-----------|----------|
| App backgrounded | `UIApplication.willResignActiveNotification` | Begin background task; export continues for ~30s |
| App terminated | No detection possible | On relaunch: detect orphaned temp files, restore queue |
| Phone call | `AVAudioSession.interruptionNotification` | Pause export, resume when interruption ends |
| Screen lock | Same as backgrounded | Background task continues |
| Low memory | `applicationDidReceiveMemoryWarning` | Flush frame buffers, reduce preview quality |
| Crash | No detection | On relaunch: clean orphaned temp files |

### 16.2 Low Disk Space

```swift
func checkDiskSpace(estimatedSizeMB: Int) throws {
    let attrs = try FileManager.default.attributesOfFileSystem(
        forPath: NSTemporaryDirectory()
    )
    let freeBytes = (attrs[.systemFreeSize] as? Int64) ?? 0
    let freeMB = freeBytes / (1024 * 1024)
    let requiredMB = Int64(estimatedSizeMB) + 500  // 500MB safety margin

    if freeMB < requiredMB {
        throw ExportError.insufficientDiskSpace(
            availableMB: Int(freeMB),
            requiredMB: Int(requiredMB)
        )
    }
}
```

Check disk space:
1. Before export starts (pre-check with estimated size)
2. Every 10% progress (ongoing check)
3. Before saving to Photos library

### 16.3 Long Videos

For videos longer than 30 minutes:
- Increase progress reporting interval to 500ms (reduce overhead)
- Use lower-quality preview frame extraction (320x180)
- Warn user about estimated time and file size
- Suggest lower resolution if export would exceed 4GB

### 16.4 Missing Media

When a MediaAsset is unlinked (file moved/deleted):
- Show unlinked assets list before export
- Offer "Relink" option (browse for replacement file using content hash matching)
- Offer "Skip" option (exclude clips referencing missing media; render gaps as black)
- Offer "Cancel" to go back and fix the timeline

### 16.5 Thermal Throttling

```swift
func monitorThermalState() {
    NotificationCenter.default.addObserver(
        forName: ProcessInfo.thermalStateDidChangeNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .serious:
            // Reduce export quality: drop FPS to 30, reduce resolution one tier
            self?.applyThermalThrottle(level: 1)
        case .critical:
            // Pause export, wait for cooldown
            self?.pauseExportForThermal()
        default:
            self?.removeThermalThrottle()
        }
    }
}
```

### 16.6 Error Categories

```swift
enum ExportError: Error {
    case noVideoTrack
    case noAudioTrack
    case compositionFailed(String)
    case exportSessionFailed(String)
    case writerFailed(String)
    case insufficientDiskSpace(availableMB: Int, requiredMB: Int)
    case thermalShutdown
    case cancelled
    case backgroundTimeExpired
    case fileNotFound(String)
    case unsupportedCodec(String)
    case memoryPressure
    case invalidConfiguration(String)
}
```

All errors are mapped to user-friendly messages in Flutter via `CupertinoAlertDialog`.

---

## 17. Performance Budget

### 17.1 Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Export speed (1080p H.264) | >= 1.0x realtime | Duration of source / export time |
| Export speed (4K H.264) | >= 0.5x realtime | Same |
| Export speed (1080p HEVC) | >= 0.7x realtime | Same |
| Memory during export | < 400MB | `os_proc_available_memory()` |
| Memory during batch (parallel) | < 600MB | Same |
| Frame grab latency | < 500ms | Time from tap to image displayed |
| Render preview (5s at 720p) | < 3s | Total render time |
| Export sheet open latency | < 200ms | Time from tap to sheet visible |
| Progress update frequency | 100ms (foreground), 500ms (background) | Timer interval |
| ETA accuracy (after 10% progress) | +/- 20% | Compared to actual |
| Queue serialization | < 50ms | Time to write queue state |
| Project bundle creation | < 30s for 1GB project | Total bundle time |
| Project bundle import | < 15s for 1GB bundle | Total import time |
| Share sheet presentation | < 300ms | Time from tap to share sheet |

### 17.2 Memory Management

During export, the primary memory consumers are:
1. **AVMutableComposition** - ~10-50MB depending on clip count
2. **Frame buffers** - Up to 4 frames in flight (~32MB at 4K)
3. **Export session internal buffers** - ~50-100MB
4. **Preview frame extraction** - ~5MB per frame
5. **Flutter widget tree** - ~20-30MB

Total: ~120-250MB typical, up to 400MB at 4K with preview.

**Mitigation strategies:**
- Nil out preview frame when export enters rendering phase
- Use `autoreleasepool` blocks in frame processing loops
- Monitor `os_proc_available_memory()` and reduce buffer count if < 200MB
- Flush URL cache on memory warning (existing in `applicationDidReceiveMemoryWarning`)

### 17.3 Thermal Management

| Thermal State | Action |
|--------------|--------|
| Nominal | Full quality export |
| Fair | No action, monitor |
| Serious | Reduce FPS to max 30, show warning chip |
| Critical | Pause export, show "Device is warm" alert, resume on cooldown |

### 17.4 Battery Considerations

Export is CPU/GPU intensive. On devices with < 20% battery:
- Show warning: "Your battery is low. Export may drain it quickly."
- Do not block export (user's choice to proceed).
- If battery drops below 5% during export, pause and save progress.

---

## 18. Implementation Plan

### 18.1 Phase Overview

| Phase | Features | Duration | Priority |
|-------|----------|----------|----------|
| **Phase 1** | Export Progress, Frame Grab, Render Preview | 2 weeks | Critical |
| **Phase 2** | Social Share, AirDrop, Platform Presets, Audio Export | 2 weeks | High |
| **Phase 3** | Background Export, Export Queue, Batch Export | 3 weeks | High |
| **Phase 4** | Burn-in Subtitles, Project Sharing | 2 weeks | Medium |

### 18.2 Phase 1: Foundation (Weeks 1-2)

**Goal:** Replace basic progress with detailed progress, add frame grab, add render preview.

**New Files:**

```
lib/
  models/
    export_config.dart            # ExportConfig, ExportProgress, ExportPhase
    frame_grab_config.dart        # FrameGrabConfig, FrameFormat
  core/
    export_progress_controller.dart  # Manages structured progress events
  views/
    export/
      export_progress_view.dart   # Detailed progress UI (extracted from export_sheet.dart)
      frame_grab_sheet.dart       # Frame grab configuration UI
      render_preview_view.dart    # Preview playback within export sheet

ios/Runner/
  ExportProgressReporter.swift    # Structured progress events
```

**Modified Files:**

```
lib/views/export/export_sheet.dart        # Refactor into smaller components
ios/Runner/VideoProcessingService.swift   # Add structured progress, frame grab API
ios/Runner/AppDelegate.swift              # Register new method channel handlers
ios/Runner/VideoConstants.swift           # Add export-related constants
```

**Method Channel Additions:**
- `extractFrameGrab` - High-quality frame extraction with transforms
- `cancelExport` - Cancel in-progress export
- `renderPreview` - Time-range limited render at preview quality

**Event Channel Changes:**
- Event format changes from `Double` to `Map<String, Any>` (with backward compat)

**Test Plan:**
- Unit tests for `ExportProgress` model serialization
- Unit tests for `FrameGrabConfig` validation
- Integration test: export with structured progress events
- Integration test: frame grab at various timestamps
- Integration test: render preview with 5s segment
- Widget test: progress UI displays all fields correctly

### 18.3 Phase 2: Sharing & Presets (Weeks 3-4)

**Goal:** Add social sharing, platform presets, enhanced audio export.

**New Files:**

```
lib/
  models/
    platform_preset.dart          # PlatformPreset, AspectRatioConfig, AutoCropConfig
    audio_export_config.dart      # AudioExportConfig, AudioFormat, AudioQuality
    share_result.dart             # ShareResult, ShareDestination
  views/
    export/
      platform_preset_selector.dart  # Horizontal preset row UI
      auto_crop_preview.dart         # Crop preview overlay
      audio_export_sheet.dart        # Audio format selection UI
      share_success_view.dart        # Post-export share UI

ios/Runner/
  ShareService.swift              # UIActivityViewController wrapper
```

**Modified Files:**

```
lib/views/export/export_sheet.dart           # Add preset selector, share flow
ios/Runner/VideoProcessingService.swift      # Add audio format export, auto-crop
ios/Runner/VideoTransformCalculator.swift    # Add crop transform calculations
ios/Runner/AppDelegate.swift                 # Register share channel handlers
```

**Method Channel Additions:**
- `shareFile` - Present UIActivityViewController
- `shareViaAirDrop` - AirDrop-specific share
- `exportAudioWithFormat` - Export audio in WAV/AAC/ALAC/FLAC

**Test Plan:**
- Unit tests for `PlatformPreset` output dimension calculations
- Unit tests for `AspectRatioConfig.outputDimensions`
- Unit tests for `AudioExportConfig` validation
- Integration test: export with Instagram Reels preset (9:16 crop)
- Integration test: export audio as WAV and AAC
- Integration test: share file via UIActivityViewController (manual verification)
- Widget test: preset selector layout and selection
- Widget test: audio export sheet controls

### 18.4 Phase 3: Background & Queue (Weeks 5-7)

**Goal:** Enable background export continuation, export queue, batch export.

**New Files:**

```
lib/
  models/
    export_queue.dart             # QueuedExport, QueueState, QueuePriority
    batch_export_config.dart      # BatchExportConfig, BatchStrategy
  core/
    export_queue_manager.dart     # Queue management with ChangeNotifier
    batch_export_controller.dart  # Batch orchestration
  views/
    export/
      export_queue_sheet.dart     # Queue management UI
      batch_export_sheet.dart     # Multi-format selection UI
      mini_export_indicator.dart  # Persistent nav bar indicator

ios/Runner/
  BackgroundExportManager.swift   # Background task management
  BatchExportOrchestrator.swift   # Batch export coordination
```

**Modified Files:**

```
lib/views/export/export_sheet.dart        # Add queue integration
lib/views/library/project_library_view.dart  # Add mini export indicator
ios/Runner/VideoProcessingService.swift   # Add cancellation, batch support
ios/Runner/AppDelegate.swift              # Register background tasks, batch handlers
```

**Method Channel Additions:**
- `startBackgroundExport` - Begin export with background task registration
- `pauseExport` / `resumeExport` - Background task lifecycle
- `getExportQueueState` - Restore queue after app restart

**Test Plan:**
- Unit tests for `ExportQueueManager` ordering, priority, state transitions
- Unit tests for queue serialization/deserialization
- Unit tests for `BatchExportConfig` validation
- Integration test: queue 3 exports, verify sequential processing
- Integration test: cancel running export, verify next in queue starts
- Integration test: batch export with 2 formats
- Integration test: background export continuation (manual - requires device)
- Widget test: queue sheet layout, reordering
- Widget test: mini indicator visibility and tap behavior
- Widget test: batch export multi-select

### 18.5 Phase 4: Subtitles & Project Bundle (Weeks 8-9)

**Goal:** Burn-in subtitle rendering, project sharing via .liquidproject bundles.

**New Files:**

```
lib/
  models/
    subtitle.dart                 # SubtitleEntry, SubtitleStyle
    project_bundle.dart           # LiquidProjectBundle, ProjectManifest
  core/
    project_bundle_service.dart   # Bundle creation/import logic
  views/
    export/
      subtitle_editor_sheet.dart  # Subtitle text entry and styling
      project_share_sheet.dart    # Project bundle sharing UI

ios/Runner/
  SubtitleRenderer.swift          # Core Animation text layer composition
  ProjectBundleService.swift      # ZIP creation/extraction
```

**Modified Files:**

```
ios/Runner/VideoProcessingService.swift   # Add subtitle rendering to composition pipeline
ios/Runner/AppDelegate.swift              # Register bundle handlers, UTType handler
ios/Runner/Info.plist                     # Add UTType declaration for .liquidproject
lib/views/export/export_sheet.dart        # Add subtitle option
```

**Method Channel Additions:**
- `renderWithSubtitles` - Export with burned-in subtitles
- `createProjectBundle` - Package project + media into .liquidproject
- `importProjectBundle` - Extract and register imported bundle
- `validateProjectBundle` - Check bundle compatibility before import

**Test Plan:**
- Unit tests for `SubtitleEntry` timing validation
- Unit tests for `SubtitleStyle` serialization
- Unit tests for `ProjectManifest` version compatibility checking
- Unit tests for `LiquidProjectBundle` serialization
- Integration test: export with 3 subtitles at different timestamps
- Integration test: create bundle, verify ZIP contents
- Integration test: import bundle, verify project and media restored
- Integration test: import bundle from newer version (version mismatch)
- Widget test: subtitle editor text entry and preview
- Widget test: project share flow

---

## Appendix A: Method Channel Protocol Summary

### New Methods (All Phases)

| Method | Phase | Direction | Parameters | Returns |
|--------|-------|-----------|------------|---------|
| `extractFrameGrab` | 1 | Flutter->Swift | videoPath, clips, timestampMs, format, quality, maxWidth, maxHeight, applyTransforms | File path (String) |
| `cancelExport` | 1 | Flutter->Swift | exportId | void |
| `renderPreview` | 1 | Flutter->Swift | videoPath, clips, startMs, durationMs, width, height, fps | File path (String) |
| `shareFile` | 2 | Flutter->Swift | filePath, fileType, excludedTypes, sourceRect | ShareResult (Map) |
| `exportAudioWithFormat` | 2 | Flutter->Swift | videoPath, clips, format, sampleRate, channels, bitrate | File path (String) |
| `startBackgroundExport` | 3 | Flutter->Swift | Same as renderComposition + exportId | void |
| `pauseExport` | 3 | Flutter->Swift | exportId | void |
| `resumeExport` | 3 | Flutter->Swift | exportId | void |
| `renderWithSubtitles` | 4 | Flutter->Swift | Same as renderComposition + subtitles array | File path (String) |
| `createProjectBundle` | 4 | Flutter->Swift | projectJson, mediaFiles, thumbnailPath | Bundle path (String) |
| `importProjectBundle` | 4 | Flutter->Swift | bundlePath | ProjectData (Map) |
| `validateProjectBundle` | 4 | Flutter->Swift | bundlePath | ValidationResult (Map) |

### Event Channel Changes

**Channel:** `com.liquideditor/video_processing/progress`

Old format: `Double` (0.0-1.0)

New format (Phase 1+):
```json
{
  "exportId": "uuid-string",
  "progress": 0.45,
  "phase": "rendering",
  "framesRendered": 810,
  "totalFrames": 1800,
  "bytesWritten": 47185920,
  "estimatedTotalBytes": 104857600,
  "elapsedMs": 12500,
  "estimatedRemainingMs": 15200,
  "thermalState": 0,
  "availableDiskMB": 12500
}
```

---

## Appendix B: UI Widget Migration Checklist

The following Material widgets in `export_sheet.dart` must be replaced:

| Current (Material) | Replacement (Cupertino/Liquid Glass) | Line(s) |
|--------------------|------------------------------------|---------|
| `IconButton` + `Icons.close` | `CupertinoButton` + `CupertinoIcons.xmark` | 585-586 |
| `Icons.bug_report` | `CupertinoIcons.ant` or `CNSymbol('ladybug')` | 601 |
| `Switch.adaptive` | `CupertinoSwitch` | 904-909 |
| `Slider` (Material) | `CupertinoSlider` | 828-836, 922-939 |
| `SliderTheme` | Remove (not needed with CupertinoSlider) | 821-829, 920-931 |
| `CircularProgressIndicator` | `CupertinoActivityIndicator` | 694-697 |
| `Icons.pause_rounded` | `CupertinoIcons.pause_fill` | 720 |
| `Icons.play_arrow_rounded` | `CupertinoIcons.play_fill` | 721 |
| `Container` buttons | `CupertinoButton.filled` | 957-981 |

---

## Appendix C: Dependency Impact

| Package | Current Use | New Use |
|---------|-------------|---------|
| `gal` | Save video to Photos | Save video + images to Photos |
| `video_player` | Export preview playback | Same + render preview playback |
| `uuid` | Clip IDs | + Export IDs, Queue IDs, Bundle IDs |
| `path_provider` | (not used) | Temp directory for bundles |
| `archive` | (not used) | **NEW** - ZIP creation/extraction for .liquidproject |
| `share_plus` | (not used) | **NOT NEEDED** - Using native UIActivityViewController |

**Note:** The `archive` Dart package is optional. ZIP operations can be handled entirely in native Swift using `Foundation`'s `FileManager` and the `Compression` framework, or via shell `zip`/`unzip` commands. Native implementation is recommended to avoid adding a dependency.

---

**End of Design Document**

*This document covers 12 features across 4 implementation phases. Each feature includes data models, architecture, native implementation, UI design, and comprehensive edge cases. The design preserves backward compatibility with the existing export pipeline while introducing structured progress, background processing, and a managed queue.*

---

## Review 1 - Architecture & Completeness

**Reviewer:** Claude Opus 4.6 (Senior Architect)
**Date:** 2026-02-06
**Review Scope:** Full design document (Sections 1-18 + Appendices A-C) cross-referenced against live codebase

### Architecture Assessment

**Overall Rating: Strong (8/10)**

The design document is exceptionally thorough at 2,480 lines covering 12 features across 4 phases. The current-state analysis in Section 2 is accurate and honest about limitations. The phased migration from AVAssetExportSession to AVAssetWriter is the correct strategic approach. Data models are well-structured with `@immutable` annotations. The event channel upgrade from `Double` to structured `Map` with backward compatibility is well-designed.

**Key architectural strengths:**
- Clear separation between Flutter UI orchestration and Swift/AVFoundation rendering
- Incremental migration path (AVAssetExportSession -> AVAssetWriter) that avoids Big Bang rewrites
- Proper use of `UIActivityViewController` for sharing instead of third-party packages
- Queue persistence via JSON serialization to survive app restarts
- Structured progress events with system health metrics (thermal, disk, memory)

**Key architectural concerns:**
- The design references `CompositionBuilder.swift` and `CompositionPlayerService` from Timeline V2, but `CompositionBuilder.swift` does not exist in the codebase. Several features implicitly depend on V2 infrastructure.
- The document references `lib/core/auto_reframe_engine.dart` for smart crop focal points, but does not specify the interface contract between the auto-reframe engine and the new crop system.
- The export pipeline currently has a single-source-video assumption (one `videoPath` parameter). Multi-source export via Timeline V2's `MediaAsset` registry is not addressed.

### Codebase Verification

**Verified against live code in:**
- `lib/views/export/export_sheet.dart` (1464 lines)
- `ios/Runner/VideoProcessingService.swift` (912 lines)
- `ios/Runner/VideoTransformCalculator.swift` (207 lines)
- `ios/Runner/VideoConstants.swift` (84 lines)
- `lib/core/timeline_manager.dart` (433 lines)
- `lib/core/clip_manager.dart` (exists, used by export sheet)
- `docs/DESIGN.md` (833 lines)

**Section 2.1 - Flutter Export Layer accuracy:**
- Correct: export_sheet.dart is ~1464 lines (doc says 1464 -- exact match)
- Correct: uses `EventChannel('com.liquideditor/video_processing/progress')` (line 186)
- Correct: uses `Gal.putVideo()` for saving (line 1406)
- Correct: `_buildClipsPayload()` samples at 100ms intervals (line 1123)
- Correct: Material widget violations identified (`Icons.close` line 585, `Switch.adaptive` line 904, `Slider` lines 828-836, `CircularProgressIndicator` line 694-697)
- Correct: No native cancellation signal (line 371 has `// Note: We could also signal native to cancel, but for now we just stop listening`)

**Section 2.2 - Native Export Layer accuracy:**
- Correct: VideoProcessingService.swift is 912 lines (exact match)
- Correct: uses `AVAssetExportSession` exclusively (no AVAssetWriter)
- Correct: progress polling via `Timer.scheduledTimer(withTimeInterval: 0.1)` (line 313, 533)
- Correct: `selectExportPreset()` maps resolution to AVAssetExportSession presets (line 765)
- Correct: HDR uses BT.2020 + HLG (lines 283-287)
- Correct: `exportAudioOnly()` uses `AVAssetExportPresetAppleM4A` (line 816)
- Correct: no `beginBackgroundTask` registration anywhere

**Section 2.3 - Platform Channel Protocol accuracy:**
- Correct: Method channel is `com.liquideditor/video_processing`
- Correct: Event channel sends single `Double` value
- Verified all method names match actual implementations in VideoProcessingService.swift

### Critical Issues

**C1: AVAssetWriter Resume After Background Suspension Is Not Possible As Described**

Section 7.2 states: "using AVAssetWriter's ability to append samples" and Section 7.3 shows `resumeExport()` that "Re-open AVAssetWriter in append mode." This is architecturally incorrect. `AVAssetWriter` does **not** support reopening a partially written file for appending. Once `finishWriting()` is called (or the writer is invalidated), the file is finalized. To resume, you would need to:

1. Read back the partially written file with `AVAssetReader`
2. Create a new `AVAssetWriter` starting from the last complete frame
3. Merge the partial file with the new output

Alternatively, the design should use a segment-based approach: render to individual segment files and concatenate them at the end. This is a fundamental correction needed in the background export architecture.

**Severity:** Critical -- the stated resume mechanism will not work and is a core feature promise.

**C2: Subtitle Burn-in Architecture Has Layer Ordering Bug**

Section 11.3 shows:
```swift
let videoLayer = animationLayer.sublayers![0]  // Comment says "index 1" but code uses [0]
```

The comment says "The video layer is the second sublayer (index 1)" but the code accesses index 0. More importantly, `AVVideoCompositionCoreAnimationTool` requires the `videoLayer` to be the layer where video frames are rendered into, and the `parentLayer` to contain both the videoLayer and any overlay layers. The current implementation adds `videoLayer` first (index 0), then `overlayLayer` (index 1), which is correct for the layer hierarchy, but the code comment is wrong and the index access should be verified.

Additionally, `CAAnimation.beginTime` in the context of `AVVideoCompositionCoreAnimationTool` must use `AVCoreAnimationBeginTimeAtZero` (which is 1e-100, not 0.0) as the reference point. The design notes this concern in Section 11.4 edge cases but does not adjust the `beginTime` values in the code. Using `CMTimeGetSeconds(startTime)` directly without adding `AVCoreAnimationBeginTimeAtZero` will cause subtitle timing to be off by the video start offset.

**Severity:** Critical -- subtitles will render at wrong times without the `AVCoreAnimationBeginTimeAtZero` offset.

**C3: Single-Source Video Assumption Conflicts with Timeline V2 Multi-Source Architecture**

The entire export pipeline (`renderComposition`) takes a single `videoPath: String` parameter. The existing `export_sheet.dart` passes `widget.sourceVideoPath` (line 1309). The new Timeline V2 architecture (documented in `docs/DESIGN.md` Section "Timeline Architecture V2") introduces `MediaAsset` with per-clip source paths. The design document does not address how the export pipeline will handle multi-source timelines where clips reference different video files.

This is not just a future concern -- the `TimelineManager` and `PersistentTimeline` already support `VideoClip` items that can have different `mediaAssetId` values. The export design must specify how clips from different source files are composed into a single AVMutableComposition with multiple source tracks.

**Severity:** Critical -- the single-videoPath architecture cannot export multi-source timelines, which is the direction the codebase is heading.

### Important Issues

**I1: AirDrop Filtering Approach Is Fragile**

Section 8.1 proposes filtering `UIActivity.ActivityType.allCases` to exclude everything except AirDrop. However, `UIActivity.ActivityType` does not conform to `CaseIterable` in iOS, so `.allCases` does not exist. The doc correctly notes this is fragile and recommends the standard share sheet approach, but the code sample is incorrect Swift and would not compile. Recommend removing the filtering code entirely and just using the standard share sheet with a comment about AirDrop being available within it.

**I2: MP3 Export Decision Needs Explicit Resolution**

Section 6.2 lists `mp3` in the `AudioFormat` enum but recommends dropping it. The enum should not include `mp3` if the recommendation is to drop it, as it creates an unimplementable code path. Either remove it from the enum or provide the `AudioToolbox`/`ExtAudioFile` implementation path. The recommendation to drop MP3 is sound (iOS cannot natively encode MP3), but the data model and the recommendation are contradictory.

**I3: Batch Export Parallel Strategy Memory Risk**

Section 10.1 mentions parallel batch export "Limited to 2 simultaneous on devices with < 4GB RAM." However, Section 17.2 states a single 4K export can consume up to 400MB. Two parallel 4K exports would consume up to 800MB, well above the document's own 600MB budget for parallel batch exports. The parallel strategy should be limited to lower resolutions (1080p or below) or the memory budget needs to be revised upward. Additionally, `os_proc_available_memory()` is not a standard iOS API -- the correct function is `os_proc_available_memory()` from `<os/proc.h>`, which requires `import os.proc` in Swift. This should be specified.

**I4: Export Queue Persistence via UserDefaults Is Risky for Large Payloads**

Section 14.3 mentions serializing the queue to "UserDefaults or a JSON file." UserDefaults has a practical size limit (~4MB on iOS, with Apple recommending much less). A queue with detailed export configs, especially those including clip payloads with per-frame keyframe data, could easily exceed this. Recommend always using a JSON file in the app's Documents or Caches directory, and removing the UserDefaults option from the design.

**I5: Project Bundle ZIP Implementation Missing**

Section 9.4 calls `self.zipDirectory(at: tempDir, to: bundlePath)` but this method is not defined anywhere in the design or codebase. iOS does not have a built-in single-call ZIP directory API. The implementation would require either:
- `NSFileCoordinator` with `NSFileCoordinator.WritingOptions.forMoving` (which does not create ZIPs)
- The `Compression` framework (which handles individual data buffers, not directory trees)
- `Process` calling `/usr/bin/zip` (not available in sandboxed iOS apps)
- Third-party library like `ZIPFoundation`

Recommend specifying `ZIPFoundation` (Swift Package) or implementing a custom `Archive`-based solution. Appendix C mentions the `archive` Dart package but says native is recommended -- the native approach needs to specify the actual ZIP library.

**I6: Event Channel Breaking Change Needs Migration Strategy**

Section 13.4 shows backward compatibility for the Flutter side (checking `event is double` vs `event is Map`). However, the native side change is a breaking change: existing `eventSinkProvider?.eventSink?(Double(exportSession.progress))` must be changed to send a `Map`. If the native code is updated but the Flutter code is not yet updated (e.g., during phased rollout), the app will crash. The migration strategy should specify:
1. Add new event channel for structured progress (e.g., `com.liquideditor/video_processing/progress_v2`)
2. Keep old channel active during migration
3. Deprecate old channel after all Flutter consumers are updated

This avoids the single-channel breaking change risk entirely.

**I7: The Design Does Not Address the ClipManager-to-TimelineManager Migration**

The current `export_sheet.dart` uses `ClipManager` (line 140, `widget.clipManager`), but the codebase has migrated to `TimelineManager` (in `lib/core/timeline_manager.dart`). The design document does not mention this transition. The export pipeline should be designed against `TimelineManager` APIs, not the legacy `ClipManager`. The `_buildClipsPayload()` method in the export sheet references `widget.clipManager.clips` and `clip.surroundingKeyframes()` -- these need to be updated to use `TimelineManager.timeline` and the new `VideoClip` type from `lib/models/clips/`.

### Minor Issues

**M1: Instagram Reels Max Duration Is 90 Seconds (Preset Says 90s, But Instagram Now Allows 3 Minutes)**

As of late 2025, Instagram Reels supports videos up to 3 minutes (180 seconds). The preset in Section 4.2 limits to 90 seconds (`maxDurationSeconds: 90`). This should be updated to 180 to match current platform specs.

**M2: YouTube Shorts Max Duration Is 60 Seconds in Preset But 3 Minutes on Platform**

YouTube Shorts now supports up to 3-minute videos. The preset limits to 60 seconds (`maxDurationSeconds: 60`). Update to 180.

**M3: TikTok Max Duration Should Be 10 Minutes**

TikTok allows videos up to 10 minutes (600 seconds). The preset limits to 180 seconds (`maxDurationSeconds: 180`). Should be updated or have separate presets for short/long TikTok videos.

**M4: Twitter/X File Size Limit Is Higher Than Stated**

The preset says `maxFileSizeMB: 512` for X/Twitter. As of 2025, X allows videos up to 2GB for regular users (8GB for X Premium). Consider increasing or adding a note about account-tier differences.

**M5: Missing `GIF Export` Feature**

The Table of Contents mentions no GIF export, but the user prompt specifically asked about "GIF/Image Sequence" export review. The design document does not include GIF or image sequence export. This is a notable omission if it was in scope. Should either be added as a feature or explicitly listed as out of scope.

**M6: `FrameFormat.tiff` Uncommon on Mobile**

Section 5.1 includes TIFF as a frame grab format. TIFF files are uncommon on iOS and not supported by the Photos app for easy viewing. Consider removing TIFF or marking it as a "Pro" feature. HEIF and PNG cover lossless and lossy use cases adequately.

**M7: Export Sheet Height Hardcoded**

The current `export_sheet.dart` uses `MediaQuery.of(context).size.height * 0.92` (line 540). The design document does not address this for the redesigned export sheet. The new multi-step export sheet (with preset selector, audio options, queue integration) may need to be a full-screen `CupertinoPageRoute` rather than a modal bottom sheet to accommodate all the new controls.

**M8: Lottie Dependency Not Listed**

Section 3.4 mentions "Checkmark animation (Lottie or custom)" for the post-export success state. If Lottie is used, it needs to be listed in Appendix C as a new dependency. Recommend using a custom `AnimatedBuilder` with `CupertinoActivityIndicator` style to avoid the dependency.

**M9: `ExportPhase.sharing` Has Ambiguous Scope**

Section 13.1 includes `sharing` as an `ExportPhase`. But sharing happens after export completion and is a separate user action. Including it in the export phase enum conflates the export lifecycle with the post-export sharing lifecycle. Consider removing it from `ExportPhase` and tracking share state separately.

### Questions

**Q1:** Is the `ClipManager` -> `TimelineManager` migration considered a prerequisite for this design, or should the design explicitly handle both paths?

**Q2:** For background export (Section 7), what is the expected user experience when the app is force-quit by iOS during background processing? The design says "Export data is lost" but does not specify whether the user sees any indication on next launch that an export was interrupted.

**Q3:** Section 9 (Project Sharing) introduces a `.liquidproject` file type. Has the UTType identifier `com.liquideditor.project` been reserved? Are there naming conflicts with other apps?

**Q4:** The batch export parallel strategy (Section 10.1) mentions monitoring `os_proc_available_memory()` and downgrading from parallel to sequential if below 200MB. Who triggers this check -- the Flutter orchestrator or the Swift side? If the Flutter side, how does it query available memory across the platform channel?

**Q5:** For subtitle burn-in (Section 11), `AVVideoCompositionCoreAnimationTool` works with `AVAssetExportSession`. However, Section 15.2 says Phase 3-4 will migrate to `AVAssetWriter`. Does `AVVideoCompositionCoreAnimationTool` work with `AVAssetWriter`? (Answer: No, it does not. AVAssetWriter requires manual pixel-level composition. This creates a Phase 4 conflict.)

**Q6:** The current `VideoProcessingService.swift` uses a weak `eventSinkProvider` pattern (line 19). When structured progress events are introduced, will multiple EventChannels be needed (one per export for batch), or will a single multiplexed channel suffice? The design suggests multiplexing via `exportId`, but `FlutterEventChannel` only supports a single `FlutterEventSink` at a time.

### Positive Observations

1. **Excellent current-state analysis.** Section 2 is one of the most thorough current-state audits I have seen in a design document. Every limitation is identified with line-number accuracy.

2. **Comprehensive edge case coverage.** Every feature section includes 4-8 edge cases with specific recovery strategies. The interrupted export table (Section 16.1) is particularly well-structured.

3. **Material-to-Cupertino migration checklist.** Appendix B provides a line-by-line mapping of Material widgets to Cupertino replacements, making the UI migration trackable and verifiable.

4. **Incremental pipeline migration.** The `ExportPipeline` protocol (Section 15.2) allowing `ExportSessionPipeline` and `AssetWriterPipeline` to coexist is a clean migration strategy.

5. **Thermal management integration.** The design includes thermal state monitoring with automatic quality reduction and pause behavior (Sections 16.5, 17.3). This is often overlooked in export designs.

6. **Test plans per phase.** Each implementation phase includes specific unit, integration, and widget test plans. This is critical for the zero-defect standard.

7. **Method channel protocol summary.** Appendix A provides a complete table of all new platform channel methods across all phases, making it easy to review the full API surface.

8. **Backward-compatible event channel.** The Flutter-side code that handles both `Double` and `Map` progress events (Section 13.4) enables gradual migration.

### Checklist Summary

| Check | Status | Notes |
|-------|--------|-------|
| Architecture soundness | PASS | Clean separation of concerns, incremental migration |
| Codebase alignment | PASS (with caveats) | Accurate current-state analysis; ClipManager vs TimelineManager gap (I7) |
| AVAssetWriter vs AVAssetExportSession | PARTIAL | Correct strategy but AVAssetWriter resume is wrong (C1) |
| Background export | FAIL | Resume mechanism is architecturally incorrect (C1) |
| GIF/Image Sequence | FAIL | Not covered in the document (M5) |
| Social platform presets | PARTIAL | Specs outdated for Instagram Reels, YouTube Shorts, TikTok (M1-M3) |
| Audio-only export | PASS | Correct AAC/WAV/ALAC/FLAC approach; MP3 recommendation sound (I2 minor) |
| Export queue | PASS | Well-designed; UserDefaults concern minor (I4) |
| Edge cases | PASS | Exceptionally thorough |
| UI design (Liquid Glass) | PASS | Correct Cupertino components specified; migration checklist provided |
| Multi-source video | FAIL | Not addressed; conflicts with Timeline V2 direction (C3) |
| Subtitle burn-in | PARTIAL | Layer timing bug (C2); AVAssetWriter conflict (Q5) |

**Recommendation:** Address C1, C2, and C3 before proceeding to implementation. Update social platform preset specs (M1-M4). Add GIF/image sequence export or explicitly exclude it. Resolve ClipManager vs TimelineManager migration question (I7).

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06
**Review Scope:** Implementation viability cross-referenced against live codebase; resolution of R1 critical issues; integration risk with parallel design tracks (Video Effects, Color Grading, Timeline V2)

### Codebase Verification Results

**Files examined for this review:**
- `lib/views/export/export_sheet.dart` (1464 lines) -- full read
- `ios/Runner/VideoProcessingService.swift` (912 lines) -- full read
- `ios/Runner/VideoTransformCalculator.swift` (207 lines) -- full read
- `ios/Runner/VideoConstants.swift` (84 lines) -- full read
- `ios/Runner/AppDelegate.swift` (lines 160-280) -- method channel registrations
- `lib/core/timeline_manager.dart` (449 lines) -- full read
- `lib/core/clip_manager.dart` (first 80 lines) -- legacy system
- `lib/models/clips/timeline_item.dart` (full) -- V2 base class
- `lib/models/clips/video_clip.dart` (first 80 lines) -- V2 video clip with `mediaAssetId`
- `lib/models/media_asset.dart` (first 120 lines) -- MediaAsset + MediaAssetRegistry
- `lib/core/auto_reframe_engine.dart` (first 60 lines) -- smart crop interface
- `docs/plans/2026-02-06-video-effects-system-design.md` -- CIFilter export integration
- `docs/plans/2026-02-06-color-grading-filters-design.md` -- color pipeline export integration

#### Verification 1: Export Sheet to Native Channel Integrity

**Status: VERIFIED with discrepancies noted**

The export sheet's `_startExport()` calls `renderComposition` on `MethodChannel('com.liquideditor/video_processing')` (line 1329). AppDelegate registers this at line 220 and forwards to `VideoProcessingService.renderComposition()` at line 235. Parameters match: `videoPath`, `clips`, `width`, `height`, `fps`, `bitrateMbps`, `audioOnly`, `enableHdr`. The pipeline is end-to-end functional for the current single-source architecture.

**Discrepancy:** The export sheet creates a `MethodChannel` instance locally (`const platform = MethodChannel(...)` at line 1329), which is valid but unusual. Most Flutter code would share a singleton channel. This works because `MethodChannel` is just a name wrapper with no state, but it means any future middleware (interceptors, logging) must be added in multiple places.

#### Verification 2: Event Sink Architecture

**Status: VERIFIED -- confirms R1-I6 concern is severe**

AppDelegate conforms to `EventSinkProvider` (line 17) and holds a single `var eventSink: FlutterEventSink?` (line 40). The `FlutterEventChannel` `onListen` sets this single sink (line 330-331), and `onCancel` nils it (line 336). `VideoProcessingService` holds a `weak var eventSinkProvider: EventSinkProvider?` (line 19) and calls `self?.eventSinkProvider?.eventSink?(Double(exportSession.progress))` (lines 315, 535).

**Critical finding:** There is exactly one event sink for the entire app. The Flutter `EventChannel.receiveBroadcastStream()` creates a listener that sets the sink on the native side. If you call `receiveBroadcastStream()` again (e.g., for a second export in a batch), the old sink is replaced. This means:

1. **Batch export multiplexing via exportId will NOT work** with the current single-sink architecture. The design proposes sending `Map` events with `exportId` routing, but if two batch jobs try to listen simultaneously, they will fight over the single sink.
2. **The proposed migration from `Double` to `Map` events is viable** for single sequential exports but requires a separate channel or a fundamentally different architecture for parallel batch exports.

**Recommendation:** Use a single multiplexed event channel (send all events through one channel with `exportId` for routing) but ensure the Flutter side has a single listener that demultiplexes to per-export `StreamController`s. Do NOT create multiple `EventChannel.receiveBroadcastStream()` subscriptions. The design document should explicitly specify this demux architecture.

#### Verification 3: ClipManager vs TimelineManager State

**Status: CONFIRMED -- two parallel systems exist**

The `export_sheet.dart` constructor takes `ClipManager clipManager` (line 140) and `String sourceVideoPath` (line 141). It uses `widget.clipManager.clips` (line 1114), `clip.surroundingKeyframes()` (line 1131), and `widget.clipManager.getTransformAtTimelinePosition()` (line 428). This is the legacy V1 system.

Meanwhile, `TimelineManager` (in `lib/core/timeline_manager.dart`) wraps `PersistentTimeline` with immutable `TimelineItem` types. `VideoClip` (V2) has `mediaAssetId` instead of direct file paths, and keyframes are stored as `List<Keyframe>` on the clip itself.

**The two systems are structurally incompatible:**

| Aspect | ClipManager (V1) | TimelineManager (V2) |
|--------|------------------|----------------------|
| Clip model | `TimelineClip` (mutable) | `VideoClip` (immutable, `@immutable`) |
| Source reference | `sourceVideoPath` (global) | `mediaAssetId` per clip |
| Keyframe access | `clip.surroundingKeyframes(duration)` | `clip.keyframes` (sorted list) |
| Mutation | Direct mutation + command pattern | Immutable update via `PersistentTimeline` |
| Timeline query | Linear scan | O(log n) tree traversal |

**The export pipeline must be designed for V2.** Designing against V1 means a full rewrite when V2 integration happens (which the Timeline V2 design marks as a high-priority migration). The `_buildClipsPayload()` method must be reimplemented to:
1. Iterate `TimelineManager.items` instead of `ClipManager.clips`
2. Resolve `mediaAssetId` to file path via `MediaAssetRegistry.getById(id).relativePath`
3. Handle mixed clip types (VideoClip, ImageClip, AudioClip, GapClip, ColorClip, TextClip) -- not just video
4. Build per-source-file AVAsset instances instead of assuming a single `videoPath`

#### Verification 4: Auto-Reframe Interface for Smart Crop

**Status: INTERFACE EXISTS but no focal point export path**

`AutoReframeEngine` (in `lib/core/auto_reframe_engine.dart`) takes `AutoReframeConfig` with `targetAspectRatio` and `framingStyle`, and outputs `List<Keyframe>` with scale/translate/rotate transforms. These keyframes represent camera motion, not focal points.

**Integration gap:** The design's `SmartCrop` strategy in `AutoCropConfig` says "the focal point is derived from person tracking data at each frame." But `AutoReframeEngine` does not expose per-frame focal points -- it exposes finished keyframes. To feed smart crop into the export pipeline, one of:
- (A) The auto-reframe engine must expose raw focal point data (not just transforms)
- (B) The smart crop can reuse the auto-reframe keyframes directly as the crop transform (which is what they already do)

Option B is actually the correct interpretation: smart crop IS auto-reframe applied during export. The design should clarify that `CropStrategy.smartCrop` simply invokes `AutoReframeEngine.generateKeyframes()` with the target aspect ratio and feeds the results into the existing keyframe-based export pipeline. No separate focal point channel is needed.

### Integration Risk Assessment

#### Risk 1: CIFilter Effects Pipeline Collision (CRITICAL)

The Video Effects System design (`2026-02-06-video-effects-system-design.md`) specifies that export rendering will use `AVAssetWriter` with `AVAssetWriterInputPixelBufferAdaptor` for per-frame CIFilter application. The Color Grading design (`2026-02-06-color-grading-filters-design.md`) similarly specifies CIFilter chains applied during export.

The Export & Sharing design proposes continuing with `AVAssetExportSession` for Phases 1-2 and migrating to `AVAssetWriter` in Phases 3-4. However, the effects pipeline assumes `AVAssetWriter` from the start.

**Conflict matrix:**

| Feature | Required Pipeline | When |
|---------|------------------|------|
| Export (Phase 1-2) | AVAssetExportSession | Weeks 1-4 |
| Export (Phase 3-4) | AVAssetWriter | Weeks 5-9 |
| Subtitle burn-in | AVVideoCompositionCoreAnimationTool (requires AVAssetExportSession) | Phase 4 |
| CIFilter effects | AVVideoComposition with customVideoCompositorClass OR AVAssetWriter | Soon after export |
| Color grading | CIFilter chain via AVVideoComposition OR AVAssetWriter | Soon after export |

**The subtitle burn-in approach is incompatible with the effects pipeline.** `AVVideoCompositionCoreAnimationTool` composites CALayers AFTER the video compositor runs. But the effects pipeline uses a `customVideoCompositorClass` on `AVVideoComposition`, which replaces the default compositor. You cannot use both `customVideoCompositorClass` AND `AVVideoCompositionCoreAnimationTool` simultaneously -- the custom compositor must manually handle the CALayer compositing.

**Resolution:** The subtitle renderer must be folded into the custom video compositor. Instead of CATextLayer + CAAnimation, render subtitles as part of the per-frame CIFilter chain: create a `CIImage` from rendered text (via `UIGraphicsImageRenderer` -> `CIImage`) and composite it with `CISourceOverCompositing`. This approach works with both `AVAssetExportSession` (via customVideoCompositorClass) and `AVAssetWriter`.

#### Risk 2: Multi-Source Export Architecture (CRITICAL -- addresses R1-C3)

**Root cause analysis:** The current `renderComposition()` in `VideoProcessingService.swift` (line 335) takes a single `videoPath` and creates a single `AVAsset` (line 347). All clips in the composition are segments of this single asset. The V2 `VideoClip` model has `mediaAssetId` referencing potentially different source files per clip.

**Required architectural change:**

```
Current (single-source):
  Flutter sends: { videoPath: "single.mp4", clips: [...] }
  Swift creates: 1 AVAsset, inserts segments from it

Required (multi-source):
  Flutter sends: { assets: [{id, path}, ...], clips: [{assetId, ...}, ...] }
  Swift creates: Map<String, AVAsset>, one per unique source
  For each clip: lookup source AVAsset by assetId, insert segment
```

This is a fundamental protocol change. The `renderComposition` method signature must change from `videoPath: String` to `assets: [[String: String]]` (or the timeline items must embed their resolved file paths). The composition builder must create separate `AVAsset` instances per unique source and manage multiple video tracks or insert time ranges from different source tracks into the composition track.

**Key subtlety:** When mixing clips from different source videos with different resolutions, frame rates, or orientations, each clip needs its own `VideoTransformCalculator` instance (since natural size and preferred transform differ per source). The current code creates one calculator per export call. Multi-source requires one per unique source.

**Estimated effort to resolve:** This is a 2-3 day refactor of `VideoProcessingService.renderComposition()` and the export sheet's `_buildClipsPayload()`. It should be done in Phase 1, not deferred, because every subsequent feature builds on the composition pipeline.

#### Risk 3: Background Export Resume (CRITICAL -- addresses R1-C1)

R1 correctly identified that `AVAssetWriter` cannot resume by reopening a partially written file. The design's `resumeExport()` method is architecturally impossible.

**Viable alternatives (ranked by feasibility):**

1. **Segment-based export with concatenation (Recommended)**
   - Render the composition in segments (e.g., 30-second chunks)
   - Each segment is a complete, valid video file
   - On background timeout: finalize current segment, store segment list
   - On resume: continue from next segment
   - On completion: concatenate all segments via `AVMutableComposition` (fast, no re-encoding)
   - **Drawback:** Segment boundaries may have minor audio glitches if not aligned to keyframes; cross-segment encoding settings must be identical

2. **Progress checkpoint with re-render**
   - Track last successfully rendered frame timestamp
   - On resume: re-create `AVAssetWriter`, set composition time range to start from checkpoint
   - Export only the remaining portion
   - Concatenate partial files at the end
   - **Drawback:** Essentially the same as option 1 but less clean

3. **Foreground-only with better UX**
   - Accept that background export beyond 30s is not reliable on iOS
   - Show clear messaging: "Keep the app open during export"
   - Use Picture-in-Picture or audio session to extend background time
   - **Drawback:** Poor UX for long exports; PiP requires video playback, audio session trick may violate App Store guidelines

**Recommendation:** Option 1 (segment-based). Segment duration should be configurable (default 30s). The concatenation step uses `AVMutableComposition` with `insertTimeRange` which is nearly instantaneous (no re-encoding). The design should specify the segment file naming convention (`export_{id}_seg_{index}.mp4`) and the metadata file format that tracks segment completion state.

#### Risk 4: Non-Video Clip Types in Export (IMPORTANT)

The V2 timeline supports six clip types: `VideoClip`, `ImageClip`, `AudioClip`, `GapClip`, `ColorClip`, `TextClip`. The export design only addresses `VideoClip`. The export pipeline must handle:

- **GapClip:** Render black frames (or configurable background color) for the gap duration. Currently gaps are implicit (no video data) and AVFoundation will render black automatically when no time range covers a region.
- **ColorClip:** Render solid color frames for the duration. Requires `AVAssetWriter` with a synthetic pixel buffer (or a pre-generated solid-color video asset inserted into the composition).
- **TextClip:** Render text overlay. Could use the subtitle burn-in system but with different styling rules. Must be addressed in Phase 4 at minimum.
- **ImageClip:** Render a still image for the configured duration. Can use `AVAssetWriter` to write the same frame repeatedly, or create a synthetic video from the image and insert it into the composition.
- **AudioClip:** Mix audio-only clips into the composition's audio track. `AVMutableComposition` supports this natively.

**Impact:** GapClip is handled automatically by AVFoundation (empty time = black). ColorClip and ImageClip require synthetic video generation, which is only practical with `AVAssetWriter` (not `AVAssetExportSession`). This means the `AVAssetWriter` migration may need to happen earlier than Phase 3-4 if the V2 timeline is integrated first.

### Critical Findings

**CF-1: Three Pipeline Designs Are Converging on Incompatible Assumptions**

The Export design, Video Effects design, and Color Grading design all propose different export pipeline architectures:

| Design | Pipeline | Compositor |
|--------|----------|-----------|
| Export (Phase 1-2) | `AVAssetExportSession` | Default + `AVVideoCompositionLayerInstruction` |
| Export (Phase 4 subtitles) | `AVAssetExportSession` + `AVVideoCompositionCoreAnimationTool` | CALayer overlay |
| Video Effects | `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor` | Custom per-frame CIFilter |
| Color Grading | `AVVideoComposition` with `customVideoCompositorClass` | CIFilter chain |

These cannot all coexist. A unified export pipeline must be designed BEFORE any of these three designs are implemented. The pipeline must:
1. Support transform keyframes (existing)
2. Support CIFilter effect chains (Video Effects + Color Grading)
3. Support text overlay compositing (Subtitles + TextClip)
4. Support multi-source composition (Timeline V2)
5. Support background pause/resume (Background Export)

**Recommendation:** Create a unified `ExportPipeline` protocol and implementation document that all three design docs reference. The implementation should use `AVVideoComposition` with a `customVideoCompositorClass` that handles transforms, CIFilter chains, AND text rendering in a single per-frame pass. This works with both `AVAssetExportSession` (for Phase 1-2) and `AVAssetWriter` (for Phase 3+). The `AVVideoCompositionCoreAnimationTool` approach for subtitles must be abandoned in favor of in-compositor text rendering.

**CF-2: Subtitle Timing Bug Confirmed and Expanded**

R1 flagged the `CAAnimation.beginTime` issue (R1-C2). After deeper analysis:

The issue is that `AVVideoCompositionCoreAnimationTool` expects `CAAnimation.beginTime` relative to `AVCoreAnimationBeginTimeAtZero` (which is `1e-100`, effectively 0 but not literally 0). However, the deeper problem is that the entire `CAAnimation`-based approach is incompatible with the custom video compositor required by the effects pipeline (see CF-1 above).

**Even if the `beginTime` is fixed**, this approach will break when CIFilter effects are added. The fix is to abandon `CAAnimation`-based subtitle timing entirely and render subtitles as `CIImage` composites within the custom video compositor. Subtitle visibility is determined by comparing the current frame time against each subtitle's start/end time, not by CAAnimation timing.

**CF-3: Export Sheet Must Be Redesigned for V2 Timeline Before Any Feature Work**

The current `export_sheet.dart` is tightly coupled to V1 `ClipManager`:
- Constructor takes `ClipManager` and `String sourceVideoPath` (lines 139-141)
- `_buildClipsPayload()` iterates `widget.clipManager.clips` (line 1114)
- `_buildPreviewTransform()` calls `widget.clipManager.sourceToTimeline()` (line 490) and `widget.clipManager.getTransformAtTimelinePosition()` (line 497)
- Export invocation sends `widget.sourceVideoPath` as the single video path (line 1309)

Before any new export features are implemented, the export sheet must be refactored to:
1. Accept `TimelineManager` instead of `ClipManager`
2. Accept `MediaAssetRegistry` instead of `String sourceVideoPath`
3. Build clip payload from `TimelineManager.items` resolving `mediaAssetId` via registry
4. Handle non-video clip types (gap, color, image, text) appropriately
5. Support multi-source timelines (multiple video paths)

This refactor is a prerequisite for ALL Phase 1-4 features. Without it, every feature will be built on the wrong foundation and require rewriting.

### Important Findings

**IF-1: Batch Export Memory Budget Is Confirmed Insufficient**

R1 flagged this (R1-I3). Verifying against the codebase: `VideoProcessingService.renderComposition()` creates an `AVAssetExportSession` (line 516) with a `AVMutableVideoComposition` that holds the entire instruction set in memory (line 496-499). For a 4K export, the video composition's render buffers alone consume ~32MB per frame (3840x2160 BGRA at 4 bytes/pixel = 33MB), with up to 4 frames in flight during encoding.

Two parallel 4K exports: 2 x (33MB x 4 + 50MB composition overhead) = ~364MB just for frame buffers, plus the composition objects, plus Flutter's widget tree (~30MB), plus any preview frame extraction. Total easily exceeds 600MB.

**Resolution:** Parallel batch export must be restricted to max 1080p per job. For 4K, batch must always be sequential. The `BatchStrategy.parallel` option should validate maximum resolution per job and auto-downgrade to sequential if any job exceeds 1080p. The memory budget table in Section 17.2 should add:

| Configuration | Memory Budget |
|--------------|---------------|
| Single export (1080p) | < 250MB |
| Single export (4K) | < 400MB |
| Parallel batch (2x 1080p) | < 500MB |
| Parallel batch (1x 4K + 1x any) | NOT ALLOWED, auto-sequential |

**IF-2: GIF/Image Sequence Export Specification**

R1 flagged this as missing (R1-M5). Here is a specification that can be added:

**GIF Export:**
- Use `AVAssetImageGenerator` to extract frames at the target frame rate (10-15 fps typical for GIF)
- Convert each `CGImage` to GIF frame using `CGImageDestination` with `kCGImagePropertyGIFDictionary`
- Set `kCGImagePropertyGIFDelayTime` per frame based on target FPS
- Max resolution: 480px (longest edge) to keep file size reasonable
- Color quantization: iOS `vImage` histogram + median cut algorithm (or accept ImageIO's built-in dithering)
- Max duration: 30 seconds (GIFs over 30s become very large)
- Output: `.gif` file, saved to Photos or shared

**Image Sequence Export:**
- Use `AVAssetImageGenerator` (same as frame grab but at every frame or every Nth frame)
- Output formats: PNG or JPEG
- Naming convention: `frame_0001.png`, `frame_0002.png`, etc.
- Package as ZIP file for sharing
- Use case: VFX compositing workflows, stop-motion review

**Method channel:** `exportGif` (videoPath, clips, maxWidth, fps, startMs, durationMs) -> file path
**Method channel:** `exportImageSequence` (videoPath, clips, format, quality, fps) -> ZIP file path

**IF-3: Social Platform Specs Need Real-Time Validation**

R1 noted outdated specs (R1-M1 through M4). Rather than hardcoding specs that change frequently, the design should:

1. Store presets in a JSON configuration file (bundled with the app) rather than Dart constants
2. Support remote preset updates via a lightweight JSON endpoint (optional, can be deferred)
3. Add a `lastVerified` timestamp to each preset
4. At minimum, update to current-as-of-February-2026 specs:

| Platform | Max Duration | Max File Size | Max Resolution | Notes |
|----------|-------------|---------------|----------------|-------|
| Instagram Reels | 15 minutes | 250MB (mobile upload) | 1080x1920 | Expanded to 15 min in late 2025 |
| Instagram Story | 60 seconds | 250MB | 1080x1920 | Segmented into 15s parts |
| TikTok | 10 minutes | 287MB (mobile) | 1080x1920 | Up to 60 min via desktop |
| YouTube Shorts | 3 minutes | 250MB | 1080x1920 | Expanded in 2025 |
| YouTube Long | 12 hours | 256GB | 8K (7680x4320) | Verified accounts |
| X (Twitter) | 2:20 (regular), 8:00 (Premium) | 512MB (regular), 8GB (Premium) | 1920x1200 | Tier-dependent |
| Facebook Feed | 240 minutes | 10GB | 4K | Verified from Meta docs |

Note: These specs change frequently. The values above should be verified against current platform documentation before implementation.

**IF-4: AVAssetExportSession Cannot Provide Frame-Level Progress**

The design's `ExportProgressReporter` (Section 13.2) proposes reporting `framesRendered` and `totalFrames`. However, `AVAssetExportSession.progress` is a `Float` (0.0-1.0) that does not expose frame counts. The session manages its own internal frame pipeline and only reports aggregate progress.

To get frame-level progress, `AVAssetWriter` is required (you control the frame loop and can count each appended sample buffer). This means the enhanced progress reporting in Phase 1 can only provide:
- `progress`: from `exportSession.progress` (existing)
- `phase`: inferred from progress ranges (0-5% = preparing, 5-95% = rendering, 95-100% = finalizing)
- `framesRendered`: estimated from `progress * totalFrames` (not actual)
- `totalFrames`: calculated from `duration * fps` (accurate)
- `bytesWritten`: not available from `AVAssetExportSession`

**True frame-level progress requires the AVAssetWriter migration (Phase 3-4).** Phase 1 should document this limitation and use estimated values with a note in the UI: "Estimated progress."

**IF-5: Export Cancellation Race Condition**

The design adds `cancelExport()` (Section 15.3) which calls `currentExportSession?.cancelExport()`. However, the current `VideoProcessingService` does not store the export session reference (it is a local variable inside `renderComposition()`). The design correctly proposes adding `private var currentExportSession: AVAssetExportSession?` as an instance property, but there is a race condition: if `cancelExport()` is called between session creation and `exportAsynchronously`, the session may not be set yet.

**Resolution:** Store the session reference immediately after creation (before calling `exportAsynchronously`), and use a serial `DispatchQueue` for all export operations to prevent concurrent access to `currentExportSession`.

### Action Items for Review 3

**Must-fix before implementation (Critical):**

1. **[CF-1] Create a unified export pipeline design** that reconciles the Export, Video Effects, and Color Grading pipeline requirements. All three designs must reference a single `ExportPipeline` protocol. The custom video compositor approach is the only architecture that satisfies all requirements.

2. **[CF-3] Add a prerequisite Phase 0** for migrating `export_sheet.dart` from ClipManager/sourceVideoPath to TimelineManager/MediaAssetRegistry. This is a blocking dependency for all 12 features.

3. **[CF-2] Replace CAAnimation-based subtitle rendering** with in-compositor CIImage text rendering. Remove all references to `AVVideoCompositionCoreAnimationTool` from the subtitle design.

4. **[Risk 2] Redesign `renderComposition` protocol** for multi-source timelines. The method channel payload must include a list of asset entries (`[{id, path}]`) and clips must reference assets by ID.

5. **[Risk 3] Replace background export resume mechanism** with segment-based export + concatenation approach. Specify segment duration, file naming, metadata file format, and concatenation procedure.

**Should-fix before implementation (Important):**

6. **[IF-1] Add resolution guard to parallel batch export** -- auto-downgrade to sequential if any job exceeds 1080p.

7. **[IF-2] Add GIF export and image sequence export** to the feature list (Section 5 or new section), or explicitly add to "Out of Scope" table.

8. **[IF-3] Update social platform preset specs** to February 2026 values. Consider JSON-based preset storage for future updateability.

9. **[IF-4] Clarify Phase 1 progress limitations** -- frame-level progress is estimated, not actual. `bytesWritten` is not available until AVAssetWriter migration.

10. **[IF-5] Address export cancellation race condition** with serial dispatch queue and immediate session reference storage.

11. **[Verification 2] Specify event channel demultiplexing architecture** for batch exports -- single listener with per-export StreamController demux.

12. **[Risk 4] Document non-video clip export handling** -- specify how GapClip, ColorClip, ImageClip, TextClip, and AudioClip are rendered during export. Note which clip types require AVAssetWriter.

**Verify in Review 3 (Final readiness):**

13. Confirm unified export pipeline protocol is specified
14. Confirm Phase 0 (V2 migration) timeline estimate
15. Confirm all three pipeline design docs (Export, Effects, Color Grading) reference the same pipeline protocol
16. Confirm GIF/image sequence is either specified or explicitly out of scope
17. Verify test plan covers multi-source export, non-video clips, segment-based background export
18. Verify performance budget accounts for custom video compositor overhead (per-frame CIFilter rendering is slower than AVAssetExportSession's optimized pipeline)

### Checklist Summary

| Check | Status | Notes |
|-------|--------|-------|
| Export pipeline assumptions verified | PARTIAL | Single-source architecture confirmed; multi-source not addressed |
| AVAssetWriter resume (R1-C1) | RESOLVED | Segment-based approach proposed (Risk 3) |
| Multi-source pipeline (R1-C3) | RESOLUTION PROPOSED | Per-asset AVAsset map architecture specified (Risk 2) |
| Subtitle timing (R1-C2) | RESOLVED/SUPERSEDED | CAAnimation approach must be abandoned entirely (CF-2) |
| Batch export memory (R1-I3) | CONFIRMED + RESOLVED | 4K parallel prohibited; resolution guard specified (IF-1) |
| GIF/Image Sequence (R1-M5) | SPECIFIED | Full specification provided (IF-2) |
| Social platform specs (R1-M1-M4) | UPDATED | February 2026 values provided (IF-3) |
| Effects pipeline integration | CRITICAL NEW FINDING | Three designs converge on incompatible pipelines (CF-1) |
| V1-to-V2 migration | CRITICAL NEW FINDING | Export sheet must be migrated before features (CF-3) |
| Non-video clip types | IMPORTANT NEW FINDING | ColorClip/ImageClip require AVAssetWriter (Risk 4) |
| Event channel architecture | IMPORTANT | Demux architecture needed for batch (Verification 2) |

**Overall Implementation Readiness: NOT READY**

The design is architecturally strong in isolation but has critical integration conflicts with two parallel design tracks (Video Effects and Color Grading). A unified export pipeline protocol must be established before any of the three designs proceed to implementation. Additionally, the V1-to-V2 migration of the export sheet is a blocking prerequisite that is not accounted for in any phase timeline.

**Recommendation:** Add a Phase 0 (1 week) for V2 migration + unified pipeline protocol design. Defer subtitle burn-in to after the unified pipeline is established. Proceed with Phase 1 features (Progress, Frame Grab, Preview) only after the export sheet accepts `TimelineManager` + `MediaAssetRegistry`.

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06
**Review Scope:** Final readiness assessment, critical issue resolution verification, risk register, implementation ordering, Phase 0 scope definition

### 1. Critical Issues Status

Six critical issues were identified across R1 and R2. Below is the final resolution status for each.

| ID | Issue | Source | Resolution Status | Final Verdict |
|----|-------|--------|-------------------|---------------|
| C1 (R1) | AVAssetWriter resume after background suspension is impossible | R1 | R2 proposed segment-based export + concatenation (Risk 3, Option 1) | **RESOLVED.** Segment-based approach is viable. See Section 3.5 below for remaining specification gaps. |
| C2 (R1) | Subtitle burn-in CAAnimation.beginTime requires AVCoreAnimationBeginTimeAtZero offset | R1 | R2 superseded: entire CAAnimation approach abandoned (CF-2) | **RESOLVED/SUPERSEDED.** CIImage composite approach replaces CAAnimation. See Section 3.4 below. |
| C3 (R1) | Single-source video assumption conflicts with V2 multi-source architecture | R1 | R2 proposed per-asset AVAsset map (Risk 2) with multi-videoPath protocol | **RESOLUTION PATH EXISTS.** CompositionBuilder.swift already supports multi-source via `assetPath` per segment. See Section 3.3. |
| CF-1 (R2) | Three pipeline designs converge on incompatible assumptions (Export vs Effects vs Color Grading) | R2 | R2 proposed unified ExportPipeline protocol with single customVideoCompositorClass | **RESOLUTION PATH EXISTS but needs Phase 0 specification.** See Section 3.2. |
| CF-2 (R2) | CAAnimation subtitle approach incompatible with custom video compositor | R2 | R2 proposed CIImage composite within custom compositor | **RESOLVED.** CIImage text rendering via UIGraphicsImageRenderer is the correct approach. |
| CF-3 (R2) | Export sheet tightly coupled to V1 ClipManager/sourceVideoPath | R2 | R2 proposed Phase 0 migration to TimelineManager/MediaAssetRegistry | **RESOLUTION PATH EXISTS.** Phase 0 scope defined below in Section 3.8. |

**Assessment:** All six critical issues have identified resolution paths. None remain unresolved. However, three resolutions (C3, CF-1, CF-3) require Phase 0 implementation work before any feature development can begin. The resolutions are conceptually sound but unimplemented.

### 2. Unified Pipeline Viability Assessment

R2 identified that three design documents propose incompatible export pipeline architectures:

- **Export design:** AVAssetExportSession with standard AVMutableVideoCompositionLayerInstruction transforms
- **Video Effects design:** AVAssetWriter with per-frame CIFilter via AVAssetWriterInputPixelBufferAdaptor
- **Color Grading design:** AVVideoComposition with customVideoCompositorClass

**The unified pipeline protocol approach is viable**, but requires a critical clarification. After examining the codebase:

**Key finding: `CompositionBuilder.swift` already exists at `ios/Runner/Timeline/CompositionBuilder.swift` (R1 said it did not exist).** This file:
- Supports multi-source segments with per-segment `assetPath` and `assetId` (line 30-31)
- Handles video, audio, image, gap, color, silence, and offline segment types (lines 17-25)
- Builds `AVMutableComposition` with `AVMutableVideoComposition` (lines 366-390)
- Has an asset cache with thread-safe locking (lines 83-86)
- Currently uses identity transform and default compositor (line 384: `layerInstruction.setTransform(.identity, at: .zero)`)
- Does NOT set `customVideoCompositorClass` (line 372-390)

**This is the correct foundation for the unified pipeline.** The `CompositionBuilder` should be extended, not replaced. The unified pipeline architecture is:

```
Phase 0-2: CompositionBuilder builds AVMutableComposition
            + AVMutableVideoComposition with standard compositor
            + AVAssetExportSession renders output
            (No CIFilter, no custom compositor yet)

Phase 3+:  CompositionBuilder builds AVMutableComposition
            + AVMutableVideoComposition with customVideoCompositorClass
            + Custom compositor handles: transforms, CIFilter effects,
              color grading, subtitle rendering (all in one per-frame pass)
            + AVAssetExportSession OR AVAssetWriter renders output
```

The protocol interface R2 proposed is correct:

```swift
protocol ExportPipeline {
    func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition?,
        outputURL: URL,
        config: ExportConfig
    ) async throws -> URL
}
```

Both `ExportSessionPipeline` and `AssetWriterPipeline` conform to this protocol. `CompositionBuilder` produces the `BuiltComposition` struct (which already contains `composition`, `videoComposition`, `audioMix`, `renderSize`), and the pipeline consumes it. This separation is clean and already partially implemented.

**Verdict: VIABLE.** The CompositionBuilder already handles the composition-building side. The pipeline protocol adds the rendering side. The custom compositor is additive (Phase 3+) and does not break the Phase 0-2 approach.

### 3. Per-Issue Deep Analysis

#### 3.1 R1 Important Issues Resolution

| ID | Issue | Resolution |
|----|-------|------------|
| I1 | AirDrop filtering uses non-existent `.allCases` | Remove filtering code. Use standard UIActivityViewController. AirDrop is a built-in activity type and will appear automatically. |
| I2 | MP3 in AudioFormat enum but recommended to drop | Remove `mp3` from the `AudioFormat` enum. The design correctly recommends dropping it. AAC covers the compressed use case. |
| I3 | Batch parallel 4K memory exceeds budget | Resolved by R2-IF-1: auto-downgrade to sequential if any job exceeds 1080p. |
| I4 | UserDefaults risky for large queue payloads | Use JSON file in Caches directory. Remove UserDefaults option. |
| I5 | ZIP implementation missing for project bundles | Use `ZIPFoundation` Swift Package (https://github.com/weichsel/ZIPFoundation). It is MIT-licensed, well-maintained, and handles directory-level ZIP operations. |
| I6 | Event channel breaking change needs migration | R2 proposed v2 channel. Correct approach: add `com.liquideditor/video_processing/progress_v2` for structured events, keep old channel during migration. |
| I7 | ClipManager-to-TimelineManager migration | Addressed by Phase 0 (see Section 3.8). |

#### 3.2 Unified Pipeline Protocol Specification Gaps

The `ExportPipeline` protocol proposed in R2 is correct in shape but missing:

1. **Progress reporting mechanism.** The protocol should include a progress callback or delegate. Proposed addition:
   ```swift
   protocol ExportPipelineDelegate: AnyObject {
       func pipeline(_ pipeline: ExportPipeline, didUpdateProgress progress: ExportProgressEvent)
       func pipeline(_ pipeline: ExportPipeline, didEncounterWarning warning: ExportWarning)
   }
   ```

2. **Cancellation token.** The protocol needs a cancellation mechanism:
   ```swift
   protocol ExportPipeline {
       func export(..., cancellationToken: ExportCancellationToken) async throws -> URL
   }
   ```

3. **Configuration for compositor selection.** Phase 0-2 uses the default compositor; Phase 3+ uses the custom compositor. The `ExportConfig` must include a flag or the pipeline must auto-detect based on whether effects/color grading/subtitles are present.

4. **BuiltComposition as input.** The protocol should accept `BuiltComposition` (from `CompositionBuilder`) rather than raw `AVMutableComposition` + `AVMutableVideoComposition`. This ensures the builder and pipeline stay in sync.

**These gaps do not block Phase 0 but must be specified before Phase 1 implementation begins.**

#### 3.3 V2 Migration and Multi-Source Export

R2 proposed redesigning `renderComposition` to accept `assets: [[String: String]]` and resolve per-clip. After examining the codebase:

**The migration path is shorter than R2 estimated.** `CompositionBuilder.swift` already accepts per-segment `assetPath` and `assetId` (lines 30-31, 39-50). It already creates per-asset `AVURLAsset` instances via `getOrCreateAsset(path:)` with caching (lines 394-409). The multi-source composition building is functionally implemented for playback.

**The gap is between the playback pipeline and the export pipeline:**
- **Playback** uses `CompositionBuilder` -> `BuiltComposition` -> `AVPlayer` (via `CompositionPlayerService`)
- **Export** uses `VideoProcessingService.renderComposition()` which builds its own `AVMutableComposition` inline with a single `videoPath`

**Phase 0 resolution:** The export pipeline should be refactored to:
1. Accept `[CompositionSegment]` (same format as the playback path) instead of `[clipData]` with a single `videoPath`
2. Use `CompositionBuilder.build()` to create the `BuiltComposition`
3. Feed the `BuiltComposition` into `AVAssetExportSession` for rendering

This unifies the playback and export composition paths, eliminating the dual-pipeline divergence. The export-specific parameters (resolution, FPS, bitrate, HDR) are applied to the `AVAssetExportSession`/`AVAssetWriter`, not to the composition itself.

**Estimated effort: 2-3 days** (aligns with R2's estimate). The composition building code already exists; the work is plumbing it through the export path and updating the Flutter-side payload generation.

#### 3.4 Subtitle Rendering: CIImage Composite Approach

R2 correctly mandated abandoning CAAnimation-based subtitles. The CIImage composite approach is:

```swift
// Within the unified custom video compositor (Phase 3+):
func renderSubtitleOverlay(text: String, style: SubtitleStyle, frameSize: CGSize) -> CIImage {
    let renderer = UIGraphicsImageRenderer(size: frameSize)
    let uiImage = renderer.image { ctx in
        // Draw text with style (font, color, outline, background)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = style.alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: style.fontSize * (frameSize.height / 1080.0)),
            .foregroundColor: style.textColor,
            .paragraphStyle: paragraphStyle,
        ]
        // Draw at calculated position
        text.draw(in: textRect, withAttributes: attributes)
    }
    return CIImage(image: uiImage)!
}

// Composite over video frame:
let subtitleImage = renderSubtitleOverlay(text: subtitle.text, style: subtitle.style, frameSize: renderSize)
let composited = subtitleImage.composited(over: videoFrame)
```

**Viability assessment: CONFIRMED VIABLE.** `UIGraphicsImageRenderer` to `CIImage` to `CISourceOverCompositing` is a well-documented pattern. Performance concern: `UIGraphicsImageRenderer` runs on CPU. For 30fps 1080p export, the text rendering must complete in under 33ms per frame. Text rendering is typically sub-millisecond for single-line subtitles. For complex multi-line styled text, caching the rendered `CIImage` for frames where the subtitle text does not change eliminates repeated rendering.

**Optimization: cache the rendered CIImage per subtitle entry.** Since a subtitle spans many frames with identical text, render once and reuse the CIImage for all frames within that subtitle's time range. Cache invalidation occurs only at subtitle boundaries.

**This approach works for both Phase 0-2 (via AVAssetExportSession with customVideoCompositorClass) and Phase 3+ (via AVAssetWriter).** However, subtitles should be deferred to Phase 4 as planned, since they require the custom compositor infrastructure from Phase 3.

#### 3.5 Background Export: Segment-Based Approach

R2 proposed segment-based export with concatenation (Risk 3, Option 1). Remaining specification gaps:

**Segment file naming:** `export_{exportId}_seg_{index:04d}.mp4` (zero-padded 4-digit index)

**Segment metadata file:** `export_{exportId}_meta.json`
```json
{
  "exportId": "uuid",
  "totalSegments": 12,
  "completedSegments": 7,
  "segmentDurationMs": 30000,
  "lastCompletedTimestamp": "2026-02-06T12:34:56Z",
  "config": { /* full ExportConfig snapshot */ },
  "segments": [
    { "index": 0, "path": "export_uuid_seg_0000.mp4", "status": "completed", "durationMs": 30000 },
    { "index": 1, "path": "export_uuid_seg_0001.mp4", "status": "completed", "durationMs": 30000 },
    /* ... */
    { "index": 7, "path": "export_uuid_seg_0007.mp4", "status": "pending" }
  ]
}
```

**Concatenation procedure:** Use `AVMutableComposition.insertTimeRange` for each completed segment file. This is lossless (no re-encoding) when all segments have identical encoding settings (codec, sample rate, timescale).

**Realistic assessment:** Segment-based export is significantly more complex than the current single-pass approach. It requires:
1. Splitting the timeline into segment time ranges
2. Building a separate `AVAssetExportSession` per segment (or reusing an `AVAssetWriter` that is finalized per segment)
3. Ensuring keyframe alignment at segment boundaries to avoid visual glitches
4. Handling audio continuity across segments (audio codecs like AAC use overlapping frames)
5. Concatenating without re-encoding

**Risk: AAC audio frame boundary glitches.** AAC uses 1024-sample frames (~23ms at 44.1kHz). If a segment boundary falls mid-frame, the concatenated output will have a pop/click at the boundary. Mitigation: align segment boundaries to audio frame boundaries (round segment duration to nearest 1024-sample boundary).

**Verdict: VIABLE but complex. Phase 3 timeline estimate (3 weeks total for Background + Queue + Batch) may be tight.** Recommend budgeting 4 weeks for Phase 3 if segment-based background export is included. Alternatively, defer segment-based resume to Phase 5 and implement Phase 3 background export as foreground-only with 30-second background task extension (the simpler "continue for 30s" approach from Section 7.2 without resume).

### 4. Risk Register

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|----|------|-----------|--------|------------|-------|
| R1 | Custom video compositor adds per-frame overhead exceeding 33ms budget at 30fps 4K | Medium | High -- export speed drops below 0.5x realtime | Profile early in Phase 3. CIFilter rendering on GPU should meet budget. CPU-rendered text overlay is the risk -- cache CIImages per subtitle entry. | Native (Swift) |
| R2 | AAC audio glitches at segment boundaries in background export resume | High | Medium -- audible pop/click in exported video | Align segment boundaries to 1024-sample audio frame boundaries. Test with variety of audio content. | Native (Swift) |
| R3 | Event channel v2 migration causes runtime crash if Flutter and native sides update out of sync | Medium | High -- app crash during export | Use separate event channel name (`progress_v2`). Never modify existing channel format. | Both |
| R4 | Phase 0 V2 migration breaks existing export functionality | Medium | Critical -- core feature regression | Maintain V1 ClipManager compatibility shim during migration. Feature flag for V2 export path. Full regression testing. | Flutter |
| R5 | CompositionBuilder identity transform does not handle video rotation for export | High | Medium -- exported video has wrong orientation | Verify `CompositionBuilder.buildVideoComposition()` applies `preferredTransform` from source track, not just identity. Currently sets identity (line 384). | Native (Swift) |
| R6 | Parallel batch export triggers iOS memory pressure termination | Medium | High -- export data lost, user frustration | Auto-sequential for any job > 1080p. Monitor `os_proc_available_memory()` every 5 seconds during batch. Abort parallel mode if < 200MB available. | Native (Swift) |
| R7 | ZIPFoundation dependency adds maintenance burden for project bundles | Low | Low -- library is stable and well-maintained | Pin to specific version. Has no transitive dependencies. Fallback: shell out to `ditto` for ZIP creation (available in iOS simulator, not on device -- so ZIPFoundation is necessary). | Build |
| R8 | Social platform preset specs become outdated within months | Certain | Low -- users get suboptimal export settings | Store presets in a bundled JSON file. Add `lastVerified` date. Document update procedure. Consider remote update mechanism in future. | Flutter |
| R9 | Export queue persistence file corruption loses pending exports | Low | Medium -- user queued exports are lost | Write queue state atomically (write to temp file, rename). Keep one backup copy. Validate JSON structure on read. | Flutter |
| R10 | CompositionBuilder.insertImageSegment throws unsupported error | Certain (known) | Medium -- ImageClip types cannot be exported | Implement image-to-video synthesis: render image frame via CIImage and write as repeating frames via AVAssetWriter. Requires Phase 3 AVAssetWriter infrastructure. | Native (Swift) |

**Risk R5 is a new finding from this review.** The `CompositionBuilder.buildVideoComposition()` at line 384 applies `setTransform(.identity, at: .zero)`. However, videos recorded on iOS have a `preferredTransform` that encodes rotation (e.g., a portrait video has a 90-degree rotation in its transform). The current export path in `VideoProcessingService.renderComposition()` handles this via `VideoTransformCalculator` (which reads `preferredTransform` and applies it). But `CompositionBuilder` does NOT use `VideoTransformCalculator`. When the export path migrates to use `CompositionBuilder`, videos may render with incorrect orientation unless the builder is updated to apply per-source `preferredTransform` values.

### 5. Implementation Checklist

Ordered by dependency chain. Each file includes its phase and estimated effort.

#### Phase 0: V2 Migration + Pipeline Foundation (1 week)

| # | File | Action | Effort | Dependencies |
|---|------|--------|--------|--------------|
| 0.1 | `ios/Runner/Timeline/CompositionBuilder.swift` | Fix identity transform to apply `preferredTransform` per source track (Risk R5) | 0.5 days | None |
| 0.2 | `lib/models/export_config.dart` | **NEW.** ExportConfig, ExportProgress, ExportPhase data models | 0.5 days | None |
| 0.3 | `lib/core/export_composition_adapter.dart` | **NEW.** Adapter that converts TimelineManager state to `[CompositionSegment]` format for CompositionBuilder | 1 day | 0.2 |
| 0.4 | `ios/Runner/VideoProcessingService.swift` | Refactor `renderComposition()` to accept `[CompositionSegment]` and delegate to `CompositionBuilder.build()` instead of inline composition building | 1 day | 0.1 |
| 0.5 | `lib/views/export/export_sheet.dart` | Replace `ClipManager` + `sourceVideoPath` with `TimelineManager` + `MediaAssetRegistry`. Update `_buildClipsPayload()` to use `export_composition_adapter.dart` | 1.5 days | 0.3, 0.4 |
| 0.6 | `lib/views/export/export_sheet.dart` | Material-to-Cupertino widget migration (Appendix B: 8 widget replacements) | 0.5 days | 0.5 |
| 0.7 | Tests | Unit tests for ExportConfig serialization, ExportCompositionAdapter mapping. Integration test: export via CompositionBuilder produces valid video. | 1 day | 0.1-0.6 |

**Phase 0 exit criteria:**
- `export_sheet.dart` accepts `TimelineManager` and `MediaAssetRegistry`, not `ClipManager` and `sourceVideoPath`
- Export pipeline delegates composition building to `CompositionBuilder`
- No Material widgets remain in `export_sheet.dart`
- `flutter analyze` = 0 issues, `flutter test` = 100% pass
- Existing single-source exports still work (regression test)

#### Phase 1: Progress, Frame Grab, Preview (2 weeks)

| # | File | Action | Effort |
|---|------|--------|--------|
| 1.1 | `ios/Runner/ExportProgressReporter.swift` | **NEW.** Structured progress events with ETA, thermal state, disk space | 1 day |
| 1.2 | `ios/Runner/VideoProcessingService.swift` | Add `extractFrameGrab`, `cancelExport`, `renderPreview` methods. Store `currentExportSession` for cancellation with serial queue guard (R2-IF-5). | 1.5 days |
| 1.3 | `ios/Runner/AppDelegate.swift` | Register new method channel handlers + v2 progress event channel | 0.5 days |
| 1.4 | `lib/core/export_progress_controller.dart` | **NEW.** Flutter-side progress event deserialization, ETA calculation, demux for future batch support | 1 day |
| 1.5 | `lib/models/frame_grab_config.dart` | **NEW.** FrameGrabConfig, FrameFormat (PNG/JPEG/HEIF -- no TIFF per R1-M6) | 0.5 days |
| 1.6 | `lib/views/export/export_progress_view.dart` | **NEW.** Detailed progress UI extracted from export_sheet.dart (percentage, ETA, phase, file size, thermal/disk chips) | 1.5 days |
| 1.7 | `lib/views/export/frame_grab_sheet.dart` | **NEW.** Frame grab configuration UI with format selector and quality slider | 1 day |
| 1.8 | `lib/views/export/render_preview_view.dart` | **NEW.** 5-second render preview with inline playback | 1 day |
| 1.9 | `lib/views/export/export_sheet.dart` | Integrate progress view, frame grab option, preview button | 1 day |
| 1.10 | Tests | Unit + integration + widget tests per Phase 1 test plan in Section 18.2 | 1.5 days |

#### Phase 2: Sharing & Presets (2 weeks)

| # | File | Action | Effort |
|---|------|--------|--------|
| 2.1 | `ios/Runner/ShareService.swift` | **NEW.** UIActivityViewController wrapper with iPad popover support | 1 day |
| 2.2 | `lib/models/platform_preset.dart` | **NEW.** PlatformPreset, AspectRatioConfig, AutoCropConfig. Use updated Feb 2026 specs from R2-IF-3. | 1 day |
| 2.3 | `lib/models/audio_export_config.dart` | **NEW.** AudioExportConfig, AudioFormat (WAV/AAC/ALAC/FLAC -- no MP3), AudioQuality | 0.5 days |
| 2.4 | `lib/models/share_result.dart` | **NEW.** ShareResult, ShareDestination | 0.5 days |
| 2.5 | `ios/Runner/VideoTransformCalculator.swift` | Add auto-crop transform calculations (cropToFill, fitWithBars) | 1 day |
| 2.6 | `ios/Runner/VideoProcessingService.swift` | Add `exportAudioWithFormat` for WAV/ALAC/FLAC via AVAssetWriter audio-only path | 1 day |
| 2.7 | `lib/views/export/platform_preset_selector.dart` | **NEW.** Horizontal scrollable preset row UI | 1 day |
| 2.8 | `lib/views/export/auto_crop_preview.dart` | **NEW.** Crop preview overlay with draggable focal point | 1 day |
| 2.9 | `lib/views/export/audio_export_sheet.dart` | **NEW.** Audio format/quality/sample rate selection UI | 0.5 days |
| 2.10 | `lib/views/export/share_success_view.dart` | **NEW.** Post-export success state with share buttons | 0.5 days |
| 2.11 | `lib/views/export/export_sheet.dart` | Integrate preset selector, audio options, share flow | 1 day |
| 2.12 | Tests | Per Phase 2 test plan in Section 18.3 | 1.5 days |

#### Phase 3: Background, Queue, Batch (3-4 weeks)

| # | File | Action | Effort |
|---|------|--------|--------|
| 3.1 | `ios/Runner/BackgroundExportManager.swift` | **NEW.** UIBackgroundTask registration, 30-second continuation, local notification. Segment-based approach deferred to Phase 5. | 1.5 days |
| 3.2 | `lib/models/export_queue.dart` | **NEW.** QueuedExport, QueueState, QueuePriority | 0.5 days |
| 3.3 | `lib/models/batch_export_config.dart` | **NEW.** BatchExportConfig, BatchStrategy, ExportJobConfig | 0.5 days |
| 3.4 | `lib/core/export_queue_manager.dart` | **NEW.** Queue management with ChangeNotifier, JSON persistence in Caches dir, sequential processing | 2 days |
| 3.5 | `lib/core/batch_export_controller.dart` | **NEW.** Batch orchestration with resolution-guarded parallelism | 1.5 days |
| 3.6 | `lib/views/export/export_queue_sheet.dart` | **NEW.** Queue management UI with reorderable list | 1.5 days |
| 3.7 | `lib/views/export/batch_export_sheet.dart` | **NEW.** Multi-format selection UI | 1 day |
| 3.8 | `lib/views/export/mini_export_indicator.dart` | **NEW.** Persistent nav bar indicator with tap-to-expand | 1 day |
| 3.9 | `ios/Runner/VideoProcessingService.swift` | Add cancellation with serial dispatch queue, multiplexed progress events with exportId | 1 day |
| 3.10 | `ios/Runner/AppDelegate.swift` | Register background task, batch handlers, v2 event channel | 0.5 days |
| 3.11 | Tests | Per Phase 3 test plan in Section 18.4 | 2 days |

#### Phase 4: Subtitles & Project Sharing (2 weeks)

| # | File | Action | Effort |
|---|------|--------|--------|
| 4.1 | `ios/Runner/SubtitleRenderer.swift` | **NEW.** CIImage-based subtitle rendering (NOT CAAnimation). Per-subtitle CIImage cache. | 2 days |
| 4.2 | `lib/models/subtitle.dart` | **NEW.** SubtitleEntry, SubtitleStyle, SubtitlePosition | 0.5 days |
| 4.3 | `lib/models/project_bundle.dart` | **NEW.** LiquidProjectBundle, ProjectManifest, BundledAsset | 0.5 days |
| 4.4 | `ios/Runner/ProjectBundleService.swift` | **NEW.** ZIP creation/extraction via ZIPFoundation. UTType registration. | 1.5 days |
| 4.5 | `lib/core/project_bundle_service.dart` | **NEW.** Bundle creation/import orchestration | 1 day |
| 4.6 | `lib/views/export/subtitle_editor_sheet.dart` | **NEW.** Subtitle text entry, styling, preview | 1 day |
| 4.7 | `lib/views/export/project_share_sheet.dart` | **NEW.** Project bundle sharing UI | 0.5 days |
| 4.8 | `ios/Runner/Info.plist` | Add UTType declaration for `.liquidproject` | 0.25 days |
| 4.9 | `ios/Runner/VideoProcessingService.swift` | Integrate SubtitleRenderer into composition pipeline (via custom compositor or inline CIImage composite) | 1 day |
| 4.10 | Tests | Per Phase 4 test plan in Section 18.5 | 1.5 days |

**Total estimated implementation: 10-11 weeks** (1 week Phase 0 + 2 weeks Phase 1 + 2 weeks Phase 2 + 3-4 weeks Phase 3 + 2 weeks Phase 4)

### 6. Phase 0 Scope Definition

**Duration:** 1 week (5 working days)
**Goal:** Migrate export pipeline from V1 (ClipManager/sourceVideoPath) to V2 (TimelineManager/MediaAssetRegistry/CompositionBuilder) and establish the foundation for all 12 features.

**Day-by-day breakdown:**

**Day 1:** Fix CompositionBuilder.swift orientation handling (Risk R5). The `buildVideoComposition()` method at line 384 must apply `preferredTransform` from each source video track, not identity. Verify with portrait and landscape test videos.

**Day 2:** Create `lib/models/export_config.dart` with core data models. Create `lib/core/export_composition_adapter.dart` that converts `TimelineManager` state into `[CompositionSegment]` dictionaries. This adapter reads `TimelineManager.items`, resolves each clip's `mediaAssetId` via `MediaAssetRegistry.getById()` to obtain the file path, and maps the clip's source in/out points and keyframes to `CompositionSegment` format.

**Day 3:** Refactor `VideoProcessingService.renderComposition()` to accept `segments` (the `[CompositionSegment]` format) and delegate composition building to `CompositionBuilder.build()`. The method retains responsibility for resolution, FPS, bitrate, HDR, and `AVAssetExportSession` configuration. Maintain backward compatibility by accepting both old format (single `videoPath` + `clips`) and new format (`segments`).

**Day 4:** Update `export_sheet.dart` to accept `TimelineManager` and `MediaAssetRegistry` instead of `ClipManager` and `sourceVideoPath`. Replace `_buildClipsPayload()` with a call to `ExportCompositionAdapter.buildSegments()`. Migrate Material widgets to Cupertino (Appendix B). Verify export still works end-to-end.

**Day 5:** Write tests. Unit test `ExportCompositionAdapter` mapping. Integration test: export a single-source timeline via the new pipeline. Integration test: verify backward compatibility shim for V1 format still works. Run `flutter analyze` and `flutter test`. Update documentation.

**Phase 0 deliverables:**
1. `lib/models/export_config.dart` -- core export data models
2. `lib/core/export_composition_adapter.dart` -- TimelineManager-to-CompositionSegment adapter
3. Updated `ios/Runner/Timeline/CompositionBuilder.swift` -- preferredTransform handling
4. Updated `ios/Runner/VideoProcessingService.swift` -- delegates to CompositionBuilder
5. Updated `lib/views/export/export_sheet.dart` -- V2 API, Cupertino widgets
6. Updated `ios/Runner/AppDelegate.swift` -- backward-compatible method channel handling
7. Test coverage for all changes

**Phase 0 does NOT include:**
- New event channel (deferred to Phase 1)
- Structured progress events (deferred to Phase 1)
- Custom video compositor (deferred to Phase 3)
- Multi-source timeline testing (deferred until multi-source timelines exist in UI)

### 7. Final Assessment

**GO / NO-GO: CONDITIONAL GO**

The design is approved for implementation with the following conditions:

1. **Phase 0 is mandatory and blocking.** No Phase 1-4 feature work may begin until Phase 0 is complete and passes all exit criteria.

2. **Segment-based background export resume is deferred to Phase 5.** Phase 3 implements 30-second background continuation only (via `UIApplication.beginBackgroundTask()`). Full resume-from-checkpoint is a separate effort that adds 1-2 weeks and should not block the core feature set.

3. **Subtitle burn-in uses CIImage composite approach only.** All references to `CAAnimation`, `CATextLayer`, and `AVVideoCompositionCoreAnimationTool` in Section 11 are superseded. The implementation must use `UIGraphicsImageRenderer` -> `CIImage` -> `CISourceOverCompositing` within the per-frame rendering pass.

4. **The `ExportPipeline` protocol must be finalized** during Phase 0 and shared across the Export, Video Effects, and Color Grading design documents. All three designs must reference the same protocol. The Color Grading R3 review has already confirmed this requirement (line 2585-2588 of that document).

5. **Social platform preset specs must be verified** against current platform documentation before Phase 2 implementation. Use the February 2026 values from R2-IF-3 as a starting point, but verify each before hardcoding.

6. **Risk R5 (CompositionBuilder identity transform)** must be fixed on Day 1 of Phase 0. This is a regression risk that affects all exports once the pipeline migrates to CompositionBuilder.

### 8. Remaining Open Questions

| # | Question | Required Resolution Timing | Proposed Answer |
|---|----------|---------------------------|-----------------|
| Q1 | Should Phase 0 maintain a V1 backward compatibility shim, or hard-cut to V2? | Before Phase 0 starts | Hard-cut. The V1 ClipManager path will be removed. The export sheet already only has one call site. Migration should be atomic within a single PR. |
| Q2 | Should GIF/image sequence export be in scope? R2 provided a specification (IF-2). | Before Phase 2 | Include GIF export in Phase 2 (1 additional day). Defer image sequence export to Phase 5 (low demand, complex ZIP packaging). |
| Q3 | What is the minimum iOS version for background task APIs? | Before Phase 3 | `UIApplication.beginBackgroundTask()` is available since iOS 4. `UNUserNotificationCenter` since iOS 10. Both are well within our iOS 18 minimum target. |
| Q4 | How will the unified compositor handle the case where no effects, no color grading, and no subtitles are applied? | Before Phase 3 | Use the default compositor (standard AVMutableVideoCompositionLayerInstruction path) when no custom rendering is needed. Only switch to `customVideoCompositorClass` when effects/grading/subtitles are present. This preserves the faster AVAssetExportSession-optimized pipeline for simple exports. |
| Q5 | Should the export queue support cross-project exports (queuing exports from different projects)? | Before Phase 3 | Yes. Each `QueuedExport` stores a full `ExportConfig` snapshot including project ID and all necessary state. The queue manager does not hold a reference to a live project. |
| Q6 | What happens to in-progress exports when the app receives a memory warning? | Before Phase 1 | Flush preview frame cache (nil out `_currentExportFrame`). Do NOT cancel the export. AVAssetExportSession manages its own memory internally. Log the event for diagnostics. |

### 9. Summary

The Export & Sharing Enhancements design is architecturally sound and well-researched. The current-state analysis (Section 2) is verified accurate against the live codebase. The 12 features are individually well-specified with thorough edge case coverage.

The three critical integration conflicts (unified pipeline, V2 migration, subtitle rendering approach) all have viable resolution paths. The addition of Phase 0 to address the V2 migration gap is the most important outcome of the review process. Without Phase 0, every feature would be built on the V1 foundation and require rework.

The key risk to monitor is the custom video compositor performance overhead (Risk R1). The transition from AVAssetExportSession's optimized internal pipeline to a custom per-frame compositor will likely reduce export speed. Early Phase 3 profiling is essential.

The design is approved for implementation beginning with Phase 0.
