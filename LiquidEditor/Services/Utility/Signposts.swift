// Signposts.swift
// LiquidEditor
//
// F0-3: Central os_signpost instrumentation per spec §10.7.
//
// Exposes a single `OSSignposter` per measured subsystem so Instruments
// Performance trace categories stay clean and comparable across runs.
//
// Usage (hot path — keep the interval stack balanced):
//
//   let id = Signposts.scrub.beginInterval("scrub", "clip=\(clipID)")
//   defer { Signposts.scrub.endInterval("scrub", id) }
//
// For one-off events:
//   Signposts.export.emitEvent("completed", "duration=\(duration)")

import os
import Foundation

// MARK: - Signposts

/// Namespaced signposter instances for each performance-instrumented
/// subsystem. Each uses a distinct `category` so Instruments can split
/// them into separate swimlanes.
enum Signposts {

    /// Timeline scrubbing — must stay under the 2ms cached / 50ms uncached
    /// budget per docs/PERFORMANCE.md.
    static let scrub = OSSignposter(
        subsystem: "com.liquideditor",
        category: "scrub"
    )

    /// Export pipeline — encoding, muxing, file-write phases.
    static let export = OSSignposter(
        subsystem: "com.liquideditor",
        category: "export"
    )

    /// Audio-waveform render + cache — target: cached=<1ms, uncached=<50ms
    /// per zoom bucket.
    static let waveform = OSSignposter(
        subsystem: "com.liquideditor",
        category: "waveform"
    )

    /// Video / histogram / vectorscope / RGB-parade sampling — target:
    /// 30Hz steady, 15Hz under thermal pressure.
    static let scope = OSSignposter(
        subsystem: "com.liquideditor",
        category: "scope"
    )

    /// Composition rebuild — target: <20ms on the background thread.
    static let composition = OSSignposter(
        subsystem: "com.liquideditor",
        category: "composition"
    )

    /// Proxy generation — low-QoS; not on the scrub / playback path.
    static let proxy = OSSignposter(
        subsystem: "com.liquideditor",
        category: "proxy"
    )
}
