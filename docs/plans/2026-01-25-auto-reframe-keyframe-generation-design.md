# Auto-Reframe Keyframe Generation Design

**Date:** 2026-01-25
**Status:** Approved

## Problem Statement

Auto-reframe does not automatically generate and place keyframes on the timeline after tracking completes. Users must manually open the AutoReframePanel and click "Apply" - a broken workflow that isn't discoverable.

Additionally, users cannot change person selection after initial tracking, and the reframing algorithm needs improvements for professional-quality output.

## Requirements

1. **Automatic keyframe generation** after person selection completes
2. **Re-selection support** - ability to change tracked persons via AutoReframePanel
3. **State-of-the-art reframing** with smooth following, smart framing, predictive motion, rule of thirds
4. **Full keyframe editing** - users can move, delete, modify any keyframe
5. **Same aspect ratio** - pan/zoom within original frame, no cropping to different ratios

## Design

### 1. Automatic Keyframe Generation Flow

**Current broken flow:**
```
Tracking → Person Selection → Confirm → (nothing happens)
```

**Fixed flow:**
```
Tracking → Person Selection → Confirm → Auto-generate keyframes → Show on timeline
```

**Implementation in `smart_edit_view.dart`:**

```dart
Future<void> _showPersonSelectionSheet() async {
  await showCupertinoModalPopup(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => Material(
      type: MaterialType.transparency,
      child: PersonSelectionSheet(
        controller: _trackingController,
        onDismiss: () {
          Navigator.of(context).pop();
          if (mounted) setState(() {});
        },
      ),
    ),
  );

  // NEW: Auto-generate keyframes after person selection
  if (_trackingController.selectedPersonIndices.isNotEmpty && mounted) {
    await _applyAutoReframe();
    // Show success feedback
    HapticFeedback.mediumImpact();
    setState(() {});
  }
}
```

### 2. Re-selection in AutoReframePanel

**UI Layout:**
```
┌─────────────────────────────────────┐
│  Auto-Reframe Settings              │
├─────────────────────────────────────┤
│  👥 Tracking 2 persons    [Change]  │  ← NEW
├─────────────────────────────────────┤
│  Framing Style    [Centered ▼]      │  ← NEW
├─────────────────────────────────────┤
│  Zoom Intensity     ────●────       │
│  Follow Speed       ──●──────       │
│  Safe Zone          ●────────       │
│  Look-ahead         ──●────         │  ← NEW
├─────────────────────────────────────┤
│  [Regenerate Keyframes]             │
└─────────────────────────────────────┘
```

**Behavior:**
- Display current tracking status: "Tracking N persons"
- "Change" button opens PersonSelectionSheet
- After confirming new selection → auto-regenerates keyframes
- PersonSelectionSheet pre-selects currently tracked persons

**New props for AutoReframePanel:**
```dart
class AutoReframePanel extends StatelessWidget {
  final AutoReframeEngine engine;
  final TrackingController trackingController; // NEW
  final VoidCallback onApply;
  final VoidCallback onDisable;
  final VoidCallback onClose;
  final Future<void> Function() onChangePersons; // NEW
}
```

### 3. State-of-the-Art Reframing Algorithm

#### 3.1 Improved Smoothing
- Increase smoothing history: 10 → 30 frames
- Use exponential moving average (EMA) instead of simple average
- Velocity-based dampening: faster movement = less smoothing lag

```dart
// Exponential moving average
double _emaAlpha = 0.15; // Smoothing factor
VideoTransform _smoothedTransform = VideoTransform.identity;

VideoTransform applyEMASmoothing(VideoTransform target) {
  _smoothedTransform = VideoTransform(
    scale: _smoothedTransform.scale + _emaAlpha * (target.scale - _smoothedTransform.scale),
    translation: Offset(
      _smoothedTransform.translation.dx + _emaAlpha * (target.translation.dx - _smoothedTransform.translation.dx),
      _smoothedTransform.translation.dy + _emaAlpha * (target.translation.dy - _smoothedTransform.translation.dy),
    ),
  );
  return _smoothedTransform;
}
```

#### 3.2 Smart Multi-Person Framing
```dart
Rect computeCombinedBoundingBox(List<PersonTrackingResult> persons) {
  // Existing: merge all bounding boxes
  // Enhancement: add dynamic padding based on spread

  final spread = bbox.width / frameWidth;
  final dynamicPadding = spread > 0.6
      ? config.safeZonePadding * 0.5  // Less padding when spread
      : config.safeZonePadding * 1.5; // More padding when close
}
```

