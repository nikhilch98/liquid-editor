# Project Management Enhancements - Design Document

**Date:** 2026-02-06
**Status:** Draft
**Author:** Claude + Nikhil

---

## Table of Contents

1. [Overview](#1-overview)
2. [Current State Analysis](#2-current-state-analysis)
3. [Project Duplication](#3-project-duplication)
4. [Project Backup/Restore](#4-project-backuprestore)
5. [Aspect Ratio Change Mid-Project](#5-aspect-ratio-change-mid-project)
6. [Project Sorting & Search](#6-project-sorting--search)
7. [Storage Usage Display](#7-storage-usage-display)
8. [iCloud Sync](#8-icloud-sync)
9. [Project Templates](#9-project-templates)
10. [Draft Management](#10-draft-management)
11. [Project Metadata Enhancements](#11-project-metadata-enhancements)
12. [Edge Cases & Error Handling](#12-edge-cases--error-handling)
13. [Performance Targets](#13-performance-targets)
14. [Implementation Plan](#14-implementation-plan)
15. [File Structure](#15-file-structure)
16. [Test Plan](#16-test-plan)

---

## 1. Overview

### 1.1 Summary

This document describes a suite of enhancements to the Liquid Editor's project management capabilities. The current system provides basic project creation, storage, opening, deletion, and renaming through the Project Library view. These enhancements transform the project library into a full-featured project management system with duplication, backup/restore, aspect ratio switching, sorting/search, storage monitoring, iCloud sync, templates, and improved draft management.

### 1.2 Goals

| Goal | Description |
|------|-------------|
| **Project Safety** | Protect user work via duplication, backup/restore, and crash recovery |
| **Workflow Efficiency** | Reduce friction with templates, sorting, and search |
| **Storage Awareness** | Give users visibility and control over disk usage |
| **Cross-Device** | Enable working on projects across multiple Apple devices |
| **Flexibility** | Allow mid-project aspect ratio changes without starting over |
| **Organization** | Tags, descriptions, and sorting for managing many projects |

### 1.3 Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Duplication strategy | Copy JSON, share media | Media files are large; sharing avoids doubling storage |
| Backup format | `.liquidbackup` (zip) | Standard, cross-platform, includes metadata for versioning |
| Aspect ratio approach | Per-project setting with per-clip override | Balances global consistency with per-clip fine-tuning |
| Search implementation | Client-side filtering | Project count is small (tens to low hundreds); no index needed |
| Storage calculation | Background isolate | Disk I/O must never block the UI thread |
| iCloud backend | iCloud Drive + CKDatabase | Handles both large files and metadata efficiently |
| Template storage | Separate Templates directory | Clean separation from projects; templates are not projects |
| Draft versioning | Ring buffer of last 5 saves | Bounded storage; enough for meaningful recovery |

### 1.4 Non-Goals (v1)

- Collaborative editing (multi-user on same project)
- Cloud storage beyond iCloud (Google Drive, Dropbox)
- Project version history with full diff/merge
- Export presets management (separate feature)
- Video proxy management (already handled by existing system)

---

## 2. Current State Analysis

### 2.1 Project Model Structure

The `Project` class (`lib/models/project.dart`) is an immutable value object with the following fields:

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `String` | UUID v4 unique identifier |
| `name` | `String` | User-visible project name |
| `sourceVideoPath` | `String` | Relative path to source video (e.g., `Videos/abc.mov`) |
| `frameRate` | `FrameRateOption` | Auto, 24, 30, or 60 FPS |
| `duration` | `Duration` | Original video duration |
| `timeline` | `KeyframeTimeline` | Keyframe data (legacy, migrated to clips) |
| `clips` | `List<TimelineItem>` | Multi-clip NLE timeline (v2) |
| `inPoint` / `outPoint` | `Duration` / `Duration?` | Legacy trim points (deprecated) |
| `createdAt` / `modifiedAt` | `DateTime` | Timestamps |
| `thumbnailPath` | `String?` | Relative path to thumbnail |
| `version` | `int` | Schema version (1 = legacy, 2 = multi-clip) |

The `Project` model supports `copyWith()` for immutable updates and `toJson()` / `fromJson()` for serialization.

**Notable absences** relevant to this design:
- No `aspectRatio` field (currently inferred from source video)
- No `description`, `tags`, or `color` metadata fields
- No `templateId` or `templateName` reference
- No `iCloudSyncStatus` tracking

### 2.2 Timeline Architecture (V2)

The Timeline Architecture V2 (`lib/models/clips/`) introduces typed clips:

| Clip Type | Description |
|-----------|-------------|
| `VideoClip` | Segment from a `MediaAsset` with in/out points and keyframes |
| `AudioClip` | Audio with volume/mute controls |
| `ImageClip` | Still image with configurable display duration |
| `GapClip` | Empty space placeholder |
| `ColorClip` | Solid color generator |

Each clip references a `MediaAsset` by ID (not file path). The `MediaAssetRegistry` provides:
- Lookup by ID and content hash
- Duplicate detection on import
- Relink support when files move

### 2.3 File Storage Layout

```
Documents/
  Projects/
    {uuid}.json              # Project data (JSON, atomic writes via .tmp rename)
  Videos/
    {uuid}.mov               # Source video files
  People/
    {personId}/
      image_{imageId}.jpg    # Person reference photos
```

### 2.4 Project Library UI

The `ProjectLibraryView` (`lib/views/library/project_library_view.dart`) provides:

- **Two-tab layout:** "Projects" and "People" tabs via `CNTabBar`
- **Grid view:** 2-column `SliverGrid` with `_PremiumProjectCard` widgets
- **Context menu:** `CupertinoContextMenu` with Open, Duplicate (TODO), Rename (TODO), Delete
- **Import flow:** `ImagePicker` -> copy to `Videos/` -> create project -> open editor
- **Pull-to-refresh:** `CupertinoSliverRefreshControl`
- **Sort button:** Present in trailing position of `CupertinoSliverNavigationBar` (TODO handler)
- **FAB:** `CNButton.icon` with `CNButtonStyle.glass` for new project creation

### 2.5 Project Storage Service

The `ProjectStorage` class (`lib/core/project_storage.dart`) provides:

| Method | Description |
|--------|-------------|
| `save(project)` | Atomic write via temp file + rename |
| `load(id)` | Load single project by UUID |
| `loadAll()` | Load all projects, sorted by `modifiedAt` descending |
| `delete(id)` | Delete project JSON file |
| `exists(id)` | Check existence |
| `scheduleAutoSave(project)` | Debounced auto-save (2-second delay) |
| `cancelAutoSave()` | Cancel pending auto-save |

Security: ID sanitization via UUID regex prevents path traversal.

### 2.6 Project File Service

The `ProjectFileService` class (`lib/core/project_file_service.dart`) handles:
- Resolving relative paths to absolute `File` objects
- Converting absolute paths to relative for storage
- Handling three path formats: relative, absolute with `/Documents/`, other absolute

---

## 3. Project Duplication

### 3.1 Overview

Users can create a complete copy of any project from the context menu. The duplicate shares media files with the original (no physical duplication of video data) but gets its own independent project JSON with a new UUID.

### 3.2 Duplication Strategy

```
Original Project:
  Projects/{original-uuid}.json
  -> references Videos/abc.mov (via sourceVideoPath or MediaAsset)

Duplicated Project:
  Projects/{new-uuid}.json        # New UUID, new name, reset timestamps
  -> references Videos/abc.mov    # SAME video file (shared, not copied)
```

**What gets duplicated:**
- All timeline clips (with new UUIDs for each clip/gap)
- All keyframes within clips (with new UUIDs)
- All timeline structure (order, in/out points, durations)
- Project settings (frame rate, version)
- Legacy fields (inPoint, outPoint, timeline)

**What gets a new identity:**
- Project ID (new UUID v4)
- Project name: `"{Original Name} Copy"` (or `"{Original Name} Copy 2"` if that exists)
- `createdAt`: current timestamp
- `modifiedAt`: current timestamp
- All clip IDs and keyframe IDs (new UUIDs to prevent cross-project conflicts)

**What is shared (not copied):**
- Source video files (referenced by same relative path)
- MediaAsset entries (same asset ID references)

### 3.3 Data Model Changes

No changes to the `Project` model are required. Duplication is a service-level operation.

### 3.4 Service Layer

```dart
/// ProjectManagementService - Handles project-level operations beyond CRUD
class ProjectManagementService {
  static final ProjectManagementService shared = ProjectManagementService._();
  ProjectManagementService._();

  final _storage = ProjectStorage.shared;

  /// Duplicate a project.
  ///
  /// Creates a deep copy of the project JSON with:
  /// - New UUID for project and all clips/keyframes
  /// - New name: "{originalName} Copy" (auto-incremented if exists)
  /// - Reset timestamps (createdAt/modifiedAt = now)
  /// - Shared media references (no file duplication)
  ///
  /// Returns the new project.
  /// Throws [ProjectStorageException] on failure.
  Future<Project> duplicateProject(String projectId) async {
    final original = await _storage.load(projectId);
    final newId = const Uuid().v4();
    final now = DateTime.now();

    // Generate unique name
    final newName = await _generateUniqueCopyName(original.name);

    // Deep clone clips with new IDs
    final clonedClips = original.clips.map((item) {
      if (item is TimelineClip) {
        return item.copyWith(
          id: const Uuid().v4(),
          keyframes: item.keyframes
              .map((kf) => kf.copyWith(id: const Uuid().v4()))
              .toList(),
        );
      }
      if (item is TimelineGap) {
        return item.copyWith(id: const Uuid().v4());
      }
      return item;
    }).toList();

    // Deep clone legacy keyframe timeline
    final clonedTimeline = original.timeline.copyWith(
      keyframes: original.timeline.keyframes
          .map((kf) => kf.copyWith(id: const Uuid().v4()))
          .toList(),
    );

    final duplicate = original.copyWith(
      id: newId,
      name: newName,
      clips: clonedClips,
      timeline: clonedTimeline,
      createdAt: now,
      modifiedAt: now,
    );

    await _storage.save(duplicate);
    return duplicate;
  }

  /// Generate a unique copy name by checking existing projects.
  Future<String> _generateUniqueCopyName(String originalName) async {
    final projects = await _storage.loadAll();
    final existingNames = projects.map((p) => p.name).toSet();

    var candidate = '$originalName Copy';
    var counter = 2;

    while (existingNames.contains(candidate)) {
      candidate = '$originalName Copy $counter';
      counter++;
    }

    return candidate;
  }
}
```

### 3.5 UI Integration

**Context Menu Action (already scaffolded):**

The `_PremiumProjectCard` context menu already has a "Duplicate" action with `TODO` placeholder at line 851-856 of `project_library_view.dart`. Replace with:

```dart
CupertinoContextMenuAction(
  onPressed: () async {
    Navigator.pop(context);
    HapticFeedback.mediumImpact();
    try {
      await ProjectManagementService.shared
          .duplicateProject(widget.project.id);
      // Trigger reload in parent
      widget.onDuplicate?.call();
    } catch (e) {
      // Show error dialog
      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Duplication Failed'),
            content: Text('Could not duplicate project: $e'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  },
  trailingIcon: CupertinoIcons.doc_on_doc,
  child: const Text('Duplicate'),
),
```

**Success feedback:**
- `HapticFeedback.mediumImpact()` on initiation
- `HapticFeedback.notificationOccurred(.success)` on completion
- Project grid reloads with new duplicate visible (animated insertion at position 0)

### 3.6 Error Handling

| Error Condition | Handling |
|----------------|----------|
| Source project not found | Show `CupertinoAlertDialog` with message |
| Insufficient disk space | Unlikely (JSON only, ~1-10KB), but catch `FileSystemException` |
| JSON serialization failure | Wrap in `ProjectStorageException`, show dialog |
| Concurrent modification | Atomic write prevents corruption; last write wins |

---

## 4. Project Backup/Restore

### 4.1 Overview

Users can export a project as a self-contained `.liquidbackup` archive and later restore it on the same or different device. The backup contains everything needed to fully reconstruct the project, including media files.

### 4.2 Backup Archive Format

```
{project-name}-backup.liquidbackup    # Actually a .zip file
  manifest.json                        # Backup metadata
  project.json                         # Complete project data
  media/                               # All referenced media files
    {original-filename-1}.mov
    {original-filename-2}.mov
    ...
  thumbnails/                          # Project thumbnails
    {thumbnail-name}.jpg
```

### 4.3 Manifest Schema

```json
{
  "version": 1,
  "appVersion": "1.0.0",
  "appBuildNumber": 42,
  "backupDate": "2026-02-06T10:30:00.000Z",
  "deviceModel": "iPhone 16 Pro",
  "iosVersion": "18.3",
  "projectId": "original-uuid",
  "projectName": "My Project",
  "projectVersion": 2,
  "mediaFiles": [
    {
      "originalPath": "Videos/abc.mov",
      "archivePath": "media/abc.mov",
      "contentHash": "sha256:...",
      "fileSize": 104857600,
      "mediaType": "video"
    }
  ],
  "totalSize": 105857600,
  "includesMedia": true
}
```

### 4.4 Backup Modes

| Mode | Description | Size | Use Case |
|------|-------------|------|----------|
| **Full Backup** | Project JSON + all media files + thumbnails | Large (GB) | Complete archival or device transfer |
| **Metadata Only** | Project JSON + thumbnails (no media) | Small (KB) | Quick backup of edits, assumes media is available |

The user selects the mode via a `CupertinoActionSheet` before export begins.

### 4.5 Data Model Changes

```dart
/// Backup metadata persisted in manifest.json
@immutable
class BackupManifest {
  final int version;
  final String appVersion;
  final int appBuildNumber;
  final DateTime backupDate;
  final String deviceModel;
  final String iosVersion;
  final String projectId;
  final String projectName;
  final int projectVersion;
  final List<BackupMediaEntry> mediaFiles;
  final int totalSize;
  final bool includesMedia;

  // JSON serialization...
}

@immutable
class BackupMediaEntry {
  final String originalPath;
  final String archivePath;
  final String contentHash;
  final int fileSize;
  final String mediaType;

  // JSON serialization...
}
```

### 4.6 Service Layer

```dart
/// ProjectBackupService - Export and import .liquidbackup archives
class ProjectBackupService {
  static final ProjectBackupService shared = ProjectBackupService._();
  ProjectBackupService._();

  /// Create a backup archive for a project.
  ///
  /// [includeMedia] controls whether media files are included (full vs metadata-only).
  /// [onProgress] reports progress as 0.0-1.0.
  ///
  /// Returns the path to the created .liquidbackup file in temp directory.
  /// Caller is responsible for sharing/moving the file.
  Future<String> createBackup({
    required String projectId,
    bool includeMedia = true,
    void Function(double progress)? onProgress,
  }) async { /* ... */ }

  /// Restore a project from a .liquidbackup archive.
  ///
  /// [archivePath] path to the .liquidbackup file.
  /// [onProgress] reports progress as 0.0-1.0.
  ///
  /// Returns the restored Project.
  /// Throws [BackupRestoreException] on failure.
  Future<Project> restoreBackup({
    required String archivePath,
    void Function(double progress)? onProgress,
  }) async { /* ... */ }

  /// Validate a backup archive without restoring.
  ///
  /// Checks manifest version, file integrity, and compatibility.
  Future<BackupValidationResult> validateBackup(String archivePath) async { /* ... */ }
}
```

### 4.7 Export Flow

1. User long-presses project card -> context menu -> "Export Backup"
2. `CupertinoActionSheet` appears:
   - "Full Backup (includes media)" with estimated size
   - "Metadata Only (edits only)" with estimated size
   - "Cancel"
3. Show progress indicator (`CupertinoActivityIndicator` with percentage text)
4. Build zip archive in background isolate:
   a. Write `manifest.json`
   b. Write `project.json`
   c. Copy media files to `media/` directory in archive (if full backup)
   d. Copy thumbnails to `thumbnails/` directory
   e. Compress to `.liquidbackup` (zip)
5. Present iOS share sheet (`Share.shareXFiles`) with the backup file
6. `HapticFeedback.notificationOccurred(.success)` on completion

### 4.8 Import/Restore Flow

1. User receives a `.liquidbackup` file (AirDrop, Files, email, etc.)
2. App registers as handler for `.liquidbackup` UTI
3. On file open:
   a. Validate manifest (check `version`, `appVersion` compatibility)
   b. Show confirmation dialog:
      - Project name
      - Backup date
      - Media file count and total size
      - Warning if backup is from newer app version
   c. If media files already exist (matched by content hash), skip re-copying
   d. Extract project JSON, assign new UUID (to prevent conflicts)
   e. Copy media files to `Videos/` directory
   f. Save project JSON to `Projects/`
   g. Navigate to project library (project appears at top)
4. Handle migration: if `project.json` has older `version`, run `migrateToMultiClip()`

### 4.9 Version Compatibility

| Backup Version | App Version | Action |
|---------------|-------------|--------|
| Same or older | Any | Restore normally, run migration if needed |
| Newer major | Any | Reject with message: "This backup requires a newer version of Liquid Editor" |
| Newer minor | Any | Warn but allow restore (forward compatibility for minor fields) |

### 4.10 UTI Registration

Add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key>
    <string>Liquid Editor Backup</string>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>LSHandlerRank</key>
    <string>Owner</string>
    <key>LSItemContentTypes</key>
    <array>
      <string>com.liquideditor.backup</string>
    </array>
  </dict>
</array>

<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeConformsTo</key>
    <array>
      <string>public.zip-archive</string>
    </array>
    <key>UTTypeDescription</key>
    <string>Liquid Editor Backup</string>
    <key>UTTypeIdentifier</key>
    <string>com.liquideditor.backup</string>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key>
      <array>
        <string>liquidbackup</string>
      </array>
    </dict>
  </dict>
</array>
```

### 4.11 Error Handling

| Error Condition | Handling |
|----------------|----------|
| Corrupt archive (not valid zip) | Show error dialog: "This file is not a valid backup" |
| Missing manifest.json | Show error dialog: "Backup file is incomplete" |
| Incompatible version | Show error with version info and App Store link |
| Insufficient disk space | Check available space before extraction; show dialog with required vs available |
| Media file missing in archive | Restore project anyway, mark affected clips as offline |
| Duplicate project name on restore | Auto-rename: "{Name} (Restored)" |
| Archive extraction failure | Clean up partial extraction, show error dialog |

---

## 5. Aspect Ratio Change Mid-Project

### 5.1 Overview

Users can change the project's target aspect ratio at any point during editing. This affects the video preview canvas, export dimensions, and timeline thumbnails. The system provides three adaptation modes for how existing clips respond to the new ratio.

### 5.2 Supported Aspect Ratios

| Ratio | Dimensions (1080p base) | Common Use |
|-------|-------------------------|------------|
| 16:9 | 1920 x 1080 | YouTube landscape, standard widescreen |
| 9:16 | 1080 x 1920 | TikTok, Instagram Reels, YouTube Shorts |
| 1:1 | 1080 x 1080 | Instagram feed posts |
| 4:3 | 1440 x 1080 | Classic television, iPad |
| 3:4 | 1080 x 1440 | Portrait photos |
| 4:5 | 1080 x 1350 | Instagram portrait posts |
| 2.35:1 | 2538 x 1080 | Cinematic widescreen (anamorphic) |
| Custom | User-defined | Arbitrary width:height |

### 5.3 Adaptation Modes

When the aspect ratio changes, existing clips must adapt. The user selects one of three modes:

#### 5.3.1 Letterbox / Pillarbox (Default)

Fit the entire source frame within the new aspect ratio. Black bars fill the remaining space.

```
Source (16:9):           Target (1:1):
┌────────────────┐       ┌──────────┐
│                │       │  ██████  │  <- Pillarbox (black bars left/right)
│    VIDEO       │  -->  │  VIDEO   │
│                │       │  ██████  │
└────────────────┘       └──────────┘
```

- Preserves all content, no cropping
- Black bars are visible (can be replaced with blur or color later)
- No keyframe adjustment needed (video stays centered)

#### 5.3.2 Zoom to Fill (Crop)

Scale the source to fill the new frame entirely. Some edges are cropped.

```
Source (16:9):           Target (1:1):
┌────────────────┐       ┌──────────┐
│    [crop]│     │       │          │
│    │VIDEO│     │  -->  │  VIDEO   │  <- Cropped edges
│    [crop]│     │       │          │
└────────────────┘       └──────────┘
```

- Fills entire frame, no black bars
- Content at edges is lost
- Existing keyframe translations may need clamping to stay within bounds

#### 5.3.3 Stretch (Distort)

Scale the source non-uniformly to exactly fill the new frame.

```
Source (16:9):           Target (1:1):
┌────────────────┐       ┌──────────┐
│                │       │          │
│    VIDEO       │  -->  │ STRETCHED│  <- Distorted proportions
│                │       │          │
└────────────────┘       └──────────┘
```

- Fills entire frame, no black bars
- Content is visually distorted
- Rarely desirable; included for completeness

### 5.4 Data Model Changes

Add to `Project`:

```dart
/// Target aspect ratio for the project canvas.
///
/// null = auto (use source video aspect ratio).
/// This defines the output frame, not the source clip dimensions.
final AspectRatioSetting? aspectRatio;

/// How clips adapt when aspect ratio differs from source.
final AspectRatioMode aspectRatioMode;
```

New model:

```dart
/// Predefined aspect ratios and custom option.
@immutable
class AspectRatioSetting {
  /// Width component (e.g., 16 for 16:9).
  final int widthRatio;

  /// Height component (e.g., 9 for 16:9).
  final int heightRatio;

  /// Display label (e.g., "16:9", "9:16", "Custom").
  final String label;

  const AspectRatioSetting({
    required this.widthRatio,
    required this.heightRatio,
    required this.label,
  });

  double get value => widthRatio / heightRatio;

  // Predefined constants
  static const landscape16x9 = AspectRatioSetting(widthRatio: 16, heightRatio: 9, label: '16:9');
  static const portrait9x16 = AspectRatioSetting(widthRatio: 9, heightRatio: 16, label: '9:16');
  static const square1x1 = AspectRatioSetting(widthRatio: 1, heightRatio: 1, label: '1:1');
  static const classic4x3 = AspectRatioSetting(widthRatio: 4, heightRatio: 3, label: '4:3');
  static const portrait3x4 = AspectRatioSetting(widthRatio: 3, heightRatio: 4, label: '3:4');
  static const portrait4x5 = AspectRatioSetting(widthRatio: 4, heightRatio: 5, label: '4:5');
  static const cinematic = AspectRatioSetting(widthRatio: 235, heightRatio: 100, label: '2.35:1');

  static const List<AspectRatioSetting> presets = [
    landscape16x9, portrait9x16, square1x1, classic4x3,
    portrait3x4, portrait4x5, cinematic,
  ];

  // JSON serialization...
}

/// How clips adapt to a different aspect ratio.
enum AspectRatioMode {
  /// Fit entirely within frame with bars (letterbox/pillarbox).
  letterbox,

  /// Zoom to fill the frame (crop edges).
  zoomToFill,

  /// Stretch non-uniformly to fill (distort).
  stretch,
}
```

### 5.5 Per-Clip Override

Each `VideoClip` can optionally override the project-level aspect ratio mode:

```dart
/// Per-clip aspect ratio mode override.
/// null = use project default.
final AspectRatioMode? aspectRatioModeOverride;
```

This allows selective treatment: some clips may zoom-to-fill while others letterbox.

### 5.6 Keyframe Impact

When changing aspect ratio with `zoomToFill` mode:

1. **Translation values** are normalized (-1.0 to 1.0) relative to the canvas, so they remain valid.
2. **Scale values** may need reclamping. If the zoom-to-fill scale already exceeds the user's keyframed scale, the effective minimum scale changes.
3. **Auto-reframe keyframes** may need regeneration since the target frame shape has changed.

**Strategy:** On aspect ratio change, iterate through all keyframes and:
- Clamp translations to valid bounds for the new aspect ratio
- Warn user if auto-reframe keyframes exist (offer to regenerate)
- Do NOT modify keyframes silently; show a confirmation dialog first

### 5.7 UI Design

**Project Settings Dropdown:**

Add an "Aspect Ratio" button to the editor toolbar or project settings panel:

```dart
CupertinoButton(
  padding: EdgeInsets.zero,
  onPressed: _showAspectRatioPicker,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(CupertinoIcons.aspectratio, size: 18),
      const SizedBox(width: 4),
      Text(project.aspectRatio?.label ?? 'Auto'),
    ],
  ),
)
```

**Aspect Ratio Picker Sheet:**

```dart
void _showAspectRatioPicker() {
  showCupertinoModalPopup(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('Aspect Ratio'),
      message: const Text('Choose the canvas aspect ratio for your project'),
      actions: [
        for (final preset in AspectRatioSetting.presets)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showAdaptationModePicker(preset);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AspectRatioPreview(ratio: preset),
                const SizedBox(width: 12),
                Text(preset.label),
              ],
            ),
          ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            _showCustomAspectRatioInput();
          },
          child: const Text('Custom...'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ),
  );
}
```

**Adaptation Mode Selection:**

After choosing a ratio, if it differs from the source video ratio, show:

```dart
CupertinoActionSheet(
  title: const Text('Adapt Content'),
  message: const Text('How should existing clips fill the new frame?'),
  actions: [
    CupertinoActionSheetAction(
      onPressed: () => _applyAspectRatio(ratio, AspectRatioMode.letterbox),
      child: const Text('Fit (Letterbox/Pillarbox)'),
    ),
    CupertinoActionSheetAction(
      onPressed: () => _applyAspectRatio(ratio, AspectRatioMode.zoomToFill),
      child: const Text('Fill (Crop Edges)'),
    ),
    CupertinoActionSheetAction(
      onPressed: () => _applyAspectRatio(ratio, AspectRatioMode.stretch),
      child: const Text('Stretch'),
    ),
  ],
  cancelButton: CupertinoActionSheetAction(
    isDefaultAction: true,
    onPressed: () => Navigator.pop(context),
    child: const Text('Cancel'),
  ),
)
```

### 5.8 Undo Support

Aspect ratio changes are undoable via the existing `KeyframeManager` undo/redo system:
- Changing the aspect ratio creates a new `Project` snapshot
- Undo reverts to the previous aspect ratio and mode
- All keyframe adjustments made during the change are also reverted

### 5.9 Export Impact

When exporting, the aspect ratio determines the output dimensions:

```dart
Size exportDimensions(Resolution resolution, AspectRatioSetting? ratio) {
  if (ratio == null) {
    // Auto: use resolution presets as-is (landscape)
    return resolution.dimensions;
  }

  // Scale to fit within resolution while maintaining aspect ratio
  final targetAR = ratio.value;
  final resWidth = resolution.width.toDouble();
  final resHeight = resolution.height.toDouble();

  if (targetAR > resWidth / resHeight) {
    // Wider than resolution: constrain by width
    return Size(resWidth, resWidth / targetAR);
  } else {
    // Taller than resolution: constrain by height
    return Size(resHeight * targetAR, resHeight);
  }
}
```

---

## 6. Project Sorting & Search

### 6.1 Overview

Enable users to sort and filter the project library by various criteria. Sorting persists across sessions. Search provides real-time as-you-type filtering.

### 6.2 Sort Options

| Sort Criteria | Direction | Implementation |
|---------------|-----------|----------------|
| Date Modified | Newest first (default) | `b.modifiedAt.compareTo(a.modifiedAt)` |
| Date Modified | Oldest first | `a.modifiedAt.compareTo(b.modifiedAt)` |
| Date Created | Newest first | `b.createdAt.compareTo(a.createdAt)` |
| Date Created | Oldest first | `a.createdAt.compareTo(b.createdAt)` |
| Name | A to Z | `a.name.toLowerCase().compareTo(b.name.toLowerCase())` |
| Name | Z to A | `b.name.toLowerCase().compareTo(a.name.toLowerCase())` |
| Duration | Longest first | `b.timelineDuration.compareTo(a.timelineDuration)` |
| Duration | Shortest first | `a.timelineDuration.compareTo(b.timelineDuration)` |

### 6.3 Sort Preference Persistence

```dart
/// Persisted via SharedPreferences
enum ProjectSortCriteria {
  modifiedNewest,
  modifiedOldest,
  createdNewest,
  createdOldest,
  nameAZ,
  nameZA,
  durationLongest,
  durationShortest,
}
```

Store in `SharedPreferences` as `project_sort_criteria` string key.

### 6.4 Sort UI

Replace the existing TODO sort button handler in `_buildProjectsTab()`:

```dart
trailing: CupertinoButton(
  padding: EdgeInsets.zero,
  onPressed: () {
    HapticFeedback.selectionClick();
    _showSortOptions();
  },
  child: const Icon(CupertinoIcons.sort_down, color: CupertinoColors.white),
),
```

Sort options sheet:

```dart
void _showSortOptions() {
  showCupertinoModalPopup(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('Sort Projects'),
      actions: [
        for (final criteria in ProjectSortCriteria.values)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _applySortCriteria(criteria);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(criteria.displayName),
                if (criteria == _currentSortCriteria) ...[
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.checkmark, size: 16),
                ],
              ],
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ),
  );
}
```

### 6.5 Search Implementation

**Search Bar:**

A `CupertinoSearchTextField` appears at the top of the project list when the user pulls down (or optionally always visible):

```dart
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: CupertinoSearchTextField(
      controller: _searchController,
      placeholder: 'Search projects',
      onChanged: _onSearchChanged,
      style: const TextStyle(color: CupertinoColors.white),
    ),
  ),
),
```

**Filtering Logic:**

```dart
List<Project> get _filteredProjects {
  var projects = List<Project>.from(_projects);

  // Apply search filter
  if (_searchQuery.isNotEmpty) {
    final query = _searchQuery.toLowerCase();
    projects = projects.where((p) =>
      p.name.toLowerCase().contains(query)
    ).toList();
  }

  // Apply sort
  projects.sort(_currentSortCriteria.comparator);

  return projects;
}

void _onSearchChanged(String value) {
  setState(() => _searchQuery = value);
}
```

**Empty Search State:**

When search produces no results, show:

```dart
SliverFillRemaining(
  child: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          CupertinoIcons.search,
          size: 48,
          color: CupertinoColors.systemGrey.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          'No Results',
          style: AppTypography.title.copyWith(color: CupertinoColors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Try a different search term',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    ),
  ),
)
```

### 6.6 Performance

- All sorting and filtering is done client-side on the already-loaded `List<Project>`
- With typical project counts (< 500), sort completes in < 1ms
- Search filtering uses `String.contains()` which is O(n * m) where n = projects, m = query length
- For < 500 projects and short queries, this is < 1ms
- No index or database needed

---

## 7. Storage Usage Display

### 7.1 Overview

Give users visibility into how much device storage Liquid Editor uses, broken down by project. Provide cleanup tools to reclaim space from unused media, orphaned files, and cache.

### 7.2 Storage Categories

| Category | Description | Source |
|----------|-------------|--------|
| **Project Files** | JSON project data | `Documents/Projects/*.json` |
| **Video Files** | Source and proxy videos | `Documents/Videos/*.mov` |
| **People Library** | Reference photos | `Documents/People/` |
| **Thumbnails** | Generated thumbnails | Various cached thumbnail locations |
| **App Cache** | Frame cache, temp files | `Library/Caches/` |
| **Other** | Misc app data | Any remaining Documents/ content |

### 7.3 Data Model

```dart
/// Storage usage breakdown
@immutable
class StorageUsage {
  final int projectFilesBytes;
  final int videoFilesBytes;
  final int peopleLibraryBytes;
  final int thumbnailsBytes;
  final int appCacheBytes;
  final int otherBytes;
  final List<ProjectStorageUsage> perProjectUsage;
  final DateTime calculatedAt;

  int get totalBytes =>
    projectFilesBytes + videoFilesBytes + peopleLibraryBytes +
    thumbnailsBytes + appCacheBytes + otherBytes;

  String get formattedTotal => _formatBytes(totalBytes);

  // JSON serialization...
}

@immutable
class ProjectStorageUsage {
  final String projectId;
  final String projectName;
  final int projectFileBytes;
  final int mediaBytes;
  final int thumbnailBytes;

  int get totalBytes => projectFileBytes + mediaBytes + thumbnailBytes;

  // JSON serialization...
}
```

### 7.4 Service Layer

```dart
/// StorageAnalysisService - Calculate storage usage in background
class StorageAnalysisService {
  static final StorageAnalysisService shared = StorageAnalysisService._();
  StorageAnalysisService._();

  /// Calculate total storage usage.
  ///
  /// Runs in a background isolate to avoid blocking the UI thread.
  /// Progress callback reports 0.0-1.0.
  Future<StorageUsage> calculateUsage({
    void Function(double progress)? onProgress,
  }) async {
    return compute(_calculateUsageIsolate, await _getBasePaths());
  }

  /// Identify orphaned media files (not referenced by any project).
  Future<List<OrphanedFile>> findOrphanedFiles() async { /* ... */ }

  /// Clean up orphaned files and cache.
  ///
  /// Returns the number of bytes freed.
  Future<int> cleanup({
    bool removeOrphanedMedia = true,
    bool clearCache = true,
    bool clearThumbnails = false,
  }) async { /* ... */ }
}
```

### 7.5 Per-Project Calculation

For each project:
1. Read the project JSON to find referenced `sourceVideoPath` values across all clips
2. Resolve each path via `ProjectFileService`
3. `stat()` each file to get size
4. Sum sizes by category

**Shared media handling:** If two projects reference the same video file, count it fully for each project in the per-project view but only once in the total. The total view uses deduplication by file path.

### 7.6 UI Design

**Settings Screen Integration:**

Add a "Storage" row to the app settings or as a new tab:

```dart
CupertinoListSection.insetGrouped(
  header: const Text('STORAGE'),
  children: [
    CupertinoListTile(
      leading: const Icon(CupertinoIcons.chart_pie),
      title: const Text('Storage Usage'),
      additionalInfo: Text(
        _storageUsage?.formattedTotal ?? 'Calculating...',
        style: TextStyle(color: CupertinoColors.secondaryLabel),
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: _showStorageDetail,
    ),
  ],
)
```

**Storage Detail View:**

A dedicated screen showing:

1. **Total usage bar** at the top (segmented color bar like iOS Settings > General > Storage)
2. **Per-category breakdown** as a list
3. **Per-project list** sorted by size (largest first)
4. **"Clean Up" button** at the bottom

```
┌─────────────────────────────────┐
│  Storage Usage                  │
│                                 │
│  ██████████░░░░░░░  2.4 GB     │
│  Videos  Projects  Cache Other │
│                                 │
│  ─── By Category ───           │
│  Videos          2.1 GB        │
│  Project Files   12.4 MB       │
│  People Library  45.2 MB       │
│  Thumbnails      8.1 MB        │
│  Cache           218 MB        │
│                                 │
│  ─── By Project ───            │
│  Travel Vlog     1.2 GB        │
│  Birthday Party  890 MB        │
│  Tutorial        245 MB        │
│                                 │
│  [    Clean Up Storage    ]     │
└─────────────────────────────────┘
```

**Clean Up Sheet:**

```dart
CupertinoActionSheet(
  title: const Text('Clean Up Storage'),
  message: Text('Free up ${_reclaimableSize} of storage'),
  actions: [
    CupertinoActionSheetAction(
      onPressed: _clearCacheOnly,
      child: Text('Clear Cache (${_cacheSize})'),
    ),
    CupertinoActionSheetAction(
      onPressed: _removeOrphans,
      child: Text('Remove Unused Media (${_orphanSize})'),
    ),
    CupertinoActionSheetAction(
      isDestructiveAction: true,
      onPressed: _clearAll,
      child: Text('Clear All Temporary Data (${_totalReclaimable})'),
    ),
  ],
  cancelButton: CupertinoActionSheetAction(
    isDefaultAction: true,
    onPressed: () => Navigator.pop(context),
    child: const Text('Cancel'),
  ),
)
```

### 7.7 Storage Warnings

Show a non-intrusive banner when available device storage is low:

| Available Space | Action |
|----------------|--------|
| > 1 GB | No warning |
| 500 MB - 1 GB | Yellow banner: "Storage is getting low" |
| < 500 MB | Red banner: "Very low storage - some features may not work" |
| < 100 MB | Block video import, show dialog |

Check on app launch and after large operations (import, export).

### 7.8 Performance

- Storage calculation must run in a background isolate via `compute()`
- Target: < 5 seconds for 100 projects with 200 media files
- Cache the result; recalculate on demand or when projects change
- Do NOT calculate on every app launch -- only when user navigates to storage screen or explicitly requests

---

## 8. iCloud Sync

### 8.1 Overview

Sync projects across the user's Apple devices via iCloud. This is a complex feature that requires careful conflict resolution, offline support, and bandwidth management.

### 8.2 Architecture

```
Device A                              iCloud                         Device B
┌──────────┐                    ┌──────────────┐               ┌──────────┐
│ Project   │  ──push JSON──>   │ CKDatabase   │  <──pull──    │ Project  │
│ Storage   │                   │ (metadata)   │               │ Storage  │
│           │  ──push media──>  │              │  <──pull──    │          │
│           │                   │ iCloud Drive │               │          │
│           │                   │ (large files)│               │          │
└──────────┘                    └──────────────┘               └──────────┘
```

### 8.3 Two-Tier Sync Strategy

| Data Type | iCloud Service | Reasoning |
|-----------|---------------|-----------|
| Project metadata (name, settings, timestamps) | `CKDatabase` (private) | Small, structured, conflict-detectable |
| Project JSON (full timeline data) | iCloud Drive (`NSFileManager.ubiquityContainerURL`) | Medium size, versioned files |
| Media files (videos, images) | iCloud Drive (same container) | Large files, native progress tracking |

### 8.4 Sync Flow

#### 8.4.1 Initial Setup

1. Check if iCloud is available: `FileManager.default.ubiquityIdentityToken`
2. If available, show opt-in dialog: "Would you like to sync projects across your devices?"
3. If accepted, begin initial sync:
   a. Upload all local projects to iCloud
   b. Download all remote projects not present locally
   c. Resolve conflicts (see 8.6)

#### 8.4.2 Ongoing Sync

**On local project save:**
1. Save locally (existing atomic write)
2. Queue upload to iCloud (background)
3. Update sync status indicator

**On remote change detected:**
1. `NSMetadataQuery` monitors iCloud container for changes
2. Download changed project JSON
3. Compare `modifiedAt` timestamps
4. Apply change or flag conflict (see 8.6)

### 8.5 Data Model Changes

Add to `Project`:

```dart
/// iCloud sync status for this project.
final SyncStatus syncStatus;

/// iCloud record change tag (for conflict detection).
final String? iCloudChangeTag;

/// Whether this project should be synced to iCloud.
final bool iCloudEnabled;
```

```dart
enum SyncStatus {
  /// Not synced, local only.
  local,

  /// Synced and up to date.
  synced,

  /// Local changes pending upload.
  pendingUpload,

  /// Remote changes pending download.
  pendingDownload,

  /// Conflict detected, needs resolution.
  conflict,

  /// Sync error occurred.
  error,

  /// Currently syncing.
  syncing,
}
```

### 8.6 Conflict Resolution

**Strategy: Last-Write-Wins with User Override**

When both devices modify the same project:

1. Compare `modifiedAt` timestamps
2. If within 60 seconds of each other: flag as conflict, ask user
3. If more than 60 seconds apart: newer version wins automatically
4. User conflict resolution dialog:

```
"This project was edited on both devices"
  iPhone: Modified 2 min ago (3 clips, 45s duration)
  iPad:   Modified 5 min ago (4 clips, 60s duration)

  [ Keep iPhone Version ]
  [ Keep iPad Version   ]
  [ Keep Both (create copy) ]
```

### 8.7 Native iOS Component

iCloud sync requires native Swift code:

```swift
/// ICloudSyncService - Native iCloud integration
class ICloudSyncService {
    static let shared = ICloudSyncService()

    private let fileManager = FileManager.default
    private var metadataQuery: NSMetadataQuery?

    /// iCloud container URL
    var containerURL: URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    /// Check if iCloud is available
    var isAvailable: Bool {
        fileManager.ubiquityIdentityToken != nil
    }

    /// Upload project to iCloud
    func uploadProject(_ projectId: String, data: Data) async throws { /* ... */ }

    /// Download project from iCloud
    func downloadProject(_ projectId: String) async throws -> Data { /* ... */ }

    /// Monitor for remote changes
    func startMonitoring(onChange: @escaping (String) -> Void) { /* ... */ }

    /// Stop monitoring
    func stopMonitoring() { /* ... */ }
}
```

### 8.8 Bandwidth Management

| Setting | Default | Description |
|---------|---------|-------------|
| Sync over WiFi only | `true` | Prevent large uploads on cellular |
| Auto-download media | `false` | Download media on demand, not automatically |
| Maximum upload size | 500 MB | Warn before syncing projects larger than this |

Store in `UserDefaults` (via `SharedPreferences`).

### 8.9 Sync Status UI

**Project Library:**

Each project card shows a small sync status icon:

| Status | Icon | Color |
|--------|------|-------|
| Synced | `checkmark.icloud` | Green |
| Syncing | `arrow.triangle.2.circlepath.icloud` | Blue (animated) |
| Pending Upload | `arrow.up.icloud` | Orange |
| Pending Download | `arrow.down.icloud` | Orange |
| Conflict | `exclamationmark.icloud` | Red |
| Error | `xmark.icloud` | Red |
| Local Only | No icon | -- |

**Settings:**

```dart
CupertinoListSection.insetGrouped(
  header: const Text('ICLOUD SYNC'),
  children: [
    CupertinoListTile(
      leading: const Icon(CupertinoIcons.cloud),
      title: const Text('iCloud Sync'),
      trailing: CupertinoSwitch(
        value: _iCloudEnabled,
        onChanged: _toggleICloudSync,
      ),
    ),
    CupertinoListTile(
      leading: const Icon(CupertinoIcons.wifi),
      title: const Text('WiFi Only'),
      trailing: CupertinoSwitch(
        value: _wifiOnly,
        onChanged: _toggleWifiOnly,
      ),
    ),
    CupertinoListTile(
      title: const Text('Last Synced'),
      additionalInfo: Text(_lastSyncedText),
    ),
  ],
)
```

### 8.10 Offline Support

- All operations work offline (local-first architecture)
- Changes are queued in a local sync queue
- When connectivity returns, queue is processed in order
- Queue is persisted to survive app restarts

```dart
/// Persistent sync operation queue
@immutable
class SyncOperation {
  final String id;
  final SyncOperationType type;   // upload, download, delete
  final String projectId;
  final DateTime queuedAt;
  final int retryCount;
  final String? error;

  // JSON serialization...
}
```

### 8.11 Privacy

- iCloud sync is opt-in (disabled by default)
- Users can selectively exclude projects from sync (per-project `iCloudEnabled` flag)
- No project data is ever sent to non-Apple servers
- Respect Apple's iCloud storage limits; warn when approaching limit

---

## 9. Project Templates

### 9.1 Overview

Templates provide preset project configurations for common use cases. Users can create projects from built-in or custom templates, and save their own projects as templates.

### 9.2 Template Types

| Template | Aspect Ratio | FPS | Resolution | Description |
|----------|-------------|-----|------------|-------------|
| **Blank** | Auto (from source) | Auto | Source | No presets, pure canvas |
| **TikTok / Reels** | 9:16 | 30 | 1080x1920 | Vertical short-form video |
| **Instagram Feed** | 1:1 | 30 | 1080x1080 | Square Instagram post |
| **Instagram Story** | 9:16 | 30 | 1080x1920 | Vertical story format |
| **YouTube** | 16:9 | 30 | 1920x1080 | Standard YouTube landscape |
| **YouTube Shorts** | 9:16 | 30 | 1080x1920 | Vertical YouTube format |
| **Cinematic** | 2.35:1 | 24 | 2538x1080 | Film-style widescreen, 24fps |
| **Custom** | User-defined | User-defined | User-defined | Saved from existing project |

### 9.3 Data Model

```dart
/// A project template with preset settings.
@immutable
class ProjectTemplate {
  /// Unique identifier.
  final String id;

  /// Template display name.
  final String name;

  /// Template description.
  final String description;

  /// Template category (built-in templates use predefined categories).
  final TemplateCategory category;

  /// Whether this is a built-in template or user-created.
  final bool isBuiltIn;

  /// Aspect ratio setting (null = auto from source).
  final AspectRatioSetting? aspectRatio;

  /// Frame rate setting.
  final FrameRateOption frameRate;

  /// Target resolution (used for export, null = source resolution).
  final Resolution? resolution;

  /// Aspect ratio adaptation mode.
  final AspectRatioMode aspectRatioMode;

  /// Default effects or LUTs to apply (future expansion).
  final List<String>? defaultEffectIds;

  /// SF Symbol name for template icon.
  final String iconSymbol;

  /// Template creation date (for custom templates).
  final DateTime createdAt;

  const ProjectTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.isBuiltIn = false,
    this.aspectRatio,
    this.frameRate = FrameRateOption.auto,
    this.resolution,
    this.aspectRatioMode = AspectRatioMode.zoomToFill,
    this.defaultEffectIds,
    required this.iconSymbol,
    required this.createdAt,
  });

  // JSON serialization...
  // Built-in templates as static constants...
}

enum TemplateCategory {
  social,       // TikTok, Instagram, YouTube
  cinematic,    // Film, widescreen
  standard,     // Blank, general purpose
  custom,       // User-created
}
```

### 9.4 Storage

```
Documents/
  Templates/
    {template-id}.json    # Custom template JSON
```

Built-in templates are hardcoded in `ProjectTemplate` static constants and never persisted.

### 9.5 Template Service

```dart
/// ProjectTemplateService - Manage templates and create projects from them
class ProjectTemplateService {
  static final ProjectTemplateService shared = ProjectTemplateService._();
  ProjectTemplateService._();

  /// Get all available templates (built-in + custom).
  Future<List<ProjectTemplate>> getAllTemplates() async { /* ... */ }

  /// Get built-in templates only.
  List<ProjectTemplate> get builtInTemplates => ProjectTemplate.builtIns;

  /// Get custom templates only.
  Future<List<ProjectTemplate>> getCustomTemplates() async { /* ... */ }

  /// Save current project settings as a new template.
  Future<ProjectTemplate> saveAsTemplate({
    required Project project,
    required String templateName,
    required String description,
  }) async { /* ... */ }

  /// Delete a custom template (built-in templates cannot be deleted).
  Future<void> deleteTemplate(String templateId) async { /* ... */ }

  /// Create a new project from a template.
  ///
  /// The project is created with the template's settings applied
  /// but no media (media is added separately via import).
  Project createFromTemplate({
    required ProjectTemplate template,
    required String projectName,
    required String sourceVideoPath,
    required Duration videoDuration,
  }) { /* ... */ }
}
```

### 9.6 UI Design

**Template Selection Sheet:**

When creating a new project, show template selection before or after video import:

```dart
void _showTemplateSelector() {
  showCupertinoModalPopup(
    context: context,
    builder: (context) => _TemplatePickerSheet(
      onSelected: (template) {
        Navigator.pop(context);
        _importVideoWithTemplate(template);
      },
    ),
  );
}
```

The template picker is a scrollable grid of template cards, grouped by category:

```
┌──────────────────────────────────────┐
│  Choose a Template                   │
│                                      │
│  ─── Social ───                     │
│  ┌─────┐  ┌─────┐  ┌─────┐        │
│  │ 9:16│  │ 1:1 │  │ 9:16│        │
│  │TikTok│ │Insta │ │Reels│         │
│  └─────┘  └─────┘  └─────┘        │
│                                      │
│  ─── Standard ───                   │
│  ┌─────┐  ┌─────┐                  │
│  │16:9 │  │Auto │                  │
│  │YouTb │ │Blank│                  │
│  └─────┘  └─────┘                  │
│                                      │
│  ─── Cinematic ───                  │
│  ┌─────┐                            │
│  │2.35 │                            │
│  │Film │                            │
│  └─────┘                            │
│                                      │
│  ─── My Templates ───              │
│  ┌─────┐  ┌─────┐                  │
│  │     │  │     │                  │
│  │My 1 │  │My 2 │                  │
│  └─────┘  └─────┘                  │
│                                      │
│        [ Cancel ]                    │
└──────────────────────────────────────┘
```

**Save As Template:**

From the project editor's settings/options menu:

```dart
CupertinoContextMenuAction(
  onPressed: () {
    Navigator.pop(context);
    _showSaveAsTemplateDialog();
  },
  trailingIcon: CupertinoIcons.bookmark,
  child: const Text('Save as Template'),
),
```

### 9.7 Default Template

Users can set a default template in settings. When a default is set:
- Tapping the FAB (+) immediately opens the video picker
- The selected template's settings are auto-applied
- No template selection sheet is shown

If no default is set, the template selection sheet is shown first.

---

## 10. Draft Management

### 10.1 Overview

Enhance the existing auto-save system with draft versioning, crash recovery, and revert capabilities. The current system uses a 2-second debounced auto-save; this enhancement adds a ring buffer of recent saves and crash detection.

### 10.2 Current Auto-Save System

From `ProjectStorage`:
- `scheduleAutoSave(project)` with 2-second debounce
- Single save target (overwrites previous)
- No crash detection
- No revert capability

### 10.3 Enhanced Draft System

#### 10.3.1 Ring Buffer of Saves

Maintain the last N auto-saves for each project:

```
Documents/
  Projects/
    {uuid}.json              # Current "official" save
  Drafts/
    {uuid}/
      draft_0.json           # Most recent draft
      draft_1.json           # Previous draft
      draft_2.json           # ...
      draft_3.json
      draft_4.json           # Oldest draft
      meta.json              # Draft metadata
```

#### 10.3.2 Draft Metadata

```json
{
  "projectId": "uuid",
  "currentIndex": 0,
  "drafts": [
    {
      "index": 0,
      "savedAt": "2026-02-06T10:30:00.000Z",
      "clipCount": 5,
      "timelineDuration": 45000,
      "triggerReason": "auto_save"
    },
    {
      "index": 1,
      "savedAt": "2026-02-06T10:29:45.000Z",
      "clipCount": 5,
      "timelineDuration": 42000,
      "triggerReason": "auto_save"
    }
  ],
  "cleanShutdown": true
}
```

### 10.4 Data Model

```dart
/// Draft metadata for a project's auto-save history
@immutable
class DraftMetadata {
  final String projectId;
  final int currentIndex;
  final List<DraftEntry> drafts;
  final bool cleanShutdown;

  // JSON serialization...
}

@immutable
class DraftEntry {
  final int index;
  final DateTime savedAt;
  final int clipCount;
  final int timelineDurationMs;
  final DraftTriggerReason triggerReason;

  // JSON serialization...
}

enum DraftTriggerReason {
  autoSave,       // Regular 2-second debounced save
  manualSave,     // User explicitly saved
  significantEdit, // Major operation (add/delete clip, aspect ratio change)
  appBackground,   // App moved to background
}
```

### 10.5 Service Layer

```dart
/// DraftManagementService - Enhanced auto-save with versioning and recovery
class DraftManagementService {
  static final DraftManagementService shared = DraftManagementService._();
  DraftManagementService._();

  static const int maxDrafts = 5;
  static const Duration autoSaveDelay = Duration(seconds: 2);

  /// Save a draft (ring buffer rotation).
  ///
  /// Writes to the next slot in the ring buffer and updates metadata.
  Future<void> saveDraft(Project project, DraftTriggerReason reason) async { /* ... */ }

  /// Check for crash recovery on project open.
  ///
  /// Returns the recoverable draft if the previous session did not shut down cleanly.
  /// Returns null if no recovery is needed.
  Future<DraftEntry?> checkForRecovery(String projectId) async { /* ... */ }

  /// Recover from a draft.
  ///
  /// Replaces the current project save with the specified draft.
  Future<Project> recoverFromDraft(String projectId, int draftIndex) async { /* ... */ }

  /// Revert to the previous draft.
  ///
  /// Returns the reverted project, or null if no previous draft exists.
  Future<Project?> revertToLastDraft(String projectId) async { /* ... */ }

  /// Mark clean shutdown for a project.
  ///
  /// Called when the editor is closed normally.
  Future<void> markCleanShutdown(String projectId) async { /* ... */ }

  /// Clean up old drafts for all projects.
  ///
  /// Removes draft folders for deleted projects.
  Future<void> cleanupOrphanedDrafts() async { /* ... */ }

  /// Get draft history for a project.
  Future<DraftMetadata?> getDraftMetadata(String projectId) async { /* ... */ }
}
```

### 10.6 Crash Recovery Flow

1. On project open, call `checkForRecovery(projectId)`
2. If `cleanShutdown == false` and a newer draft exists than the saved project:
3. Show recovery dialog:

```dart
CupertinoAlertDialog(
  title: const Text('Recover Unsaved Changes?'),
  content: Text(
    'Liquid Editor found unsaved changes from '
    '${_formatTime(draft.savedAt)}.\n\n'
    'Recovered version has ${draft.clipCount} clips '
    '(${_formatDuration(draft.timelineDurationMs)}).',
  ),
  actions: [
    CupertinoDialogAction(
      isDestructiveAction: true,
      onPressed: () {
        Navigator.pop(context, false);
      },
      child: const Text('Discard'),
    ),
    CupertinoDialogAction(
      isDefaultAction: true,
      onPressed: () {
        Navigator.pop(context, true);
      },
      child: const Text('Recover'),
    ),
  ],
)
```

### 10.7 Unsaved Changes Indicator

When the project has changes since the last save, show a small indicator:

```dart
// In the editor's navigation bar:
CupertinoNavigationBar(
  middle: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(project.name),
      if (_hasUnsavedChanges) ...[
        const SizedBox(width: 6),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: CupertinoColors.systemOrange,
            shape: BoxShape.circle,
          ),
        ),
      ],
    ],
  ),
)
```

### 10.8 Revert to Last Save

Available from the editor's options menu:

```dart
CupertinoContextMenuAction(
  onPressed: () async {
    Navigator.pop(context);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Revert to Last Save?'),
        content: const Text(
          'This will discard all changes since your last save. '
          'This action cannot be undone.',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revert'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _revertToLastSave();
    }
  },
  trailingIcon: CupertinoIcons.arrow_counterclockwise,
  child: const Text('Revert to Last Save'),
),
```

### 10.9 App Lifecycle Integration

```dart
/// In the editor widget:
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  switch (state) {
    case AppLifecycleState.paused:
    case AppLifecycleState.inactive:
      // Save draft immediately when app goes to background
      DraftManagementService.shared.saveDraft(
        _currentProject,
        DraftTriggerReason.appBackground,
      );
      break;
    case AppLifecycleState.detached:
      // App is being terminated - clean shutdown
      DraftManagementService.shared.markCleanShutdown(_currentProject.id);
      break;
    default:
      break;
  }
}
```

### 10.10 Draft Expiry

- Drafts older than 7 days are automatically cleaned up
- Cleanup runs on app launch (background, non-blocking)
- Only drafts for existing projects are kept; orphaned draft folders are removed
- Total draft storage is bounded: 5 drafts per project x project JSON size (~1-10KB each) = ~50KB per project

---

## 11. Project Metadata Enhancements

### 11.1 Overview

Enrich the project model with additional metadata for organization and discovery.

### 11.2 New Fields

Add to `Project` model:

```dart
/// Optional project description.
final String? description;

