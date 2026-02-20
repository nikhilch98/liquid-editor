# Auto-Reframe Keyframe Generation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix auto-reframe to automatically generate keyframes after person selection, add re-selection support, and improve reframing algorithm quality.

**Architecture:** Modify `_showPersonSelectionSheet()` to call `_applyAutoReframe()` after dismissal. Add tracking status and re-selection UI to `AutoReframePanel`. Enhance `AutoReframeEngine` with predictive motion and rule-of-thirds positioning.

**Tech Stack:** Flutter/Dart, Cupertino widgets, existing tracking infrastructure

---

## Task 1: Fix Automatic Keyframe Generation After Person Selection

**Files:**
- Modify: `lib/views/smart_edit/smart_edit_view.dart:260-275`

**Step 1: Read current `_showPersonSelectionSheet()` method**

Verify the current implementation at lines 260-275.

**Step 2: Modify `_showPersonSelectionSheet()` to auto-generate keyframes**

Replace the existing method with:

```dart
/// Show person selection sheet for multi-person videos
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
        },
      ),
    ),
  );

  // Auto-generate keyframes after person selection is confirmed
  if (_trackingController.selectedPersonIndices.isNotEmpty && mounted) {
    debugPrint('Auto-generating keyframes after person selection...');
    await _applyAutoReframe();
    HapticFeedback.mediumImpact();
    if (mounted) setState(() {});
  }
}
```

**Step 3: Verify import exists**

Ensure `HapticFeedback` is imported:
```dart
import 'package:flutter/services.dart';
```

**Step 4: Run flutter analyze**

```bash
flutter analyze
```

Expected: No new errors

---

## Task 2: Add Liquid Glass Styling to AutoReframePanel

**Files:**
- Modify: `lib/views/smart_edit/auto_reframe_panel.dart`

**Step 1: Add dart:ui import for BackdropFilter**

Add at top of file after existing imports:
```dart
import 'dart:ui';
```

**Step 2: Replace Container decoration with Liquid Glass styling**

Replace lines 27-35:
```dart
        return Container(
          decoration: BoxDecoration(
            color: CupertinoColors.black.withValues(alpha: 0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
```

With:
```dart
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              decoration: BoxDecoration(
                color: CupertinoColors.white.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(
                  color: CupertinoColors.white.withValues(alpha: 0.25),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
```

**Step 3: Close the extra wrappers at end of build method**

Find the closing of the Container's child Column (around line 224-226) and add closing brackets:
```dart
            // Bottom safe area
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
            ),
          ),
        );
```

**Step 4: Run flutter analyze**

```bash
flutter analyze
```

---

## Task 3: Add TrackingController and Re-selection to AutoReframePanel

**Files:**
- Modify: `lib/views/smart_edit/auto_reframe_panel.dart`

**Step 1: Add TrackingController import and props**

Add import:
```dart
import '../smart_edit/tracking_controller.dart';
```

Update class props (after line 9):
```dart
class AutoReframePanel extends StatelessWidget {
  final AutoReframeEngine engine;
  final TrackingController? trackingController;
  final VoidCallback? onApply;
  final VoidCallback? onDisable;
  final VoidCallback? onClose;
  final VoidCallback? onChangePersons;

  const AutoReframePanel({
    super.key,
    required this.engine,
    this.trackingController,
    this.onApply,
    this.onDisable,
    this.onClose,
    this.onChangePersons,
  });
```

**Step 2: Add tracking status row after the title section**

After the close button row (after line 127), before the sliders section, add:

```dart
              // Tracking status and re-selection (show when tracking is active)
              if (trackingController != null && trackingController!.selectedPersonIndices.isNotEmpty) ...[
                Container(height: 1, color: CupertinoColors.white.withValues(alpha: 0.1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.person_2_fill,
                        size: 18,
                        color: CupertinoColors.activeGreen,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tracking ${trackingController!.selectedPersonIndices.length} person${trackingController!.selectedPersonIndices.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: CupertinoColors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: onChangePersons,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: CupertinoColors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: CupertinoColors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Text(
                            'Change',
                            style: TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
```

