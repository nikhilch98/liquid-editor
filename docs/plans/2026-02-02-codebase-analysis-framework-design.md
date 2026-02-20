# Codebase Analysis Framework Design

**Created:** 2026-02-02
**Status:** In Progress

---

## Overview

Comprehensive per-file analysis of all Swift and Dart files in the Liquid Editor codebase, covering:
- Technical debt identification and refactoring opportunities
- App Store quality gate verification (iOS 26 compliance, performance, edge cases)
- Onboarding documentation for new developers

---

## Analysis Scope

### Swift Files (21 files)
- `ios/Runner/` - App delegates, services
- `ios/Runner/Timeline/` - Composition building, decoder pool
- `ios/Runner/Tracking/` - Vision framework tracking
- `ios/Runner/Tracking/ReID/` - Re-identification
- `ios/Runner/People/` - People detection
- `ios/RunnerTests/` - Native tests

### Dart Files (~76 files)
- `lib/main.dart` - Entry point
- `lib/models/` - Data models
- `lib/models/clips/` - Timeline clip types
- `lib/core/` - Business logic
- `lib/design_system/` - Liquid Glass styling
- `lib/components/` - Reusable components
- `lib/views/smart_edit/` - Editor views
- `lib/timeline/` - Timeline module (data, cache, editing, rendering, gestures, widgets)
- `test/` - Test files

---

## File Naming Convention

**Pattern:** `analysis_[lang]_[full_unique_path].md`

**Examples:**
- `analysis_swift_ios_Runner_AppDelegate.md`
- `analysis_dart_lib_core_frame_cache.md`
- `analysis_dart_lib_timeline_data_models_timeline_clip.md`

---

## Template Structure

Each analysis file contains:

### Header Sections
1. **File Summary** - Purpose, category, line count, dates
2. **Dependencies** - What it imports, what imports it
3. **Architecture Compliance** - SRP, DRY, Thread Safety, Error Handling, Documentation
4. **Documentation Quality** - File-level docs, API docs, comments accuracy
5. **Test Coverage** - Associated test file, coverage status
6. **Risk Assessment** - Overall risk level with rationale

### Analysis Tables
7. **UI Analysis** - 16 columns (or N/A)
8. **Logic Analysis** - 18 columns (or N/A)

### Summary
9. **Improvements** - Prioritized list (Critical, Medium, Low)

---

## UI Analysis Columns (16)

| # | Column | Values |
|---|--------|--------|
| 1 | Element | Text name |
| 2 | Type | Button / Slider / TextField / Container / List / Gesture / Animation / Other |
| 3 | Liquid Glass Compliant | ✅ / ❌ / ⚠️ |
| 4 | Component Used | Widget class name |
| 5 | Correct Implementation | ✅ / ❌ / ⚠️ |
| 6 | Dependency Usage | ✅ / ❌ / ⚠️ |
| 7 | Responsive | ✅ / ❌ / ⚠️ |
| 8 | Overflow Handling | ✅ / ❌ / ⚠️ |
| 9 | Safe Area | ✅ / ❌ / ⚠️ / N/A |
| 10 | Accessibility | ✅ / ❌ / ⚠️ |
| 11 | Haptic Feedback | ✅ / ❌ / N/A |
| 12 | Hardcoded Values | ✅ None / ⚠️ Some / ❌ Many |
| 13 | State Handling | ✅ / ❌ / ⚠️ |
| 14 | Edge Cases | ✅ / ❌ / ⚠️ |
| 15 | Improvements | Text |
| 16 | Priority | 🔴 / 🟡 / 🟢 |

---

## Logic Analysis Columns (18)

| # | Column | Values |
|---|--------|--------|
| 1 | Method | Signature |
| 2 | Purpose | Text description |
| 3 | Correct Implementation | ✅ / ❌ / ⚠️ |
| 4 | Complexity | O(1) / O(log n) / O(n) / O(n²) / etc. |
| 5 | Dependency Usage | ✅ / ❌ / ⚠️ |
| 6 | Contract Adherence | ✅ / ❌ / ⚠️ |
| 7 | Thread Safety | ✅ Main Thread / ✅ Background / ✅ Thread-Safe / ⚠️ Risk / ❌ Race Condition |
| 8 | Error Handling | ✅ Throws / ✅ Result Type / ⚠️ Silent / ❌ Crashes |
| 9 | Input Validation | ✅ / ❌ / ⚠️ / N/A |
| 10 | Edge Cases | ✅ / ❌ / ⚠️ |
| 11 | Memory Management | ✅ / ❌ / ⚠️ / N/A |
| 12 | Performance | ✅ / ❌ / ⚠️ |
| 13 | Hardcoded Values | ✅ None / ⚠️ Some / ❌ Many |
| 14 | Configurable | ✅ / ⚠️ / ❌ / N/A |
| 15 | Test Coverage | ✅ Tested / ⚠️ Partial / ❌ No Tests |
| 16 | Side Effects | Text or "None" |
| 17 | Improvements | Text |
| 18 | Priority | 🔴 / 🟡 / 🟢 |

---

## Index File

`analysis/INDEX.md` contains:
- Summary statistics (total issues by priority, compliance %)
- Table of all files with risk level and issue counts
- Top 10 critical issues across codebase
- Quick links to each analysis file

---

## Analysis Groups (for parallel processing)

| Group | Files | Agent |
|-------|-------|-------|
| Swift - Core | AppDelegate, SceneDelegate, ProxyGenerator, CompositionPlayerService | 1 |
| Swift - Timeline | CompositionBuilder, NativeDecoderPool, CompositionManagerService | 2 |
| Swift - Tracking | TrackingService, TrackingProtocol, BoundingBoxTracker, TrackingDataStore, TrackDebugInfo | 3 |
| Swift - Tracking Utils | KalmanFilter, PersonIdentifier, CameraMotionCompensator | 4 |
| Swift - ReID & People | ReIDExtractor, AppearanceFeature, TrackArchive, PeopleService, PeopleMethodChannel | 5 |
| Dart - Entry & Models | main, export_preset, detected_person, project, keyframe, media_asset | 6 |
| Dart - Models V2 | timeline_node, persistent_timeline, rational, timeline_v2, clips/* | 7 |
| Dart - Core (Part 1) | gesture_capture_engine, transform_interpolator, project_storage, auto_reframe_engine | 8 |
| Dart - Core (Part 2) | tracking_storage, playback_controller, composition_playback_controller, timeline_manager | 9 |
| Dart - Core (Part 3) | composition_manager, scrub_controller, playback_engine_controller, decoder_pool, frame_cache | 10 |
| Dart - Design System | liquid_action_sheet, glass_styles, liquid_glass_popup, liquid_glass_fab, native_glass_fab | 11 |
| Dart - Views | All smart_edit views | 12 |
| Dart - Timeline Models | All timeline/data/models/* | 13 |
| Dart - Timeline Cache | All timeline/cache/* | 14 |
| Dart - Timeline Editing | All timeline/editing/* | 15 |
| Dart - Timeline Rendering | All timeline/rendering/* | 16 |
| Dart - Timeline Gestures | All timeline/gestures/* | 17 |
| Dart - Timeline Widgets | timeline.dart, timeline_controller, widgets/* | 18 |
| Tests | All test files | 19 |

---

## Deliverables

1. `analysis/INDEX.md` - Master index with statistics
2. `analysis/analysis_*.md` - One file per source file (~97 files)
3. Updated `docs/plans/2026-02-02-codebase-analysis-framework-design.md` - This document

