# Coding Standards & Quality Protocol

**CRITICAL:** This app is being developed for **App Store release** and must meet **production-grade quality standards** at all times.

---

## Swift Naming Conventions

- **Types** (structs, classes, enums, protocols): `UpperCamelCase` -- `MediaAsset`, `PlaybackEngine`, `TrackingServiceProtocol`
- **Properties, methods, variables**: `lowerCamelCase` -- `currentTime`, `insertClip()`, `isPlaying`
- **Constants and static properties**: `lowerCamelCase` -- `static let maxFrameCount = 120`
- **Enum cases**: `lowerCamelCase` -- `case playing`, `case paused`
- **Boolean properties**: Use `is`, `has`, `should`, `can` prefixes -- `isPlaying`, `hasUnsavedChanges`, `canUndo`
- **Protocols**: Use noun for capabilities (`Codable`, `Sendable`), `-ing` for actions (`Tracking`), or `-Protocol` suffix for service abstractions (`TrackingServiceProtocol`)
- **Type aliases**: `UpperCamelCase` -- `typealias TimeMicros = Int64`

---

## Swift Language Standards

### @Observable (NOT ObservableObject)

All ViewModels use the `@Observable` macro from the Observation framework:

```swift
// CORRECT: @Observable macro
@Observable
@MainActor
final class EditorViewModel {
    var currentTime: TimeMicros = 0
    var isPlaying = false

    func play() { ... }
}

// WRONG: ObservableObject (legacy Combine pattern)
class EditorViewModel: ObservableObject {
    @Published var currentTime: TimeMicros = 0  // Do NOT use
}
```

### @MainActor Isolation

All UI-bound classes must be `@MainActor`:

```swift
@Observable
@MainActor
final class ProjectLibraryViewModel {
    var projects: [Project] = []

    func loadProjects() async {
        // Safe to update UI properties here
    }
}
```

In tests, annotate test structs/methods that access @MainActor-isolated ViewModels:

```swift
@MainActor
@Suite("ProjectLibraryViewModel Tests")
struct ProjectLibraryViewModelTests {
    @Test func loadProjects() async {
        let vm = ProjectLibraryViewModel()
        // ...
    }
}
```

### Swift 6 Strict Concurrency

- **`Sendable`**: All types crossing concurrency boundaries must conform to `Sendable`
- **`actor`**: Use actors for I/O-bound services (e.g., `PlaybackEngine`)
- **`@unchecked Sendable`**: Only for GPU hot-path services that use `OSAllocatedUnfairLock` for thread safety
- **`nonisolated`**: Use explicitly when a method does not need actor isolation
- **No data races**: Swift 6 strict concurrency checking is enabled. All shared mutable state must be protected.

```swift
// Actor for I/O-bound service
actor PlaybackEngine {
    private var player: AVPlayer?

    func seek(to time: CMTime) {
        await player?.seek(to: time)
    }
}

// @unchecked Sendable with lock for GPU hot path
final class MultiTrackCompositor: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _renderTarget: MTLTexture?

    var renderTarget: MTLTexture? {
        lock.withLock { _renderTarget }
    }
}
```

### Error Handling

- **No force unwraps (`!`)** in production code. Use optional binding (`if let`, `guard let`) or `nil` coalescing (`??`).
- **No `try!`** in production code. Use `do/catch` or `try?` with appropriate fallback.
- **No `fatalError()`** for recoverable conditions. Only use for programmer errors (unreachable code).
- Use `throws` for operations that can fail. Use `Result<T, Error>` when async error handling is needed.

```swift
// CORRECT: Safe unwrapping
guard let asset = mediaAsset else {
    logger.warning("No media asset available")
    return
}

// CORRECT: Error handling with throws
func loadProject(id: UUID) throws -> Project {
    let data = try Data(contentsOf: projectURL)
    return try JSONDecoder().decode(Project.self, from: data)
}

// WRONG: Force unwrap
let asset = mediaAsset!  // NEVER do this
```

### Access Control

- **`private`**: Default for all properties and methods. Only expose what is necessary.
- **`internal`** (default): For types and members used within the module.
- **`public`**: Only for framework/package boundaries (rarely needed in app targets).
- **`private(set)`**: For properties that are read externally but written internally.

