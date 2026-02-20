# Testing & Validation Protocol

**Last Updated:** 2026-02-13

---

## Test Coverage Summary

**Total Tests:** 1,918 tests (100% passing)
**Test Files:** 45 files in `LiquidEditorTests/`
**Framework:** Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`)

### Test File Overview

| Directory | Files | Coverage |
|-----------|-------|----------|
| `DesignSystem/` | 1 | Design tokens and modifiers |
| `Extensions/` | 1 | CMTime+Codable |
| `Models/Audio/` | 2 | AudioEffect, AudioFade |
| `Models/Clips/` | 3 | ColorClip, GapClip, TimelineClip |
| `Models/ColorGrading/` | 1 | ColorGrading models |
| `Models/Common/` | 1 | ARGBColor |
| `Models/Compositing/` | 1 | Compositing models |
| `Models/Effects/` | 3 | EffectChain, EffectParameter, VideoEffect |
| `Models/Export/` | 1 | Export configuration |
| `Models/Markers/` | 1 | MarkerStore |
| `Models/Masking/` | 1 | Mask models |
| `Models/Media/` | 1 | MediaAsset |
| `Models/Project/` | 1 | Project serialization |
| `Models/Sticker/` | 1 | Sticker models |
| `Models/Text/` | 1 | Text models |
| `Models/Timeline/` | 11 | Timeline, Rational, Node, Track, etc. |
| `Models/Tracking/` | 1 | Tracking data models |
| `Navigation/` | 2 | AppCoordinator, AppRoute |
| `Repositories/` | 6 | All repository types |
| `Services/` | 6+ | ClipManager, AutoReframe, AudioMixer, etc. |

---

## Swift Testing Framework

This project uses the **Swift Testing** framework (not XCTest). Key differences:

### Test Structure

```swift
import Testing
@testable import LiquidEditor

@Suite("PersistentTimeline Tests")
struct PersistentTimelineTests {

    @Test("Insert clip at correct position")
    func insertClip() {
        let timeline = PersistentTimeline()
        let clip = VideoClip(/* ... */)

        let result = timeline.inserting(clip, at: 0)

        #expect(result.count == 1)
        #expect(result.totalDuration == clip.duration)
    }

    @Test("Split preserves total duration")
    func splitPreservesTotalDuration() {
        let timeline = /* ... */
        let originalDuration = timeline.totalDuration

        let result = timeline.splitting(clipId: clipId, at: splitPoint)

        #expect(result.totalDuration == originalDuration)
    }
}
```

### Key Annotations

| Annotation | Purpose |
|-----------|---------|
| `@Suite("Name")` | Groups related tests into a suite |
| `@Test("Description")` | Marks a method as a test case |
| `@Test(.disabled("reason"))` | Skips a test with a reason |
| `@Test(.tags(.model))` | Tags for filtering |
| `#expect(condition)` | Assertion (replaces XCTAssert) |
| `#expect(throws: ErrorType.self)` | Expects a specific error |

### @MainActor in Tests

When testing ViewModels or other @MainActor-isolated types, annotate the test struct:

```swift
@MainActor
@Suite("EditorViewModel Tests")
struct EditorViewModelTests {

    @Test("Play toggles isPlaying")
    func playTogglesState() async {
        let vm = EditorViewModel()
        #expect(vm.isPlaying == false)

        vm.play()
        #expect(vm.isPlaying == true)
    }
}
```

### Async Tests

Tests that call async methods are automatically async:

```swift
@Test("Load project from repository")
func loadProject() async throws {
    let repo = ProjectRepository(baseURL: tempDir)
    let project = Project(name: "Test")

    try await repo.save(project)
    let loaded = try await repo.load(id: project.id)

    #expect(loaded.name == "Test")
}
```

---

## Test Isolation Patterns

### Temporary Directories

Use temporary directories for file-based tests to avoid interference:

```swift
@Suite("ProjectRepository Tests")
struct ProjectRepositoryTests {
    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    @Test func saveAndLoad() async throws {
        let repo = ProjectRepository(baseURL: tempDir)
        // ... test using isolated temp directory
    }
}
```

### Mock Patterns for Protocols

Services are defined behind protocols, enabling mock injection for tests:

