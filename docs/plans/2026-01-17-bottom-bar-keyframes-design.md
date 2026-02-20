# Bottom Bar & Keyframes Fix Design

**Date:** 2026-01-17
**Status:** Approved for Implementation

## Problem Statement

1. **Keyframes don't work** - Transform not applied during playback due to timing sync issues
2. **Bottom bar not Liquid Glass** - Uses custom widgets instead of native iOS components

## Solution

### Part 1: Keyframe Bug Fix

**Root Cause:** Race condition between ticker's `setState()` and ViewModel's `notifyListeners()`. Also `smoothCurrentTime` vs `currentTime` mismatch.

**Fix:**
1. Remove redundant ticker in `smart_edit_view.dart`
2. Use ViewModel's `notifyListeners()` as single update source
3. Use consistent time source in `currentTransform` getter

### Part 2: Liquid Glass Bottom Bar

**Layout:**
```
┌─────────────────────────────────────────────────────────┐
│  [CNTabBar - Left]              [Action Buttons - Right] │
│  ┌─────────────────────┐        ┌────┐ ┌────┐ ┌────┐    │
│  │ Edit │ FX │ Audio │ │        │ ◇+ │ │ ↶  │ │ ↷  │    │
│  └─────────────────────┘        └────┘ └────┘ └────┘    │
└─────────────────────────────────────────────────────────┘
```

**Tab Categories:**
- Edit: Keyframes, Trim, Split, Copy
- FX: Filters, Effects, Adjust
- Audio: Volume, Speed, Voice
- Smart: Track, Auto-reframe, Captions

**Components Used:**
- `CNTabBar` from `cupertino_native_better`
- `CNButton.icon` with `CNButtonStyle.glass`
- `CNSymbol` for SF Symbols

### File Changes

1. `lib/views/smart_edit/smart_edit_view.dart` - Remove ticker, integrate new toolbar
2. `lib/views/smart_edit/smart_edit_view_model.dart` - Fix currentTransform time source
3. `lib/views/smart_edit/editor_bottom_toolbar.dart` - Complete rewrite with native components
