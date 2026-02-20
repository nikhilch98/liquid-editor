import Foundation

/// Protocol for all items that can be placed on a timeline.
protocol TimelineItemProtocol: Sendable, Identifiable where ID == String {
    var id: String { get }
    var durationMicroseconds: Int64 { get }
    var displayName: String { get }
}

/// Immutable node in the persistent order statistic tree.
///
/// This node is never mutated after creation (all properties are `let`).
/// All "modifications" create new nodes, enabling O(1) undo via pointer swap.
///
/// FINAL CLASS — not struct. Reference-counted node sharing requires class semantics
/// for structural sharing. All properties are `let` for thread safety + Sendable.
final class TimelineNode: @unchecked Sendable {
    /// Unique node ID (same as item ID).
    let id: String

    /// The timeline item stored at this node.
    let item: any TimelineItemProtocol

    /// Left child (items before this one in timeline order).
    let left: TimelineNode?

    /// Right child (items after this one in timeline order).
    let right: TimelineNode?

    /// Height for AVL balancing.
    let height: Int

    /// Total duration of this subtree (self + left + right) in microseconds.
    let subtreeDurationMicros: Int64

    /// Number of items in this subtree (self + left + right).
    let subtreeCount: Int

    /// Creates a timeline node.
    init(
        id: String,
        item: any TimelineItemProtocol,
        left: TimelineNode?,
        right: TimelineNode?,
        height: Int,
        subtreeDurationMicros: Int64,
        subtreeCount: Int
    ) {
        self.id = id
        self.item = item
        self.left = left
        self.right = right
        self.height = height
        self.subtreeDurationMicros = subtreeDurationMicros
        self.subtreeCount = subtreeCount
    }

    /// Duration of just this item in microseconds.
    var itemDurationMicros: Int64 { item.durationMicroseconds }

    /// Create a leaf node (no children).
    static func leaf(_ item: any TimelineItemProtocol) -> TimelineNode {
        TimelineNode(
            id: item.id,
            item: item,
            left: nil,
            right: nil,
            height: 1,
            subtreeDurationMicros: item.durationMicroseconds,
            subtreeCount: 1
        )
    }

    /// Create updated node with new children (for persistent updates).
    ///
    /// This is the core operation for path copying — we create a new node
    /// with updated children while preserving the item.
    func withChildren(
        left: TimelineNode? = nil,
        right: TimelineNode? = nil,
        clearLeft: Bool = false,
        clearRight: Bool = false
    ) -> TimelineNode {
        let newLeft = clearLeft ? nil : (left ?? self.left)
        let newRight = clearRight ? nil : (right ?? self.right)

        let leftDur = newLeft?.subtreeDurationMicros ?? 0
        let rightDur = newRight?.subtreeDurationMicros ?? 0
        let leftCnt = newLeft?.subtreeCount ?? 0
        let rightCnt = newRight?.subtreeCount ?? 0
        let leftH = newLeft?.height ?? 0
        let rightH = newRight?.height ?? 0

        return TimelineNode(
            id: id,
            item: item,
            left: newLeft,
            right: newRight,
            height: 1 + max(leftH, rightH),
            subtreeDurationMicros: leftDur + itemDurationMicros + rightDur,
            subtreeCount: leftCnt + 1 + rightCnt
        )
    }

    /// Create node with updated item.
    func withItem(_ newItem: any TimelineItemProtocol) -> TimelineNode {
        let leftDur = left?.subtreeDurationMicros ?? 0
        let rightDur = right?.subtreeDurationMicros ?? 0

        return TimelineNode(
            id: newItem.id,
            item: newItem,
            left: left,
            right: right,
            height: height,
            subtreeDurationMicros: leftDur + newItem.durationMicroseconds + rightDur,
            subtreeCount: subtreeCount
        )
    }

    /// Balance factor for AVL (left height - right height).
    var balanceFactor: Int { (left?.height ?? 0) - (right?.height ?? 0) }

    /// Whether this subtree is balanced.
    var isBalanced: Bool { abs(balanceFactor) <= 1 }

    /// Left subtree duration.
    var leftDuration: Int64 { left?.subtreeDurationMicros ?? 0 }

    /// Right subtree duration.
    var rightDuration: Int64 { right?.subtreeDurationMicros ?? 0 }

    /// Left subtree count.
    var leftCount: Int { left?.subtreeCount ?? 0 }

    /// Right subtree count.
    var rightCount: Int { right?.subtreeCount ?? 0 }
}

// MARK: - AVL Tree Operations

/// Helper enum for AVL tree operations.
/// All operations return new nodes (immutable/persistent).
enum AVLOperations {

    /// Balance a node after insertion/deletion.
    static func balance(_ node: TimelineNode) -> TimelineNode {
        let bf = node.balanceFactor

        if bf > 1 {
            // Left heavy
            if (node.left?.balanceFactor ?? 0) < 0 {
                // Left-Right case
                return rotateRight(node.withChildren(
                    left: rotateLeft(node.left!)
                ))
            }
            // Left-Left case
            return rotateRight(node)
        }

        if bf < -1 {
            // Right heavy
            if (node.right?.balanceFactor ?? 0) > 0 {
                // Right-Left case
                return rotateLeft(node.withChildren(
                    right: rotateRight(node.right!)
                ))
            }
            // Right-Right case
            return rotateLeft(node)
        }

        return node
    }

    /// Rotate right around node y.
    ///
    /// ```
    ///       y                x
    ///      / \              / \
    ///     x   C    =>      A   y
    ///    / \                  / \
    ///   A   B                B   C
    /// ```
    static func rotateRight(_ y: TimelineNode) -> TimelineNode {
        precondition(y.left != nil, "Cannot rotate right without left child")
        let x = y.left!
        let b = x.right

        return x.withChildren(
            right: y.withChildren(left: b, clearLeft: b == nil)
        )
    }

    /// Rotate left around node x.
    ///
    /// ```
    ///     x                  y
    ///    / \                / \
    ///   A   y      =>      x   C
    ///      / \            / \
    ///     B   C          A   B
    /// ```
    static func rotateLeft(_ x: TimelineNode) -> TimelineNode {
        precondition(x.right != nil, "Cannot rotate left without right child")
        let y = x.right!
        let b = y.left

        return y.withChildren(
            left: x.withChildren(right: b, clearRight: b == nil)
        )
    }

    /// Find the minimum node in a subtree.
    static func findMin(_ node: TimelineNode) -> TimelineNode {
        var current = node
        while let left = current.left {
            current = left
        }
        return current
    }

    /// Find the maximum node in a subtree.
    static func findMax(_ node: TimelineNode) -> TimelineNode {
        var current = node
        while let right = current.right {
            current = right
        }
        return current
    }

    /// Remove the minimum node from a subtree.
    /// Returns (minNode, newSubtreeRoot).
    static func removeMin(_ node: TimelineNode) -> (min: TimelineNode, newRoot: TimelineNode?) {
        if node.left == nil {
            return (node, node.right)
        }

        precondition(node.left != nil, "removeMin invariant: left child must exist for recursive call")
        let (min, newLeft) = removeMin(node.left!)
        let newNode = node.withChildren(left: newLeft, clearLeft: newLeft == nil)
        return (min, balance(newNode))
    }
}
