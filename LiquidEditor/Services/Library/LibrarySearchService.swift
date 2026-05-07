// LibrarySearchService.swift
// LiquidEditor
//
// Library search implementation (F6-18).
//
// Fuzzy-matches a query string against:
//   • Project name (case-insensitive substring + Levenshtein fallback)
//   • Tag names (via an injectable tag provider)
//   • Clip content (via an injectable clip-text provider)
//
// Caches the last 10 query results keyed by the normalised query to
// avoid redundant scans while the user types.
//
// Levenshtein threshold for fuzzy matches is `2` (edit distance) —
// enough to tolerate typical typos without matching unrelated words.
//
// All public state is `@Observable` so views can bind `lastResults`.

import Foundation
import Observation

// MARK: - LibrarySearchService

/// Main-actor isolated search over the user's project library.
@MainActor
@Observable
final class LibrarySearchService {

    // MARK: - Constants

    /// Maximum edit distance to count as a fuzzy match (typo tolerance).
    static let levenshteinThreshold: Int = 2

    /// Maximum number of cached queries. Evicted in FIFO order.
    static let cacheCapacity: Int = 10

    // MARK: - Observable State

    /// Most recent result set, suitable for direct binding in a view.
    private(set) var lastResults: [Project] = []

    /// Last query string that produced `lastResults`.
    private(set) var lastQuery: String = ""

    // MARK: - Injectable Providers

    /// Returns the list of tag names associated with a project id.
    /// Default is an empty list so callers that don't have tags still
    /// get name + clip-content matching.
    @ObservationIgnored
    var tagsProvider: @MainActor (String) -> [String]

    /// Returns searchable text for a project's clip content (e.g.
    /// transcripts, clip captions). Default is an empty array.
    @ObservationIgnored
    var clipContentProvider: @MainActor (String) -> [String]

    // MARK: - Cache

    /// Ordered (oldest → newest) list of cached queries, used to evict
    /// the least-recently-added entry once `cacheCapacity` is exceeded.
    @ObservationIgnored
    private var cacheOrder: [String] = []

    /// Normalised query → cached result set.
    @ObservationIgnored
    private var cache: [String: [Project]] = [:]

    // MARK: - Init

    init(
        tagsProvider: @escaping @MainActor (String) -> [String] = { _ in [] },
        clipContentProvider: @escaping @MainActor (String) -> [String] = { _ in [] }
    ) {
        self.tagsProvider = tagsProvider
        self.clipContentProvider = clipContentProvider
    }

    // MARK: - Public API

    /// Search `projects` for `query`.
    ///
    /// - Parameters:
    ///   - query: raw user input. Leading / trailing whitespace is
    ///     trimmed; empty queries return `projects` unchanged.
    ///   - projects: projects to search.
    /// - Returns: matching projects, preserving input order (stable
    ///   sort with respect to project identity).
    @discardableResult
    func search(query: String, in projects: [Project]) -> [Project] {
        let normalised = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Empty → return input unchanged; don't cache the empty key.
        guard !normalised.isEmpty else {
            lastQuery = ""
            lastResults = projects
            return projects
        }

        // Cache hit short-circuits.
        if let cached = cache[normalised] {
            // Move to most-recent slot in the order log.
            cacheOrder.removeAll { $0 == normalised }
            cacheOrder.append(normalised)
            lastQuery = normalised
            lastResults = cached
            return cached
        }

        let results = projects.filter { project in
            matches(project: project, query: normalised)
        }

        insertInCache(query: normalised, results: results)
        lastQuery = normalised
        lastResults = results
        return results
    }

    /// Clear the internal query cache.
    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    // MARK: - Matching

    /// Returns true if any of (name, tags, clip content) matches.
    private func matches(project: Project, query: String) -> Bool {
        if matchesText(project.name, query: query) { return true }

        for tag in tagsProvider(project.id) where matchesText(tag, query: query) {
            return true
        }

        for text in clipContentProvider(project.id) where matchesText(text, query: query) {
            return true
        }

        return false
    }

    /// Match `haystack` against the normalised `query`. Returns true
    /// when:
    ///   - haystack contains query as a case-insensitive substring, OR
    ///   - min-edit-distance of any word in the haystack to the query
    ///     is `<= Self.levenshteinThreshold`.
    private func matchesText(_ haystack: String, query: String) -> Bool {
        let lower = haystack.lowercased()
        if lower.contains(query) { return true }

        // Fuzzy: compare query against each whitespace-separated word,
        // cheap and bounded. Skip if query is very short to avoid
        // matching everything.
        guard query.count >= 3 else { return false }

        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for word in words {
            if levenshtein(String(word), query) <= Self.levenshteinThreshold {
                return true
            }
        }
        return false
    }

    // MARK: - Cache helpers

    private func insertInCache(query: String, results: [Project]) {
        cache[query] = results
        cacheOrder.append(query)

        // Evict oldest entries until we're within capacity.
        while cacheOrder.count > Self.cacheCapacity {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    // MARK: - Levenshtein distance

    /// Standard two-row dynamic-programming edit distance. O(n * m) in
    /// time, O(min(n, m)) in space. Both inputs are already lowercased
    /// by the caller.
    fileprivate func levenshtein(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        let aChars = Array(a)
        let bChars = Array(b)
        let n = aChars.count
        let m = bChars.count

        var prev = Array(0...m)
        var curr = Array(repeating: 0, count: m + 1)

        for i in 1...n {
            curr[0] = i
            for j in 1...m {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    curr[j - 1] + 1,        // insertion
                    prev[j] + 1,            // deletion
                    prev[j - 1] + cost      // substitution
                )
            }
            swap(&prev, &curr)
        }
        return prev[m]
    }
}
