// JLCutServiceTests.swift
// LiquidEditorTests
//
// Tests for JLCutService.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("JLCutService")
@MainActor
struct JLCutServiceTests {

    // MARK: - Helpers

    private func makeService() -> JLCutService {
        JLCutService()
    }

    private func makeVideoClip(
        id: String = "video-1",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 5_000_000,
        linkedClipId: String? = "audio-1"
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: "track-video",
            type: .video,
            startTime: startTime,
            duration: duration,
            sourceIn: 0,
            sourceOut: duration,
            linkedClipId: linkedClipId
        )
    }

    private func makeAudioClip(
        id: String = "audio-1",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 5_000_000,
        linkedClipId: String? = "video-1"
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: "track-audio",
            type: .audio,
            startTime: startTime,
            duration: duration,
            sourceIn: 0,
            sourceOut: duration,
            linkedClipId: linkedClipId
        )
    }

    private var defaultClips: [TimelineClip] {
        [makeVideoClip(), makeAudioClip()]
    }

    // MARK: - Find Linked Clips

    @Test("findLinkedAudioClip finds linked audio")
    func findLinkedAudio() {
        let service = makeService()
        let video = makeVideoClip()
        let audio = makeAudioClip()
        let result = service.findLinkedAudioClip(video, allClips: [video, audio])
        #expect(result?.id == "audio-1")
    }

    @Test("findLinkedAudioClip returns nil when no link")
    func findLinkedAudioNoLink() {
        let service = makeService()
        let video = makeVideoClip(linkedClipId: nil)
        let result = service.findLinkedAudioClip(video, allClips: [video])
        #expect(result == nil)
    }

    @Test("findLinkedVideoClip finds linked video")
    func findLinkedVideo() {
        let service = makeService()
        let video = makeVideoClip()
        let audio = makeAudioClip()
        let result = service.findLinkedVideoClip(audio, allClips: [video, audio])
        #expect(result?.id == "video-1")
    }

    // MARK: - Validation

    @Test("validateJLCut succeeds for valid clip pair")
    func validateValid() {
        let service = makeService()
        let result = service.validateJLCut("video-1", allClips: defaultClips)
        #expect(result.isValid == true)
        #expect(result.videoClip?.id == "video-1")
        #expect(result.audioClip?.id == "audio-1")
        #expect(result.maxOverlap > 0)
    }

    @Test("validateJLCut succeeds when starting from audio clip")
    func validateFromAudio() {
        let service = makeService()
        let result = service.validateJLCut("audio-1", allClips: defaultClips)
        #expect(result.isValid == true)
        #expect(result.videoClip?.id == "video-1")
        #expect(result.audioClip?.id == "audio-1")
    }

    @Test("validateJLCut fails for clip not found")
    func validateClipNotFound() {
        let service = makeService()
        let result = service.validateJLCut("nonexistent", allClips: defaultClips)
        #expect(result.isValid == false)
        #expect(result.error?.contains("not found") == true)
    }

    @Test("validateJLCut fails for clip without linked partner")
    func validateNoLinkedPartner() {
        let service = makeService()
        let clip = makeVideoClip(linkedClipId: nil)
        let result = service.validateJLCut("video-1", allClips: [clip])
        #expect(result.isValid == false)
        #expect(result.error?.contains("no linked") == true)
    }

    @Test("validateJLCut fails for non-AV clip types")
    func validateNonAVClip() {
        let service = makeService()
        let textClip = TimelineClip(
            id: "text-1",
            trackId: "t1",
            type: .text,
            startTime: 0,
            duration: 1_000_000,
            linkedClipId: "audio-1"
        )
        let audio = makeAudioClip(linkedClipId: "text-1")
        let result = service.validateJLCut("text-1", allClips: [textClip, audio])
        #expect(result.isValid == false)
    }

    @Test("validateJLCut fails for clips too short")
    func validateTooShort() {
        let service = makeService()
        // Very short clips where maxOverlap < minOverlap
        let video = makeVideoClip(duration: 100_000) // 100ms
        let audio = makeAudioClip(duration: 100_000)
        let result = service.validateJLCut("video-1", allClips: [video, audio])
        #expect(result.isValid == false)
        #expect(result.error?.contains("too short") == true)
    }

    // MARK: - J-Cut Preview

    @Test("createJCutPreview creates valid preview")
    func jCutPreview() {
        let service = makeService()
        let video = makeVideoClip(startTime: 1_000_000)
        // Audio needs sourceIn >= overlapDuration (500_000) so the J-cut can extend backward.
        let audio = TimelineClip(
            id: "audio-1",
            trackId: "track-audio",
            type: .audio,
            startTime: 1_000_000,
            duration: 5_000_000,
            sourceIn: 500_000,
            sourceOut: 5_500_000,
            linkedClipId: "video-1"
        )
        let preview = service.createJCutPreview(
            videoClip: video,
            audioClip: audio,
            overlapDuration: 500_000
        )
        #expect(preview != nil)
        #expect(preview?.cutType == .jCut)
        #expect(preview?.updatedAudioClip.startTime == 500_000) // 1M - 500k
        #expect(preview?.updatedAudioClip.duration == 5_500_000) // 5M + 500k
        #expect(preview?.overlapDuration == 500_000)
        #expect(preview?.description.contains("J-Cut") == true)
    }

    @Test("createJCutPreview returns nil for overlap below minimum")
    func jCutPreviewBelowMinimum() {
        let service = makeService()
        let preview = service.createJCutPreview(
            videoClip: makeVideoClip(),
            audioClip: makeAudioClip(),
            overlapDuration: 50_000 // Below 100ms minimum
        )
        #expect(preview == nil)
    }

    @Test("createJCutPreview returns nil when would go before timeline start")
    func jCutPreviewBeforeStart() {
        let service = makeService()
        let video = makeVideoClip(startTime: 50_000) // Close to start
        let audio = makeAudioClip(startTime: 50_000)
        let preview = service.createJCutPreview(
            videoClip: video,
            audioClip: audio,
            overlapDuration: 200_000 // Would push audio to -150_000
        )
        #expect(preview == nil)
    }

    // MARK: - L-Cut Preview

    @Test("createLCutPreview creates valid preview")
    func lCutPreview() {
        let service = makeService()
        let video = makeVideoClip()
        let audio = makeAudioClip()
        let preview = service.createLCutPreview(
            videoClip: video,
            audioClip: audio,
            overlapDuration: 500_000
        )
        #expect(preview != nil)
        #expect(preview?.cutType == .lCut)
        #expect(preview?.updatedAudioClip.duration == 5_500_000) // 5M + 500k
        #expect(preview?.overlapDuration == 500_000)
        #expect(preview?.description.contains("L-Cut") == true)
    }

    @Test("createLCutPreview returns nil for overlap below minimum")
    func lCutPreviewBelowMinimum() {
        let service = makeService()
        let preview = service.createLCutPreview(
            videoClip: makeVideoClip(),
            audioClip: makeAudioClip(),
            overlapDuration: 50_000
        )
        #expect(preview == nil)
    }

    // MARK: - Apply J/L Cut

    @Test("applyJLCut returns success for J-cut")
    func applyJCut() {
        let service = makeService()
        let preview = JLCutPreview(
            cutType: .jCut,
            updatedVideoClip: makeVideoClip(),
            updatedAudioClip: makeAudioClip(startTime: -500_000, duration: 5_500_000),
            overlapDuration: 500_000,
            description: "J-Cut"
        )
        let result = service.applyJLCut(preview)
        #expect(result.success == true)
        #expect(result.operationName == "Apply J-Cut")
    }

    @Test("applyJLCut returns success for L-cut")
    func applyLCut() {
        let service = makeService()
        let preview = JLCutPreview(
            cutType: .lCut,
            updatedVideoClip: makeVideoClip(),
            updatedAudioClip: makeAudioClip(duration: 5_500_000),
            overlapDuration: 500_000,
            description: "L-Cut"
        )
        let result = service.applyJLCut(preview)
        #expect(result.success == true)
        #expect(result.operationName == "Apply L-Cut")
    }

    // MARK: - Reset J/L Cut

    @Test("resetJLCut synchronizes audio to video boundaries")
    func resetCut() {
        let service = makeService()
        let video = makeVideoClip(startTime: 1_000_000, duration: 3_000_000)
        let audio = makeAudioClip(startTime: 500_000, duration: 4_000_000)

        let result = service.resetJLCut(videoClip: video, audioClip: audio)
        #expect(result.success == true)
        #expect(result.updatedAudioClip?.startTime == 1_000_000)
        #expect(result.updatedAudioClip?.duration == 3_000_000)
        #expect(result.operationName == "Reset J/L Cut")
    }

    // MARK: - Detect Existing Cut

    @Test("detectExistingCut returns nil for synchronized clips")
    func detectNoCut() {
        let service = makeService()
        let video = makeVideoClip(startTime: 1_000_000)
        let audio = makeAudioClip(startTime: 1_000_000)
        let result = service.detectExistingCut(videoClip: video, audioClip: audio)
        #expect(result == nil)
    }

    @Test("detectExistingCut detects J-cut (audio starts earlier)")
    func detectJCut() {
        let service = makeService()
        let video = makeVideoClip(startTime: 1_000_000)
        let audio = makeAudioClip(startTime: 500_000) // Audio leads by 500k
        let result = service.detectExistingCut(videoClip: video, audioClip: audio)
        #expect(result != nil)
        #expect(result?.type == .jCut)
        #expect(result?.overlap == 500_000)
    }

    @Test("detectExistingCut detects L-cut (audio ends later)")
    func detectLCut() {
        let service = makeService()
        let video = makeVideoClip(startTime: 0, duration: 3_000_000)
        let audio = makeAudioClip(startTime: 0, duration: 4_000_000) // Audio trails by 1M
        let result = service.detectExistingCut(videoClip: video, audioClip: audio)
        #expect(result != nil)
        #expect(result?.type == .lCut)
        #expect(result?.overlap == 1_000_000)
    }

    // MARK: - Drag Handle Offsets

    @Test("getDragHandleOffsets calculates correctly for J-cut")
    func dragHandleOffsetsJCut() {
        let service = makeService()
        let video = makeVideoClip(startTime: 1_000_000)
        let audio = makeAudioClip(startTime: 500_000) // 500k lead
        let offsets = service.getDragHandleOffsets(
            videoClip: video,
            audioClip: audio,
            microsPerPixel: 10_000
        )
        #expect(offsets.audioLeadPixels == 50.0) // 500_000 / 10_000
        #expect(offsets.audioTrailPixels == 0.0)
    }

    @Test("getDragHandleOffsets calculates correctly for L-cut")
    func dragHandleOffsetsLCut() {
        let service = makeService()
        let video = makeVideoClip(startTime: 0, duration: 3_000_000)
        let audio = makeAudioClip(startTime: 0, duration: 4_000_000) // 1M trail
        let offsets = service.getDragHandleOffsets(
            videoClip: video,
            audioClip: audio,
            microsPerPixel: 10_000
        )
        #expect(offsets.audioLeadPixels == 0.0)
        #expect(offsets.audioTrailPixels == 100.0) // 1_000_000 / 10_000
    }

    @Test("getDragHandleOffsets returns zeros for synchronized clips")
    func dragHandleOffsetsSynced() {
        let service = makeService()
        let video = makeVideoClip()
        let audio = makeAudioClip()
        let offsets = service.getDragHandleOffsets(
            videoClip: video,
            audioClip: audio,
            microsPerPixel: 10_000
        )
        #expect(offsets.audioLeadPixels == 0.0)
        #expect(offsets.audioTrailPixels == 0.0)
    }

    // MARK: - Additional Validation Edge Cases

    @Test("validateJLCut fails when linked clip is missing from allClips")
    func validateLinkedClipMissing() {
        let service = makeService()
        let video = makeVideoClip(linkedClipId: "audio-missing")
        let result = service.validateJLCut("video-1", allClips: [video])
        #expect(result.isValid == false)
        #expect(result.error?.contains("Linked clip not found") == true)
    }

    @Test("validateJLCut fails for two video clips linked together")
    func validateTwoVideoClips() {
        let service = makeService()
        let video1 = TimelineClip(
            id: "v1", trackId: "t1", type: .video, startTime: 0,
            duration: 2_000_000, linkedClipId: "v2"
        )
        let video2 = TimelineClip(
            id: "v2", trackId: "t1", type: .video, startTime: 0,
            duration: 2_000_000, linkedClipId: "v1"
        )
        let result = service.validateJLCut("v1", allClips: [video1, video2])
        #expect(result.isValid == false)
        #expect(result.error?.contains("video+audio pair") == true)
    }

    @Test("validateJLCut maxOverlap is 50% of shorter clip")
    func validateMaxOverlapCalculation() {
        let service = makeService()
        let video = makeVideoClip(duration: 4_000_000)
        let audio = makeAudioClip(duration: 2_000_000) // Shorter
        let result = service.validateJLCut("video-1", allClips: [video, audio])
        #expect(result.isValid == true)
        // maxOverlap = 50% of 2M = 1M
        #expect(result.maxOverlap == 1_000_000)
    }

    // MARK: - Additional J-Cut Edge Cases

    @Test("createJCutPreview returns nil when audio sourceIn too small")
    func jCutPreviewInsufficientSource() {
        let service = makeService()
        let video = makeVideoClip(startTime: 1_000_000)
        // Audio sourceIn is 0, so extending backward by 500k would make newSourceIn negative
        let audio = TimelineClip(
            id: "audio-1", trackId: "track-audio", type: .audio,
            startTime: 1_000_000, duration: 5_000_000,
            sourceIn: 0, sourceOut: 5_000_000, linkedClipId: "video-1"
        )
        let preview = service.createJCutPreview(
            videoClip: video, audioClip: audio, overlapDuration: 500_000
        )
        #expect(preview == nil)
    }

    @Test("createJCutPreview preserves video clip unchanged")
    func jCutPreviewVideoUnchanged() {
        let service = makeService()
        let video = makeVideoClip(startTime: 2_000_000, duration: 3_000_000)
        let audio = TimelineClip(
            id: "audio-1", trackId: "track-audio", type: .audio,
            startTime: 2_000_000, duration: 3_000_000,
            sourceIn: 1_000_000, sourceOut: 4_000_000, linkedClipId: "video-1"
        )
        let preview = service.createJCutPreview(
            videoClip: video, audioClip: audio, overlapDuration: 500_000
        )
        #expect(preview != nil)
        #expect(preview?.updatedVideoClip == video)
    }

    @Test("createJCutPreview exactly at minimum overlap succeeds")
    func jCutPreviewExactMinimum() {
        let service = makeService()
        let video = makeVideoClip(startTime: 1_000_000)
        let audio = TimelineClip(
            id: "audio-1", trackId: "track-audio", type: .audio,
            startTime: 1_000_000, duration: 5_000_000,
            sourceIn: 200_000, sourceOut: 5_200_000, linkedClipId: "video-1"
        )
        let preview = service.createJCutPreview(
            videoClip: video, audioClip: audio,
            overlapDuration: JLCutService.minOverlap // Exactly 100_000
        )
        #expect(preview != nil)
    }

    // MARK: - Additional L-Cut Edge Cases

    @Test("createLCutPreview preserves video clip unchanged")
    func lCutPreviewVideoUnchanged() {
        let service = makeService()
        let video = makeVideoClip()
        let audio = makeAudioClip()
        let preview = service.createLCutPreview(
            videoClip: video, audioClip: audio, overlapDuration: 500_000
        )
        #expect(preview?.updatedVideoClip == video)
    }

    @Test("createLCutPreview description contains seconds value")
    func lCutPreviewDescriptionSeconds() {
        let service = makeService()
        let video = makeVideoClip()
        let audio = makeAudioClip()
        let preview = service.createLCutPreview(
            videoClip: video, audioClip: audio, overlapDuration: 1_500_000
        )
        #expect(preview?.description.contains("1.5") == true)
    }

    // MARK: - Additional Apply and Reset

    @Test("applyJLCut preserves clips from preview")
    func applyPreservesClips() {
        let service = makeService()
        let video = makeVideoClip(startTime: 1_000_000)
        let audio = makeAudioClip(startTime: 500_000, duration: 5_500_000)
        let preview = JLCutPreview(
            cutType: .jCut, updatedVideoClip: video, updatedAudioClip: audio,
            overlapDuration: 500_000, description: "J-Cut: Audio leads by 0.5s"
        )
        let result = service.applyJLCut(preview)
        #expect(result.updatedVideoClip == video)
        #expect(result.updatedAudioClip == audio)
    }

    @Test("resetJLCut syncs source in and out")
    func resetSyncsSourcePoints() {
        let service = makeService()
        let video = TimelineClip(
            id: "video-1", trackId: "track-video", type: .video,
            startTime: 1_000_000, duration: 3_000_000,
            sourceIn: 500_000, sourceOut: 3_500_000, linkedClipId: "audio-1"
        )
        let audio = makeAudioClip(startTime: 500_000, duration: 4_000_000)
        let result = service.resetJLCut(videoClip: video, audioClip: audio)
        #expect(result.updatedAudioClip?.sourceIn == video.sourceIn)
        #expect(result.updatedAudioClip?.sourceOut == video.sourceOut)
    }

    // MARK: - Additional Detection Edge Cases

    @Test("detectExistingCut returns nil when audio is shorter but aligned start")
    func detectAudioShorterAlignedStart() {
        let service = makeService()
        let video = makeVideoClip(startTime: 0, duration: 5_000_000)
        let audio = makeAudioClip(startTime: 0, duration: 3_000_000)
        // startTime matches, endTime: audio (3M) < video (5M) -- not J or L cut
        let result = service.detectExistingCut(videoClip: video, audioClip: audio)
        #expect(result == nil)
    }

    // MARK: - Type Enums and Static Constructors

    @Test("JLCutType allCases contains both types")
    func jlCutTypeAllCases() {
        #expect(JLCutType.allCases.count == 2)
        #expect(JLCutType.allCases.contains(.jCut))
        #expect(JLCutType.allCases.contains(.lCut))
    }

    @Test("JLCutValidation.valid factory creates valid result")
    func validationValidFactory() {
        let video = makeVideoClip()
        let audio = makeAudioClip()
        let validation = JLCutValidation.valid(videoClip: video, audioClip: audio, maxOverlap: 1_000_000)
        #expect(validation.isValid == true)
        #expect(validation.error == nil)
        #expect(validation.maxOverlap == 1_000_000)
    }

    @Test("JLCutValidation.invalid factory creates invalid result")
    func validationInvalidFactory() {
        let validation = JLCutValidation.invalid("test error")
        #expect(validation.isValid == false)
        #expect(validation.error == "test error")
        #expect(validation.videoClip == nil)
        #expect(validation.audioClip == nil)
    }

    @Test("JLCutResult.failure creates failed result")
    func resultFailureFactory() {
        let result = JLCutResult.failure("something went wrong")
        #expect(result.success == false)
        #expect(result.error == "something went wrong")
        #expect(result.updatedVideoClip == nil)
        #expect(result.updatedAudioClip == nil)
        #expect(result.operationName == "J/L Cut")
    }

    @Test("JLCutDragHandleOffsets equality")
    func dragHandleOffsetsEquality() {
        let a = JLCutDragHandleOffsets(audioLeadPixels: 10.0, audioTrailPixels: 20.0)
        let b = JLCutDragHandleOffsets(audioLeadPixels: 10.0, audioTrailPixels: 20.0)
        let c = JLCutDragHandleOffsets(audioLeadPixels: 5.0, audioTrailPixels: 20.0)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Constants

    @Test("minOverlap is 100ms")
    func minOverlapConstant() {
        #expect(JLCutService.minOverlap == 100_000)
    }

    @Test("maxOverlapFraction is 0.5")
    func maxOverlapFractionConstant() {
        #expect(JLCutService.maxOverlapFraction == 0.5)
    }

    // MARK: - findLinkedVideoClip returns nil when no link

    @Test("findLinkedVideoClip returns nil when audio has no link")
    func findLinkedVideoNoLink() {
        let service = makeService()
        let audio = makeAudioClip(linkedClipId: nil)
        let result = service.findLinkedVideoClip(audio, allClips: [audio])
        #expect(result == nil)
    }
}
