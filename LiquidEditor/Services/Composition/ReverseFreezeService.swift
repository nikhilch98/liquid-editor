// ReverseFreezeService.swift
// LiquidEditor
//
// TD8-13: Render-action service for "Reverse clip" and "Freeze frame".
//
// Per docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §8.13.
//
// This is a **stub** — the production implementation will use
// `AVAssetReader` + `AVAssetWriter` to (a) decode frames, reverse them
// in memory / via on-disk buffering, and re-encode; (b) snapshot a
// single frame and re-encode it for `duration` seconds. Both are
// CPU/GPU-heavy operations — they are expected to run off the main
// actor once implemented. For now we expose a `progress` signal the
// UI can bind to and simulate work with `Task.sleep` so the
// progress overlay is testable end-to-end.
//
// Concurrency model:
//  - `@MainActor @Observable` so SwiftUI progress HUDs can observe
//    `progress` without hops.
//  - The two public `async throws` methods stay on the main actor and
//    simulate progress with `Task.sleep`. Once the real reader/writer
//    pipeline lands, the heavy work will be dispatched to a
//    background task and progress will be published back via
//    `await MainActor.run { self.progress = … }`.

import AVFoundation
import Foundation

// MARK: - ReverseFreezeError

/// Errors surfaced by `ReverseFreezeService`.
enum ReverseFreezeError: Error, Sendable {
    /// Input URL is missing or unreadable.
    case missingSource
    /// Underlying AVFoundation failure.
    case exportFailed(String)
    /// Caller-requested cancellation.
    case cancelled
}

// MARK: - ReverseFreezeService

/// Drives "Reverse clip" and "Freeze frame" render actions.
///
/// Observable `progress` lets the UI show a HUD during the
/// (currently simulated) render. Both methods return a URL that the
/// caller will splice back into the timeline; today they return the
/// original URL unchanged with a TODO marker in the log.
@Observable
@MainActor
final class ReverseFreezeService {

    // MARK: - Observable State

    /// Progress, `0.0 … 1.0`. Reset to 0 at the start of each call and
    /// advanced monotonically until completion.
    private(set) var progress: Double = 0.0

    /// Whether a render is currently in progress.
    private(set) var isRendering: Bool = false

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Reverse an entire clip and return a URL pointing at the reversed
    /// asset.
    ///
    /// - Parameter clipURL: Source clip URL.
    /// - Returns: URL of the reversed clip (currently the input URL
    ///   unchanged — see TODO).
    /// - Throws: ``ReverseFreezeError`` on failure.
    ///
    /// TODO(TD8-13): Implement with `AVAssetReader` to decode all
    /// video samples, buffer to disk in chunks, then re-encode with
    /// `AVAssetWriter` in reverse presentation order. Apply the
    /// reversed audio track similarly (or mute if reverse-playback
    /// audio is undesired). Report progress from the reader's
    /// `copyNextSampleBuffer` loop.
    func reverse(clipURL: URL) async throws -> URL {
        try await runSimulatedRender(source: clipURL, label: "reverse")
    }

    /// Replace the content of a clip with a repeated still frame
    /// captured at `time`, lasting `duration` seconds.
    ///
    /// - Parameters:
    ///   - clipURL: Source clip URL.
    ///   - time:    Timestamp (in microseconds) of the frame to freeze.
    ///   - duration: Duration in seconds of the resulting frozen clip.
    /// - Returns: URL of the frozen clip (currently the input URL
    ///   unchanged — see TODO).
    /// - Throws: ``ReverseFreezeError`` on failure.
    ///
    /// TODO(TD8-13): Implement using `AVAssetImageGenerator` to extract
    /// the still at `time`, then write a new MP4 via `AVAssetWriter`
    /// containing `duration * frameRate` copies of that frame.
    func freezeFrame(clipURL: URL,
                     at time: TimeMicros,
                     duration: TimeInterval) async throws -> URL {
        _ = time
        _ = duration
        return try await runSimulatedRender(source: clipURL, label: "freezeFrame")
    }

    /// Reset progress to zero (e.g. when the HUD is dismissed).
    func resetProgress() {
        progress = 0.0
        isRendering = false
    }

    // MARK: - Private

    /// Shared helper that simulates a multi-stage render by advancing
    /// `progress` in discrete steps with `Task.sleep` between them.
    /// Useful for exercising the progress overlay UI before the real
    /// reader/writer pipeline lands.
    private func runSimulatedRender(source: URL,
                                    label: String) async throws -> URL {
        _ = label
        // Validate the URL points at something — a missing file is the
        // most common programmer error we can surface early.
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ReverseFreezeError.missingSource
        }

        isRendering = true
        progress = 0.0
        defer { isRendering = false }

        let steps = 10
        for step in 1...steps {
            // 40ms × 10 ≈ 400ms total — enough to see the HUD animate.
            try await Task.sleep(nanoseconds: 40_000_000)
            progress = Double(step) / Double(steps)
        }

        // TODO(TD8-13): Swap this stub return for the real reader/writer
        // output URL once the pipeline is implemented.
        return source
    }
}
