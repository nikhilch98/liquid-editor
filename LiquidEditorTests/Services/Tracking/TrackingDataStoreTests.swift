// TrackingDataStoreTests.swift
// LiquidEditorTests
//
// Comprehensive tests for TrackingDataStore (1180-line actor):
// - Storage operations (store, get, clear, replace)
// - Binary search correctness
// - Time range queries
// - Interpolation between frames
// - smoothBoundingBoxes algorithm
// - mergeTracksBySpatialProximity algorithm
// - filterNoiseTracks algorithm
// - fillTrackingGaps algorithm
// - Memory cleanup
// - JSON serialization round-trip
// - Edge cases (empty store, single track, overlapping tracks)

import Testing
import Foundation
import CoreMedia
import CoreGraphics
@testable import LiquidEditor

// MARK: - Test Helpers

/// Create a PersonTrackingResult for testing.
private func makePerson(
    index: Int = 0,
    confidence: Double = 0.95,
    x: Double = 0.5,
    y: Double = 0.5,
    width: Double = 0.2,
    height: Double = 0.3,
    timestampMs: Int = 0,
    pose: PoseJoints? = nil,
    identifiedPersonId: String? = nil,
    identifiedPersonName: String? = nil,
    identificationConfidence: Double? = nil
) -> PersonTrackingResult {
    PersonTrackingResult(
        personIndex: index,
        confidence: confidence,
        boundingBox: NormalizedBoundingBox(x: x, y: y, width: width, height: height),
        bodyOutline: nil,
        pose: pose,
        timestampMs: timestampMs,
        identifiedPersonId: identifiedPersonId,
        identifiedPersonName: identifiedPersonName,
        identificationConfidence: identificationConfidence
    )
}

/// Create a FrameTrackingResult.
private func makeFrame(
    timestampMs: Int,
    people: [PersonTrackingResult]
) -> FrameTrackingResult {
    FrameTrackingResult(timestampMs: timestampMs, people: people)
}

/// Helper to create CMTime from milliseconds.
private func cmTime(ms: Int) -> CMTime {
    CMTime(value: Int64(ms), timescale: 1000)
}

// MARK: - TrackingDataStore Tests

@Suite("TrackingDataStore Tests")
struct TrackingDataStoreTests {

    // MARK: - Initial State

    @Test("Empty store has zero frames")
    func emptyStore() async {
        let store = TrackingDataStore()
        let count = await store.frameCount
        #expect(count == 0)
    }

    @Test("Empty store returns nil for getResult")
    func emptyStoreGetResult() async {
        let store = TrackingDataStore()
        let result = await store.getResult(at: cmTime(ms: 0))
        #expect(result == nil)
    }

    @Test("Empty store returns empty for getAllResults")
    func emptyStoreGetAll() async {
        let store = TrackingDataStore()
        let results = await store.getAllResults()
        #expect(results.isEmpty)
    }

    @Test("Empty store returns empty for getResults range")
    func emptyStoreRange() async {
        let store = TrackingDataStore()
        let results = await store.getResults(from: cmTime(ms: 0), to: cmTime(ms: 1000))
        #expect(results.isEmpty)
    }

    // MARK: - Store and Retrieve

    @Test("Store and retrieve a single frame")
    func storeAndRetrieve() async {
        let store = TrackingDataStore()
        let frame = makeFrame(
            timestampMs: 100,
            people: [makePerson(index: 0, timestampMs: 100)]
        )

        await store.store(frame, smooth: false)
        let count = await store.frameCount
        #expect(count == 1)

        let retrieved = await store.getResult(at: cmTime(ms: 100))
        #expect(retrieved != nil)
        #expect(retrieved?.timestampMs == 100)
        #expect(retrieved?.people.count == 1)
    }