**Step 3: Run flutter analyze**

```bash
flutter analyze
```

---

## Task 4: Update SmartEditView to Pass TrackingController to Panel

**Files:**
- Modify: `lib/views/smart_edit/smart_edit_view.dart`

**Step 1: Find AutoReframePanel usage and add new props**

Find the AutoReframePanel instantiation (around line 674) and update:

```dart
                    child: AutoReframePanel(
                      engine: _autoReframeEngine,
                      trackingController: _trackingController,
                      onApply: () async {
                        await _applyAutoReframe();
                        setState(() {
                          _showAutoReframePanel = false;
                        });
                      },
                      onDisable: () {
                        _disableAutoReframe();
                      },
                      onClose: () {
                        setState(() {
                          _showAutoReframePanel = false;
                        });
                      },
                      onChangePersons: () async {
                        // Close panel, show person selection, regenerate
                        setState(() {
                          _showAutoReframePanel = false;
                        });
                        await _showPersonSelectionSheet();
                      },
                    ),
```

**Step 2: Run flutter analyze**

```bash
flutter analyze
```

---

## Task 5: Add Framing Style to AutoReframeConfig

**Files:**
- Modify: `lib/core/auto_reframe_engine.dart`

**Step 1: Add FramingStyle enum at top of file (after imports, before AutoReframeConfig)**

```dart
/// Framing style for subject positioning
enum FramingStyle {
  /// Center subjects in frame
  centered,
  /// Position subjects according to rule of thirds
  ruleOfThirds,
}
```

**Step 2: Add new fields to AutoReframeConfig**

Add after `targetAspectRatio` field (around line 28):

```dart
  /// Framing style (centered or rule of thirds)
  final FramingStyle framingStyle;

  /// Look-ahead duration in milliseconds for predictive motion (0-500)
  final int lookaheadMs;
```

**Step 3: Update AutoReframeConfig constructor**

```dart
  const AutoReframeConfig({
    this.zoomIntensity = 1.2,
    this.followSpeed = 0.3,
    this.safeZonePadding = 0.1,
    this.maxZoom = 3.0,
    this.minZoom = 1.0,
    this.targetAspectRatio,
    this.framingStyle = FramingStyle.centered,
    this.lookaheadMs = 150,
  });
```

**Step 4: Update copyWith method**

```dart
  AutoReframeConfig copyWith({
    double? zoomIntensity,
    double? followSpeed,
    double? safeZonePadding,
    double? maxZoom,
    double? minZoom,
    double? targetAspectRatio,
    FramingStyle? framingStyle,
    int? lookaheadMs,
  }) {
    return AutoReframeConfig(
      zoomIntensity: zoomIntensity ?? this.zoomIntensity,
      followSpeed: followSpeed ?? this.followSpeed,
      safeZonePadding: safeZonePadding ?? this.safeZonePadding,
      maxZoom: maxZoom ?? this.maxZoom,
      minZoom: minZoom ?? this.minZoom,
      targetAspectRatio: targetAspectRatio ?? this.targetAspectRatio,
      framingStyle: framingStyle ?? this.framingStyle,
      lookaheadMs: lookaheadMs ?? this.lookaheadMs,
    );
  }
```

**Step 5: Run flutter analyze**

```bash
flutter analyze
```

---

## Task 6: Implement Rule of Thirds Positioning

**Files:**
- Modify: `lib/core/auto_reframe_engine.dart`

**Step 1: Add motion direction tracking to class**

Add after `_transformHistory` (around line 93):

```dart
  /// Last known motion direction for rule of thirds
  Offset _lastMotionDirection = Offset.zero;
```

**Step 2: Add method to compute motion direction**

