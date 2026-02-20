import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - Helper

/// Creates a 512-dimensional normalized embedding for testing.
private func makeEmbedding(seed: Float = 1.0) -> [Float] {
    var embedding = [Float](repeating: 0, count: 512)
    for i in 0..<512 {
        embedding[i] = sin(Float(i) * seed * 0.01) + seed * 0.1
    }
    return embedding
}

/// Creates an AppearanceFeature with a specific seed for deterministic testing.
private func makeAppearance(seed: Float = 1.0, quality: Float = 0.8) -> AppearanceFeature {
    AppearanceFeature(embedding: makeEmbedding(seed: seed), qualityScore: quality)
}

// MARK: - ArchiveConfig Tests

@Suite("ArchiveConfig Tests")
struct ArchiveConfigTests {

    @Test("static constants have expected values")
    func staticConstants() {
        #expect(ArchiveConfig.minDetectionsStandard == 3)
        #expect(ArchiveConfig.minDetectionsEdge == 1)
        #expect(ArchiveConfig.minQualityForSingleFrame == 0.6)
        #expect(ArchiveConfig.edgeThreshold == 0.08)
        #expect(ArchiveConfig.premiumLifetimeFrames == 300)
        #expect(ArchiveConfig.standardLifetimeFrames == 120)
        #expect(ArchiveConfig.minimumLifetimeFrames == 60)
        #expect(ArchiveConfig.longGapThreshold == 45)
    }
}

// MARK: - ArchivedTrack Tests

@Suite("ArchivedTrack Tests")
struct ArchivedTrackTests {

    @Test("lifetime tiers - premium")
    func lifetimePremium() {
        let track = ArchivedTrack(
            trackId: 1,
            appearance: makeAppearance(quality: 0.8),
            lastBoundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastCenter: CGPoint(x: 0.5, y: 0.5),
            lastVelocity: .zero,
            archivedAtFrame: 100,
            firstSeenFrame: 0,
            totalActiveFrames: 50,
            avgConfidence: 0.8,
            previousRestorations: 0,
            wasEdgeDetection: false,
            identifiedPersonId: nil,
            identifiedPersonName: nil,
            identificationConfidence: nil
        )
        #expect(track.lifetime == ArchiveConfig.premiumLifetimeFrames)
    }

    @Test("lifetime tiers - standard")
    func lifetimeStandard() {
        let track = ArchivedTrack(
            trackId: 2,
            appearance: makeAppearance(quality: 0.5),
            lastBoundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastCenter: CGPoint(x: 0.5, y: 0.5),
            lastVelocity: .zero,
            archivedAtFrame: 100,
            firstSeenFrame: 90,
            totalActiveFrames: 10,
            avgConfidence: 0.6,
            previousRestorations: 0,
            wasEdgeDetection: false,
            identifiedPersonId: nil,
            identifiedPersonName: nil,
            identificationConfidence: nil
        )
        #expect(track.lifetime == ArchiveConfig.standardLifetimeFrames)
    }

    @Test("lifetime tiers - minimum")
    func lifetimeMinimum() {
        let track = ArchivedTrack(
            trackId: 3,
            appearance: makeAppearance(quality: 0.3),
            lastBoundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastCenter: CGPoint(x: 0.5, y: 0.5),
            lastVelocity: .zero,
            archivedAtFrame: 100,
            firstSeenFrame: 99,
            totalActiveFrames: 2,
            avgConfidence: 0.4,
            previousRestorations: 0,
            wasEdgeDetection: false,
            identifiedPersonId: nil,
            identifiedPersonName: nil,
            identificationConfidence: nil
        )
        #expect(track.lifetime == ArchiveConfig.minimumLifetimeFrames)
    }

    @Test("isExpired returns false before lifetime")
    func isExpiredFalse() {
        let track = ArchivedTrack(
            trackId: 1,
            appearance: makeAppearance(quality: 0.3),
            lastBoundingBox: .zero,
            lastCenter: .zero,
            lastVelocity: .zero,
            archivedAtFrame: 100,
            firstSeenFrame: 99,
            totalActiveFrames: 2,
            avgConfidence: 0.4,
            previousRestorations: 0,
            wasEdgeDetection: false,
            identifiedPersonId: nil,
            identifiedPersonName: nil,
            identificationConfidence: nil
        )
        // Minimum lifetime = 60 frames
        #expect(track.isExpired(currentFrame: 150) == false)
    }

    @Test("isExpired returns true after lifetime")
    func isExpiredTrue() {
        let track = ArchivedTrack(
            trackId: 1,
            appearance: makeAppearance(quality: 0.3),
            lastBoundingBox: .zero,
            lastCenter: .zero,
            lastVelocity: .zero,
            archivedAtFrame: 100,
            firstSeenFrame: 99,
            totalActiveFrames: 2,
            avgConfidence: 0.4,
            previousRestorations: 0,
            wasEdgeDetection: false,
            identifiedPersonId: nil,
            identifiedPersonName: nil,
            identificationConfidence: nil
        )
        // Minimum lifetime = 60 frames, so 161 - 100 = 61 > 60
        #expect(track.isExpired(currentFrame: 161) == true)
    }
}

