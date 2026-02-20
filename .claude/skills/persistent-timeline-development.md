---
name: persistent-timeline-development
description: Use when implementing or modifying the persistent order statistic tree timeline, undo/redo system, or clip management operations
---

## Persistent Timeline Development Guide

This skill guides implementation of the Timeline Architecture V2's persistent data structures in pure Swift.

### Reference Document

**Primary Design Doc:** `docs/plans/2026-01-30-timeline-architecture-v2-design.md`

Read Sections 6 (Persistent Timeline Index) and 8 (Clip Type Hierarchy) before any implementation.

### Core Concepts

1. **Immutability:** All tree operations return NEW `PersistentTimeline` values. Never mutate existing nodes. `TimelineNode` is a `final class` with all `let` properties.
2. **Path Copying:** Only nodes on the modification path are copied. Unchanged subtrees are shared via reference counting (class semantics enable structural sharing).
3. **Order Statistic Augmentation:** Each node stores `subtreeDurationMicros` and `subtreeCount` for O(log n) time-based lookups and O(log n) index-based lookups.
4. **AVL Balancing:** Tree stays balanced via `AVLOperations.balance()`. Balance factor must be in [-1, 0, 1].
5. **Value Semantics with Reference Identity:** `PersistentTimeline` is a `struct` backed by a `_Storage` class for stable object identity and lazy ID index caching.

### File Locations

| Component | Location |
|-----------|----------|
| TimelineItemProtocol | `LiquidEditor/Models/Timeline/TimelineNode.swift` |
| TimelineNode | `LiquidEditor/Models/Timeline/TimelineNode.swift` |
| PersistentTimeline | `LiquidEditor/Services/Composition/PersistentTimeline.swift` |
| ClipManager (undo/redo) | `LiquidEditor/Services/Composition/ClipManager.swift` |
| TimeTypes / TimeMicros | `LiquidEditor/Models/Timeline/TimeTypes.swift` |
| Rational (frame rates) | `LiquidEditor/Models/Timeline/Rational.swift` |
| **Clip Types:** | |
| VideoClip | `LiquidEditor/Models/Clips/VideoClip.swift` |
| AudioClip | `LiquidEditor/Models/Clips/AudioClip.swift` |
| ImageClip | `LiquidEditor/Models/Clips/ImageClip.swift` |
| TextClip | `LiquidEditor/Models/Clips/TextClip.swift` |
| StickerClip | `LiquidEditor/Models/Clips/StickerClip.swift` |
| GapClip | `LiquidEditor/Models/Clips/GapClip.swift` |
| ColorClip | `LiquidEditor/Models/Clips/ColorClip.swift` |
| TimelineItem (protocol) | `LiquidEditor/Models/Clips/TimelineItem.swift` |
| TimelineClip (base) | `LiquidEditor/Models/Clips/TimelineClip.swift` |
| **Tests:** | |
| TimelineNodeTests | `LiquidEditorTests/Models/Timeline/TimelineNodeTests.swift` |
| PersistentTimelineTests | `LiquidEditorTests/Services/Composition/PersistentTimelineTests.swift` |

### Type Hierarchy

```
TimelineItemProtocol (protocol: Sendable, Identifiable where ID == String)
  |-- id: String
  |-- durationMicroseconds: Int64
  |-- displayName: String
  |
  +-- TimelineItem (protocol: TimelineItemProtocol, Codable, Equatable, Hashable, Sendable)
        |-- itemType: TimelineItemType
        |-- isMediaClip: Bool
        |-- isGeneratorClip: Bool
        |
        +-- MediaClip (protocol: TimelineItem)
        |     |-- mediaAssetId: String
        |     |-- sourceInMicros: TimeMicros
        |     |-- sourceOutMicros: TimeMicros
        |     |
        |     +-- VideoClip (struct)
        |     +-- AudioClip (struct)
        |     +-- ImageClip (struct)
        |
        +-- GeneratorClip (protocol: TimelineItem)
              |
              +-- GapClip (struct)
              +-- ColorClip (struct)
              +-- TextClip (struct, requires `style: TextOverlayStyle`)
              +-- StickerClip (struct)
```

### TimeMicros Convention

All time values use `TimeMicros` (typealias for `Int64`), stored as microseconds:

```swift
typealias TimeMicros = Int64

// Conversions:
let seconds: Double = timeMicros.toSeconds           // Double(self) / 1_000_000.0
let ms: Double = timeMicros.toMilliseconds           // Double(self) / 1_000.0
let micros = TimeMicrosUtils.fromSeconds(2.5)        // 2_500_000
```