```swift
@Observable
@MainActor
final class TimelineViewModel {
    // Public read, private write
    private(set) var clips: [TimelineItem] = []

    // Fully private
    private var undoStack: [PersistentTimeline] = []

    // Internal (accessible within module)
    func insertClip(_ clip: VideoClip, at position: TimeMicros) { ... }
}
```

---

## Implementation Standards

- **Code Clarity:**
  - Every line of code must serve a purpose
  - No "clever" code -- clarity over cleverness
  - Comments explain **why**, not **what**
  - Descriptive variable/function names
  - Functions < 50 lines (extract helpers if longer)
  - Break complex expressions into computed properties to help the Swift compiler

- **Architecture:**
  - Single Responsibility Principle followed
  - DRY (Don't Repeat Yourself) principle applied
  - Thread-safe by design (actors, @MainActor, locks)
  - Keep all existing guidelines in place (never break working code)
  - Protocol-oriented design for service abstractions

- **Constants & Safety:**
  - Constants instead of magic numbers
  - Proper error handling (no silent failures)
  - No force unwraps in production code
  - No `try!` or `fatalError()` for recoverable conditions
  - All switch statements must be exhaustive (or have a well-documented `default`)

---

## Zero-Tolerance Issues

The following issues are **UNACCEPTABLE** in any commit:

- Memory leaks
- Main thread blocking (> 16ms operations)
- Force unwraps without nil checks (`!`)
- Unhandled exceptions or force-try (`try!`)
- Build warnings (must fix all warnings)
- Crashes on edge cases (nil, empty, boundary values)
- Race conditions or data races (Swift 6 strict concurrency must be clean)
- Hardcoded strings that should be localized
- Magic numbers without named constants
- Code duplication (DRY violations)

---

## Mandatory Quality Checklist

After **EVERY** code change, you must complete this validation protocol:

### 1. Code Review & Analysis

**Memory Safety:**
- [ ] No memory leaks (subscriptions properly cancelled)
- [ ] No retain cycles in closures (use `[weak self]` where needed)
- [ ] Proper cleanup in `deinit` methods
- [ ] Large objects released when no longer needed
- [ ] Image/video buffers properly deallocated

**Concurrency & Threading:**
- [ ] No data races (Swift 6 strict concurrency clean)
- [ ] Actors used for shared mutable state
- [ ] @MainActor for all UI-bound classes
- [ ] No deadlocks from improper lock ordering
- [ ] Background work properly isolated in actors or Task groups

**Performance:**
- [ ] No blocking operations on main thread (main thread < 16ms for 60fps)
- [ ] Efficient algorithms (O(n log n) or better for critical paths)
- [ ] LRU caches used where appropriate
- [ ] Image/video decoding done asynchronously
- [ ] Minimal view body recomputations in SwiftUI

**Storage & Persistence:**
- [ ] Files properly saved and closed
- [ ] No excessive disk I/O (batch operations)
- [ ] Proper error handling for file operations
- [ ] Paths validated before file access
- [ ] Temporary files cleaned up

**Logic & Correctness:**
- [ ] Edge cases handled (nil, empty, boundary values)
- [ ] Error states properly handled with user feedback
- [ ] State machines have valid transitions
- [ ] Calculations use correct math
- [ ] Off-by-one errors checked in loops and array access

### 2. Design Validation

**iOS 26 Liquid Glass Design Language:**
- [ ] All UI elements conform to iOS 26 design guidelines
- [ ] Glassmorphic effects properly applied (`.glassEffect()`)
- [ ] Haptic feedback at appropriate interactions
- [ ] Animations smooth and use proper easing curves
- [ ] Typography follows San Francisco font guidelines
- [ ] Color palette consistent with app theme
- [ ] Dark mode support
- [ ] Accessibility labels for VoiceOver

**User Experience:**
- [ ] UI is visually appealing and polished
- [ ] Layout adapts to different screen sizes (iPhone SE to Pro Max)
- [ ] Touch targets minimum 44x44 points
- [ ] Loading states communicate progress
- [ ] Error messages are user-friendly
- [ ] Gestures feel natural and responsive

---

## Completion Criteria

A task is **ONLY** marked as complete when:

1. All items in the Quality Checklist are verified
2. Code builds without errors OR warnings (`xcodebuild build`)
3. All tests pass (`xcodebuild test`)
4. Feature is fully functional
5. Code follows Swift best practices and design patterns
6. Performance is within budget
7. UI matches iOS 26 Liquid Glass design language
8. Documentation is updated

---

**Last Updated:** 2026-02-13
