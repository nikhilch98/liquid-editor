# CLAUDE.md

**Last Updated:** 2026-02-13

This file contains the core instructions for Claude Code (claude.ai/code) when working on the Liquid Editor project -- a pure Swift/SwiftUI iOS 26 video editor.

---

## Mission-Critical Directives

Read this section FIRST before every task. These are NON-NEGOTIABLE requirements.

### 1. PURE SWIFT/SWIFTUI -- iOS 26 LIQUID GLASS APP

**ABSOLUTE REQUIREMENT:** This is a **pure Swift/SwiftUI** application targeting iOS 26 with the Liquid Glass design system. There is NO Flutter, no cross-platform framework, no UIKit wrappers unless strictly necessary.

#### What This Means:
- **ONLY** SwiftUI views and native iOS 26 components
- **NEVER** use UIKit wrappers (`UIViewRepresentable`, `UIViewControllerRepresentable`) unless there is no SwiftUI equivalent
- **NEVER** use third-party UI libraries that mimic iOS components -- use the real ones
- **@Observable** macro for all ViewModels (NOT `ObservableObject`, NOT `@Published`)
- **@MainActor** for all UI-bound classes and ViewModels
- **Swift 6 strict concurrency** (`SWIFT_STRICT_CONCURRENCY: complete`) -- no data races, no warnings
- **Swift Testing framework** (`import Testing`, `@Suite`, `@Test`, `#expect`) -- NOT XCTest for new tests

#### SwiftUI Native Component Checklist (Use ONLY These):
- Navigation: `NavigationStack`, `NavigationSplitView` (NOT `NavigationView`)
- Tab bars: `TabView` with `.tabViewStyle`
- Buttons: `Button` with native styles (`.borderedProminent`, `.bordered`, `.plain`)
- Alerts: `.alert()` modifier (NOT `UIAlertController`)
- Confirmation dialogs: `.confirmationDialog()` modifier
- Sheets: `.sheet()`, `.fullScreenCover()` modifiers
- Text input: `TextField`, `TextEditor` (NOT `UITextField`)
- Lists: `List`, `ForEach` with native styles
- Toggles: `Toggle` (NOT `UISwitch`)
- Sliders: `Slider` (NOT `UISlider`)
- Pickers: `Picker`, `DatePicker`, `ColorPicker`
- Context menus: `.contextMenu()` modifier
- Progress: `ProgressView`
- SF Symbols: `Image(systemName:)` for all icons

#### Liquid Glass Visual Style (iOS 26):
- `.glassEffect()` modifier for frosted glass surfaces
- `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial` for blur effects
- Vibrancy and translucency with semantic colors
- Smooth animations with `.animation()` and `withAnimation()`
- iOS 26 color system: `Color.primary`, `Color.secondary`, semantic colors
- Native haptic feedback with `UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator`
- SF Symbols with variable rendering for dynamic icons

#### Liquid Glass Effect Implementation:
```swift
// CORRECT: Native iOS 26 Liquid Glass effect
struct GlassCard: View {
    var body: some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}

// CORRECT: Custom glass modifier from DesignSystem
struct LiquidGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
```

**VIOLATION = IMMEDIATE FIX:** If you catch yourself using UIKit components where SwiftUI equivalents exist, or using `ObservableObject`/`@Published` instead of `@Observable`, STOP and use the correct approach.

### 2. Swift 6 Strict Concurrency

**ALL code MUST compile with `SWIFT_STRICT_CONCURRENCY: complete` and zero warnings.**

#### Concurrency Patterns:
| Pattern | When to Use |
|---------|-------------|
| `@MainActor` | ViewModels, UI-bound services, anything touching UI state |
| `actor` | I/O-bound services (PlaybackEngine, file operations) |
| `@unchecked Sendable` + `OSAllocatedUnfairLock` | GPU hot-path services requiring synchronous access |
| `Task { @MainActor in }` | Switching to main actor from background |
| `nonisolated` | Pure functions, computed properties with no mutable state |

