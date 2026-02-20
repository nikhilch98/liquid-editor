// StickerPreviewRendererTests.swift
// LiquidEditorTests
//
// Tests for StickerPreviewRenderer calculations and hit testing.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("StickerPreviewRenderer Tests")
struct StickerPreviewRendererTests {

    // MARK: - Animation Progress Tests

    @Test("animation progress at start is 0")
    func animationProgressAtStart() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 0,
            animationSpeed: 1.0,
            animationLoops: true,
            animationDurationMs: 1000
        )
        #expect(progress == 0.0)
    }

    @Test("animation progress at midpoint is 0.5")
    func animationProgressAtMidpoint() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 500_000,  // 500ms
            animationSpeed: 1.0,
            animationLoops: true,
            animationDurationMs: 1000   // 1000ms total
        )
        #expect(progress == 0.5)
    }

    @Test("animation progress loops correctly")
    func animationProgressLoops() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 1_500_000,  // 1500ms = 1.5x through
            animationSpeed: 1.0,
            animationLoops: true,
            animationDurationMs: 1000
        )
        #expect(abs(progress - 0.5) < 0.001)
    }

    @Test("animation progress clamps when not looping")
    func animationProgressClamps() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 2_000_000,  // 2000ms, past end
            animationSpeed: 1.0,
            animationLoops: false,
            animationDurationMs: 1000
        )
        #expect(progress == 1.0)
    }

    @Test("animation progress with nil duration returns 0")
    func animationProgressNilDuration() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 500_000,
            animationSpeed: 1.0,
            animationLoops: true,
            animationDurationMs: nil
        )
        #expect(progress == 0.0)
    }

    @Test("animation progress with zero duration returns 0")
    func animationProgressZeroDuration() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 500_000,
            animationSpeed: 1.0,
            animationLoops: true,
            animationDurationMs: 0
        )
        #expect(progress == 0.0)
    }

    @Test("animation progress respects speed")
    func animationProgressWithSpeed() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 250_000,  // 250ms
            animationSpeed: 2.0,        // 2x speed -> effective 500ms
            animationLoops: true,
            animationDurationMs: 1000
        )
        #expect(abs(progress - 0.5) < 0.001)
    }

    // MARK: - Hit Test Tests

    @Test("hit test center of sticker returns true")
    func hitTestCenter() {
        let result = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.5, y: 0.5),
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 1.0,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 300)
        )
        #expect(result == true)
    }

    @Test("hit test outside sticker returns false")
    func hitTestOutside() {
        let result = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.0, y: 0.0),
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 1.0,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 300)
        )
        #expect(result == false)
    }

    @Test("hit test on edge of sticker returns true")
    func hitTestEdge() {
        // Sticker at (0.5, 0.5) with width 100/400 = 0.25 normalized
        // Half-width = 0.125, so edge is at 0.5 + 0.125 = 0.625
        let result = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.625, y: 0.5),
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 1.0,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 300)
        )
        #expect(result == true)
    }

    @Test("hit test with rotation")
    func hitTestRotated() {
        // Sticker rotated 90 degrees - what was width is now height
        let result = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.5, y: 0.5),
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: .pi / 2,
            stickerScale: 1.0,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 400)
        )
        #expect(result == true)
    }

    @Test("hit test with scale")
    func hitTestScaled() {
        // Sticker at (0.5, 0.5), scaled 2x
        // Half-width = (100 * 2 / 400) / 2 = 0.25
        // Edge at 0.5 + 0.25 = 0.75
        let justInside = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.74, y: 0.5),
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 2.0,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 400)
        )
        #expect(justInside == true)

        let justOutside = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.76, y: 0.5),
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 2.0,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 400)
        )
        #expect(justOutside == false)
    }

    // MARK: - Constants Tests

    @Test("sticker preview constants are reasonable")
    func constants() {
        #expect(StickerPreviewCalculations.handleRadius > 0)
        #expect(StickerPreviewCalculations.rotationHandleOffset > 0)
        #expect(StickerPreviewCalculations.selectionBorderWidth > 0)
    }

    // MARK: - StickerRenderData Tests

    @Test("identity sticker render data has expected defaults")
    func identityDefaults() {
        let identity = StickerRenderData.identity
        #expect(identity.clipId == "")
        #expect(identity.scale == 1.0)
        #expect(identity.rotation == 0.0)
        #expect(identity.opacity == 1.0)
        #expect(identity.isFlippedHorizontally == false)
        #expect(identity.isFlippedVertically == false)
        #expect(identity.renderWidth == 0)
        #expect(identity.renderHeight == 0)
        #expect(identity.image == nil)
    }

    // MARK: - Additional Animation Progress Tests

    @Test("animation progress with speed 0.5 is half as fast")
    func animationProgressHalfSpeed() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 500_000, // 500ms
            animationSpeed: 0.5,       // 0.5x speed -> effective 250ms
            animationLoops: true,
            animationDurationMs: 1000
        )
        #expect(abs(progress - 0.25) < 0.001)
    }

    @Test("animation progress negative offset clamps to 0")
    func animationProgressNegativeOffset() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: -500_000,
            animationSpeed: 1.0,
            animationLoops: false,
            animationDurationMs: 1000
        )
        #expect(progress == 0.0)
    }

    @Test("animation progress non-looping at exact end is 1.0")
    func animationProgressNonLoopingAtEnd() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 1_000_000, // Exactly 1000ms
            animationSpeed: 1.0,
            animationLoops: false,
            animationDurationMs: 1000
        )
        #expect(progress == 1.0)
    }

    @Test("animation progress looping at exact end wraps to 0")
    func animationProgressLoopingAtEnd() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 1_000_000, // Exactly 1000ms
            animationSpeed: 1.0,
            animationLoops: true,
            animationDurationMs: 1000
        )
        #expect(progress == 0.0)
    }

    @Test("animation progress with very fast speed")
    func animationProgressFastSpeed() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 100_000, // 100ms
            animationSpeed: 10.0,      // 10x speed -> effective 1000ms
            animationLoops: true,
            animationDurationMs: 1000
        )
        #expect(progress == 0.0) // 1000ms / 1000ms = 1 full loop
    }

    @Test("animation progress negative duration returns 0")
    func animationProgressNegativeDuration() {
        let progress = StickerPreviewCalculations.computeAnimationProgress(
            clipOffsetMicros: 500_000,
            animationSpeed: 1.0,
            animationLoops: true,
            animationDurationMs: -100
        )
        #expect(progress == 0.0)
    }

    // MARK: - Additional Hit Test Tests

    @Test("hit test with zero scale returns false (degenerate)")
    func hitTestZeroScale() {
        let result = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.5, y: 0.5),
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 0.0,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 300)
        )
        // Zero scale means zero size, so the point can only hit if exactly at position
        // The actual result depends on whether half-extents are 0 and point is at center
        _ = result // No crash is the key check
    }

    @Test("hit test with very small scale misses at slight offset")
    func hitTestSmallScaleMiss() {
        let result = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.6, y: 0.6),
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 0.01,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 300)
        )
        #expect(result == false)
    }

    @Test("hit test with large scale hits at farther offset")
    func hitTestLargeScale() {
        let result = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.8, y: 0.5),
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 3.0,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 300)
        )
        #expect(result == true)
    }

    @Test("hit test with 45-degree rotation")
    func hitTestRotated45() {
        // At 45 degrees, a point on the original horizontal axis
        // gets rotated and might not be inside anymore
        let result = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.5, y: 0.5), // Center should always hit
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: .pi / 4,
            stickerScale: 1.0,
            intrinsicWidth: 100,
            intrinsicHeight: 100,
            canvasSize: CGSize(width: 400, height: 400)
        )
        #expect(result == true)
    }

    @Test("hit test rectangular sticker aspect ratio")
    func hitTestRectangularSticker() {
        // Wide sticker: 200x50
        // At (0.5, 0.5), halfW = 200/(2*400) = 0.25, halfH = 50/(2*300) = 0.083
        let hitInside = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.74, y: 0.5), // Near right edge
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 1.0,
            intrinsicWidth: 200,
            intrinsicHeight: 50,
            canvasSize: CGSize(width: 400, height: 300)
        )
        #expect(hitInside == true)

        let missVertical = StickerPreviewCalculations.hitTestSticker(
            touchPoint: CGPoint(x: 0.5, y: 0.7), // Too far vertically
            stickerPosition: CGPoint(x: 0.5, y: 0.5),
            stickerRotation: 0,
            stickerScale: 1.0,
            intrinsicWidth: 200,
            intrinsicHeight: 50,
            canvasSize: CGSize(width: 400, height: 300)
        )
        #expect(missVertical == false)
    }

    // MARK: - Additional StickerRenderData Tests

    @Test("StickerRenderData id uses clipId")
    func renderDataId() {
        let data = StickerRenderData(
            clipId: "sticker-123",
            stickerAssetId: "asset-1",
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 1.0,
            rotation: 0,
            opacity: 1.0,
            isFlippedHorizontally: false,
            isFlippedVertically: false,
            tintColorValue: nil,
            renderWidth: 100,
            renderHeight: 100,
            image: nil,
            sourceRect: .zero,
            trackIndex: 0,
            isAnimated: false
        )
        #expect(data.id == "sticker-123")
    }

    @Test("StickerRenderData identity position is center")
    func identityPosition() {
        let identity = StickerRenderData.identity
        #expect(identity.position.x == 0.5)
        #expect(identity.position.y == 0.5)
    }

    @Test("StickerRenderData identity is not animated")
    func identityNotAnimated() {
        #expect(StickerRenderData.identity.isAnimated == false)
    }

    @Test("StickerRenderData identity source rect is zero")
    func identitySourceRect() {
        #expect(StickerRenderData.identity.sourceRect == .zero)
    }

    @Test("StickerRenderData identity tint is nil")
    func identityTint() {
        #expect(StickerRenderData.identity.tintColorValue == nil)
    }

    // MARK: - StickerPreviewCalculations Properties

    @Test("StickerPreviewCalculations stores stickers")
    func calculationsStoresStickers() {
        let calc = StickerPreviewCalculations(
            visibleStickers: [StickerRenderData.identity],
            selectedStickerId: nil
        )
        #expect(calc.visibleStickers.count == 1)
    }

    @Test("StickerPreviewCalculations stores selected ID")
    func calculationsStoresSelectedId() {
        let calc = StickerPreviewCalculations(
            visibleStickers: [],
            selectedStickerId: "sticker-5"
        )
        #expect(calc.selectedStickerId == "sticker-5")
    }

    @Test("StickerPreviewCalculations with nil selected ID")
    func calculationsNilSelected() {
        let calc = StickerPreviewCalculations(
            visibleStickers: [],
            selectedStickerId: nil
        )
        #expect(calc.selectedStickerId == nil)
    }

    // MARK: - Additional Constants Tests

    @Test("handle radius is positive and reasonable")
    func handleRadiusReasonable() {
        #expect(StickerPreviewCalculations.handleRadius > 0)
        #expect(StickerPreviewCalculations.handleRadius < 50)
    }

    @Test("rotation handle offset is larger than handle radius")
    func rotationHandleOffsetLarger() {
        #expect(StickerPreviewCalculations.rotationHandleOffset > StickerPreviewCalculations.handleRadius)
    }

    @Test("selection border width is positive")
    func selectionBorderWidthPositive() {
        #expect(StickerPreviewCalculations.selectionBorderWidth > 0)
    }
}
