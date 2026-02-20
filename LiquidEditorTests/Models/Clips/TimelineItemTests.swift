import Testing
import Foundation
@testable import LiquidEditor

// MARK: - TimelineItemType Tests

@Suite("TimelineItemType Tests")
struct TimelineItemTypeTests {

    @Test("all raw values are correct")
    func rawValues() {
        #expect(TimelineItemType.video.rawValue == "video")
        #expect(TimelineItemType.image.rawValue == "image")
        #expect(TimelineItemType.audio.rawValue == "audio")
        #expect(TimelineItemType.gap.rawValue == "gap")
        #expect(TimelineItemType.color.rawValue == "color")
        #expect(TimelineItemType.text.rawValue == "text")
        #expect(TimelineItemType.sticker.rawValue == "sticker")
        #expect(TimelineItemType.effect.rawValue == "effect")
    }

    @Test("showsThumbnails is true only for video and image")
    func showsThumbnails() {
        #expect(TimelineItemType.video.showsThumbnails == true)
        #expect(TimelineItemType.image.showsThumbnails == true)
        #expect(TimelineItemType.audio.showsThumbnails == false)
        #expect(TimelineItemType.gap.showsThumbnails == false)
        #expect(TimelineItemType.text.showsThumbnails == false)
        #expect(TimelineItemType.sticker.showsThumbnails == false)
        #expect(TimelineItemType.color.showsThumbnails == false)
    }

    @Test("showsWaveform is true only for audio")
    func showsWaveform() {
        #expect(TimelineItemType.audio.showsWaveform == true)
        #expect(TimelineItemType.video.showsWaveform == false)
        #expect(TimelineItemType.image.showsWaveform == false)
    }

    @Test("Codable round-trip for all cases")
    func codableRoundTrip() throws {
        let types: [TimelineItemType] = [.video, .image, .audio, .gap, .color, .text, .sticker, .effect]
        for t in types {
            let data = try JSONEncoder().encode(t)
            let decoded = try JSONDecoder().decode(TimelineItemType.self, from: data)
            #expect(decoded == t)
        }
    }
}

// MARK: - TimelineItemDecoder Tests

@Suite("TimelineItemDecoder Tests")
struct TimelineItemDecoderTests {

    @Test("decode unknown type falls back to GapClip")
    func decodeUnknownType() throws {
        let json: [String: Any] = [
            "itemType": "future_type",
            "id": "unknown-1",
            "durationMicros": Int64(2_000_000)
        ]
        let decoded = try TimelineItemDecoder.decode(from: json)
        #expect(decoded.id == "unknown-1")
        #expect(decoded.durationMicroseconds == 2_000_000)
    }

    @Test("decode missing itemType falls back to GapClip")
    func decodeMissingType() throws {
        let json: [String: Any] = [
            "id": "no-type",
            "durationMicros": 1_000_000
        ]
        let decoded = try TimelineItemDecoder.decode(from: json)
        #expect(decoded.id == "no-type")
        #expect(decoded.durationMicroseconds == 1_000_000)
    }

    @Test("decode gap type")
    func decodeGapType() throws {
        let json: [String: Any] = [
            "itemType": "gap",
            "id": "gap-1",
            "durationMicros": 500_000
        ]
        let decoded = try TimelineItemDecoder.decode(from: json)
        #expect(decoded.id == "gap-1")
        #expect(decoded.durationMicroseconds == 500_000)
    }
}
