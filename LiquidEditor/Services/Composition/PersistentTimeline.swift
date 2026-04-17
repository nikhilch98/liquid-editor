import Foundation
import os

// MARK: - PersistentTimeline

/// Persistent timeline data structure.
///
/// An immutable order statistic tree where each node stores the total duration
/// of its subtree, enabling O(log n) time-based queries.
///
/// All mutation operations return new `PersistentTimeline` values, leaving the
/// original unchanged. This enables O(1) undo/redo via pointer swap.
///
/// Uses value semantics (struct), backed by a reference-counted `_Storage` class
/// for identity-based caching. The underlying `TimelineNode` tree uses structural
/// sharing — unchanged subtrees are shared between versions.
struct PersistentTimeline: Sendable, CustomStringConvertible, Equatable {

    // MARK: - Equatable

    /// Two timelines are considered equal when they share the same backing
    /// storage (i.e. no mutation has happened since the other was derived).
    /// Because `PersistentTimeline` uses path-copying, any mutation returns a
    /// fresh `_Storage` instance, so reference equality is both O(1) and a
    /// strict subset of structural equality — safe to use as the change
    /// trigger for SwiftUI's `.onChange`. Two independently-constructed
    /// timelines with identical content will compare unequal, which is fine
    /// for observation (it simply re-fires).
    static func == (lhs: PersistentTimeline, rhs: PersistentTimeline) -> Bool {
        lhs._storage === rhs._storage
    }

    // MARK: - Storage (Reference Identity for Cache)

    /// Internal storage class that gives each PersistentTimeline value a stable
    /// object identity and hosts the lazily-built ID index cache.
    ///
    /// All tree properties are `let` — the only mutable state is the write-once
    /// `_idIndex` cache, protected by `os_unfair_lock` for thread safety.
    /// `TimelineNode` is `@unchecked Sendable` (immutable reference type with
    /// structural sharing), so this is safe.
    private final class _Storage: @unchecked Sendable {
        let root: TimelineNode?

        /// Lazily-built ID index. Written at most once, then read-only.
        /// Protected by `_lock` for thread-safe initialization.
        private var _idIndex: [String: any TimelineItemProtocol]?
        private let _lock = OSAllocatedUnfairLock()

        init(_ root: TimelineNode?) {
            self.root = root
        }

        /// Returns the lazily-built ID index, building it on first access.
        func getIdIndex() -> [String: any TimelineItemProtocol] {
            _lock.withLock {
                if let existing = _idIndex {
                    return existing
                }
                var index = [String: any TimelineItemProtocol]()
                Self._collectItems(root, &index)
                _idIndex = index
                return index
            }
        }

        private static func _collectItems(
            _ node: TimelineNode?,
            _ index: inout [String: any TimelineItemProtocol]
        ) {
            guard let node else { return }
            _collectItems(node.left, &index)
            index[node.item.id] = node.item
            _collectItems(node.right, &index)
        }
    }

    /// Boxed storage — provides object identity for caching and structural sharing.
    private let _storage: _Storage

    /// Root of the tree (nil if empty).
    var root: TimelineNode? { _storage.root }

    // MARK: - Initializers

    /// Creates a persistent timeline with an optional root node.
    init(_ root: TimelineNode? = nil) {
        _storage = _Storage(root)
    }

    /// Empty timeline.
    static let empty = PersistentTimeline(nil)

    // MARK: - Properties

    /// Total duration of timeline in microseconds.
    var totalDurationMicros: TimeMicros {
        root?.subtreeDurationMicros ?? 0
    }

    /// Total duration as `TimeInterval` (seconds).
    var totalDurationSeconds: TimeInterval {
        Double(totalDurationMicros) / 1_000_000.0
    }

    /// Number of items in the timeline.
    var count: Int {
        root?.subtreeCount ?? 0
    }

    /// Whether the timeline is empty.
    var isEmpty: Bool {
        root == nil
    }

    /// Whether the timeline has items.
    var isNotEmpty: Bool {
        root != nil
    }

    // MARK: - Queries (O(log n))

    /// Find item at a specific time position.
    ///
    /// - Parameter timeMicros: Absolute time position in microseconds.
    /// - Returns: Tuple of `(item, offsetWithinItem)` or `nil` if time is out of range.
    ///   The offset is the time relative to the item's start.
    func itemAtTime(_ timeMicros: TimeMicros) -> (any TimelineItemProtocol, TimeMicros)? {
        guard let root, timeMicros >= 0, timeMicros < totalDurationMicros else {
            return nil
        }
        return Self._itemAtTime(root, timeMicros)
    }