    @Test("Store multiple frames maintains sorted order")
    func storeMultipleFrames() async {
        let store = TrackingDataStore()

        // Store out of order
        await store.store(makeFrame(timestampMs: 300, people: [makePerson(timestampMs: 300)]), smooth: false)
        await store.store(makeFrame(timestampMs: 100, people: [makePerson(timestampMs: 100)]), smooth: false)
        await store.store(makeFrame(timestampMs: 200, people: [makePerson(timestampMs: 200)]), smooth: false)

        let allResults = await store.getAllResults()
        #expect(allResults.count == 3)
        #expect(allResults[0].timestampMs == 100)
        #expect(allResults[1].timestampMs == 200)
        #expect(allResults[2].timestampMs == 300)
    }

    @Test("Storing duplicate timestamp replaces existing frame")
    func storeDuplicate() async {
        let store = TrackingDataStore()

        let frame1 = makeFrame(timestampMs: 100, people: [makePerson(index: 0, timestampMs: 100)])
        await store.store(frame1, smooth: false)

        let frame2 = makeFrame(timestampMs: 100, people: [
            makePerson(index: 0, timestampMs: 100),
            makePerson(index: 1, timestampMs: 100),
        ])
        await store.store(frame2, smooth: false)

        let count = await store.frameCount
        #expect(count == 1) // still 1 frame

        let retrieved = await store.getResult(at: cmTime(ms: 100))
        #expect(retrieved?.people.count == 2) // updated
    }

    // MARK: - Range Queries

    @Test("Get results in time range returns correct subset")
    func rangeQuery() async {
        let store = TrackingDataStore()

        for ms in stride(from: 0, through: 500, by: 100) {
            await store.store(makeFrame(
                timestampMs: ms,
                people: [makePerson(timestampMs: ms)]
            ), smooth: false)
        }

        let results = await store.getResults(from: cmTime(ms: 100), to: cmTime(ms: 300))
        #expect(results.count == 3) // 100, 200, 300
        #expect(results[0].timestampMs == 100)
        #expect(results[2].timestampMs == 300)
    }

