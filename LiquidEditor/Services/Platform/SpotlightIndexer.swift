// SpotlightIndexer.swift
// LiquidEditor
//
// OS17-4: CoreSpotlight indexing per spec §10.10.3.
//
// Each project gets one CSSearchableItem with:
// - title            -> project name
// - contentDescription -> "N clips · MM:SS · <last-edited>"
// - thumbnailData    -> PNG representation of Project.thumbnail
// - keywords         -> collection names + tags
// - contentType      -> public.movie-editing-project
//
// Taps on Spotlight results route through DeepLinkRouter using the
// `liquideditor://open?project=<id>` scheme (OS17-3).
//
// Index updates are debounced to at most once every 10s after an edit
// commit, and trashed projects are removed via `removeItems(ids:)`.

import CoreSpotlight
import Foundation
import Observation
import UniformTypeIdentifiers

// MARK: - SpotlightIndexer

/// Actor-bounded wrapper around CSSearchableIndex with debounce.
@Observable
@MainActor
final class SpotlightIndexer {

    // MARK: - State

    /// Debounce window — Spotlight should update at most once per this
    /// interval per spec §10.10.3.
    let debounceInterval: TimeInterval

    /// Pending deadline for the current debounce timer.
    private var debounceTask: Task<Void, Never>?

    /// Items queued up for the next flush.
    private var pendingItems: [CSSearchableItem] = []

    /// IDs queued for removal.
    private var pendingRemovals: [String] = []

    // MARK: - Init

    init(debounceInterval: TimeInterval = 10.0) {
        self.debounceInterval = debounceInterval
    }

    // MARK: - Public API

    /// Index a single project. Thumbnail should be a PNG-encoded `Data`.
    func index(
        projectID: String,
        name: String,
        clipCount: Int,
        durationDescription: String,
        lastEditedDescription: String,
        tags: [String] = [],
        thumbnail: Data? = nil
    ) {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.movie)
        attrs.title = name
        attrs.contentDescription = "\(clipCount) clips · \(durationDescription) · \(lastEditedDescription)"
        attrs.keywords = tags
        if let thumbnail {
            attrs.thumbnailData = thumbnail
        }

        let item = CSSearchableItem(
            uniqueIdentifier: projectID,
            domainIdentifier: "com.liquideditor.projects",
            attributeSet: attrs
        )
        pendingItems.append(item)
        scheduleFlush()
    }

    /// Remove a project from the Spotlight index (called on trash / permanent delete).
    func remove(projectID: String) {
        pendingRemovals.append(projectID)
        scheduleFlush()
    }

    /// Force an immediate flush (skip the debounce window). Used at app
    /// termination so pending writes don't get lost.
    func flushNow() async {
        debounceTask?.cancel()
        debounceTask = nil
        await performFlush()
    }

    // MARK: - Private

    private func scheduleFlush() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.debounceInterval * 1_000_000_000))
            if Task.isCancelled { return }
            await self.performFlush()
        }
    }

    private func performFlush() async {
        let items = pendingItems
        let removals = pendingRemovals
        pendingItems.removeAll(keepingCapacity: true)
        pendingRemovals.removeAll(keepingCapacity: true)

        let index = CSSearchableIndex.default()
        if !items.isEmpty {
            try? await index.indexSearchableItems(items)
        }
        if !removals.isEmpty {
            try? await index.deleteSearchableItems(withIdentifiers: removals)
        }
    }
}
