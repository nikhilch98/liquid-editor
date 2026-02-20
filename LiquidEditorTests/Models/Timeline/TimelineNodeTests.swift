import Testing
@testable import LiquidEditor

/// Mock timeline item for testing.
struct MockTimelineItem: TimelineItemProtocol {
    let id: String
    let durationMicroseconds: Int64
    var displayName: String { "Mock \(id)" }
}

@Suite("TimelineNode Tests")
struct TimelineNodeTests {

    // MARK: - Leaf Creation

    @Test("Leaf node has correct properties")
    func leafCreation() {
        let item = MockTimelineItem(id: "item1", durationMicroseconds: 1_000_000)
        let node = TimelineNode.leaf(item)

        #expect(node.id == "item1")
        #expect(node.height == 1)
        #expect(node.subtreeCount == 1)
        #expect(node.subtreeDurationMicros == 1_000_000)
        #expect(node.left == nil)
        #expect(node.right == nil)
    }

    @Test("Leaf node item duration matches")
    func leafItemDuration() {
        let item = MockTimelineItem(id: "a", durationMicroseconds: 500_000)
        let node = TimelineNode.leaf(item)
        #expect(node.itemDurationMicros == 500_000)
    }

    // MARK: - withChildren

    @Test("withChildren creates node with updated children")
    func withChildren() {
        let item1 = MockTimelineItem(id: "root", durationMicroseconds: 1_000_000)
        let item2 = MockTimelineItem(id: "left", durationMicroseconds: 500_000)
        let item3 = MockTimelineItem(id: "right", durationMicroseconds: 750_000)

        let root = TimelineNode.leaf(item1)
        let leftChild = TimelineNode.leaf(item2)
        let rightChild = TimelineNode.leaf(item3)

        let updated = root.withChildren(left: leftChild, right: rightChild)

        #expect(updated.left?.id == "left")
        #expect(updated.right?.id == "right")
        #expect(updated.height == 2)
        #expect(updated.subtreeCount == 3)
        #expect(updated.subtreeDurationMicros == 2_250_000) // 1M + 500K + 750K
    }

    @Test("withChildren clearLeft removes left child")
    func withChildrenClearLeft() {
        let item1 = MockTimelineItem(id: "root", durationMicroseconds: 1_000_000)
        let item2 = MockTimelineItem(id: "left", durationMicroseconds: 500_000)

        let root = TimelineNode.leaf(item1)
        let leftChild = TimelineNode.leaf(item2)
        let withLeft = root.withChildren(left: leftChild)

        #expect(withLeft.left?.id == "left")

        let cleared = withLeft.withChildren(clearLeft: true)
        #expect(cleared.left == nil)
        #expect(cleared.subtreeCount == 1)
    }

    @Test("withChildren clearRight removes right child")
    func withChildrenClearRight() {
        let item1 = MockTimelineItem(id: "root", durationMicroseconds: 1_000_000)
        let item3 = MockTimelineItem(id: "right", durationMicroseconds: 750_000)

        let root = TimelineNode.leaf(item1)
        let rightChild = TimelineNode.leaf(item3)
        let withRight = root.withChildren(right: rightChild)
        let cleared = withRight.withChildren(clearRight: true)

        #expect(cleared.right == nil)
        #expect(cleared.subtreeCount == 1)
    }

    // MARK: - withItem

    @Test("withItem creates node with new item preserving structure")
    func withItem() {
        let item1 = MockTimelineItem(id: "root", durationMicroseconds: 1_000_000)
        let left = MockTimelineItem(id: "left", durationMicroseconds: 500_000)
        let root = TimelineNode.leaf(item1).withChildren(left: TimelineNode.leaf(left))

        let newItem = MockTimelineItem(id: "root2", durationMicroseconds: 2_000_000)
        let updated = root.withItem(newItem)

        #expect(updated.id == "root2")
        #expect(updated.itemDurationMicros == 2_000_000)
        #expect(updated.left?.id == "left") // structure preserved
        #expect(updated.subtreeDurationMicros == 2_500_000) // 2M + 500K
    }

