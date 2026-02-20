import Testing
import Foundation
@testable import LiquidEditor

@Suite("GapClip Tests")
struct GapClipTests {

    // MARK: - Creation

    @Test("Creation with id and duration")
    func creation() {
        let gap = GapClip(id: "gap-1", durationMicroseconds: 1_000_000)
        #expect(gap.id == "gap-1")
        #expect(gap.durationMicroseconds == 1_000_000)
    }

    @Test("displayName is always Gap")
    func displayName() {
        let gap = GapClip(id: "g", durationMicroseconds: 500_000)
        #expect(gap.displayName == "Gap")
    }

    @Test("itemType is .gap")
    func itemType() {
        let gap = GapClip(id: "g", durationMicroseconds: 500_000)
        #expect(gap.itemType == .gap)
    }

    @Test("isGeneratorClip is true")
    func isGeneratorClip() {
        let gap = GapClip(id: "g", durationMicroseconds: 500_000)
        #expect(gap.isGeneratorClip == true)
    }

    @Test("isMediaClip is false")
    func isMediaClip() {
        let gap = GapClip(id: "g", durationMicroseconds: 500_000)
        #expect(gap.isMediaClip == false)
    }

    // MARK: - withDuration

    @Test("withDuration changes duration, preserves id")
    func withDuration() {
        let gap = GapClip(id: "gap-1", durationMicroseconds: 1_000_000)
        let updated = gap.withDuration(2_000_000)
        #expect(updated.id == "gap-1")
        #expect(updated.durationMicroseconds == 2_000_000)
    }

    // MARK: - with() Copy

    @Test("with() preserves all values when no changes")
    func withNoChanges() {
        let gap = GapClip(id: "g1", durationMicroseconds: 500_000)
        let copy = gap.with()
        #expect(copy == gap)
    }

    @Test("with() changes id")
    func withNewId() {
        let gap = GapClip(id: "g1", durationMicroseconds: 500_000)
        let updated = gap.with(id: "g2")
        #expect(updated.id == "g2")
        #expect(updated.durationMicroseconds == 500_000)
    }

    @Test("with() changes duration")
    func withNewDuration() {
        let gap = GapClip(id: "g1", durationMicroseconds: 500_000)
        let updated = gap.with(durationMicroseconds: 1_000_000)
        #expect(updated.id == "g1")
        #expect(updated.durationMicroseconds == 1_000_000)
    }

    // MARK: - duplicate

    @Test("duplicate creates new id but same duration")
    func duplicate() {
        let gap = GapClip(id: "original", durationMicroseconds: 750_000)
        let dup = gap.duplicate()
        #expect(dup.id != "original")
        #expect(!dup.id.isEmpty)
        #expect(dup.durationMicroseconds == 750_000)
    }

    // MARK: - splitAt

    @Test("splitAt produces correct left and right")
    func splitAtBasic() {
        let gap = GapClip(id: "g", durationMicroseconds: 1_000_000) // 1 second
        let result = gap.splitAt(400_000) // split at 400ms
        #expect(result != nil)

        let left = result!.left
        let right = result!.right

        #expect(left.durationMicroseconds == 400_000)
        #expect(right.durationMicroseconds == 600_000)
        // New IDs are generated
        #expect(left.id != gap.id)
        #expect(right.id != gap.id)
        #expect(left.id != right.id)
    }

    @Test("splitAt returns nil when left portion too small")
    func splitAtLeftTooSmall() {
        let gap = GapClip(id: "g", durationMicroseconds: 500_000)
        // 50ms < 100ms minimum
        let result = gap.splitAt(50_000)
        #expect(result == nil)
    }

    @Test("splitAt returns nil when right portion too small")
    func splitAtRightTooSmall() {
        let gap = GapClip(id: "g", durationMicroseconds: 500_000)
        // right would be 500_000 - 450_000 = 50_000 < 100_000 min
        let result = gap.splitAt(450_000)
        #expect(result == nil)
    }

    @Test("splitAt at exactly minimum boundary succeeds")
    func splitAtExactMinimum() {
        let gap = GapClip(id: "g", durationMicroseconds: 200_000) // exactly 2x minimum
        let result = gap.splitAt(100_000) // exactly at minimum
        #expect(result != nil)
        #expect(result!.left.durationMicroseconds == 100_000)
        #expect(result!.right.durationMicroseconds == 100_000)
    }