// MARK: - ReIDRestorationEvent Tests

@Suite("ReIDRestorationEvent Tests")
struct ReIDRestorationEventTests {

    @Test("creation")
    func creation() {
        let event = ReIDRestorationEvent(
            frameNumber: 100,
            timestampMs: 3300,
            similarity: 0.85,
            restoredTrackId: 5,
            wouldHaveBeenTrackId: 12
        )
        #expect(event.frameNumber == 100)
        #expect(event.timestampMs == 3300)
        #expect(event.similarity == 0.85)
        #expect(event.restoredTrackId == 5)
        #expect(event.wouldHaveBeenTrackId == 12)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let event = ReIDRestorationEvent(
            frameNumber: 50,
            timestampMs: 1650,
            similarity: 0.78,
            restoredTrackId: 3,
            wouldHaveBeenTrackId: nil
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ReIDRestorationEvent.self, from: data)
        #expect(decoded.frameNumber == 50)
        #expect(decoded.similarity == 0.78)
        #expect(decoded.restoredTrackId == 3)
        #expect(decoded.wouldHaveBeenTrackId == nil)
    }
}

// MARK: - TrackArchive Tests

@Suite("TrackArchive Tests")
struct TrackArchiveTests {

    // MARK: - Empty Archive

    @Test("empty archive has zero count")
    func emptyArchive() {
        let archive = TrackArchive()
        #expect(archive.count == 0)
        #expect(archive.archivedTrackIds.isEmpty)
        #expect(archive.restorationEvents.isEmpty)
    }

    // MARK: - shouldArchive

    @Test("shouldArchive requires minimum detections for standard tracks")
    func shouldArchiveMinDetections() {
        let archive = TrackArchive()
        // Standard track needs 3+ frames
        #expect(archive.shouldArchive(totalActiveFrames: 2, wasEdgeDetection: false, appearanceQuality: 0.9) == false)
        #expect(archive.shouldArchive(totalActiveFrames: 3, wasEdgeDetection: false, appearanceQuality: 0.9) == true)
    }

    @Test("shouldArchive requires only 1 frame for edge detections")
    func shouldArchiveEdge() {
        let archive = TrackArchive()
        #expect(archive.shouldArchive(totalActiveFrames: 1, wasEdgeDetection: true, appearanceQuality: 0.7) == true)
    }

    @Test("shouldArchive single-frame requires quality threshold")
    func shouldArchiveSingleFrameQuality() {
        let archive = TrackArchive()
        // Edge detection with 1 frame but low quality
        #expect(archive.shouldArchive(totalActiveFrames: 1, wasEdgeDetection: true, appearanceQuality: 0.5) == false)
        // Edge detection with 1 frame and good quality
        #expect(archive.shouldArchive(totalActiveFrames: 1, wasEdgeDetection: true, appearanceQuality: 0.7) == true)
    }

    // MARK: - archive

    @Test("archive adds track")
    func archiveAdds() {
        let archive = TrackArchive()
        archive.archive(
            trackId: 1,
            appearance: makeAppearance(),
            lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 0,
            totalActiveFrames: 10,
            avgConfidence: 0.8,
            previousRestorations: 0
        )
        #expect(archive.count == 1)
        #expect(archive.archivedTrackIds == [1])
    }

    @Test("archive prevents duplicates")
    func archiveNoDuplicates() {
        let archive = TrackArchive()
        for _ in 0..<3 {
            archive.archive(
                trackId: 1,
                appearance: makeAppearance(),
                lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
                lastVelocity: .zero,
                currentFrame: 100,
                firstSeenFrame: 0,
                totalActiveFrames: 10,
                avgConfidence: 0.8,
                previousRestorations: 0
            )
        }
        #expect(archive.count == 1)
    }

    @Test("archive rejects tracks that do not meet threshold")
    func archiveRejectsLowQuality() {
        let archive = TrackArchive()
        archive.archive(
            trackId: 1,
            appearance: makeAppearance(quality: 0.3),
            lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 99,
            totalActiveFrames: 1, // Only 1 frame, non-edge, needs quality >= 0.6
            avgConfidence: 0.5,
            previousRestorations: 0
        )
        #expect(archive.count == 0)
    }

    // MARK: - remove and reset

    @Test("remove removes specific track")
    func removeTrack() {
        let archive = TrackArchive()
        archive.archive(
            trackId: 1,
            appearance: makeAppearance(seed: 1.0),
            lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 0,
            totalActiveFrames: 10,
            avgConfidence: 0.8,
            previousRestorations: 0
        )
        archive.archive(
            trackId: 2,
            appearance: makeAppearance(seed: 2.0),
            lastBbox: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 0,
            totalActiveFrames: 10,
            avgConfidence: 0.8,
            previousRestorations: 0
        )
        #expect(archive.count == 2)

        archive.remove(trackId: 1)
        #expect(archive.count == 1)
        #expect(archive.archivedTrackIds == [2])
    }

