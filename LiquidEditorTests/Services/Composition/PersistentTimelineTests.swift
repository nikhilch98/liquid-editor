import Testing
@testable import LiquidEditor

// MockTimelineItem is defined in TimelineNodeTests.swift and shared across the test target.

@Suite("PersistentTimeline Tests")
struct PersistentTimelineTests {

    // MARK: - Helpers

    private func makeItem(_ id: String, duration: Int64 = 1_000_000) -> MockTimelineItem {
        MockTimelineItem(id: id, durationMicroseconds: duration)
    }

    /// Build a timeline with N items named "0", "1", ... each with the given duration.
    private func buildTimeline(count: Int, duration: Int64 = 1_000_000) -> PersistentTimeline {
        var tl = PersistentTimeline.empty
        for i in 0..<count {
            tl = tl.append(makeItem("\(i)", duration: duration))
        }
        return tl
    }

    // MARK: - 1. Empty Timeline

    @Suite("Empty Timeline")
    struct EmptyTimelineTests {
        @Test("empty timeline has zero count")
        func emptyCount() {
            let tl = PersistentTimeline.empty
            #expect(tl.count == 0)
        }

        @Test("empty timeline has zero totalDuration")
        func emptyDuration() {
            let tl = PersistentTimeline.empty
            #expect(tl.totalDurationMicros == 0)
            #expect(tl.totalDurationSeconds == 0.0)
        }

        @Test("empty timeline isEmpty is true")
        func emptyIsEmpty() {
            let tl = PersistentTimeline.empty
            #expect(tl.isEmpty)
            #expect(!tl.isNotEmpty)
        }

        @Test("empty timeline root is nil")
        func emptyRoot() {
            let tl = PersistentTimeline.empty
            #expect(tl.root == nil)
        }

        @Test("empty timeline toList returns empty array")
        func emptyToList() {
            let tl = PersistentTimeline.empty
            #expect(tl.toList().isEmpty)
        }

        @Test("empty timeline items sequence is empty")
        func emptyItems() {
            let tl = PersistentTimeline.empty
            #expect(Array(tl.items).isEmpty)
        }

        @Test("empty timeline itemAtTime returns nil")
        func emptyItemAtTime() {
            let tl = PersistentTimeline.empty
            #expect(tl.itemAtTime(0) == nil)
            #expect(tl.itemAtTime(100) == nil)
        }

        @Test("empty timeline getById returns nil")
        func emptyGetById() {
            let tl = PersistentTimeline.empty
            #expect(tl.getById("nonexistent") == nil)
        }

        @Test("empty timeline containsId returns false")
        func emptyContainsId() {
            let tl = PersistentTimeline.empty
            #expect(!tl.containsId("anything"))
        }

        @Test("empty timeline startTimeOf returns nil")
        func emptyStartTimeOf() {
            let tl = PersistentTimeline.empty
            #expect(tl.startTimeOf("x") == nil)
        }

        @Test("empty timeline itemAtIndex returns nil")
        func emptyItemAtIndex() {
            let tl = PersistentTimeline.empty
            #expect(tl.itemAtIndex(0) == nil)
            #expect(tl.itemAtIndex(-1) == nil)
        }
    }

    // MARK: - 2. Append

    @Test("append single item increases count and duration")
    func appendSingle() {
        let item = makeItem("a", duration: 500_000)
        let tl = PersistentTimeline.empty.append(item)

        #expect(tl.count == 1)
        #expect(tl.totalDurationMicros == 500_000)
        #expect(!tl.isEmpty)
        #expect(tl.isNotEmpty)
    }

    @Test("append multiple items accumulates count and duration")
    func appendMultiple() {
        var tl = PersistentTimeline.empty
        tl = tl.append(makeItem("a", duration: 1_000_000))
        tl = tl.append(makeItem("b", duration: 2_000_000))
        tl = tl.append(makeItem("c", duration: 3_000_000))

        #expect(tl.count == 3)
        #expect(tl.totalDurationMicros == 6_000_000)
    }

    @Test("appended items appear in order via toList")
    func appendOrder() {
        var tl = PersistentTimeline.empty
        tl = tl.append(makeItem("first"))
        tl = tl.append(makeItem("second"))
        tl = tl.append(makeItem("third"))

        let ids = tl.toList().map { $0.id }
        #expect(ids == ["first", "second", "third"])
    }

