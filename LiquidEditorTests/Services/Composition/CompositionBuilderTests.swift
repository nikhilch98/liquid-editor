// CompositionBuilderTests.swift
// LiquidEditorTests
//
// Tests for CompositionBuilder: build errors, progress reporting,
// cache management, and CompositionBuildError error descriptions.

import Testing
import Foundation
import AVFoundation
@testable import LiquidEditor

// MARK: - CompositionBuilder Tests

@Suite("CompositionBuilder Tests")
struct CompositionBuilderTests {

    // MARK: - Initialization

    @Suite("Initialization")
    struct InitTests {

        @Test("Creates without errors")
        func createsSuccessfully() {
            let builder = CompositionBuilder()
            _ = builder // Just verifying init doesn't crash
        }
    }

    // MARK: - Build with Empty Segments

    @Suite("Build with Empty Segments")
    struct EmptySegmentsTests {

        @Test("Build throws emptySegments for empty array")
        func throwsForEmptySegments() async {
            let builder = CompositionBuilder()
            do {
                _ = try await builder.build(segments: [], compositionId: "test")
                Issue.record("Expected emptySegments error")
            } catch let error as CompositionBuildError {
                if case .emptySegments = error {
                    // Expected
                } else {
                    Issue.record("Expected emptySegments, got \(error)")
                }
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - Build with Non-existent Asset

    @Suite("Build with Non-existent Asset")
    struct NonExistentAssetTests {

        @Test("Build throws assetNotFound for missing file")
        func throwsForMissingAsset() async {
            let builder = CompositionBuilder()
            let segment = CompositionSegment(
                clipId: "clip1",
                assetId: "asset1",
                assetURL: URL(fileURLWithPath: "/nonexistent/video.mp4"),
                sourceTimeRange: TimeRange(0, 1_000_000),
                timelineStartTime: 0,
                playbackSpeed: 1.0,
                volume: 1.0,
                trackIndex: 0
            )

            do {
                _ = try await builder.build(segments: [segment], compositionId: "test")
                Issue.record("Expected assetNotFound error")
            } catch let error as CompositionBuildError {
                if case .assetNotFound = error {
                    // Expected
                } else {
                    Issue.record("Expected assetNotFound, got \(error)")
                }
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - Progress Reporting

    @Suite("Progress Reporting")
    struct ProgressTests {

        @Test("buildWithProgress emits correct number of updates for single segment")
        func progressSingleSegment() async {
            let builder = CompositionBuilder()
            let segment = CompositionSegment(
                clipId: "c1",
                assetId: "a1",
                assetURL: URL(fileURLWithPath: "/tmp/test.mp4"),
                sourceTimeRange: TimeRange(0, 1_000_000),
                timelineStartTime: 0,
                playbackSpeed: 1.0,
                volume: 1.0,
                trackIndex: 0
            )

            var progressUpdates: [CompositionBuildProgress] = []
            let stream = builder.buildWithProgress(segments: [segment], compositionId: "test")

            for await progress in stream {
                progressUpdates.append(progress)
            }

            // Should have 1 per-segment update + 1 final
            #expect(progressUpdates.count == 2)
            #expect(progressUpdates.last?.fraction == 1.0)
            #expect(progressUpdates.last?.segmentsProcessed == 1)
            #expect(progressUpdates.last?.totalSegments == 1)
        }

        @Test("buildWithProgress emits correct updates for multiple segments")
        func progressMultipleSegments() async {
            let builder = CompositionBuilder()
            let segments = (0..<5).map { i in
                CompositionSegment(
                    clipId: "c\(i)",
                    assetId: "a\(i)",
                    assetURL: URL(fileURLWithPath: "/tmp/test\(i).mp4"),
                    sourceTimeRange: TimeRange(0, 1_000_000),
                    timelineStartTime: TimeMicros(i) * 1_000_000,
                    playbackSpeed: 1.0,
                    volume: 1.0,
                    trackIndex: 0
                )
            }

            var progressUpdates: [CompositionBuildProgress] = []
            let stream = builder.buildWithProgress(segments: segments, compositionId: "test")

            for await progress in stream {
                progressUpdates.append(progress)
            }

            // 5 per-segment + 1 final
            #expect(progressUpdates.count == 6)
            #expect(progressUpdates.last?.fraction == 1.0)
            #expect(progressUpdates.last?.segmentsProcessed == 5)
        }

        @Test("buildWithProgress with empty segments emits single 100% update")
        func progressEmptySegments() async {
            let builder = CompositionBuilder()
            var updates: [CompositionBuildProgress] = []

            let stream = builder.buildWithProgress(segments: [], compositionId: "test")

            for await progress in stream {
                updates.append(progress)
            }

            // Should still emit the final 100% update
            #expect(updates.count == 1)
            #expect(updates[0].fraction == 1.0)
            #expect(updates[0].totalSegments == 0)
        }

        @Test("Progress fraction increases monotonically")
        func progressFractionMonotonic() async {
            let builder = CompositionBuilder()
            let segments = (0..<10).map { i in
                CompositionSegment(
                    clipId: "c\(i)",
                    assetId: "a\(i)",
                    assetURL: URL(fileURLWithPath: "/tmp/test\(i).mp4"),
                    sourceTimeRange: TimeRange(0, 1_000_000),
                    timelineStartTime: TimeMicros(i) * 1_000_000,
                    playbackSpeed: 1.0,
                    volume: 1.0,
                    trackIndex: 0
                )
            }

            var fractions: [Double] = []
            let stream = builder.buildWithProgress(segments: segments, compositionId: "test")

            for await progress in stream {
                fractions.append(progress.fraction)
            }

            // Verify monotonically non-decreasing
            for i in 1..<fractions.count {
                #expect(fractions[i] >= fractions[i - 1])
            }
        }
    }

    // MARK: - Cache Management

    @Suite("Cache Management")
    struct CacheTests {

        @Test("clearCache does not crash on empty cache")
        func clearEmptyCache() {
            let builder = CompositionBuilder()
            builder.clearCache()
        }

        @Test("clearCache can be called multiple times")
        func clearMultipleTimes() {
            let builder = CompositionBuilder()
            builder.clearCache()
            builder.clearCache()
            builder.clearCache()
        }
    }

    // MARK: - CompositionBuildProgress

    @Suite("CompositionBuildProgress")
    struct BuildProgressTests {

        @Test("Properties are correctly initialized")
        func propertiesCorrect() {
            let progress = CompositionBuildProgress(
                fraction: 0.5,
                segmentsProcessed: 5,
                totalSegments: 10
            )
            #expect(progress.fraction == 0.5)
            #expect(progress.segmentsProcessed == 5)
            #expect(progress.totalSegments == 10)
        }

        @Test("Zero fraction is valid")
        func zeroFraction() {
            let progress = CompositionBuildProgress(
                fraction: 0.0,
                segmentsProcessed: 0,
                totalSegments: 5
            )
            #expect(progress.fraction == 0.0)
        }

        @Test("Full fraction is valid")
        func fullFraction() {
            let progress = CompositionBuildProgress(
                fraction: 1.0,
                segmentsProcessed: 3,
                totalSegments: 3
            )
            #expect(progress.fraction == 1.0)
        }
    }

    // MARK: - BuiltComposition

    @Suite("BuiltComposition")
    struct BuiltCompositionTests {

        @Test("totalDuration converts correctly from microseconds")
        func totalDurationConversion() {
            let composition = AVMutableComposition()
            let built = BuiltComposition(
                id: "test",
                composition: composition,
                videoComposition: nil,
                audioMix: nil,
                totalDurationMicros: 5_000_000,
                renderSize: CGSize(width: 1920, height: 1080)
            )

            let duration = built.totalDuration
            let seconds = CMTimeGetSeconds(duration)
            #expect(abs(seconds - 5.0) < 0.001)
        }

        @Test("Properties are stored correctly")
        func propertiesStored() {
            let composition = AVMutableComposition()
            let renderSize = CGSize(width: 3840, height: 2160)
            let built = BuiltComposition(
                id: "build_42",
                composition: composition,
                videoComposition: nil,
                audioMix: nil,
                totalDurationMicros: 10_000_000,
                renderSize: renderSize
            )

            #expect(built.id == "build_42")
            #expect(built.totalDurationMicros == 10_000_000)
            #expect(built.renderSize == renderSize)
            #expect(built.videoComposition == nil)
            #expect(built.audioMix == nil)
        }
    }
}

// MARK: - CompositionBuildError Tests

@Suite("CompositionBuildError")
struct CompositionBuildErrorTests {

    @Test("emptySegments error description")
    func emptySegmentsDescription() {
        let error = CompositionBuildError.emptySegments
        #expect(error.errorDescription?.contains("empty") == true)
    }

    @Test("failedToCreateTrack error description")
    func failedToCreateTrackDescription() {
        let error = CompositionBuildError.failedToCreateTrack("video", 0)
        #expect(error.errorDescription?.contains("video") == true)
        #expect(error.errorDescription?.contains("0") == true)
    }

    @Test("assetNotFound error description")
    func assetNotFoundDescription() {
        let error = CompositionBuildError.assetNotFound("/path/to/video.mp4")
        #expect(error.errorDescription?.contains("/path/to/video.mp4") == true)
    }

    @Test("noVideoTrack error description")
    func noVideoTrackDescription() {
        let error = CompositionBuildError.noVideoTrack
        #expect(error.errorDescription?.contains("video") == true)
    }

    @Test("noAudioTrack error description")
    func noAudioTrackDescription() {
        let error = CompositionBuildError.noAudioTrack
        #expect(error.errorDescription?.contains("audio") == true)
    }

    @Test("invalidTimeRange error description")
    func invalidTimeRangeDescription() {
        let error = CompositionBuildError.invalidTimeRange
        #expect(error.errorDescription?.contains("time range") == true)
    }

    @Test("invalidSegmentDuration error description")
    func invalidSegmentDurationDescription() {
        let error = CompositionBuildError.invalidSegmentDuration(42_000)
        #expect(error.errorDescription?.contains("42000") == true)
    }

    @Test("All errors conform to LocalizedError")
    func allErrorsHaveDescriptions() {
        let errors: [CompositionBuildError] = [
            .emptySegments,
            .failedToCreateTrack("audio", 1),
            .assetNotFound("/test"),
            .noVideoTrack,
            .noAudioTrack,
            .invalidTimeRange,
            .invalidSegmentDuration(0),
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - CompositionSegment Tests

@Suite("CompositionSegment")
struct CompositionSegmentTests {

    @Test("Properties are stored correctly")
    func propertiesStored() {
        let url = URL(fileURLWithPath: "/tmp/video.mp4")
        let segment = CompositionSegment(
            clipId: "clip1",
            assetId: "asset1",
            assetURL: url,
            sourceTimeRange: TimeRange(100_000, 2_000_000),
            timelineStartTime: 500_000,
            playbackSpeed: 2.0,
            volume: 0.5,
            trackIndex: 1
        )

        #expect(segment.clipId == "clip1")
        #expect(segment.assetId == "asset1")
        #expect(segment.assetURL == url)
        #expect(segment.sourceTimeRange.start == 100_000)
        #expect(segment.sourceTimeRange.duration == 1_900_000)
        #expect(segment.timelineStartTime == 500_000)
        #expect(segment.playbackSpeed == 2.0)
        #expect(segment.volume == 0.5)
        #expect(segment.trackIndex == 1)
    }

    @Test("Equatable conformance works")
    func equatable() {
        let url = URL(fileURLWithPath: "/tmp/video.mp4")
        let segment1 = CompositionSegment(
            clipId: "c1", assetId: "a1", assetURL: url,
            sourceTimeRange: TimeRange(0, 1_000_000),
            timelineStartTime: 0, playbackSpeed: 1.0, volume: 1.0, trackIndex: 0
        )
        let segment2 = CompositionSegment(
            clipId: "c1", assetId: "a1", assetURL: url,
            sourceTimeRange: TimeRange(0, 1_000_000),
            timelineStartTime: 0, playbackSpeed: 1.0, volume: 1.0, trackIndex: 0
        )
        let segment3 = CompositionSegment(
            clipId: "c2", assetId: "a1", assetURL: url,
            sourceTimeRange: TimeRange(0, 1_000_000),
            timelineStartTime: 0, playbackSpeed: 1.0, volume: 1.0, trackIndex: 0
        )

        #expect(segment1 == segment2)
        #expect(segment1 != segment3)
    }
}
