// TextClipManagerTests.swift
// LiquidEditorTests
//
// Tests for TextClipManager: creation, modification, render state,
// and edge cases for the stateless text clip service.

import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - TextClipManager Creation Tests

@Suite("TextClipManager - Creation")
struct TextClipManagerCreationTests {

    @Test("createDefault creates a text clip with correct type")
    func createsTextType() {
        let clip = TextClipManager.createDefault(trackId: "track1")
        #expect(clip.type == .text)
    }

    @Test("createDefault uses provided trackId")
    func usesTrackId() {
        let clip = TextClipManager.createDefault(trackId: "overlay_track")
        #expect(clip.trackId == "overlay_track")
    }

    @Test("createDefault uses default text 'Text'")
    func defaultText() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        #expect(clip.label == "Text")
    }

    @Test("createDefault with custom text")
    func customText() {
        let clip = TextClipManager.createDefault(trackId: "t1", text: "Hello World")
        #expect(clip.label == "Hello World")
    }

    @Test("createDefault uses default start time of 0")
    func defaultStartTime() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        #expect(clip.startTime == 0)
    }

    @Test("createDefault with custom start time")
    func customStartTime() {
        let clip = TextClipManager.createDefault(trackId: "t1", startTime: 5_000_000)
        #expect(clip.startTime == 5_000_000)
    }

    @Test("createDefault uses default duration of 3 seconds")
    func defaultDuration() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        #expect(clip.duration == 3_000_000)
    }

    @Test("createDefault with custom duration")
    func customDuration() {
        let clip = TextClipManager.createDefault(trackId: "t1", durationMicros: 10_000_000)
        #expect(clip.duration == 10_000_000)
    }

    @Test("createDefault generates a unique ID")
    func uniqueId() {
        let clip1 = TextClipManager.createDefault(trackId: "t1")
        let clip2 = TextClipManager.createDefault(trackId: "t1")
        #expect(clip1.id != clip2.id)
    }

    @Test("createDefault clip has no mediaAssetId")
    func noMediaAssetId() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        #expect(clip.mediaAssetId == nil)
    }

    @Test("createDefault clip is a generator clip")
    func isGeneratorClip() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        #expect(clip.isGeneratorClip == true)
    }

    @Test("createDefault with all custom parameters")
    func allCustomParameters() {
        let clip = TextClipManager.createDefault(
            trackId: "custom_track",
            text: "Custom Title",
            startTime: 2_000_000,
            durationMicros: 5_000_000
        )

        #expect(clip.trackId == "custom_track")
        #expect(clip.label == "Custom Title")
        #expect(clip.startTime == 2_000_000)
        #expect(clip.duration == 5_000_000)
        #expect(clip.type == .text)
    }
}

// MARK: - TextClipManager Modification Tests

@Suite("TextClipManager - Modification")
struct TextClipManagerModificationTests {

    @Test("updateText changes the label")
    func updateTextChangesLabel() {
        let clip = TextClipManager.createDefault(trackId: "t1", text: "Original")
        let updated = TextClipManager.updateText(clip, newText: "Updated")

        #expect(updated.label == "Updated")
    }

    @Test("updateText preserves other properties")
    func updateTextPreservesOther() {
        let clip = TextClipManager.createDefault(
            trackId: "t1", text: "Original", startTime: 1_000_000, durationMicros: 5_000_000
        )
        let updated = TextClipManager.updateText(clip, newText: "New")

        #expect(updated.id == clip.id)
        #expect(updated.trackId == "t1")
        #expect(updated.startTime == 1_000_000)
        #expect(updated.duration == 5_000_000)
        #expect(updated.type == .text)
    }

    @Test("updateText with empty string")
    func updateTextEmpty() {
        let clip = TextClipManager.createDefault(trackId: "t1", text: "Something")
        let updated = TextClipManager.updateText(clip, newText: "")

        #expect(updated.label == "")
    }

    @Test("updatePosition changes start time")
    func updatePositionChangesStartTime() {
        let clip = TextClipManager.createDefault(trackId: "t1", startTime: 0)
        let updated = TextClipManager.updatePosition(clip, newStartTime: 3_000_000)

        #expect(updated.startTime == 3_000_000)
    }

