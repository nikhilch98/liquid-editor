// SpeedProcessorProtocol.swift
// LiquidEditor
//
// Protocol for speed processing and time mapping.
// Enables dependency injection and testability.

import Foundation

// MARK: - SpeedProcessorProtocol

/// Protocol for computing time mappings from speed configurations.
///
/// Implementations calculate how source media time maps to output
/// timeline time, accounting for constant speed changes and speed
/// ramp keyframes.
///
/// References:
/// - `SpeedConfig` from Models/Speed/SpeedConfig.swift
/// - `SpeedKeyframe` from Models/Speed/SpeedConfig.swift
/// - `FrameBlendMode` from Models/Speed/SpeedConfig.swift
protocol SpeedProcessorProtocol: Sendable {
    /// Apply a speed configuration to calculate the time mapping.
    ///
    /// For constant speed, the mapping is a simple linear scale.
    /// For speed ramps, the mapping is computed via numerical
    /// integration of the keyframed speed curve.
    ///
    /// - Parameters:
    ///   - config: The speed configuration to apply.
    ///   - inputDuration: Duration of the source media in microseconds.
    /// - Returns: The computed speed mapping with output duration and time map.
    func processSpeed(
        config: SpeedConfig,
        inputDuration: TimeMicros
    ) -> SpeedMapping
}

// MARK: - SpeedMapping

/// Result of processing a speed configuration.
///
/// Contains the output duration and a sampled time map that describes
/// how input (source) time corresponds to output (timeline) time.
struct SpeedMapping: Sendable {
    /// Duration of the output after speed processing, in microseconds.
    let outputDuration: TimeMicros

    /// Sampled time mapping from input to output.
    ///
    /// Each entry maps an input time (source media position) to an
    /// output time (timeline position). Entries are sorted by inputTime.
    /// Intermediate values should be linearly interpolated.
    let timeMap: [SpeedTimeEntry]

    /// Whether the clip plays in reverse.
    let isReversed: Bool
}

// MARK: - SpeedTimeEntry

/// A single entry in a speed time map.
struct SpeedTimeEntry: Sendable {
    /// Time position in the source media (microseconds).
    let inputTime: TimeMicros

    /// Corresponding time position on the output timeline (microseconds).
    let outputTime: TimeMicros
}