    // MARK: - Balance Factor

    @Test("Balanced node has factor 0")
    func balancedNode() {
        let root = TimelineNode.leaf(MockTimelineItem(id: "r", durationMicroseconds: 100))
        let left = TimelineNode.leaf(MockTimelineItem(id: "l", durationMicroseconds: 100))
        let right = TimelineNode.leaf(MockTimelineItem(id: "ri", durationMicroseconds: 100))
        let balanced = root.withChildren(left: left, right: right)

        #expect(balanced.balanceFactor == 0)
        #expect(balanced.isBalanced == true)
    }

    @Test("Left-heavy node has positive balance factor")
    func leftHeavy() {
        let root = TimelineNode.leaf(MockTimelineItem(id: "r", durationMicroseconds: 100))
        let left = TimelineNode.leaf(MockTimelineItem(id: "l", durationMicroseconds: 100))
        let leftLeft = TimelineNode.leaf(MockTimelineItem(id: "ll", durationMicroseconds: 100))
        let leftNode = left.withChildren(left: leftLeft)
        let unbalanced = root.withChildren(left: leftNode)

        #expect(unbalanced.balanceFactor == 2)
        #expect(unbalanced.isBalanced == false)
    }

    // MARK: - Computed Properties

    @Test("leftDuration and rightDuration compute correctly")
    func subtreeDurations() {
        let root = TimelineNode.leaf(MockTimelineItem(id: "r", durationMicroseconds: 100))
        let left = TimelineNode.leaf(MockTimelineItem(id: "l", durationMicroseconds: 200))
        let right = TimelineNode.leaf(MockTimelineItem(id: "ri", durationMicroseconds: 300))
        let node = root.withChildren(left: left, right: right)

        #expect(node.leftDuration == 200)
        #expect(node.rightDuration == 300)
        #expect(node.leftCount == 1)
        #expect(node.rightCount == 1)
    }

    @Test("Nil children return zero for durations and counts")
    func nilChildrenDefaults() {
        let leaf = TimelineNode.leaf(MockTimelineItem(id: "a", durationMicroseconds: 100))
        #expect(leaf.leftDuration == 0)
        #expect(leaf.rightDuration == 0)
        #expect(leaf.leftCount == 0)
        #expect(leaf.rightCount == 0)
    }
}

@Suite("AVLOperations Tests")
struct AVLOperationsTests {

    private func makeNode(_ id: String, _ duration: Int64 = 100) -> TimelineNode {
        TimelineNode.leaf(MockTimelineItem(id: id, durationMicroseconds: duration))
    }

    // MARK: - Rotations

    @Test("Rotate right preserves order")
    func rotateRight() {
        // Build: y(left: x(left: A), right: C) where x has left child A
        let a = makeNode("A")
        let x = makeNode("x").withChildren(left: a)
        let c = makeNode("C")
        let y = makeNode("y").withChildren(left: x, right: c)

        let rotated = AVLOperations.rotateRight(y)

        // After rotation: x(left: A, right: y(left: nil, right: C))
        #expect(rotated.id == "x")
        #expect(rotated.left?.id == "A")
        #expect(rotated.right?.id == "y")
        #expect(rotated.right?.right?.id == "C")
    }

    @Test("Rotate left preserves order")
    func rotateLeft() {
        let a = makeNode("A")
        let y = makeNode("y").withChildren(right: makeNode("C"))
        let x = makeNode("x").withChildren(left: a, right: y)

        let rotated = AVLOperations.rotateLeft(x)

        #expect(rotated.id == "y")
        #expect(rotated.left?.id == "x")
        #expect(rotated.left?.left?.id == "A")
        #expect(rotated.right?.id == "C")
    }

    // MARK: - Balance

    @Test("Balance corrects left-left case")
    func balanceLeftLeft() {
        let ll = makeNode("ll")
        let l = makeNode("l").withChildren(left: ll)
        let root = makeNode("root").withChildren(left: l)

        let balanced = AVLOperations.balance(root)
        #expect(balanced.isBalanced)
        #expect(balanced.subtreeCount == 3)
    }

