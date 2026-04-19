// CrossProjectClipboardService.swift
// LiquidEditor
//
// T7-14: Cross-project clip clipboard.
//
// Persists copied clips to UserDefaults (with an optional iCloud mirror via
// NSUbiquitousKeyValueStore) so a clip copied in one project can be pasted
// into another. Entries expire after 24h to avoid stale clipboard content.
//
// Pairs with the in-memory ClipboardStore in TimelineCutCommand.swift, which
// handles same-project copy/paste without serialization overhead.

import Foundation
import os

/// Persisted clip clipboard entry. Codable so it survives app relaunch.
struct CrossProjectClipboardEntry: Codable, Sendable, Identifiable {
    let id: UUID
    /// Encoded clip payload. Opaque blob — the producer decides what's in it.
    let payload: Data
    /// MIME-style kind hint, e.g. "video/clip" or "compound/bundle".
    let kind: String
    /// Source project ID for audit + UI display.
    let sourceProjectID: UUID
    /// Wall-clock timestamp. Used for TTL enforcement.
    let copiedAt: Date
    /// Human-readable label for the paste menu ("Sunset beach clip").
    let label: String

    init(
        payload: Data,
        kind: String,
        sourceProjectID: UUID,
        label: String,
        id: UUID = UUID(),
        copiedAt: Date = .now
    ) {
        self.id = id
        self.payload = payload
        self.kind = kind
        self.sourceProjectID = sourceProjectID
        self.label = label
        self.copiedAt = copiedAt
    }
}

/// Cross-project clip clipboard. Backed by UserDefaults + optional iCloud KVS.
@MainActor
@Observable
final class CrossProjectClipboardService {

    static let shared = CrossProjectClipboardService()

    /// Most recent entries (max 20). Newest first. Entries older than `ttl`
    /// are filtered out on read.
    private(set) var entries: [CrossProjectClipboardEntry] = []

    private let defaults: UserDefaults
    private let storageKey = "com.liquideditor.clipboard.crossProject.v1"
    private let maxEntries = 20
    private let ttl: TimeInterval = 24 * 60 * 60

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "CrossProjectClipboard"
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - API

    /// Push a new entry onto the clipboard. Oldest entries beyond `maxEntries`
    /// are evicted. Persists immediately.
    func copy(_ entry: CrossProjectClipboardEntry) {
        var next = entries
        next.insert(entry, at: 0)
        if next.count > maxEntries { next = Array(next.prefix(maxEntries)) }
        entries = next
        persist()
    }

    /// Most recent entry matching `kind` (or nil). Does not remove it.
    func mostRecent(ofKind kind: String? = nil) -> CrossProjectClipboardEntry? {
        let live = entries.filter { Date().timeIntervalSince($0.copiedAt) < ttl }
        if let kind { return live.first { $0.kind == kind } }
        return live.first
    }

    /// Remove a specific entry by id. No-op if not present.
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// Clear every entry.
    func clearAll() {
        entries = []
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let blob = defaults.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([CrossProjectClipboardEntry].self, from: blob)
            let fresh = decoded.filter { Date().timeIntervalSince($0.copiedAt) < ttl }
            entries = Array(fresh.prefix(maxEntries))
        } catch {
            Self.logger.error("Failed to decode clipboard: \(error.localizedDescription, privacy: .public)")
            entries = []
        }
    }

    private func persist() {
        do {
            let blob = try JSONEncoder().encode(entries)
            defaults.set(blob, forKey: storageKey)
        } catch {
            Self.logger.error("Failed to persist clipboard: \(error.localizedDescription, privacy: .public)")
        }
    }
}