#### 3.3 Predictive Motion (Look-ahead)
```dart
VideoTransform computeWithLookahead({
  required List<FrameTrackingResult> results,
  required int currentIndex,
  required int lookaheadFrames, // 5-15 frames (~150-500ms at 30fps)
}) {
  // Get current and future positions
  final current = results[currentIndex];
  final futureIndex = min(currentIndex + lookaheadFrames, results.length - 1);
  final future = results[futureIndex];

  // Calculate motion vector
  final currentCenter = getCombinedCenter(current);
  final futureCenter = getCombinedCenter(future);
  final motionVector = futureCenter - currentCenter;

  // Bias frame position toward predicted location
  final predictedCenter = currentCenter + motionVector * 0.3;

  return computeTransformForCenter(predictedCenter);
}
```

#### 3.4 Rule of Thirds Positioning
```dart
enum FramingStyle { centered, ruleOfThirds }

Offset computeTargetPosition(Rect bbox, FramingStyle style) {
  if (style == FramingStyle.centered) {
    return Offset(0.5, 0.5); // Center of frame
  }

  // Rule of thirds
  final bboxCenter = bbox.center;
  final motionDirection = _computeMotionDirection();

  // Place subject on opposite third from motion direction
  // Moving right → place on left third (0.33)
  // Moving left → place on right third (0.67)
  final xPosition = motionDirection.dx > 0 ? 0.33 : 0.67;

  // Vertical: keep roughly centered or slight upper third
  final yPosition = 0.45;

  return Offset(xPosition, yPosition);
}
```

### 4. Keyframe Timeline Integration

**Ensure keyframes appear on timeline:**
1. Verify `KeyframeTimelineView` is in SmartEditView's widget tree
2. Pass `_viewModel.keyframeManager` to the timeline
3. Call `setState()` after keyframe generation to trigger rebuild

**Visual feedback on generation:**
```dart
// In _applyAutoReframe() after adding keyframes:
HapticFeedback.mediumImpact();

// Optional: show toast
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('Generated ${keyframes.length} keyframes')),
);
```

**Keyframe interactions (already implemented in KeyframeTimelineView):**
- Tap → select keyframe
- Double-tap → open KeyframeEditorSheet
- Long-press → quick actions menu
- Drag → move keyframe time position

### 5. New Configuration Options

**Add to AutoReframeConfig:**
```dart
class AutoReframeConfig {
  // Existing
  final double zoomIntensity;
  final double followSpeed;
  final double safeZonePadding;
  final double maxZoom;
  final double minZoom;

  // New
  final FramingStyle framingStyle;      // centered or ruleOfThirds
  final int lookaheadMs;                // 0-500ms for predictive motion
  final bool useAdaptiveSmoothing;      // EMA vs simple average
}
```

## Files to Modify

| File | Changes |
|------|---------|
| `lib/views/smart_edit/smart_edit_view.dart` | Call `_applyAutoReframe()` after person selection, add feedback |
| `lib/views/smart_edit/auto_reframe_panel.dart` | Add person re-selection UI, framing style toggle, look-ahead slider |
| `lib/core/auto_reframe_engine.dart` | Implement predictive motion, rule of thirds, improved smoothing |
| `lib/views/smart_edit/person_selection_sheet.dart` | Support re-selection (pre-select current persons) |
| `lib/models/keyframe.dart` | Add FramingStyle enum if needed |

## Implementation Order

1. **Fix broken connection** - Auto-generate keyframes after person selection (~30 min)
2. **Add re-selection to panel** - "Change Tracked Persons" button (~1 hour)
3. **Improve smoothing algorithm** - EMA, velocity dampening (~1 hour)
4. **Add predictive motion** - Look-ahead computation (~2 hours)
5. **Add rule of thirds** - Compositional framing option (~1 hour)
6. **Add success feedback** - Toast, haptic, ensure timeline shows keyframes (~30 min)

## Success Criteria

- [ ] Keyframes auto-generate after person selection without manual intervention
- [ ] Keyframes visible on timeline immediately after generation
- [ ] Can change tracked persons via AutoReframePanel
- [ ] Smooth camera movement, no jitter
- [ ] Camera anticipates motion (doesn't lag behind fast movement)
- [ ] Rule of thirds option produces visually pleasing compositions
- [ ] All keyframes fully editable after generation