/// User-assigned tags for organization.
final List<String> tags;

/// Star rating (0 = unrated, 1-5 = rated).
final int starRating;

/// Color label for visual organization in project grid.
final ProjectColor? colorLabel;

/// Whether this project is marked as a favorite.
final bool isFavorite;
```

```dart
/// Color labels for project organization.
enum ProjectColor {
  red,
  orange,
  yellow,
  green,
  blue,
  purple,
  pink;

  Color get color {
    switch (this) {
      case ProjectColor.red: return CupertinoColors.systemRed;
      case ProjectColor.orange: return CupertinoColors.systemOrange;
      case ProjectColor.yellow: return CupertinoColors.systemYellow;
      case ProjectColor.green: return CupertinoColors.systemGreen;
      case ProjectColor.blue: return CupertinoColors.systemBlue;
      case ProjectColor.purple: return CupertinoColors.systemPurple;
      case ProjectColor.pink: return CupertinoColors.systemPink;
    }
  }
}
```

### 11.3 JSON Schema Update

These fields are all optional with defaults to maintain backward compatibility:

```dart
// In Project.fromJson():
description: json['description'] as String?,
tags: (json['tags'] as List?)?.cast<String>() ?? const [],
starRating: json['starRating'] as int? ?? 0,
colorLabel: json['colorLabel'] != null
    ? ProjectColor.values.byName(json['colorLabel'] as String)
    : null,
