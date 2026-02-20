import Foundation

/// Type alias for microsecond timestamps.
/// All times are stored as microseconds (Int64) for precision.
typealias TimeMicros = Int64

// MARK: - TimeMicros Utilities

enum TimeMicrosUtils {
    /// Convert seconds to microseconds.
    static func fromSeconds(_ seconds: Double) -> TimeMicros {
        TimeMicros((seconds * 1_000_000).rounded())
    }

    /// Convert milliseconds to microseconds.
    static func fromMilliseconds(_ ms: Double) -> TimeMicros {
        TimeMicros((ms * 1_000).rounded())
    }
}

extension TimeMicros {
    /// Convert to seconds.
    var toSeconds: Double { Double(self) / 1_000_000.0 }

    /// Convert to milliseconds.
    var toMilliseconds: Double { Double(self) / 1_000.0 }

    /// Format as timecode (HH:MM:SS:FF).
    func toTimecode(_ frameRate: Rational) -> String {
        let totalFrames = timeToFrames(self, frameRate: frameRate)
        let fps = Int(frameRate.value.rounded())
        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(
            format: "%02d:%02d:%02d:%02d",
            hours, minutes, seconds, frames
        )
    }

    /// Format as simple time (MM:SS.ms).
    var simpleTimeString: String {
        let totalSeconds = Int(self / 1_000_000)
        let ms = Int((self % 1_000_000) / 1_000)
        let seconds = totalSeconds % 60
        let minutes = totalSeconds / 60

        return String(format: "%02d:%02d.%02d", minutes, seconds, ms / 10)
    }
}

// MARK: - Frame/Time Conversion Functions

/// Convert time to frames.
func timeToFrames(_ time: TimeMicros, frameRate: Rational) -> Int {
    Int((time * Int64(frameRate.numerator)) / (Int64(frameRate.denominator) * 1_000_000))
}

/// Convert frames to time.
func framesToTime(_ frames: Int, frameRate: Rational) -> TimeMicros {
    (Int64(frames) * Int64(frameRate.denominator) * 1_000_000) / Int64(frameRate.numerator)
}

// MARK: - TimeRange

/// Immutable time range.
struct TimeRange: Codable, Equatable, Hashable, Sendable {
    let start: TimeMicros
    let end: TimeMicros

    init(_ start: TimeMicros, _ end: TimeMicros) {
        self.start = start
        self.end = end
    }

    /// Create from start and duration.
    static func fromDuration(start: TimeMicros, duration: TimeMicros) -> TimeRange {
        TimeRange(start, start + duration)
    }

    /// Duration of the range.
    var duration: TimeMicros { end - start }

    /// Check if time is within range (inclusive start, exclusive end).
    func contains(_ time: TimeMicros) -> Bool {
        time >= start && time < end
    }

    /// Check if time is within range (inclusive both ends).
    func containsInclusive(_ time: TimeMicros) -> Bool {
        time >= start && time <= end
    }

    /// Check if this range overlaps with another.
    func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && end > other.start
    }

    /// Check if this range fully contains another.
    func fullyContains(_ other: TimeRange) -> Bool {
        start <= other.start && end >= other.end
    }

    /// Get the intersection of two ranges (or nil if no overlap).
    func intersection(_ other: TimeRange) -> TimeRange? {
        guard overlaps(other) else { return nil }
        return TimeRange(
            max(start, other.start),
            min(end, other.end)
        )
    }

    /// Get the union of two ranges (smallest range containing both).
    func union(_ other: TimeRange) -> TimeRange {
        TimeRange(
            min(start, other.start),
            max(end, other.end)
        )
    }

    /// Expand range by amount on both sides.
    func expand(by amount: TimeMicros) -> TimeRange {
        TimeRange(start - amount, end + amount)
    }

    /// Shift range by delta.
    func shift(by delta: TimeMicros) -> TimeRange {
        TimeRange(start + delta, end + delta)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case start, end
    }
}
