# UI/UX Feature Enhancements - Design Document

**Date:** 2026-02-06
**Status:** Draft
**Author:** Claude + Nikhil

---

## Table of Contents

1. [Overview](#1-overview)
2. [Current UI Architecture Analysis](#2-current-ui-architecture-analysis)
3. [Full-Screen Preview](#3-full-screen-preview)
4. [Grid Overlay System](#4-grid-overlay-system)
5. [Safe Zone Overlay](#5-safe-zone-overlay)
6. [Comparison View (Before/After)](#6-comparison-view-beforeafter)
7. [Preview Quality Toggle](#7-preview-quality-toggle)
8. [Onboarding Tutorial](#8-onboarding-tutorial)
9. [Gesture Hints](#9-gesture-hints)
10. [Context-Sensitive Help](#10-context-sensitive-help)
11. [Customizable Workspace](#11-customizable-workspace)
12. [Orientation Lock](#12-orientation-lock)
13. [Accessibility](#13-accessibility)
14. [Dark/Light Mode](#14-darklight-mode)
15. [Edge Cases](#15-edge-cases)
16. [Performance Budget](#16-performance-budget)
17. [Implementation Plan](#17-implementation-plan)
18. [File Structure](#18-file-structure)
19. [Test Plan](#19-test-plan)

---

## 1. Overview

### 1.1 Summary

This document specifies ten UI/UX feature enhancements for Liquid Editor. Each feature is designed to integrate with the existing iOS 26 Liquid Glass design system, use only native Cupertino widgets, and respect the performance budget defined in `CLAUDE.md`. Together, these features transform the editor from a functional tool into a polished, production-grade experience.

### 1.2 Goals

| Goal | Description |
|------|-------------|
| **Professional editing support** | Grid overlays, safe zones, and comparison view give editors the tools they expect |
| **Smooth onboarding** | First-launch tutorial and gesture hints reduce time-to-first-export |
| **Adaptive workspace** | Resizable preview/timeline and orientation support fit different workflows |
| **Performance awareness** | Quality toggle lets users trade resolution for smooth scrubbing on older devices |
| **Accessibility** | VoiceOver, Dynamic Type, and Reduce Motion support make the app usable by everyone |

### 1.3 Non-Goals (v1)

- iPad / macOS support (iPhone only)
- Cloud-synced workspace preferences
- Custom keyboard shortcuts
- External display support
- Third-party plugin system for overlays

### 1.4 Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| `cupertino_native_better` | current | CNTabBar, CNButton, CNSymbol |
| `shared_preferences` | current | Persist user preferences (grid type, quality, workspace) |
| `video_player` | current | Preview quality scaling |
| Flutter Cupertino library | current | All native UI components |

---

## 2. Current UI Architecture Analysis

### 2.1 Layout Structure

The editor (`SmartEditView`) uses a `Column` layout inside a `Stack`:

```
Stack
 +-- Column (main content)
 |    +-- SafeArea: Top toolbar (X, project name, 2K, Export)    ~44px
 |    +-- SizedBox(height: 450): Video preview                  450px
 |    +-- Playback controls (play, time, undo/redo)              ~44px
 |    +-- Ruler + Timeline with playhead                         ~56px
 +-- Positioned(bottom: 0): EditorBottomToolbar                  ~120px
 +-- Positioned(fill): Overlays (tracking, reorder, auto-reframe, dropdowns)
```

**Screen budget on iPhone 16 Pro (852pt height):**
- Status bar + safe area top: ~59px
- Top toolbar: ~44px
- Video preview: 450px
- Playback controls: ~44px
- Timeline: ~56px
- Bottom toolbar: ~120px
- Bottom safe area: ~34px
- **Total: ~807px** (leaves ~45px margin)

### 2.2 Existing Design System Components

From `lib/design_system/glass_styles.dart`:

| Component | Type | Usage |
|-----------|------|-------|
| `AppColors` | Constants | 40+ color constants including glass, semantic, gradient |
| `AppTypography` | Constants | 7 text styles + `scaledStyle()` for Dynamic Type |
| `LiquidGlassPanel` | Widget | Frosted glass panel with blur, gradient, border, highlight |
| `GlassPanel` | Widget | Simpler glass panel for small elements |
| `GlassEffectContainer` | Widget | Full-width glass container (e.g., toolbars) |
| `LiquidGlassButton` | Widget | Animated press-scale button with glass blur |
| `CircularGlassButton` | Widget | Round glass button (44px default) |
| `PlaybackButton` | Widget | Circle button for play/pause/skip |
| `GlassToolbarButton` | Widget | Icon + label toolbar button (56px wide) |
| `GlassActionChip` | Widget | Contextual action chip with accent color |
| `CompactGlassIconButton` | Widget | Small icon button (32px default) |
| `GlassSlider` | Widget | Styled slider with label and value display |
| `KeyframeDiamond` | Widget | Diamond shape for keyframe markers |
| `IndicatorChip` | Widget | Small pill badge (icon + label) |
| `HapticManager` | Singleton | Centralized haptic feedback API |

From `lib/design_system/liquid_glass_popup.dart`:

| Component | Type | Usage |
|-----------|------|-------|
| `LiquidGlassPopup` | Widget | Floating dropdown menu with blur |
| `LiquidGlassPopupItem` | Widget | Tappable menu row |
| `LiquidGlassPopupToggle` | Widget | Toggle row with CupertinoSwitch |
| `LiquidGlassPopupDivider` | Widget | Thin separator line |
| `LiquidGlassPopupTrigger` | Widget | Tap-to-show popup wrapper |
| `showLiquidGlassPopup()` | Function | Show popup as overlay route |

### 2.3 Navigation Flow

```
ProjectLibraryView (root)
  |-- CNTabBar: [Projects, People]
  |
  +-- Projects tab
  |     +-- CupertinoSliverNavigationBar (large title)
  |     +-- Grid of _PremiumProjectCard
  |     +-- CupertinoContextMenu (long-press: Open, Duplicate, Rename, Delete)
  |     +-- Tap -> push CupertinoPageRoute -> SmartEditView
  |
  +-- People tab
        +-- CupertinoSliverNavigationBar (large title)
        +-- Grid of _PersonCard
        +-- CupertinoContextMenu (long-press: View, Add Photo, Rename, Delete)
```

### 2.4 Existing State That Intersects With New Features

| State Variable | Location | Relevance |
|----------------|----------|-----------|
| `_viewModel.isFullscreen` | SmartEditViewModel | Full-screen preview already partially implemented |
| `_showGuides` | SmartEditView | Boolean for guides, not yet connected to UI rendering |
| `_viewModel.timelineZoomLevel` | SmartEditViewModel | 0.5x - 4.0x, used for workspace sizing |
| `_isTimelineSelected` | SmartEditView | Track if timeline has user focus |
| `_loopPlayback` | SmartEditView | Project setting toggle |
| `_snappingEnabled` | SmartEditView | Project setting toggle |
| `_showFrames` | SmartEditView | Project setting toggle |
| `_visualClipsEnabled` | SmartEditView | Project setting toggle |
| `_audioClipsEnabled` | SmartEditView | Project setting toggle |

---

## 3. Full-Screen Preview

### 3.1 Current State

The fullscreen view already exists in `_buildFullscreenView()` (line 2618 of `smart_edit_view.dart`). It renders the video centered on a black background with:
- Tap-anywhere to exit
- Exit button (top-left `CircularGlassButton`)
- Play/pause overlay (center)
- Time display (bottom-center)

### 3.2 What Needs to Change

The existing fullscreen view is minimal. It needs to become a polished, professional preview experience.

#### 3.2.1 Entry/Exit Gestures

| Gesture | Action | Feedback |
|---------|--------|----------|
| Tap chevron (bottom of preview) | Enter fullscreen | `HapticFeedback.selectionClick()` |
| Double-tap video preview | Enter fullscreen | `HapticFeedback.mediumImpact()` |
| Swipe down (velocity > 500px/s) | Exit fullscreen | `HapticFeedback.lightImpact()` |
| Tap exit button (top-left) | Exit fullscreen | `HapticFeedback.selectionClick()` |
| Pinch outward from preview | Enter fullscreen (animated zoom) | `HapticFeedback.mediumImpact()` |

#### 3.2.2 Auto-Hide Controls

Controls should appear on tap and auto-hide after 3 seconds of inactivity:

```dart
// State
Timer? _controlsHideTimer;
bool _showFullscreenControls = true;

void _resetControlsTimer() {
  _controlsHideTimer?.cancel();
  setState(() => _showFullscreenControls = true);
  _controlsHideTimer = Timer(const Duration(seconds: 3), () {
    if (mounted && _viewModel.isFullscreen) {
      setState(() => _showFullscreenControls = false);
    }
  });
}
```

Controls to show/hide with `AnimatedOpacity(duration: 300ms)`:
- Top bar: exit button, time display, grid/safe zone toggles
- Bottom bar: play/pause, scrub bar, loop toggle
- Status bar: hidden via `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)`

#### 3.2.3 Fullscreen Layout

```
Stack (Positioned.fill, color: Colors.black)
 +-- Center: AspectRatio > Transform > VideoPlayer
 +-- AnimatedOpacity (controls)
 |    +-- Positioned(top): SafeArea
 |    |    +-- Row: [Exit button, Spacer, Grid toggle, SafeZone toggle, Quality badge]
 |    +-- Positioned(bottom): SafeArea
 |         +-- Column:
 |              +-- CupertinoSlider (scrub bar)
 |              +-- Row: [Time, Spacer, Play/Pause, Spacer, Loop, Orientation lock]
 +-- GestureDetector (swipe down to exit, tap to toggle controls)
```

#### 3.2.4 Transition Animation

Entry: `Hero` animation from the video preview widget to fullscreen, combined with background fade-in.

```dart
// Wrap the preview in a Hero:
Hero(
  tag: 'video_preview',
  child: _buildCapCutVideoPreview(),
)

// Fullscreen uses matching Hero:
Hero(
  tag: 'video_preview',
  child: AspectRatio(
    aspectRatio: controller.value.aspectRatio,
    child: VideoPlayer(controller),
  ),
)
```

If Hero animation causes platform view issues (since CompositionPlayerView must stay in the widget tree), fall back to a custom `AnimationController` with:
- Scale from preview bounds to screen bounds (300ms, `Curves.easeOutCubic`)
- Background opacity 0 to 1 (200ms)
- Status bar fade out (200ms)

#### 3.2.5 Rotation Support

In fullscreen mode only, allow landscape orientation:

```dart
void _enterFullscreen() {
  _viewModel.isFullscreen = true;
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

void _exitFullscreen() {
  _viewModel.isFullscreen = false;
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}
```

#### 3.2.6 Grid and Safe Zone in Fullscreen

The grid overlay and safe zone overlay (defined in sections 4 and 5) should render on top of the video in fullscreen mode. Toggle buttons in the fullscreen top bar control their visibility. State is shared with the normal editor view.

---

## 4. Grid Overlay System

### 4.1 Grid Types

| Grid Type | Description | Lines | Use Case |
|-----------|-------------|-------|----------|
| `ruleOfThirds` | 2 horizontal + 2 vertical lines dividing frame into 9 equal parts | 4 | Composition, subject placement |
| `goldenRatio` | Lines at ~38.2% and ~61.8% of frame width/height | 4 | Classical composition |
| `centerCross` | Single vertical + single horizontal through center | 2 | Centering subjects |
| `diagonal` | Lines from each corner to opposite corner | 2 (or 4 with subdivisions) | Dynamic composition, leading lines |
| `squareGrid` | 4x4 or 8x8 even grid | 6 or 14 | Alignment, symmetry |
| `custom` | User-defined NxM grid | variable | Specific framing needs |

### 4.2 Data Model

```dart
enum GridType {
  ruleOfThirds,
  goldenRatio,
  centerCross,
  diagonal,
  squareGrid,
  custom,
}

class GridOverlayConfig {
  final GridType type;
  final bool isVisible;
  final double opacity;       // 0.0 - 1.0, default 0.5
  final Color lineColor;      // default: Colors.white
  final double lineWidth;     // default: 0.5 (retina-crisp)
  final int customRows;       // for custom grid, default: 3
  final int customColumns;    // for custom grid, default: 3

  const GridOverlayConfig({
    this.type = GridType.ruleOfThirds,
    this.isVisible = false,
    this.opacity = 0.5,
    this.lineColor = const Color(0xFFFFFFFF),
    this.lineWidth = 0.5,
    this.customRows = 3,
    this.customColumns = 3,
  });
}
```

### 4.3 CustomPainter Implementation

```dart
class GridOverlayPainter extends CustomPainter {
  final GridOverlayConfig config;

  GridOverlayPainter({required this.config});

  @override
  void paint(Canvas canvas, Size size) {
    if (!config.isVisible) return;

    final paint = Paint()
      ..color = config.lineColor.withOpacity(config.opacity)
      ..strokeWidth = config.lineWidth
      ..style = PaintingStyle.stroke;

    // Shadow paint for readability on any background
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(config.opacity * 0.5)
      ..strokeWidth = config.lineWidth + 1.0
      ..style = PaintingStyle.stroke;

    switch (config.type) {
      case GridType.ruleOfThirds:
        _drawGrid(canvas, size, 3, 3, paint, shadowPaint);
      case GridType.goldenRatio:
        _drawGoldenRatio(canvas, size, paint, shadowPaint);
      case GridType.centerCross:
        _drawCenterCross(canvas, size, paint, shadowPaint);
      case GridType.diagonal:
        _drawDiagonals(canvas, size, paint, shadowPaint);
      case GridType.squareGrid:
        _drawGrid(canvas, size, 4, 4, paint, shadowPaint);
      case GridType.custom:
        _drawGrid(canvas, size, config.customRows, config.customColumns, paint, shadowPaint);
    }
  }

  void _drawGrid(Canvas canvas, Size size, int rows, int cols,
      Paint paint, Paint shadowPaint) {
    // Vertical lines
    for (int i = 1; i < cols; i++) {
      final x = size.width * i / cols;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), shadowPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines
    for (int i = 1; i < rows; i++) {
      final y = size.height * i / rows;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), shadowPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawGoldenRatio(Canvas canvas, Size size,
      Paint paint, Paint shadowPaint) {
    const phi = 0.381966; // 1 - 1/phi
    final positions = [phi, 1.0 - phi];
    for (final p in positions) {
      final x = size.width * p;
      final y = size.height * p;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), shadowPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), shadowPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawCenterCross(Canvas canvas, Size size,
      Paint paint, Paint shadowPaint) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), shadowPaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), shadowPaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
  }

  void _drawDiagonals(Canvas canvas, Size size,
      Paint paint, Paint shadowPaint) {
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), shadowPaint);
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), shadowPaint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(GridOverlayPainter oldDelegate) {
    return oldDelegate.config != config;
  }
}
```

### 4.4 Integration

The overlay sits inside the video preview `ClipRRect`, on top of the video but below gesture detectors:

```dart
// Inside _buildCapCutVideoPreview(), within the Stack:
if (_gridConfig.isVisible)
  Positioned.fill(
    child: CustomPaint(
      painter: GridOverlayPainter(config: _gridConfig),
    ),
  ),
```

### 4.5 Toggle UI

Grid type selection lives in the project settings dropdown (`_buildProjectSettingsDropdown()`), using existing `LiquidGlassPopup` components:

```dart
LiquidGlassPopupItem(
  icon: CupertinoIcons.grid,
  label: 'Grid: ${_gridConfig.type.displayName}',
  onTap: () => _showGridTypePicker(),
),
LiquidGlassPopupToggle(
  icon: CupertinoIcons.grid,
  label: 'Show Grid',
  value: _gridConfig.isVisible,
  onChanged: (value) {
    setState(() => _gridConfig = _gridConfig.copyWith(isVisible: value));
  },
),
```

Grid type picker uses `CupertinoActionSheet`:

```dart
void _showGridTypePicker() {
  showCupertinoModalPopup(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('Grid Type'),
      actions: GridType.values.map((type) =>
        CupertinoActionSheetAction(
          onPressed: () {
            setState(() => _gridConfig = _gridConfig.copyWith(type: type));
            Navigator.pop(context);
          },
          child: Text(type.displayName),
        ),
      ).toList(),
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ),
  );
}
```

### 4.6 Persistence

Grid preference saved via `shared_preferences`:

```dart
// Key: 'grid_type' -> string (enum name)
// Key: 'grid_visible' -> bool
// Key: 'grid_opacity' -> double
// Key: 'grid_custom_rows' -> int
// Key: 'grid_custom_cols' -> int
```

Loaded in `initState`, saved on every change. Per-app setting (not per-project) because grid preference is a user workflow choice.

### 4.7 Visibility During Playback

By default, the grid remains visible during playback. Users may want to check composition while reviewing. A toggle option "Hide Grid During Playback" can be added to the grid settings if user feedback requests it.

---

## 5. Safe Zone Overlay

### 5.1 Zone Definitions

| Zone | Percentage | Purpose | Default Color |
|------|-----------|---------|---------------|
| **Title Safe** | 80% of frame (10% inset each side) | Text and important graphics must be within this area | `CupertinoColors.systemYellow` @ 40% opacity |
| **Action Safe** | 90% of frame (5% inset each side) | Critical action must be within this area | `CupertinoColors.systemGreen` @ 30% opacity |
| **Custom** | User-defined percentage | Platform-specific safe zones | `CupertinoColors.systemBlue` @ 30% opacity |

### 5.2 Social Media Platform Safe Zones

In addition to broadcast standards, provide platform-specific overlays:

| Platform | Top Inset | Bottom Inset | Side Inset | Notes |
|----------|-----------|--------------|------------|-------|
| **TikTok** | 15% | 25% | 5% | Account for bottom UI controls and captions |
| **Instagram Reels** | 12% | 20% | 5% | Similar to TikTok |
| **YouTube Shorts** | 10% | 15% | 5% | Minimal UI overlay |
| **Broadcast 4:3** | 10% / 5% | 10% / 5% | 10% / 5% | Title safe / Action safe |
| **Broadcast 16:9** | 10% / 5% | 10% / 5% | 10% / 5% | Title safe / Action safe |

### 5.3 Data Model

```dart
enum SafeZonePreset {
  titleSafe,
  actionSafe,
  tikTok,
  instagramReels,
  youTubeShorts,
  broadcast,
  custom,
}

class SafeZoneConfig {
  final Set<SafeZonePreset> activeZones;
  final double customTopPercent;
  final double customBottomPercent;
  final double customLeftPercent;
  final double customRightPercent;
  final bool showLabels;

  const SafeZoneConfig({
    this.activeZones = const {},
    this.customTopPercent = 10.0,
    this.customBottomPercent = 10.0,
    this.customLeftPercent = 10.0,
    this.customRightPercent = 10.0,
    this.showLabels = true,
  });
}
```

### 5.4 CustomPainter Implementation

```dart
class SafeZonePainter extends CustomPainter {
  final SafeZoneConfig config;

  SafeZonePainter({required this.config});

  @override
  void paint(Canvas canvas, Size size) {
    for (final zone in config.activeZones) {
      _drawZone(canvas, size, zone);
    }
  }

  void _drawZone(Canvas canvas, Size size, SafeZonePreset zone) {
    final insets = _getInsets(zone, size);
    final rect = Rect.fromLTRB(
      insets.left,
      insets.top,
      size.width - insets.right,
      size.height - insets.bottom,
    );

    final paint = Paint()
      ..color = _getColor(zone)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw dashed rectangle
    _drawDashedRect(canvas, rect, paint);

    // Draw label
    if (config.showLabels) {
      _drawLabel(canvas, rect, _getLabel(zone), _getColor(zone));
    }
  }

  EdgeInsets _getInsets(SafeZonePreset zone, Size size) {
    switch (zone) {
      case SafeZonePreset.titleSafe:
        return EdgeInsets.all(size.width * 0.1); // 10% each side
      case SafeZonePreset.actionSafe:
        return EdgeInsets.all(size.width * 0.05); // 5% each side
      case SafeZonePreset.tikTok:
        return EdgeInsets.fromLTRB(
          size.width * 0.05,
          size.height * 0.15,
          size.width * 0.05,
          size.height * 0.25,
        );
      case SafeZonePreset.instagramReels:
        return EdgeInsets.fromLTRB(
          size.width * 0.05,
          size.height * 0.12,
          size.width * 0.05,
          size.height * 0.20,
        );
      case SafeZonePreset.youTubeShorts:
        return EdgeInsets.fromLTRB(
          size.width * 0.05,
          size.height * 0.10,
          size.width * 0.05,
          size.height * 0.15,
        );
      case SafeZonePreset.broadcast:
        return EdgeInsets.all(size.width * 0.10); // Title safe
      case SafeZonePreset.custom:
        return EdgeInsets.fromLTRB(
          size.width * config.customLeftPercent / 100,
          size.height * config.customTopPercent / 100,
          size.width * config.customRightPercent / 100,
          size.height * config.customBottomPercent / 100,
        );
    }
  }

  Color _getColor(SafeZonePreset zone) {
    switch (zone) {
      case SafeZonePreset.titleSafe:
        return CupertinoColors.systemYellow.withOpacity(0.6);
      case SafeZonePreset.actionSafe:
        return CupertinoColors.systemGreen.withOpacity(0.5);
      case SafeZonePreset.tikTok:
        return CupertinoColors.systemPink.withOpacity(0.5);
      case SafeZonePreset.instagramReels:
        return CupertinoColors.systemPurple.withOpacity(0.5);
      case SafeZonePreset.youTubeShorts:
        return CupertinoColors.systemRed.withOpacity(0.5);
      case SafeZonePreset.broadcast:
        return CupertinoColors.systemTeal.withOpacity(0.5);
      case SafeZonePreset.custom:
        return CupertinoColors.systemBlue.withOpacity(0.5);
    }
  }

  String _getLabel(SafeZonePreset zone) {
    switch (zone) {
      case SafeZonePreset.titleSafe: return 'Title Safe';
      case SafeZonePreset.actionSafe: return 'Action Safe';
      case SafeZonePreset.tikTok: return 'TikTok';
      case SafeZonePreset.instagramReels: return 'IG Reels';
      case SafeZonePreset.youTubeShorts: return 'YT Shorts';
      case SafeZonePreset.broadcast: return 'Broadcast';
      case SafeZonePreset.custom: return 'Custom';
    }
  }

  @override
  bool shouldRepaint(SafeZonePainter oldDelegate) {
    return oldDelegate.config != config;
  }
}
```

### 5.5 Integration

Safe zone overlay sits in the same layer as the grid overlay, stacked on top of the video inside the preview `ClipRRect`:

```dart
// After grid overlay in the Stack:
if (_safeZoneConfig.activeZones.isNotEmpty)
  Positioned.fill(
    child: CustomPaint(
      painter: SafeZonePainter(config: _safeZoneConfig),
    ),
  ),
```

### 5.6 Toggle UI

Safe zone selection uses a `CupertinoActionSheet` with multi-select:

```dart
void _showSafeZonePicker() {
  showCupertinoModalPopup(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => CupertinoActionSheet(
        title: const Text('Safe Zones'),
        message: const Text('Select one or more safe zone overlays'),
        actions: SafeZonePreset.values.map((preset) =>
          CupertinoActionSheetAction(
            onPressed: () {
              setSheetState(() {
                final zones = Set<SafeZonePreset>.from(_safeZoneConfig.activeZones);
                if (zones.contains(preset)) {
                  zones.remove(preset);
                } else {
                  zones.add(preset);
                }
                setState(() => _safeZoneConfig = _safeZoneConfig.copyWith(activeZones: zones));
              });
              HapticFeedback.selectionClick();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_safeZoneConfig.activeZones.contains(preset))
                  const Icon(CupertinoIcons.checkmark, size: 16),
                if (_safeZoneConfig.activeZones.contains(preset))
                  const SizedBox(width: 8),
                Text(preset.displayName),
              ],
            ),
          ),
        ).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ),
    ),
  );
}
```

### 5.7 Persistence

Same pattern as grid: `shared_preferences` with keys `safe_zone_active_*` (bool per preset), `safe_zone_custom_*` (doubles), `safe_zone_show_labels` (bool).

---

## 6. Comparison View (Before/After)

### 6.1 Modes

| Mode | Description | Interaction | Performance Cost |
|------|-------------|-------------|-----------------|
| **Split Screen** | Vertical divider splits frame: left = original, right = processed | Drag divider left/right | 2x rendering (two frames) |
| **Toggle** | Tap to switch between original and processed full-frame | Tap anywhere / hold for original | 1x rendering (switches source) |
| **Side-by-Side** | Two small previews next to each other | None (static comparison) | 2x rendering |

### 6.2 When Available

Comparison view is only meaningful when the current clip has modifications applied:
- Color grading/filters active
- Effects applied
- Crop/transform changes
- Speed changes (shows frame difference)
- Auto-reframe active (shows original framing vs. reframed)

If no modifications exist, the comparison button is disabled (greyed out).

### 6.3 Data Model

```dart
enum ComparisonMode {
  off,
  splitScreen,
  toggle,
  sideBySide,
}

class ComparisonConfig {
  final ComparisonMode mode;
  final double splitPosition;   // 0.0 - 1.0, default 0.5 (center)
  final bool showingOriginal;   // for toggle mode

  const ComparisonConfig({
    this.mode = ComparisonMode.off,
    this.splitPosition = 0.5,
    this.showingOriginal = false,
  });
}
```

### 6.4 Split Screen Implementation

```dart
Widget _buildSplitComparison(Size previewSize) {
  return Stack(
    children: [
      // Full-frame: processed video
      _buildProcessedVideoFrame(),

      // Clipped: original video (left portion)
      ClipRect(
        clipper: _SplitClipper(splitPosition: _comparisonConfig.splitPosition),
        child: _buildOriginalVideoFrame(),
      ),

      // Divider handle
      Positioned(
        left: previewSize.width * _comparisonConfig.splitPosition - 1,
        top: 0,
        bottom: 0,
        child: GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              final newPos = _comparisonConfig.splitPosition +
                  details.delta.dx / previewSize.width;
              _comparisonConfig = _comparisonConfig.copyWith(
                splitPosition: newPos.clamp(0.1, 0.9),
              );
            });
          },
          child: Container(
            width: 3,
            color: CupertinoColors.white,
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.arrow_left_arrow_right,
                  size: 14,
                  color: CupertinoColors.black,
                ),
              ),
            ),
          ),
        ),
      ),

      // Labels
      Positioned(
        top: 8,
        left: 8,
        child: _ComparisonLabel(text: 'Original'),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: _ComparisonLabel(text: 'Edited'),
      ),
    ],
  );
}
```

### 6.5 Toggle Mode Implementation

```dart
Widget _buildToggleComparison() {
  return GestureDetector(
    // Long press and hold to show original
    onLongPressStart: (_) {
      HapticFeedback.lightImpact();
      setState(() => _comparisonConfig = _comparisonConfig.copyWith(showingOriginal: true));
    },
    onLongPressEnd: (_) {
      setState(() => _comparisonConfig = _comparisonConfig.copyWith(showingOriginal: false));
    },
    child: Stack(
      children: [
        AnimatedCrossFade(
          firstChild: _buildProcessedVideoFrame(),
          secondChild: _buildOriginalVideoFrame(),
          crossFadeState: _comparisonConfig.showingOriginal
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        // Indicator
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: IndicatorChip(
              icon: _comparisonConfig.showingOriginal
                  ? CupertinoIcons.eye_slash
                  : CupertinoIcons.eye,
              label: _comparisonConfig.showingOriginal ? 'Original' : 'Edited',
              color: CupertinoColors.white,
            ),
          ),
        ),
      ],
    ),
  );
}
```

### 6.6 Original Frame Rendering

For the "original" frame, we need to render the video without any applied transforms or effects. This requires:

1. **No transforms:** Skip the `_buildTransformMatrix()` call, render video at identity matrix
2. **No color grading:** Bypass any color filter pipeline (when implemented)
3. **No effects:** Render raw decoded frame

Since the current app primarily applies keyframe-based transforms (scale, translate, rotate), the original frame is simply the video rendered with `Transform.identity`:

```dart
Widget _buildOriginalVideoFrame() {
  return RepaintBoundary(
    child: VideoPlayer(_viewModel.playbackController.controller!),
  );
}

Widget _buildProcessedVideoFrame() {
  return Transform(
    alignment: Alignment.center,
    transform: _buildTransformMatrix(previewWidth, previewHeight),
    child: RepaintBoundary(
      child: VideoPlayer(_viewModel.playbackController.controller!),
    ),
  );
}
```

### 6.7 Performance Considerations

- **Split screen and side-by-side** render two `VideoPlayer` widgets from the same controller. This is efficient because both share the same decoded frame buffer; only the transform/clip differs.
- **Toggle mode** uses `AnimatedCrossFade` which briefly shows both children during transition. This is acceptable for the 200ms duration.
- On low-memory devices, comparison mode should be disabled during playback and only available when paused, to avoid doubling GPU texture memory.

### 6.8 Toggle Button

Add a comparison toggle to the FX tab of `EditorBottomToolbar`:

```dart
// In EditorTab.fx tools:
_ToolButton(
  icon: CupertinoIcons.square_split_1x2,
  label: 'Compare',
  onPressed: _hasModifications ? () => _cycleComparisonMode() : null,
  isActive: _comparisonConfig.mode != ComparisonMode.off,
),
```

---

## 7. Preview Quality Toggle

### 7.1 Quality Levels

| Level | Scale Factor | Resolution (1080p source) | Memory per Frame | Purpose |
|-------|-------------|---------------------------|------------------|---------|
| **Full** | 1.0 | 1920x1080 | ~8.3 MB (RGBA) | Final preview, paused review |
| **Half** | 0.5 | 960x540 | ~2.1 MB | Smooth scrubbing, mid-range devices |
| **Quarter** | 0.25 | 480x270 | ~0.5 MB | Fast scrubbing, low-memory devices |
| **Auto** | dynamic | varies | varies | Full when paused, half during scrubbing |

### 7.2 Implementation Strategy

Quality scaling happens on the native side by adjusting the video player's preferred maximum resolution.

#### 7.2.1 Native-Side Resolution Cap

On iOS, `AVPlayerItem` supports `preferredMaximumResolution`:

```swift
// In AppDelegate or a dedicated PlayerConfigService:
case "setPreviewQuality":
    let scale = args["scale"] as? Double ?? 1.0
    if let playerItem = self.currentPlayerItem {
        let fullWidth = playerItem.asset.tracks(withMediaType: .video).first?.naturalSize.width ?? 1920
        let fullHeight = playerItem.asset.tracks(withMediaType: .video).first?.naturalSize.height ?? 1080
        playerItem.preferredMaximumResolution = CGSize(
            width: fullWidth * scale,
            height: fullHeight * scale
        )
    }
    result(nil)
```

#### 7.2.2 Flutter-Side Platform Channel

```dart
// In SmartEditViewModel or a dedicated PreviewQualityService:
static const _videoChannel = MethodChannel('com.liquideditor/video_processing');

Future<void> setPreviewQuality(PreviewQuality quality) async {
  final scale = switch (quality) {
    PreviewQuality.full => 1.0,
    PreviewQuality.half => 0.5,
    PreviewQuality.quarter => 0.25,
    PreviewQuality.auto => null, // managed dynamically
  };

  if (scale != null) {
    await _videoChannel.invokeMethod('setPreviewQuality', {'scale': scale});
  }

  _currentQuality = quality;
  notifyListeners();
}
```

#### 7.2.3 Auto Mode Logic

```dart
// In timeline scrub handler:
void _onScrubStart() {
  if (_currentQuality == PreviewQuality.auto) {
    _videoChannel.invokeMethod('setPreviewQuality', {'scale': 0.5});
  }
}

void _onScrubEnd() {
  if (_currentQuality == PreviewQuality.auto) {
    // Delay 200ms then restore full quality
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_isScrubbing) {
        _videoChannel.invokeMethod('setPreviewQuality', {'scale': 1.0});
      }
    });
  }
}
```

### 7.3 Data Model

```dart
enum PreviewQuality {
  full,
  half,
  quarter,
  auto,
}
```

### 7.4 UI

The quality indicator is the existing "2K" badge in the top toolbar. Replace it with an interactive toggle:

```dart
// In _buildCapCutTopToolbar():
GestureDetector(
  onTap: () {
    _showQualityPicker();
    HapticFeedback.selectionClick();
  },
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _getQualityBadgeColor().withOpacity(0.2),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: _getQualityBadgeColor().withOpacity(0.4),
        width: 0.5,
      ),
    ),
    child: Text(
      _getQualityLabel(),
      style: TextStyle(
        color: _getQualityBadgeColor(),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
),
```

Quality picker uses `CupertinoActionSheet`:

```dart
void _showQualityPicker() {
  showCupertinoModalPopup(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('Preview Quality'),
      message: const Text('Lower quality improves scrubbing performance'),
      actions: [
        _qualityAction('Full (2K)', PreviewQuality.full, 'Best quality'),
        _qualityAction('Half (1K)', PreviewQuality.half, 'Balanced'),
        _qualityAction('Quarter (480p)', PreviewQuality.quarter, 'Fastest scrubbing'),
        _qualityAction('Auto', PreviewQuality.auto, 'Full when paused, half when scrubbing'),
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

### 7.5 Persistence

`shared_preferences` key: `preview_quality` -> string (enum name). Default: `auto`.

### 7.6 Memory Savings

| Quality | Frame Cache (120 frames @ 1080p) | Savings |
|---------|----------------------------------|---------|
| Full | ~996 MB | baseline |
| Half | ~249 MB | 75% reduction |
| Quarter | ~62 MB | 94% reduction |
| Auto | ~249 MB during scrub, ~996 MB paused | 75% during active use |

Note: The existing frame cache system (from Timeline Architecture V2) already caps at 300MB / 120 frames. The quality setting primarily affects GPU texture memory and decode time, not the cache itself.

---

## 8. Onboarding Tutorial

### 8.1 First-Launch Detection

```dart
// In main.dart or ProjectLibraryView.initState:
final prefs = await SharedPreferences.getInstance();
final hasCompletedOnboarding = prefs.getBool('onboarding_complete') ?? false;

if (!hasCompletedOnboarding && mounted) {
  await Navigator.of(context).push(
    CupertinoPageRoute(
      fullscreenDialog: true,
      builder: (_) => const OnboardingView(),
    ),
  );
}
```

### 8.2 Tutorial Steps

| Step | Title | Description | Visual | Gesture Demo |
|------|-------|-------------|--------|-------------|
| 1 | Welcome to Liquid Editor | Your videos deserve a premium editing experience | App icon with glass effect | None |
| 2 | Import a Video | Tap the + button to import a video from your library | Screenshot of library with highlighted + button | Tap animation on + |
| 3 | Timeline Basics | Scroll to navigate, pinch to zoom, tap to select clips | Timeline mockup | Scroll + pinch animation |
| 4 | Trim and Split | Drag clip edges to trim, use Split to cut at the playhead | Timeline with trim handles highlighted | Drag handle animation |
| 5 | Smart Tracking | Automatically track people and reframe your video | Preview with tracking boxes | Auto-play tracking demo |
| 6 | Effects and Filters | Add color grading, effects, and adjustments | FX tab tools highlighted | Tab switch animation |
| 7 | Export and Share | Choose a preset and export your masterpiece | Export sheet mockup | Tap export animation |

### 8.3 OnboardingView Widget

```dart
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const _totalPages = 7;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.bgTop,
      child: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.bgTop, AppColors.bgBottom],
              ),
            ),
          ),

          // Page content
          PageView.builder(
            controller: _pageController,
            itemCount: _totalPages,
            onPageChanged: (index) {
              HapticFeedback.selectionClick();
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) => _buildPage(index),
          ),

          // Bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 32,
            child: Column(
              children: [
                // Progress dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_totalPages, (i) =>
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentPage ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _currentPage
                            ? AppColors.primary
                            : AppColors.glassWhite,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Next / Get Started button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: CupertinoButton.filled(
                    onPressed: _currentPage == _totalPages - 1
                        ? _completeOnboarding
                        : _nextPage,
                    child: Text(
                      _currentPage == _totalPages - 1
                          ? 'Get Started'
                          : 'Next',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Skip button (top-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _completeOnboarding,
              child: Text(
                'Skip',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop();
  }
}
```

### 8.4 Page Content Design

Each page follows this layout inside a `LiquidGlassPanel`:

```
Padding(all: 40)
 +-- Column(center)
      +-- Spacer(flex: 2)
      +-- AnimatedVisual (illustration or mockup)   240px height
      +-- SizedBox(height: 40)
      +-- Text(title, headline style)
      +-- SizedBox(height: 12)
      +-- Text(description, subtitle style, centered)
      +-- Spacer(flex: 3)
```

Illustrations can be:
- **Custom `CustomPainter` animations** for simple demos (e.g., a hand doing a pinch gesture)
- **Lottie animations** loaded from `assets/onboarding/` for more complex demos
- **Static assets** (PNG/SVG) for mockups

For v1, use `CustomPainter` + `AnimationController` for gesture animations, and screenshot mockups for UI demonstrations.

### 8.5 Re-Access from Settings

Add a "Show Tutorial" option to the project settings menu or a future Settings screen:

```dart
LiquidGlassPopupItem(
  icon: CupertinoIcons.question_circle,
  label: 'Show Tutorial',
  onTap: () {
    Navigator.pop(context); // Close settings
    Navigator.of(context).push(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => const OnboardingView(),
      ),
    );
  },
),
```

### 8.6 Haptic Feedback

| Event | Haptic |
|-------|--------|
| Page swipe | `HapticFeedback.selectionClick()` |
| Next button | `HapticFeedback.lightImpact()` |
| Get Started button | `HapticFeedback.mediumImpact()` |
| Skip button | `HapticFeedback.selectionClick()` |

---

## 9. Gesture Hints

### 9.1 Hint Types

| Hint ID | Gesture | Context | Animation |
|---------|---------|---------|-----------|
| `pinch_timeline` | Pinch to zoom | First time opening timeline | Two fingers pinching apart |
| `scroll_timeline` | Swipe to scroll | First time opening timeline | Single finger swiping left |
| `long_press_reorder` | Long press to reorder | First time with 2+ clips | Finger pressing down, then dragging |
| `double_tap_fullscreen` | Double tap for fullscreen | First time opening editor | Two quick taps |
| `pinch_preview` | Pinch to zoom preview | First time tapping preview | Two fingers pinching |
| `swipe_down_exit` | Swipe down to exit fullscreen | First time entering fullscreen | Finger swiping down |
| `drag_trim` | Drag edges to trim | First time selecting a clip | Finger dragging clip edge |

### 9.2 Display Logic

```dart
class GestureHintManager {
  static final GestureHintManager shared = GestureHintManager._();
  GestureHintManager._();

  final Map<String, int> _showCounts = {};
  static const _maxShows = 3; // Show each hint max 3 times

  Future<void> _loadCounts() async {
    final prefs = await SharedPreferences.getInstance();
    for (final hint in GestureHintType.values) {
      _showCounts[hint.id] = prefs.getInt('hint_${hint.id}') ?? 0;
    }
  }

  bool shouldShow(String hintId) {
    return (_showCounts[hintId] ?? 0) < _maxShows;
  }

  Future<void> markShown(String hintId) async {
    final count = (_showCounts[hintId] ?? 0) + 1;
    _showCounts[hintId] = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hint_$hintId', count);
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final hint in GestureHintType.values) {
      await prefs.remove('hint_${hint.id}');
      _showCounts[hint.id] = 0;
    }
  }
}
```

### 9.3 Hint Overlay Widget

```dart
class GestureHintOverlay extends StatefulWidget {
  final GestureHintType type;
  final VoidCallback onDismiss;

  const GestureHintOverlay({
    super.key,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<GestureHintOverlay> createState() => _GestureHintOverlayState();
}

class _GestureHintOverlayState extends State<GestureHintOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: CupertinoColors.black.withOpacity(0.3),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.glassBorder, width: 0.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated gesture icon
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CustomPaint(
                        painter: _GestureAnimationPainter(
                          type: widget.type,
                          progress: _animController,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.type.title,
                      style: AppTypography.title.copyWith(
                        color: CupertinoColors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.type.description,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                      onPressed: widget.onDismiss,
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### 9.4 Gesture Animation Painter

The `_GestureAnimationPainter` renders simple finger/hand animations:

- **Pinch:** Two circles moving apart/together
- **Swipe:** Circle moving left-to-right with trail
- **Long press:** Circle with expanding ring
- **Double tap:** Circle flashing twice
- **Drag:** Circle moving from point A to point B with path line

All drawn with `Paint` using `CupertinoColors.white` at 80% opacity, with motion tied to the `AnimationController` value. Finger circles are 12px radius, trails are 2px lines at 40% opacity.

### 9.5 Trigger Points

| Hint | Trigger Condition |
|------|------------------|
| `pinch_timeline` | `initState` of SmartEditView, after video loaded, if timeline visible |
| `scroll_timeline` | After `pinch_timeline` is dismissed |
| `long_press_reorder` | When clip count transitions from 1 to 2+ |
| `double_tap_fullscreen` | First 3 times SmartEditView is opened |
| `pinch_preview` | After `double_tap_fullscreen` is dismissed |
| `swipe_down_exit` | Immediately after entering fullscreen first time |
| `drag_trim` | When a clip is first selected |

---

## 10. Context-Sensitive Help

### 10.1 Architecture

Each tool button and significant control can have a help tooltip. The tooltip system uses the existing `LiquidGlassPopup` component for consistent styling.

### 10.2 Help Content Registry

```dart
class HelpContent {
  final String title;
  final String body;
  final String? deepLinkTutorialStep; // Optional: jump to specific onboarding step

  const HelpContent({
    required this.title,
    required this.body,
    this.deepLinkTutorialStep,
  });
}

const Map<String, HelpContent> helpRegistry = {
  'tool_trim': HelpContent(
    title: 'Trim',
    body: 'Drag the edges of a clip to shorten it from the start or end.',
    deepLinkTutorialStep: 'step_4',
  ),
  'tool_split': HelpContent(
    title: 'Split',
    body: 'Cut the selected clip at the current playhead position, creating two separate clips.',
  ),
  'tool_track': HelpContent(
    title: 'Track People',
    body: 'Analyze the video to detect and track people. Required before auto-reframe.',
    deepLinkTutorialStep: 'step_5',
  ),
  'tool_reframe': HelpContent(
    title: 'Auto Reframe',
    body: 'Automatically generate keyframes to keep tracked subjects in frame.',
  ),
  'tool_volume': HelpContent(
    title: 'Volume',
    body: 'Adjust the audio volume of the selected clip from 0% (mute) to 200% (boost).',
  ),
  'tool_speed': HelpContent(
    title: 'Speed',
    body: 'Change playback speed from 0.25x (slow motion) to 4x (fast forward).',
  ),
  'tool_export': HelpContent(
    title: 'Export',
    body: 'Render your edited video and save it to your photo library.',
    deepLinkTutorialStep: 'step_7',
  ),
  'timeline_overview': HelpContent(
    title: 'Timeline',
    body: 'Scroll to navigate through your video. Pinch to zoom in for precise editing. Tap a clip to select it.',
    deepLinkTutorialStep: 'step_3',
  ),
  'grid_overlay': HelpContent(
    title: 'Grid Overlay',
    body: 'Display composition guidelines over the video preview. Choose from rule of thirds, golden ratio, center cross, and more.',
  ),
  'safe_zones': HelpContent(
    title: 'Safe Zones',
    body: 'Show safe areas for different platforms (TikTok, Instagram, YouTube, broadcast). Keep important content within these zones.',
  ),
};
```

### 10.3 Info Button Pattern

Rather than adding (i) buttons next to every control (which would clutter the UI), use long-press on any tool button to show help:

```dart
class _ToolButtonWithHelp extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? helpKey;

  // ... standard _ToolButton fields ...

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (onPressed != null) {
          HapticFeedback.selectionClick();
          onPressed!();
        }
      },
      onLongPress: helpKey != null
          ? () {
              HapticFeedback.mediumImpact();
              _showHelp(context, helpKey!);
            }
          : null,
      child: /* existing _ToolButton UI */,
    );
  }

  void _showHelp(BuildContext context, String key) {
    final content = helpRegistry[key];
    if (content == null) return;

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(content.title),
        content: Text(content.body),
        actions: [
          if (content.deepLinkTutorialStep != null)
            CupertinoDialogAction(
              onPressed: () {
                Navigator.pop(context);
                // Navigate to tutorial at specific step
              },
              child: const Text('Show Tutorial'),
            ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
```

### 10.4 Accessibility

- VoiceOver reads `Semantics(label: helpContent.body)` for each tool button
- Help dialogs use `CupertinoAlertDialog` which is automatically VoiceOver-compatible
- Long-press hint is communicated via `Semantics(hint: 'Long press for help')`

---

## 11. Customizable Workspace

### 11.1 Preview/Timeline Size Ratio

Allow users to drag a handle between the video preview and the timeline to resize them.

#### 11.1.1 Size Constraints

| State | Preview Height | Timeline Area | Notes |
|-------|---------------|---------------|-------|
| **Default** | 450px | ~100px (ruler + clips) | Current layout |
| **Maximum preview** | 80% of available* | ~56px (collapsed) | Preview fills most of screen |
| **Maximum timeline** | 200px (minimum preview) | Remaining space | Detailed multi-track editing |

*Available height = screen height - top toolbar - playback controls - bottom toolbar - safe areas

#### 11.1.2 Implementation

Replace the fixed `SizedBox(height: 450)` with a flexible `Expanded` that respects a user-controlled ratio:

```dart
// State
double _previewHeightRatio = 0.65; // 0.3 - 0.8 range
static const _minPreviewRatio = 0.30;
static const _maxPreviewRatio = 0.80;

// In _buildMainContent:
Column(
  children: [
    _buildCapCutTopToolbar(),

    // Flexible preview area
    Expanded(
      flex: (_previewHeightRatio * 100).round(),
      child: _buildCapCutVideoPreview(),
    ),

    // Drag handle
    _buildWorkspaceHandle(),

    _buildCapCutPlaybackControls(),

    // Flexible timeline area
    Expanded(
      flex: ((1.0 - _previewHeightRatio) * 100).round(),
      child: _buildRulerAndTimelineWithPlayhead(),
    ),
  ],
),
```

#### 11.1.3 Drag Handle Widget

```dart
Widget _buildWorkspaceHandle() {
  return GestureDetector(
    onVerticalDragUpdate: (details) {
      final screenHeight = MediaQuery.of(context).size.height;
      final availableHeight = screenHeight
          - MediaQuery.of(context).padding.top
          - MediaQuery.of(context).padding.bottom
          - 44   // top toolbar
          - 44   // playback controls
          - 120; // bottom toolbar

      final delta = details.delta.dy / availableHeight;
      setState(() {
        _previewHeightRatio = (_previewHeightRatio + delta)
            .clamp(_minPreviewRatio, _maxPreviewRatio);
      });
    },
    onVerticalDragEnd: (_) {
      _saveWorkspacePreference();
      HapticFeedback.selectionClick();
    },
    child: Container(
      height: 20,
      color: CupertinoColors.transparent,
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.glassBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );
}
```

#### 11.1.4 Collapsed Timeline

When the timeline area is minimized (ratio > 0.75), collapse to show only:
- Playhead position line
- Minimal time indicator
- No thumbnails or waveforms

```dart
bool get _isTimelineCollapsed => _previewHeightRatio > 0.75;

Widget _buildCollapsedTimeline() {
  return Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Text(
          _viewModel.formattedTimelineCurrentTime,
          style: AppTypography.timecode,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CupertinoSlider(
            value: _viewModel.timelineProgress,
            onChanged: (value) => _viewModel.seekToProgress(value),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _viewModel.formattedTimelineDuration,
          style: AppTypography.timecode.copyWith(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}
```

#### 11.1.5 Persistence

`shared_preferences` key: `workspace_preview_ratio` -> double.

### 11.2 Double-Tap to Reset

Double-tap the drag handle to reset to default ratio (0.65):

```dart
GestureDetector(
  onDoubleTap: () {
    setState(() => _previewHeightRatio = 0.65);
    _saveWorkspacePreference();
    HapticFeedback.mediumImpact();
  },
  // ... existing onVerticalDrag handlers
)
```

---

## 12. Orientation Lock

### 12.1 Current Behavior

The app is portrait-only (`DeviceOrientation.portraitUp`). This is enforced in `main.dart` via `SystemChrome.setPreferredOrientations`.

### 12.2 Proposed Behavior

| Context | Orientation | User Control |
|---------|-------------|-------------|
| Project Library | Portrait only | Not configurable |
| Editor (normal) | Portrait only (default) | Lock button toggles landscape support |
| Editor (fullscreen) | Portrait + landscape | Always enabled in fullscreen |
| Onboarding | Portrait only | Not configurable |

### 12.3 Landscape Editor Layout

When the editor is in landscape mode:

```
Row
 +-- Expanded(flex: 6): Video preview (fills left side)
 +-- Container(width: 1, color: divider)
 +-- Expanded(flex: 4): Column
      +-- Playback controls (compact)
      +-- Ruler + Timeline (vertical scroll)
      +-- Bottom toolbar (compact, horizontal scroll)
```

Alternatively, a simpler landscape layout:

```
Column
 +-- Expanded: Video preview (wider, shorter)
 +-- SizedBox(height: 56): Ruler + timeline (full width)
 +-- SizedBox(height: ~80): Compact bottom toolbar
```

The simpler layout is recommended for v1 to minimize layout complexity.

### 12.4 Lock Toggle UI

Add orientation lock button to:
- **Editor top toolbar:** Small lock icon next to the 2K/quality badge
- **Fullscreen controls:** In the bottom control bar

```dart
CompactGlassIconButton(
  icon: _isOrientationLocked
      ? CupertinoIcons.lock_rotation
      : CupertinoIcons.lock_rotation_open,
  onPressed: () {
    setState(() => _isOrientationLocked = !_isOrientationLocked);
    if (_isOrientationLocked) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    HapticFeedback.selectionClick();
  },
  isSelected: !_isOrientationLocked,
),
```

### 12.5 Persistence

`shared_preferences` key: `orientation_locked` -> bool. Default: `true` (portrait only).

---

## 13. Accessibility

### 13.1 VoiceOver Labels

Every interactive element needs a `Semantics` wrapper:

```dart
// Tool buttons
Semantics(
  button: true,
  label: 'Split clip at playhead',
  hint: 'Double tap to split. Long press for help.',
  child: _ToolButton(icon: CupertinoIcons.scissors, label: 'Split', ...),
)

// Video preview
Semantics(
  label: 'Video preview. ${_viewModel.formattedTimelineCurrentTime} of ${_viewModel.formattedTimelineDuration}',
  hint: 'Double tap for fullscreen. Pinch to zoom.',
  child: _buildCapCutVideoPreview(),
)

// Timeline clips
Semantics(
  label: 'Video clip ${index + 1} of ${clipCount}. Duration: ${clip.formattedDuration}',
  hint: 'Tap to select. Long press to reorder.',
  child: TimelineClipWidget(...),
)
```

### 13.2 Dynamic Type Support

The `AppTypography.scaledStyle()` method already exists. Ensure all text uses it:

```dart
// Before (not accessible):
Text('Export', style: TextStyle(fontSize: 13))

// After (accessible):
Text('Export', style: AppTypography.scaledStyle(context, TextStyle(fontSize: 13)))
```

Minimum text sizes:
- Labels: 11pt minimum (iOS standard)
- Body text: 14pt minimum
- Timecodes: 12pt minimum (may use monospace which has different scaling)

### 13.3 Reduce Motion

Respect the system's "Reduce Motion" setting:

```dart
extension ReduceMotionContext on BuildContext {
  bool get reduceMotion =>
      MediaQuery.of(this).disableAnimations;
}

// Usage:
AnimatedContainer(
  duration: context.reduceMotion
      ? Duration.zero
      : const Duration(milliseconds: 200),
  // ...
)

// For custom animations:
if (!context.reduceMotion) {
  _animController.forward();
} else {
  _animController.value = 1.0; // Jump to end state
}
```

### 13.4 High Contrast

When the system high contrast mode is active, increase visual contrast:

```dart
// Check:
MediaQuery.of(context).highContrast

// Apply:
final borderColor = MediaQuery.of(context).highContrast
    ? CupertinoColors.white
    : AppColors.glassBorder;

final textColor = MediaQuery.of(context).highContrast
    ? CupertinoColors.white
    : AppColors.textSecondary;
```

### 13.5 Minimum Tap Targets

All interactive elements must have a minimum hit area of 44x44pt per Apple HIG:

```dart
// Already met by most design system components:
// - CircularGlassButton: 44pt default
// - GlassToolbarButton: 56px wide, 44px icon area
// - CompactGlassIconButton: 32px - NEEDS TO BE WRAPPED
//
// Fix for CompactGlassIconButton:
SizedBox(
  width: 44,
  height: 44,
  child: Center(
    child: CompactGlassIconButton(
      icon: CupertinoIcons.xmark,
      size: 32,
      onPressed: ...,
    ),
  ),
)
```

### 13.6 Color Blind Friendly Indicators

Never use color alone to convey state. Always pair with:
- Icons (checkmark for selected, x for error)
- Text labels
- Shape differences (filled vs. outline)

The existing design system already uses icon + label + color for most states. Audit required for:
- Timeline clip type colors (video purple, audio green, etc.) - add small type icon
- Tracking overlay colors - add person index labels (already present)
- Safe zone overlays - labels already included per section 5

---

## 14. Dark/Light Mode

### 14.1 Current State

The app is dark-mode only. `AppColors` defines a single dark palette. `AppTheme.dark` is the only theme.

### 14.2 Proposed Architecture

```dart
class AppColors {
  // Keep existing dark colors as-is

  // Add light mode equivalents:
  static Color bgTopLight = const Color(0xFFF2F2F7);
  static Color bgBottomLight = const Color(0xFFFFFFFF);
  static Color textPrimaryLight = const Color(0xFF000000);
  static Color textSecondaryLight = const Color(0xFF6C6C70);
  static Color glassWhiteLight = const Color(0x1A000000);
  static Color glassBorderLight = const Color(0x33000000);
  // ... etc

  // Semantic accessors that respect the current theme:
  static Color bgTop(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.dark
          ? const Color(0xFF0A0A0F)
          : const Color(0xFFF2F2F7);

  // Or use CupertinoTheme.of(context) for system colors
}
```

### 14.3 Recommended Approach

Use `CupertinoColors` system colors which automatically adapt:

| Dark Mode Color | Light Mode Equivalent | Cupertino Adaptive |
|----------------|----------------------|-------------------|
| `AppColors.bgTop` (0x0A0A0F) | 0xF2F2F7 | `CupertinoColors.systemBackground` |
| `AppColors.textPrimary` (0xF0F6FC) | 0x000000 | `CupertinoColors.label` |
| `AppColors.textSecondary` (0x8B949E) | 0x6C6C70 | `CupertinoColors.secondaryLabel` |
| `AppColors.glassBorder` (0x33FFFFFF) | 0x33000000 | `CupertinoColors.separator` |

### 14.4 Implementation Plan

1. Introduce `CupertinoThemeData` with both brightness variants
2. Replace hardcoded `AppColors` references with `CupertinoColors` equivalents where possible
3. Add `CupertinoTheme` wrapper at the root
4. Custom painters receive `Brightness` parameter to select colors
5. Liquid Glass effects: change blur background tint based on brightness

### 14.5 Toggle

```dart
// In a Settings screen or project library:
CupertinoSwitch(
  value: _isDarkMode,
  onChanged: (value) {
    setState(() => _isDarkMode = value);
    // Save to SharedPreferences
  },
)

// Options:
// - 'system' (follow device setting) - DEFAULT
// - 'dark' (always dark)
// - 'light' (always light)
```

### 14.6 Priority

**LOW.** The dark theme is well-suited for video editing (reduces eye strain, makes video colors more accurate). Light mode is a nice-to-have for users who prefer it, but should not delay the higher-priority features.

---

## 15. Edge Cases

### 15.1 Screen Size Variations

| Device | Screen Height (pt) | Preview Height | Timeline | Notes |
|--------|-------------------|----------------|----------|-------|
| iPhone SE (3rd gen) | 667 | 350 (reduced from 450) | 56 | Limited space, collapse toolbar |
| iPhone 14 | 844 | 450 | 56 | Default target |
| iPhone 16 Pro | 852 | 450 | 56 | Default target |
| iPhone 16 Pro Max | 932 | 500+ | 80+ | Extra space for timeline |

**Adaptive preview height:**

```dart
double _getDefaultPreviewHeight(BuildContext context) {
  final screenHeight = MediaQuery.of(context).size.height;
  if (screenHeight < 700) return 320;  // SE
  if (screenHeight < 850) return 420;  // Standard
  if (screenHeight < 900) return 450;  // Pro
  return 500;                           // Pro Max
}
```

With the customizable workspace feature (section 11), the fixed height becomes a default that users can adjust.

### 15.2 Dynamic Island

The existing `SafeArea` handles Dynamic Island properly. In fullscreen mode, use `SystemUiMode.immersiveSticky` to hide the status bar and reclaim that space.

For the grid and safe zone overlays, they render inside the video `ClipRRect` which is already properly inset, so no Dynamic Island intersection.

### 15.3 Notch in Landscape

When landscape mode is enabled (section 12), the notch/Dynamic Island creates a larger safe area on one side:

```dart
// Use MediaQuery.of(context).padding which respects orientation:
final leftPadding = MediaQuery.of(context).padding.left;   // 0 or ~47 (notch side)
final rightPadding = MediaQuery.of(context).padding.right;  // 0 or ~47 (notch side)
```

Ensure the video preview is centered between safe areas, not shifted to one side.

### 15.4 VoiceOver During Playback

When VoiceOver is active and video is playing:
- Announce time updates every 5 seconds (not every frame)
- Play/pause is the first VoiceOver focus target
- Swipe gestures do not conflict with VoiceOver navigation (VoiceOver uses different gesture system)

```dart
// Check if VoiceOver is active:
MediaQuery.of(context).accessibleNavigation

// Reduce update frequency:
if (MediaQuery.of(context).accessibleNavigation) {
  // Announce every 5 seconds instead of every frame
  if (_viewModel.currentTime.inSeconds % 5 == 0) {
    SemanticsService.announce(
      'Playback at ${_viewModel.formattedTimelineCurrentTime}',
      TextDirection.ltr,
    );
  }
}
```

### 15.5 Reduced Motion During Transitions

When `MediaQuery.of(context).disableAnimations` is true:
- Page transitions: instant (no slide or fade)
- Onboarding: static images instead of animated demos
- Gesture hints: show static diagram instead of animation
- Grid/safe zone toggle: instant visibility change (no fade)
- Fullscreen entry/exit: instant (no scale/fade)
- Controls auto-hide: instant (no opacity animation)

### 15.6 Low Power Mode

Detect via `ProcessInfo.processInfo.isLowPowerModeEnabled` (native side) and reduce:
- Background liquid orb animation: stop or reduce to 5fps
- Backdrop blur sigma: reduce from 30 to 10
- Frame cache prefetch: reduce from 120 to 30 frames
- Auto quality: force half resolution during scrubbing

### 15.7 Memory Pressure

When receiving memory warnings via `didReceiveMemoryWarning`:
- Clear grid/safe zone CustomPainter caches
- Release comparison view second frame
- Reduce preview quality to quarter
- Dismiss onboarding animations

---

## 16. Performance Budget

### 16.1 Overlay Rendering Cost

| Feature | Render Time per Frame | GPU Impact | Memory Impact |
|---------|----------------------|------------|---------------|
| Grid overlay (CustomPainter) | < 0.05ms | Negligible | ~1 KB (paint cache) |
| Safe zone overlay (CustomPainter) | < 0.1ms | Negligible | ~2 KB (paint cache) |
| Combined grid + safe zone | < 0.15ms | Negligible | ~3 KB |
| Comparison view (split) | < 0.5ms (clip path) | +1 texture | +8 MB (1080p RGBA) |
| Comparison view (toggle) | < 0.3ms (cross fade) | Briefly 2 textures | +8 MB during transition |
| Gesture hint overlay | < 0.1ms | Negligible (BackdropFilter reused) | ~5 KB |
| Onboarding page | < 1ms (Lottie decode) | Moderate (animation) | ~2 MB (Lottie assets) |
| Workspace resize | < 0.1ms (layout) | Negligible | None |

### 16.2 Frame Rate Impact

All overlay features maintain 60fps because:
- `CustomPainter` is cached via `shouldRepaint` (only repaints on config change)
- Overlays use `RepaintBoundary` to isolate from video repaints
- `BackdropFilter` blur is GPU-accelerated and only computed when the underlying content changes

### 16.3 Memory Budget Compliance

| Scenario | Memory Usage | Budget (200MB) | Status |
|----------|-------------|----------------|--------|
| Normal editing | ~120 MB | OK | Baseline |
| + Grid + Safe zones | ~120.003 MB | OK | Negligible |
| + Comparison split | ~128 MB | OK | +8 MB for second frame |
| + Quarter quality | ~90 MB | OK | 25% reduction |
| + Onboarding loaded | ~122 MB | OK | +2 MB assets |
| Worst case (all enabled) | ~130 MB | OK | Well within budget |

### 16.4 Startup Impact

| Feature | Startup Cost | Strategy |
|---------|-------------|----------|
| Grid config load | < 1ms | `SharedPreferences` (cached) |
| Safe zone config load | < 1ms | `SharedPreferences` (cached) |
| Quality preference load | < 1ms | `SharedPreferences` (cached) |
| Gesture hint counts load | < 2ms | `SharedPreferences` (cached) |
| Onboarding check | < 1ms | Single bool read |
| Workspace ratio load | < 1ms | `SharedPreferences` (cached) |
| **Total additional startup** | **< 5ms** | **No impact on 2s budget** |

---

## 17. Implementation Plan

### Phase 1: Visual Overlays (Priority: High)

**Duration:** 3-4 days

| Task | File(s) | Est. Hours |
|------|---------|-----------|
| Grid overlay CustomPainter | `lib/overlays/grid_overlay.dart` | 3 |
| Safe zone overlay CustomPainter | `lib/overlays/safe_zone_overlay.dart` | 4 |
| Grid type picker UI | `smart_edit_view.dart` (project settings) | 2 |
| Safe zone picker UI | `smart_edit_view.dart` (project settings) | 2 |
| Persistence (SharedPreferences) | `lib/core/user_preferences.dart` | 2 |
| Integration in video preview | `smart_edit_view.dart` | 2 |
| Integration in fullscreen view | `smart_edit_view.dart` | 1 |
| Tests | `test/grid_overlay_test.dart`, `test/safe_zone_overlay_test.dart` | 3 |

### Phase 2: Full-Screen Preview Enhancement (Priority: High)

**Duration:** 2-3 days

| Task | File(s) | Est. Hours |
|------|---------|-----------|
| Enhanced fullscreen controls | `smart_edit_view.dart` | 3 |
| Auto-hide timer system | `smart_edit_view.dart` | 2 |
| Swipe-down exit gesture | `smart_edit_view.dart` | 2 |
| Double-tap entry from preview | `smart_edit_view.dart` | 1 |
| Landscape support in fullscreen | `smart_edit_view.dart` | 3 |
| Status bar hiding | `smart_edit_view.dart` | 1 |
| Hero/scale transition animation | `smart_edit_view.dart` | 3 |
| Tests | `test/fullscreen_preview_test.dart` | 2 |

### Phase 3: Comparison View + Preview Quality (Priority: Medium)

**Duration:** 3-4 days

| Task | File(s) | Est. Hours |
|------|---------|-----------|
| Split screen comparison widget | `lib/overlays/comparison_overlay.dart` | 4 |
| Toggle comparison mode | `lib/overlays/comparison_overlay.dart` | 2 |
| Comparison button in FX tab | `editor_bottom_toolbar.dart` | 1 |
| Preview quality native implementation | `ios/Runner/AppDelegate.swift` | 3 |
| Preview quality Flutter channel | `lib/core/preview_quality_service.dart` | 2 |
| Quality badge UI (replace 2K) | `smart_edit_view.dart` | 2 |
| Auto quality (scrub detection) | `smart_edit_view.dart` | 2 |
| Tests | `test/comparison_view_test.dart`, `test/preview_quality_test.dart` | 3 |

### Phase 4: Onboarding + Gesture Hints + Help (Priority: Medium)

**Duration:** 4-5 days

| Task | File(s) | Est. Hours |
|------|---------|-----------|
| OnboardingView scaffold + pages | `lib/views/onboarding/onboarding_view.dart` | 4 |
| Gesture animation painters | `lib/views/onboarding/gesture_animations.dart` | 4 |
| First-launch detection | `lib/main.dart`, `project_library_view.dart` | 1 |
| GestureHintManager | `lib/core/gesture_hint_manager.dart` | 2 |
| GestureHintOverlay widget | `lib/overlays/gesture_hint_overlay.dart` | 3 |
| Hint trigger integration | `smart_edit_view.dart` | 2 |
| Help content registry | `lib/core/help_content.dart` | 2 |
| Long-press help on tool buttons | `editor_bottom_toolbar.dart` | 2 |
| Tests | `test/onboarding_test.dart`, `test/gesture_hint_test.dart` | 3 |

### Phase 5: Customizable Workspace + Orientation (Priority: Low)

**Duration:** 3-4 days

| Task | File(s) | Est. Hours |
|------|---------|-----------|
| Workspace drag handle | `smart_edit_view.dart` | 3 |
| Flexible preview/timeline layout | `smart_edit_view.dart` | 3 |
| Collapsed timeline mode | `smart_edit_view.dart` | 2 |
| Orientation lock toggle | `smart_edit_view.dart` | 2 |
| Landscape editor layout (basic) | `smart_edit_view.dart` | 4 |
| Persistence | `lib/core/user_preferences.dart` | 1 |
| Tests | `test/workspace_test.dart` | 2 |

### Phase 6: Accessibility + Dark/Light Mode (Priority: Low)

**Duration:** 3-4 days

| Task | File(s) | Est. Hours |
|------|---------|-----------|
| VoiceOver labels audit | All view files | 3 |
| Dynamic Type audit | All view files | 2 |
| Reduce Motion support | All animated widgets | 2 |
| High Contrast support | `glass_styles.dart`, all painters | 2 |
| Minimum tap target audit | All interactive widgets | 2 |
| Light mode color palette | `glass_styles.dart` | 3 |
| CupertinoTheme integration | `main.dart`, `glass_styles.dart` | 3 |
| Theme toggle UI | Settings menu | 1 |
| Tests | `test/accessibility_test.dart` | 3 |

### Total Estimate

| Phase | Duration | Hours |
|-------|----------|-------|
| Phase 1: Visual Overlays | 3-4 days | ~19 hrs |
| Phase 2: Fullscreen Preview | 2-3 days | ~17 hrs |
| Phase 3: Comparison + Quality | 3-4 days | ~19 hrs |
| Phase 4: Onboarding + Hints + Help | 4-5 days | ~23 hrs |
| Phase 5: Workspace + Orientation | 3-4 days | ~17 hrs |
| Phase 6: Accessibility + Light Mode | 3-4 days | ~21 hrs |
| **Total** | **~18-24 days** | **~116 hrs** |

---

## 18. File Structure

```
lib/
  overlays/
    grid_overlay.dart           # GridOverlayPainter + GridOverlayConfig
    safe_zone_overlay.dart      # SafeZonePainter + SafeZoneConfig + SafeZonePreset
    comparison_overlay.dart     # ComparisonView + SplitClipper + ComparisonConfig
    gesture_hint_overlay.dart   # GestureHintOverlay + GestureAnimationPainter
  views/
    onboarding/
      onboarding_view.dart      # OnboardingView (PageView + step pages)
      onboarding_page.dart      # Individual page widget
      gesture_animations.dart   # CustomPainter animations for gesture demos
    smart_edit/
      smart_edit_view.dart      # Modified: grid/safe zone/comparison integration
      editor_bottom_toolbar.dart # Modified: comparison toggle, help long-press
  core/
    user_preferences.dart       # Centralized SharedPreferences wrapper
    gesture_hint_manager.dart   # Gesture hint show/count logic
    help_content.dart           # Help registry (tool descriptions)
    preview_quality_service.dart # Native quality scaling bridge
  design_system/
    glass_styles.dart           # Modified: light mode colors, adaptive helpers

ios/Runner/
  AppDelegate.swift             # Modified: setPreviewQuality handler

test/
  grid_overlay_test.dart
  safe_zone_overlay_test.dart
  comparison_view_test.dart
  preview_quality_test.dart
  onboarding_test.dart
  gesture_hint_test.dart
  workspace_test.dart
  accessibility_test.dart
```

---

## 19. Test Plan

### 19.1 Unit Tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `grid_overlay_test.dart` | GridOverlayConfig defaults, copyWith, all grid type line calculations | GridOverlayPainter |
| `safe_zone_overlay_test.dart` | SafeZoneConfig defaults, inset calculations for each preset, label text | SafeZonePainter |
| `comparison_view_test.dart` | ComparisonConfig state transitions, split position clamping | ComparisonConfig |
| `preview_quality_test.dart` | Quality enum values, scale factors, memory estimates | PreviewQuality |
| `gesture_hint_test.dart` | Show count tracking, max shows, reset | GestureHintManager |
| `workspace_test.dart` | Ratio clamping, collapsed threshold, persistence | Workspace config |

### 19.2 Widget Tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `grid_overlay_test.dart` | Renders correct number of lines for each grid type at 300x400 size | GridOverlayPainter rendering |
| `safe_zone_overlay_test.dart` | Renders correct inset rectangles, labels visible when enabled | SafeZonePainter rendering |
| `onboarding_test.dart` | PageView navigation, skip button, progress dots, completion callback | OnboardingView |
| `gesture_hint_test.dart` | Overlay appears, auto-dismiss timer, "Got it" button | GestureHintOverlay |
| `accessibility_test.dart` | Semantics labels present, minimum tap targets met, Dynamic Type scaling | All interactive widgets |

### 19.3 Integration Tests

| Scenario | Steps | Expected Result |
|----------|-------|----------------|
| Grid toggle during editing | Open editor, enable grid, verify lines on preview, play video, verify grid stays, change grid type, verify new grid | Grid renders correctly at all times |
| Safe zone with grid | Enable both grid and safe zone, verify both render without conflicts | Overlays stack correctly |
| Fullscreen with overlays | Enable grid + safe zone, enter fullscreen, verify overlays scale correctly | Overlays match video bounds in fullscreen |
| Comparison split drag | Enable comparison split, drag divider, verify clip regions update | Smooth divider drag at 60fps |
| Quality toggle during scrub | Set quality to Auto, scrub timeline, verify quality drops, pause, verify quality restores | Smooth quality transitions |
| Onboarding completion | Fresh install, verify onboarding shows, complete all steps, verify flag saved, restart, verify onboarding skipped | One-time onboarding |
| Workspace resize | Drag workspace handle, verify preview and timeline resize, exit and reopen, verify persisted | Layout persistence |

### 19.4 Performance Tests

| Test | Metric | Target |
|------|--------|--------|
| Grid overlay paint time | `Timeline` in DevTools | < 0.1ms per frame |
| Safe zone overlay paint time | `Timeline` in DevTools | < 0.1ms per frame |
| Comparison split render | `Timeline` in DevTools | < 0.5ms per frame |
| Fullscreen transition | Stopwatch | < 300ms total |
| Workspace resize (drag) | Frame rate during drag | 60fps maintained |
| Onboarding page transition | Frame rate during swipe | 60fps maintained |

---

## Appendix A: SF Symbol Names for CNSymbol

| Feature | Symbol | Usage |
|---------|--------|-------|
| Grid overlay | `grid` or `squareshape.split.3x3` | Grid toggle button |
| Safe zones | `rectangle.center.inset.filled` | Safe zone toggle |
| Fullscreen | `arrow.up.left.and.arrow.down.right` | Enter fullscreen |
| Exit fullscreen | `arrow.down.right.and.arrow.up.left` | Exit fullscreen |
| Comparison | `square.split.1x2` | Compare toggle |
| Quality | `dial.low` / `dial.medium` / `dial.high` | Quality badge |
| Help | `questionmark.circle` | Help button |
| Orientation lock | `lock.rotation` / `lock.rotation.open` | Lock toggle |
| Onboarding skip | `forward.end` | Skip button |
| Gesture hint dismiss | `checkmark.circle` | Got it button |

---

## Appendix B: Shared Preferences Key Registry

| Key | Type | Default | Feature |
|-----|------|---------|---------|
| `onboarding_complete` | bool | false | Onboarding |
| `grid_type` | String | "ruleOfThirds" | Grid overlay |
| `grid_visible` | bool | false | Grid overlay |
| `grid_opacity` | double | 0.5 | Grid overlay |
| `grid_custom_rows` | int | 3 | Grid overlay |
| `grid_custom_cols` | int | 3 | Grid overlay |
| `safe_zone_title_safe` | bool | false | Safe zones |
| `safe_zone_action_safe` | bool | false | Safe zones |
| `safe_zone_tiktok` | bool | false | Safe zones |
| `safe_zone_instagram` | bool | false | Safe zones |
| `safe_zone_youtube` | bool | false | Safe zones |
| `safe_zone_broadcast` | bool | false | Safe zones |
| `safe_zone_custom` | bool | false | Safe zones |
| `safe_zone_custom_top` | double | 10.0 | Safe zones |
| `safe_zone_custom_bottom` | double | 10.0 | Safe zones |
| `safe_zone_custom_left` | double | 10.0 | Safe zones |
| `safe_zone_custom_right` | double | 10.0 | Safe zones |
| `safe_zone_show_labels` | bool | true | Safe zones |
| `preview_quality` | String | "auto" | Preview quality |
| `workspace_preview_ratio` | double | 0.65 | Workspace |
| `orientation_locked` | bool | true | Orientation |
| `hint_pinch_timeline` | int | 0 | Gesture hints |
| `hint_scroll_timeline` | int | 0 | Gesture hints |
| `hint_long_press_reorder` | int | 0 | Gesture hints |
| `hint_double_tap_fullscreen` | int | 0 | Gesture hints |
| `hint_pinch_preview` | int | 0 | Gesture hints |
| `hint_swipe_down_exit` | int | 0 | Gesture hints |
| `hint_drag_trim` | int | 0 | Gesture hints |
| `theme_mode` | String | "system" | Dark/Light mode |

---

## Appendix C: Design System Additions

### New Colors (to add to AppColors)

```dart
// Grid overlay
static const Color gridLine = Color(0xBFFFFFFF);     // White 75%
static const Color gridShadow = Color(0x80000000);    // Black 50%

// Safe zone colors (from CupertinoColors, stored for CustomPainter use)
static const Color safeZoneTitleSafe = Color(0x99FFCC00);   // Yellow 60%
static const Color safeZoneActionSafe = Color(0x8034C759);  // Green 50%
static const Color safeZoneTikTok = Color(0x80FF2D55);      // Pink 50%
static const Color safeZoneInstagram = Color(0x80AF52DE);   // Purple 50%
static const Color safeZoneYouTube = Color(0x80FF3B30);     // Red 50%
static const Color safeZoneBroadcast = Color(0x8030B0C7);   // Teal 50%
static const Color safeZoneCustom = Color(0x80007AFF);      // Blue 50%

// Comparison
static const Color comparisonDivider = Color(0xFFFFFFFF);   // White 100%
static const Color comparisonLabel = Color(0xBFFFFFFF);      // White 75%
```

### New Typography (to add to AppTypography)

```dart
// Overlay labels (grid type name, safe zone labels)
static const TextStyle overlayLabel = TextStyle(
  fontFamily: fontFamily,
  fontSize: 10,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.3,
  color: Color(0xBFFFFFFF), // White 75%
  shadows: [
    Shadow(color: Color(0x80000000), blurRadius: 4),
  ],
);

// Onboarding title
static const TextStyle onboardingTitle = TextStyle(
  fontFamily: fontFamily,
  fontSize: 24,
  fontWeight: FontWeight.w700,
  letterSpacing: -0.5,
  color: Color(0xFFF0F6FC),
);

// Onboarding body
static const TextStyle onboardingBody = TextStyle(
  fontFamily: fontFamily,
  fontSize: 16,
  fontWeight: FontWeight.w400,
  height: 1.4,
  color: Color(0xFF8B949E),
);
```

---

## Review 1 - Architecture & Completeness

**Reviewer:** Claude Opus 4.6 (Senior Architect)
**Date:** 2026-02-06
**Scope:** Architecture, completeness, feasibility, iOS 26 compliance, edge cases, performance, accessibility, UX

### Summary

This is a thorough and well-structured design document. All 10 stated UI/UX features are covered (full-screen, grid, safe zones, comparison, preview quality, onboarding, gesture hints, context-sensitive help, customizable workspace, orientation lock), plus two bonus sections (accessibility, dark/light mode). The code samples are concrete and generally correct. The performance budget analysis is credible and methodical. Below are issues categorized by severity.

---

### CRITICAL Issues

**C1. Comparison View: CompositionPlayerView Duplication Will Crash**

The split-screen and side-by-side comparison modes (Section 6.4) assume you can render two `VideoPlayer` widgets from the same controller. However, the codebase comment at line 1269 of `smart_edit_view.dart` states:

> "CRITICAL: Once CompositionPlayerView is created, it must NEVER be removed from the widget tree, or PlatformException will occur on recreation."

The current architecture uses a `CompositionPlayerView` (native platform view) for multi-clip playback, not a pure-Dart `VideoPlayer`. Section 6.6 proposes `_buildOriginalVideoFrame()` and `_buildProcessedVideoFrame()` using `VideoPlayer(controller)`, but when the editor is in composition playback mode, the video is rendered via `CompositionPlayerView` -- a native iOS platform view that cannot be instantiated twice from the same backing view. The design must address:
- How the "original" frame is obtained when using `CompositionPlayerView` (there is no second AVPlayer to render the untransformed frame)
- A fallback strategy: capture a snapshot texture from the native side for the "original" frame, or use a `RepaintBoundary` + `toImage()` approach on the processed frame, then render the original by requesting a raw frame via platform channel

**Recommendation:** Add a `getOriginalFrame(timestamp)` platform channel method that returns a `Uint8List` RGBA bitmap without transforms. In split/side-by-side mode, display the original as a `RawImage` or `Image.memory` rather than a second video player widget.

**C2. Workspace Resize: Fixed Height Replaced by Flex, But EditorBottomToolbar is Positioned**

Section 11.1.2 replaces `SizedBox(height: 450)` with `Expanded(flex: ...)` inside a `Column`. However, the current layout (line 757 of `smart_edit_view.dart`) uses a `Stack` where `EditorBottomToolbar` is `Positioned(bottom: 0)`. Introducing `Expanded` for the preview and timeline inside a `Column` that is itself inside a `Stack` with a `Positioned` bottom toolbar creates a layout conflict:
- The `Column` with `Expanded` children will fill the available `Stack` space, but the bottom toolbar overlay occupies ~120px at the bottom. Unless the Column accounts for this overlap, the timeline will be hidden behind the toolbar.
- The current code at line 766 uses a fixed `SizedBox(height: 450)` with `_buildRulerAndTimelineWithPlayhead()` taking remaining space, and the bottom toolbar overlaps the bottom portion. Switching to `Expanded` without adding bottom padding equal to the toolbar height will break the layout.

**Recommendation:** Either (a) add `SizedBox(height: 120)` at the bottom of the `Column` to reserve space for the overlapping toolbar, or (b) restructure to put the toolbar inside the `Column` instead of using `Positioned`, or (c) keep the `Positioned` toolbar but wrap the `Column` in a `Padding(bottom: 120)`.

**C3. Fullscreen Hero Animation Conflicts With Platform View Lifecycle**

Section 3.2.4 proposes a `Hero` animation wrapping the video preview. The `CompositionPlayerView` is a native iOS platform view with strict lifecycle constraints (cannot be removed from widget tree). A `Hero` animation moves the widget from one route's widget tree to another during a page transition. This will either:
- Reparent the platform view (causing a PlatformException), or
- Require recreating it in the hero destination (also causing PlatformException per the existing codebase constraints)

The document acknowledges this risk ("If Hero animation causes platform view issues... fall back to a custom AnimationController") but does not detail the fallback implementation.

**Recommendation:** Remove the Hero approach entirely and commit to the custom `AnimationController` path. Specify the fallback fully: animate a `Positioned` widget that scales from preview bounds to screen bounds over a `Stack`, keeping the `CompositionPlayerView` permanently mounted. The fullscreen should be an overlay within the same `Stack`, not a separate route.

---

### IMPORTANT Issues

**I1. Safe Zone Insets Use `size.width` for Title/Action Safe Vertical Calculations**

In Section 5.4, `_getInsets` for `titleSafe` and `actionSafe` both use `EdgeInsets.all(size.width * 0.1)` and `EdgeInsets.all(size.width * 0.05)`. This means vertical insets are calculated as a percentage of the frame *width*, not *height*. For a 9:16 portrait video, a 10% width-based inset produces a much smaller vertical margin than expected. Broadcast title-safe standards define 10% of *each dimension* (10% of width on sides, 10% of height on top/bottom).

**Recommendation:** Change to `EdgeInsets.symmetric(horizontal: size.width * 0.1, vertical: size.height * 0.1)` for title safe, and analogously for action safe.

**I2. No `copyWith` Method Defined for Data Models**

Sections 4.2, 5.3, 6.3 reference `_gridConfig.copyWith(...)`, `_safeZoneConfig.copyWith(...)`, and `_comparisonConfig.copyWith(...)`, but the class definitions shown do not include `copyWith` implementations. While this may seem like an implementation detail, the design should specify whether these classes are `@immutable` with generated `copyWith` (e.g., via `freezed`) or hand-written.

**Recommendation:** Add `copyWith` method signatures to each data model in the design, or specify that the `freezed` code generation package will be used.

**I3. Gesture Hint Manager Uses Singleton Pattern With Async Init**

Section 9.2 defines `GestureHintManager.shared` as a singleton with `_loadCounts()` as an async method. If `shouldShow()` is called before `_loadCounts()` completes, `_showCounts` will be empty and all hints will show. There is no initialization guard.

**Recommendation:** Either (a) make `_loadCounts()` run in the constructor and expose a `Future<void> get ready` that callers await, or (b) use a `late final Future<void> _initFuture` pattern with a `FutureBuilder` at call sites, or (c) load hint counts synchronously from `SharedPreferences` in `main()` before `runApp()` and inject them.

**I4. Fullscreen Controls Timer Leak on Rapid Tap**

Section 3.2.2 creates a new `Timer` on every `_resetControlsTimer()` call. While the previous timer is cancelled, rapid tapping could cause frequent `setState` calls. More importantly, the timer is not cancelled in `dispose()`, which could cause a `setState on disposed widget` error if the user exits the screen during the timer's 3-second window.

**Recommendation:** Add `_controlsHideTimer?.cancel()` to the widget's `dispose()` method. Document this in the design.

**I5. Preview Quality: `preferredMaximumResolution` Does Not Work on All Content**

Section 7.2.1 relies on `AVPlayerItem.preferredMaximumResolution`. This property only affects HLS/adaptive streaming content. For local file playback (which is the primary use case in a video editor), this property is ignored. The actual rendered resolution is determined by the player layer's bounds and content mode.

**Recommendation:** For local files, implement quality scaling by adjusting the `AVPlayerLayer` frame size or by rendering to a smaller `CVPixelBuffer` via `AVPlayerItemVideoOutput`. Update the design to reflect this distinction.

**I6. `withOpacity()` Deprecation**

Multiple code samples use `.withOpacity()` (e.g., `CupertinoColors.systemYellow.withOpacity(0.6)`). The existing codebase at `liquid_glass_popup.dart` already uses the newer `.withValues(alpha: ...)` API. The design should be consistent.

**Recommendation:** Replace all `.withOpacity()` calls with `.withValues(alpha: ...)` to match the existing codebase pattern and avoid deprecation warnings.

**I7. Landscape Layout is Underspecified**

Section 12.3 provides two alternative landscape layouts but does not commit to either. It says "simpler layout is recommended for v1" but does not detail how the bottom toolbar adapts in landscape, how overlays (tracking, grid, safe zones) reposition, or how the workspace resize handle behaves in landscape orientation.

**Recommendation:** Fully specify the chosen landscape layout, including toolbar placement, overlay behavior, and workspace handle orientation (vertical drag becomes horizontal drag?). Consider whether landscape support should be deferred entirely to a later version to reduce scope.

**I8. Missing State Management Strategy for New Features**

The design adds significant new state (`GridOverlayConfig`, `SafeZoneConfig`, `ComparisonConfig`, `PreviewQuality`, workspace ratio, orientation lock, gesture hints). All of this appears to be local widget state in `SmartEditView`. The view is already state-heavy (30+ state variables visible in the first 105 lines). The design does not address:
- Whether any of this state should move to `SmartEditViewModel`
- How state is communicated between normal editor and fullscreen (currently shared via `_viewModel.isFullscreen`, but grid/safe zone toggles need sharing too)
- Whether a dedicated `OverlayConfigNotifier` or similar separation is warranted

**Recommendation:** Specify which state lives in the ViewModel versus the View. Consider a dedicated `EditorOverlayState` class or similar to group overlay-related state and prevent further bloat of `SmartEditView`.

---

### MINOR Issues

**M1. Onboarding Step Count Mismatch Risk**

Section 8.2 lists 7 steps, and `_totalPages = 7`. However, the step content depends on features that may not all be implemented (e.g., step 6 references "Effects and Filters" which is a future feature). If the onboarding is built before the referenced features, the screenshots/demos will be inaccurate.

**Recommendation:** Add a note that onboarding pages should be feature-gated -- only show pages for features that are actually implemented. Consider a `List<OnboardingStep>` that is built dynamically based on feature flags.

**M2. Grid `squareGrid` Description Says "4x4 or 8x8" But Implementation is Only 4x4**

Section 4.1 describes `squareGrid` as "4x4 or 8x8 even grid" but the `_drawGrid` call in Section 4.3 passes `(4, 4)` only. There is no way to select 8x8.

**Recommendation:** Either remove the "or 8x8" claim, or add a configuration option for square grid density.

**M3. Custom Grid Validation Missing**

The `GridOverlayConfig` allows `customRows` and `customColumns` with default 3, but there are no bounds. A user could set `customRows = 0` or `customRows = 1000`, causing either division-by-zero or rendering thousands of lines.

**Recommendation:** Add validation: `customRows.clamp(2, 20)`, `customColumns.clamp(2, 20)`.

**M4. Safe Zone Picker Dismissal UX**

Section 5.6 uses a `CupertinoActionSheet` with multi-select. However, action sheets are not standard for multi-select in iOS HIG; they are intended for single-action selection. Each tap on a zone also calls `setState` on the parent widget, which will rebuild behind the modal -- this is correct but the `setSheetState` call is needed to update checkmarks in the sheet itself. The `setSheetState` call needs to access the outer `_safeZoneConfig` which is in the parent scope, creating a coupling.

**Recommendation:** Consider using a `CupertinoListSection` inside a modal popup route instead, which is more idiomatic for multi-select on iOS. Alternatively, use `showCupertinoModalPopup` with a custom `StatefulWidget` that manages its own local state and calls back on dismiss.

**M5. Appendix A: Some SF Symbol Names May Not Exist**

`lock.rotation` and `lock.rotation.open` (used in Section 12.4 and Appendix A) are not standard SF Symbols. The correct names are likely `lock.rotation` (which does exist in SF Symbols 5) and `lock.open.rotation` or similar. Verify against the SF Symbols app.

**Recommendation:** Validate all SF Symbol names against the SF Symbols 5 catalog before implementation.

**M6. Missing `_dDrawDashedRect` Implementation**

Section 5.4 calls `_drawDashedRect(canvas, rect, paint)` but does not provide the implementation. Dashed line drawing in Flutter's Canvas requires manual segment calculation since there is no built-in dashed line API.

**Recommendation:** Include the `_drawDashedRect` implementation in the design, or reference a utility like `path_drawing` package or a `CustomPainter` helper.

**M7. Onboarding `TextStyle` Hardcodes Colors Instead of Using Design System**

Section 8.3 uses `AppColors.primary` and `AppColors.textSecondary` directly (which is correct for dark mode), but the skip button text uses inline `TextStyle(color: AppColors.textSecondary, fontSize: 16)` instead of `AppTypography`. Appendix C adds `onboardingTitle` and `onboardingBody` styles, but these are not referenced in the widget code.

**Recommendation:** Update the `OnboardingView` code sample to use the typography styles from Appendix C.

---

### QUESTIONS

**Q1. Should Grid/Safe Zone Settings Be Per-Project or Per-App?**

Section 4.6 states "Per-app setting (not per-project) because grid preference is a user workflow choice." This is reasonable for grid type, but safe zone presets might be per-project (e.g., a TikTok project vs. a YouTube project). Is this intentional?

**Q2. Comparison View During Playback - Paused Only?**

Section 6.7 mentions "On low-memory devices, comparison mode should be disabled during playback and only available when paused." How is "low-memory device" detected? Is this a heuristic based on `ProcessInfo`? Or should comparison always be paused-only in v1 for simplicity?

**Q3. Custom Grid: How Does the User Set Custom Row/Column Count?**

Section 4.1 mentions `custom` grid type with user-defined NxM, but the toggle UI in Section 4.5 only shows a grid type picker via `CupertinoActionSheet`. There is no UI for entering the custom row/column values. Should this be a separate settings screen, inline stepper controls, or a `CupertinoAlertDialog` with text fields?

**Q4. Gesture Hints: What Happens If User Completes the Gesture Before the Hint?**

Section 9.5 triggers hints based on first-time actions (e.g., first time opening timeline). If the user naturally performs the gesture before the hint appears, should the hint still show? Should gesture completion pre-emptively dismiss the hint?

**Q5. Is the 120-Hour Estimate Realistic Given the CompositionPlayerView Constraints?**

The comparison view and fullscreen Hero transition both require significant rework to accommodate the platform view lifecycle constraints. This adds unplanned complexity. Is the 116-hour estimate still valid, or should a buffer be added for C1 and C3?

**Q6. Fullscreen: Should Pinch-Outward Entry Be Scoped?**

Section 3.2.1 proposes pinch-outward from the preview to enter fullscreen. The preview already uses pinch gestures for zoom (via `GestureCaptureEngine`). How is the intent disambiguated? (A zoom pinch vs. a "go fullscreen" pinch.) Is there a velocity or scale threshold?

---

### Checklist Summary

| Category | Status | Notes |
|----------|--------|-------|
| All 10 features covered | PASS | Full-screen, grid, safe zones, comparison, preview quality, onboarding, gesture hints, help, workspace, orientation |
| iOS 26 Liquid Glass compliance | PASS with notes | All proposed UI uses Cupertino widgets; M5 SF Symbol names need verification |
| Technical feasibility | FAIL - 3 CRITICAL | C1 (comparison + platform view), C2 (workspace layout conflict), C3 (Hero + platform view) |
| Performance budget | PASS | Well-analyzed; I5 (preview quality for local files) needs platform-specific fix |
| Accessibility | PASS | VoiceOver, Dynamic Type, Reduce Motion, High Contrast, color-blind all addressed |
| Edge cases | PASS with notes | Screen sizes, Dynamic Island, landscape notch covered; Q6 pinch disambiguation missing |
| UX quality | PASS | Onboarding flow is solid; gesture hint timing is well-thought-out |
| Consistency with codebase | PARTIAL | C1-C3 conflict with existing platform view constraints; I6 API deprecation |

---

### Action Items for Author (Before Review 2)

1. **Resolve C1:** Design the original-frame acquisition strategy for comparison view when using `CompositionPlayerView`
2. **Resolve C2:** Specify how the workspace `Expanded` layout coexists with the `Positioned` bottom toolbar
3. **Resolve C3:** Replace Hero animation with a concrete custom animation spec that keeps the platform view mounted
4. **Address I1:** Fix safe zone inset calculations to use per-dimension percentages
5. **Address I5:** Research `AVPlayerItemVideoOutput` for local file quality scaling
6. **Address I7:** Commit to a single landscape layout or defer landscape to a future version
7. **Address I8:** Specify state management strategy for new overlay/config state

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06
**Scope:** Codebase verification, platform view constraints, integration feasibility, Liquid Glass compliance

---

### Codebase Verification Results

The following assumptions from the design document were verified against the actual source code.

#### V1. SmartEditView Layout Structure -- VERIFIED WITH ISSUES

**Source:** `lib/views/smart_edit/smart_edit_view.dart` lines 751-839

The design document's Section 2.1 layout diagram is accurate. The actual code at line 757 confirms:

```
Stack
 +-- Column
 |    +-- _buildCapCutTopToolbar()
 |    +-- SizedBox(height: 450, child: _buildCapCutVideoPreview())
 |    +-- _buildCapCutPlaybackControls()
 |    +-- _buildRulerAndTimelineWithPlayhead()
 +-- Positioned(left: 0, right: 0, bottom: 0): EditorBottomToolbar
 +-- [Various overlay Positioned widgets for tracking, reorder, etc.]
```

**Key Finding:** `_buildRulerAndTimelineWithPlayhead()` is NOT wrapped in `Expanded` -- it takes whatever space remains after the `SizedBox(height: 450)` and other fixed widgets. The `Column` does not use any `Expanded` children. The timeline simply overflows behind the `Positioned` bottom toolbar. This confirms R1's C2 finding and means the workspace resize feature (Section 11) requires more careful layout restructuring than proposed.

#### V2. CompositionPlayerView Lifecycle -- VERIFIED, CRITICAL

**Source:** `lib/widgets/composition_player_view.dart` (43 lines), `lib/views/smart_edit/smart_edit_view.dart` lines 1267-1360, `ios/Runner/CompositionPlayerService.swift` lines 24-66

Verified findings:

1. `CompositionPlayerView` is a `StatelessWidget` wrapping a `UiKitView` with `viewType: 'liquid_editor/composition_player'` and a static `ValueKey` to prevent recreation.
2. The native `CompositionPlayerViewFactory` (Swift) tracks created views by ID in `createdViews: [Int64: CompositionPlayerPlatformView]` and returns existing views when the same ID is requested. However, if the Flutter side removes and re-creates the widget, Flutter assigns a new view ID, which the factory has no mapping for -- triggering a new native view creation that conflicts with the existing `AVPlayerLayer`.
3. The `_buildVideoContainerWidgets` method uses `Offstage(offstage: !useComposition)` to hide but never remove the `CompositionPlayerView` from the widget tree. The `_hasEverUsedComposition` flag ensures the view is permanently mounted once first used.
4. **The fullscreen view (`_buildFullscreenView()` at line 2618) uses `VideoPlayer(controller)` -- the standard Flutter video player widget, NOT `CompositionPlayerView`.** This means fullscreen mode currently does NOT show the composition playback. It falls back to the single-clip `VideoPlayerController`, which may show incorrect content when in multi-clip composition mode.

**Impact:** This is more severe than R1 identified. Not only does the Hero animation approach have lifecycle issues (R1 C3), but the existing fullscreen implementation is fundamentally broken for multi-clip scenarios. The fullscreen view must be reworked to keep the `CompositionPlayerView` visible (via repositioning within the same `Stack`) rather than replacing it with a different player widget.

#### V3. CompositionPlayerService -- Single AVPlayer Architecture VERIFIED

**Source:** `ios/Runner/CompositionPlayerService.swift` lines 162-550

The native service maintains exactly one `AVPlayer`, one `AVPlayerItem`, and one `AVPlayerLayer`. There is no mechanism to create a second player or layer for comparison view purposes. Key observations:

- `setupPlayer()` (line 491) always recreates the player and layer: `player = AVPlayer(playerItem: item)`, `playerLayer = AVPlayerLayer(player: player)`.
- There is no `captureFrame` or `generateSnapshot` method on the service.
- There is no `AVPlayerItemVideoOutput` attached to the player item.
- The composition is a single `AVMutableComposition` with no concept of "original vs. processed" frames -- transforms are applied on the Flutter side via `Transform` widget, not in the `AVVideoComposition`.

**Impact for Comparison View (R1 C1):** R1's recommendation of a `getOriginalFrame(timestamp)` platform channel is the correct approach, but the implementation complexity is higher than estimated. The native side would need to:
1. Create an `AVAssetImageGenerator` from the source asset (not the composition).
2. Generate a `CGImage` at the requested timestamp.
3. Convert to `Uint8List` PNG/RGBA and send via platform channel.
4. This is an async operation (~20-50ms per frame for 1080p) and would not support real-time split-screen comparison during playback.

#### V4. Orientation Lock via SystemChrome -- VERIFIED, FEASIBLE

**Source:** `lib/main.dart` line 23

The app currently locks orientation in `main()` via:
```dart
SystemChrome.setPreferredOrientations([
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
]);
```

This is Flutter's standard API and works correctly on iOS. The design document's proposed `setPreferredOrientations` calls in `_enterFullscreen()` / `_exitFullscreen()` (Section 3.2.5) and orientation lock toggle (Section 12.4) are **technically feasible**. However:

- `SystemChrome.setPreferredOrientations` is a global setting. If the SmartEditView sets landscape-allowed and the user navigates back to ProjectLibraryView before it resets, the library view will be in landscape.
- The `dispose()` method of SmartEditView must reset orientation to portrait, and the pop navigation must also handle this.
- `DeviceOrientation.portraitDown` is currently allowed in `main.dart` but the design proposes only `portraitUp`. This is a minor inconsistency.

#### V5. Existing Design System Components -- VERIFIED, ADEQUATE

**Source:** `lib/design_system/glass_styles.dart`, `lib/design_system/liquid_glass_popup.dart`

Verified that all components listed in Section 2.2 exist:
- `AppColors`: 40+ color constants confirmed (lines 14-124 of glass_styles.dart)
- `AppTypography`: Font styles with `scaledStyle()` at line 189 -- confirmed for Dynamic Type support
- `LiquidGlassPanel`, `GlassPanel`, `GlassEffectContainer`, `LiquidGlassButton`, `CircularGlassButton`, `PlaybackButton`, `GlassToolbarButton`, `GlassActionChip`, `CompactGlassIconButton`, `GlassSlider`, `KeyframeDiamond`, `IndicatorChip`, `HapticManager`: all present in glass_styles.dart
- `LiquidGlassPopup` family: all present in liquid_glass_popup.dart

The design system is sufficient for all proposed UI additions. No new design system components are needed beyond the color and typography additions in Appendix C.

#### V6. Preview Quality Native Implementation -- VERIFIED, I5 CONFIRMED BLOCKER

**Source:** `ios/Runner/AppDelegate.swift` lines 161-200, `ios/Runner/CompositionPlayerService.swift`

Searched the entire `ios/Runner/` directory for `setPreviewQuality` and `preferredMaximumResolution` -- **zero results**. Neither method exists in the codebase. This confirms R1's I5 finding that the design's proposed implementation needs to be built from scratch.

Additionally, the `CompositionPlayerService` uses `AVMutableComposition` for local files. The `preferredMaximumResolution` property on `AVPlayerItem` indeed only affects HLS/adaptive streaming, not local file compositions. For local files, quality scaling would require either:
1. Changing the `AVMutableVideoComposition.renderSize` to a smaller value (e.g., half resolution), which requires rebuilding the composition.
2. Adding an `AVPlayerItemVideoOutput` and extracting frames at reduced resolution.
3. Simply scaling the `AVPlayerLayer.frame` smaller and relying on GPU downscaling (visually similar but does not save decode memory).

Option 3 is the simplest and achieves the scrubbing performance goal without composition rebuilds. The design should specify this.

#### V7. Semantics / VoiceOver Coverage -- VERIFIED, MINIMAL

Searched the entire `lib/` directory for `Semantics`, `semanticLabel`, and `SemanticsService` -- found only **7 occurrences across 3 files** (`speed_control_sheet.dart`, `timeline_widget.dart`, `volume_control_sheet.dart`). The main `smart_edit_view.dart` and `editor_bottom_toolbar.dart` have **zero** `Semantics` wrappers.

This confirms that the accessibility work in Section 13 is substantial and the 3-4 day estimate for Phase 6 may be optimistic given the breadth of unlabeled interactive elements.

#### V8. EditorBottomToolbar Structure -- VERIFIED

**Source:** `lib/views/smart_edit/editor_bottom_toolbar.dart` lines 1-100

The toolbar uses `BackdropFilter` with blur, a `SingleChildScrollView` horizontal tool row, and `CNTabBar` for tab switching. It receives callbacks via constructor params. Adding a comparison toggle to the FX tab (Section 6.8) is straightforward -- add an `onCompare` callback and a new `_ToolButton` in the FX tools list. Adding long-press help (Section 10.3) requires wrapping each `_ToolButton` in a `GestureDetector` with `onLongPress`, which is feasible but touches every tool button widget.

---

### Integration Risk Assessment

| Feature | Risk Level | Primary Risk | Mitigation |
|---------|-----------|-------------|------------|
| Full-Screen Preview | **HIGH** | Existing fullscreen uses `VideoPlayer`, not `CompositionPlayerView`. Rework needed to keep platform view mounted. | Implement fullscreen as overlay within same `Stack`, not as separate build path. |
| Grid Overlay | **LOW** | `CustomPainter` on top of `ClipRRect` video area. No platform view interaction. | Straightforward implementation. |
| Safe Zone Overlay | **LOW** | Same as grid. No platform view interaction. | Straightforward implementation. |
| Comparison View | **CRITICAL** | Single `AVPlayer` architecture prevents dual-view rendering. No native snapshot API exists. | Implement `AVAssetImageGenerator`-based snapshot on native side. Split-screen only feasible when paused. |
| Preview Quality | **MEDIUM** | `preferredMaximumResolution` does not work for local files. Native implementation missing entirely. | Use `AVPlayerLayer` frame scaling (Option 3) for v1. |
| Onboarding | **LOW** | Independent feature. No integration with platform views. | Standard Flutter PageView implementation. |
| Gesture Hints | **LOW** | Overlay system. No platform view interaction. | Standard overlay implementation. |
| Context Help | **LOW** | Long-press on existing buttons. | Simple `GestureDetector` wrapping. |
| Workspace Resize | **MEDIUM** | Current layout uses fixed `SizedBox(height: 450)` in a `Column` with overlapping `Positioned` toolbar. Switching to `Expanded` requires accounting for toolbar overlap. | Add `SizedBox(height: bottomToolbarHeight)` spacer at bottom of Column. |
| Orientation Lock | **MEDIUM** | `SystemChrome` orientation is global. Navigation stack must coordinate reset. | Add orientation reset in `dispose()` and `WillPopScope`. |
| Accessibility | **MEDIUM** | Near-zero existing Semantics coverage. Large surface area to cover. | Audit all interactive elements. Budget 4-5 days, not 3-4. |
| Dark/Light Mode | **LOW** | Additive feature. `CupertinoColors` adaptive colors already available. | Low priority, defer to post-v1. |

---

### Critical Findings

**CF1. Fullscreen Mode Is Broken for Multi-Clip Composition Playback (NEW -- More Severe Than R1 C3)**

R1 identified that the Hero animation approach would conflict with platform view lifecycle. Upon code verification, the problem is deeper: the existing `_buildFullscreenView()` at line 2618 renders `VideoPlayer(controller)` -- the standard Flutter video player -- while in multi-clip mode, the actual video is rendered via `CompositionPlayerView` (native `AVPlayerLayer`). These are two completely different playback paths.

When the user enters fullscreen in multi-clip composition mode:
1. `_viewModel.isFullscreen` is set to `true`
2. `_buildMainContent()` returns `_buildFullscreenView()` instead of the normal layout
3. The normal layout (including the permanently-mounted `CompositionPlayerView`) is removed from the widget tree
4. The `VideoPlayer(controller)` in fullscreen shows the single-clip fallback player, which may show incorrect content or no content at all

**Resolution Required:** The fullscreen view must be implemented as a layer within the existing `Stack`, not as a replacement for `_buildMainContent()`. The approach:
1. Keep the normal `Column` layout always in the tree (with the `CompositionPlayerView` permanently mounted)
2. Overlay a fullscreen `Positioned.fill` container on top that repositions/scales the video area
3. Use `Offstage` or opacity to hide non-fullscreen elements (toolbar, timeline, controls)
4. Animate the video container from its normal bounds (32px horizontal padding, 450px height) to full-screen bounds

This is a prerequisite for all fullscreen-related features (Section 3).

**CF2. Comparison View Split-Screen Is Not Feasible During Playback (CONFIRMS and EXTENDS R1 C1)**

Verified that `CompositionPlayerService` has a single `AVPlayer` and `AVPlayerLayer`. The design proposes rendering two `VideoPlayer` widgets from the same controller for split-screen (Section 6.4). Verification reveals:

1. In single-clip mode: Two `VideoPlayer` widgets CAN share the same `VideoPlayerController` in Flutter's `video_player` package (the package creates a texture per controller, and multiple `VideoPlayer` widgets reference the same texture). So split-screen with `VideoPlayer` is technically possible for single-clip mode.
2. In composition mode: The `CompositionPlayerView` is a native platform view (`UiKitView`) backed by a single `AVPlayerLayer`. Only ONE `AVPlayerLayer` can display a given `AVPlayer`'s output at a time. You cannot create two `CompositionPlayerView` instances showing different content.

For the "original" frame, since transforms are applied on the Flutter side (via `Transform` widget wrapping the video player), the "original" is simply the video without the `Transform` matrix. This means:
- **Toggle mode works:** Show the same video with/without the `Transform` widget. One player, two presentation modes.
- **Split-screen works for single-clip mode:** Two `VideoPlayer` widgets from the same controller -- one with `Transform`, one without.
- **Split-screen does NOT work for composition mode:** Cannot duplicate the native platform view. The only option is snapshot-based comparison (paused only) via `AVAssetImageGenerator`.

**Recommendation:** Scope comparison view to:
1. Toggle mode: Always available (zero additional rendering cost).
2. Split-screen: Available only in single-clip mode OR when paused in composition mode (using a captured snapshot for the original half).

**CF3. `_buildRulerAndTimelineWithPlayhead()` Has No Height Constraint (EXTENDS R1 C2)**

The timeline widget at line 772 is placed in the `Column` after the fixed-height elements but has no `Expanded` wrapper and no fixed height. In the current code, it relies on the `Column` giving it remaining space, but the `Column` is inside a `Stack` where the `Positioned(bottom: 0)` toolbar overlaps. The timeline content extends behind the toolbar, and the toolbar's `BackdropFilter` blur makes the overlap visually acceptable.

When implementing workspace resize (Section 11), if we switch to `Expanded` for both preview and timeline:
1. The `Column` must have a bounded height. Inside a `Stack`, the `Column` takes the full `Stack` height.
2. The `Expanded` children will divide ALL available vertical space, including the space occupied by the overlapping toolbar.
3. The timeline's scrollable content will have its bottom ~120px hidden behind the toolbar.

**Resolution:** The workspace resize implementation must add a `SizedBox(height: bottomToolbarHeight + bottomSafeArea)` at the end of the `Column` children to reserve space for the overlapping toolbar. Alternatively, restructure to use a non-overlapping layout (toolbar inside the Column), but this would change the current visual design where the toolbar's backdrop blur extends over the timeline.

---

### Important Findings

**IF1. Fullscreen Transition Must Not Use `setState(() => isFullscreen = true)` Alone**

Currently, `_viewModel.isFullscreen = true` triggers a full widget rebuild via `notifyListeners()`. The `_buildMainContent()` method then returns a completely different widget tree (fullscreen vs. normal). This causes the entire normal layout to be unmounted and the fullscreen layout to be mounted from scratch.

For a smooth transition, the implementation needs:
1. Both normal and fullscreen layouts in the tree simultaneously during the transition
2. An `AnimationController` driving position/scale interpolation
3. After animation completes, the normal layout can be hidden (but NOT removed due to `CompositionPlayerView`)

This means `isFullscreen` should not be a simple boolean that swaps widget trees, but rather a state that drives an animation with both trees present.

**IF2. Grid/Safe Zone Overlay Positioning Within `_buildCapCutVideoPreview` -- VERIFIED FEASIBLE**

The `_buildCapCutVideoPreview()` method at line 1212 returns a `GestureDetector > Padding(horizontal: 32) > ClipRRect > Stack`. The overlays would be added as `Positioned.fill` children of this `Stack`, above the video container widgets but below the chevron. This is correct and feasible.

However, the `Stack` children list is constructed via `..._buildVideoContainerWidgets(...)` (spread operator). The overlay widgets should be added after this spread, inside the same `Stack.children` list. The design's Section 4.4 shows this correctly.

**One concern:** The `ClipRRect(borderRadius: BorderRadius.circular(8))` at line 1231 will clip the overlay to the rounded rectangle. This is correct behavior (overlays should match the video preview shape), but means the grid lines will have rounded corners at the edges. This is actually a nice visual touch and consistent with the design language.

**IF3. `CompactGlassIconButton` 32px Size Violates 44pt Minimum Tap Target**

The design's Section 13.5 correctly identifies that `CompactGlassIconButton` has a 32px default size, below the Apple HIG 44pt minimum. The recommended wrapper with `SizedBox(width: 44, height: 44)` is the correct fix. However, this button is used in multiple places in the codebase (fullscreen exit button at line 2657 uses `CircularGlassButton(size: 44)` which is fine, but other uses may be undersized).

An audit of all `CompactGlassIconButton` usages should be part of the Phase 6 accessibility work.

**IF4. `GestureHintManager` Singleton Race Condition -- Concrete Scenario**

R1 identified the async init issue (I3). The concrete scenario:
1. App launches and calls `GestureHintManager.shared` (constructor runs synchronously, `_showCounts` is empty)
2. SmartEditView's `initState` calls `GestureHintManager.shared.shouldShow('pinch_timeline')`
3. `_showCounts['pinch_timeline']` is null, so `shouldShow` returns true
4. Meanwhile, `_loadCounts()` has not been called at all because the design shows no call site for it

The design's `GestureHintManager` constructor does not call `_loadCounts()`. There is no initialization path shown. This will cause ALL hints to show every time until `_loadCounts()` is explicitly called and awaited.

**Resolution:** Call `await GestureHintManager.shared.init()` in `main()` before `runApp()`, where `init()` calls `_loadCounts()`. Or use `SharedPreferences.getInstance()` synchronously in `main()` (it caches the instance after first async load) and pass it to the manager.

**IF5. Landscape Layout Impact on `CompositionPlayerView` Bounds**

When the device rotates to landscape, the Flutter framework changes `MediaQuery.of(context).size` and triggers a rebuild. The `CompositionPlayerView` (native `UiKitView`) will receive a new frame from Flutter's layout system. The native `PlayerContainerView.layoutSubviews()` (CompositionPlayerService.swift line 74) correctly updates `playerLayer.frame = bounds` on layout change.

This means landscape support for the platform view itself is technically sound. However, the aspect ratio calculation in `_buildVideoContainerWidgets` (line 1290: `final aspectRatio = controller?.value.aspectRatio ?? 9 / 16`) will produce a very wide, short preview in landscape for 9:16 content, or fill most of the width for 16:9 content. The landscape layout must account for the video content aspect ratio when allocating space.

**IF6. `withOpacity()` vs `withValues(alpha:)` -- Scope of Change**

R1 flagged this as I6. Searching the design document, `.withOpacity()` appears in:
- Section 4.3: `config.lineColor.withOpacity(config.opacity)`, `Colors.black.withOpacity(config.opacity * 0.5)`
- Section 5.4: `CupertinoColors.systemYellow.withOpacity(0.6)` and 6 more
- Section 6.4: `CupertinoColors.black.withOpacity(0.3)` and 1 more
- Section 8.3: `AppColors.glassWhite` (no opacity call)
- Section 9.3: `CupertinoColors.black.withOpacity(0.3)`, `AppColors.glassBorder`

Total: ~15 instances that need updating to `.withValues(alpha: ...)` before implementation. This is a minor but pervasive change.

---

### Liquid Glass Compliance Verification

| Section | Component Used | Compliant | Notes |
|---------|---------------|-----------|-------|
| 3 (Fullscreen) | `CircularGlassButton`, `PlaybackButton`, `AppTypography.timecode` | YES | Exit button uses `Icons.fullscreen_exit_rounded` (Material icon) -- should use `CupertinoIcons` |
| 4 (Grid) | `CupertinoActionSheet`, `LiquidGlassPopupItem`, `LiquidGlassPopupToggle` | YES | Fully Cupertino-native |
| 5 (Safe Zones) | `CupertinoActionSheet`, `CupertinoColors` | YES | Multi-select UX is non-standard for action sheets (R1 M4), but technically correct |
| 6 (Comparison) | `IndicatorChip`, `CupertinoColors` | YES | Divider handle uses raw `Container` -- acceptable for custom UI elements |
| 7 (Quality) | `CupertinoActionSheet`, `GestureDetector` + `Container` badge | PARTIAL | Quality badge uses inline styling instead of a design system component |
| 8 (Onboarding) | `CupertinoPageScaffold`, `CupertinoButton.filled`, `AppColors`, `AppTypography` | YES | Uses `LinearGradient` background which is custom but appropriate |
| 9 (Hints) | `BackdropFilter`, `CupertinoButton`, `AppColors`, `AppTypography` | YES | Fully compliant |
| 10 (Help) | `CupertinoAlertDialog`, `CupertinoDialogAction` | YES | Proper native dialog usage |
| 11 (Workspace) | `CupertinoSlider` (collapsed), `CupertinoColors`, `AppColors` | YES | Drag handle is custom but minimal |
| 12 (Orientation) | `CompactGlassIconButton`, `CupertinoIcons` | YES | Uses existing design system component |
| 13 (Accessibility) | `Semantics`, `CupertinoColors`, `MediaQuery` | YES | Standard Flutter accessibility |
| 14 (Dark/Light) | `CupertinoThemeData`, `CupertinoColors` | YES | Uses system adaptive colors |

**One Compliance Issue:** The existing fullscreen view (line 2662) uses `Icons.fullscreen_exit_rounded` -- a Material icon. This violates the Liquid Glass requirement. It should use `CupertinoIcons.arrow_down_right_arrow_up_left` or similar SF Symbol equivalent. The design document Section 3.2.3 layout diagram does not specify which icon to use for the exit button; Appendix A lists `arrow.down.right.and.arrow.up.left` as the SF Symbol, which should be referenced via `CupertinoIcons` or `CNSymbol`.

---

### Action Items for Review 3

1. **Resolve CF1 (PREREQUISITE for all fullscreen work):** Redesign `_buildFullscreenView()` as an overlay within the existing `Stack` that keeps `CompositionPlayerView` mounted. Provide concrete widget tree showing both normal and fullscreen states coexisting. Specify the `AnimationController` animation for transitioning between states.

2. **Resolve CF2 (Scope comparison view):** Update Section 6 to:
   - Toggle mode: available in all playback modes (single-clip and composition)
   - Split-screen: available in single-clip mode during playback; available in composition mode only when paused (using `AVAssetImageGenerator` snapshot for original frame)
   - Side-by-side: same constraints as split-screen
   - Add native `captureFrame(timestampMs)` platform channel spec to Section 6.6

3. **Resolve CF3 (Workspace layout):** Provide the exact `Column` children list including the bottom spacer `SizedBox` that reserves toolbar space. Show how `_buildRulerAndTimelineWithPlayhead()` gets its height constraint.

4. **Address IF1:** Redesign the fullscreen state transition to use an `AnimationController` with both layouts in the tree simultaneously. Define the animation parameters (duration, curve, what properties are animated).

5. **Address IF4:** Add concrete initialization path for `GestureHintManager` showing where `_loadCounts()` is called and awaited.

6. **Verify SF Symbol Names:** As R1 M5 noted, validate `lock.rotation`, `lock.rotation.open`, and all other SF Symbol names against the SF Symbols 5/6 catalog before implementation.

7. **Fix Material Icon Usage:** Replace `Icons.fullscreen_exit_rounded` in existing fullscreen view with `CupertinoIcons` equivalent.

8. **Address Preview Quality Implementation (V6):** Replace the `preferredMaximumResolution` approach with a concrete alternative for local files. Recommend specifying Option 3 (AVPlayerLayer frame scaling) for v1 with a note that Option 2 (AVPlayerItemVideoOutput) could be added later for actual decode-level savings.

9. **Revise Time Estimates:** Given CF1 (fullscreen rework), CF2 (comparison scope reduction and native snapshot API), and IF1 (transition animation complexity), add 8-12 hours buffer to the total estimate. Phase 2 (Fullscreen) should be 4-5 days, not 2-3. Phase 3 (Comparison) should include native Swift work for the snapshot API.

10. **Accessibility Estimate Revision:** With only 7 `Semantics` occurrences across 3 files in the entire codebase, the VoiceOver audit alone requires touching every interactive widget in `smart_edit_view.dart` (~2800 lines), `editor_bottom_toolbar.dart`, `project_library_view.dart`, and all overlay/sheet widgets. Budget 5-6 days for Phase 6, not 3-4.

---

### Summary

The design document is well-architected and most features are straightforward to implement. The three critical findings (CF1-CF3) all stem from the same root cause: the `CompositionPlayerView` native platform view has strict lifecycle constraints that the design does not fully account for. Specifically:

- **Fullscreen is broken today** for multi-clip composition mode (CF1) and must be rearchitected before any fullscreen enhancements can be built.
- **Comparison split-screen** requires a native snapshot API and must be scoped to paused-only for composition mode (CF2).
- **Workspace resize** needs explicit space reservation for the overlapping toolbar (CF3).

The low-risk features (grid overlay, safe zone overlay, onboarding, gesture hints, context help) can proceed immediately with high confidence. The medium-risk features (preview quality, orientation lock) need minor design adjustments. The high-risk features (fullscreen, comparison, workspace) need the design revisions itemized above before implementation begins.

Recommended implementation order adjustment:
1. **Phase 1: Grid + Safe Zone overlays** (LOW risk, proceed as-is)
2. **Phase 1.5: Fullscreen rearchitecture** (NEW -- fix CF1 before enhancing fullscreen)
3. **Phase 2: Fullscreen enhancements** (after CF1 is resolved)
4. **Phase 3: Comparison toggle mode + preview quality** (defer split-screen to later)
5. **Phase 4: Onboarding + hints + help** (LOW risk, proceed as-is)
6. **Phase 5: Workspace + orientation** (after CF3 layout fix)
7. **Phase 6: Accessibility** (budget 5-6 days)

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06

---

### Critical Issues Status

All six critical issues from R1 (C1-C3) and R2 (CF1-CF3) have been evaluated for resolution viability. Below is the disposition of each.

| ID | Issue | Status | Resolution Path | Residual Risk |
|----|-------|--------|----------------|---------------|
| C1 / CF2 | Comparison View: CompositionPlayerView duplication will crash | **RESOLVABLE** | Toggle mode uses single player with/without `Transform` (zero cost). Split-screen uses `AVAssetImageGenerator` snapshot for original half when paused in composition mode. Existing `AVAssetImageGenerator` usage in `VideoProcessingService.swift` and `NativeDecoderPool.swift` confirms the native pattern is already established in the codebase. | Medium -- snapshot latency (~20-50ms) may cause a visible delay when entering split-screen comparison in composition mode. Acceptable for paused-only usage. |
| C2 / CF3 | Workspace resize: `Expanded` layout conflicts with `Positioned` bottom toolbar | **RESOLVABLE** | Add `SizedBox(height: bottomToolbarHeight + bottomSafeArea)` as the last child of the `Column` to reserve space. The overlapping toolbar continues to visually float over this spacer, preserving the current backdrop blur aesthetic. When workspace ratio is adjusted, the spacer remains constant and the `Expanded` flex values redistribute between preview and timeline only. | Low -- straightforward layout arithmetic. |
| C3 / CF1 | Hero animation / Fullscreen: CompositionPlayerView removed from widget tree | **RESOLVABLE** | Abandon Hero entirely. Implement fullscreen as a `Positioned.fill` overlay within the existing `Stack` in `_buildMainContent()`. The normal `Column` (including the permanently-mounted `CompositionPlayerView`) stays in the widget tree at all times. An `AnimationController` (300ms, `Curves.easeOutCubic`) animates: (a) the video container from its normal bounds `Rect(32, topOffset, screenWidth-64, 450)` to full-screen `Rect(0, 0, screenWidth, screenHeight)`, (b) the background opacity from 0 to 1 (black), (c) non-video elements to opacity 0. The `isFullscreen` boolean becomes a tristate: `normal`, `animatingToFullscreen`, `fullscreen`, `animatingToNormal`. Both `_buildFullscreenView()` and the normal layout coexist in the widget tree; visibility is controlled by opacity and `IgnorePointer`, not by conditional widget swapping. | Medium -- requires careful gesture handling during animation transition. The `CompositionPlayerView` must be reparented from the `ClipRRect > Stack` to a higher-level `Stack` child to allow it to escape its 450px container during animation. This reparenting must use `GlobalKey` to preserve widget identity, or the composition player must always live at the top `Stack` level with a `Positioned` that animates from preview bounds to screen bounds. |

**Assessment:** All critical issues have viable resolution paths. No issue is a fundamental architectural blocker. The highest residual risk is C3/CF1 because the `CompositionPlayerView` reparenting requires either (a) always mounting the platform view at the top-level `Stack` and using animated `Positioned` to move it between preview bounds and fullscreen bounds, or (b) accepting a visual discontinuity during transition where the platform view stays in its original position while a screenshot placeholder animates. Option (a) is recommended.

---

### Platform View Lifecycle: Viable Fullscreen Architecture

After examining `_buildVideoContainerWidgets()` (lines 1275-1359) and `_buildFullscreenView()` (lines 2618-2706), the following architecture is the recommended resolution for CF1/C3:

**Current problem:** `_buildMainContent()` at line 751 returns either `_buildFullscreenView()` OR the normal `Stack` layout, never both. This removes the `CompositionPlayerView` from the tree when entering fullscreen.

**Recommended architecture:**

```
_buildMainContent() always returns:
Stack
 +-- Column (normal layout, always in tree)
 |    +-- _buildCapCutTopToolbar()           // animated to opacity 0 in fullscreen
 |    +-- SizedBox(height: 450)              // video preview PLACEHOLDER (empty)
 |    +-- _buildCapCutPlaybackControls()     // animated to opacity 0
 |    +-- _buildRulerAndTimelineWithPlayhead()
 |    +-- SizedBox(height: toolbarHeight)    // spacer for workspace resize
 +-- AnimatedPositioned (the actual video container with CompositionPlayerView)
 |    // Normal state: matches preview bounds (left:32, top:~103, w:screenW-64, h:450)
 |    // Fullscreen state: fills screen (left:0, top:0, w:screenW, h:screenH)
 +-- Positioned(bottom: 0): EditorBottomToolbar // animated to opacity 0
 +-- [overlay widgets]
 +-- if (isFullscreen) Positioned.fill: fullscreen controls overlay
```

The key insight is that the `CompositionPlayerView` must live in an `AnimatedPositioned` at the `Stack` level -- not nested inside the `Column` -- so it can animate between preview size and fullscreen size without being removed from the tree. The `SizedBox(height: 450)` in the `Column` acts as a placeholder that reserves the correct vertical space.

This approach resolves CF1 completely and makes the fullscreen transition smooth without any platform view lifecycle violations.

---

### Scoping Decisions

**Comparison View scoped to paused-only for split-screen in composition mode: ACCEPTABLE.**

R2's recommendation to limit split-screen comparison to paused-only when in composition mode is the correct engineering decision. Rationale:

1. Real-time split-screen requires two simultaneous video renders. The single-AVPlayer architecture makes this impossible for composition mode without a second player (which would double memory and decode cost).
2. The primary use case for comparison is reviewing color grading, crop, or transform changes -- which is naturally a paused activity (scrub to a representative frame, toggle comparison).
3. Toggle mode (hold to see original) is available during playback at zero cost since it only changes the `Transform` widget wrapping, not the video source.
4. Professional video editors (DaVinci Resolve, Final Cut Pro) also restrict A/B comparison to paused or single-frame mode in their preview viewers.

**One addition:** The comparison toggle button should display a tooltip or mode indicator when the user attempts split-screen during composition playback, explaining that split-screen is available when paused. Use a brief `CupertinoAlertDialog` or an `IndicatorChip` that auto-dismisses after 2 seconds.

**Landscape support deferred: RECOMMENDED.**

R1 I7 flagged the underspecified landscape layout. R2 did not resolve this. Given that:
- The `CompositionPlayerView` bounds update correctly on rotation (IF5 confirmed)
- But the timeline, toolbar, and overlay positioning all require landscape-specific layout code
- The editor already has ~2800 lines and significant complexity

Landscape support for the normal editor mode should be deferred to post-v1. Fullscreen landscape (Section 3.2.5) is acceptable because the fullscreen overlay is a simple `Stack` with `SafeArea`-aware controls that adapt naturally to orientation changes.

---

### Risk Register

| Risk ID | Feature | Severity | Probability | Impact | Mitigation | Owner |
|---------|---------|----------|------------|--------|------------|-------|
| R1 | CompositionPlayerView reparented to Stack-level AnimatedPositioned breaks existing gesture handling | HIGH | Medium | Preview tap, pinch, pan gestures must move from `_buildCapCutVideoPreview` to the new AnimatedPositioned container. Gesture targets change coordinate space. | Test all gestures (tap to deselect, pinch to zoom, double-tap fullscreen, chevron tap) after reparenting. Use `GlobalKey` on gesture detector to maintain state. | Phase 1.5 |
| R2 | `AVAssetImageGenerator` snapshot latency causes comparison view to feel sluggish | MEDIUM | Medium | 20-50ms per frame capture is noticeable if user scrubs while in split-screen mode. | Cache the last-captured original frame. Only regenerate when playhead moves more than 100ms. Pre-fetch snapshots during scrub anticipation. | Phase 3 |
| R3 | `SystemChrome.setPreferredOrientations` not reset on unexpected navigation (e.g., system interruption, phone call) | MEDIUM | Low | App could get stuck in landscape if SmartEditView is killed without calling `dispose()`. | Add orientation reset in `WidgetsBindingObserver.didChangeAppLifecycleState()` for `paused` and `detached` states. Also reset in `ProjectLibraryView.initState()` as a safety net. | Phase 2/5 |
| R4 | Workspace resize drag conflicts with timeline scroll gesture | MEDIUM | Medium | The drag handle (20px tall) sits between the playback controls and the timeline. A vertical drag on the handle could be misinterpreted as a timeline scroll attempt. | Use `HitTestBehavior.opaque` on the drag handle. Add visual affordance (highlight on touch) to make the handle discoverable. Require a 10px minimum vertical delta before starting resize to filter accidental touches. | Phase 5 |
| R5 | Onboarding references unimplemented features (Effects, Filters) | LOW | High | Step 6 of onboarding shows Effects/Filters which are TODO stubs. Screenshots will show empty or placeholder UI. | Gate onboarding pages to only show implemented features. Use a `List<OnboardingStep>` built from feature flags rather than a fixed 7-page sequence. | Phase 4 |
| R6 | GestureHintManager singleton race condition causes all hints to show on every launch | MEDIUM | High | Without explicit initialization path, `_showCounts` is empty at first access. Every hint passes `shouldShow()`. | Call `await GestureHintManager.shared.init()` in `main()` before `runApp()`. Add assertion in `shouldShow()` that throws if `_initialized` flag is false. | Phase 4 |
| R7 | Accessibility audit (7 existing `Semantics` wrappers) underscoped at 3-4 days | LOW | High | Phase 6 estimate of 3-4 days is insufficient for ~0 VoiceOver coverage. Interactive widgets across 8+ files need labeling. | Budget 5-6 days as R2 recommended. Prioritize: (1) editor toolbar buttons, (2) timeline clips, (3) playback controls, (4) overlay controls, (5) onboarding, (6) project library. | Phase 6 |
| R8 | Preview quality `preferredMaximumResolution` does not work for local files | MEDIUM | Certain | Confirmed: this API is HLS-only. Design must use an alternative. | Use `AVPlayerLayer` frame scaling (Option 3 from R2 V6) for v1. This achieves visual quality reduction and faster rendering without decode-level savings. Adequate for performance perception. | Phase 3 |

---

### Implementation Checklist

Ordered by dependency and priority. Each item lists the file(s) to create or modify.

#### Phase 1: Visual Overlays (3-4 days, LOW risk)
No dependencies. Can proceed immediately.

| # | Task | File(s) | Depends On | Est. Hours |
|---|------|---------|-----------|-----------|
| 1 | Create `GridOverlayConfig` model with `copyWith`, `GridType` enum, validation (`clamp(2,20)` for custom) | `lib/overlays/grid_overlay.dart` | -- | 1 |
| 2 | Implement `GridOverlayPainter` (all 6 grid types, shadow paint for contrast) | `lib/overlays/grid_overlay.dart` | #1 | 2 |
| 3 | Create `SafeZoneConfig` model with `copyWith`, `SafeZonePreset` enum | `lib/overlays/safe_zone_overlay.dart` | -- | 1 |
| 4 | Implement `SafeZonePainter` (all 7 presets, dashed rect utility, label rendering). Fix I1: use `size.height` for vertical insets. | `lib/overlays/safe_zone_overlay.dart` | #3 | 3 |
| 5 | Create `UserPreferencesService` (centralized SharedPreferences wrapper for all new keys from Appendix B) | `lib/core/user_preferences.dart` | -- | 2 |
| 6 | Integrate grid overlay into `_buildCapCutVideoPreview()` Stack, after `_buildVideoContainerWidgets` spread | `lib/views/smart_edit/smart_edit_view.dart` | #2, #5 | 1 |
| 7 | Integrate safe zone overlay into same Stack | `lib/views/smart_edit/smart_edit_view.dart` | #4, #5 | 1 |
| 8 | Add grid type picker (`CupertinoActionSheet`) and toggle to project settings dropdown | `lib/views/smart_edit/smart_edit_view.dart` | #6 | 2 |
| 9 | Add safe zone picker (custom `StatefulWidget` in modal popup, not action sheet -- per R1 M4) | `lib/views/smart_edit/smart_edit_view.dart` | #7 | 2 |
| 10 | Unit + widget tests for grid and safe zone painters | `test/grid_overlay_test.dart`, `test/safe_zone_overlay_test.dart` | #2, #4 | 3 |

#### Phase 1.5: Fullscreen Rearchitecture (3-4 days, HIGH risk -- PREREQUISITE)
Must complete before Phase 2. Resolves CF1/C3.

| # | Task | File(s) | Depends On | Est. Hours |
|---|------|---------|-----------|-----------|
| 11 | Reparent `CompositionPlayerView` to top-level `Stack` with `AnimatedPositioned`. Replace `SizedBox(height:450)` video area with empty placeholder. | `lib/views/smart_edit/smart_edit_view.dart` | -- | 4 |
| 12 | Re-route all preview gestures (tap, pinch, double-tap, chevron) to the `AnimatedPositioned` container. Verify gesture coordinate spaces. | `lib/views/smart_edit/smart_edit_view.dart` | #11 | 3 |
| 13 | Implement fullscreen as overlay: `AnimationController` (300ms, `easeOutCubic`), animate `Positioned` bounds from preview rect to screen rect. Hide non-video elements with `AnimatedOpacity`. | `lib/views/smart_edit/smart_edit_view.dart` | #11 | 4 |
| 14 | Add `SystemChrome.setEnabledSystemUIMode(immersiveSticky)` for fullscreen, reset on exit. Add orientation unlock for fullscreen landscape. | `lib/views/smart_edit/smart_edit_view.dart` | #13 | 1 |
| 15 | Replace `Icons.fullscreen_exit_rounded` (Material) with `CupertinoIcons.arrow_down_right_arrow_up_left` | `lib/views/smart_edit/smart_edit_view.dart` | #13 | 0.5 |
| 16 | Replace `Icons.play_arrow_rounded` (Material) in fullscreen with `CupertinoIcons.play_fill` | `lib/views/smart_edit/smart_edit_view.dart` | #13 | 0.5 |
| 17 | Test: fullscreen entry/exit in single-clip mode, composition mode, during playback, while paused | `test/fullscreen_preview_test.dart` | #13 | 3 |

#### Phase 2: Fullscreen Enhancements (3-4 days, MEDIUM risk)
Depends on Phase 1.5 completion.

| # | Task | File(s) | Depends On | Est. Hours |
|---|------|---------|-----------|-----------|
| 18 | Auto-hide controls with `Timer` (3s timeout, `AnimatedOpacity` 300ms). Cancel timer in `dispose()`. | `lib/views/smart_edit/smart_edit_view.dart` | #13 | 2 |
| 19 | Swipe-down exit gesture (velocity > 500px/s threshold) | `lib/views/smart_edit/smart_edit_view.dart` | #13 | 2 |
| 20 | Double-tap preview to enter fullscreen | `lib/views/smart_edit/smart_edit_view.dart` | #12 | 1 |
| 21 | Fullscreen top bar: grid toggle, safe zone toggle, quality badge (shared state with normal editor) | `lib/views/smart_edit/smart_edit_view.dart` | #6, #7, #13 | 2 |
| 22 | Fullscreen bottom bar: scrub slider (`CupertinoSlider`), play/pause, loop toggle | `lib/views/smart_edit/smart_edit_view.dart` | #13 | 2 |
| 23 | Orientation safety: reset in `dispose()`, `WidgetsBindingObserver.didChangeAppLifecycleState`, and `ProjectLibraryView.initState` | `lib/views/smart_edit/smart_edit_view.dart`, `lib/views/project_library/project_library_view.dart` | #14 | 1 |
| 24 | Tests | `test/fullscreen_preview_test.dart` | #18-#22 | 2 |

#### Phase 3: Comparison View + Preview Quality (4-5 days, MEDIUM risk)
Comparison toggle mode has no dependencies. Split-screen requires Phase 1.5 for correct video container access.

| # | Task | File(s) | Depends On | Est. Hours |
|---|------|---------|-----------|-----------|
| 25 | Create `ComparisonConfig` model with `copyWith` and `ComparisonMode` enum | `lib/overlays/comparison_overlay.dart` | -- | 1 |
| 26 | Implement toggle mode: long-press shows original (same player, no `Transform`), release restores processed | `lib/overlays/comparison_overlay.dart`, `smart_edit_view.dart` | #25 | 2 |
| 27 | Implement split-screen for single-clip mode: two `VideoPlayer` widgets from same controller, `_SplitClipper`, draggable divider | `lib/overlays/comparison_overlay.dart` | #25 | 3 |
| 28 | Add native `captureOriginalFrame(timestampMs)` platform channel using existing `AVAssetImageGenerator` pattern from `VideoProcessingService.swift` | `ios/Runner/CompositionPlayerService.swift`, `lib/views/smart_edit/smart_edit_view.dart` | -- | 3 |
| 29 | Implement split-screen for composition mode (paused only): display captured snapshot via `Image.memory` for original half | `lib/overlays/comparison_overlay.dart` | #27, #28 | 2 |
| 30 | Add Compare button to FX tab of `EditorBottomToolbar`. Disable when no modifications. Show mode indicator if split-screen attempted during composition playback. | `lib/views/smart_edit/editor_bottom_toolbar.dart` | #25 | 1 |
| 31 | Preview quality: implement `AVPlayerLayer` frame scaling on native side (Option 3) | `ios/Runner/CompositionPlayerService.swift` | -- | 2 |
| 32 | Preview quality: Flutter platform channel + `PreviewQuality` enum + auto mode (half during scrub, full when paused) | `lib/core/preview_quality_service.dart`, `smart_edit_view.dart` | #31 | 2 |
| 33 | Replace "2K" badge with interactive quality picker (`CupertinoActionSheet`) | `lib/views/smart_edit/smart_edit_view.dart` | #32 | 1 |
| 34 | Tests | `test/comparison_view_test.dart`, `test/preview_quality_test.dart` | #26-#33 | 3 |

#### Phase 4: Onboarding + Gesture Hints + Help (4-5 days, LOW risk)
No hard dependencies on other phases.

| # | Task | File(s) | Depends On | Est. Hours |
|---|------|---------|-----------|-----------|
| 35 | `GestureHintManager` with proper `init()` method called in `main()` before `runApp()` | `lib/core/gesture_hint_manager.dart`, `lib/main.dart` | -- | 2 |
| 36 | `GestureHintOverlay` widget with auto-dismiss timer, animation, "Got it" button | `lib/overlays/gesture_hint_overlay.dart` | #35 | 3 |
| 37 | Integrate hint triggers at documented trigger points in `smart_edit_view.dart` | `lib/views/smart_edit/smart_edit_view.dart` | #36 | 2 |
| 38 | `OnboardingView` with `PageView`, feature-gated pages (only show pages for implemented features), progress dots, skip button | `lib/views/onboarding/onboarding_view.dart` | -- | 4 |
| 39 | Gesture animation painters (pinch, swipe, long-press, double-tap, drag) using `CustomPainter` | `lib/views/onboarding/gesture_animations.dart` | -- | 3 |
| 40 | First-launch detection in `ProjectLibraryView.initState` | `lib/views/project_library/project_library_view.dart` | #38 | 1 |
| 41 | Help content registry (`Map<String, HelpContent>`) | `lib/core/help_content.dart` | -- | 1 |
| 42 | Long-press help on `_ToolButton` in `EditorBottomToolbar` using `CupertinoAlertDialog` | `lib/views/smart_edit/editor_bottom_toolbar.dart` | #41 | 2 |
| 43 | "Show Tutorial" option in project settings dropdown | `lib/views/smart_edit/smart_edit_view.dart` | #38 | 0.5 |
| 44 | Tests | `test/onboarding_test.dart`, `test/gesture_hint_test.dart` | #35-#43 | 3 |

#### Phase 5: Workspace Resize + Orientation Lock (3-4 days, MEDIUM risk)
Depends on Phase 1.5 (video container reparented to Stack-level).

| # | Task | File(s) | Depends On | Est. Hours |
|---|------|---------|-----------|-----------|
| 45 | Add `SizedBox(height: bottomToolbarHeight + bottomSafeArea)` spacer to Column. Replace `SizedBox(height: 450)` preview with `Expanded(flex: previewFlex)`. Wrap timeline in `Expanded(flex: timelineFlex)`. | `lib/views/smart_edit/smart_edit_view.dart` | Phase 1.5 | 3 |
| 46 | Workspace drag handle widget with `onVerticalDragUpdate`, ratio clamping (0.30-0.80), double-tap reset | `lib/views/smart_edit/smart_edit_view.dart` | #45 | 2 |
| 47 | Collapsed timeline mode when ratio > 0.75 (simple `CupertinoSlider` + timecodes) | `lib/views/smart_edit/smart_edit_view.dart` | #45 | 2 |
| 48 | Orientation lock toggle in top toolbar. Reset orientation in `dispose()` and `WidgetsBindingObserver`. | `lib/views/smart_edit/smart_edit_view.dart` | -- | 2 |
| 49 | Persist workspace ratio and orientation lock preference via `UserPreferencesService` | `lib/core/user_preferences.dart` | #5 | 1 |
| 50 | Tests | `test/workspace_test.dart` | #45-#49 | 2 |

#### Phase 6: Accessibility (5-6 days, MEDIUM risk)
Can start in parallel with Phase 5.

| # | Task | File(s) | Depends On | Est. Hours |
|---|------|---------|-----------|-----------|
| 51 | VoiceOver labels audit: add `Semantics` wrappers to all interactive elements in `smart_edit_view.dart` | `lib/views/smart_edit/smart_edit_view.dart` | -- | 4 |
| 52 | VoiceOver labels: `editor_bottom_toolbar.dart`, `project_library_view.dart` | Multiple files | -- | 2 |
| 53 | Dynamic Type: audit all text elements, ensure `AppTypography.scaledStyle()` usage | All view files | -- | 2 |
| 54 | Reduce Motion: wrap all animations in `context.reduceMotion` check, provide instant alternatives | All animated widgets | -- | 2 |
| 55 | High Contrast: increase border/text contrast when `MediaQuery.highContrast` is true | `lib/design_system/glass_styles.dart`, painters | -- | 2 |
| 56 | Minimum tap target audit: wrap undersized `CompactGlassIconButton` in 44x44 `SizedBox` | All usages | -- | 1 |
| 57 | Color-blind audit: add type icons to timeline clip colors, verify no color-only indicators | Timeline widgets | -- | 1 |
| 58 | VoiceOver during playback: throttle time announcements to every 5s when `accessibleNavigation` is true | `lib/views/smart_edit/smart_edit_view.dart` | #51 | 1 |
| 59 | Tests | `test/accessibility_test.dart` | #51-#58 | 3 |

#### Phase 7: Dark/Light Mode (LOW priority, defer to post-v1)

Not included in the implementation checklist for v1. The dark theme is appropriate for video editing. Light mode can be added later by introducing `CupertinoThemeData` with brightness variants and replacing hardcoded `AppColors` with `CupertinoColors` adaptive equivalents.

---

### Revised Time Estimates

| Phase | Original Est. | Revised Est. | Delta | Reason |
|-------|--------------|-------------|-------|--------|
| Phase 1: Visual Overlays | 3-4 days (19h) | 3-4 days (19h) | 0 | Low risk, no changes |
| Phase 1.5: Fullscreen Rearchitecture | (not in original) | 3-4 days (16h) | +16h | NEW -- CF1/C3 resolution, prerequisite |
| Phase 2: Fullscreen Enhancements | 2-3 days (17h) | 2-3 days (12h) | -5h | Reduced scope (rearchitecture done in 1.5) |
| Phase 3: Comparison + Quality | 3-4 days (19h) | 4-5 days (20h) | +1h | Native snapshot API work added |
| Phase 4: Onboarding + Hints + Help | 4-5 days (23h) | 4-5 days (22h) | -1h | Feature-gating simplifies pages |
| Phase 5: Workspace + Orientation | 3-4 days (17h) | 3-4 days (12h) | -5h | Landscape deferred to post-v1 |
| Phase 6: Accessibility | 3-4 days (21h) | 5-6 days (18h) | -3h on hours, +2 days calendar | More calendar days due to audit breadth |
| **Total** | **~18-24 days (116h)** | **~24-32 days (~119h)** | **+6-8 calendar days, +3h** | Primarily from Phase 1.5 addition |

The hour count is similar (~119h vs ~116h) because landscape deferral and scope reductions offset the new Phase 1.5. However, calendar time increases because Phase 1.5 is a sequential dependency that gates Phase 2 and Phase 5.

---

### Test Plan Verification

| Test Category | Coverage Adequate | Gaps Identified |
|--------------|-------------------|----------------|
| Unit tests (Section 19.1) | YES | Add: `ComparisonConfig` snapshot caching logic, `UserPreferencesService` key serialization, `PreviewQuality` auto mode state transitions |
| Widget tests (Section 19.2) | YES | Add: Fullscreen overlay animation states, workspace drag handle ratio changes, comparison mode indicator visibility |
| Integration tests (Section 19.3) | PARTIAL | Missing: Fullscreen entry/exit in composition mode (the most critical scenario), orientation reset on navigation, gesture hint showing only for implemented features |
| Performance tests (Section 19.4) | YES | Add: `AVAssetImageGenerator` snapshot capture time benchmark (target < 50ms), fullscreen transition animation frame rate (target 60fps during 300ms transition) |

**Additional test scenarios required:**

1. **Fullscreen composition mode round-trip:** Enter fullscreen while composition is playing, verify video continues playing without interruption, exit fullscreen, verify normal layout is intact and `CompositionPlayerView` is still rendering.
2. **Comparison mode in composition paused:** Pause in composition mode, activate split-screen, verify original snapshot is captured and displayed, drag divider, verify smooth update, deactivate comparison, verify normal playback resumes.
3. **Workspace resize with composition player:** Drag workspace handle to resize preview, verify `CompositionPlayerView` bounds update correctly (native `layoutSubviews` called), verify no platform view errors.
4. **Memory pressure during comparison:** Simulate memory warning, verify comparison view releases second frame, verify preview quality drops to quarter.

---

### Final Assessment: CONDITIONAL GO

**Decision: GO with conditions.**

This design document is comprehensive, well-structured, and covers all stated features with sufficient detail for implementation. The three rounds of review have identified and resolved all critical architectural issues. The primary risk center -- `CompositionPlayerView` lifecycle constraints -- has a viable resolution path (Stack-level `AnimatedPositioned` with permanent mounting).

**Conditions for proceeding:**

1. **Phase 1.5 must be implemented and verified BEFORE any other fullscreen or workspace work begins.** This is the foundational rearchitecture that unblocks Phases 2, 3 (split-screen), and 5. If Phase 1.5 encounters unexpected issues with `UiKitView` reparenting or gesture routing, it must be resolved before proceeding.

2. **Landscape editor layout is deferred to post-v1.** Only fullscreen landscape is in scope. This removes ~4 hours of underspecified work and reduces integration risk.

3. **Dark/Light mode is deferred to post-v1.** Phase 7 is not part of this implementation cycle.

4. **All `.withOpacity()` calls in the design must be implemented as `.withValues(alpha: ...)`.** This is a blanket rule -- do not introduce deprecated API usage.

5. **All SF Symbol names must be verified against the SF Symbols 6 catalog before implementation.** Specifically: `lock.rotation`, `lock.rotation.open`, `squareshape.split.3x3`, and `rectangle.center.inset.filled`.

6. **The `GestureHintManager` must have a synchronous-safe initialization path** (await in `main()` before `runApp()`). The singleton must assert initialization before any method call.

7. **Comparison split-screen is paused-only for composition mode.** This scoping decision is final for v1. Toggle mode is available at all times.

---

### Remaining Open Questions

| # | Question | Recommendation | Decision Needed From |
|---|----------|---------------|---------------------|
| OQ1 | Should safe zone presets be per-project or per-app? R1 Q1 raised this. TikTok project vs YouTube project may want different presets. | Per-app for v1 (simpler). Add per-project override in v2 when project settings model is extended. | Product |
| OQ2 | Custom grid row/column input UI? R1 Q3 raised this. No UI specified for entering custom NxM values. | Use a `CupertinoAlertDialog` with two `CupertinoTextField` inputs (rows, columns) shown when "Custom" grid type is selected. Validate input to 2-20 range. | Implementation detail -- proceed with this approach. |
| OQ3 | Pinch-outward to enter fullscreen (Section 3.2.1) -- how to disambiguate from preview zoom pinch? R1 Q6. | Defer pinch-to-fullscreen to post-v1. Keep double-tap and chevron tap as the two entry methods. Pinch on preview should always be zoom. This avoids the disambiguation problem entirely. | Architecture -- recommend deferral. |
| OQ4 | Should the `UserPreferencesService` use `SharedPreferences` directly or go through a repository pattern? 27 preference keys is substantial. | Use a simple `SharedPreferences` wrapper with typed getters/setters. No need for a full repository pattern at this scale. Migrate to a proper settings database if key count exceeds ~50. | Implementation detail -- proceed with wrapper. |
| OQ5 | Onboarding: should gesture animation demos be `CustomPainter` or Lottie? The design suggests `CustomPainter` for v1. | `CustomPainter` for v1 (no new dependency). Lottie can be explored in v2 if more polished animations are desired. | Implementation detail -- proceed with CustomPainter. |

---

### Sign-off

This document, with the resolutions and conditions noted above, is approved for implementation. The design is sound, the critical issues have viable resolution paths, and the phased implementation plan provides appropriate risk isolation. Phase 1 (Visual Overlays) and Phase 4 (Onboarding/Hints/Help) can begin immediately. Phase 1.5 (Fullscreen Rearchitecture) should start in parallel and must complete before Phases 2, 3, and 5.

**Estimated delivery:** 24-32 calendar days for Phases 1 through 6 (excluding Phase 7 Dark/Light Mode).

**Review status:** COMPLETE. No further design review needed. Proceed to implementation.
