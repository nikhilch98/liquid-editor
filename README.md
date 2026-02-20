# Liquid Editor

A professional video editor built as a pure Swift/SwiftUI application targeting iOS 26 with the Liquid Glass design system.

## Architecture

- **Pattern:** MVVM + Coordinator + Repository
- **Language:** Swift 6 with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- **UI Framework:** SwiftUI with iOS 26 Liquid Glass design tokens
- **Concurrency:** `@Observable` ViewModels, `@MainActor` UI isolation, `actor` for I/O services
- **Timeline:** Persistent Order Statistic Tree (immutable AVL) with O(log n) operations and O(1) undo/redo
- **GPU:** Metal shaders for compositing, color grading, and effects via `CIContext`
- **Time Representation:** `TimeMicros` (`Int64` typealias) for microsecond precision

## Dependencies

Managed via Swift Package Manager (declared in `project.yml`):

| Package | Version | Purpose |
|---------|---------|---------|
| [swift-collections](https://github.com/apple/swift-collections) | >= 1.1.0 | `OrderedDictionary`, `Deque`, and other data structures |
| [swift-algorithms](https://github.com/apple/swift-algorithms) | >= 1.2.0 | `chunked`, `uniqued`, and other sequence algorithms |

## Prerequisites

- **Xcode 16.0+** with iOS 26 SDK
- **[xcodegen](https://github.com/yonaskolb/XcodeGen):** `brew install xcodegen`
- **macOS 15+** (Sequoia or later)

## Build

The Xcode project file is generated from `project.yml` using xcodegen. Do NOT edit `LiquidEditor.xcodeproj` directly.

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"

# Generate the Xcode project (required after adding/removing files)
xcodegen generate

# Build for iOS (no code signing)
xcodebuild build \
  -project LiquidEditor.xcodeproj \
  -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

## Test

Tests use the Swift Testing framework (`@Suite`, `@Test`, `#expect`).

```bash
# Run all tests on simulator
xcodebuild test \
  -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO

# Run a specific test suite
xcodebuild test \
  -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' \
  -only-testing:LiquidEditorTests/PersistentTimelineTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

## Project Structure

```
LiquidEditor/
  project.yml                 # xcodegen project definition (source of truth)
  CLAUDE.md                   # Claude Code instructions
  LiquidEditor/               # Application source
    App/                      # App entry point
    Assets.xcassets/          # Asset catalog
    DesignSystem/             # Liquid Glass tokens and modifiers
    Extensions/               # Swift extensions
    Metal/Shaders/            # Metal GPU shaders (.metal, SharedTypes.h)
    Models/                   # Data models
    Navigation/               # AppCoordinator
    Repositories/             # Data access layer
    Services/                 # Business logic and composition
    Timeline/                 # Timeline UI components
    ViewModels/               # @Observable ViewModels
    Views/                    # SwiftUI Views
  LiquidEditorTests/          # Swift Testing test suites
  docs/                       # Project documentation
```

## Key Design Decisions

- **@Observable over ObservableObject:** All ViewModels use the `@Observable` macro for cleaner reactivity without `@Published` boilerplate.
- **Strict concurrency:** Swift 6 complete concurrency checking ensures zero data races at compile time.
- **Immutable timeline:** `PersistentTimeline` uses structural sharing (path copying) for efficient undo/redo.
- **Metal shaders:** Custom `.metal` files for compositing, color grading, chroma key, and effects processing.
- **xcodegen:** `project.yml` is the single source of truth for project configuration. The `.xcodeproj` is generated and gitignored.