isFavorite: json['isFavorite'] as bool? ?? false,
```

### 11.4 Context Menu Enhancements

Expand the project card context menu:

```dart
// Existing actions: Open, Duplicate, Rename, Delete
// New actions:
CupertinoContextMenuAction(
  onPressed: () {
    Navigator.pop(context);
    _showColorPicker();
  },
  trailingIcon: CupertinoIcons.paintbrush,
  child: const Text('Color Label'),
),
CupertinoContextMenuAction(
  onPressed: () {
    Navigator.pop(context);
    _toggleFavorite();
  },
  trailingIcon: project.isFavorite
      ? CupertinoIcons.heart_fill
      : CupertinoIcons.heart,
  child: Text(project.isFavorite ? 'Unfavorite' : 'Favorite'),
),
CupertinoContextMenuAction(
  onPressed: () {
    Navigator.pop(context);
    _showProjectInfo();
  },
  trailingIcon: CupertinoIcons.info,
  child: const Text('Info'),
),
```

### 11.5 Visual Integration

**Color Label:** Thin colored border at the bottom of the project card thumbnail.

**Favorite:** Small heart icon overlay at the top-left of the project card.

**Star Rating:** Shown on the project info sheet, not on the card (to keep the grid clean).

### 11.6 Search Enhancement

With metadata, search can be extended to filter by:
- Name (existing)
- Tags
- Color label
- Favorites only
- Star rating >= N

---

## 12. Edge Cases & Error Handling

### 12.1 Cross-Feature Edge Cases

| Scenario | Handling |
|----------|----------|
| Duplicate project with missing media | Duplication succeeds (JSON only); clips referencing missing media show "offline" indicator |
| Restore backup from newer app version | Reject if major version mismatch; warn and attempt if minor |
| iCloud sync conflict on same project from two devices | Last-write-wins with 60-second conflict window; user resolves ties |
| Storage full during backup export | Check available space before starting; abort with user-friendly message |
| Very large projects (100+ clips) | All operations use streaming/pagination; JSON serialization is still fast (< 50ms for 100 clips) |
| Aspect ratio change with existing auto-reframe keyframes | Warn user and offer to regenerate auto-reframe keyframes for new ratio |
| Template created from project with custom fonts/LUTs | Template stores references by ID; missing references show warning on template use |
| Draft recovery after iOS kills app for memory | `cleanShutdown` flag in draft metadata detects this; recovery dialog shown on next launch |
| Search with special characters | Escape regex chars; use plain `String.contains()` (no regex) |
| Rename project to existing name | Allow (names are not unique); search/sort helps distinguish |
| Delete project while iCloud sync in progress | Cancel sync operation, delete locally, queue remote delete |
| Backup import with duplicate media (same content hash) | Skip re-copying; reference existing media file via `MediaAssetRegistry.hasDuplicate()` |
| Aspect ratio change on empty project (no clips) | Simply update the setting; no adaptation dialog needed |
| Template deletion while project using it | Projects do not reference templates after creation; safe to delete |
| iCloud account change | Detect via `NSUbiquitousKeyValueStore.didChangeExternallyNotification`; re-sync |

### 12.2 Error Recovery Principles

1. **Never lose user data silently.** Always show a dialog if an operation fails.
2. **Prefer degraded functionality over failure.** If media is missing, still show the project.
3. **Atomic operations.** Use temp files + rename for all write operations (already done by `ProjectStorage`).
4. **Background error retry.** iCloud sync operations retry with exponential backoff.
5. **User agency.** Always give the user a choice (recover/discard, keep A/keep B, retry/cancel).

---

## 13. Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Project duplication | < 500ms | JSON copy + new UUIDs; no file I/O for media |
| Backup creation (metadata only) | < 1s | JSON + small files |
| Backup creation (full, 1GB media) | < 60s | Proportional to media size; zip compression |
| Backup restoration | < 60s | Proportional to archive size |
| Aspect ratio change | < 100ms | Project model update + keyframe reclamping |
| Sort change | < 5ms | In-memory sort of loaded project list |
| Search filtering | < 5ms | In-memory string matching |
| Storage calculation (100 projects) | < 5s | Background isolate; cached result |
| iCloud initial sync (10 projects) | < 30s | Dependent on network; projects sync first, media lazily |
| Template creation | < 100ms | Extract settings from project |
| Draft save | < 50ms | JSON write to ring buffer slot |
| Crash recovery check | < 10ms | Read draft metadata JSON |
| Draft revert | < 100ms | Read draft JSON + replace project |

### 13.1 Memory Constraints

| Feature | Memory Budget | Notes |
|---------|--------------|-------|
| Project list (100 projects) | < 5 MB | ~50KB per project model in memory |
| Storage analysis result | < 1 MB | Summary data only |
| Template list | < 500 KB | Small data models |
| Draft metadata | < 100 KB | Ring buffer metadata only |
| Backup archive (in progress) | Streaming | Never load full archive into memory |

### 13.2 Threading Model

| Operation | Thread | Mechanism |
|-----------|--------|-----------|
| Project duplication | Main thread | Fast enough; JSON operations only |
| Backup creation | Background isolate | `compute()` for zip creation |
| Backup restoration | Background isolate | `compute()` for zip extraction |
| Storage calculation | Background isolate | `compute()` for disk I/O |
| iCloud sync | Background queue | Native Swift async/await |
| Search/sort | Main thread | Fast enough for in-memory operations |
| Draft save | Main thread | Small JSON write; < 50ms |

---

## 14. Implementation Plan

### Phase 1: Core Project Management (Week 1-2)

| Task | Priority | Complexity | Dependencies |
|------|----------|------------|--------------|
| Project Duplication service + UI | P0 | Low | None |
| Project Sorting (all criteria) | P0 | Low | None |
| Project Search (name filter) | P0 | Low | None |
| Sort preference persistence | P1 | Low | SharedPreferences |
| Project Rename (complete TODO) | P0 | Low | None |

**Deliverables:**
- `lib/core/project_management_service.dart`
- Updated `lib/views/library/project_library_view.dart` (sort, search, duplicate)
- Tests for duplication logic and sorting
- Updated analysis files

### Phase 2: Aspect Ratio & Drafts (Week 3-4)

| Task | Priority | Complexity | Dependencies |
|------|----------|------------|--------------|
| `AspectRatioSetting` model | P0 | Low | None |
| Aspect ratio picker UI | P0 | Medium | AspectRatioSetting model |
| Adaptation mode logic | P0 | Medium | Aspect ratio model |
| Keyframe reclamping on ratio change | P1 | Medium | Adaptation mode logic |
| Draft ring buffer service | P0 | Medium | None |
| Crash recovery detection | P0 | Medium | Draft service |
| Revert to Last Save | P1 | Low | Draft service |
| Unsaved changes indicator | P1 | Low | Draft service |
| App lifecycle integration | P0 | Low | Draft service |

**Deliverables:**
- `lib/models/aspect_ratio.dart`
- `lib/core/draft_management_service.dart`
- Updated `Project` model with aspect ratio fields
- Aspect ratio picker UI
- Draft recovery dialog
- Tests for aspect ratio calculations and draft ring buffer
- Updated analysis files

### Phase 3: Backup/Restore & Storage (Week 5-6)

| Task | Priority | Complexity | Dependencies |
|------|----------|------------|--------------|
| `BackupManifest` model | P0 | Low | None |
| Backup creation service | P0 | High | BackupManifest |
| Backup restoration service | P0 | High | BackupManifest, migration |
| UTI registration for `.liquidbackup` | P0 | Medium | iOS native |
| Share sheet integration for export | P1 | Medium | Backup service |
| Backup/restore UI (action sheet + progress) | P0 | Medium | Services |
| `StorageUsage` model | P0 | Low | None |
| Storage calculation service | P0 | Medium | Background isolate |
| Storage usage UI (settings screen) | P1 | Medium | Storage service |
| Cleanup service (orphans, cache) | P1 | Medium | Storage service |
| Storage warnings | P2 | Low | Storage service |

**Deliverables:**
- `lib/models/backup_manifest.dart`
- `lib/core/project_backup_service.dart`
- `lib/core/storage_analysis_service.dart`
- `lib/views/settings/storage_usage_view.dart`
- Updated `ios/Runner/Info.plist` with UTI registration
- Tests for backup creation, restoration, and storage calculation
- Updated analysis files

### Phase 4: iCloud Sync & Templates (Week 7-10)

| Task | Priority | Complexity | Dependencies |
|------|----------|------------|--------------|
| `ProjectTemplate` model | P0 | Low | AspectRatioSetting |
| Built-in templates | P0 | Low | Template model |
| Template service | P0 | Medium | Template model |
| Template picker UI | P1 | Medium | Template service |
| Save-as-template flow | P1 | Low | Template service |
| Default template setting | P2 | Low | Template service |
| iCloud availability detection | P0 | Medium | Native Swift |
| iCloud Drive integration (project JSON) | P0 | High | Native Swift |
| iCloud Drive integration (media files) | P1 | High | Native Swift |
| Sync status tracking | P0 | Medium | iCloud integration |
| Conflict resolution UI | P0 | Medium | Sync status |
| Offline queue | P1 | High | Sync status |
| Sync settings UI | P1 | Medium | iCloud integration |
| Project metadata enhancements | P2 | Low | None |

**Deliverables:**
- `lib/models/project_template.dart`
- `lib/core/project_template_service.dart`
- `lib/views/library/template_picker_sheet.dart`
- `ios/Runner/ICloudSyncService.swift`
- `lib/core/icloud_sync_service.dart` (Flutter bridge)
- `lib/core/sync_queue.dart`
- Updated `Project` model with sync and metadata fields
- Tests for templates, sync queue, and conflict resolution
- Updated analysis files

---

## 15. File Structure

### New Files

```
lib/
  models/
    aspect_ratio.dart               # AspectRatioSetting, AspectRatioMode
    backup_manifest.dart            # BackupManifest, BackupMediaEntry
    project_template.dart           # ProjectTemplate, TemplateCategory
    storage_usage.dart              # StorageUsage, ProjectStorageUsage
    draft_metadata.dart             # DraftMetadata, DraftEntry
    sync_operation.dart             # SyncOperation, SyncStatus
  core/
    project_management_service.dart # Duplication, rename (non-CRUD operations)
    project_backup_service.dart     # Backup export/import
    project_template_service.dart   # Template CRUD and project creation
    draft_management_service.dart   # Draft ring buffer and recovery
    storage_analysis_service.dart   # Storage calculation and cleanup
    icloud_sync_service.dart        # iCloud sync Flutter bridge
    sync_queue.dart                 # Offline sync operation queue
  views/
    library/
      template_picker_sheet.dart    # Template selection UI
      sort_options_sheet.dart       # Sort criteria picker (or inline)
    settings/
      storage_usage_view.dart       # Storage breakdown and cleanup UI
      icloud_settings_view.dart     # iCloud sync configuration