    private static func _itemAtTime(
        _ node: TimelineNode,
        _ timeMicros: TimeMicros
    ) -> (any TimelineItemProtocol, TimeMicros)? {
        let leftDuration = node.leftDuration

        if timeMicros < leftDuration {
            // Target is in left subtree
            return _itemAtTime(node.left!, timeMicros)
        }

        let timeAfterLeft = timeMicros - leftDuration

        if timeAfterLeft < node.itemDurationMicros {
            // Target is at this node
            return (node.item, timeAfterLeft)
        }

        // Target is in right subtree
        let timeInRight = timeAfterLeft - node.itemDurationMicros
        return _itemAtTime(node.right!, timeInRight)
    }

    /// Get the timeline start time of a specific item by ID.
    ///
    /// - Parameter itemId: The ID of the item to find.
    /// - Returns: Start time in microseconds, or `nil` if item not found.
    func startTimeOf(_ itemId: String) -> TimeMicros? {
        guard let root else { return nil }
        return Self._startTimeOf(root, itemId, 0)
    }

    private static func _startTimeOf(
        _ node: TimelineNode,
        _ itemId: String,
        _ accumulated: TimeMicros
    ) -> TimeMicros? {
        // Try left subtree first (in-order traversal)
        if let left = node.left {
            if let found = _startTimeOf(left, itemId, accumulated) {
                return found
            }
        }

        let nodeStart = accumulated + node.leftDuration

        // Check this node
        if node.item.id == itemId {
            return nodeStart
        }

        // Try right subtree
        if let right = node.right {
            let rightAccum = nodeStart + node.itemDurationMicros
            return _startTimeOf(right, itemId, rightAccum)
        }

        return nil
    }

    /// Get item by ID (O(1) via lazily-built ID index).
    ///
    /// On first call, builds a dictionary from item IDs to items by traversing
    /// the tree once (O(n)). Subsequent calls are O(1) dictionary lookups.
    /// The index is cached per-instance inside `_Storage` so it does not
    /// break the immutable/value-type contract.
    func getById(_ itemId: String) -> (any TimelineItemProtocol)? {
        guard root != nil else { return nil }
        return _storage.getIdIndex()[itemId]
    }

    /// Check if an item with this ID exists (O(1) via lazily-built ID index).
    func containsId(_ itemId: String) -> Bool {
        guard root != nil else { return false }
        return _storage.getIdIndex()[itemId] != nil
    }

    /// Get item by index (0-based, in timeline order).
    ///
    /// - Parameter index: Zero-based position in timeline order.
    /// - Returns: The item at that position, or `nil` if out of range.
    func itemAtIndex(_ index: Int) -> (any TimelineItemProtocol)? {
        guard let root, index >= 0, index < count else { return nil }
        return Self._itemAtIndex(root, index)
    }

    private static func _itemAtIndex(
        _ node: TimelineNode,
        _ index: Int
    ) -> (any TimelineItemProtocol)? {
        let leftCount = node.leftCount

        if index < leftCount {
            return _itemAtIndex(node.left!, index)
        }

        if index == leftCount {
            return node.item
        }

        return _itemAtIndex(node.right!, index - leftCount - 1)
    }

    /// Get all items in timeline order (for serialization).
    ///
    /// - Returns: Array of items in timeline order.
    func toList() -> [any TimelineItemProtocol] {
        var result = [any TimelineItemProtocol]()
        result.reserveCapacity(count)
        Self._inOrder(root, &result)
        return result
    }

    private static func _inOrder(
        _ node: TimelineNode?,
        _ result: inout [any TimelineItemProtocol]
    ) {
        guard let node else { return }
        _inOrder(node.left, &result)
        result.append(node.item)
        _inOrder(node.right, &result)
    }

    /// All items as a lazy sequence (in-order traversal).
    ///
    /// Uses an iterative stack-based traversal for efficiency.
    /// Memory usage is O(h) where h is the tree height (O(log n) for balanced trees).
    var items: AnySequence<any TimelineItemProtocol> {
        guard let root else { return AnySequence([]) }
        return AnySequence(InOrderIteratorSequence(root: root))
    }

    // MARK: - Mutations (Return new tree, O(log n))

    /// Insert item at a specific time position.
    ///
    /// - Parameters:
    ///   - timeMicros: Time position to insert at (microseconds).
    ///   - item: The item to insert.
    /// - Returns: New timeline with the item inserted.
    func insertAt(_ timeMicros: TimeMicros, _ item: any TimelineItemProtocol) -> PersistentTimeline {
        guard let root else {
            return PersistentTimeline(TimelineNode.leaf(item))
        }
        return PersistentTimeline(Self._insertAt(root, timeMicros, item))
    }

