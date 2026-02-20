import Testing
import Foundation
@testable import LiquidEditor

@Suite("BeatMap Tests")
struct BeatMapTests {

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let beatMap = BeatMap(
            assetId: "asset-1",
            beats: [1_000_000, 2_000_000],
            estimatedBPM: 120.0
        )
        #expect(beatMap.assetId == "asset-1")
        #expect(beatMap.beats.count == 2)
        #expect(beatMap.estimatedBPM == 120.0)
        #expect(beatMap.confidence == 0.0)
        #expect(beatMap.timeSignatureNumerator == 4)
        #expect(beatMap.timeSignatureDenominator == 4)
    }

    @Test("creation with custom values")
    func creationCustom() {
        let beatMap = BeatMap(
            assetId: "song-2",
            beats: [500_000, 1_000_000, 1_500_000],
            estimatedBPM: 140.0,
            confidence: 0.95,
            timeSignatureNumerator: 3,
            timeSignatureDenominator: 4
        )
        #expect(beatMap.assetId == "song-2")
        #expect(beatMap.beats.count == 3)
        #expect(beatMap.estimatedBPM == 140.0)
        #expect(beatMap.confidence == 0.95)
        #expect(beatMap.timeSignatureNumerator == 3)
        #expect(beatMap.timeSignatureDenominator == 4)
    }

    // MARK: - Static Properties

    @Test("empty beat map has no beats")
    func emptyBeatMap() {
        let empty = BeatMap.empty
        #expect(empty.assetId == "")
        #expect(empty.beats.isEmpty)
        #expect(empty.estimatedBPM == 0.0)
        #expect(empty.hasBeats == false)
        #expect(empty.beatCount == 0)
    }

    // MARK: - Computed Properties

    @Test("hasBeats returns correct value")
    func hasBeats() {
        let withBeats = BeatMap(assetId: "a", beats: [100], estimatedBPM: 120)
        #expect(withBeats.hasBeats == true)

        let noBeats = BeatMap(assetId: "b", beats: [], estimatedBPM: 0)
        #expect(noBeats.hasBeats == false)
    }

    @Test("beatCount returns correct count")
    func beatCount() {
        let map = BeatMap(assetId: "a", beats: [1, 2, 3, 4, 5], estimatedBPM: 120)
        #expect(map.beatCount == 5)
    }

    @Test("timeSignature returns formatted string")
    func timeSignature() {
        let map44 = BeatMap(assetId: "a", beats: [], estimatedBPM: 120)
        #expect(map44.timeSignature == "4/4")

        let map34 = BeatMap(
            assetId: "a", beats: [], estimatedBPM: 120,
            timeSignatureNumerator: 3, timeSignatureDenominator: 4
        )
        #expect(map34.timeSignature == "3/4")
    }

    // MARK: - nearestBeat

    @Test("nearestBeat returns nil for empty beats")
    func nearestBeatEmpty() {
        let map = BeatMap.empty
        #expect(map.nearestBeat(to: 500_000) == nil)
    }

    @Test("nearestBeat returns sole beat for single-beat map")
    func nearestBeatSingle() {
        let map = BeatMap(assetId: "a", beats: [1_000_000], estimatedBPM: 60)
        #expect(map.nearestBeat(to: 500_000) == 1_000_000)
        #expect(map.nearestBeat(to: 2_000_000) == 1_000_000)
    }

    @Test("nearestBeat returns closest beat")
    func nearestBeatMultiple() {
        let beats: [TimeMicros] = [1_000_000, 2_000_000, 3_000_000, 4_000_000]
        let map = BeatMap(assetId: "a", beats: beats, estimatedBPM: 60)

        #expect(map.nearestBeat(to: 900_000) == 1_000_000)
        #expect(map.nearestBeat(to: 1_000_000) == 1_000_000)
        #expect(map.nearestBeat(to: 1_400_000) == 1_000_000)
        #expect(map.nearestBeat(to: 1_600_000) == 2_000_000)
        #expect(map.nearestBeat(to: 2_500_000) == 2_000_000)  // Tie goes to before
        #expect(map.nearestBeat(to: 3_800_000) == 4_000_000)
    }

    @Test("nearestBeat edge: before first beat")
    func nearestBeatBeforeFirst() {
        let map = BeatMap(assetId: "a", beats: [1_000_000, 2_000_000], estimatedBPM: 60)
        #expect(map.nearestBeat(to: 0) == 1_000_000)
    }

    @Test("nearestBeat edge: after last beat")
    func nearestBeatAfterLast() {
        let map = BeatMap(assetId: "a", beats: [1_000_000, 2_000_000], estimatedBPM: 60)
        #expect(map.nearestBeat(to: 10_000_000) == 2_000_000)
    }

    // MARK: - beatsInRange

    @Test("beatsInRange returns empty for empty map")
    func beatsInRangeEmpty() {
        let map = BeatMap.empty
        #expect(map.beatsInRange(start: 0, end: 1_000_000).isEmpty)
    }

    @Test("beatsInRange returns beats within range")
    func beatsInRangeNormal() {
        let beats: [TimeMicros] = [1_000_000, 2_000_000, 3_000_000, 4_000_000, 5_000_000]
        let map = BeatMap(assetId: "a", beats: beats, estimatedBPM: 60)

        let result = map.beatsInRange(start: 2_000_000, end: 4_000_000)
        #expect(result == [2_000_000, 3_000_000, 4_000_000])
    }

    @Test("beatsInRange returns empty when no beats in range")
    func beatsInRangeNone() {
        let beats: [TimeMicros] = [1_000_000, 5_000_000]
        let map = BeatMap(assetId: "a", beats: beats, estimatedBPM: 60)

        let result = map.beatsInRange(start: 2_000_000, end: 4_000_000)
        #expect(result.isEmpty)
    }

    @Test("beatsInRange includes boundary beats")
    func beatsInRangeBoundary() {
        let beats: [TimeMicros] = [1_000_000, 2_000_000, 3_000_000]
        let map = BeatMap(assetId: "a", beats: beats, estimatedBPM: 60)

        let result = map.beatsInRange(start: 1_000_000, end: 3_000_000)
        #expect(result == [1_000_000, 2_000_000, 3_000_000])
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = BeatMap(
            assetId: "song-test",
            beats: [500_000, 1_000_000, 1_500_000],
            estimatedBPM: 128.5,
            confidence: 0.87,
            timeSignatureNumerator: 3,
            timeSignatureDenominator: 8
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BeatMap.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Equatable / Hashable

    @Test("equal beat maps are equal")
    func equality() {
        let a = BeatMap(assetId: "a", beats: [1, 2], estimatedBPM: 120)
        let b = BeatMap(assetId: "a", beats: [1, 2], estimatedBPM: 120)
        #expect(a == b)
    }

    @Test("different beat maps are not equal")
    func inequality() {
        let a = BeatMap(assetId: "a", beats: [1, 2], estimatedBPM: 120)
        let b = BeatMap(assetId: "b", beats: [1, 2], estimatedBPM: 120)
        #expect(a != b)
    }
}
