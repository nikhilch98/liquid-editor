// HDRPreviewPipeline.swift
// LiquidEditor
//
// PP12-15: HDR preview pipeline (stub).
//
// Implements the preview-side branch described in spec §10.11.5:
// HDR projects render through a tone-mapped CIImage pipeline so
// SDR displays see a clipped but safe approximation of the HDR
// image; HDR-capable displays bypass the tone map.
//
// This file is a STUB. The final implementation will replace the
// placeholder tone curve with ITU-R BT.2446 Method A. The shape
// of the API — `renderPreview(image:isHDR:headroom:)` — is the
// stable contract, and the ring buffer between previewer and
// compositor should drop-in without changes once the real tone
// mapper lands.

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

// MARK: - Pipeline

/// Main-actor preview pipeline that mediates HDR content for the
/// preview surface.
///
/// All inputs and outputs are `CIImage`s — the pipeline does not
/// render to a CVPixelBuffer; hand off to an existing CIContext
/// sink for that.
@MainActor
final class HDRPreviewPipeline {

    // MARK: - Filters

    /// Reusable tone curve filter. Kept stable across frames so
    /// Core Image can reuse its compiled kernel.
    private let toneCurve = CIFilter.toneCurve()

    /// Absolute difference placeholder (stub). The spec requires
    /// this filter be used in the chain as a sentinel until
    /// BT.2446 Method A lands.
    private let absoluteDifference = CIFilter.colorAbsoluteDifference()

    /// Shared black reference — used as the second operand to
    /// `CIColorAbsoluteDifference` so the filter collapses to an
    /// identity (|x - 0| = |x|). This keeps the filter in the
    /// chain without altering pixel values, matching "stub".
    private let blackReference: CIImage = CIImage(color: .black)

    // MARK: - Init

    init() {
        configureToneCurve()
    }

    // MARK: - API

    /// Render a preview frame, optionally tone-mapped.
    ///
    /// - Parameters:
    ///   - image: The source frame. For HDR projects this is an
    ///     extended-range image (`> 1.0` samples permitted).
    ///   - isHDR: Whether to engage the HDR branch. SDR projects
    ///     pass `false` and receive an identity passthrough.
    ///   - headroom: Display headroom (linear multiplier above
    ///     1.0 nits normalized). Callers may pass the default
    ///     computed from the source via `defaultHeadroom(for:)`.
    /// - Returns: A `CIImage` ready for the preview sink.
    func renderPreview(
        image: CIImage,
        isHDR: Bool,
        headroom: Float
    ) -> CIImage {
        guard isHDR else {
            // SDR identity passthrough — no allocation.
            return image
        }
        return toneMapStub(image: image, headroom: headroom)
    }

    /// Default headroom derived from the image's color space.
    /// Extended-range color spaces (HDR10, Rec.2100 PQ/HLG,
    /// extendedLinearDisplayP3, etc.) get a placeholder headroom of
    /// 4.0; everything else gets 1.0 (effectively no expansion).
    ///
    /// This is a stub — the real headroom is the display's reported
    /// EDR headroom from `UIScreen.currentEDRHeadroom`.
    static func defaultHeadroom(for image: CIImage) -> Float {
        guard let cs = image.colorSpace else { return 1.0 }
        // `CGColorSpaceUsesExtendedRange` is the free function form of
        // the extended-range query. Available on all iOS 9+ targets.
        return CGColorSpaceUsesExtendedRange(cs) ? 4.0 : 1.0
    }

    // MARK: - Tone map (stub)

    /// Placeholder HDR → SDR tone map.
    ///
    /// Current chain:
    ///
    /// 1. `CIColorAbsoluteDifference` against pure black (no-op,
    ///    sentinel in the chain).
    /// 2. `CIToneCurve` five-point roll-off that compresses the
    ///    `[1, headroom]` range into `[0.8, 1.0]`.
    ///
    /// **TODO:** Replace with ITU-R BT.2446 Method A (PQ/HLG →
    /// sRGB) using a dedicated CIKernel. Tracked in spec §10.11.5.
    private func toneMapStub(image: CIImage, headroom: Float) -> CIImage {
        absoluteDifference.inputImage = image
        absoluteDifference.inputImage2 = blackReference
        let absd = absoluteDifference.outputImage ?? image

        // Placeholder roll-off: samples above 1.0 are compressed
        // proportionally to the headroom so the overall energy
        // lands within SDR display gamut.
        let h = max(Float(1.0), headroom)
        let compress: Float = 1.0 / h
        toneCurve.inputImage = absd
        toneCurve.point0 = CGPoint(x: 0.00, y: 0.00)
        toneCurve.point1 = CGPoint(x: 0.25, y: 0.25 * CGFloat(compress) * 2)
        toneCurve.point2 = CGPoint(x: 0.50, y: 0.50 * CGFloat(compress) * 1.6)
        toneCurve.point3 = CGPoint(x: 0.75, y: 0.75 * CGFloat(compress) * 1.3)
        toneCurve.point4 = CGPoint(x: 1.00, y: 1.00)
        return toneCurve.outputImage ?? absd
    }

    // MARK: - Setup

    private func configureToneCurve() {
        // Initialize with identity points; `toneMapStub` overrides
        // per-call but the identity default keeps the filter safe
        // to pull `outputImage` from without configuration.
        toneCurve.point0 = CGPoint(x: 0.0, y: 0.0)
        toneCurve.point1 = CGPoint(x: 0.25, y: 0.25)
        toneCurve.point2 = CGPoint(x: 0.5, y: 0.5)
        toneCurve.point3 = CGPoint(x: 0.75, y: 0.75)
        toneCurve.point4 = CGPoint(x: 1.0, y: 1.0)
    }
}