ios/
  Runner/
    ICloudSyncService.swift         # Native iCloud integration
```

### Modified Files

```
lib/
  models/
    project.dart                    # Add aspectRatio, description, tags, starRating,
                                    #   colorLabel, isFavorite, syncStatus fields
  core/
    project_storage.dart            # Integration with draft management
  views/
    library/
      project_library_view.dart     # Sort, search, enhanced context menu,
                                    #   template selection, sync indicators
    smart_edit/
      smart_edit_view.dart          # Aspect ratio picker, draft indicator,
                                    #   revert-to-save option
ios/
  Runner/
    Info.plist                      # UTI registration for .liquidbackup
```

---

## 16. Test Plan

### 16.1 Unit Tests

| Test File | Coverage | Priority |
|-----------|----------|----------|
| `test/core/project_management_service_test.dart` | Duplication (unique names, clip cloning, shared media, edge cases) | P0 |
| `test/core/draft_management_service_test.dart` | Ring buffer rotation, crash detection, recovery, revert, cleanup | P0 |
| `test/core/project_backup_service_test.dart` | Manifest creation, archive structure, restore with/without media | P0 |
| `test/core/storage_analysis_service_test.dart` | Size calculation, orphan detection, shared media deduplication | P1 |
| `test/core/project_template_service_test.dart` | Built-in templates, custom save/load/delete, project creation from template | P1 |
| `test/core/sync_queue_test.dart` | Queue persistence, ordering, retry logic, deduplication | P1 |
| `test/models/aspect_ratio_test.dart` | Ratio calculations, preset values, JSON serialization, export dimensions | P0 |
| `test/models/backup_manifest_test.dart` | JSON round-trip, version comparison, media entry matching | P0 |
| `test/models/project_metadata_test.dart` | New fields serialization, backward compatibility (missing fields default) | P0 |
| `test/models/draft_metadata_test.dart` | Ring buffer index rotation, JSON round-trip | P1 |

### 16.2 Integration Tests

| Test Scenario | Description | Priority |
|---------------|-------------|----------|
| Duplicate and open | Duplicate project, verify it opens correctly with all clips | P0 |
| Backup round-trip | Export full backup, delete project, restore backup, verify identical | P0 |
| Aspect ratio change | Change ratio mid-edit, verify preview updates, export at new ratio | P0 |
| Sort persistence | Set sort, kill app, relaunch, verify sort persists | P1 |
| Crash recovery | Force-kill app during editing, relaunch, verify recovery dialog | P0 |
| Search accuracy | Create 10 projects, search by partial name, verify results | P1 |
| Template round-trip | Save project as template, create new project from template, verify settings match | P1 |

### 16.3 Manual Testing Checklist

- [ ] Duplicate a project with 10+ clips and verify all clips/keyframes are independent
- [ ] Export a full backup (with media) and restore on a different device
- [ ] Export a metadata-only backup and restore (verify media-missing handling)
- [ ] Change aspect ratio from 16:9 to 9:16 with existing keyframes
- [ ] Change aspect ratio from 16:9 to 1:1 with auto-reframe keyframes
- [ ] Sort by all 8 criteria and verify correct ordering
- [ ] Search for partial project name and verify results
- [ ] Force-kill app during editing and verify crash recovery on relaunch
- [ ] Use "Revert to Last Save" and verify undo of recent changes
- [ ] Check storage usage screen with 5+ projects
- [ ] Run "Clean Up" and verify orphaned files removed
- [ ] Open a `.liquidbackup` file from Files app and verify import flow
- [ ] Create a project from each built-in template
- [ ] Save a project as custom template and create a new project from it
- [ ] Test iCloud sync between two devices (when implemented)
- [ ] Test iCloud conflict resolution with simultaneous edits
- [ ] Test all features with VoiceOver enabled (accessibility)
- [ ] Test haptic feedback on all new interactive elements

---

## Appendix A: JSON Schema Version Migration

When adding new fields to `Project.toJson()`, all fields must have defaults in `fromJson()` for backward compatibility:

```dart
// Version 2 -> 3 migration map:
// aspectRatio:      null (auto, matches v2 behavior)
// aspectRatioMode:  AspectRatioMode.letterbox
// description:      null
// tags:             []
// starRating:       0
// colorLabel:       null
// isFavorite:       false
// syncStatus:       SyncStatus.local
// iCloudChangeTag:  null
// iCloudEnabled:    false
```

The `version` field in the project JSON should be bumped to `3` when these fields are added. Migration from v2 to v3 is automatic (all new fields have safe defaults).

---

## Appendix B: SF Symbols Reference

| Feature | Symbol Name | Usage |
|---------|------------|-------|
| Duplicate | `doc.on.doc` | Context menu |
| Backup/Export | `square.and.arrow.up` | Context menu |
| Restore/Import | `square.and.arrow.down` | Import action |
| Aspect Ratio | `aspectratio` | Settings button |
| Sort | `arrow.up.arrow.down` | Sort button |
| Search | `magnifyingglass` | Search bar |
| Storage | `chart.pie` | Settings row |
| iCloud Synced | `checkmark.icloud` | Card overlay |
| iCloud Syncing | `arrow.triangle.2.circlepath.icloud` | Card overlay |
| iCloud Error | `xmark.icloud` | Card overlay |
| Template | `bookmark` | Template picker |
| Draft/Save | `clock.arrow.circlepath` | Draft indicator |
| Revert | `arrow.counterclockwise` | Menu action |
| Favorite | `heart` / `heart.fill` | Context menu / card |
| Color Label | `paintbrush` | Context menu |
| Info | `info.circle` | Context menu |
| Clean Up | `trash.circle` | Storage screen |

---

## Review 1 - Architecture & Completeness

**Reviewer:** Senior Architecture Review
**Date:** 2026-02-06
**Scope:** Full design document review against codebase reality
**Files Reviewed:** `project.dart`, `project_storage.dart`, `project_file_service.dart`, `timeline_clip.dart`, `media_asset.dart`, `clips/video_clip.dart`, `clips/timeline_item.dart`, `project_library_view.dart`, `DESIGN.md`

---

### CRITICAL Issues

#### CRITICAL-1: Duplication code references wrong clip types (V2 vs Legacy mismatch)

The duplication code in Section 3.4 operates on `TimelineClip` and `TimelineGap` from `timeline_clip.dart` (the legacy mutable model), but the codebase has **two parallel clip systems**:

1. **Legacy (`lib/models/timeline_clip.dart`):** Mutable `TimelineClip` and `TimelineGap` with `orderIndex`, `sourceVideoPath`, etc. These are what `Project.clips` currently stores.
2. **V2 (`lib/models/clips/`):** Immutable `VideoClip`, `GapClip`, `AudioClip`, `ImageClip`, `ColorClip` extending `TimelineItem`/`MediaClip`/`GeneratorClip` from `timeline_item.dart`. These use `mediaAssetId` instead of `sourceVideoPath`.

The duplication code assumes `TimelineClip` has a `copyWith(id:, keyframes:)` signature, which is correct for the legacy model. However, the V2 `VideoClip` has a different `copyWith` signature (uses `mediaAssetId` instead of `sourceVideoPath`). The design must clarify which clip system it targets, or handle both during the transition period.

**Additionally:** The legacy `TimelineClip` is **mutable** (its `keyframes`, `sourceInPoint`, `sourceOutPoint`, `isSelected`, `isDragging` are all mutable fields). The `copyWith` in the legacy model does a shallow copy of keyframes via `kf.copyWith()`, which is correct. But the duplication code's `item.copyWith(id: ..., keyframes: ...)` approach will NOT work for `TimelineGap` -- the legacy `TimelineGap.copyWith` does not accept a `keyframes` parameter, which is fine, but the code filters on `item is TimelineClip` and `item is TimelineGap` without handling `AudioClip`, `ImageClip`, or `ColorClip` from V2. If a project ever has V2 clips, duplication silently drops them (the final `return item` branch returns the original without a new ID).

**Fix:** The duplication service must handle ALL clip types from both systems, or the design must explicitly state it only supports legacy clips and add a migration path.

#### CRITICAL-2: Duplication does not clone MediaAsset references correctly

Section 3.2 states "MediaAsset entries (same asset ID references)" are shared. This is correct for the asset registry, but the design does not address WHERE the `MediaAssetRegistry` lives or how it is persisted. Looking at the codebase:

- `MediaAssetRegistry` is a `ChangeNotifier` that lives in-memory (not persisted to the project JSON).
- The `Project.toJson()` does NOT serialize `MediaAssetRegistry`.
- `VideoClip` from V2 references `mediaAssetId`, but if the registry is not project-scoped and persisted, the duplicated project's clips may reference asset IDs that don't resolve.

The design must specify:
1. Where is the `MediaAssetRegistry` persisted? Is it per-project or app-global?
2. If app-global, duplication is fine (shared references work). If per-project, the registry must be duplicated too.
3. For backup/restore (Section 4), the `MediaAssetRegistry` MUST be included in the backup archive, or restored projects will have broken asset references.

#### CRITICAL-3: Backup archive missing MediaAssetRegistry data

Section 4.2 shows the backup archive contains `project.json` and `media/` files, but `project.json` does NOT contain `MediaAssetRegistry` data (verified by reading `Project.toJson()`). If a project uses V2 clips with `mediaAssetId` references, restoring the backup will produce clips that reference non-existent assets.

**Fix:** Either:
- Add `mediaAssets` array to `project.json` in the backup, or
- Add a separate `media_assets.json` file to the backup archive, or
- Rebuild the registry from the media files present in the archive during restore.

#### CRITICAL-4: iCloud sync lacks data model for MediaAssetRegistry

Section 8 describes syncing `project.json` and media files, but does not address syncing the `MediaAssetRegistry`. On Device B, after downloading `project.json` and media files, the V2 clips will reference `mediaAssetId` values that Device B's registry does not contain. The registry must be synced alongside the project data.

---

### IMPORTANT Issues

#### IMPORTANT-1: `Project.copyWith` uses nullable wrapper pattern for `thumbnailPath` -- duplication code does not account for this

The actual `Project.copyWith` signature uses `String? Function()? thumbnailPath` (a nullable function returning nullable string) to distinguish "not provided" from "set to null". The duplication code in Section 3.4 calls `original.copyWith(id: ..., name: ..., clips: ..., timeline: ..., createdAt: ..., modifiedAt: ...)` without addressing `thumbnailPath`. This means the duplicate will inherit the original's thumbnail path, which is correct behavior (shared thumbnail), but the design should explicitly state this decision and note that if thumbnails are project-specific (e.g., regenerated from the timeline), the duplicate may show stale thumbnails after editing.

#### IMPORTANT-2: Draft `cleanShutdown` flag unreliable for iOS app termination

Section 10.9 uses `AppLifecycleState.detached` to call `markCleanShutdown()`. However, on iOS:
- `detached` is **not reliably called** when the system kills the app for memory pressure or when the user force-quits.
- `paused` fires when the app goes to background, but the app may be killed without `detached` firing.
- The draft save in `paused` state is correct, but `markCleanShutdown` in `detached` is unreliable.

**Fix:** Instead of relying on `detached`, mark clean shutdown in `paused`/`inactive` AFTER the draft save completes. Then on next launch, if the most recent draft is newer than the saved project, offer recovery regardless of the `cleanShutdown` flag. Use `cleanShutdown` as a hint, not a gate.

#### IMPORTANT-3: Aspect ratio change does not address the export pipeline

Section 5.9 shows `exportDimensions()` logic, but the actual export is handled by native Swift code in `AppDelegate.swift`. The design does not describe how the new `aspectRatio` and `aspectRatioMode` fields propagate through the platform channel to the native rendering/export pipeline. The native `CompositionBuilder.swift` likely needs modifications to handle:
- Non-source aspect ratios in the AVMutableComposition
- Letterbox/pillarbox rendering (adding black bars)
- Zoom-to-fill cropping via `AVMutableVideoComposition` layer instructions

This is a significant native-side implementation gap that is not covered.

#### IMPORTANT-4: iCloud conflict resolution 60-second window is arbitrary and fragile

Section 8.6 uses a 60-second threshold to decide between auto-resolve and user prompt. This is problematic:
- Clock skew between devices can exceed 60 seconds
- The `modifiedAt` timestamps are local device times, not server-synchronized times
- Two quick edits 30 seconds apart should still be flagged if they are on different devices

**Fix:** Use `CKRecord.recordChangeTag` (mentioned as `iCloudChangeTag` in the data model) for conflict detection instead of timestamp comparison. CloudKit provides built-in conflict detection via change tags -- use it rather than inventing a timestamp-based scheme.

#### IMPORTANT-5: Backup zip creation on background isolate cannot use `dart:io` File operations on passed file handles

Section 4.7 step 4 says "Build zip archive in background isolate." However, `compute()` in Dart runs the function in a separate isolate where `path_provider` may not work (it requires the Flutter engine's platform channel). The isolate must receive pre-resolved paths, not rely on `getApplicationDocumentsDirectory()` at runtime.

**Fix:** Resolve all file paths on the main isolate, then pass them as a data object to the background isolate for zip creation.

#### IMPORTANT-6: `_generateUniqueCopyName` loads ALL projects just to check names

Section 3.4's `_generateUniqueCopyName` calls `_storage.loadAll()` which reads and parses every project JSON file on disk. For a user with 100+ projects, this is expensive I/O just to generate a name. This should use a lighter-weight approach:
- Cache project names in memory (the library view already has them loaded)
- Or pass the existing project list as a parameter instead of re-loading

#### IMPORTANT-7: Per-project `iCloudEnabled` flag creates confusing UX when combined with global toggle

Section 8.5 adds `iCloudEnabled` per-project AND Section 8.9 has a global iCloud toggle in settings. The interaction is not specified:
- If global is ON but project is OFF: project stays local (clear)
- If global is OFF: are all per-project flags ignored? (unclear)
- Can user enable per-project sync when global is OFF? (should not be possible)

**Fix:** Define the precedence clearly: global toggle is the master switch. Per-project `iCloudEnabled` is only meaningful when global sync is enabled. When global sync is disabled, all per-project flags are ignored and no sync occurs.

#### IMPORTANT-8: Storage calculation double-counts shared media in per-project view

Section 7.5 says "If two projects reference the same video file, count it fully for each project in the per-project view but only once in the total." This means the sum of per-project usage will exceed the total usage, which will confuse users. Consider adding a note like "Shared with 2 other projects" next to the media entry in per-project view, or show "unique" vs "shared" breakdowns.

---

### MINOR Issues

#### MINOR-1: Design references `HapticFeedback.notificationOccurred(.success)` which is not valid Dart

Section 3.5 mentions `HapticFeedback.notificationOccurred(.success)`. The actual Flutter API is `HapticFeedback.heavyImpact()` or using the `flutter_haptic_feedback` package. The standard Flutter `HapticFeedback` class does not have `notificationOccurred`. For notification-type haptics, you need to use a platform channel or a package like `haptic_feedback`.

**Fix:** Use `HapticFeedback.mediumImpact()` or `HapticFeedback.heavyImpact()` from `flutter/services.dart`, or specify which haptic package to use.

#### MINOR-2: `AspectRatioSetting.cinematic` uses ratio 235:100 instead of a proper reduced fraction

The cinematic ratio is defined as `widthRatio: 235, heightRatio: 100`. While mathematically correct (235/100 = 2.35), it would be cleaner as `widthRatio: 47, heightRatio: 20` to match the convention of using smallest integers. This is a cosmetic issue -- the `value` getter produces the same double regardless.

#### MINOR-3: Template `createFromTemplate` requires `sourceVideoPath` and `videoDuration` which may not be known at template selection time

Section 9.5 shows `createFromTemplate` requires source video details. But Section 9.6 shows the UI flow as "select template, then import video." This means the template is chosen BEFORE the video is available. The service API should either:
- Accept these as optional and allow setting them later, or
- Return a "pending project" configuration that is finalized after import

The current signature works if the flow is "import video, then select template," but the UI design suggests the opposite.

#### MINOR-4: Draft metadata uses `timelineDurationMs` (milliseconds) while clips use microseconds

The V2 clip system uses microseconds throughout (`durationMicroseconds`, `sourceInMicros`, etc.). The draft metadata uses `timelineDurationMs` in milliseconds. While this is just metadata for display, it creates an inconsistency. Consider using microseconds for consistency, or explicitly documenting the unit choice.

#### MINOR-5: Search only filters by name, not by new metadata fields

Section 6.5 only searches `p.name`. Section 11.6 mentions extending search to tags, color, favorites, and rating, but does not provide implementation details or UI for filter chips/toggles. This should be fleshed out or explicitly deferred to a later phase.

#### MINOR-6: Missing `duration` field handling in `Project.fromJson`

The `Project` model has a `duration` field, but looking at `Project.fromJson()`, there is no `duration` key being parsed -- the field defaults to `Duration.zero`. The design does not mention this, and the backup manifest calculates `totalSize` but does not verify that restored projects have correct `duration` values. This could cause issues with templates that rely on `videoDuration`.

#### MINOR-7: Backup file naming uses project name which may contain filesystem-unsafe characters

Section 4.2 shows `{project-name}-backup.liquidbackup`. Project names can contain spaces, slashes, colons, and other characters that are problematic in filenames. The backup filename should be sanitized (replace unsafe characters with dashes or underscores).

#### MINOR-8: No rate limiting on iCloud sync operations

Section 8.4.2 says "Queue upload to iCloud (background)" on every local save. With auto-save firing every 2 seconds during active editing, this could queue hundreds of sync operations during a single editing session. The sync queue should debounce or coalesce uploads for the same project.

---

### QUESTIONS

#### Q1: What happens to the legacy `timeline_clip.dart` model during this implementation?

The codebase has two clip systems: legacy (`TimelineClip`/`TimelineGap` in `timeline_clip.dart`) and V2 (`VideoClip`/`GapClip`/etc. in `clips/`). The `Project.clips` field currently uses legacy `TimelineItem` from `timeline_clip.dart`. The V2 `TimelineItem` from `clips/timeline_item.dart` is a completely separate class hierarchy. Will this design:
- Work exclusively with legacy clips?
- Migrate to V2 clips as part of this work?
- Support both simultaneously?

This is the most important architectural question to resolve before implementation.

#### Q2: Should the `MediaAssetRegistry` be persisted as part of the project JSON?

Currently it is not. For backup, restore, iCloud sync, and duplication to work correctly with V2 clips, the registry data needs to be available alongside the project. Is the plan to:
- Add it to `Project.toJson()`?
- Store it in a separate file per project?
- Make it app-global and reconstruct from file system?

#### Q3: How does the backup UTI handler integrate with Flutter?

Section 4.10 registers the UTI in `Info.plist`, but Flutter apps receive file-open events through `AppDelegate` or `SceneDelegate`. The design does not describe:
- Which native delegate method handles the incoming file
- How it forwards the file path to Flutter (MethodChannel? deep link?)
- Whether the app needs to be running or can be cold-launched with the file

#### Q4: What is the plan for the `thumbnailPath` during iCloud sync?

Thumbnails are generated locally from video content. During iCloud sync:
- Are thumbnails synced? (They can be large and are regeneratable)
- If not synced, are they regenerated on the receiving device?
- What does the project card show while the thumbnail is missing/regenerating?

#### Q5: How does aspect ratio change interact with the native playback pipeline?

The `PlaybackEngineController` and `CompositionManager` build `AVComposition` objects on the native side. When aspect ratio changes, the native composition needs to be rebuilt with new video composition instructions. Is this a hot-swap operation (using the existing double-buffer system), or does it require a full pipeline restart?

#### Q6: What zip library will be used for backup creation?

Dart's standard library does not include zip support. Common options are:
- `archive` package (pure Dart, works in isolates)
- `flutter_archive` package (native, may not work in isolates)

The choice affects whether backup creation can truly run in a background isolate.

---

### Summary

| Severity | Count | Key Themes |
|----------|-------|------------|
| CRITICAL | 4 | Dual clip system mismatch, MediaAssetRegistry not persisted/synced/backed up |
| IMPORTANT | 8 | iOS lifecycle reliability, native pipeline gaps, iCloud conflict resolution, performance |
| MINOR | 8 | API inconsistencies, naming, unit mismatches, missing sanitization |
| QUESTION | 6 | Fundamental architecture decisions needed before implementation |

**Overall Assessment:** The design is thorough and well-structured across all 8 feature areas. The primary risk is the **dual clip system** (legacy vs V2) that pervades the codebase. The design was written assuming the legacy clip model, but the V2 clip system is already implemented and will be the future. The `MediaAssetRegistry` persistence gap is the second critical issue -- it affects duplication, backup, restore, and iCloud sync simultaneously. These must be resolved in the next review round before implementation begins.

**Recommendation:** Before Review Round 2, resolve Q1 and Q2 above. This will cascade into fixes for CRITICAL-1 through CRITICAL-4 and significantly de-risk the implementation plan.

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06
**Scope:** Codebase-verified implementation feasibility for all 8 feature areas
**Files Verified:** `project.dart`, `project_storage.dart`, `project_file_service.dart`, `timeline_clip.dart`, `clips/timeline_item.dart`, `clips/video_clip.dart`, `clips/gap_clip.dart`, `clips/audio_clip.dart`, `clips/image_clip.dart`, `clips/color_clip.dart`, `media_asset.dart`, `composition_manager.dart`, `CompositionPlayerService.swift`, `AppDelegate.swift`, `SceneDelegate.swift`, `VideoProcessingService.swift`, `Info.plist`, `project_library_view.dart`, `smart_edit_view_model.dart`, `glass_styles.dart`, `DESIGN.md`, `pubspec.yaml`

---

### Codebase Verification Results

#### V1: Project Model -- VERIFIED with caveats

The `Project` model at `lib/models/project.dart` matches the design document's Section 2.1 description precisely. Key verification points:

- **`copyWith` signature confirmed.** The `copyWith` method supports `id`, `name`, `clips`, `timeline`, `createdAt`, `modifiedAt` parameters as assumed by the duplication code. The nullable wrapper pattern for `thumbnailPath` (uses `String? Function()?`) and `outPoint` (uses `Duration? Function()?`) is confirmed. The duplication code in Section 3.4 omits `thumbnailPath`, which means the duplicate inherits the original's thumbnail -- this is acceptable for shared-media duplication since the thumbnail depicts the same video.

- **`clips` field uses `List<TimelineItem>` from `timeline_clip.dart` (legacy).** The `Project.clips` field is typed as `List<TimelineItem>` imported from `lib/models/timeline_clip.dart`. This is the LEGACY mutable clip system. The V2 `TimelineItem` from `lib/models/clips/timeline_item.dart` is a completely separate, immutable class hierarchy. These two `TimelineItem` types have **identical simple names but different import paths, different fields, and different serialization formats**. This is the single largest integration risk in the entire design.

- **`toJson`/`fromJson` round-trip confirmed.** The JSON serialization uses `'type': 'clip'` / `'type': 'gap'` discriminators for legacy clips, while V2 uses `'itemType': 'video'` / `'itemType': 'gap'` etc. These two formats are **incompatible** -- a project saved with V2 clips cannot be loaded by the legacy `TimelineItem.fromJson`.

- **New fields (aspectRatio, description, tags, etc.) can be added safely.** The `fromJson` method uses named parameters with defaults, so adding new optional fields with safe defaults is backward-compatible. The `copyWith` method accepts explicit new parameters. The schema version can be bumped from 2 to 3.

**Risk: HIGH.** The dual `TimelineItem` class hierarchy is a class-name collision that will cause import ambiguity and type errors during implementation.

#### V2: ProjectStorage -- VERIFIED, viable

The `ProjectStorage` class at `lib/core/project_storage.dart` is a clean singleton with atomic write support. Verification:

- **`save(project)` and `load(id)` work correctly** for the duplication use case. The duplication code can call `_storage.load(projectId)` then `_storage.save(duplicate)` without issues.
- **`loadAll()` is expensive** -- it reads and parses every JSON file on disk. The design's `_generateUniqueCopyName` calls this method. For 100 projects, this is roughly 100 file reads + JSON parses just to check name uniqueness. Review 1 flagged this (IMPORTANT-6). **Confirmed: there is no in-memory cache of project names.** The `_ProjectLibraryViewState._projects` list holds loaded projects in the widget state, but this is not accessible from the service layer.
- **`scheduleAutoSave` confirmed** with 2-second debounce using `Timer`. The `SmartEditViewModel._onKeyframeChange()` calls `_saveProject()` which calls `ProjectStorage.shared.scheduleAutoSave(project)` (confirmed via grep at line 1124-1125 of `smart_edit_view_model.dart`). The draft system can wrap this existing mechanism.
- **ID sanitization** via UUID regex is solid -- prevents path traversal.

**Risk: LOW.** The storage layer is clean and extensible.

#### V3: ProjectLibraryView -- VERIFIED, scaffolded for enhancements

The `ProjectLibraryView` at `lib/views/library/project_library_view.dart` was verified against the design:

- **Context menu confirmed** at lines 839-875. The Duplicate action is scaffolded with `// TODO: Implement duplicate functionality` at line 853. The Rename action is similarly stubbed at line 861. Integration points are ready.
- **Sort button confirmed** at line 186-188 with `// TODO: Sort action` handler. The `CupertinoSliverNavigationBar` trailing button is in place.
- **No search bar currently exists.** The design proposes adding a `CupertinoSearchTextField` as a `SliverToBoxAdapter`. This requires inserting a new sliver between the navigation bar and the grid. Feasible, but note that `CupertinoSliverNavigationBar` already provides a `largeTitle` collapsing effect -- the search bar must be positioned below this, not inside it, to avoid layout conflicts.
- **Grid delegate uses `childAspectRatio: 0.8`** (line 277). When color labels and sync indicators are added to the card, the aspect ratio may need adjustment to prevent overflow.
- **`_PremiumProjectCard` does not have `onDuplicate` callback.** The design's Section 3.5 references `widget.onDuplicate?.call()`, but the current card widget only has `onTap` and `onDelete` callbacks. A new `onDuplicate` callback must be added, or the duplication should trigger a reload via a different mechanism (e.g., listening to `ProjectStorage` changes).

