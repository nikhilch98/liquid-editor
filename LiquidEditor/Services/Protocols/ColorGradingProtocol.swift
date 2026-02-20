// ColorGradingProtocol.swift
// LiquidEditor
//
// Protocol for color grading pipeline.
// Enables dependency injection and testability.

import CoreImage
import Foundation

// MARK: - ColorGradingProtocol

/// Protocol for the 12-stage color grading pipeline.
///
/// Implementations apply `ColorGrade` configurations to CIImage frames
/// using CIFilter chains. LUT files are cached for performance.
///
/// References:
/// - `ColorGrade` from Models/ColorGrading/ColorGrade.swift
/// - `LUTReference` from Models/ColorGrading/LUTReference.swift
protocol ColorGradingProtocol: Sendable {
    /// Apply a color grade configuration to an image.
    ///
    /// The grade is applied as a multi-stage pipeline:
    /// exposure, white balance, contrast, HSL, curves, LUT, vignette, etc.
    /// Identity grades (all defaults) return the input unchanged.
    ///
    /// - Parameters:
    ///   - grade: The color grade configuration to apply.
    ///   - image: The source CIImage.
    /// - Returns: The color-graded CIImage.
    func apply(grade: ColorGrade, to image: CIImage) -> CIImage

    /// Clear any cached LUT textures.
    ///
    /// Call when LUT files are deleted or the project changes.
    func clearLUTCache()
}
