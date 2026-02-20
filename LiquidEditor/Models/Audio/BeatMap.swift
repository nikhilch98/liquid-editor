import Foundation

// MARK: - BeatMap

/// Detected beats from audio analysis.
///
/// Contains beat timestamps, estimated tempo, and confidence.
/// Beat detection runs on the native side using spectral flux
/// onset detection and autocorrelation tempo estimation.
struct BeatMap: Codable, Equatable, Hashable, Sendable {
    /// Asset ID this beat map was generated from.
    let assetId: String

    /// Detected beat timestamps (microseconds, sorted ascending).
    let beats: [TimeMicros]

    /// Estimated tempo in BPM (beats per minute).
    let estimatedBPM: Double

    /// Confidence of tempo estimate (0.0 - 1.0).
    let confidence: Double

    /// Time signature numerator (e.g., 4 for 4/4).
    let timeSignatureNumerator: Int

    /// Time signature denominator (e.g., 4 for 4/4).
    let timeSignatureDenominator: Int

    init(
        assetId: String,
        beats: [TimeMicros],
        estimatedBPM: Double,
        confidence: Double = 0.0,
        timeSignatureNumerator: Int = 4,
        timeSignatureDenominator: Int = 4
    ) {
        // Validate that beats array is sorted ascending (required for binary search)
        precondition(beats.isEmpty || zip(beats, beats.dropFirst()).allSatisfy { $0 < $1 },
                     "beats array must be sorted in ascending order")

        self.assetId = assetId
        self.beats = beats
        self.estimatedBPM = estimatedBPM
        self.confidence = confidence
        self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator
    }

    /// Empty beat map.
    static let empty = BeatMap(
        assetId: "",
        beats: [],
        estimatedBPM: 0.0
    )

    /// Whether beats were detected.
    var hasBeats: Bool { !beats.isEmpty }

    /// Number of detected beats.
    var beatCount: Int { beats.count }

    /// Time signature as string (e.g., "4/4").
    var timeSignature: String {
        "\(timeSignatureNumerator)/\(timeSignatureDenominator)"
    }

    /// Get beat nearest to a given time (binary search).
    ///
    /// Returns the beat timestamp closest to `timeMicros`,
    /// or nil if no beats exist.
    func nearestBeat(to timeMicros: TimeMicros) -> TimeMicros? {
        guard !beats.isEmpty else { return nil }
        guard beats.count > 1 else { return beats[0] }

        // Binary search for closest beat
        var lo = 0
        var hi = beats.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if beats[mid] < timeMicros {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // Compare lo and lo-1 to find closest
        if lo == 0 { return beats[0] }
        let before = beats[lo - 1]
        let after = beats[lo]
        return abs(timeMicros - before) <= abs(after - timeMicros) ? before : after
    }

    /// Get beats within a time range (for visible region rendering).
    ///
    /// Uses binary search for efficient O(log n + k) where k = beats in range.
    func beatsInRange(start startMicros: TimeMicros, end endMicros: TimeMicros) -> [TimeMicros] {
        guard !beats.isEmpty else { return [] }

        // Binary search for start index
        var lo = 0
        var hi = beats.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if beats[mid] < startMicros {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // Collect beats in range
        var result: [TimeMicros] = []
        var i = lo
        while i < beats.count && beats[i] <= endMicros {
            result.append(beats[i])
            i += 1
        }
        return result
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case assetId
        case beats
        case estimatedBPM
        case confidence
        case timeSignatureNumerator
        case timeSignatureDenominator
    }
}