**Risk: LOW-MEDIUM.** The UI scaffolding is solid. Adding callbacks and new slivers is straightforward, but the `_PremiumProjectCard` is currently private and has limited callbacks.

#### V4: CompositionManager and Native Playback -- VERIFIED, significant gap for aspect ratio

The `CompositionManager` at `lib/core/composition_manager.dart` takes a `MediaAssetRegistry` and builds compositions via platform channel `'com.liquideditor/composition'`. The native `CompositionPlayerService.swift` builds `AVMutableComposition` from `CompositionClip` structs.

- **No aspect ratio handling exists** in either the Dart `CompositionManager` or the Swift `CompositionPlayerService`. The `CompositionClip` struct has only `sourceVideoPath`, `sourceInPointMs`, `sourceOutPointMs`, `orderIndex`. There is no field for target aspect ratio, letterbox mode, or crop parameters.
- **The native composition builder does not apply `AVMutableVideoComposition`** for layer-level transforms. Currently it inserts track segments directly into an `AVMutableComposition`, which uses the source video's natural dimensions. To implement aspect ratio changes:
  1. An `AVMutableVideoComposition` with `AVMutableVideoCompositionInstruction` and `AVMutableVideoCompositionLayerInstruction` must be created.
  2. Each layer instruction must apply `setTransform(_:at:)` to scale/translate the source video into the target frame.
  3. The `renderSize` property on the `AVMutableVideoComposition` must be set to the target aspect ratio dimensions.
  4. This is a significant addition to the native pipeline (~200-300 lines of Swift) and has not been estimated in the implementation plan.