```swift
// Protocol
protocol TrackingServiceProtocol {
    func analyzeVideo(at url: URL) async throws -> [TrackingResult]
}

// Production implementation
final class TrackingService: TrackingServiceProtocol {
    func analyzeVideo(at url: URL) async throws -> [TrackingResult] {
        // Real Vision framework implementation
    }
}

// Mock for testing
final class MockTrackingService: TrackingServiceProtocol {
    var mockResults: [TrackingResult] = []
    var analyzeCallCount = 0

    func analyzeVideo(at url: URL) async throws -> [TrackingResult] {
        analyzeCallCount += 1
        return mockResults
    }
}

// Usage in tests
@Suite("AutoReframeEngine Tests")
struct AutoReframeEngineTests {

    @Test func generateKeyframes() async {
        let mockTracking = MockTrackingService()
        mockTracking.mockResults = [/* test data */]

        let engine = AutoReframeEngine(trackingService: mockTracking)
        let keyframes = engine.generateKeyframes(from: mockTracking.mockResults)

        #expect(keyframes.count > 0)
        #expect(mockTracking.analyzeCallCount == 0) // Uses pre-existing results
    }
}
```

### Testing @Observable ViewModels

```swift
@MainActor
@Suite("ProjectLibraryViewModel Tests")
struct ProjectLibraryViewModelTests {

    @Test func loadProjects() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let repo = ProjectRepository(baseURL: tempDir)
        let vm = ProjectLibraryViewModel(repository: repo)

        #expect(vm.projects.isEmpty)

        let project = Project(name: "Test Project")
        try await repo.save(project)
        await vm.loadProjects()

        #expect(vm.projects.count == 1)
        #expect(vm.projects.first?.name == "Test Project")
    }
}
```

---

## Build Validation (MANDATORY After Every Task)

**CRITICAL REQUIREMENT:** After completing ANY task, you **MUST** ensure the build passes completely.

### 1. Build (Zero Errors)

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"

xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

### 2. Run All Tests

```bash
xcodebuild test -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,id=C7A15E20-CAA1-4480-B2BA-392A94328930' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

### 3. Xcodegen (After File Changes)

```bash
# Always run after adding or removing Swift files
xcodegen generate
```

### Handling Failures

- **If Build Fails:** Task is NOT complete. Fix immediately.
- **If Tests Fail:** Task is NOT complete. Fix failing tests.
- **If Warnings Exist:** Task is NOT complete until ALL warnings are fixed. Zero-tolerance policy.

---

## Testing Checklist

### Functional Testing
- [ ] Happy path works correctly
- [ ] Nil/empty inputs handled (guard let, if let)
- [ ] Boundary values tested (min, max, zero)
- [ ] Invalid inputs rejected with clear errors
- [ ] Concurrent operations work safely (actor isolation verified)
- [ ] State transitions are valid
- [ ] UI updates reflect state changes

### Performance Testing
- [ ] No memory leaks (run for 5+ minutes in Instruments)
- [ ] No memory growth over time
- [ ] 60fps maintained during animations and playback
- [ ] Gesture response < 16ms
- [ ] No main thread blocking
- [ ] Battery usage acceptable

### Error Testing
- [ ] File system errors handled (disk full, permission denied)
- [ ] Corrupted project data handled gracefully
- [ ] App backgrounding/foregrounding works
- [ ] Low memory warnings handled (cache eviction)
- [ ] Missing media assets handled (relink flow)

---

## Debugging Workflow

1. **Reproduce** the issue consistently
2. **Isolate** the root cause (use Xcode debugger, Instruments, print statements)
3. **Analyze** related code for similar issues
4. **Fix** the root cause (not just symptoms)
5. **Verify** the fix resolves the issue
6. **Test** for regressions in related functionality
7. **Add tests** to prevent future regressions
8. **Document** the fix in `docs/APP_LOGIC.md`

### Common Debugging Tools

| Tool | Purpose |
|------|---------|
| Xcode Debugger | Breakpoints, variable inspection, LLDB |
| Instruments Time Profiler | CPU hotspots |
| Instruments Allocations | Memory usage patterns |
| Instruments Leaks | Memory leak detection |
| Metal System Trace | GPU shader profiling |
| View Debugger | SwiftUI view hierarchy inspection |
| Console.app | System log messages |

---

## Common Test Pitfalls

### Swift Compiler Errors

- **"Unable to type-check expression in reasonable time"** -- Break complex test bodies into helper methods or extracted computed properties.
- **"Cannot convert value of type..."** -- Ensure @MainActor test structs match the isolation of the types being tested.

### SourceKit Cross-File Errors

- SourceKit may show false positive errors for cross-file references. These resolve in a full `xcodebuild` build. Do not trust SourceKit alone for validation.

### @Observable Macro Issues

- The `@Observable` macro generates `nonisolated` properties that are incompatible with `Task` storage. Avoid storing @Observable objects inside unstructured Tasks.

### PersistentTimeline Gotchas

- `PersistentTimeline` is **sequential** (packed). `startTimeOf()` returns the cumulative position, not an absolute time.
- Overlay tracks use GapClip spacers for absolute positioning.

### TextClip Requirements

- `TextClip` requires a `style: TextOverlayStyle` parameter (it is not optional). Tests must provide it.

---

**Last Updated:** 2026-02-13