    // MARK: - 3. Prepend

    @Test("prepend inserts item at index 0")
    func prependBasic() {
        var tl = PersistentTimeline.empty
        tl = tl.append(makeItem("b"))
        tl = tl.append(makeItem("c"))
        tl = tl.prepend(makeItem("a"))

        let ids = tl.toList().map { $0.id }
        #expect(ids == ["a", "b", "c"])
        #expect(tl.count == 3)
    }

    @Test("prepend on empty timeline creates single-item timeline")
    func prependEmpty() {
        let tl = PersistentTimeline.empty.prepend(makeItem("only"))
        #expect(tl.count == 1)
        #expect(tl.toList().first?.id == "only")
    }

    @Test("prepend multiple items maintains reverse insertion order at front")
    func prependMultiple() {
        var tl = PersistentTimeline.empty
        tl = tl.append(makeItem("c"))
        tl = tl.prepend(makeItem("b"))
        tl = tl.prepend(makeItem("a"))

        let ids = tl.toList().map { $0.id }
        #expect(ids == ["a", "b", "c"])
    }

    // MARK: - 4. insertAt

    @Test("insertAt time 0 prepends")
    func insertAtZero() {
        var tl = PersistentTimeline.empty
        tl = tl.append(makeItem("b", duration: 1_000_000))
        tl = tl.insertAt(0, makeItem("a", duration: 500_000))

        let ids = tl.toList().map { $0.id }
        #expect(ids.first == "a")
        #expect(tl.count == 2)
        #expect(tl.totalDurationMicros == 1_500_000)
    }

    @Test("insertAt end appends")
    func insertAtEnd() {
        var tl = PersistentTimeline.empty
        tl = tl.append(makeItem("a", duration: 1_000_000))
        tl = tl.insertAt(1_000_000, makeItem("b", duration: 500_000))

        let ids = tl.toList().map { $0.id }
        #expect(ids == ["a", "b"])
    }

    @Test("insertAt middle position places item correctly")
    func insertAtMiddle() {
        var tl = PersistentTimeline.empty
        tl = tl.append(makeItem("a", duration: 1_000_000))
        tl = tl.append(makeItem("c", duration: 1_000_000))
        // Insert at time 1_000_000 (boundary between a and c)
        tl = tl.insertAt(1_000_000, makeItem("b", duration: 500_000))

        let ids = tl.toList().map { $0.id }
        #expect(ids == ["a", "b", "c"])
        #expect(tl.count == 3)
        #expect(tl.totalDurationMicros == 2_500_000)
    }

    @Test("insertAt on empty timeline creates single item")
    func insertAtEmpty() {
        let tl = PersistentTimeline.empty.insertAt(0, makeItem("x"))
        #expect(tl.count == 1)
    }

    // MARK: - 5. Immutability

    @Test("append does not modify original timeline")
    func immutabilityAppend() {
        let original = PersistentTimeline.empty.append(makeItem("a"))
        let modified = original.append(makeItem("b"))

        #expect(original.count == 1)
        #expect(modified.count == 2)
        #expect(original.toList().map { $0.id } == ["a"])
        #expect(modified.toList().map { $0.id } == ["a", "b"])
    }