- **The `VideoTransformCalculator.swift` exists** in `ios/Runner/` and handles transform calculations for keyframe-based editing. This could be extended for aspect ratio adaptation, but it currently operates on per-frame transforms, not composition-level layout.

**Risk: HIGH.** The native pipeline requires non-trivial Swift additions for aspect ratio support. This is underestimated in the Phase 2 plan (listed as "Medium" complexity). It should be "High" complexity and may need its own sub-phase.

#### V5: Native File Handling for Backup/Restore -- VERIFIED, feasible with limitations

- **`Info.plist` verified** -- no UTI declarations exist currently. The design's Section 4.10 UTI registration can be added cleanly.
- **`SceneDelegate.swift`** extends `FlutterSceneDelegate` but does NOT override `scene(_:openURLContexts:)`. This method is required to handle incoming `.liquidbackup` files when the app receives them via AirDrop, Files, or email. The design does not specify this integration point (confirmed by Review 1 Q3). **This override must be added to `SceneDelegate.swift`**, forwarding the file URL to Flutter via a MethodChannel.
- **The `AppDelegate.swift` uses `FlutterImplicitEngineDelegate` (UIScene lifecycle).** This means `application(_:open:options:)` on AppDelegate is NOT called for file opens -- it must go through `SceneDelegate.scene(_:openURLContexts:)`.
- **No zip library in `pubspec.yaml`.** The `pubspec.yaml` does not include any archive/zip package. The `archive` package (pure Dart, works in isolates) is the correct choice. The `flutter_archive` package uses native code and may have threading issues in background isolates. **Action item: add `archive: ^3.x` to `pubspec.yaml`.**

**Risk: MEDIUM.** The UTI registration and zip library are standard additions. The SceneDelegate file-open handler is the gap that must be implemented.

#### V6: MediaAssetRegistry Persistence -- VERIFIED, confirmed NOT persisted

The `MediaAssetRegistry` class at `lib/models/media_asset.dart` is a `ChangeNotifier` that maintains in-memory maps (`_assetsById`, `_idByHash`). Key findings:

- **`toJson()` and `fromJson()` methods exist** on `MediaAssetRegistry` (lines 424-439). The registry CAN be serialized.
- **`Project.toJson()` does NOT serialize the registry.** The `Project` class has no reference to `MediaAssetRegistry`.
- **`CompositionManager` receives the registry as a constructor parameter.** This means the registry is managed at a higher level, likely the view model or a controller.
- **The V2 clips (`VideoClip`, `AudioClip`, `ImageClip`) reference `mediaAssetId`**, which resolves against the registry. If the registry is lost, these clips have dangling references.

For **duplication**: If projects use only legacy clips (which reference `sourceVideoPath` directly), no registry is needed. If V2 clips are used, the registry MUST be either (a) persisted alongside the project or (b) reconstructable from the media files on disk (by re-scanning and re-hashing).

For **backup/restore**: The registry MUST be included. The design should add a `media_assets.json` to the backup archive.

For **iCloud sync**: The registry must be synced alongside the project JSON.

**Risk: CRITICAL (confirming Review 1 CRITICAL-2, CRITICAL-3, CRITICAL-4).** The registry has serialization support but no persistence mechanism. This must be resolved before implementing any feature that involves V2 clips.

#### V7: Auto-Save and Lifecycle -- VERIFIED with iOS concern

- **Auto-save confirmed** via `ProjectStorage.scheduleAutoSave()` with 2-second debounce. Used by `SmartEditViewModel`.
- **No `WidgetsBindingObserver` implementation exists** in the current codebase. The `SmartEditView` and `SmartEditViewModel` do not observe app lifecycle changes. The draft management design requires `didChangeAppLifecycleState` -- this is a new addition, not a modification.
- **Review 1 IMPORTANT-2 confirmed**: `AppLifecycleState.detached` is unreliable on iOS. The `SmartEditViewModel.dispose()` (line 1122-1125) calls `ProjectStorage.shared.cancelAutoSave()` -- this cancels pending saves but does NOT perform a final save. If the user force-quits while a save is pending, data is lost. The draft system's `appBackground` trigger in `paused` state would fix this, but only if implemented.
- **`SceneDelegate.sceneDidEnterBackground`** fires reliably on iOS when the app backgrounds. This could be used as an alternative to Flutter's lifecycle observer for native-triggered saves, but it would require a MethodChannel callback to Flutter.

**Risk: MEDIUM.** The lifecycle integration is straightforward but requires careful ordering: save draft first, then mark clean shutdown, all within the `paused`/`inactive` window.

#### V8: iCloud Sync Path -- VERIFIED, large scope

- **No iCloud entitlements exist.** The `ios/Runner/Runner.entitlements` file (if it exists) does not contain `com.apple.developer.icloud-container-identifiers` or `com.apple.developer.ubiquity-container-identifiers`. These must be configured in Xcode capabilities.
- **No `NSMetadataQuery` usage** exists in the Swift codebase. This is entirely new native code.
- **The `AppDelegate` already manages multiple services** (`compositionPlayerService`, `compositionManagerService`, `nativeDecoderPool`, `trackingService`, `peopleMethodChannel`, `videoProcessingService`). Adding `iCloudSyncService` follows the same pattern.
- **The platform channel pattern is well-established.** Adding `com.liquideditor/icloud_sync` follows existing patterns (see `com.liquideditor/video_processing`, `com.liquideditor/tracking`, etc.).

**Risk: HIGH (scope, not feasibility).** iCloud sync is architecturally feasible following existing patterns, but the implementation scope is the largest of any feature in this design (3-4 weeks for Phase 4). The conflict resolution, offline queue, and bandwidth management add significant complexity.

---

### Integration Risk Assessment

| Feature | Feasibility | Integration Risk | Blocking Issues |
|---------|-------------|-----------------|-----------------|
| **Project Duplication** | HIGH | LOW | Dual clip system (if V2 clips used) |
| **Backup/Restore** | HIGH | MEDIUM | Missing registry persistence, missing SceneDelegate handler, no zip library |
| **Aspect Ratio Change** | MEDIUM | HIGH | Native pipeline requires AVMutableVideoComposition additions; no existing aspect ratio plumbing |
| **Project Sorting & Search** | HIGH | LOW | None -- purely additive UI changes |
| **Storage Usage Display** | HIGH | LOW | None -- standard background isolate pattern |
| **iCloud Sync** | MEDIUM | HIGH | No entitlements, no NSMetadataQuery experience in codebase, registry sync gap |
| **Project Templates** | HIGH | LOW | Depends on AspectRatioSetting model being implemented first |
| **Draft Management** | HIGH | LOW-MEDIUM | Lifecycle observer not yet implemented; ring buffer is new but simple |
| **Project Metadata** | HIGH | LOW | Simple additive fields with defaults |

---

### Critical Findings

#### CRITICAL-5: Two incompatible `TimelineItem` class hierarchies with identical names will cause implementation chaos

This is the most urgent finding, expanding on Review 1 CRITICAL-1. The codebase has:

1. **Legacy `TimelineItem`** (`lib/models/timeline_clip.dart` line 11): Abstract class with `String id`, mutable `int orderIndex`, abstract `Duration get duration`. Subtypes: `TimelineClip` (mutable, has `sourceVideoPath`, `keyframes`, `isSelected`, `isDragging`) and `TimelineGap` (mutable `_duration`). Serialization uses `'type': 'clip'` / `'type': 'gap'`.

2. **V2 `TimelineItem`** (`lib/models/clips/timeline_item.dart` line 24): Immutable abstract class with `String id`, abstract `int get durationMicroseconds`. Subtypes: `VideoClip` (immutable, uses `mediaAssetId`, microsecond precision), `AudioClip`, `ImageClip` (both `MediaClip` subtypes), `GapClip`, `ColorClip` (both `GeneratorClip` subtypes). Serialization uses `'itemType': 'video'` / `'itemType': 'gap'` etc.

**The `Project.clips` field currently uses Legacy `TimelineItem`.** Any file that imports both `project.dart` and any V2 clip type will face name collisions. The `import 'timeline_clip.dart'` in `project.dart` (line 19) brings the legacy `TimelineItem` into scope.

**Recommendation:** Before starting Phase 1, either:
- (a) Rename the legacy types to `LegacyTimelineItem`, `LegacyTimelineClip`, `LegacyTimelineGap` to avoid collision, OR
- (b) Migrate `Project.clips` to use V2 `List<clips.TimelineItem>` and update `toJson`/`fromJson` to use the V2 serialization format (with a migration path from the legacy format), OR
- (c) Scope Phase 1-3 to legacy clips ONLY and defer V2 integration to Phase 4.

Option (b) is the cleanest long-term choice. Option (c) defers risk but accumulates debt.

#### CRITICAL-6: V2 clip `duplicate()` methods do NOT deep-clone keyframes

Each V2 clip type has a `duplicate()` method. Examining `VideoClip.duplicate()` (line 247-254):

```dart
VideoClip duplicate() => VideoClip(
    id: const Uuid().v4(),
    mediaAssetId: mediaAssetId,
    sourceInMicros: sourceInMicros,
    sourceOutMicros: sourceOutMicros,
    keyframes: keyframes,  // <-- SHALLOW COPY of keyframe list
    name: name != null ? '$name (copy)' : null,
);
```

The `keyframes` list is passed by reference. Since `Keyframe` objects are `@immutable`, this is technically safe (no mutation possible). However, the duplicate and original share the SAME `Keyframe` instances with the SAME IDs. If the duplication design requires new UUIDs for keyframes (Section 3.2 states "All clip IDs and keyframe IDs (new UUIDs to prevent cross-project conflicts)"), then `duplicate()` does NOT satisfy this requirement.

The duplication service must explicitly remap keyframe IDs even when using V2 clips. The design's Section 3.4 code handles this for legacy clips but not for V2 clips.

---

### Important Findings

#### IMPORTANT-9: `_PremiumProjectCard` is a private widget with no `onDuplicate` callback

The card widget (line 652-660) accepts only `project`, `onTap`, and `onDelete`. The design's Section 3.5 references `widget.onDuplicate?.call()` which does not exist. Options:
1. Add `onDuplicate` callback to `_PremiumProjectCard` constructor -- requires also updating `_buildProjectsTab` to pass the callback.
2. Trigger reload via `_loadProjects()` from the parent -- but the context menu action runs inside the card's state, so it needs a way to notify the parent.

**Recommendation:** Add `VoidCallback? onDuplicate` to `_PremiumProjectCard` and pass `_loadProjects` from the parent.

#### IMPORTANT-10: Backup zip creation requires pre-resolved paths for background isolate

Confirmed by code analysis: `ProjectFileService` uses `getApplicationDocumentsDirectory()` which calls a platform channel. Platform channels are NOT available in `compute()` isolates. The backup creation must:
1. Resolve all file paths on the main isolate.
2. Pass resolved absolute paths to the background isolate.
3. The background isolate uses `dart:io` `File` operations with absolute paths only (this works fine).

Additionally, the `archive` Dart package (`archive: ^3.x`) works in isolates since it is pure Dart. This is confirmed as the correct dependency choice.

#### IMPORTANT-11: Storage calculation must handle shared media deduplication carefully

The `_PremiumProjectCard._loadData()` method (line 678-705) already resolves video paths via `'${docsDir.path}/${widget.project.sourceVideoPath}'`. The `StorageAnalysisService` can use the same pattern. However, two projects referencing `Videos/abc.mov` should count that file only once in the total. The service must:
1. Collect all referenced media paths across all projects.
2. Deduplicate by absolute path (not by content hash -- content hash requires reading file data).
3. `stat()` each unique file once.

The design's per-project view counting shared media fully for each project is confirmed as potentially confusing (Review 1 IMPORTANT-8). The UI should show a "shared" indicator.

#### IMPORTANT-12: Aspect ratio change must propagate through three separate render paths

The codebase has THREE render paths, all of which need aspect ratio awareness:

1. **Preview playback** -- `CompositionPlayerService.swift` builds `AVComposition` for the native `AVPlayerLayer`. Aspect ratio requires `AVMutableVideoComposition` with layer instructions.
2. **Scrub/thumbnail generation** -- `VideoProcessingService.swift` generates thumbnails via `AVAssetImageGenerator`. For aspect ratio changes, the generated thumbnails should reflect the target frame (with letterbox/crop applied). Currently `maximumSize` is hardcoded to `VideoConstants.thumbnailMaxSize`.
3. **Export rendering** -- `VideoProcessingService.swift` exports with transforms via `AVAssetExportSession` or `AVAssetWriter`. The export dimensions must match the selected aspect ratio.

The design only addresses export dimensions (Section 5.9). The preview and thumbnail paths are not addressed.

#### IMPORTANT-13: Draft ring buffer must not interfere with existing auto-save

The current auto-save system in `ProjectStorage.scheduleAutoSave()` writes to `Projects/{uuid}.json`. The draft system writes to `Drafts/{uuid}/draft_N.json`. These are separate paths, so they will NOT conflict. However, the coordination must ensure:
1. The draft save happens BEFORE the main save (so the draft captures the state at the moment of the trigger).
2. Or the draft save and main save capture the same state (write both atomically).

The design implies drafts are a REPLACEMENT for the auto-save mechanism (Section 10.2: "this enhancement adds a ring buffer of recent saves"). If so, `ProjectStorage.scheduleAutoSave()` should be redirected to `DraftManagementService.saveDraft()` which writes to BOTH the draft ring buffer AND the main `Projects/{uuid}.json`. Otherwise, the two systems diverge.

**Recommendation:** `DraftManagementService.saveDraft()` should:
1. Write to the ring buffer slot.
2. Also call `ProjectStorage.save()` for the canonical save.
3. Replace `scheduleAutoSave` in `SmartEditViewModel` with `DraftManagementService.scheduleDraftSave()`.

#### IMPORTANT-14: Template `createFromTemplate` flow has a temporal ordering problem

Confirmed by Review 1 MINOR-3. The template picker UI (Section 9.6) shows "select template, then import video" flow. But `createFromTemplate` requires `sourceVideoPath` and `videoDuration` which are only known after import. The current import flow in `_importVideo()` (project_library_view.dart lines 484-613) creates the project with hardcoded `FrameRateOption.auto` and no aspect ratio.

**Solution path:** The template selection should produce a `ProjectTemplate` object that is held in state. The `_importVideo()` method then uses it when creating the `Project`. The `createFromTemplate` method should accept video details as late parameters:

```dart
// Step 1: User selects template (before import)
final template = await _showTemplateSelector();
// Step 2: User picks video
final video = await picker.pickVideo(...);
// Step 3: Create project with template + video details
final project = templateService.createFromTemplate(
    template: template,
    projectName: 'New Project',
    sourceVideoPath: relativePath,
    videoDuration: duration,
);
```

This two-step flow is feasible and the design's API already supports it.

---

### Minor Findings

#### MINOR-9: Legacy `TimelineClip` has mutable state that complicates duplication

The legacy `TimelineClip` has mutable fields: `sourceInPoint`, `sourceOutPoint`, `keyframes`, `isSelected`, `isDragging` (lines 48-63 of `timeline_clip.dart`). When duplicating, the `copyWith` correctly creates a new instance, but if any code holds a reference to the original clip's `keyframes` list and mutates it, the duplicate's list could be affected (since `copyWith` does `this.keyframes.map((kf) => kf.copyWith()).toList()` which creates new `Keyframe` objects).

The V2 `VideoClip` is `@immutable`, which is inherently safer.

#### MINOR-10: `HapticManager.notification(NotificationType.warning)` in project_library_view.dart

The codebase uses a custom `HapticManager` class (line 930 of `glass_styles.dart`) with custom `NotificationType` enum. The design references `HapticFeedback.notificationOccurred(.success)` which is not the API used by the codebase. The design's haptic calls should use `HapticManager.shared.notification(NotificationType.success)` for consistency with existing code.

