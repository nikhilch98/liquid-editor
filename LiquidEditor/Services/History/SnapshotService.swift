// SnapshotService.swift
// LiquidEditor
//
// P1-16: Capture thumbnail + diff-label at every committed edit. Backs
// the Undo History Scrubber (§9.8) and the Project Settings "Snapshots"
// entry.
//
// Scope:
// - On each committed edit, caller invokes `record(label:thumbnail:)`.
// - Snapshots are stored in memory (recent-first) and persisted per
//   project as a sidecar file (caller's responsibility to flush).
// - Retention policy per D0-4: soft cap + aged thinning; this service
//   keeps the most recent N, evicts oldest first.

import CoreGraphics
import Foundation
import Observation

// MARK: - Snapshot

struct Snapshot: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let label: String
    let thumbnailURL: URL?
    let timelineSignature: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        label: String,
        thumbnailURL: URL?,
        timelineSignature: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.thumbnailURL = thumbnailURL
        self.timelineSignature = timelineSignature
    }
}

// MARK: - SnapshotService

/// Observable snapshot store. One instance per open project.
@Observable
@MainActor
final class SnapshotService {

    // MARK: - State

    /// Snapshots newest-first.
    private(set) var snapshots: [Snapshot] = []

    /// Cap from D0-4; default 200 per spec note.
    var maxSnapshots: Int

    // MARK: - Init

    init(maxSnapshots: Int = 200) {
        self.maxSnapshots = maxSnapshots
    }

    // MARK: - API

    /// Record a new snapshot at the head. Evicts oldest when over cap.
    func record(label: String, thumbnailURL: URL?, timelineSignature: String) {
        let snap = Snapshot(
            label: label,
            thumbnailURL: thumbnailURL,
            timelineSignature: timelineSignature
        )
        snapshots.insert(snap, at: 0)
        applyRetention()
    }

    /// Drop all snapshots (used on hard project reset).
    func clear() {
        snapshots.removeAll()
    }

    /// Look up a snapshot by ID (for Restore / Branch flows).
    func snapshot(withID id: UUID) -> Snapshot? {
        snapshots.first { $0.id == id }
    }

    // MARK: - Retention

    /// Simple eviction — keep the N most-recent. Aged-thinning strategy
    /// lives here later per D0-4 resolution.
    private func applyRetention() {
        if snapshots.count > maxSnapshots {
            snapshots = Array(snapshots.prefix(maxSnapshots))
        }
    }
}
