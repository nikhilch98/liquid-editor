// CurvesShader.swift
// LiquidEditor
//
// C5-15: Tone-curve render stage.
//
// Applies four independent tone curves — Master (luminance),
// Red, Green, Blue — via a CIFilter chain. Each curve is a
// series of `CGPoint` control points in the unit square that
// the shader interpolates with monotone cubic Hermite to avoid
// ringing.
//
// The four curves are modeled as a lightweight `ClipCurves` bundle
// holding four `[CGPoint]` point arrays plus a master enable flag.
// Identity is skipped.
//
// This is a *new* stage, complementary to the existing per-`CurveData`
// stage in `ColorGradingPipeline` (which uses `CurveData` from the
// ColorGrade model). The new stage lets callers pass raw `[CGPoint]`
// control points straight from the Curves editor UI.

import Foundation
import CoreImage
import CoreGraphics

// MARK: - ClipCurves

/// Per-channel curve control points for a single clip.
///
/// Each array is a list of control points in the unit square
/// (`x` input, `y` output), sorted by `x`. Two-point `[(0,0),(1,1)]`
/// means "identity". The Master curve applies to luminance (RGB
/// together); R/G/B curves apply per channel.
struct ClipCurves: Equatable, Sendable {
    /// Master curve (luminance) control points.
    var master: [CGPoint]
    /// Red channel control points.
    var red: [CGPoint]
    /// Green channel control points.
    var green: [CGPoint]
    /// Blue channel control points.
    var blue: [CGPoint]

    init(
        master: [CGPoint] = Self.identityPoints,
        red: [CGPoint] = Self.identityPoints,
        green: [CGPoint] = Self.identityPoints,
        blue: [CGPoint] = Self.identityPoints
    ) {
        self.master = master
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Identity control points: straight diagonal from (0,0) to (1,1).
    static let identityPoints: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]

    /// Identity curves (all four channels straight diagonals).
    static let identity = ClipCurves()

    /// Whether all four curves are at identity.
    var isIdentity: Bool {
        Self.isPointsIdentity(master)
            && Self.isPointsIdentity(red)
            && Self.isPointsIdentity(green)
            && Self.isPointsIdentity(blue)
    }

    private static func isPointsIdentity(_ pts: [CGPoint]) -> Bool {
        pts.count == 2
            && abs(pts[0].x - 0) < 0.0001 && abs(pts[0].y - 0) < 0.0001
            && abs(pts[1].x - 1) < 0.0001 && abs(pts[1].y - 1) < 0.0001
    }
}

// MARK: - CurvesShader

/// Applies `ClipCurves` to a `CIImage` by chaining a luminance
/// `CIToneCurve` followed by per-channel `CIColorPolynomial` fits.
///
/// Thread safety: the shader is stateless. Safe to use from any
/// render thread. The underlying CIContext is supplied by
/// `EffectPipeline.sharedContext` at render time.
struct CurvesShader: Sendable {

    /// Epsilon for zero checks.
    private static let epsilon: Double = 0.0001

    /// Build-and-apply entry point.
    ///
    /// - Parameters:
    ///   - image: Source image.
    ///   - curves: Four-channel curve bundle.
    /// - Returns: Curve-corrected `CIImage` (or `image` on identity).
    func apply(to image: CIImage, curves: ClipCurves) -> CIImage {
        guard !curves.isIdentity else { return image }

        var current = image

        // Master (luminance) first via CIToneCurve.
        if !isIdentity(curves.master) {
            current = applyToneCurve(current, points: curves.master)
        }

        // Per-channel RGB curves via CIColorPolynomial.
        if !isIdentity(curves.red) {
            current = applyChannelPolynomial(current, points: curves.red, channel: .red)
        }
        if !isIdentity(curves.green) {
            current = applyChannelPolynomial(current, points: curves.green, channel: .green)
        }
        if !isIdentity(curves.blue) {
            current = applyChannelPolynomial(current, points: curves.blue, channel: .blue)
        }

        return current
    }

    // MARK: - Master: CIToneCurve (5-sample)

    /// Apply a 5-point tone curve to luminance using `CIToneCurve`.
    ///
    /// Samples the incoming control points at x = {0, 0.25, 0.5, 0.75, 1}
    /// using monotone cubic Hermite interpolation.
    private func applyToneCurve(_ image: CIImage, points: [CGPoint]) -> CIImage {
        guard let filter = CIFilter(name: "CIToneCurve") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)

        let sampleXs: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let ys = sampleXs.map { evaluate(points: points, at: $0) }

        for i in 0..<5 {
            let key = "inputPoint\(i)"
            filter.setValue(CIVector(x: CGFloat(sampleXs[i]), y: CGFloat(ys[i])), forKey: key)
        }