Add after `_addToHistory` method:

```dart
  /// Compute motion direction from recent bounding box positions
  Offset _computeMotionDirection(Rect? currentBbox, Rect? previousBbox) {
    if (currentBbox == null || previousBbox == null) {
      return _lastMotionDirection;
    }

    final dx = currentBbox.center.dx - previousBbox.center.dx;
    final dy = currentBbox.center.dy - previousBbox.center.dy;

    // Only update if movement is significant
    if (dx.abs() > 0.01 || dy.abs() > 0.01) {
      _lastMotionDirection = Offset(dx, dy);
    }

    return _lastMotionDirection;
  }
```

**Step 3: Add rule of thirds offset calculation**

Add after motion direction method:

```dart
  /// Calculate target position offset for rule of thirds framing
  Offset _calculateRuleOfThirdsOffset(Offset motionDirection) {
    // Place subject on opposite third from motion direction
    // Moving right → place on left third (offset positive, moves frame left)
    // Moving left → place on right third (offset negative, moves frame right)

    double xOffset = 0.0;
    if (motionDirection.dx > 0.005) {
      // Moving right, place subject at left third
      xOffset = 0.12; // ~1/6 of frame to position at 1/3
    } else if (motionDirection.dx < -0.005) {
      // Moving left, place subject at right third
      xOffset = -0.12;
    }

    // Slight upward bias for more pleasing framing
    const yOffset = -0.03;

    return Offset(xOffset, yOffset);
  }
```

**Step 4: Modify computeTargetTransform to use framing style**

In `computeTargetTransform`, after calculating `targetX` and `targetY` (around line 181), add:

```dart
    // Apply rule of thirds offset if enabled
    double finalTargetX = targetX;
    double finalTargetY = targetY;

    if (_config.framingStyle == FramingStyle.ruleOfThirds) {
      final ruleOfThirdsOffset = _calculateRuleOfThirdsOffset(_lastMotionDirection);
      finalTargetX += ruleOfThirdsOffset.dx * scale;
      finalTargetY += ruleOfThirdsOffset.dy * scale;
    }
```

Then update the clamping to use `finalTargetX` and `finalTargetY`:

```dart
    // Clamp translation to computed limits
    final clampedX = finalTargetX.clamp(finalMinX, finalMaxX);
    final clampedY = finalTargetY.clamp(finalMinY, finalMaxY);
```

**Step 5: Run flutter analyze**

```bash
flutter analyze
```

---

## Task 7: Implement Predictive Motion (Look-ahead)

**Files:**
- Modify: `lib/core/auto_reframe_engine.dart`

**Step 1: Update generateKeyframes to use configurable lookahead**

In `generateKeyframes`, replace the fixed `_lookaheadFrames` usage with config-based value.

Find (around line 450):
```dart
      // Use lookahead averaging for smoother motion
      final avgBbox = _computeAveragedBbox(
        sortedResults,
        resultIndex,
        _lookaheadFrames,
        selectedPersonIndices,
      );
```

Replace with:
```dart
      // Calculate lookahead frame count from config (assuming ~30fps)
      final lookaheadFrameCount = (_config.lookaheadMs / 33.0).ceil().clamp(1, 15);

      // Use lookahead averaging for smoother, predictive motion
      final avgBbox = _computeAveragedBbox(
        sortedResults,
        resultIndex,
        lookaheadFrameCount,
        selectedPersonIndices,
      );

      // Track motion direction for rule of thirds
      Rect? previousBbox;
      if (resultIndex > 0) {
        final prevFrame = sortedResults[resultIndex - 1];
        final prevPersons = prevFrame.people
            .where((p) => selectedPersonIndices.contains(p.personIndex))
            .toList();
        previousBbox = computeCombinedBoundingBox(prevPersons);
      }
      _computeMotionDirection(avgBbox, previousBbox);
```

**Step 2: Run flutter analyze**