#### MINOR-11: `_deleteProject` does not delete media files or thumbnails

The current `_deleteProject` method (lines 623-649 of `project_library_view.dart`) only calls `_storage.delete(project.id)` which deletes the JSON file. It does NOT delete the source video file in `Videos/`. This means "orphaned files" already accumulate in the current system. The `StorageAnalysisService.findOrphanedFiles()` method will need to detect these.

#### MINOR-12: No existing settings screen to host Storage and iCloud UI

The design's Sections 7.6 and 8.9 assume a settings screen with `CupertinoListSection.insetGrouped` rows. There is no settings screen in the current codebase (`lib/views/` contains only `smart_edit/`, `library/`, and `export/`). A new `lib/views/settings/settings_view.dart` must be created, along with a navigation path from the library view.

---

### Action Items for Review 3

| # | Action | Owner | Priority | Blocks |
|---|--------|-------|----------|--------|
| A1 | **Resolve the dual clip system question** (Review 1 Q1). Decision: implement against legacy clips only, or migrate `Project.clips` to V2 first? This cascades to ALL features. | Architecture Lead | P0 | Phase 1-4 |
| A2 | **Add `MediaAssetRegistry` persistence to `Project`** (or a sidecar file). Implement `toJson`/`fromJson` integration. This unblocks backup, restore, iCloud sync for V2 clips. | Architecture Lead | P0 | Phase 3, 4 |
| A3 | **Estimate native Swift work for aspect ratio** in `CompositionPlayerService.swift`. Build a spike with `AVMutableVideoComposition` + `AVMutableVideoCompositionLayerInstruction` for letterbox and zoom-to-fill modes. | iOS Lead | P0 | Phase 2 |
| A4 | **Add `scene(_:openURLContexts:)` to `SceneDelegate.swift`** for `.liquidbackup` file handling. Define the MethodChannel contract for forwarding file URLs to Flutter. | iOS Lead | P1 | Phase 3 |
| A5 | **Add `archive` package to `pubspec.yaml`** and verify it works in a `compute()` isolate with pre-resolved paths. Build a minimal spike. | Dart Lead | P1 | Phase 3 |
| A6 | **Add iCloud entitlements** to the Xcode project. Verify iCloud container access in a simple test. | iOS Lead | P1 | Phase 4 |
| A7 | **Create settings view scaffold** (`lib/views/settings/settings_view.dart`) with navigation from library. Needed for Storage and iCloud settings UI. | UI Lead | P2 | Phase 3, 4 |
| A8 | **Add `onDuplicate` callback to `_PremiumProjectCard`** or refactor card to support arbitrary context menu actions via a callback map. | UI Lead | P2 | Phase 1 |
| A9 | **Define draft/auto-save coordination strategy.** Should `DraftManagementService` replace `ProjectStorage.scheduleAutoSave()`, or wrap it? Document in the design. | Architecture Lead | P1 | Phase 2 |
| A10 | **Update Phase 2 complexity estimates.** Aspect ratio native pipeline work should be rated "High" not "Medium". Consider splitting into Phase 2a (Dart model + picker UI) and Phase 2b (native pipeline + export). | PM | P1 | Phase 2 |
| A11 | **Review 3 scope: End-to-end data flow verification.** Trace a complete backup-export-restore cycle through all layers (Dart model -> JSON -> zip -> UTI -> SceneDelegate -> MethodChannel -> Flutter -> restore). Verify the iCloud sync data flow similarly. | Senior Architect | P0 | Phase 3, 4 |

---

### Summary

| Severity | Count | Key Themes |
|----------|-------|------------|
| CRITICAL | 2 | Dual clip hierarchy name collision (CRITICAL-5), V2 keyframe duplication gap (CRITICAL-6) |
| IMPORTANT | 6 | Native aspect ratio pipeline (IMPORTANT-12), card callback gap (IMPORTANT-9), path resolution in isolates (IMPORTANT-10), storage dedup UX (IMPORTANT-11), draft/auto-save coordination (IMPORTANT-13), template flow ordering (IMPORTANT-14) |
| MINOR | 4 | Mutable legacy clips (MINOR-9), haptic API mismatch (MINOR-10), orphan file accumulation (MINOR-11), missing settings screen (MINOR-12) |
| ACTION ITEMS | 11 | 3 at P0, 4 at P1, 4 at P2 |

**Overall Assessment:** The design is implementable. The Dart-side features (duplication, sorting, search, templates, drafts, metadata) can proceed with low risk using the existing legacy clip system. The two HIGH-risk features are:

1. **Aspect Ratio Change** -- requires significant native Swift work that is currently unestimated. The Dart model and UI are straightforward; the native `AVMutableVideoComposition` integration across preview, scrub, and export pipelines is the bottleneck.

2. **iCloud Sync** -- architecturally feasible but scope is large. The entitlements, NSMetadataQuery, conflict resolution, and offline queue represent 3-4 weeks of work, matching the Phase 4 estimate.

The most impactful pre-implementation decision remains **A1 (which clip system to target)**. If the team targets legacy clips only for Phase 1-3, all eight features become viable with the caveat that V2 migration is deferred. If the team migrates to V2 clips first, the `MediaAssetRegistry` persistence (A2) becomes a hard prerequisite.

**Recommendation for Review 3:** Resolve A1 and A2, then trace the end-to-end data flow for backup/restore and iCloud sync (A11) to verify no additional gaps exist in the serialization chain.

---

**Last Updated:** 2026-02-06

**Maintained By:** Development Team

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06
**Scope:** Final sign-off review. Resolution paths for all criticals, risk register, implementation checklist, test plan, remaining gaps.
**Files Verified (Re-read):** `project.dart`, `project_storage.dart`, `project_library_view.dart`, `media_asset.dart`, `timeline_clip.dart`, `clips/video_clip.dart`, `clips/gap_clip.dart`, `clips/audio_clip.dart`, `clips/image_clip.dart`, `clips/color_clip.dart`, `keyframe.dart`

---

### Critical Issues Status

All six critical issues from R1 and R2 are assessed below with concrete resolution paths.

#### C1 (R1 CRITICAL-1): Duplication code references wrong clip types -- RESOLUTION PATH DEFINED

**Status:** Resolvable. The duplication service in Section 3.4 operates on legacy `TimelineClip`/`TimelineGap` from `timeline_clip.dart`. This is correct for the CURRENT state of `Project.clips`, which imports from `timeline_clip.dart` (line 19 of `project.dart`). The code as written will work for all projects that exist today.

**Resolution:** Implement Phase 1 duplication targeting legacy clips ONLY. Add a `TODO` marker and guard clause:

```dart
// In duplicateProject():
final clonedClips = original.clips.map((item) {
  if (item is TimelineClip) {
    return item.copyWith(
      id: const Uuid().v4(),
      keyframes: item.keyframes.map((kf) => kf.copyWith(id: const Uuid().v4())).toList(),
    );
  }
  if (item is TimelineGap) {
    return item.copyWith(id: const Uuid().v4());
  }
  // Guard: if V2 clips are ever mixed in, fail loudly rather than silently dropping
  throw UnsupportedError('Duplication of ${item.runtimeType} not yet supported. '
      'Migrate to V2 duplication handler.');
}).toList();
```

When V2 migration occurs (separate effort), update to use each clip type's `duplicate()` method with keyframe ID remapping.

**Verdict:** RESOLVED for Phase 1 scope. V2 support deferred.

#### C2 (R1 CRITICAL-2): Duplication does not clone MediaAssetRegistry correctly -- RESOLUTION PATH DEFINED

**Status:** Non-blocking for Phase 1. The legacy `TimelineClip` uses `sourceVideoPath` (a string) -- it does NOT use `mediaAssetId`. Therefore, duplication of legacy clips does not require `MediaAssetRegistry` at all. The shared media file references work via shared file paths, exactly as the design describes.

**Resolution:** For Phase 1, no registry action needed. When V2 clips are adopted, the registry must be persisted as a sidecar file (`{uuid}_assets.json`) alongside the project JSON. The `MediaAssetRegistry` already has `toJson()`/`fromJson()` methods (verified at lines 424-439 of `media_asset.dart`), so persistence is a straightforward addition to `ProjectStorage`.

**Verdict:** RESOLVED for Phase 1. Registry persistence required before V2 clip adoption.

#### C3 (R1 CRITICAL-3): Backup archive missing MediaAssetRegistry data -- RESOLUTION PATH DEFINED

**Status:** Non-blocking for Phase 3 if Phase 3 ships before V2 clip migration. Legacy clips reference media by `sourceVideoPath`, and the backup archive includes media files mapped by `originalPath` in the manifest. Restoration reconstructs the project from `project.json` and copies media files to `Videos/` -- the legacy clips will resolve correctly.

**Resolution:** Add a forward-compatible slot in the backup archive format:

```
{project-name}-backup.liquidbackup
  manifest.json
  project.json
  media_assets.json          # OPTIONAL - present when project uses V2 clips
  media/
    ...
  thumbnails/
    ...
```

In the `BackupManifest`, add:
```dart
final bool includesAssetRegistry;  // default false for v1 backups
```

On restore, if `media_assets.json` is present, load it into the registry. If absent (legacy backup), skip -- legacy clips don't need it.

**Verdict:** RESOLVED with forward-compatible archive format. Implementation cost: ~20 lines.

#### C4 (R1 CRITICAL-4): iCloud sync lacks data model for MediaAssetRegistry -- RESOLUTION PATH DEFINED

**Status:** Deferred. iCloud sync is Phase 4 (weeks 7-10). By that time, the team must have resolved A1 (clip system decision) and A2 (registry persistence). The sync service should sync whatever files exist alongside the project JSON, including `{uuid}_assets.json` if present.

**Resolution:** The iCloud sync design should treat the project as a "project bundle" consisting of:
1. `{uuid}.json` -- project data
2. `{uuid}_assets.json` -- asset registry (if V2 clips used)
3. Media files referenced by the project

The sync service uploads/downloads all bundle files atomically. This is a minor refinement to Section 8.4 that does not change the architecture.

**Verdict:** RESOLVED in principle. Implementation deferred to Phase 4 prerequisites.

#### C5 (R2 CRITICAL-5): Two incompatible `TimelineItem` class hierarchies -- RESOLUTION PATH DEFINED

**Status:** The most important architectural decision. After reviewing both hierarchies:

- Legacy `TimelineItem` (in `timeline_clip.dart`): Mutable, uses `Duration` for timing, `sourceVideoPath` for media, `'type': 'clip'/'gap'` JSON discriminator.
- V2 `TimelineItem` (in `clips/timeline_item.dart`): Immutable, uses microseconds for timing, `mediaAssetId` for media, `'itemType': 'video'/'gap'/...` JSON discriminator.

The `Project.clips` field currently uses legacy `TimelineItem` exclusively. The V2 system is implemented but NOT wired into `Project` yet.

**Resolution (Recommended: Option C from R2):** Scope Phase 1-3 to legacy clips ONLY. This is the pragmatic choice because:
1. All existing projects use legacy clips.
2. The V2 system is complete but not yet integrated into `Project`.
3. Migrating `Project.clips` to V2 is a separate, high-risk refactoring effort that should not be coupled with feature work.
4. Every feature in Phases 1-3 works correctly with legacy clips.

To prevent accidental import collisions during implementation, add a lint rule or doc comment:
```dart
// In project.dart:
// IMPORTANT: This file uses TimelineItem from timeline_clip.dart (legacy).
// Do NOT import from clips/timeline_item.dart in this file.
import 'timeline_clip.dart';
```

**Verdict:** RESOLVED via scoping decision. Phase 1-3 = legacy clips. V2 migration is a separate workstream.

#### C6 (R2 CRITICAL-6): V2 clip `duplicate()` methods do NOT deep-clone keyframes -- RESOLUTION PATH DEFINED

**Status:** Confirmed. `VideoClip.duplicate()` (line 247-254 of `video_clip.dart`) passes `keyframes: keyframes` by reference. Since `Keyframe` is `@immutable` (confirmed at line 281 of `keyframe.dart`), there is no mutation risk. However, the original and duplicate share identical keyframe IDs, violating the design requirement that "All clip IDs and keyframe IDs (new UUIDs to prevent cross-project conflicts)."