    @Test("Get results with range outside data returns empty")
    func rangeQueryOutside() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 100, people: [makePerson(timestampMs: 100)]), smooth: false)

        let results = await store.getResults(from: cmTime(ms: 500), to: cmTime(ms: 600))
        #expect(results.isEmpty)
    }

    // MARK: - Interpolated Result

    @Test("Interpolated result at exact timestamp returns that frame")
    func interpolateExact() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 100, people: [makePerson(index: 0, x: 0.3, timestampMs: 100)]), smooth: false)
        await store.store(makeFrame(timestampMs: 200, people: [makePerson(index: 0, x: 0.7, timestampMs: 200)]), smooth: false)

        let result = await store.getInterpolatedResult(at: cmTime(ms: 100))
        #expect(result != nil)
        #expect(result?.timestampMs == 100)
    }

    @Test("Interpolated result between two frames interpolates bounding box")
    func interpolateBetween() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 0, people: [makePerson(index: 0, x: 0.0, y: 0.0, timestampMs: 0)]), smooth: false)
        await store.store(makeFrame(timestampMs: 100, people: [makePerson(index: 0, x: 1.0, y: 1.0, timestampMs: 100)]), smooth: false)

        let result = await store.getInterpolatedResult(at: cmTime(ms: 50))
        #expect(result != nil)

        if let bbox = result?.people.first?.boundingBox {
            // At t=0.5, interpolated x should be around 0.5
            #expect(abs(bbox.x - 0.5) < 0.01)
            #expect(abs(bbox.y - 0.5) < 0.01)
        } else {
            Issue.record("Expected interpolated bounding box")
        }
    }

    @Test("Interpolated result with no matching person index returns empty people")
    func interpolateNoMatchingPerson() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 0, people: [makePerson(index: 0, timestampMs: 0)]), smooth: false)
        await store.store(makeFrame(timestampMs: 100, people: [makePerson(index: 1, timestampMs: 100)]), smooth: false)

        let result = await store.getInterpolatedResult(at: cmTime(ms: 50))
        #expect(result != nil)
        // Person 0 is in frame 0 but not frame 100, and person 1 is only in frame 100.
        // Interpolation only keeps people that exist in both frames.
        #expect(result?.people.isEmpty == true)
    }

    // MARK: - Clear

    @Test("Clear removes all data")
    func clearStore() async {
        let store = TrackingDataStore()
        for ms in stride(from: 0, through: 500, by: 100) {
            await store.store(makeFrame(
                timestampMs: ms,
                people: [makePerson(timestampMs: ms)]
            ), smooth: false)
        }

        #expect(await store.frameCount == 6)

        await store.clear()
        #expect(await store.frameCount == 0)
        #expect(await store.getAllResults().isEmpty)
    }

    // MARK: - Replace All Results

    @Test("Replace all results replaces stored data")
    func replaceAll() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 100, people: [makePerson(timestampMs: 100)]), smooth: false)
        await store.store(makeFrame(timestampMs: 200, people: [makePerson(timestampMs: 200)]), smooth: false)
        #expect(await store.frameCount == 2)

        let newFrames = [
            makeFrame(timestampMs: 500, people: [makePerson(timestampMs: 500)]),
            makeFrame(timestampMs: 600, people: [makePerson(timestampMs: 600)]),
            makeFrame(timestampMs: 700, people: [makePerson(timestampMs: 700)]),
        ]
        await store.replaceAllResults(newFrames)
        #expect(await store.frameCount == 3)

        let all = await store.getAllResults()
        #expect(all[0].timestampMs == 500)
        #expect(all[2].timestampMs == 700)
    }

    // MARK: - Configure

    @Test("Configure sets algorithm and duration and clears data")
    func configureStore() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 100, people: [makePerson(timestampMs: 100)]), smooth: false)
        #expect(await store.frameCount == 1)

        let duration = CMTime(seconds: 10.0, preferredTimescale: 600)
        await store.configure(algorithmType: "boundingBox", videoDuration: duration)

        #expect(await store.frameCount == 0)
        let algo = await store.algorithmType
        #expect(algo == "boundingBox")
        let dur = await store.videoDuration
        #expect(abs(dur.seconds - 10.0) < 0.001)
    }

    // MARK: - Detected Persons

    @Test("Get detected persons returns person info sorted by index")
    func detectedPersons() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 0, people: [
            makePerson(index: 1, x: 0.3, timestampMs: 0),
            makePerson(index: 0, x: 0.7, timestampMs: 0),
        ]), smooth: false)
        await store.store(makeFrame(timestampMs: 100, people: [
            makePerson(index: 0, x: 0.75, timestampMs: 100),
            makePerson(index: 2, x: 0.1, timestampMs: 100),
        ]), smooth: false)

        let persons = await store.getDetectedPersons()
        #expect(persons.count == 3)
        #expect(persons[0].personIndex == 0)
        #expect(persons[1].personIndex == 1)
        #expect(persons[2].personIndex == 2)
    }

    @Test("First detection timestamp is stored correctly")
    func firstDetectionTimestamp() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 100, people: [
            makePerson(index: 0, timestampMs: 100),
        ]), smooth: false)
        await store.store(makeFrame(timestampMs: 200, people: [
            makePerson(index: 0, timestampMs: 200),
        ]), smooth: false)

        let persons = await store.getDetectedPersons()
        #expect(persons.count == 1)
        #expect(persons[0].firstTimestampMs == 100) // first detection, not 200
    }

    // MARK: - Unique Track IDs

    @Test("Get unique track IDs returns all person indices")
    func uniqueTrackIds() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 0, people: [
            makePerson(index: 0, timestampMs: 0),
            makePerson(index: 1, timestampMs: 0),
        ]), smooth: false)
        await store.store(makeFrame(timestampMs: 100, people: [
            makePerson(index: 1, timestampMs: 100),
            makePerson(index: 2, timestampMs: 100),
        ]), smooth: false)

        let ids = await store.getUniqueTrackIds()
        #expect(ids == Set([0, 1, 2]))
    }

    // MARK: - Get Frames For Track

    @Test("Get frames for specific track returns correct subset")
    func framesForTrack() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 0, people: [
            makePerson(index: 0, x: 0.1, timestampMs: 0),
            makePerson(index: 1, x: 0.9, timestampMs: 0),
        ]), smooth: false)
        await store.store(makeFrame(timestampMs: 100, people: [
            makePerson(index: 0, x: 0.2, timestampMs: 100),
        ]), smooth: false)

        let track0Frames = await store.getFramesForTrack(0)
        #expect(track0Frames.count == 2)
        #expect(track0Frames[0].timestampMs == 0)
        #expect(track0Frames[1].timestampMs == 100)

        let track1Frames = await store.getFramesForTrack(1)
        #expect(track1Frames.count == 1)
    }

    @Test("Get frames for track with limit returns top by confidence")
    func framesForTrackWithLimit() async {
        let store = TrackingDataStore()
        for ms in stride(from: 0, through: 400, by: 100) {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, confidence: Double(ms) / 500.0, timestampMs: ms),
            ]), smooth: false)
        }

        let limited = await store.getFramesForTrack(0, limit: 2)
        #expect(limited.count == 2)
        // Should be top 2 by confidence (highest first)
        #expect(limited[0].confidence > limited[1].confidence)
    }

    // MARK: - Update Identification

    @Test("Update identification updates all frames for a track")
    func updateIdentification() async {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 0, people: [
            makePerson(index: 0, timestampMs: 0),
        ]), smooth: false)
        await store.store(makeFrame(timestampMs: 100, people: [
            makePerson(index: 0, timestampMs: 100),
            makePerson(index: 1, timestampMs: 100),
        ]), smooth: false)

        await store.updateIdentification(
            forTrack: 0,
            personId: "person-abc",
            personName: "Alice",
            confidence: 0.92
        )

        let allResults = await store.getAllResults()
        for frame in allResults {
            for person in frame.people where person.personIndex == 0 {
                #expect(person.identifiedPersonId == "person-abc")
                #expect(person.identifiedPersonName == "Alice")
            }
            for person in frame.people where person.personIndex == 1 {
                #expect(person.identifiedPersonId == nil)
            }
        }
    }

    // MARK: - Smooth Bounding Boxes

    @Test("Smooth bounding boxes does not crash on empty store")
    func smoothBboxEmpty() async {
        let store = TrackingDataStore()
        await store.smoothBoundingBoxes()
        #expect(await store.frameCount == 0)
    }

    @Test("Smooth bounding boxes enforces hard minimum width and height")
    func smoothBboxMinFloors() async {
        let store = TrackingDataStore()

        // Store many frames with very small bounding boxes
        for ms in stride(from: 0, through: 900, by: 33) {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, x: 0.5, y: 0.5, width: 0.01, height: 0.05, timestampMs: ms),
            ]), smooth: false)
        }

        await store.smoothBoundingBoxes()

        let allResults = await store.getAllResults()
        for frame in allResults {
            for person in frame.people {
                if let bbox = person.boundingBox {
                    // Hard minimums are 0.04 (width) and 0.12 (height)
                    #expect(bbox.width >= 0.04 - 0.001)
                    #expect(bbox.height >= 0.12 - 0.001)
                }
            }
        }
    }

    @Test("Smooth bounding boxes clamps width and height to 1.0")
    func smoothBboxMaxClamp() async {
        let store = TrackingDataStore()

        for ms in stride(from: 0, through: 300, by: 33) {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, x: 0.5, y: 0.5, width: 1.5, height: 1.5, timestampMs: ms),
            ]), smooth: false)
        }

        await store.smoothBoundingBoxes()

        let allResults = await store.getAllResults()
        for frame in allResults {
            for person in frame.people {
                if let bbox = person.boundingBox {
                    #expect(bbox.width <= 1.0 + 0.001)
                    #expect(bbox.height <= 1.0 + 0.001)
                }
            }
        }
    }

    // MARK: - Filter Noise Tracks

    @Test("Filter noise tracks removes short-lived tracks")
    func filterNoiseTracks() async {
        let store = TrackingDataStore()

        // Person 0: appears in 50 frames (long enough to keep at 30fps, minDuration=1.0)
        for ms in stride(from: 0, through: 1633, by: 33) {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, timestampMs: ms),
            ]), smooth: false)
        }

        // Person 1: appears in only 3 frames (noise -- should be removed)
        for ms in [2000, 2033, 2066] {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 1, timestampMs: ms),
            ]), smooth: false)
        }

        await store.filterNoiseTracks(minDurationSeconds: 1.0, fps: 30.0)

        let trackIds = await store.getUniqueTrackIds()
        // Person 1 should be removed; only person 0 remains (possibly remapped to 0)
        #expect(trackIds.count == 1)
    }

    @Test("Filter noise tracks does nothing when all tracks are long enough")
    func filterNoiseTracksAllGood() async {
        let store = TrackingDataStore()

        for ms in stride(from: 0, through: 1633, by: 33) {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, timestampMs: ms),
                makePerson(index: 1, x: 0.8, timestampMs: ms),
            ]), smooth: false)
        }

        let countBefore = await store.frameCount
        await store.filterNoiseTracks(minDurationSeconds: 1.0, fps: 30.0)
        let countAfter = await store.frameCount

        #expect(countAfter == countBefore)
        let trackIds = await store.getUniqueTrackIds()
        #expect(trackIds.count == 2)
    }

    // MARK: - Merge Tracks by Spatial Proximity

    @Test("Merge does nothing with single track")
    func mergeSingleTrack() async {
        let store = TrackingDataStore()
        for ms in stride(from: 0, through: 300, by: 33) {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, timestampMs: ms),
            ]), smooth: false)
        }

        await store.mergeTracksBySpatialProximity()

        let trackIds = await store.getUniqueTrackIds()
        #expect(trackIds.count == 1)
    }

    @Test("Merge does nothing when tracks are spatially distant")
    func mergeDistantTracks() async {
        let store = TrackingDataStore()

        // Two tracks that are far apart spatially
        for ms in stride(from: 0, through: 300, by: 33) {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, x: 0.1, y: 0.1, timestampMs: ms),
                makePerson(index: 1, x: 0.9, y: 0.9, timestampMs: ms),
            ]), smooth: false)
        }

        await store.mergeTracksBySpatialProximity()

        // Both tracks should remain (they are active simultaneously and far apart)
        let trackIds = await store.getUniqueTrackIds()
        #expect(trackIds.count == 2)
    }

    @Test("Merge does nothing when empty")
    func mergeEmpty() async {
        let store = TrackingDataStore()
        await store.mergeTracksBySpatialProximity()
        #expect(await store.frameCount == 0)
    }

    // MARK: - Fill Tracking Gaps

    @Test("Fill gaps returns 0 for empty store")
    func fillGapsEmpty() async {
        let store = TrackingDataStore()
        let filled = await store.fillTrackingGaps()
        #expect(filled == 0)
    }

    @Test("Fill gaps fills short missing segments")
    func fillGapsBasic() async {
        let store = TrackingDataStore()

        // Person 0 is present for several frames, then absent for 3 frames, then present again
        // Build up history before gap
        for ms in stride(from: 0, through: 165, by: 33) {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, x: 0.5, y: 0.5, timestampMs: ms),
            ]), smooth: false)
        }

        // Gap: 3 frames with no person 0
        for ms in [198, 231, 264] {
            await store.store(makeFrame(timestampMs: ms, people: []), smooth: false)
        }

        // Person 0 returns
        for ms in stride(from: 297, through: 500, by: 33) {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, x: 0.55, y: 0.55, timestampMs: ms),
            ]), smooth: false)
        }

        let filled = await store.fillTrackingGaps(maxGapFrames: 5)
        #expect(filled == 3) // 3 frames were filled
    }

    @Test("Fill gaps does not fill long gaps beyond maxGapFrames")
    func fillGapsLongGap() async {
        let store = TrackingDataStore()

        // Person present in first 3 frames
        for ms in [0, 33, 66] {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, x: 0.5, timestampMs: ms),
            ]), smooth: false)
        }

        // Long gap of 10 frames
        for ms in stride(from: 99, through: 396, by: 33) {
            await store.store(makeFrame(timestampMs: ms, people: []), smooth: false)
        }

        // Person returns
        for ms in [429, 462] {
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, x: 0.6, timestampMs: ms),
            ]), smooth: false)
        }

        let filled = await store.fillTrackingGaps(maxGapFrames: 5)
        #expect(filled == 0) // gap is > 5 frames, so not filled
    }

    // MARK: - JSON Serialization

    @Test("Export and import JSON round-trip preserves data")
    func jsonRoundTrip() async throws {
        let store = TrackingDataStore()
        await store.store(makeFrame(timestampMs: 0, people: [
            makePerson(index: 0, x: 0.3, y: 0.4, width: 0.2, height: 0.3, timestampMs: 0),
        ]), smooth: false)
        await store.store(makeFrame(timestampMs: 100, people: [
            makePerson(index: 0, x: 0.5, y: 0.6, width: 0.22, height: 0.32, timestampMs: 100),
            makePerson(index: 1, x: 0.8, y: 0.2, width: 0.15, height: 0.25, timestampMs: 100),
        ]), smooth: false)

        let json = try await store.exportJSON()
        #expect(json.count > 0)

        // Import into a new store
        let store2 = TrackingDataStore()
        try await store2.importJSON(json)

        let count = await store2.frameCount
        #expect(count == 2)

        let frame0 = await store2.getResult(at: cmTime(ms: 0))
        #expect(frame0?.people.count == 1)
        #expect(frame0?.people.first?.boundingBox?.x == 0.3)

        let frame100 = await store2.getResult(at: cmTime(ms: 100))
        #expect(frame100?.people.count == 2)
    }

    // MARK: - RTS Smoothing

    @Test("Apply RTS smoothing does not crash on empty store")
    func rtsEmpty() async {
        let store = TrackingDataStore()
        await store.applyRTSSmoothing()
        #expect(await store.frameCount == 0)
    }

    @Test("Apply RTS smoothing preserves frame count after smoothing")
    func rtsPreservesFrameCount() async {
        let store = TrackingDataStore()

        // Store frames with smoothing enabled (which builds Kalman snapshots)
        for ms in stride(from: 0, through: 300, by: 33) {
            let x = 0.3 + Double(ms) / 1000.0
            await store.store(makeFrame(timestampMs: ms, people: [
                makePerson(index: 0, x: x, y: 0.5, timestampMs: ms),
            ]), smooth: true)
        }

        let countBefore = await store.frameCount
        await store.applyRTSSmoothing()
        let countAfter = await store.frameCount

        #expect(countBefore == countAfter)
    }

    // MARK: - Smoothing with Pose Joints

    @Test("Smoothing preserves pose joints")
    func smoothingWithPose() async {
        let store = TrackingDataStore()
        let pose = PoseJoints(joints: [
            "nose": CGPoint(x: 0.5, y: 0.3),
            "leftShoulder": CGPoint(x: 0.4, y: 0.5),
            "rightShoulder": CGPoint(x: 0.6, y: 0.5),
        ])

        await store.store(makeFrame(timestampMs: 0, people: [
            makePerson(index: 0, x: 0.5, y: 0.5, timestampMs: 0, pose: pose),
        ]), smooth: true)

        let result = await store.getResult(at: cmTime(ms: 0))
        #expect(result?.people.first?.pose != nil)
        #expect(result?.people.first?.pose?.joints.count == 3)
    }

    // MARK: - Identification Tracking

    @Test("Identified person is stored on first availability")
    func identifiedPersonStored() async {
        let store = TrackingDataStore()

        // First frame: not identified
        await store.store(makeFrame(timestampMs: 0, people: [
            makePerson(index: 0, timestampMs: 0),
        ]), smooth: false)

        // Second frame: identified
        await store.store(makeFrame(timestampMs: 100, people: [
            makePerson(index: 0, timestampMs: 100,
                       identifiedPersonId: "p1",
                       identifiedPersonName: "Bob",
                       identificationConfidence: 0.9),
        ]), smooth: false)

        let persons = await store.getDetectedPersons()
        #expect(persons.count == 1)
        #expect(persons[0].identifiedPersonId == "p1")
        #expect(persons[0].identifiedPersonName == "Bob")
    }
}