```bash
flutter analyze
```

---

## Task 8: Add Framing Style and Look-ahead Controls to Panel

**Files:**
- Modify: `lib/views/smart_edit/auto_reframe_panel.dart`

**Step 1: Add import for auto_reframe_engine enums**

Already imported via `auto_reframe_engine.dart`.

**Step 2: Add Framing Style toggle after Safe Zone slider**

After the Safe Zone slider section (around line 186), add:

```dart
                      const SizedBox(height: 16),

                      // Framing Style toggle
                      Row(
                        children: [
                          const Icon(CupertinoIcons.rectangle_split_3x3, size: 16, color: CupertinoColors.systemGrey),
                          const SizedBox(width: 8),
                          const Text(
                            'Framing',
                            style: TextStyle(
                              color: CupertinoColors.systemGrey2,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          CupertinoSlidingSegmentedControl<FramingStyle>(
                            groupValue: engine.config.framingStyle,
                            children: const {
                              FramingStyle.centered: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('Center', style: TextStyle(fontSize: 12)),
                              ),
                              FramingStyle.ruleOfThirds: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('Thirds', style: TextStyle(fontSize: 12)),
                              ),
                            },
                            onValueChanged: (value) {
                              if (value != null) {
                                engine.config = engine.config.copyWith(framingStyle: value);
                                onApply?.call();
                              }
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Look-ahead slider
                      _SliderRow(
                        label: 'Look-ahead',
                        value: engine.config.lookaheadMs.toDouble(),
                        min: 0,
                        max: 500,
                        icon: CupertinoIcons.arrow_right_circle,
                        valueLabel: '${engine.config.lookaheadMs}ms',
                        onChanged: (value) {
                          engine.config = engine.config.copyWith(lookaheadMs: value.toInt());
                          onApply?.call();
                        },
                      ),
```

**Step 3: Run flutter analyze**

```bash
flutter analyze
```

---

## Task 9: Pre-select Current Persons in PersonSelectionSheet

**Files:**
- Modify: `lib/views/smart_edit/person_selection_sheet.dart`

**Step 1: Verify PersonSelectionSheet uses controller's selectedPersonIndices**

The current implementation already uses `controller.isPersonSelected(person.personIndex)` to show selection state. This should work correctly for re-selection since the controller maintains the selection state.

**Step 2: Verify the selection persists**

No code changes needed - the TrackingController already maintains `_selectedPersonIndices` across sheet open/close cycles.

---

## Task 10: Final Verification and Testing

**Step 1: Run flutter analyze**

```bash
flutter analyze
```

Expected: 0 new errors (only pre-existing info warnings)

**Step 2: Run flutter test**

```bash
flutter test
```

**Step 3: Manual testing checklist**

- [ ] Load a video with people
- [ ] Enable tracking (should analyze)
- [ ] Person selection sheet appears after analysis
- [ ] Select persons and confirm
- [ ] Keyframes auto-generate on timeline
- [ ] Open AutoReframePanel
- [ ] Verify "Tracking N persons" status shows
- [ ] Tap "Change" to re-select persons
- [ ] Verify new keyframes generate after re-selection
- [ ] Test Framing Style toggle (Center vs Thirds)
- [ ] Test Look-ahead slider
- [ ] Verify smooth camera following during playback

---

## Summary of Changes

| File | Changes |
|------|---------|
| `smart_edit_view.dart` | Auto-call `_applyAutoReframe()` after person selection, pass `trackingController` to panel, add `onChangePersons` callback |
| `auto_reframe_panel.dart` | Add Liquid Glass styling, tracking status row, Change button, Framing Style toggle, Look-ahead slider |
| `auto_reframe_engine.dart` | Add `FramingStyle` enum, `framingStyle` and `lookaheadMs` config, rule of thirds calculation, predictive motion |
| `person_selection_sheet.dart` | No changes needed (already works for re-selection) |