    private static func _insertAt(
        _ node: TimelineNode,
        _ timeMicros: TimeMicros,
        _ item: any TimelineItemProtocol
    ) -> TimelineNode {
        let leftDuration = node.leftDuration
        let newNode: TimelineNode

        if timeMicros <= leftDuration {
            // Insert in left subtree
            let newLeft: TimelineNode
            if let left = node.left {
                newLeft = _insertAt(left, timeMicros, item)
            } else {
                newLeft = TimelineNode.leaf(item)
            }
            newNode = node.withChildren(left: newLeft)
        } else {
            // Insert in right subtree
            let timeInRight = timeMicros - leftDuration - node.itemDurationMicros
            let clampedTime = max(timeInRight, 0)
            let newRight: TimelineNode
            if let right = node.right {
                newRight = _insertAt(right, clampedTime, item)
            } else {
                newRight = TimelineNode.leaf(item)
            }
            newNode = node.withChildren(right: newRight)
        }

        return AVLOperations.balance(newNode)
    }

    /// Append item at the end of timeline.
    ///
    /// - Parameter item: The item to append.
    /// - Returns: New timeline with the item appended.
    func append(_ item: any TimelineItemProtocol) -> PersistentTimeline {
        insertAt(totalDurationMicros, item)
    }

    /// Prepend item at the start of timeline.
    ///
    /// - Parameter item: The item to prepend.
    /// - Returns: New timeline with the item prepended.
    func prepend(_ item: any TimelineItemProtocol) -> PersistentTimeline {
        insertAt(0, item)
    }

    /// Remove item by ID.
    ///
    /// - Parameter itemId: The ID of the item to remove.
    /// - Returns: New timeline without the item (or same timeline if not found).
    func remove(_ itemId: String) -> PersistentTimeline {
        guard let root else { return self }
        let newRoot = Self._remove(root, itemId)
        return PersistentTimeline(newRoot)
    }

    private static func _remove(
        _ node: TimelineNode,
        _ itemId: String
    ) -> TimelineNode? {
        if node.item.id == itemId {
            // Found the node to remove
            if node.left == nil { return node.right }
            if node.right == nil { return node.left }

            // Has two children — replace with in-order successor
            let (successor, newRight) = AVLOperations.removeMin(node.right!)
            let newNode = successor.withChildren(
                left: node.left,
                right: newRight,
                clearRight: newRight == nil
            )
            return AVLOperations.balance(newNode)
        }

        // Search in subtrees without pre-checking contains (avoids double traversal).
        // Try left subtree first; if the count didn't change, the item wasn't there.
        if let left = node.left {
            let newLeft = _remove(left, itemId)
            let leftChanged = newLeft == nil ||
                newLeft!.subtreeCount != left.subtreeCount
            if leftChanged {
                let newNode = node.withChildren(
                    left: newLeft,
                    clearLeft: newLeft == nil
                )
                return AVLOperations.balance(newNode)
            }
        }

        if let right = node.right {
            let newRight = _remove(right, itemId)
            let rightChanged = newRight == nil ||
                newRight!.subtreeCount != right.subtreeCount
            if rightChanged {
                let newNode = node.withChildren(
                    right: newRight,
                    clearRight: newRight == nil
                )
                return AVLOperations.balance(newNode)
            }
        }

        return node // Item not found
    }

    /// Update an item (e.g., after trim or keyframe change).
    ///
    /// - Parameters:
    ///   - itemId: The ID of the item to update.
    ///   - newItem: The replacement item.
    /// - Returns: New timeline with the updated item.
    func updateItem(
        _ itemId: String,
        _ newItem: any TimelineItemProtocol
    ) -> PersistentTimeline {
        guard let root else { return self }
        return PersistentTimeline(Self._updateItem(root, itemId, newItem))
    }

    private static func _updateItem(
        _ node: TimelineNode,
        _ itemId: String,
        _ newItem: any TimelineItemProtocol
    ) -> TimelineNode {
        if node.item.id == itemId {
            return node.withItem(newItem)
        }

        // Try left subtree first without pre-checking contains (avoids double traversal).
        // Compare identity to detect if an update occurred.
        if let left = node.left {
            let updatedLeft = _updateItem(left, itemId, newItem)
            if updatedLeft !== left {
                return node.withChildren(left: updatedLeft)
            }
        }

        if let right = node.right {
            let updatedRight = _updateItem(right, itemId, newItem)
            if updatedRight !== right {
                return node.withChildren(right: updatedRight)
            }
        }

        return node
    }

    /// Replace item at index.
    ///
    /// - Parameters:
    ///   - index: Zero-based position in timeline order.
    ///   - newItem: The replacement item.
    /// - Returns: New timeline with the replaced item.
    func replaceAt(_ index: Int, _ newItem: any TimelineItemProtocol) -> PersistentTimeline {
        guard let oldItem = itemAtIndex(index) else { return self }
        return updateItem(oldItem.id, newItem)
    }

