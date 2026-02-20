// MaskingProtocol.swift
// LiquidEditor
//
// Protocol for mask rendering.
// Enables dependency injection and testability.

import CoreImage
import Foundation

// MARK: - MaskRenderingProtocol

/// Protocol for rendering masks onto video frames.
///
/// Implementations generate mask alpha channels from `Mask` definitions
/// and composite them with the source image. Supports all mask types:
/// rectangle, ellipse, polygon, brush, luminance, and color.
///
/// References:
/// - `Mask` from Models/Masking/Mask.swift
/// - `MaskType` from Models/Masking/Mask.swift
/// - `BrushStroke` from Models/Masking/Mask.swift
protocol MaskRenderingProtocol: Sendable {
    /// Apply a mask to an image.
    ///
    /// Generates the mask alpha channel and composites it with the
    /// source image. The mask's feather, opacity, expansion, and
    /// inversion settings are all applied.
    ///
    /// - Parameters:
    ///   - mask: The mask definition to apply.
    ///   - image: The source CIImage.
    ///   - frameSize: Output frame dimensions for coordinate conversion.
    /// - Returns: The masked CIImage.
    func applyMask(
        mask: Mask,
        to image: CIImage,
        frameSize: CGSize
    ) -> CIImage

    /// Generate a mask preview image (alpha channel visualization).
    ///
    /// Renders the mask as a grayscale alpha image for UI preview.
    /// White = included, Black = excluded, Gray = partially included.
    ///
    /// - Parameters:
    ///   - mask: The mask definition to preview.
    ///   - frameSize: Target dimensions for the preview.
    /// - Returns: Grayscale CIImage representing the mask.
    func generatePreview(
        mask: Mask,
        frameSize: CGSize
    ) -> CIImage
}
