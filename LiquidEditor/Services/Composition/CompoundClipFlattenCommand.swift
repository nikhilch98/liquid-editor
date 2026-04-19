// CompoundClipFlattenCommand.swift
// LiquidEditor
//
// T7-39 (Premium UI §7.23): Flatten a compound clip to a single video
// file on disk. The user triggers this from the compound's context
// menu when they want to bake the inner timeline into a standalone
// asset (for export, hand-off, or to break the live link to the inner
// edit).
//
// The implementation needs to:
//  1. Build an AVComposition from `compoundClip`'s inner timeline.
//  2. Hook `MultiTrackCompositor` as the custom video compositor.
//  3. Run an AVAssetExportSession to a temp URL in Caches/.
//  4. Return the URL for the caller to import back into the timeline.
//
// The composition wiring is non-trivial and shares code with the
// export path (`ExportService`). This file establishes the async API
// with a guarded stub so the Flatten menu item compiles today.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.23
//       (compound clip render / flatten).

import AVFoundation
import Foundation

// MARK: - CompoundClipFlattenCommand

/// Stateless command that flattens a compound clip. `@MainActor` because
/// it coordinates with `MultiTrackCompositor` which holds main-actor
/// state (Metal texture pool, compositor registration).
@MainActor
enum CompoundClipFlattenCommand {

    // MARK: - Errors

    /// Errors that can occur while flattening.
    enum FlattenError: Error, Sendable {
        /// The compound had no member clips to flatten.
        case emptyCompound
        /// The export session failed or produced no output.
        case exportFailed(String)
    }

    // MARK: - Flatten

    /// Flatten `compoundClip` into a single video file using `compositor`.
    ///
    /// - Parameters:
    ///   - compoundClip: The compound to flatten.
    ///   - compositor: The shared `MultiTrackCompositor` to use for
    ///     rendering.
    /// - Returns: The URL of the produced video file (in Caches/).
    /// - Throws: `FlattenError` when the compound is empty or the
    ///   export pipeline fails.
    static func flatten(
        compoundClip: CompoundClip,
        compositor: MultiTrackCompositor
    ) async throws -> URL {
        guard !compoundClip.memberIDs.isEmpty else {
            throw FlattenError.emptyCompound
        }
        _ = compositor

        // TODO: build AVComposition from the compound's inner timeline,
        // register `MultiTrackCompositor` as the custom video compositor,
        // and run AVAssetExportSession to the returned URL. Share
        // buffer-pool config with ExportService to avoid duplication.
        let filename = "compound-\(compoundClip.id).mov"
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        return url
    }
}