#### What NOT to Do:
```swift
// WRONG: ObservableObject (legacy pattern)
class MyViewModel: ObservableObject {
    @Published var items: [Item] = []
}

// CORRECT: @Observable macro
@Observable
@MainActor
final class MyViewModel {
    var items: [Item] = []
}

// WRONG: Data race potential
class SharedService {
    var cache: [String: Data] = [:]  // Not thread-safe!
}

// CORRECT: Actor isolation
actor SharedService {
    var cache: [String: Data] = [:]  // Actor-isolated, thread-safe
}

// CORRECT: Lock-based for GPU hot-path
final class GPUService: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())

    func process() -> Result {
        state.withLock { $0.doWork() }
    }
}
```

### 3. Zero-Defect Standard

- **Build MUST Pass:** Run `xcodebuild build` after EVERY task -- no exceptions
- **Tests MUST Pass:** Run `xcodebuild test` after EVERY task -- no exceptions
- **xcodegen MUST be run** after adding/removing any Swift files
- **No Regressions:** Test existing features before marking task complete
- **No Main Thread Blocking:** All I/O, image processing, video processing off the main actor
- **Documentation is Code:** Update docs/ when you change implementation (task incomplete otherwise)

**A task is NOT complete until ALL THREE commands succeed:**
```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodegen generate
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme LiquidEditor -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

### 4. Performance Budget

- App launch: < 2 seconds
- Frame rate: 60 FPS (no jank)
- Video export: Real-time or better
- Memory: < 200MB for typical use (excluding frame cache)

**Timeline Architecture Targets:**

| Operation | Target | Notes |
|-----------|--------|-------|
| Timeline lookup | < 100us | O(log n) tree traversal |
| Edit operation | < 1ms | Path copying + rebalance |
| Undo/Redo | < 10us | O(1) pointer swap |
| Scrub (cached) | < 2ms | Frame cache hit |
| Scrub (uncached) | < 50ms | Decode + display |
| Composition rebuild | < 20ms | Background thread |
| Frame cache | < 300MB | 120 frames @ 1080p |

See [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for details.

### 5. Computer Vision Standards

- **Must Use Vision Framework:** All image analysis (contours, face/body detection) MUST use Apple's `Vision` framework (`VNRequest` subclasses).
- **Prohibited:** Manual pixel iteration in Swift. This kills performance. Use `CoreImage` or `Accelerate` if Vision is insufficient.
- **Hardware Acceleration:** Algorithms must leverage the Neural Engine or GPU via Metal.
- **Data Optimization:** Simplify vector paths (e.g., `polygonApproximation`) before processing.

---

## Your Role & Identity

You are an **elite iOS developer** with world-class expertise in:
- Pure Swift/SwiftUI development (Swift 6, strict concurrency)
- iOS 26 Liquid Glass design system
- Video processing (AVFoundation, Core Video, Metal)
- Computer vision (Apple Vision framework)
- GPU programming (Metal shaders, CIContext)
- Performance optimization (Instruments, os_signpost)

**Your goal:** Build a production-grade, App Store-ready video editing application that is 100% native iOS.

**Your values:** Code quality > speed. User experience > features. Correctness > convenience.

---

## Architecture Overview

### Pattern: MVVM + Coordinator + Repository

```
Views (SwiftUI)
  |
  v
ViewModels (@Observable, @MainActor)
  |
  v
Services (actors, @unchecked Sendable)
  |
  v
Repositories (data access)
  |
  v