    @Test("splitAt returns nil when offset equals zero")
    func splitAtZero() {
        let gap = GapClip(id: "g", durationMicroseconds: 500_000)
        let result = gap.splitAt(0)
        #expect(result == nil) // 0 < 100_000 minimum
    }

    @Test("splitAt returns nil when offset equals total duration")
    func splitAtFullDuration() {
        let gap = GapClip(id: "g", durationMicroseconds: 500_000)
        let result = gap.splitAt(500_000)
        #expect(result == nil) // right = 0 < 100_000 minimum
    }

    @Test("splitAt preserves total duration")
    func splitAtPreservesTotalDuration() {
        let gap = GapClip(id: "g", durationMicroseconds: 1_500_000)
        let result = gap.splitAt(600_000)!
        let total = result.left.durationMicroseconds + result.right.durationMicroseconds
        #expect(total == 1_500_000)
    }

    @Test("Minimum duration enforcement is 100ms (100_000 microseconds)")
    func minDurationIs100ms() {
        let gap = GapClip(id: "g", durationMicroseconds: 200_000)
        // 99_999 < 100_000 -> should fail
        let result = gap.splitAt(99_999)
        #expect(result == nil)

        // 100_000 >= 100_000 -> should succeed
        let result2 = gap.splitAt(100_000)
        #expect(result2 != nil)
    }

    // MARK: - Codable Roundtrip

    @Test("Codable roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let gap = GapClip(id: "codec-gap", durationMicroseconds: 2_500_000)
        let data = try JSONEncoder().encode(gap)
        let decoded = try JSONDecoder().decode(GapClip.self, from: data)
        #expect(decoded.id == gap.id)
        #expect(decoded.durationMicroseconds == gap.durationMicroseconds)
        #expect(decoded == gap)
    }

    @Test("JSON uses correct coding keys")
    func jsonCodingKeys() throws {
        let gap = GapClip(id: "key-test", durationMicroseconds: 300_000)
        let data = try JSONEncoder().encode(gap)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["itemType"] as? String == "gap")
        #expect(json["id"] as? String == "key-test")
        #expect(json["durationMicros"] as? Int64 == 300_000)
        // Should not have raw property names
        #expect(json["durationMicroseconds"] == nil)
    }

    @Test("Decode from Dart-style JSON")
    func decodeDartJson() throws {
        let jsonString = """
        {
            "itemType": "gap",
            "id": "dart-gap",
            "durationMicros": 750000
        }
        """
        let data = jsonString.data(using: .utf8)!
        let gap = try JSONDecoder().decode(GapClip.self, from: data)
        #expect(gap.id == "dart-gap")
        #expect(gap.durationMicroseconds == 750_000)
    }

    // MARK: - Equatable & Hashable

    @Test("Equal gaps are equal")
    func equality() {
        let a = GapClip(id: "g1", durationMicroseconds: 500_000)
        let b = GapClip(id: "g1", durationMicroseconds: 500_000)
        #expect(a == b)
    }

    @Test("Different gaps are not equal")
    func inequality() {
        let a = GapClip(id: "g1", durationMicroseconds: 500_000)
        let b = GapClip(id: "g2", durationMicroseconds: 500_000)
        #expect(a != b)

        let c = GapClip(id: "g1", durationMicroseconds: 600_000)
        #expect(a != c)
    }

    @Test("Gaps can be used in Set")
    func setUsage() {
        let a = GapClip(id: "g1", durationMicroseconds: 500_000)
        let b = GapClip(id: "g2", durationMicroseconds: 500_000)
        let c = GapClip(id: "g1", durationMicroseconds: 500_000)
        let gapSet: Set<GapClip> = [a, b, c]
        #expect(gapSet.count == 2)
    }

    // MARK: - Sendable

    @Test("Sendable conformance")
    func sendable() async {
        let gap = GapClip(id: "sendable", durationMicroseconds: 1_000_000)
        let result = await Task.detached { gap.durationMicroseconds }.value
        #expect(result == 1_000_000)
    }
}