    @Test("remove does not modify original timeline")
    func immutabilityRemove() {
        let original = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))
        let modified = original.remove("a")

        #expect(original.count == 2)
        #expect(modified.count == 1)
        #expect(original.containsId("a"))
        #expect(!modified.containsId("a"))
    }

    @Test("updateItem does not modify original timeline")
    func immutabilityUpdate() {
        let original = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
        let modified = original.updateItem("a", makeItem("a", duration: 2_000_000))

        #expect(original.totalDurationMicros == 1_000_000)
        #expect(modified.totalDurationMicros == 2_000_000)
    }

    @Test("prepend does not modify original timeline")
    func immutabilityPrepend() {
        let original = PersistentTimeline.empty.append(makeItem("b"))
        let modified = original.prepend(makeItem("a"))

        #expect(original.count == 1)
        #expect(original.toList().first?.id == "b")
        #expect(modified.count == 2)
    }

    // MARK: - 6. itemAtTime

    @Test("itemAtTime at time 0 returns first item with offset 0")
    func itemAtTimeZero() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        let result = tl.itemAtTime(0)
        #expect(result != nil)
        #expect(result?.0.id == "a")
        #expect(result?.1 == 0)
    }

    @Test("itemAtTime within first item returns correct offset")
    func itemAtTimeWithinFirst() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        let result = tl.itemAtTime(500_000)
        #expect(result?.0.id == "a")
        #expect(result?.1 == 500_000)
    }

    @Test("itemAtTime at boundary returns second item")
    func itemAtTimeBoundary() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        // Time exactly at boundary of a (1_000_000) should be start of b
        let result = tl.itemAtTime(1_000_000)
        #expect(result?.0.id == "b")
        #expect(result?.1 == 0)
    }

    @Test("itemAtTime within second item returns correct offset")
    func itemAtTimeWithinSecond() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        let result = tl.itemAtTime(1_500_000)
        #expect(result?.0.id == "b")
        #expect(result?.1 == 500_000)
    }

    @Test("itemAtTime past end returns nil")
    func itemAtTimePastEnd() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))

        #expect(tl.itemAtTime(1_000_000) == nil)
        #expect(tl.itemAtTime(2_000_000) == nil)
    }

    @Test("itemAtTime negative returns nil")
    func itemAtTimeNegative() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))

        #expect(tl.itemAtTime(-1) == nil)
    }

    @Test("itemAtTime with three items navigates correctly")
    func itemAtTimeThreeItems() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))  // 0 ..< 1M
            .append(makeItem("b", duration: 2_000_000))  // 1M ..< 3M
            .append(makeItem("c", duration: 3_000_000))  // 3M ..< 6M

        let resultC = tl.itemAtTime(4_000_000) // within c
        #expect(resultC?.0.id == "c")
        #expect(resultC?.1 == 1_000_000) // 4M - 3M = 1M offset

        let resultLast = tl.itemAtTime(5_999_999) // last microsecond of c
        #expect(resultLast?.0.id == "c")
        #expect(resultLast?.1 == 2_999_999)
    }

    // MARK: - 7. startTimeOf

    @Test("startTimeOf first item is 0")
    func startTimeOfFirst() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        #expect(tl.startTimeOf("a") == 0)
    }

    @Test("startTimeOf second item is first item's duration")
    func startTimeOfSecond() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        #expect(tl.startTimeOf("b") == 1_000_000)
    }

    @Test("startTimeOf cumulative with multiple items")
    func startTimeOfCumulative() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))
            .append(makeItem("c", duration: 3_000_000))

        #expect(tl.startTimeOf("a") == 0)
        #expect(tl.startTimeOf("b") == 1_000_000)
        #expect(tl.startTimeOf("c") == 3_000_000) // 1M + 2M
    }

    @Test("startTimeOf nonexistent item returns nil")
    func startTimeOfNonexistent() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))

        #expect(tl.startTimeOf("zzz") == nil)
    }

    // MARK: - 8. getById

    @Test("getById returns correct item")
    func getByIdFound() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 100))
            .append(makeItem("b", duration: 200))
            .append(makeItem("c", duration: 300))

        let item = tl.getById("b")
        #expect(item != nil)
        #expect(item?.id == "b")
        #expect(item?.durationMicroseconds == 200)
    }

    @Test("getById returns nil for nonexistent ID")
    func getByIdNotFound() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))

        #expect(tl.getById("nonexistent") == nil)
    }

    @Test("getById on empty timeline returns nil")
    func getByIdEmpty() {
        #expect(PersistentTimeline.empty.getById("x") == nil)
    }

    // MARK: - 9. containsId

    @Test("containsId returns true for existing item")
    func containsIdTrue() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))

        #expect(tl.containsId("a"))
        #expect(tl.containsId("b"))
    }

    @Test("containsId returns false for nonexistent item")
    func containsIdFalse() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))

        #expect(!tl.containsId("zzz"))
    }

    @Test("containsId returns false on empty timeline")
    func containsIdEmpty() {
        #expect(!PersistentTimeline.empty.containsId("x"))
    }

    // MARK: - 10. itemAtIndex

    @Test("itemAtIndex returns items in order")
    func itemAtIndexInOrder() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))
            .append(makeItem("c"))

        #expect(tl.itemAtIndex(0)?.id == "a")
        #expect(tl.itemAtIndex(1)?.id == "b")
        #expect(tl.itemAtIndex(2)?.id == "c")
    }

    @Test("itemAtIndex out of range returns nil")
    func itemAtIndexOutOfRange() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))

        #expect(tl.itemAtIndex(-1) == nil)
        #expect(tl.itemAtIndex(1) == nil)
        #expect(tl.itemAtIndex(100) == nil)
    }

    @Test("itemAtIndex on empty timeline returns nil")
    func itemAtIndexEmpty() {
        #expect(PersistentTimeline.empty.itemAtIndex(0) == nil)
    }

    // MARK: - 11. toList

    @Test("toList returns all items in order")
    func toListOrder() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 100))
            .append(makeItem("b", duration: 200))
            .append(makeItem("c", duration: 300))

        let items = tl.toList()
        #expect(items.count == 3)
        #expect(items[0].id == "a")
        #expect(items[1].id == "b")
        #expect(items[2].id == "c")
    }

    @Test("toList returns empty array for empty timeline")
    func toListEmpty() {
        #expect(PersistentTimeline.empty.toList().isEmpty)
    }

    @Test("toList single item")
    func toListSingle() {
        let tl = PersistentTimeline.empty.append(makeItem("only"))
        let items = tl.toList()
        #expect(items.count == 1)
        #expect(items[0].id == "only")
    }

    // MARK: - 12. items (lazy sequence)

    @Test("items sequence matches toList order")
    func itemsMatchToList() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))
            .append(makeItem("c"))

        let fromItems = Array(tl.items).map { $0.id }
        let fromToList = tl.toList().map { $0.id }
        #expect(fromItems == fromToList)
    }

    @Test("items sequence on empty timeline is empty")
    func itemsEmpty() {
        #expect(Array(PersistentTimeline.empty.items).isEmpty)
    }

    @Test("items sequence supports multiple iterations")
    func itemsMultipleIterations() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))

        let first = Array(tl.items).map { $0.id }
        let second = Array(tl.items).map { $0.id }
        #expect(first == second)
    }

    // MARK: - 13. remove

    @Test("remove existing item decreases count")
    func removeExisting() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))
            .append(makeItem("c", duration: 3_000_000))

        let removed = tl.remove("b")
        #expect(removed.count == 2)
        #expect(removed.totalDurationMicros == 4_000_000) // 1M + 3M
        #expect(!removed.containsId("b"))
    }

    @Test("remove preserves remaining items in order")
    func removePreservesOrder() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))
            .append(makeItem("c"))

        let removed = tl.remove("b")
        let ids = removed.toList().map { $0.id }
        #expect(ids == ["a", "c"])
    }

    @Test("remove first item")
    func removeFirst() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))

        let removed = tl.remove("a")
        #expect(removed.count == 1)
        #expect(removed.toList().first?.id == "b")
    }

    @Test("remove last item")
    func removeLast() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))

        let removed = tl.remove("b")
        #expect(removed.count == 1)
        #expect(removed.toList().first?.id == "a")
    }

    @Test("remove only item results in empty timeline")
    func removeOnlyItem() {
        let tl = PersistentTimeline.empty.append(makeItem("a"))
        let removed = tl.remove("a")

        #expect(removed.isEmpty)
        #expect(removed.count == 0)
        #expect(removed.totalDurationMicros == 0)
    }

    @Test("remove nonexistent item returns equivalent timeline")
    func removeNonexistent() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))

        let removed = tl.remove("zzz")
        #expect(removed.count == 2)
        #expect(removed.toList().map { $0.id } == ["a", "b"])
    }

    @Test("remove from empty timeline returns empty")
    func removeFromEmpty() {
        let tl = PersistentTimeline.empty.remove("x")
        #expect(tl.isEmpty)
    }

    // MARK: - 14. updateItem

    @Test("updateItem changes duration")
    func updateItemDuration() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        let updated = tl.updateItem("b", makeItem("b", duration: 5_000_000))

        #expect(updated.count == 2)
        #expect(updated.totalDurationMicros == 6_000_000) // 1M + 5M
        #expect(updated.getById("b")?.durationMicroseconds == 5_000_000)
    }

    @Test("updateItem preserves order")
    func updateItemPreservesOrder() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))
            .append(makeItem("c"))

        let updated = tl.updateItem("b", makeItem("b_new", duration: 999))
        let ids = updated.toList().map { $0.id }
        // The item at index 1 should now have the new ID
        #expect(ids[0] == "a")
        #expect(ids[1] == "b_new")
        #expect(ids[2] == "c")
    }

    @Test("updateItem nonexistent returns same timeline")
    func updateItemNonexistent() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))

        let updated = tl.updateItem("zzz", makeItem("zzz", duration: 999))
        #expect(updated.count == 1)
        #expect(updated.totalDurationMicros == 1_000_000)
    }

    @Test("updateItem on empty timeline returns empty")
    func updateItemEmpty() {
        let updated = PersistentTimeline.empty.updateItem("x", makeItem("x"))
        #expect(updated.isEmpty)
    }

    // MARK: - 15. replaceAt

    @Test("replaceAt index 0 replaces first item")
    func replaceAtFirst() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        let replaced = tl.replaceAt(0, makeItem("x", duration: 500_000))
        #expect(replaced.count == 2)
        #expect(replaced.itemAtIndex(0)?.id == "x")
        #expect(replaced.totalDurationMicros == 2_500_000) // 500K + 2M
    }

    @Test("replaceAt last index replaces last item")
    func replaceAtLast() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        let replaced = tl.replaceAt(1, makeItem("y", duration: 3_000_000))
        #expect(replaced.itemAtIndex(1)?.id == "y")
        #expect(replaced.totalDurationMicros == 4_000_000) // 1M + 3M
    }

    @Test("replaceAt out of range returns same timeline")
    func replaceAtOutOfRange() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))

        let replaced = tl.replaceAt(5, makeItem("x"))
        #expect(replaced.count == 1)
        #expect(replaced.totalDurationMicros == 1_000_000)
    }

    // MARK: - 16. fromList

    @Test("fromList creates timeline with correct items")
    func fromListBasic() {
        let items: [any TimelineItemProtocol] = [
            makeItem("a", duration: 100),
            makeItem("b", duration: 200),
            makeItem("c", duration: 300),
        ]
        let tl = PersistentTimeline.fromList(items)

        #expect(tl.count == 3)
        #expect(tl.totalDurationMicros == 600)
        #expect(tl.toList().map { $0.id } == ["a", "b", "c"])
    }

    @Test("fromList empty array returns empty timeline")
    func fromListEmpty() {
        let tl = PersistentTimeline.fromList([])
        #expect(tl.isEmpty)
    }

    @Test("fromList single item")
    func fromListSingle() {
        let items: [any TimelineItemProtocol] = [makeItem("only", duration: 42)]
        let tl = PersistentTimeline.fromList(items)
        #expect(tl.count == 1)
        #expect(tl.totalDurationMicros == 42)
    }

    // MARK: - 17. fromSortedList

    @Test("fromSortedList creates balanced tree")
    func fromSortedListBalanced() {
        let items: [any TimelineItemProtocol] = (0..<7).map {
            makeItem("\($0)", duration: 1_000_000)
        }
        let tl = PersistentTimeline.fromSortedList(items)

        #expect(tl.count == 7)
        #expect(tl.totalDurationMicros == 7_000_000)
        // A balanced tree of 7 items should have height <= 3
        #expect(tl.root!.height <= 3)
    }

    @Test("fromSortedList preserves order")
    func fromSortedListOrder() {
        let items: [any TimelineItemProtocol] = [
            makeItem("a", duration: 100),
            makeItem("b", duration: 200),
            makeItem("c", duration: 300),
            makeItem("d", duration: 400),
            makeItem("e", duration: 500),
        ]
        let tl = PersistentTimeline.fromSortedList(items)
        let ids = tl.toList().map { $0.id }
        #expect(ids == ["a", "b", "c", "d", "e"])
    }

    @Test("fromSortedList empty returns empty timeline")
    func fromSortedListEmpty() {
        let tl = PersistentTimeline.fromSortedList([])
        #expect(tl.isEmpty)
    }

    @Test("fromSortedList single item")
    func fromSortedListSingle() {
        let items: [any TimelineItemProtocol] = [makeItem("only")]
        let tl = PersistentTimeline.fromSortedList(items)
        #expect(tl.count == 1)
        #expect(tl.root!.height == 1)
    }

    @Test("fromSortedList two items")
    func fromSortedListTwo() {
        let items: [any TimelineItemProtocol] = [
            makeItem("a", duration: 100),
            makeItem("b", duration: 200),
        ]
        let tl = PersistentTimeline.fromSortedList(items)
        #expect(tl.count == 2)
        #expect(tl.toList().map { $0.id } == ["a", "b"])
    }

    @Test("fromSortedList produces more balanced tree than fromList for large input")
    func fromSortedListVsFromList() {
        let items: [any TimelineItemProtocol] = (0..<31).map {
            makeItem("\($0)", duration: 1_000)
        }
        let sorted = PersistentTimeline.fromSortedList(items)
        let sequential = PersistentTimeline.fromList(items)

        // Both should have same data
        #expect(sorted.count == sequential.count)
        #expect(sorted.totalDurationMicros == sequential.totalDurationMicros)

        // fromSortedList should produce a perfectly balanced tree
        // height of balanced tree for 31 items: ceil(log2(32)) = 5
        #expect(sorted.root!.height <= 5)
    }

    // MARK: - 18. Large Tree

    @Test("large tree with 100 items - append and verify all queries")
    func largeTreeAppend() {
        let count = 100
        let duration: Int64 = 1_000_000
        let tl = buildTimeline(count: count, duration: duration)

        #expect(tl.count == count)
        #expect(tl.totalDurationMicros == Int64(count) * duration)

        // Verify itemAtIndex for every item
        for i in 0..<count {
            let item = tl.itemAtIndex(i)
            #expect(item?.id == "\(i)")
        }
    }

    @Test("large tree - toList returns all items in order")
    func largeTreeToList() {
        let count = 100
        let tl = buildTimeline(count: count)

        let ids = tl.toList().map { $0.id }
        let expected = (0..<count).map { "\($0)" }
        #expect(ids == expected)
    }

    @Test("large tree - containsId for all items")
    func largeTreeContainsId() {
        let count = 100
        let tl = buildTimeline(count: count)

        for i in 0..<count {
            #expect(tl.containsId("\(i)"))
        }
        #expect(!tl.containsId("nonexistent"))
    }

    @Test("large tree - startTimeOf cumulates correctly")
    func largeTreeStartTime() {
        let count = 50
        let duration: Int64 = 1_000_000
        let tl = buildTimeline(count: count, duration: duration)

        for i in 0..<count {
            let expected = Int64(i) * duration
            #expect(tl.startTimeOf("\(i)") == expected)
        }
    }

    @Test("large tree - itemAtTime finds correct items")
    func largeTreeItemAtTime() {
        let count = 50
        let duration: Int64 = 1_000_000
        let tl = buildTimeline(count: count, duration: duration)

        // Check middle of each item
        for i in 0..<count {
            let time = Int64(i) * duration + duration / 2
            let result = tl.itemAtTime(time)
            #expect(result?.0.id == "\(i)")
            #expect(result?.1 == duration / 2)
        }
    }

    @Test("large tree - remove and verify shrinks correctly")
    func largeTreeRemove() {
        let count = 100
        var tl = buildTimeline(count: count)

        // Remove every other item
        for i in stride(from: 0, to: count, by: 2) {
            tl = tl.remove("\(i)")
        }

        #expect(tl.count == 50)

        // Remaining items should be odd-numbered
        let ids = tl.toList().map { $0.id }
        let expected = stride(from: 1, to: count, by: 2).map { "\($0)" }
        #expect(ids == expected)
    }

    @Test("large tree - fromSortedList is balanced")
    func largeTreeFromSorted() {
        let items: [any TimelineItemProtocol] = (0..<128).map {
            makeItem("\($0)", duration: 1_000)
        }
        let tl = PersistentTimeline.fromSortedList(items)

        #expect(tl.count == 128)
        // A balanced tree of 128 items: height = ceil(log2(129)) = 8
        #expect(tl.root!.height <= 8)
    }

    @Test("large tree items sequence matches toList")
    func largeTreeItemsSequence() {
        let count = 100
        let tl = buildTimeline(count: count)

        let fromItems = Array(tl.items).map { $0.id }
        let fromToList = tl.toList().map { $0.id }
        #expect(fromItems == fromToList)
    }

    // MARK: - 19. Structural Sharing (Undo/Redo)

    @Test("old and new timelines can coexist after append")
    func structuralSharingAppend() {
        let v1 = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))
        let v2 = v1.append(makeItem("c"))

        // Both versions are valid simultaneously
        #expect(v1.count == 2)
        #expect(v2.count == 3)
        #expect(v1.toList().map { $0.id } == ["a", "b"])
        #expect(v2.toList().map { $0.id } == ["a", "b", "c"])
    }

    @Test("old and new timelines can coexist after remove")
    func structuralSharingRemove() {
        let v1 = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))
            .append(makeItem("c"))
        let v2 = v1.remove("b")

        #expect(v1.count == 3)
        #expect(v2.count == 2)
        #expect(v1.containsId("b"))
        #expect(!v2.containsId("b"))
    }

    @Test("multiple versions coexist - simulates undo stack")
    func structuralSharingUndoStack() {
        var history: [PersistentTimeline] = []

        var tl = PersistentTimeline.empty
        history.append(tl) // v0: empty

        tl = tl.append(makeItem("a"))
        history.append(tl) // v1: [a]

        tl = tl.append(makeItem("b"))
        history.append(tl) // v2: [a, b]

        tl = tl.append(makeItem("c"))
        history.append(tl) // v3: [a, b, c]

        tl = tl.remove("b")
        history.append(tl) // v4: [a, c]

        // All versions are independently valid
        #expect(history[0].count == 0)
        #expect(history[1].count == 1)
        #expect(history[2].count == 2)
        #expect(history[3].count == 3)
        #expect(history[4].count == 2)

        #expect(history[1].toList().map { $0.id } == ["a"])
        #expect(history[2].toList().map { $0.id } == ["a", "b"])
        #expect(history[3].toList().map { $0.id } == ["a", "b", "c"])
        #expect(history[4].toList().map { $0.id } == ["a", "c"])

        // "Undo" to v2 by just using the old value
        let undone = history[2]
        #expect(undone.count == 2)
        #expect(undone.toList().map { $0.id } == ["a", "b"])
    }

    @Test("structural sharing preserves independent queries")
    func structuralSharingQueries() {
        let v1 = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        let v2 = v1.updateItem("b", makeItem("b", duration: 5_000_000))

        // v1 queries
        #expect(v1.totalDurationMicros == 3_000_000)
        #expect(v1.getById("b")?.durationMicroseconds == 2_000_000)
        #expect(v1.startTimeOf("b") == 1_000_000)

        // v2 queries
        #expect(v2.totalDurationMicros == 6_000_000)
        #expect(v2.getById("b")?.durationMicroseconds == 5_000_000)
        #expect(v2.startTimeOf("b") == 1_000_000)
    }

    // MARK: - 20. description (CustomStringConvertible)

    @Test("description shows count and duration in ms")
    func descriptionBasic() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 2_500_000)) // 2.5s = 2500ms

        #expect(tl.description == "PersistentTimeline(1 items, 2500ms)")
    }

    @Test("description for empty timeline")
    func descriptionEmpty() {
        #expect(PersistentTimeline.empty.description == "PersistentTimeline(0 items, 0ms)")
    }

    @Test("description for multiple items")
    func descriptionMultiple() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))
            .append(makeItem("c", duration: 3_000_000))

        #expect(tl.description == "PersistentTimeline(3 items, 6000ms)")
    }

    // MARK: - Additional Edge Cases

    @Test("totalDurationSeconds computes correctly")
    func totalDurationSeconds() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_500_000)) // 1.5s

        #expect(tl.totalDurationSeconds == 1.5)
    }

    @Test("isNotEmpty returns true for non-empty timeline")
    func isNotEmptyTrue() {
        let tl = PersistentTimeline.empty.append(makeItem("a"))
        #expect(tl.isNotEmpty)
        #expect(!tl.isEmpty)
    }

    @Test("remove all items one by one results in empty timeline")
    func removeAllItemsSequentially() {
        var tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))
            .append(makeItem("c"))

        tl = tl.remove("b")
        tl = tl.remove("a")
        tl = tl.remove("c")

        #expect(tl.isEmpty)
        #expect(tl.count == 0)
        #expect(tl.totalDurationMicros == 0)
    }

    @Test("AVL invariant holds across inserts and random removals")
    func avlInvariantHoldsAcrossMutations() {
        // Deterministic linear congruential generator (Numerical Recipes parameters)
        // so the test is reproducible without depending on platform SystemRandomNumberGenerator.
        struct SeededLCG: RandomNumberGenerator {
            var state: UInt64
            mutating func next() -> UInt64 {
                state = state &* 1_664_525 &+ 1_013_904_223
                return state
            }
        }
        var rng = SeededLCG(state: 0xDEAD_BEEF_CAFE_F00D)

        // Phase 1: 200 sequential inserts — check invariant after every one.
        var tl = PersistentTimeline.empty
        for i in 0..<200 {
            tl = tl.append(makeItem("item\(i)"))
            #expect(tl._checkBalanceInvariant(),
                    "AVL invariant violated after insert #\(i)")
        }
        #expect(tl.count == 200)

        // Phase 2: 100 random removals (seeded) — check invariant after every one.
        // Collect current IDs and shuffle with the seeded RNG so the removal order
        // is deterministic but non-sequential (stresses rebalancing).
        var liveIds = (0..<200).map { "item\($0)" }
        liveIds.shuffle(using: &rng)

        for k in 0..<100 {
            let id = liveIds.removeLast()
            tl = tl.remove(id)
            #expect(tl._checkBalanceInvariant(),
                    "AVL invariant violated after removal #\(k) (id=\(id))")
        }
        #expect(tl.count == 100)

        // Final state must still satisfy the AVL invariant at every node.
        #expect(tl._checkBalanceInvariant())
    }

    @Test("getById is consistent with containsId")
    func getByIdConsistentWithContainsId() {
        let tl = buildTimeline(count: 20)

        for i in 0..<20 {
            let id = "\(i)"
            #expect(tl.containsId(id) == (tl.getById(id) != nil))
        }
        #expect(!tl.containsId("nonexistent"))
        #expect(tl.getById("nonexistent") == nil)
    }

    @Test("items with varying durations have correct cumulative start times")
    func varyingDurations() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 100))
            .append(makeItem("b", duration: 300))
            .append(makeItem("c", duration: 500))
            .append(makeItem("d", duration: 700))

        #expect(tl.startTimeOf("a") == 0)
        #expect(tl.startTimeOf("b") == 100)
        #expect(tl.startTimeOf("c") == 400) // 100 + 300
        #expect(tl.startTimeOf("d") == 900) // 100 + 300 + 500
        #expect(tl.totalDurationMicros == 1600) // 100 + 300 + 500 + 700
    }

    @Test("updateItem on first item propagates duration change")
    func updateFirstItem() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        let updated = tl.updateItem("a", makeItem("a", duration: 500_000))
        #expect(updated.totalDurationMicros == 2_500_000)
        #expect(updated.startTimeOf("b") == 500_000)
    }

    @Test("updateItem on last item propagates duration change")
    func updateLastItem() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))

        let updated = tl.updateItem("b", makeItem("b", duration: 500_000))
        #expect(updated.totalDurationMicros == 1_500_000)
        #expect(updated.startTimeOf("a") == 0)
    }

    @Test("zero-duration items are handled correctly")
    func zeroDurationItems() {
        // When appending "b" after zero-duration "a", insertAt(0, b) places "b"
        // before "a" because timeMicros(0) <= leftDuration(0) goes left.
        // So the order becomes [b, a] with b at time 0 and a at time 1_000_000.
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 0))
            .append(makeItem("b", duration: 1_000_000))

        #expect(tl.count == 2)
        #expect(tl.totalDurationMicros == 1_000_000)
        // "b" is placed before "a" because insert at time 0 goes left
        #expect(tl.startTimeOf("b") == 0)
        #expect(tl.startTimeOf("a") == 1_000_000) // zero-duration "a" after "b"
    }

    @Test("very large durations do not overflow")
    func largeDurations() {
        let hugeDuration: Int64 = 3_600_000_000 // 1 hour in microseconds
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: hugeDuration))
            .append(makeItem("b", duration: hugeDuration))

        #expect(tl.totalDurationMicros == 2 * hugeDuration)
        #expect(tl.startTimeOf("b") == hugeDuration)
    }
}
