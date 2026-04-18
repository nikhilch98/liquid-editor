// LibraryUIState.swift
// LiquidEditor
//
// Codable UI-state model for the Project Library screen (sidebar selection,
// grid/list mode, sort order, and future search filters), plus a `@MainActor`
// `@Observable` store that persists the state to `UserDefaults` on every
// mutation.
//
// Per §4.2 of docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md,
// the iPad Library uses a left sidebar with Collections, Templates, and Trash,
// a grid/list view toggle, and a Recent / Name / Size sort segmented control.
// This file captures the persisted state for those controls.

import Foundation
import Observation
import os

// MARK: - LibrarySidebarItem

/// A single entry selectable from the Library sidebar (iPad) or tab bar (iPhone).
///
/// Persisted in `UserDefaults` as part of ``LibraryUIState``. JSON shape uses
/// explicit keys so enum-case reordering cannot invalidate previously-saved
/// state. Collections are identified by their project-space `UUID`.
enum LibrarySidebarItem: Codable, Hashable, Sendable {

    // MARK: - Cases

    /// All projects in the library, unfiltered.
    case allProjects

    /// Recently opened or edited projects.
    case recent

    /// Projects the user has starred.
    case starred

    /// Unfinished drafts (auto-saved but not yet formally saved).
    case drafts

    /// A user-created collection, identified by its `UUID`.
    case collection(UUID)

    /// Built-in and user-saved project templates.
    case templates

    /// Deleted projects available for recovery.
    case trash

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
    }

    private enum Kind: String, Codable {
        case allProjects
        case recent
        case starred
        case drafts
        case collection
        case templates
        case trash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .allProjects: self = .allProjects
        case .recent: self = .recent
        case .starred: self = .starred
        case .drafts: self = .drafts
        case .collection:
            let id = try container.decode(UUID.self, forKey: .id)
            self = .collection(id)
        case .templates: self = .templates
        case .trash: self = .trash
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allProjects: try container.encode(Kind.allProjects, forKey: .kind)
        case .recent: try container.encode(Kind.recent, forKey: .kind)
        case .starred: try container.encode(Kind.starred, forKey: .kind)
        case .drafts: try container.encode(Kind.drafts, forKey: .kind)
        case .collection(let id):
            try container.encode(Kind.collection, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .templates: try container.encode(Kind.templates, forKey: .kind)
        case .trash: try container.encode(Kind.trash, forKey: .kind)
        }
    }
}

// MARK: - LibraryViewMode

/// The visual presentation mode for the library's project grid.
enum LibraryViewMode: String, Codable, Hashable, Sendable, CaseIterable {

    /// Multi-column grid of project-card thumbnails.
    case grid

    /// Single-column list of compact rows.
    case list
}

// MARK: - LibrarySortOrder

/// Ordering criterion for the library grid / list.
enum LibrarySortOrder: String, Codable, Hashable, Sendable, CaseIterable {

    /// Most-recently modified projects first.
    case recent

    /// Alphabetical by project name.
    case name

    /// Largest on-disk size first.
    case size
}

// MARK: - LibrarySearchFilters

/// Reserved filter container for the library search box.
///
/// Empty in v1. Future iterations will add filters such as date ranges,
/// aspect ratios, tags, or cloud-sync status.
struct LibrarySearchFilters: Codable, Hashable, Sendable {

    // MARK: - Initialization

    /// Creates an empty filter set.
    init() {}
}

// MARK: - LibraryUIState

/// Aggregate UI-state for the Project Library screen.
///
/// This value is persisted in `UserDefaults` as a single JSON-encoded blob via
/// ``LibraryUIStateStore``. Mutate individual fields freely; the store
/// observes the whole value and re-persists on every change.
struct LibraryUIState: Codable, Hashable, Sendable {

    // MARK: - Properties

    /// Currently-selected sidebar section (or tab on iPhone).
    var sidebarSelection: LibrarySidebarItem