    @Test("updatePosition preserves other properties")
    func updatePositionPreservesOther() {
        let clip = TextClipManager.createDefault(
            trackId: "t1", text: "Title", startTime: 0, durationMicros: 2_000_000
        )
        let updated = TextClipManager.updatePosition(clip, newStartTime: 5_000_000)

        #expect(updated.label == "Title")
        #expect(updated.duration == 2_000_000)
        #expect(updated.trackId == "t1")
    }

    @Test("updateDuration changes duration")
    func updateDurationChangesDuration() {
        let clip = TextClipManager.createDefault(trackId: "t1", durationMicros: 3_000_000)
        let updated = TextClipManager.updateDuration(clip, newDuration: 7_000_000)

        #expect(updated.duration == 7_000_000)
    }

    @Test("updateDuration enforces minimum duration")
    func updateDurationEnforcesMinimum() {
        let clip = TextClipManager.createDefault(trackId: "t1", durationMicros: 3_000_000)
        let updated = TextClipManager.updateDuration(clip, newDuration: 100)

        // Should enforce TimelineClip.minDuration
        #expect(updated.duration == TimelineClip.minDuration)
    }

    @Test("updateDuration preserves other properties")
    func updateDurationPreservesOther() {
        let clip = TextClipManager.createDefault(
            trackId: "t1", text: "Title", startTime: 1_000_000
        )
        let updated = TextClipManager.updateDuration(clip, newDuration: 10_000_000)

        #expect(updated.label == "Title")
        #expect(updated.startTime == 1_000_000)
        #expect(updated.trackId == "t1")
    }

    @Test("moveToTrack changes track ID")
    func moveToTrackChangesTrack() {
        let clip = TextClipManager.createDefault(trackId: "track1")
        let moved = TextClipManager.moveToTrack(clip, trackId: "track2")

        #expect(moved.trackId == "track2")
    }

    @Test("moveToTrack preserves other properties")
    func moveToTrackPreservesOther() {
        let clip = TextClipManager.createDefault(
            trackId: "track1", text: "Title", startTime: 2_000_000, durationMicros: 4_000_000
        )
        let moved = TextClipManager.moveToTrack(clip, trackId: "track2")

        #expect(moved.label == "Title")
        #expect(moved.startTime == 2_000_000)
        #expect(moved.duration == 4_000_000)
        #expect(moved.id == clip.id)
    }
}

// MARK: - TextClipManager Render State Tests

@Suite("TextClipManager - Render State")
struct TextClipManagerRenderStateTests {

