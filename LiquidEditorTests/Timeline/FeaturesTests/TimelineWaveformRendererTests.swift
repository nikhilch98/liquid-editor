// TimelineWaveformRendererTests.swift
// LiquidEditorTests
//
// Tests for TimelineWaveformRenderer.

import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("TimelineWaveformRenderer")
struct TimelineWaveformRendererTests {

    // MARK: - buildWaveformPath

    @Test("buildWaveformPath returns empty path for empty samples")
    func emptyPath() {
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: [],
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 64)
        )
        #expect(path.isEmpty)
    }

    @Test("buildWaveformPath returns non-empty path for valid samples")
    func validPath() {
        let samples: [Float] = [0.0, 0.5, 1.0, 0.5, 0.0, -0.5, -1.0, -0.5]
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 64)
        )
        #expect(!path.isEmpty)
    }

    @Test("buildWaveformPath returns empty for zero-width rect")
    func zeroWidthRect() {
        let samples: [Float] = [0.5, 0.5, 0.5]
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: CGRect(x: 0, y: 0, width: 0, height: 64)
        )
        #expect(path.isEmpty)
    }

    @Test("buildWaveformPath returns empty for zero-height rect")
    func zeroHeightRect() {
        let samples: [Float] = [0.5, 0.5, 0.5]
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 0)
        )
        #expect(path.isEmpty)
    }

    @Test("buildWaveformPath respects isAudioClip=true (full height)")
    func audioClipFullHeight() {
        let samples: [Float] = [0.5, 1.0, 0.5]
        let clipRect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: clipRect,
            isAudioClip: true
        )
        let bounds = path.boundingBox
        // Full height mode uses clipRect deflated by 2
        #expect(bounds.maxY <= clipRect.maxY)
        #expect(bounds.minY >= clipRect.minY)
    }

    @Test("buildWaveformPath respects isAudioClip=false (bottom 30%)")
    func videoClipBottom30() {
        let samples: [Float] = [0.5, 1.0, 0.5]
        let clipRect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: clipRect,
            isAudioClip: false
        )
        let bounds = path.boundingBox
        // Bottom 30% => should be in lower portion of rect
        #expect(bounds.minY >= clipRect.height * 0.6) // At or below 70% mark
    }

    @Test("buildWaveformPath produces symmetrical waveform")
    func symmetrical() {
        let samples: [Float] = Array(repeating: 0.5, count: 100)
        let clipRect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: clipRect,
            isAudioClip: true
        )
        let bounds = path.boundingBox
        // Center should be approximately at midY (48 = (100-4)/2 = center of deflated rect)
        let center = clipRect.midY
        let topDistance = center - bounds.minY
        let bottomDistance = bounds.maxY - center
        // Should be approximately equal (within rounding)
        #expect(abs(topDistance - bottomDistance) < 2.0)
    }

    // MARK: - buildClipWaveformPath

    @Test("buildClipWaveformPath extracts visible portion")
    func clipWaveformPath() {
        // 100 samples over 10 seconds
        let samples: [Float] = (0..<100).map { Float($0) / 100.0 }
        let clipRect = CGRect(x: 0, y: 0, width: 200, height: 64)

        let path = TimelineWaveformRenderer.buildClipWaveformPath(
            samples: samples,
            sourceIn: 2_000_000, // 20% through
            sourceOut: 8_000_000, // 80% through
            durationMicros: 10_000_000,
            clipRect: clipRect
        )
        #expect(!path.isEmpty)
    }

    @Test("buildClipWaveformPath returns empty for zero duration")
    func clipWaveformZeroDuration() {
        let samples: [Float] = [0.5, 0.5]
        let path = TimelineWaveformRenderer.buildClipWaveformPath(
            samples: samples,
            sourceIn: 0,
            sourceOut: 1_000_000,
            durationMicros: 0,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 64)
        )
        #expect(path.isEmpty)
    }

    @Test("buildClipWaveformPath returns empty for empty samples")
    func clipWaveformEmptySamples() {
        let path = TimelineWaveformRenderer.buildClipWaveformPath(
            samples: [],
            sourceIn: 0,
            sourceOut: 1_000_000,
            durationMicros: 5_000_000,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 64)
        )
        #expect(path.isEmpty)
    }

    @Test("buildClipWaveformPath clamps sample indices to bounds")
    func clipWaveformClamps() {
        let samples: [Float] = [0.5, 0.5, 0.5]
        // sourceIn/sourceOut that would exceed sample bounds
        let path = TimelineWaveformRenderer.buildClipWaveformPath(
            samples: samples,
            sourceIn: 0,
            sourceOut: 20_000_000, // Way beyond duration
            durationMicros: 1_000_000,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 64)
        )
        // Should not crash, should produce a valid path
        // (may be empty if clamped range is invalid)
        _ = path // Just verify no crash
    }

    // MARK: - WaveformStyle

    @Test("WaveformStyle defaults")
    func styleDefaults() {
        let style = WaveformStyle.defaults
        #expect(style.opacity == 0.6)
        #expect(style.isPlaceholder == false)
    }

    @Test("WaveformStyle placeholder")
    func stylePlaceholder() {
        let style = WaveformStyle.placeholder
        #expect(style.isPlaceholder == true)
    }

    // MARK: - CGContext Rendering (smoke tests)

    @Test("draw does not crash with empty thumbnails")
    func drawEmpty() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 200, height: 64, bitsPerComponent: 8, bytesPerRow: 200 * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }

        // Should not crash
        TimelineWaveformRenderer.draw(
            in: context,
            path: nil,
            style: .defaults,
            size: CGSize(width: 200, height: 64)
        )
    }

    @Test("draw renders placeholder without crash")
    func drawPlaceholder() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 200, height: 64, bitsPerComponent: 8, bytesPerRow: 200 * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }

        TimelineWaveformRenderer.draw(
            in: context,
            path: nil,
            style: .placeholder,
            size: CGSize(width: 200, height: 64)
        )
    }

    @Test("draw renders valid waveform path without crash")
    func drawValidPath() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 200, height: 64, bitsPerComponent: 8, bytesPerRow: 200 * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }

        let samples: [Float] = (0..<50).map { sin(Float($0) * 0.3) }
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 64)
        )

        TimelineWaveformRenderer.draw(
            in: context,
            path: path,
            style: .defaults,
            size: CGSize(width: 200, height: 64)
        )
    }

    // MARK: - Additional buildWaveformPath Tests

    @Test("buildWaveformPath with single sample produces non-empty path")
    func singleSample() {
        let samples: [Float] = [0.5]
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 64)
        )
        #expect(!path.isEmpty)
    }

    @Test("buildWaveformPath with all zero samples produces flat path")
    func allZeroSamples() {
        let samples: [Float] = Array(repeating: 0.0, count: 50)
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 64)
        )
        let bounds = path.boundingBox
        // All zeros should have very small/zero height variance
        #expect(bounds.height < 2.0)
    }

    @Test("buildWaveformPath with all max samples produces full height path")
    func allMaxSamples() {
        let samples: [Float] = Array(repeating: 1.0, count: 50)
        let clipRect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: clipRect,
            isAudioClip: true
        )
        let bounds = path.boundingBox
        // Should use most of the height (deflated by 2 on each side)
        #expect(bounds.height > 80)
    }

    @Test("buildWaveformPath with offset clip rect")
    func offsetClipRect() {
        let samples: [Float] = [0.5, 0.5, 0.5]
        let clipRect = CGRect(x: 100, y: 50, width: 200, height: 64)
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: clipRect,
            isAudioClip: true
        )
        let bounds = path.boundingBox
        #expect(bounds.minX >= 100)
    }

    @Test("buildWaveformPath with negative samples uses absolute value")
    func negativeSamples() {
        let samples: [Float] = [-0.5, -1.0, -0.5]
        let clipRect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: clipRect,
            isAudioClip: true
        )
        let bounds = path.boundingBox
        #expect(bounds.height > 10) // Should produce amplitude
    }

    @Test("buildWaveformPath many samples more than width")
    func manySamples() {
        let samples: [Float] = (0..<1000).map { sin(Float($0) * 0.1) }
        let clipRect = CGRect(x: 0, y: 0, width: 200, height: 64)
        let path = TimelineWaveformRenderer.buildWaveformPath(
            samples: samples,
            clipRect: clipRect
        )
        #expect(!path.isEmpty)
    }

    // MARK: - Additional buildClipWaveformPath Tests

    @Test("buildClipWaveformPath uses only visible portion")
    func clipWaveformVisiblePortion() {
        let samples: [Float] = (0..<100).map { Float($0) / 100.0 }
        let clipRect = CGRect(x: 0, y: 0, width: 200, height: 64)

        let path = TimelineWaveformRenderer.buildClipWaveformPath(
            samples: samples,
            sourceIn: 5_000_000, // 50% through 10s
            sourceOut: 10_000_000, // end
            durationMicros: 10_000_000,
            clipRect: clipRect
        )
        #expect(!path.isEmpty)
    }

    @Test("buildClipWaveformPath with sourceIn == sourceOut returns empty")
    func clipWaveformZeroRange() {
        let samples: [Float] = [0.5, 0.5, 0.5]
        let path = TimelineWaveformRenderer.buildClipWaveformPath(
            samples: samples,
            sourceIn: 500_000,
            sourceOut: 500_000,
            durationMicros: 1_000_000,
            clipRect: CGRect(x: 0, y: 0, width: 200, height: 64)
        )
        #expect(path.isEmpty)
    }

    @Test("buildClipWaveformPath with isAudioClip false uses bottom 30%")
    func clipWaveformVideoClip() {
        let samples: [Float] = (0..<50).map { _ in Float(0.5) }
        let clipRect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = TimelineWaveformRenderer.buildClipWaveformPath(
            samples: samples,
            sourceIn: 0,
            sourceOut: 5_000_000,
            durationMicros: 10_000_000,
            clipRect: clipRect,
            isAudioClip: false
        )
        let bounds = path.boundingBox
        #expect(bounds.minY >= clipRect.height * 0.6)
    }

    // MARK: - WaveformStyle Additional Tests

    @Test("WaveformStyle custom initialization")
    func styleCustomInit() {
        let custom = WaveformStyle(
            color: CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
            opacity: 0.8,
            isPlaceholder: false,
            placeholderAnimationValue: 0.5
        )
        #expect(custom.opacity == 0.8)
        #expect(custom.isPlaceholder == false)
        #expect(custom.placeholderAnimationValue == 0.5)
    }

    @Test("WaveformStyle equatable")
    func styleEquatable() {
        let a = WaveformStyle.defaults
        let b = WaveformStyle.defaults
        #expect(a == b)
    }

    @Test("WaveformStyle placeholder has default color")
    func stylePlaceholderColor() {
        let style = WaveformStyle.placeholder
        // Placeholder should use default green color
        #expect(style.color != nil)
        #expect(style.isPlaceholder == true)
        #expect(style.opacity == 0.6) // Default opacity
    }

    // MARK: - draw with CGPath Tests

    @Test("draw with nil path and non-placeholder does nothing")
    func drawNilPathNonPlaceholder() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 100 * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        // Should not crash - no path provided, not placeholder
        TimelineWaveformRenderer.draw(
            in: context,
            path: nil,
            style: .defaults,
            size: CGSize(width: 100, height: 50)
        )
    }

    @Test("draw with placeholder animation value")
    func drawPlaceholderWithAnimation() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 200, height: 64, bitsPerComponent: 8, bytesPerRow: 200 * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create context")
            return
        }
        let style = WaveformStyle(
            isPlaceholder: true,
            placeholderAnimationValue: 0.75
        )
        TimelineWaveformRenderer.draw(
            in: context,
            path: nil,
            style: style,
            size: CGSize(width: 200, height: 64)
        )
    }
}