    /// Grid vs. list presentation of the main card area.
    var viewMode: LibraryViewMode

    /// Sort criterion applied to the current section's projects.
    var sortOrder: LibrarySortOrder

    /// Optional search-filter set (empty in v1).
    var searchFilters: LibrarySearchFilters

    // MARK: - Defaults

    /// Default state: All Projects, grid view, most-recent first.
    static let `default`: LibraryUIState = LibraryUIState(
        sidebarSelection: .allProjects,
        viewMode: .grid,
        sortOrder: .recent,
        searchFilters: LibrarySearchFilters()
    )

    // MARK: - Initialization

    /// Creates a new library UI state.
    ///
    /// - Parameters:
    ///   - sidebarSelection: Initial sidebar / tab selection.
    ///   - viewMode: Initial grid / list mode.
    ///   - sortOrder: Initial sort order.
    ///   - searchFilters: Initial search filters (defaults to empty).
    init(
        sidebarSelection: LibrarySidebarItem = .allProjects,
        viewMode: LibraryViewMode = .grid,
        sortOrder: LibrarySortOrder = .recent,
        searchFilters: LibrarySearchFilters = LibrarySearchFilters()
    ) {
        self.sidebarSelection = sidebarSelection
        self.viewMode = viewMode
        self.sortOrder = sortOrder
        self.searchFilters = searchFilters
    }
}

// MARK: - LibraryUIStateStore

/// `@Observable` wrapper that persists ``LibraryUIState`` to `UserDefaults`.
///
/// The store reads any previously-persisted state on init (falling back to
/// ``LibraryUIState/default`` on first launch or decode failure) and writes
/// the full state on every mutation via `didSet`. Because ``LibraryUIState``
/// is a value type, nested mutations (e.g., `store.state.viewMode = .list`)
/// fire `didSet` on the `state` property and trigger a re-persist.
///
/// Usage:
/// ```swift
/// let store = LibraryUIStateStore()
/// store.state.sortOrder = .name // persisted immediately
/// ```
@Observable
@MainActor
final class LibraryUIStateStore {

    // MARK: - Constants

    /// UserDefaults key under which the JSON-encoded state blob is stored.
    private static let persistenceKey: String = "library.ui.state.v1"

    // MARK: - Dependencies

    /// UserDefaults instance used for persistence. Injected for testability.
    private let userDefaults: UserDefaults

    // MARK: - Logger

    private let logger: Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.liquideditor",
        category: "LibraryUIStateStore"
    )

    // MARK: - State

    /// Current library UI state. Writes persist synchronously on every change.
    var state: LibraryUIState {
        didSet { persist() }
    }

    // MARK: - Initialization

    /// Creates a new store, loading any persisted state from `UserDefaults`.
    ///
    /// - Parameter userDefaults: The `UserDefaults` instance to read from and
    ///   write to. Defaults to `.standard`; pass a custom suite for tests.
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.state = Self.loadState(from: userDefaults, logger: nil)
        logger.debug("Loaded LibraryUIState from UserDefaults")
    }

    // MARK: - Loading

    /// Decode a persisted state blob, or fall back to the default.
    ///
    /// `nonisolated static` so it can be called from `init` before the
    /// instance logger is constructed.
    private static func loadState(
        from userDefaults: UserDefaults,
        logger: Logger?
    ) -> LibraryUIState {
        guard let data = userDefaults.data(forKey: Self.persistenceKey) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(LibraryUIState.self, from: data)
        } catch {
            logger?.warning("Failed to decode LibraryUIState; using default: \(error.localizedDescription, privacy: .public)")
            return .default
        }
    }

    // MARK: - Persistence

    /// Encode the current state and write it to `UserDefaults`.
    private func persist() {
        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: Self.persistenceKey)
        } catch {
            logger.error("Failed to encode LibraryUIState for persistence: \(error.localizedDescription, privacy: .public)")
        }
    }
}
