import Testing
import Foundation
@testable import LiquidEditor

@Suite("Time Types Tests")
struct TimeTypesTests {

    // MARK: - TimeMicros Utilities

    @Test("fromSeconds converts correctly")
    func fromSeconds() {
        let micros = TimeMicrosUtils.fromSeconds(1.5)
        #expect(micros == 1_500_000)
    }

    @Test("fromSeconds zero")
    func fromSecondsZero() {
        #expect(TimeMicrosUtils.fromSeconds(0) == 0)
    }

    @Test("fromMilliseconds converts correctly")
    func fromMilliseconds() {
        let micros = TimeMicrosUtils.fromMilliseconds(500)
        #expect(micros == 500_000)
    }

    // MARK: - TimeMicros Extensions

    @Test("toSeconds converts correctly")
    func toSeconds() {
        let micros: TimeMicros = 2_500_000
        #expect(micros.toSeconds == 2.5)
    }

    @Test("toMilliseconds converts correctly")
    func toMilliseconds() {
        let micros: TimeMicros = 1_500_000
        #expect(micros.toMilliseconds == 1500.0)
    }

    @Test("toTimecode formats correctly at 30fps")
    func toTimecode30fps() {
        // 1 minute, 30 seconds, 15 frames at 30fps
        let fps30 = Rational.fps30
        let frames = 1 * 60 * 30 + 30 * 30 + 15
        let micros = framesToTime(frames, frameRate: fps30)
        let tc = micros.toTimecode(fps30)
        #expect(tc == "00:01:30:15")
    }

    @Test("toTimecode zero time")
    func toTimecodeZero() {
        let tc: TimeMicros = 0
        #expect(tc.toTimecode(Rational.fps30) == "00:00:00:00")
    }

    @Test("simpleTimeString formats correctly")
    func simpleTimeString() {
        let micros: TimeMicros = 125_500_000 // 2m 5.5s
        let str = micros.simpleTimeString
        #expect(str == "02:05.50")
    }

    @Test("simpleTimeString zero time")
    func simpleTimeStringZero() {
        let micros: TimeMicros = 0
        #expect(micros.simpleTimeString == "00:00.00")
    }

    // MARK: - Frame/Time Conversion Functions

    @Test("timeToFrames at 30fps")
    func timeToFrames30fps() {
        let fps = Rational.fps30
        let micros: TimeMicros = 1_000_000 // 1 second
        let frames = timeToFrames(micros, frameRate: fps)
        #expect(frames == 30)
    }

    @Test("framesToTime at 30fps")
    func framesToTime30fps() {
        let fps = Rational.fps30
        let micros = framesToTime(30, frameRate: fps)
        #expect(micros == 1_000_000) // 1 second
    }

    @Test("Frame/time roundtrip exact when 1M divisible by fps")
    func frameTimeRoundtripExact() {
        // 25fps: 1_000_000 / 25 = 40000 exactly
        let fps = Rational.fps25
        for frame in [0, 1, 10, 24, 25, 100, 1000] {
            let micros = framesToTime(frame, frameRate: fps)
            let back = timeToFrames(micros, frameRate: fps)
            #expect(back == frame, "Frame \(frame) failed roundtrip at 25fps")
        }
    }

    @Test("Frame/time roundtrip within 1 frame for all rates")
    func frameTimeRoundtripApproximate() {
        // Integer division truncation means roundtrip may lose 1 frame.
        // This matches Dart's ~/ operator behavior.
        for fps in [Rational.fps30, .fps60, .fps29_97, .fps23_976] {
            for frame in [0, 1, 29, 30, 100, 1000] {
                let micros = framesToTime(frame, frameRate: fps)
                let back = timeToFrames(micros, frameRate: fps)
                #expect(back == frame || back == frame - 1,
                        "Frame \(frame) at \(fps.frameRateString)")
            }
        }
    }

    @Test("timeToFrames floors partial frames")
    func timeToFramesFloors() {
        let fps = Rational.fps30
        // Half a frame past frame 5
        let micros = framesToTime(5, frameRate: fps) + fps.microsecondsPerFrame / 2
        let frames = timeToFrames(micros, frameRate: fps)
        #expect(frames == 5) // should floor, not round
    }
}