    @Test("Balance corrects right-right case")
    func balanceRightRight() {
        let rr = makeNode("rr")
        let r = makeNode("r").withChildren(right: rr)
        let root = makeNode("root").withChildren(right: r)

        let balanced = AVLOperations.balance(root)
        #expect(balanced.isBalanced)
        #expect(balanced.subtreeCount == 3)
    }

    @Test("Balance corrects left-right case")
    func balanceLeftRight() {
        let lr = makeNode("lr")
        let l = makeNode("l").withChildren(right: lr)
        let root = makeNode("root").withChildren(left: l)

        let balanced = AVLOperations.balance(root)
        #expect(balanced.isBalanced)
        #expect(balanced.subtreeCount == 3)
    }

    @Test("Balance corrects right-left case")
    func balanceRightLeft() {
        let rl = makeNode("rl")
        let r = makeNode("r").withChildren(left: rl)
        let root = makeNode("root").withChildren(right: r)

        let balanced = AVLOperations.balance(root)
        #expect(balanced.isBalanced)
        #expect(balanced.subtreeCount == 3)
    }

    @Test("Balance preserves already balanced tree")
    func balanceAlreadyBalanced() {
        let l = makeNode("l")
        let r = makeNode("r")
        let root = makeNode("root").withChildren(left: l, right: r)

        let balanced = AVLOperations.balance(root)
        #expect(balanced.id == "root")
        #expect(balanced.subtreeCount == 3)
    }

    // MARK: - Find Min/Max

    @Test("findMin returns leftmost node")
    func findMin() {
        let a = makeNode("A")
        let b = makeNode("B").withChildren(left: a)
        let c = makeNode("C").withChildren(left: b)

        let min = AVLOperations.findMin(c)
        #expect(min.id == "A")
    }

    @Test("findMax returns rightmost node")
    func findMax() {
        let c = makeNode("C")
        let b = makeNode("B").withChildren(right: c)
        let a = makeNode("A").withChildren(right: b)

        let max = AVLOperations.findMax(a)
        #expect(max.id == "C")
    }

    @Test("findMin on leaf returns itself")
    func findMinLeaf() {
        let node = makeNode("only")
        let min = AVLOperations.findMin(node)
        #expect(min.id == "only")
    }

    // MARK: - Remove Min

    @Test("removeMin removes and returns minimum")
    func removeMin() {
        let a = makeNode("A", 100)
        let b = makeNode("B", 200)
        let c = makeNode("C", 300)
        let root = b.withChildren(left: a, right: c)

        let (min, newRoot) = AVLOperations.removeMin(root)
        #expect(min.id == "A")
        #expect(newRoot?.id == "B")
        #expect(newRoot?.left == nil)
        #expect(newRoot?.right?.id == "C")
    }

    @Test("removeMin on leaf returns nil root")
    func removeMinLeaf() {
        let node = makeNode("only")
        let (min, newRoot) = AVLOperations.removeMin(node)
        #expect(min.id == "only")
        #expect(newRoot == nil)
    }

    // MARK: - Subtree Duration Integrity

    @Test("Subtree duration sums correctly after operations")
    func subtreeDurationIntegrity() {
        let a = makeNode("a", 100)
        let b = makeNode("b", 200)
        let c = makeNode("c", 300)
        let d = makeNode("d", 400)
        let e = makeNode("e", 500)

        // Build a tree
        let left = b.withChildren(left: a, right: c)
        let right = makeNode("right_root", 150).withChildren(right: e)
        let root = d.withChildren(left: left, right: right)

        #expect(root.subtreeDurationMicros == 100 + 200 + 300 + 400 + 150 + 500)
        #expect(root.subtreeCount == 6)

        // After balancing, totals should be preserved
        let balanced = AVLOperations.balance(root)
        #expect(balanced.subtreeDurationMicros == root.subtreeDurationMicros)
        #expect(balanced.subtreeCount == root.subtreeCount)
    }
}