    @Test("computeRenderState returns correct clipId")
    func renderStateClipId() {
        let clip = TextClipManager.createDefault(trackId: "t1", text: "Hello")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.clipId == clip.id)
    }

    @Test("computeRenderState returns clip label as text")
    func renderStateText() {
        let clip = TextClipManager.createDefault(trackId: "t1", text: "Hello World")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.text == "Hello World")
    }

    @Test("computeRenderState defaults to 'Text' when label is nil")
    func renderStateDefaultText() {
        // Create a clip with nil label directly
        let clip = TimelineClip(
            trackId: "t1",
            type: .text,
            startTime: 0,
            duration: 1_000_000,
            label: nil
        )
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.text == "Text")
    }

    @Test("computeRenderState has centered position")
    func renderStatePosition() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 500_000)

        #expect(state.position.x == 0.5)
        #expect(state.position.y == 0.5)
    }

    @Test("computeRenderState has default scale of 1.0")
    func renderStateScale() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.scale == 1.0)
    }

    @Test("computeRenderState has default rotation of 0.0")
    func renderStateRotation() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.rotation == 0.0)
    }

    @Test("computeRenderState has default opacity of 1.0")
    func renderStateOpacity() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.opacity == 1.0)
    }

    @Test("computeRenderState has maxWidthFraction of 0.8")
    func renderStateMaxWidth() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.maxWidthFraction == 0.8)
    }

    @Test("computeRenderState has isSubtitle as false")
    func renderStateNotSubtitle() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.isSubtitle == false)
    }

    @Test("computeRenderState has visibleCharCount of -1 (all chars)")
    func renderStateAllCharsVisible() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.visibleCharCount == -1)
    }

    @Test("computeRenderState has blurSigma of 0.0")
    func renderStateNoBlur() {
        let clip = TextClipManager.createDefault(trackId: "t1")
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        #expect(state.blurSigma == 0.0)
    }

    @Test("computeRenderState at beginning of clip")
    func renderStateAtStart() {
        let clip = TextClipManager.createDefault(trackId: "t1", durationMicros: 3_000_000)
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        // At start, progress should be 0
        #expect(state.opacity == 1.0)
    }

    @Test("computeRenderState at middle of clip")
    func renderStateAtMiddle() {
        let clip = TextClipManager.createDefault(trackId: "t1", durationMicros: 2_000_000)
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 1_000_000)

        // Progress is 0.5
        #expect(state.opacity == 1.0)
    }

    @Test("computeRenderState at end of clip")
    func renderStateAtEnd() {
        let clip = TextClipManager.createDefault(trackId: "t1", durationMicros: 2_000_000)
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 2_000_000)

        // Progress clamped to 1.0
        #expect(state.opacity == 1.0)
    }

    @Test("computeRenderState with zero-duration clip does not crash")
    func renderStateZeroDuration() {
        let clip = TimelineClip(
            trackId: "t1",
            type: .text,
            startTime: 0,
            duration: 0,
            label: "Zero"
        )
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 0)

        // Should not crash, progress would be 0 due to division guard
        #expect(state.text == "Zero")
    }

    @Test("computeRenderState beyond clip duration clamps progress")
    func renderStateBeyondDuration() {
        let clip = TextClipManager.createDefault(trackId: "t1", durationMicros: 1_000_000)
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: 5_000_000)

        // Progress clamps to 1.0
        #expect(state.opacity == 1.0)
    }

    @Test("computeRenderState with negative offset clamps progress")
    func renderStateNegativeOffset() {
        let clip = TextClipManager.createDefault(trackId: "t1", durationMicros: 1_000_000)
        let state = TextClipManager.computeRenderState(clip, clipOffsetMicros: -500_000)

        // Progress clamps to 0.0
        #expect(state.opacity == 1.0)
    }
}

// MARK: - TextRenderState Equatable Tests

@Suite("TextRenderState - Equatable")
struct TextRenderStateEquatableTests {

    @Test("Equal states are equal")
    func equalStates() {
        let state1 = TextRenderState(
            clipId: "c1", text: "Hello", position: CGPoint(x: 0.5, y: 0.5),
            scale: 1.0, rotation: 0.0, opacity: 1.0, maxWidthFraction: 0.8,
            isSubtitle: false, visibleCharCount: -1, blurSigma: 0.0
        )
        let state2 = TextRenderState(
            clipId: "c1", text: "Hello", position: CGPoint(x: 0.5, y: 0.5),
            scale: 1.0, rotation: 0.0, opacity: 1.0, maxWidthFraction: 0.8,
            isSubtitle: false, visibleCharCount: -1, blurSigma: 0.0
        )

        #expect(state1 == state2)
    }

    @Test("Different text makes states unequal")
    func differentText() {
        let state1 = TextRenderState(
            clipId: "c1", text: "Hello", position: .zero,
            scale: 1.0, rotation: 0.0, opacity: 1.0, maxWidthFraction: 0.8,
            isSubtitle: false, visibleCharCount: -1, blurSigma: 0.0
        )
        let state2 = TextRenderState(
            clipId: "c1", text: "World", position: .zero,
            scale: 1.0, rotation: 0.0, opacity: 1.0, maxWidthFraction: 0.8,
            isSubtitle: false, visibleCharCount: -1, blurSigma: 0.0
        )

        #expect(state1 != state2)
    }

    @Test("Different clipId makes states unequal")
    func differentClipId() {
        let state1 = TextRenderState(
            clipId: "c1", text: "Hello", position: .zero,
            scale: 1.0, rotation: 0.0, opacity: 1.0, maxWidthFraction: 0.8,
            isSubtitle: false, visibleCharCount: -1, blurSigma: 0.0
        )
        let state2 = TextRenderState(
            clipId: "c2", text: "Hello", position: .zero,
            scale: 1.0, rotation: 0.0, opacity: 1.0, maxWidthFraction: 0.8,
            isSubtitle: false, visibleCharCount: -1, blurSigma: 0.0
        )

        #expect(state1 != state2)
    }
}
