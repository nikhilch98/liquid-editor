import Testing
import Foundation
@testable import LiquidEditor

@Suite("StickerEditorPanel Tests")
struct StickerEditorPanelTests {

    // MARK: - Timestamp Formatting

    @Suite("Timestamp Formatting")
    struct TimestampFormattingTests {

        @Test("Format zero microseconds")
        func formatZero() {
            #expect(StickerEditorPanel.formatTimestamp(0) == "0:00")
        }

        @Test("Format 1 second exactly")
        func formatOneSecond() {
            #expect(StickerEditorPanel.formatTimestamp(1_000_000) == "1:00")
        }

        @Test("Format sub-second value")
        func formatSubSecond() {
            // 500ms = 500_000 micros -> 0:50
            #expect(StickerEditorPanel.formatTimestamp(500_000) == "0:50")
        }

        @Test("Format 2.5 seconds")
        func formatTwoPointFive() {
            // 2_500_000 micros = 2s 500ms -> 2:50
            #expect(StickerEditorPanel.formatTimestamp(2_500_000) == "2:50")
        }

        @Test("Format 10 seconds")
        func formatTenSeconds() {
            #expect(StickerEditorPanel.formatTimestamp(10_000_000) == "10:00")
        }

        @Test("Format 100ms (0.1s)")
        func formatHundredMs() {
            // 100_000 micros = 100ms -> 0:10
            #expect(StickerEditorPanel.formatTimestamp(100_000) == "0:10")
        }
    }

    // MARK: - Default Clip State

    @Suite("Default StickerClip State")
    struct DefaultClipStateTests {

        @Test("Default clip has opacity 1.0")
        func defaultOpacity() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            #expect(clip.opacity == 1.0)
        }

        @Test("Default clip is not flipped horizontally")
        func defaultFlipH() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            #expect(clip.isFlippedHorizontally == false)
        }

        @Test("Default clip is not flipped vertically")
        func defaultFlipV() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            #expect(clip.isFlippedVertically == false)
        }

        @Test("Default clip has no tint color")
        func defaultTintColor() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            #expect(clip.tintColorValue == nil)
        }

        @Test("Default clip animation speed is 1.0")
        func defaultAnimSpeed() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            #expect(clip.animationSpeed == 1.0)
        }

        @Test("Default clip animation loops is true")
        func defaultAnimLoop() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            #expect(clip.animationLoops == true)
        }

        @Test("Default clip has no keyframes")
        func defaultKeyframes() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            #expect(clip.keyframes.isEmpty)
            #expect(clip.sortedKeyframes.isEmpty)
        }
    }

    // MARK: - Clip Modification

    @Suite("Clip Modification via copyWith")
    struct ClipModificationTests {

        @Test("Changing opacity returns updated clip")
        func changeOpacity() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test",
                opacity: 1.0
            )
            let updated = clip.with(opacity: 0.5)
            #expect(updated.opacity == 0.5)
            #expect(updated.id == clip.id)
        }

        @Test("Toggling flip horizontal")
        func toggleFlipH() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            let flipped = clip.with(isFlippedHorizontally: true)
            #expect(flipped.isFlippedHorizontally == true)
        }

        @Test("Clearing tint color via clearTintColorValue")
        func clearTintColor() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test",
                tintColorValue: 0xFF_FF_00_00
            )
            #expect(clip.tintColorValue != nil)

            let cleared = clip.with(clearTintColorValue: true)
            #expect(cleared.tintColorValue == nil)
        }

        @Test("Changing animation speed")
        func changeAnimSpeed() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            let updated = clip.with(animationSpeed: 2.0)
            #expect(updated.animationSpeed == 2.0)
        }

        @Test("Changing animation loops")
        func changeAnimLoop() {
            let clip = StickerClip(
                durationMicroseconds: 3_000_000,
                stickerAssetId: "test"
            )
            let updated = clip.with(animationLoops: false)
            #expect(updated.animationLoops == false)
        }
    }
}