@Suite("TimeRange Tests")
struct TimeRangeTests {

    // MARK: - Basic Creation

    @Test("Creates range with start and end")
    func basicCreation() {
        let range = TimeRange(1_000_000, 5_000_000)
        #expect(range.start == 1_000_000)
        #expect(range.end == 5_000_000)
    }

    @Test("Duration computed correctly")
    func duration() {
        let range = TimeRange(1_000_000, 5_000_000)
        #expect(range.duration == 4_000_000)
    }

    @Test("fromDuration factory")
    func fromDuration() {
        let range = TimeRange.fromDuration(start: 1_000_000, duration: 3_000_000)
        #expect(range.start == 1_000_000)
        #expect(range.end == 4_000_000)
    }

    // MARK: - Contains

    @Test("Contains is inclusive start, exclusive end")
    func contains() {
        let range = TimeRange(100, 200)
        #expect(range.contains(100) == true)  // inclusive start
        #expect(range.contains(150) == true)
        #expect(range.contains(200) == false) // exclusive end
        #expect(range.contains(50) == false)
        #expect(range.contains(250) == false)
    }

    @Test("ContainsInclusive includes both ends")
    func containsInclusive() {
        let range = TimeRange(100, 200)
        #expect(range.containsInclusive(100) == true)
        #expect(range.containsInclusive(200) == true) // inclusive end
        #expect(range.containsInclusive(50) == false)
    }

    // MARK: - Overlap Detection

    @Test("Overlaps detects partial overlap")
    func overlaps() {
        let a = TimeRange(0, 100)
        let b = TimeRange(50, 150)
        #expect(a.overlaps(b) == true)
        #expect(b.overlaps(a) == true)
    }

    @Test("Non-overlapping ranges")
    func noOverlap() {
        let a = TimeRange(0, 100)
        let b = TimeRange(100, 200) // adjacent, not overlapping
        #expect(a.overlaps(b) == false)
    }

    @Test("FullyContains checks containment")
    func fullyContains() {
        let outer = TimeRange(0, 200)
        let inner = TimeRange(50, 150)
        #expect(outer.fullyContains(inner) == true)
        #expect(inner.fullyContains(outer) == false)
    }

    // MARK: - Set Operations

    @Test("Intersection of overlapping ranges")
    func intersection() {
        let a = TimeRange(0, 100)
        let b = TimeRange(50, 150)
        let i = a.intersection(b)
        #expect(i != nil)
        #expect(i?.start == 50)
        #expect(i?.end == 100)
    }

    @Test("Intersection returns nil for non-overlapping")
    func intersectionNil() {
        let a = TimeRange(0, 50)
        let b = TimeRange(100, 200)
        #expect(a.intersection(b) == nil)
    }

    @Test("Union of ranges")
    func union() {
        let a = TimeRange(10, 50)
        let b = TimeRange(30, 80)
        let u = a.union(b)
        #expect(u.start == 10)
        #expect(u.end == 80)
    }

    // MARK: - Transform Operations

    @Test("Expand range by amount")
    func expand() {
        let range = TimeRange(100, 200)
        let expanded = range.expand(by: 10)
        #expect(expanded.start == 90)
        #expect(expanded.end == 210)
    }

    @Test("Shift range by delta")
    func shift() {
        let range = TimeRange(100, 200)
        let shifted = range.shift(by: 50)
        #expect(shifted.start == 150)
        #expect(shifted.end == 250)
    }

    // MARK: - Codable

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = TimeRange(1_000_000, 5_000_000)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimeRange.self, from: data)
        #expect(decoded == original)
    }

    @Test("JSON keys are correct")
    func jsonKeys() throws {
        let range = TimeRange(100, 200)
        let data = try JSONEncoder().encode(range)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["start"] as? Int64 == 100)
        #expect(json["end"] as? Int64 == 200)
    }

    // MARK: - Equatable & Hashable

    @Test("Equality works correctly")
    func equality() {
        let a = TimeRange(100, 200)
        let b = TimeRange(100, 200)
        let c = TimeRange(100, 300)
        #expect(a == b)
        #expect(a != c)
    }
}