### Implementation Checklist

When modifying timeline operations:

- [ ] Operation returns new `PersistentTimeline`, does not modify `self`
- [ ] All ancestor `subtreeDurationMicros` and `subtreeCount` values are recalculated
- [ ] AVL balance is maintained (call `AVLOperations.balance()` on every modified path)
- [ ] Undo/redo pushes old timeline before mutation (in ClipManager)
- [ ] Unit test covers edge cases (empty tree, single node, boundary conditions)
- [ ] Test uses Swift Testing framework (`@Suite`, `@Test`, `#expect`)

### Key Invariants

```swift
// These must ALWAYS hold for any TimelineNode:

// Subtree duration = left duration + self + right duration
#expect(node.subtreeDurationMicros ==
    (node.left?.subtreeDurationMicros ?? 0) +
    node.item.durationMicroseconds +
    (node.right?.subtreeDurationMicros ?? 0))

// AVL balance factor in [-1, 0, 1]
let balance = (node.right?.height ?? 0) - (node.left?.height ?? 0)
#expect(abs(balance) <= 1)

// Height is correct
#expect(node.height ==
    1 + max(node.left?.height ?? 0, node.right?.height ?? 0))

// Subtree count is correct
#expect(node.subtreeCount ==
    (node.left?.subtreeCount ?? 0) + 1 + (node.right?.subtreeCount ?? 0))
```

### Common Patterns

#### Adding a New Operation to PersistentTimeline

```swift
// 1. Define on PersistentTimeline (returns new timeline, never mutates self)
func myOperation(_ params: SomeParams) -> PersistentTimeline {
    guard let root else { return self } // Handle empty
    return PersistentTimeline(Self._myOperationRecursive(root, params))
}

private static func _myOperationRecursive(
    _ node: TimelineNode,
    _ params: SomeParams
) -> TimelineNode {
    // ... recursive logic with path copying ...
    // Use node.withChildren(left:right:) for path copying
    // Use node.withItem(_:) to replace the item at a node
    return AVLOperations.balance(newNode)  // ALWAYS balance at end
}

// 2. Wrap in ClipManager (handles undo stack)
func myOperation(_ params: SomeParams) {
    pushUndo()
    currentTimeline = currentTimeline.myOperation(params)
}
```

#### Using withChildren for Path Copying

```swift
// TimelineNode provides copy-on-write helpers:
let newNode = node.withChildren(left: newLeft)           // Replace left child
let newNode = node.withChildren(right: newRight)         // Replace right child
let newNode = node.withChildren(left: newLeft, right: newRight)  // Replace both
let newNode = node.withChildren(clearLeft: true)         // Set left to nil
let newNode = node.withItem(newItem)                     // Replace item (updates duration)
```

#### Lazy ID Index

```swift
// getById uses a lazily-built dictionary cached in _Storage:
// - First call: O(n) tree traversal to build index
// - Subsequent calls: O(1) dictionary lookup
// - New PersistentTimeline instances (after mutation) rebuild on demand
let clip = timeline.getById("clip-id")     // O(1) after first access
let exists = timeline.containsId("clip-id") // O(1) after first access
```

#### In-Order Iteration

```swift
// Lazy iteration via stack-based iterator (O(h) memory, O(log n) for balanced trees):
for item in timeline.items {
    print(item.displayName)
}

// Materialized list (O(n) time and space):
let allItems = timeline.toList()
```

#### Building a Timeline

```swift
// From sorted list (O(n), efficient for initial load):
let timeline = PersistentTimeline.fromSortedList(items)

// From unsorted list (O(n log n), via repeated append):
let timeline = PersistentTimeline.fromList(items)

// Incremental building:
var timeline = PersistentTimeline.empty
timeline = timeline.append(videoClip)
timeline = timeline.append(gapClip)
timeline = timeline.insertAt(1_000_000, audioClip)
```

### Testing Timeline Operations