        return filter.outputImage ?? image
    }

    // MARK: - Per-channel: CIColorPolynomial (cubic fit)

    private enum Channel { case red, green, blue }

    /// Fit a cubic polynomial `a + b·x + c·x² + d·x³` to four curve samples
    /// and apply it to a single color channel via `CIColorPolynomial`.
    private func applyChannelPolynomial(
        _ image: CIImage,
        points: [CGPoint],
        channel: Channel
    ) -> CIImage {
        guard let filter = CIFilter(name: "CIColorPolynomial") else { return image }

        let y0 = evaluate(points: points, at: 0.0)
        let y1 = evaluate(points: points, at: 0.33)
        let y2 = evaluate(points: points, at: 0.66)
        let y3 = evaluate(points: points, at: 1.0)

        let a = y0
        let d = y3 - 3 * y2 + 3 * y1 - y0
        let c = y2 - 2 * y1 + y0
        let b = y1 - y0 - c / 3.0

        let coeffs = CIVector(x: CGFloat(a), y: CGFloat(b), z: CGFloat(c), w: CGFloat(d))
        let identity = CIVector(x: 0, y: 1, z: 0, w: 0)

        filter.setValue(image, forKey: kCIInputImageKey)
        switch channel {
        case .red:
            filter.setValue(coeffs, forKey: "inputRedCoefficients")
            filter.setValue(identity, forKey: "inputGreenCoefficients")
            filter.setValue(identity, forKey: "inputBlueCoefficients")
        case .green:
            filter.setValue(identity, forKey: "inputRedCoefficients")
            filter.setValue(coeffs, forKey: "inputGreenCoefficients")
            filter.setValue(identity, forKey: "inputBlueCoefficients")
        case .blue:
            filter.setValue(identity, forKey: "inputRedCoefficients")
            filter.setValue(identity, forKey: "inputGreenCoefficients")
            filter.setValue(coeffs, forKey: "inputBlueCoefficients")
        }
        filter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputAlphaCoefficients")

        return filter.outputImage ?? image
    }

    // MARK: - Interpolation

    private func isIdentity(_ pts: [CGPoint]) -> Bool {
        pts.count == 2
            && abs(pts[0].x - 0) < Self.epsilon && abs(pts[0].y - 0) < Self.epsilon
            && abs(pts[1].x - 1) < Self.epsilon && abs(pts[1].y - 1) < Self.epsilon
    }

    /// Evaluate the curve at `x` using monotone cubic Hermite (Fritsch-Carlson).
    ///
    /// Mirrors `CurveData.evaluate` for parity with the main ColorGrading
    /// pipeline but operates on raw `[CGPoint]` control points.
    func evaluate(points rawPts: [CGPoint], at xIn: Double) -> Double {
        let pts = rawPts.sorted { $0.x < $1.x }
        guard !pts.isEmpty else { return xIn }
        if pts.count == 1 { return Double(pts[0].y) }

        let x = min(max(xIn, 0.0), 1.0)
        if x <= Double(pts.first!.x) { return Double(pts.first!.y) }
        if x >= Double(pts.last!.x) { return Double(pts.last!.y) }

        // Binary search for the interval.
        var low = 0
        var high = pts.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if Double(pts[mid].x) <= x {
                low = mid
            } else {
                high = mid
            }
        }

        if pts.count == 2 {
            let dx = Double(pts[high].x - pts[low].x)
            guard dx > 1e-10 else { return Double(pts[low].y) }
            let t = (x - Double(pts[low].x)) / dx
            return Double(pts[low].y) + t * Double(pts[high].y - pts[low].y)
        }

        return evaluateMonotoneCubic(pts: pts, x: x, i: low)
    }

    private func evaluateMonotoneCubic(pts: [CGPoint], x: Double, i: Int) -> Double {
        let n = pts.count

        var deltas = [Double](repeating: 0, count: n - 1)
        for k in 0..<(n - 1) {
            let dx = Double(pts[k + 1].x - pts[k].x)
            if abs(dx) < 1e-10 {
                deltas[k] = 0.0
            } else {
                deltas[k] = Double(pts[k + 1].y - pts[k].y) / dx
            }
        }

        var tangents = [Double](repeating: 0, count: n)
        tangents[0] = deltas[0]
        tangents[n - 1] = deltas[n - 2]
        for k in 1..<(n - 1) {
            if deltas[k - 1].sign != deltas[k].sign
                || abs(deltas[k - 1]) < 1e-10
                || abs(deltas[k]) < 1e-10
            {
                tangents[k] = 0.0
            } else {
                tangents[k] = (deltas[k - 1] + deltas[k]) / 2.0
            }
        }
        for k in 0..<(n - 1) {
            if abs(deltas[k]) < 1e-10 {
                tangents[k] = 0.0
                tangents[k + 1] = 0.0
            } else {
                let alpha = tangents[k] / deltas[k]
                let beta = tangents[k + 1] / deltas[k]
                let sum = alpha * alpha + beta * beta
                if sum > 9.0 {
                    let tau = 3.0 / sum.squareRoot()
                    tangents[k] = tau * alpha * deltas[k]
                    tangents[k + 1] = tau * beta * deltas[k]
                }
            }
        }

        let h = Double(pts[i + 1].x - pts[i].x)
        guard abs(h) >= 1e-10 else { return Double(pts[i].y) }
        let t = (x - Double(pts[i].x)) / h
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        let result = h00 * Double(pts[i].y)
            + h10 * h * tangents[i]
            + h01 * Double(pts[i + 1].y)
            + h11 * h * tangents[i + 1]
        return min(max(result, 0.0), 1.0)
    }
}

// MARK: - ColorGradingPipeline integration

extension ColorGradingPipeline {
    /// Apply a `ClipCurves` bundle to an image (new optional stage, C5-15).
    ///
    /// Use this when the caller wants to feed raw `[CGPoint]` control points
    /// directly from the Curves editor UI without building a full `ColorGrade`.
    /// Returns `image` unchanged if `curves` are identity.
    func applyClipCurves(_ image: CIImage, curves: ClipCurves) -> CIImage {
        CurvesShader().apply(to: image, curves: curves)
    }
}
