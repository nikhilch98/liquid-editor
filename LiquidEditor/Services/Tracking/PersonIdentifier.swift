//
//  PersonIdentifier.swift
//  LiquidEditor
//
//  Identifies tracked people against the People library using
//  OSNet 512-dimensional appearance embeddings.
//
//  Uses nonisolated(unsafe) for immutable-after-init configuration constants.
//

import Foundation

// MARK: - Data Structures

/// A person from the library for identification lookup.
struct PersonLibraryEntry: Sendable {
    let personId: String
    let personName: String
    let embeddings: [AppearanceFeature]
    let bestQualityScore: Float
}

/// Result of identifying a track against the People library.
struct IdentificationResult: Sendable {
    let isIdentified: Bool
    let personId: String?
    let personName: String?
    let confidence: Double
    let topCandidates: [IdentificationCandidate]

    static func unidentified(
        confidence: Double = 0,
        topCandidates: [IdentificationCandidate] = []
    ) -> IdentificationResult {
        IdentificationResult(
            isIdentified: false,
            personId: nil,
            personName: nil,
            confidence: confidence,
            topCandidates: topCandidates
        )
    }
}

/// A candidate match for identification.
struct IdentificationCandidate: Sendable {
    let personId: String
    let personName: String
    let similarity: Double
}

// MARK: - PersonIdentifier

/// Identifies tracked people against the People library.
///
/// Thread-safe via `actor` isolation. Maintains a library of known
/// persons with pre-computed embeddings, and matches new tracks
/// against them using cosine similarity with ambiguity checks.
actor PersonIdentifier {

    // MARK: - Configuration

    private let identificationThreshold: Double = 0.72
    private let singleEntryThreshold: Double = 0.78
    private let highConfidenceThreshold: Double = 0.80
    private let ambiguityMargin: Double = 0.08
    private let minEmbeddingQuality: Float = 0.5
    private let maxCandidates: Int = 3

    // MARK: - State

    private var libraryEntries: [PersonLibraryEntry] = []
    private var identificationCache: [Int: IdentificationResult] = [:]
    private var activeIdentifications: [String: (trackId: Int, similarity: Double)] = [:]

    // MARK: - Library Management

    /// Update the library with new entries (full replace).
    func updateLibrary(_ entries: [PersonLibraryEntry]) {
        libraryEntries = entries
        identificationCache.removeAll()
        activeIdentifications.removeAll()
    }

    /// Clear the library.
    func clearLibrary() {
        libraryEntries.removeAll()
        identificationCache.removeAll()
        activeIdentifications.removeAll()
    }

    /// Whether a library is loaded.
    var hasLibrary: Bool { !libraryEntries.isEmpty }

    /// Number of people in the library.
    var libraryCount: Int { libraryEntries.count }

    // MARK: - Identification (Single Embedding)

    /// Identify a track using a single appearance embedding.
    func identify(
        trackId: Int,
        appearance: AppearanceFeature,
        forceReidentify: Bool = false
    ) -> IdentificationResult {
        if !forceReidentify, let cached = identificationCache[trackId] {
            return cached
        }

        guard !libraryEntries.isEmpty else { return .unidentified() }
        guard appearance.qualityScore >= minEmbeddingQuality else { return .unidentified() }

        let candidates = computeCandidates { libraryEmbedding in
            Double(appearance.cosineSimilarity(with: libraryEmbedding))
        }

        return resolveIdentification(trackId: trackId, candidates: candidates)
    }

    // MARK: - Identification (Multi-View)

    /// Identify using multi-view appearance for cross-orientation matching.
    func identify(
        trackId: Int,
        multiViewAppearance: MultiViewAppearance,
        forceReidentify: Bool = false
    ) -> IdentificationResult {
        if !forceReidentify, let cached = identificationCache[trackId] {
            return cached
        }

        guard !libraryEntries.isEmpty else { return .unidentified() }
        guard multiViewAppearance.hasEmbeddings else { return .unidentified() }

        let candidates = computeCandidates { libraryEmbedding in
            Double(multiViewAppearance.bestSimilarity(with: libraryEmbedding))
        }

        return resolveIdentification(trackId: trackId, candidates: candidates)
    }

    // MARK: - Candidate Computation

    /// Compute similarity candidates for all library entries.
    private func computeCandidates(
        similarityFn: (AppearanceFeature) -> Double
    ) -> [(entry: PersonLibraryEntry, similarity: Double)] {
        var candidates: [(entry: PersonLibraryEntry, similarity: Double)] = []

        for entry in libraryEntries {
            var bestSimilarity: Double = 0
            for libraryEmbedding in entry.embeddings {
                let similarity = similarityFn(libraryEmbedding)
                bestSimilarity = max(bestSimilarity, similarity)
            }
            candidates.append((entry, bestSimilarity))
        }

        return candidates
    }

    // MARK: - Resolution Logic

    private func resolveIdentification(
        trackId: Int,
        candidates: [(entry: PersonLibraryEntry, similarity: Double)]
    ) -> IdentificationResult {
        let sorted = candidates.sorted { $0.similarity > $1.similarity }

        let topCandidates = sorted.prefix(maxCandidates).map { candidate in
            IdentificationCandidate(
                personId: candidate.entry.personId,
                personName: candidate.entry.personName,
                similarity: candidate.similarity
            )
        }

        let effectiveThreshold = libraryEntries.count == 1 ? singleEntryThreshold : identificationThreshold

        guard let bestMatch = sorted.first, bestMatch.similarity >= effectiveThreshold else {
            let result = IdentificationResult.unidentified(
                confidence: sorted.first?.similarity ?? 0,
                topCandidates: Array(topCandidates)
            )
            identificationCache[trackId] = result
            return result
        }

        // Ambiguity check
        if sorted.count >= 2 {
            let margin = bestMatch.similarity - sorted[1].similarity
            if margin < ambiguityMargin && bestMatch.similarity < highConfidenceThreshold {
                let result = IdentificationResult.unidentified(
                    confidence: bestMatch.similarity,
                    topCandidates: Array(topCandidates)
                )
                identificationCache[trackId] = result
                return result
            }
        }

        // Uniqueness constraint
        let personId = bestMatch.entry.personId
        if let existing = activeIdentifications[personId] {
            if existing.trackId != trackId && existing.similarity >= bestMatch.similarity {
                let result = IdentificationResult.unidentified(
                    confidence: bestMatch.similarity,
                    topCandidates: Array(topCandidates)
                )
                identificationCache[trackId] = result
                return result
            } else if existing.trackId != trackId {
                identificationCache.removeValue(forKey: existing.trackId)
            }
        }

        activeIdentifications[personId] = (trackId: trackId, similarity: bestMatch.similarity)

        let result = IdentificationResult(
            isIdentified: true,
            personId: bestMatch.entry.personId,
            personName: bestMatch.entry.personName,
            confidence: bestMatch.similarity,
            topCandidates: Array(topCandidates)
        )
        identificationCache[trackId] = result
        return result
    }

    // MARK: - Cache Management

    /// Clear cache for a specific track.
    func clearCache(for trackId: Int) {
        if let cached = identificationCache[trackId],
           let personId = cached.personId,
           let active = activeIdentifications[personId],
           active.trackId == trackId {
            activeIdentifications.removeValue(forKey: personId)
        }
        identificationCache.removeValue(forKey: trackId)
    }

    /// Clear all caches.
    func clearAllCache() {
        identificationCache.removeAll()
        activeIdentifications.removeAll()
    }
}