```swift
import Testing

@Suite("PersistentTimeline Operations")
struct PersistentTimelineOperationTests {

    @Test("Operation preserves tree invariants")
    func operationPreservesInvariants() {
        var timeline = PersistentTimeline.empty
        for i in 0..<100 {
            let clip = GapClip(
                id: "gap-\(i)",
                durationMicroseconds: 1_000_000
            )
            timeline = timeline.append(clip)
        }

        timeline = timeline.myOperation(params)

        // Verify invariants
        verifyTreeInvariants(timeline.root)
        #expect(timeline.count == expectedCount)
        #expect(timeline.totalDurationMicros == expectedDuration)
    }

    private func verifyTreeInvariants(_ node: TimelineNode?) {
        guard let node else { return }

        // Check subtree duration
        let expectedDuration =
            (node.left?.subtreeDurationMicros ?? 0) +
            node.item.durationMicroseconds +
            (node.right?.subtreeDurationMicros ?? 0)
        #expect(node.subtreeDurationMicros == expectedDuration)

        // Check AVL balance
        let balance = (node.right?.height ?? 0) - (node.left?.height ?? 0)
        #expect(abs(balance) <= 1)

        // Check subtree count
        let expectedCount =
            (node.left?.subtreeCount ?? 0) + 1 + (node.right?.subtreeCount ?? 0)
        #expect(node.subtreeCount == expectedCount)

        // Recurse
        verifyTreeInvariants(node.left)
        verifyTreeInvariants(node.right)
    }
}
```

### Sequential (Packed) Timeline Positioning

**CRITICAL:** PersistentTimeline is a SEQUENTIAL (packed) timeline. Items are stored in order and `startTimeOf()` returns the cumulative position:

```swift
// If timeline has [ClipA(2s), ClipB(3s), ClipC(1s)]:
timeline.startTimeOf("clipA") // -> 0
timeline.startTimeOf("clipB") // -> 2_000_000  (after ClipA)
timeline.startTimeOf("clipC") // -> 5_000_000  (after ClipA + ClipB)
timeline.totalDurationMicros  // -> 6_000_000

// Overlay tracks need ABSOLUTE positioning with GapClip spacers:
// [GapClip(2s), TextClip(1s)]  -- text starts at 2 seconds
```

### Edge Cases to Test

1. Empty timeline (`root == nil`)
2. Single item timeline
3. Operation at timeline start (time = 0)
4. Operation at timeline end (time = totalDurationMicros)
5. Operation at exact clip boundary
6. 1000+ items (performance, verify O(log n))
7. Undo/redo cycle preserves data exactly (pointer swap)
8. Mixed clip types on same timeline (VideoClip, GapClip, TextClip, etc.)
9. Zero-duration items (should not normally exist, but handle gracefully)
10. `TextClip` always requires `style: TextOverlayStyle` parameter

### Performance Targets

| Operation | Target | Complexity |
|-----------|--------|------------|
| `itemAtTime(t)` | < 100us | O(log n) tree traversal |
| `insertAt(t, item)` | < 1ms | O(log n) path copy + balance |
| `remove(id)` | < 1ms | O(log n) path copy + balance |
| `updateItem(id, new)` | < 1ms | O(log n) path copy |
| `undo()` / `redo()` | < 10us | O(1) pointer swap |
| `getById(id)` | < 1us (after first) | O(1) dictionary lookup |
| `toList()` | O(n) | Linear in-order traversal |
| `fromSortedList()` | O(n) | Balanced tree construction |

### Common Mistakes

1. **Mutating nodes:** `TimelineNode` is a `final class` with all `let` properties. Never try to mutate. Use `node.withChildren(left:)` or `node.withItem(_:)` for path copying.
2. **Forgetting balance:** Every insert/remove must call `AVLOperations.balance()` on the modification path.
3. **Wrong subtree duration:** Forgetting to update `subtreeDurationMicros` after child changes. The `withChildren` helper recalculates automatically.
4. **Linear search:** Using `toList().firstIndex(where:)` instead of tree traversal. Use `itemAtTime()` for time-based or `getById()` for ID-based lookups.
5. **Blocking UI:** Tree operations are O(log n) microseconds -- running on main thread is fine.
6. **Forgetting `@unchecked Sendable`:** `TimelineNode` is `@unchecked Sendable` because it is immutable (all `let`). New types that wrap nodes should follow the same pattern.
7. **Double traversal:** The `remove` and `updateItem` methods avoid pre-checking `containsId` to prevent double traversal. Follow this pattern.
8. **TextClip without style:** `TextClip` requires a `style: TextOverlayStyle` parameter. Omitting it causes a compile error.
9. **Overlay absolute positioning:** Overlay tracks use GapClip spacers for absolute positioning. Do not assume items start at time 0 in overlay tracks.
10. **Confusing `_Storage` identity with value equality:** Two `PersistentTimeline` values with the same tree content but different `_Storage` instances are logically equal but have different object identities for caching purposes.

### Verification Commands

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodegen generate
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
    -destination 'generic/platform=iOS' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme LiquidEditor \
    -destination 'platform=iOS Simulator,id=C7A15E20-CAA1-4480-B2BA-392A94328930' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```
