import CoreMedia

/// Custom Codable conformance for CMTime.
///
/// CMTime is NOT natively Codable. We encode it as Double seconds
/// to maintain backward compatibility with Dart JSON (which stores
/// durations as double seconds or microsecond integers).
///
/// ## Timescale Choice
/// We use a timescale of 600 (common video timescale) which:
/// - Evenly divides common frame rates (24, 25, 30, 60, 120)
/// - Balances precision vs granularity for video editing
/// - Matches AVFoundation's default for many codecs
/// - Prevents precision loss during conversions
extension CMTime {
    /// Normalized to standard timescale for consistent dictionary keys.
    var normalized: CMTime {
        CMTime(value: CMTimeValue(seconds * 600), timescale: 600)
    }
}

/// Wrapper for encoding/decoding CMTime as Double seconds in JSON.
struct CodableCMTime: Codable, Equatable, Hashable, Sendable {
    let time: CMTime

    init(_ time: CMTime) {
        self.time = time
    }

    init(seconds: Double) {
        self.time = CMTime(seconds: seconds, preferredTimescale: 600)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let seconds = try container.decode(Double.self)
        time = CMTime(seconds: seconds, preferredTimescale: 600)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(time.seconds)
    }

    static func == (lhs: CodableCMTime, rhs: CodableCMTime) -> Bool {
        CMTimeCompare(lhs.time, rhs.time) == 0
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(time.seconds)
    }
}