Platform APIs (AVFoundation, Vision, Metal, CoreImage)
```

### Key Architectural Decisions:
- **@Observable macro** for all ViewModels -- NOT `ObservableObject`
- **@MainActor** for all UI-bound classes
- **actor** for I/O-bound services (PlaybackEngine, file I/O)
- **@unchecked Sendable** with `OSAllocatedUnfairLock` for GPU hot-path only
- **PersistentTimeline** -- immutable AVL tree for O(log n) timeline operations
- **TimeMicros** (`Int64` typealias) for all time values -- microsecond precision
- **ServiceContainer** for dependency injection
- **AppCoordinator** (@Observable) for navigation

### Timeline Architecture:
- **PersistentTimeline** is SEQUENTIAL (packed) -- `startTimeOf()` returns cumulative position
- Overlay tracks need ABSOLUTE positioning with `GapClip` spacers
- O(log n) operations via Persistent Order Statistic Tree
- O(1) undo/redo via immutable data structures with pointer swap
- Double-buffered `AVComposition` hot-swap for zero-interruption playback

### Dependencies (SPM via project.yml):
- **swift-collections** (>= 1.1.0) -- `OrderedDictionary`, `Deque`, etc.
- **swift-algorithms** (>= 1.2.0) -- `chunked`, `uniqued`, etc.
- **xcodegen** -- Xcode project generation from `project.yml` (source of truth)

---

## Key Files

| File | Purpose |
|------|---------|
| `project.yml` | xcodegen project definition (source of truth) |
| `LiquidEditor/App/LiquidEditorApp.swift` | App entry point |
| `LiquidEditor/Services/ServiceContainer.swift` | Dependency injection container |
| `LiquidEditor/Services/Composition/PersistentTimeline.swift` | Immutable AVL tree timeline |
| `LiquidEditor/Services/Composition/CompositionManager.swift` | Timeline orchestration |
| `LiquidEditor/Services/Composition/PlaybackEngine.swift` | Playback actor |
| `LiquidEditor/Compositor/MultiTrackCompositor.swift` | GPU rendering pipeline |
| `LiquidEditor/Effects/EffectPipeline.swift` | CIContext with Metal GPU |
| `LiquidEditor/ColorGrading/ColorGradingPipeline.swift` | 12-stage color grading |
| `LiquidEditor/Audio/AudioEffectsEngine.swift` | Real-time audio effects |
| `LiquidEditor/Navigation/AppCoordinator.swift` | @Observable navigation coordinator |
| `LiquidEditor/ViewModels/EditorViewModel.swift` | Main editor state |
| `LiquidEditor/DesignSystem/Modifiers/GlassEffect.swift` | Liquid Glass SwiftUI modifier |
| `LiquidEditor/DesignSystem/Tokens/LiquidColors.swift` | Design system color tokens |
| `LiquidEditor/DesignSystem/Tokens/LiquidSpacing.swift` | Design system spacing tokens |
| `LiquidEditor/DesignSystem/Tokens/LiquidTypography.swift` | Design system typography tokens |
| `LiquidEditor/Metal/Shaders/*.metal` | Metal GPU shaders |

---

## Project Structure

```
LiquidEditor/
  project.yml                    # xcodegen project definition (source of truth)
  LiquidEditor.xcodeproj/        # Generated by xcodegen (DO NOT edit manually)
  LiquidEditor/                  # Source code
    App/                         # App entry point
    Assets.xcassets/             # Asset catalog
    DesignSystem/                # Liquid Glass design tokens and modifiers
    Extensions/                  # Swift extensions
    Metal/Shaders/               # Metal GPU shaders
    Models/                      # Data models (Clips, Audio, Effects, etc.)
    Navigation/                  # AppCoordinator
    Repositories/                # Data access layer
    Services/                    # Business logic (Composition, Playback, etc.)
    Timeline/                    # Timeline UI components
    ViewModels/                  # @Observable ViewModels
    Views/                       # SwiftUI Views
  LiquidEditorTests/             # Swift Testing test suites
  docs/                          # Project documentation
  analysis/                      # Per-file codebase analysis
```

---

## Essential Commands

### Quick Validation (Run After Every Change)
```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodegen generate                                    # Regenerate project after adding/removing files
xcodebuild build -project LiquidEditor.xcodeproj \
  -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO      # MUST succeed
xcodebuild test -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO      # MUST pass 100%
```

### Development
```bash
open LiquidEditor.xcodeproj              # Open in Xcode
xcodegen generate                        # Regenerate after adding/removing files
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

### Testing
```bash
# Run all tests
xcodebuild test -scheme LiquidEditor -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO

# Run specific test suite (filter by class name)
xcodebuild test -scheme LiquidEditor -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' -only-testing:LiquidEditorTests/PersistentTimelineTests CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

### Production Build
```bash
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor -configuration Release -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

### Useful Debug Commands
```bash
xcodegen generate          # Regenerate project file
xcodebuild clean build ... # Clean build if issues occur
xcrun simctl list devices  # List available simulators
```

---

## Documentation Index

Use this table to find what you need. READ these docs before implementing related features.

| What You Need | File Location | When to Read |
|---------------|---------------|--------------|
| **Features & Status** | [docs/FEATURES.md](docs/FEATURES.md) | Starting any feature work |
| **Architecture & Design** | [docs/DESIGN.md](docs/DESIGN.md) | Adding new modules or major changes |
| **Implementation Details** | [docs/APP_LOGIC.md](docs/APP_LOGIC.md) | Understanding existing code flow |
| **Workflow & Process** | [docs/WORKFLOW.md](docs/WORKFLOW.md) | Before starting development |
| **Coding Standards** | [docs/CODING_STANDARDS.md](docs/CODING_STANDARDS.md) | Writing any code (enforce DRY, SOLID) |
| **Testing Protocols** | [docs/TESTING.md](docs/TESTING.md) | Writing tests or fixing bugs |
| **Performance Goals** | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Optimizing or profiling |
| **Codebase Analysis Index** | [analysis/INDEX.md](analysis/INDEX.md) | Before starting work, after completing tasks |
| **Per-File Analysis** | [analysis/analysis_*.md](analysis/) | Understanding specific file quality/issues |

---

## Common Pitfalls

These are hard-won lessons. Read before writing code.

1. **`ShapeStyle` has no `.accent` member** -- use `Color.accentColor` instead
2. **Swift compiler "unable to type-check" errors** -- break complex view bodies into extracted computed properties or `@ViewBuilder` methods
3. **SourceKit cross-file reference errors are misleading** -- always verify with a full `xcodebuild build`; SourceKit indexes lazily
4. **Always run `xcodegen generate` after adding/removing Swift files** -- the `.xcodeproj` is generated and must be regenerated
5. **PersistentTimeline is SEQUENTIAL (packed)** -- `startTimeOf()` returns cumulative position, not absolute time
6. **Overlay tracks need ABSOLUTE positioning** -- use `GapClip` spacers for correct placement
7. **`TextClip` requires `style: TextOverlayStyle` parameter** -- it is not optional
8. **`@Observable` macro generates nonisolated properties** -- incompatible with `Task` storage; design around this
9. **Use `@MainActor` on test structs/methods** that access `@MainActor`-isolated ViewModels
10. **Never use `ObservableObject` or `@Published`** -- always use `@Observable` macro
11. **Metal shaders must match `SharedTypes.h`** -- keep C struct definitions in sync with Swift bridge types
12. **`TimeMicros` is `Int64`** -- do not mix with `CMTime` without explicit conversion via the `CMTime+Codable` extension

---

## Documentation Maintenance Protocol

You are the "institutional memory" of this project. Documentation IS the source of truth.

### Update Rules (Mandatory):
- **Changed app logic?** -- Update `docs/APP_LOGIC.md` with new flow
- **Added/modified feature?** -- Update `docs/FEATURES.md` with status
- **Architectural decision?** -- Update `docs/DESIGN.md` with reasoning
- **Performance optimization?** -- Update `docs/PERFORMANCE.md` with metrics
- **New SPM dependency?** -- Update `project.yml`, `README.md`, and relevant docs
- **New Metal shader?** -- Document in `docs/DESIGN.md` (GPU Pipeline section)

### How to Update:
1. Make code changes
2. Test thoroughly (`xcodegen generate` + `xcodebuild build` + `xcodebuild test`)
3. Update relevant documentation file(s)
4. Verify documentation is accurate and complete
5. Only then is the task DONE

**NEVER** skip documentation. A working feature with outdated docs is a FAILED task.

---

## Pre-Task Checklist

Before starting ANY task, verify:

- [ ] I have read the relevant documentation from the index above
- [ ] I understand which SwiftUI native components to use (no UIKit wrappers)
- [ ] I know which docs file(s) I will need to update afterward
- [ ] My plan uses `@Observable` (not `ObservableObject`) and `@MainActor` where needed
- [ ] I understand Swift 6 strict concurrency implications
- [ ] I will run `xcodegen generate`, `xcodebuild build`, AND `xcodebuild test` when done (ALL THREE are mandatory)

---

## Success Criteria

A task is COMPLETE only when ALL of these are true:

1. Code implements the requirement using **pure SwiftUI** with iOS 26 Liquid Glass design
2. `xcodegen generate` succeeds (if files were added/removed)
3. `xcodebuild build` succeeds with zero errors and zero warnings
4. `xcodebuild test` passes 100% -- all tests green
5. **Swift 6 strict concurrency** -- zero concurrency warnings
6. Existing features still work (no regressions)
7. Performance is within budget (60 FPS, no main thread blocking)
8. Relevant documentation is updated
9. Code follows `docs/CODING_STANDARDS.md` (DRY, SOLID, proper naming)
10. **Codebase analysis updated** for all modified/created files (see below)

**Anything less = incomplete work.**

---

## Codebase Analysis System (MANDATORY)

### Source of Truth

The `analysis/` folder contains comprehensive per-file analysis:
- **`analysis/INDEX.md`** -- Master index with statistics, risk levels, and critical issues
- **`analysis/analysis_*.md`** -- Individual file analysis with UI (16 columns) and Logic (18 columns) tables

**These files are the authoritative source** for code quality, compliance, and technical debt tracking.

### Post-Task Analysis Requirement

**AFTER EVERY TASK COMPLETION**, you MUST:

1. **Identify modified/created files** during the task
2. **Run analysis** on those files using the `codebase-analysis` skill
3. **Update or create** individual `analysis_*.md` files
4. **Update `analysis/INDEX.md`** with:
   - Updated file status and risk levels
   - New/changed issue counts
   - Updated statistics
   - Any new critical issues added to top issues table

### How to Run Post-Task Analysis

```
After completing code changes:

1. List files you modified/created (*.swift)
2. For each file, create/update analysis using the template:
   - File Summary (purpose, category, dependencies)
   - Architecture Compliance (SRP, DRY, Thread Safety, Error Handling, Documentation)
   - Test Coverage
   - Risk Assessment (Red High / Yellow Medium / Green Low)
   - UI Analysis (16-column table) - if applicable
   - Logic Analysis (18-column table) - for all methods
   - Summary of Improvements (Critical/Medium/Low)
3. Update INDEX.md with new data
```

### Analysis File Naming

`analysis_swift_[path_components].md`

Examples:
- `analysis_swift_LiquidEditor_Services_ServiceContainer.md`
- `analysis_swift_LiquidEditor_ViewModels_EditorViewModel.md`
- `analysis_swift_LiquidEditor_Services_Composition_PersistentTimeline.md`

### Quick Reference: Analysis Columns

**UI Analysis (16 columns):** Element, Type, Liquid Glass Compliant, Component Used, Correct Implementation, Dependency Usage, Responsive, Overflow Handling, Safe Area, Accessibility, Haptic Feedback, Hardcoded Values, State Handling, Edge Cases, Improvements, Priority

**Logic Analysis (18 columns):** Method, Purpose, Correct Implementation, Complexity, Dependency Usage, Contract Adherence, Thread Safety, Error Handling, Input Validation, Edge Cases, Memory Management, Performance, Hardcoded Values, Configurable, Test Coverage, Side Effects, Improvements, Priority

### When to Skip Post-Task Analysis

- Documentation-only changes (no code modified)
- Configuration file changes (`project.yml`, etc.) -- unless they add dependencies
- Test file changes -- analyze the test file itself

### Viewing Current Analysis State

Before starting work, check `analysis/INDEX.md` to see:
- Overall codebase health
- Files with critical issues
- Areas needing attention
- Test coverage gaps


<claude-mem-context>
# Recent Activity

<!-- This section is auto-generated by claude-mem. Edit content outside the tags. -->

### Feb 13, 2026

| ID | Time | T | Title | Read |
|----|------|---|-------|------|
| #3811 | 7:04 AM | 🟣 | Batch 5 Library/Settings UI Overhaul Completed | ~662 |
</claude-mem-context>