This is NOT blocking for Phase 1 (which uses legacy clips and the design's explicit deep-clone code), but it WILL be blocking when V2 clips are adopted.

**Resolution:** When V2 clips are wired into duplication, the service must NOT use `VideoClip.duplicate()` directly. Instead:

```dart
// For V2 clips, use copyWith with remapped keyframes:
final cloned = videoClip.copyWith(
  id: const Uuid().v4(),
  keyframes: videoClip.keyframes.map((kf) => kf.copyWith(id: const Uuid().v4())).toList(),
);
```

Additionally, the V2 `duplicate()` methods should be patched to remap keyframe IDs as a separate maintenance task (affects `VideoClip` only, since `AudioClip`, `ImageClip`, `GapClip`, `ColorClip` do not have keyframes).

**Verdict:** RESOLVED for Phase 1 (not applicable). Fix required before V2 adoption.

---

### Critical Issues Summary

| ID | Status | Blocking Phase | Resolution |
|----|--------|---------------|------------|
| C1 | RESOLVED | None (Phase 1 scoped to legacy) | Guard clause + throw on unknown clip types |
| C2 | RESOLVED | V2 migration | Registry persistence as sidecar file |
| C3 | RESOLVED | None (forward-compatible archive) | Optional `media_assets.json` in backup |
| C4 | DEFERRED | Phase 4 prerequisite | Project bundle sync approach |
| C5 | RESOLVED | None (scoping decision) | Phase 1-3 target legacy clips only |
| C6 | RESOLVED | V2 migration | Use `copyWith` with remapped keyframe IDs |

**All six criticals have defined resolution paths. No criticals block Phase 1-3 implementation.**

---

### Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| R1 | V2 clip migration occurs mid-implementation, invalidating Phase 1-3 code | LOW | HIGH | Scope decision locks Phase 1-3 to legacy clips. V2 migration is a separate workstream. Do not merge V2 migration during Phase 1-3 implementation. |
| R2 | `_generateUniqueCopyName` calling `loadAll()` causes visible latency for users with 100+ projects | MEDIUM | LOW | Pass cached project list from library view state instead of re-loading. Fallback: `loadAll()` is ~50ms for 100 small JSON files -- acceptable but suboptimal. |
| R3 | `AppLifecycleState.detached` not firing on iOS force-quit causes false crash recovery prompts | HIGH | LOW | Use timestamp comparison (draft newer than saved project) as the primary recovery trigger, with `cleanShutdown` as a secondary hint. This over-recovers (may offer recovery when not needed) but never loses data. |
| R4 | Native `AVMutableVideoComposition` for aspect ratio is more complex than estimated | HIGH | MEDIUM | Split Phase 2 into 2a (Dart model + picker UI) and 2b (native pipeline). Phase 2a can ship independently. Phase 2b requires iOS lead spike. |
| R5 | Backup zip creation in isolate fails due to path resolution issues | MEDIUM | MEDIUM | Pre-resolve all absolute paths on main isolate before passing to `compute()`. Verify `archive` package works in isolate with spike test (A5). |
| R6 | iCloud sync scope exceeds Phase 4 estimate (3-4 weeks) | HIGH | MEDIUM | Implement in sub-phases: 4a (templates, metadata -- 1 week), 4b (iCloud availability + project JSON sync -- 2 weeks), 4c (media sync + conflict resolution + offline queue -- 2-3 weeks). Accept that 4c may slip. |
| R7 | `SceneDelegate.scene(_:openURLContexts:)` not implemented, blocking backup import via AirDrop/Files | MEDIUM | HIGH | Implement early in Phase 3 as a prerequisite spike. Define MethodChannel contract: `com.liquideditor/file_open` with `{path: String, type: String}` payload. |
| R8 | No settings screen exists, blocking Storage and iCloud UI | LOW | LOW | Create minimal settings scaffold (`settings_view.dart`) at start of Phase 3. Low complexity. |
| R9 | Draft ring buffer and auto-save coordination causes double-writes or missed saves | MEDIUM | MEDIUM | `DraftManagementService.saveDraft()` wraps `ProjectStorage.save()` -- it does BOTH the ring buffer write and the canonical save atomically. Replace `scheduleAutoSave` calls in `SmartEditViewModel` with `DraftManagementService.scheduleDraftSave()`. |
| R10 | Storage calculation takes >5s on devices with many large video files | LOW | LOW | Calculate asynchronously in background isolate. Show spinner and cache result. Users rarely visit storage screen. |
| R11 | Shared media double-counting in per-project storage view confuses users | MEDIUM | LOW | Add "(shared)" label next to media entries that are referenced by multiple projects. Show deduplicated total prominently. |
| R12 | Template flow temporal ordering: template selected before video known | LOW | LOW | Hold template in state, apply after video import. API already supports this (R2 IMPORTANT-14 solution path confirmed). |

---

### Implementation Checklist

Ordered by implementation phase, with file paths and descriptions. Each item should be implemented and tested before moving to the next.

#### Phase 1: Core Project Management (Week 1-2)

| # | File | Description | Dependencies | Est. |
|---|------|-------------|--------------|------|
| 1.1 | `lib/core/project_management_service.dart` | New file. Singleton service with `duplicateProject()` and `_generateUniqueCopyName()`. Operates on legacy clips only. Includes guard clause for unknown clip types. | `project_storage.dart`, `timeline_clip.dart` | 2h |
| 1.2 | `lib/views/library/project_library_view.dart` | Add `VoidCallback? onDuplicate` to `_PremiumProjectCard`. Wire context menu Duplicate action to `ProjectManagementService.shared.duplicateProject()`. Call `_loadProjects()` on success. | 1.1 | 1h |
| 1.3 | `lib/views/library/project_library_view.dart` | Implement Rename context menu action. Show `CupertinoAlertDialog` with `CupertinoTextField` for new name. Call `ProjectStorage.save()` with updated name. | `project_storage.dart` | 1h |
| 1.4 | `lib/views/library/project_library_view.dart` | Add `ProjectSortCriteria` enum, `_currentSortCriteria` state, `_showSortOptions()` method. Wire sort button handler. Persist via `SharedPreferences`. Apply sort to `_projects` list. | `shared_preferences` | 2h |
| 1.5 | `lib/views/library/project_library_view.dart` | Add `CupertinoSearchTextField` as `SliverToBoxAdapter` below nav bar. Add `_searchQuery` state and `_filteredProjects` getter. Update grid to use `_filteredProjects`. | None | 1.5h |
| 1.6 | `test/core/project_management_service_test.dart` | Unit tests: duplication creates new IDs, unique name generation, shared media paths, legacy clip deep clone, guard clause for unknown types. | 1.1 | 2h |
| 1.7 | `test/views/library/project_sort_test.dart` | Unit tests: all 8 sort criteria produce correct ordering. | 1.4 | 1h |

**Phase 1 total estimate: ~10.5 hours**

#### Phase 2: Aspect Ratio & Drafts (Week 3-4)

| # | File | Description | Dependencies | Est. |
|---|------|-------------|--------------|------|
| 2.1 | `lib/models/aspect_ratio.dart` | New file. `AspectRatioSetting` (immutable, with presets), `AspectRatioMode` enum. JSON serialization. | None | 1h |
| 2.2 | `lib/models/project.dart` | Add `aspectRatio` (`AspectRatioSetting?`), `aspectRatioMode` (`AspectRatioMode`) fields to `Project`. Update `copyWith`, `toJson`, `fromJson` with backward-compatible defaults. Bump schema version to 3. | 2.1 | 1.5h |
| 2.3 | `lib/views/smart_edit/` (or new aspect ratio picker widget) | Aspect ratio picker UI: `CupertinoActionSheet` with presets + custom option. Adaptation mode selection sheet. Wire to project update. | 2.1, 2.2 | 3h |
| 2.4 | `lib/models/draft_metadata.dart` | New file. `DraftMetadata`, `DraftEntry`, `DraftTriggerReason` models. JSON serialization. | None | 1h |
| 2.5 | `lib/core/draft_management_service.dart` | New file. Singleton with ring buffer save (max 5 slots), crash recovery check, revert-to-last, clean shutdown marking. Wraps `ProjectStorage.save()`. | 2.4, `project_storage.dart` | 4h |
| 2.6 | `lib/views/smart_edit/smart_edit_view.dart` or `smart_edit_view_model.dart` | Integrate `DraftManagementService`: replace `scheduleAutoSave` calls, add `WidgetsBindingObserver` for lifecycle, add crash recovery dialog on project open, add unsaved changes indicator dot. | 2.5 | 3h |
| 2.7 | `test/models/aspect_ratio_test.dart` | Unit tests: ratio calculations, preset values, JSON round-trip, export dimensions, custom ratios. | 2.1 | 1.5h |
| 2.8 | `test/core/draft_management_service_test.dart` | Unit tests: ring buffer rotation (write 7 drafts, verify only 5 retained), crash detection, recovery, revert, cleanup, metadata JSON round-trip. | 2.5 | 3h |

**Phase 2a (Dart-side) total estimate: ~18 hours**

Phase 2b (native aspect ratio pipeline) is deferred pending iOS lead spike:

| # | File | Description | Dependencies | Est. |
|---|------|-------------|--------------|------|
| 2b.1 | `ios/Runner/CompositionPlayerService.swift` | Add `AVMutableVideoComposition` with `renderSize` matching target aspect ratio. Add layer instructions for letterbox and zoom-to-fill transforms. | 2.2 (Dart model) | 8-12h |
| 2b.2 | `ios/Runner/VideoProcessingService.swift` | Update thumbnail generation to respect target aspect ratio. Update export to use new video composition. | 2b.1 | 4-6h |
| 2b.3 | Integration test: preview + export with non-source aspect ratio | Verify letterbox, zoom-to-fill, and stretch modes render correctly in both preview and export. | 2b.1, 2b.2 | 3h |

**Phase 2b estimate: ~15-21 hours (HIGH uncertainty)**

#### Phase 3: Backup/Restore & Storage (Week 5-6)

| # | File | Description | Dependencies | Est. |
|---|------|-------------|--------------|------|
| 3.1 | `pubspec.yaml` | Add `archive: ^3.6.1` dependency for zip creation/extraction in isolates. | None | 0.25h |
| 3.2 | `lib/models/backup_manifest.dart` | New file. `BackupManifest`, `BackupMediaEntry`, `BackupValidationResult` models. JSON serialization. Includes `includesAssetRegistry` flag. | None | 1.5h |
| 3.3 | `lib/core/project_backup_service.dart` | New file. `createBackup()` (resolve paths on main isolate, zip in background via `compute()`), `restoreBackup()` (validate, extract, assign new UUID, copy media, deduplicate by content hash), `validateBackup()`. | 3.1, 3.2, `project_storage.dart`, `project_file_service.dart` | 8h |
| 3.4 | `ios/Runner/Info.plist` | Add `CFBundleDocumentTypes` and `UTExportedTypeDeclarations` for `com.liquideditor.backup` / `.liquidbackup`. | None | 0.5h |
| 3.5 | `ios/Runner/SceneDelegate.swift` | Add `scene(_:openURLContexts:)` override. Forward `.liquidbackup` file URL to Flutter via `MethodChannel("com.liquideditor/file_open")`. | 3.4 | 2h |
| 3.6 | `lib/core/file_open_handler.dart` | New file. Listen to `MethodChannel("com.liquideditor/file_open")` for incoming file URLs. Trigger restore flow when `.liquidbackup` received. | 3.5, 3.3 | 1.5h |
| 3.7 | `lib/views/library/project_library_view.dart` | Add "Export Backup" to context menu. Show `CupertinoActionSheet` for full/metadata mode. Show progress indicator. Use `Share.shareXFiles` for output. | 3.3 | 2h |
| 3.8 | `lib/models/storage_usage.dart` | New file. `StorageUsage`, `ProjectStorageUsage`, `OrphanedFile` models. | None | 1h |
| 3.9 | `lib/core/storage_analysis_service.dart` | New file. `calculateUsage()` in background isolate, `findOrphanedFiles()` with path deduplication, `cleanup()` for orphans and cache. | 3.8, `project_storage.dart`, `project_file_service.dart` | 4h |
| 3.10 | `lib/views/settings/settings_view.dart` | New file. Settings screen scaffold with navigation from library. Storage row, iCloud placeholder. Uses `CupertinoListSection.insetGrouped`. | None | 2h |
| 3.11 | `lib/views/settings/storage_usage_view.dart` | New file. Storage detail screen: segmented bar, per-category breakdown, per-project list, cleanup action sheet. | 3.9, 3.10 | 3h |
| 3.12 | `test/core/project_backup_service_test.dart` | Unit tests: manifest creation, archive structure validation, restore with/without media, content hash deduplication, version compatibility. | 3.3 | 4h |
| 3.13 | `test/core/storage_analysis_service_test.dart` | Unit tests: size calculation, orphan detection, shared media dedup in totals. | 3.9 | 2h |

**Phase 3 total estimate: ~31.75 hours**

#### Phase 4: Templates, Metadata & iCloud (Week 7-10)

| # | File | Description | Dependencies | Est. |
|---|------|-------------|--------------|------|
| 4.1 | `lib/models/project_template.dart` | New file. `ProjectTemplate`, `TemplateCategory`, built-in templates as static constants. JSON serialization. | `aspect_ratio.dart` | 1.5h |
| 4.2 | `lib/core/project_template_service.dart` | New file. `getAllTemplates()`, `saveAsTemplate()`, `deleteTemplate()`, `createFromTemplate()`. Persists custom templates in `Documents/Templates/`. | 4.1 | 2h |
| 4.3 | `lib/views/library/template_picker_sheet.dart` | New file. Modal popup with template grid grouped by category. | 4.1, 4.2 | 3h |
| 4.4 | `lib/views/library/project_library_view.dart` | Integrate template picker into import flow. Hold selected template in state, apply after video import. | 4.2, 4.3 | 1.5h |
| 4.5 | `lib/models/project.dart` | Add metadata fields: `description`, `tags`, `starRating`, `colorLabel`, `isFavorite`. Update `copyWith`, `toJson`, `fromJson` with backward-compatible defaults. | None | 1.5h |
| 4.6 | `lib/views/library/project_library_view.dart` | Add Color Label, Favorite, Info context menu actions. Visual integration: color border, heart overlay. | 4.5 | 2h |
| 4.7 | `lib/views/library/project_library_view.dart` | Extend search to include tags. Add filter chips for favorites and color labels. | 4.5, 1.5 | 2h |
| 4.8 | `ios/Runner/ICloudSyncService.swift` | New file. Native iCloud integration: availability check, upload/download via iCloud Drive, `NSMetadataQuery` monitoring. | iCloud entitlements | 12h |
| 4.9 | `lib/core/icloud_sync_service.dart` | New file. Flutter bridge via `MethodChannel("com.liquideditor/icloud_sync")`. Manages sync status, triggers upload/download. | 4.8 | 4h |
| 4.10 | `lib/core/sync_queue.dart` | New file. Persistent offline operation queue. JSON-backed, ordered, retry with exponential backoff, debounce for same-project uploads. | 4.9 | 4h |
| 4.11 | `lib/models/project.dart` | Add sync fields: `syncStatus`, `iCloudChangeTag`, `iCloudEnabled`. | None | 1h |
| 4.12 | `lib/views/settings/icloud_settings_view.dart` | New file. iCloud toggle, WiFi-only toggle, last sync info. | 4.9, 3.10 | 2h |
| 4.13 | `lib/views/library/project_library_view.dart` | Add sync status icons on project cards. | 4.11 | 1.5h |
| 4.14 | `test/core/project_template_service_test.dart` | Unit tests: built-in templates, custom save/load/delete, project creation from template. | 4.2 | 2h |
| 4.15 | `test/core/sync_queue_test.dart` | Unit tests: queue persistence, ordering, retry, deduplication, debounce. | 4.10 | 2h |
| 4.16 | `test/models/project_metadata_test.dart` | Unit tests: new fields serialization, backward compatibility. | 4.5 | 1h |

**Phase 4 total estimate: ~40 hours (iCloud accounts for ~20h)**

---

### Comprehensive Test Plan

#### Unit Tests (Automated, run in CI)

| Test File | What It Covers | Key Assertions | Priority |
|-----------|---------------|----------------|----------|
| `project_management_service_test.dart` | Duplication | New project ID != original; new clip IDs != original; new keyframe IDs != original; name is "{name} Copy"; name auto-increments; shared sourceVideoPath; modifiedAt reset; guard clause throws for unknown clip types | P0 |
| `aspect_ratio_test.dart` | Ratio model | `value` getter correct for all presets; JSON round-trip; export dimensions correct for portrait/landscape/square; custom ratio validation; cinematic ratio = 2.35 | P0 |
| `draft_management_service_test.dart` | Draft system | Ring buffer: 7 writes produce 5 files; correct slot rotation; crash detection (cleanShutdown=false + newer draft); recovery returns correct draft; revert loads previous slot; cleanup removes orphaned draft folders; metadata JSON round-trip | P0 |
| `project_backup_service_test.dart` | Backup/restore | Archive contains manifest.json + project.json; full backup includes media/; metadata-only excludes media/; manifest fields populated correctly; restore assigns new UUID; restore skips existing media (by content hash); version compatibility checks; corrupt archive rejected; backup filename sanitized | P0 |
| `storage_analysis_service_test.dart` | Storage calc | Total = sum of categories; shared media counted once in total; per-project shows full size; orphan detection finds unreferenced files; cleanup removes orphans | P1 |
| `project_template_service_test.dart` | Templates | Built-in count matches expected; custom template save/load round-trip; delete custom succeeds; delete built-in throws; createFromTemplate applies all settings | P1 |
| `sync_queue_test.dart` | Sync queue | Operations persisted across restarts; FIFO order; retry increments count; debounce coalesces same-project uploads; max retry reached -> mark failed | P1 |
| `project_metadata_test.dart` | Metadata fields | New fields serialize/deserialize; missing fields default correctly (backward compat); color label enum round-trip; tags list round-trip; starRating clamped 0-5 | P0 |
| `project_sort_test.dart` | Sort criteria | All 8 criteria produce correct order; case-insensitive name sort; empty list handled; single-element list handled | P1 |

#### Integration Tests (Device/Simulator)

| Scenario | Steps | Expected Result | Priority |
|----------|-------|-----------------|----------|
| Duplicate full project | Create project with 3 clips + keyframes -> Duplicate -> Open duplicate | Duplicate has independent clips, all keyframes present, editing one does not affect other | P0 |
| Backup full round-trip | Create project -> Export full backup -> Delete project -> Import backup | Restored project matches original (clips, keyframes, media playable) | P0 |
| Backup metadata-only | Export metadata-only -> Delete project -> Import | Project restored but clips show "offline" for media | P0 |
| Aspect ratio change | Set 16:9 project -> Change to 1:1 letterbox -> Verify preview | Preview shows letterbox bars, video centered | P0 |
| Crash recovery | Open project -> Edit -> Force-kill app -> Relaunch -> Open project | Recovery dialog appears with correct draft info | P0 |
| Sort persistence | Set sort to "Name A-Z" -> Kill app -> Relaunch | Sort persists as "Name A-Z" | P1 |
| Search | Create 10 projects -> Search "vlog" -> Verify results | Only projects with "vlog" in name shown | P1 |
| Template flow | Select TikTok template -> Import video -> Open project | Project has 9:16 aspect ratio and 30fps | P1 |
| Storage cleanup | Import video -> Delete project (not video) -> Storage screen -> Clean Up | Orphaned video file detected and removed | P1 |
| File open handler | AirDrop `.liquidbackup` to device | App opens, shows restore confirmation, restores project | P1 |

#### Manual Testing (Pre-Release)

- [ ] Duplicate a project with 10+ clips and verify all clips/keyframes are independent copies
- [ ] Export a full backup (>500MB) and verify progress indicator updates smoothly
- [ ] Restore backup on different device via AirDrop
- [ ] Export metadata-only backup and restore on same device
- [ ] Change aspect ratio 16:9 -> 9:16 with auto-reframe keyframes (verify warning dialog)
- [ ] Change aspect ratio 16:9 -> 1:1 with manual keyframes (verify clamp dialog)
- [ ] Sort by all 8 criteria and verify visual order
- [ ] Search with partial name, special characters, and empty query
- [ ] Force-kill app during active editing and verify crash recovery
- [ ] Use "Revert to Last Save" and verify all recent changes discarded
- [ ] Storage screen with 5+ projects, verify per-project breakdown sums reasonably
- [ ] Clean Up and verify orphaned files removed, active files preserved
- [ ] Create project from each built-in template
- [ ] Save project as custom template, create new project from it
- [ ] Delete custom template, verify no impact on existing projects
- [ ] Color label and favorite on project card (visual verification)
- [ ] VoiceOver enabled: navigate all new UI elements
- [ ] Haptic feedback on all new interactive elements
- [ ] iPad layout: verify no overflow or layout issues on larger screen

---

### Final Assessment: CONDITIONAL GO

**Decision: GO for Phase 1-3. CONDITIONAL GO for Phase 4.**

The design document is comprehensive, well-structured, and addresses all major feature areas. After three rounds of review, all six critical issues have defined resolution paths, and none block Phase 1-3 implementation.

**Phase 1 (Core Project Management):** GREEN. Low risk, high value. All scaffolding is in place in the codebase. Estimated 10.5 hours.

**Phase 2a (Aspect Ratio Dart + Drafts):** GREEN. Model and UI work is straightforward. Estimated 18 hours. Phase 2b (native pipeline) is YELLOW -- requires iOS lead spike before committing to a timeline.

**Phase 3 (Backup/Restore + Storage):** GREEN with one prerequisite: the `SceneDelegate` file-open handler (item 3.5) must be spiked early to validate the MethodChannel flow for incoming `.liquidbackup` files. Estimated 31.75 hours.

**Phase 4 (Templates + iCloud):** YELLOW. Templates (4.1-4.7) are GREEN and can ship independently. iCloud sync (4.8-4.13) is the highest-scope, highest-risk feature. Recommend splitting Phase 4 into 4a (templates + metadata, 1 week) and 4b (iCloud, 3-4 weeks). iCloud should not block other features.

**Conditions for GO:**
1. Team agrees on scoping decision: Phase 1-3 targets legacy clips only (C5 resolution).
2. Phase 2b (native aspect ratio) gets a separate spike estimate before committing the Phase 2 timeline.
3. `archive` package isolate compatibility is verified with a spike test before Phase 3 begins.

---

### Remaining Open Questions

| # | Question | Owner | Needed By | Impact |
|---|----------|-------|-----------|--------|
| OQ1 | When will V2 clip migration into `Project.clips` occur? This determines when C2, C4, C6 fixes become urgent. | Architecture Lead | Before Phase 4b | HIGH -- affects iCloud sync data model |
| OQ2 | What is the target iOS minimum deployment version? iCloud `NSMetadataQuery` and some `CKDatabase` APIs vary by iOS version. | PM | Before Phase 4b | MEDIUM -- affects iCloud API selection |
| OQ3 | Should backup export require WiFi (large files)? The design does not specify cellular restrictions for backup operations (only for iCloud sync). | PM/UX | Before Phase 3 | LOW -- UX decision |
| OQ4 | How will the settings screen be navigated to? The current app has no settings entry point. Options: (a) gear icon in nav bar, (b) third tab in `CNTabBar`, (c) long-press on app icon. | UX Lead | Before Phase 3 | LOW -- UI scaffolding decision |
| OQ5 | Should the project `version` field be bumped to 3 in Phase 2 (when aspect ratio fields are added) or deferred until all metadata fields are added in Phase 4? Bumping once is cleaner but delays metadata fields from being version-gated. | Architecture Lead | Before Phase 2 | LOW -- single bump at Phase 2 is recommended |
| OQ6 | What happens to thumbnails when aspect ratio changes? Should thumbnails be regenerated to show the letterbox/crop preview, or keep showing the source frame? | UX Lead | Before Phase 2b | LOW -- cosmetic but affects user expectation |

---

### Acknowledgments

This review concludes the three-round review process. The design document is approved for implementation with the conditions noted above. The phased approach de-risks the highest-complexity features (native aspect ratio pipeline, iCloud sync) while delivering immediate user value in Phases 1-2a.

**Review Chain:**
- R1: Architecture and Completeness -- identified 4 criticals (C1-C4), 8 important, 8 minor, 6 questions
- R2: Implementation Viability and Integration Risk -- confirmed all R1 findings via codebase verification, identified 2 new criticals (C5-C6), 6 important, 4 minor, 11 action items
- R3: Final Implementation Readiness -- defined resolution paths for all 6 criticals, created risk register (12 risks), implementation checklist (40+ items), comprehensive test plan, conditional GO assessment

**Total issues tracked across all reviews: 6 CRITICAL, 14 IMPORTANT, 12 MINOR, 11 ACTION ITEMS, 6 OPEN QUESTIONS.**

---