    @Test("reset clears everything")
    func resetClears() {
        let archive = TrackArchive()
        archive.archive(
            trackId: 1,
            appearance: makeAppearance(),
            lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 0,
            totalActiveFrames: 10,
            avgConfidence: 0.8,
            previousRestorations: 0
        )
        #expect(archive.count == 1)

        archive.reset()
        #expect(archive.count == 0)
        #expect(archive.restorationEvents.isEmpty)
    }

    // MARK: - cleanupExpired

    @Test("cleanupExpired removes expired tracks")
    func cleanupExpired() {
        let archive = TrackArchive()
        // Archive a minimum-lifetime track (60 frames)
        archive.archive(
            trackId: 1,
            appearance: makeAppearance(quality: 0.3),
            lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 97,
            totalActiveFrames: 4,
            avgConfidence: 0.4,
            previousRestorations: 0
        )
        #expect(archive.count == 1)

        // Not expired yet (100 + 60 = 160, current is 150)
        archive.cleanupExpired(currentFrame: 150)
        #expect(archive.count == 1)

        // Now expired (100 + 60 = 160, current is 161)
        archive.cleanupExpired(currentFrame: 161)
        #expect(archive.count == 0)
    }

    // MARK: - isNearFrameEdge

    @Test("isNearFrameEdge detects edge bounding boxes")
    func isNearFrameEdge() {
        // Near left edge
        #expect(TrackArchive.isNearFrameEdge(CGRect(x: 0.01, y: 0.5, width: 0.1, height: 0.2)) == true)
        // Near right edge
        #expect(TrackArchive.isNearFrameEdge(CGRect(x: 0.85, y: 0.5, width: 0.2, height: 0.2)) == true)
        // Near top edge
        #expect(TrackArchive.isNearFrameEdge(CGRect(x: 0.5, y: 0.01, width: 0.2, height: 0.1)) == true)
        // Near bottom edge
        #expect(TrackArchive.isNearFrameEdge(CGRect(x: 0.5, y: 0.85, width: 0.2, height: 0.2)) == true)
        // Center - not near edge
        #expect(TrackArchive.isNearFrameEdge(CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)) == false)
    }

    // MARK: - findMatch

    @Test("findMatch returns nil for empty archive")
    func findMatchEmpty() {
        let archive = TrackArchive()
        let result = archive.findMatch(
            appearance: makeAppearance(),
            bbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            currentFrame: 200
        )
        #expect(result == nil)
    }

    @Test("findMatch with identical appearance returns match")
    func findMatchIdentical() {
        let archive = TrackArchive()
        let appearance = makeAppearance(seed: 1.0)

        archive.archive(
            trackId: 1,
            appearance: appearance,
            lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 0,
            totalActiveFrames: 10,
            avgConfidence: 0.8,
            previousRestorations: 0
        )

        // Same appearance should match with high similarity (cosine similarity of normalized vector with itself = 1.0)
        let match = archive.findMatch(
            appearance: appearance,
            bbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            currentFrame: 110
        )
        #expect(match != nil)
        #expect(match?.trackId == 1)
    }

    @Test("findMatch removes matched track from archive")
    func findMatchRemovesFromArchive() {
        let archive = TrackArchive()
        let appearance = makeAppearance(seed: 1.0)

        archive.archive(
            trackId: 1,
            appearance: appearance,
            lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 0,
            totalActiveFrames: 10,
            avgConfidence: 0.8,
            previousRestorations: 0
        )

        _ = archive.findMatch(
            appearance: appearance,
            bbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            currentFrame: 110
        )

        #expect(archive.count == 0) // Match was removed
    }

    @Test("findMatch records restoration event")
    func findMatchRecordsEvent() {
        let archive = TrackArchive()
        let appearance = makeAppearance(seed: 1.0)

        archive.archive(
            trackId: 1,
            appearance: appearance,
            lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 0,
            totalActiveFrames: 10,
            avgConfidence: 0.8,
            previousRestorations: 0
        )

        _ = archive.findMatch(
            appearance: appearance,
            bbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            currentFrame: 110,
            wouldBeTrackId: 99
        )

        #expect(archive.restorationEvents.count == 1)
        #expect(archive.restorationEvents[0].restoredTrackId == 1)
        #expect(archive.restorationEvents[0].wouldHaveBeenTrackId == 99)
    }

    @Test("restorations(for:) filters by track ID")
    func restorationsForTrack() {
        let archive = TrackArchive()
        let appearance = makeAppearance(seed: 1.0)

        // Archive and match track 1
        archive.archive(
            trackId: 1,
            appearance: appearance,
            lastBbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            lastVelocity: .zero,
            currentFrame: 100,
            firstSeenFrame: 0,
            totalActiveFrames: 10,
            avgConfidence: 0.8,
            previousRestorations: 0
        )
        _ = archive.findMatch(
            appearance: appearance,
            bbox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            currentFrame: 110
        )

        let events = archive.restorations(for: 1)
        #expect(events.count == 1)

        let noEvents = archive.restorations(for: 999)
        #expect(noEvents.isEmpty)
    }
}