    // MARK: - Bulk Operations

    /// Create timeline from a list of items (via repeated append, O(n log n)).
    ///
    /// - Parameter items: Items in timeline order.
    /// - Returns: A new timeline containing all items.
    static func fromList(_ items: [any TimelineItemProtocol]) -> PersistentTimeline {
        var timeline = PersistentTimeline.empty
        for item in items {
            timeline = timeline.append(item)
        }
        return timeline
    }

    /// Create a balanced tree from a sorted list (O(n)).
    ///
    /// More efficient than repeated insertions for initial load.
    ///
    /// - Parameter items: Items in timeline order.
    /// - Returns: A new timeline with a balanced tree.
    static func fromSortedList(_ items: [any TimelineItemProtocol]) -> PersistentTimeline {
        if items.isEmpty { return .empty }
        return PersistentTimeline(_buildBalanced(items, 0, items.count - 1))
    }

    private static func _buildBalanced(
        _ items: [any TimelineItemProtocol],
        _ start: Int,
        _ end: Int
    ) -> TimelineNode {
        precondition(start <= end, "Invalid range: start (\(start)) > end (\(end))")

        if start == end {
            return TimelineNode.leaf(items[start])
        }

        let mid = (start + end) / 2
        let item = items[mid]

        var left: TimelineNode?
        var right: TimelineNode?

        if start <= mid - 1 {
            left = _buildBalanced(items, start, mid - 1)
        }
        if mid + 1 <= end {
            right = _buildBalanced(items, mid + 1, end)
        }

        let leftH = left?.height ?? 0
        let rightH = right?.height ?? 0

        return TimelineNode(
            id: item.id,
            item: item,
            left: left,
            right: right,
            height: 1 + max(leftH, rightH),
            subtreeDurationMicros: (left?.subtreeDurationMicros ?? 0)
                + item.durationMicroseconds
                + (right?.subtreeDurationMicros ?? 0),
            subtreeCount: (left?.subtreeCount ?? 0) + 1 + (right?.subtreeCount ?? 0)
        )
    }

    // MARK: - CustomStringConvertible

    var description: String {
        let ms = totalDurationMicros / 1_000
        return "PersistentTimeline(\(count) items, \(ms)ms)"
    }

    // MARK: - Debug / Invariant Checks

    /// Recursively verifies the AVL invariant across every node in the tree.
    ///
    /// For each non-nil node, this asserts:
    /// 1. Balance factor: `|height(left) - height(right)| <= 1`
    /// 2. Height consistency: `node.height == 1 + max(height(left), height(right))`
    /// 3. Leaf height == 1
    ///
    /// Intended for test/debug use only.
    ///
    /// - Returns: `true` if the invariant holds at every node, `false` otherwise.
    func _checkBalanceInvariant() -> Bool {
        Self._checkBalanceInvariant(root) >= 0
    }

    /// Returns the computed height of the subtree if the invariant holds everywhere,
    /// or `-1` if any node violates the AVL invariant or stored height.
    private static func _checkBalanceInvariant(_ node: TimelineNode?) -> Int {
        guard let node else { return 0 }

        let leftHeight = _checkBalanceInvariant(node.left)
        if leftHeight < 0 { return -1 }

        let rightHeight = _checkBalanceInvariant(node.right)
        if rightHeight < 0 { return -1 }

        if abs(leftHeight - rightHeight) > 1 { return -1 }

        let expectedHeight = 1 + max(leftHeight, rightHeight)
        if node.height != expectedHeight { return -1 }

        return expectedHeight
    }
}

// MARK: - In-Order Iterator

/// Stack-based in-order iterator for `TimelineNode` trees.
///
/// Provides lazy iteration without requiring Swift `async` or generator syntax.
/// Memory usage is O(h) where h is the tree height (O(log n) for balanced trees).
private struct InOrderIteratorSequence: Sequence {
    let root: TimelineNode

    func makeIterator() -> InOrderIterator {
        InOrderIterator(root: root)
    }
}

private struct InOrderIterator: IteratorProtocol {
    private var stack: [TimelineNode]

    init(root: TimelineNode) {
        stack = []
        // Push leftmost spine
        var current: TimelineNode? = root
        while let node = current {
            stack.append(node)
            current = node.left
        }
    }

    mutating func next() -> (any TimelineItemProtocol)? {
        guard !stack.isEmpty else { return nil }

        let node = stack.removeLast()
        let item = node.item

        // Push leftmost spine of right subtree
        var current = node.right
        while let next = current {
            stack.append(next)
            current = next.left
        }

        return item
    }
}
