// VideoTransformCalculator.swift
// LiquidEditor
//
// Affine transform calculation for video composition.
// Handles source video rotation metadata, scale/translate transforms,
// and user transform overlay for keyframe animation.

import AVFoundation
import CoreGraphics
import Foundation

// MARK: - VideoTransformCalculator

/// Calculates affine transforms for video composition.
///
/// Handles source video orientation (preferredTransform) and user
/// transformations (scale, translate, rotate). Eliminates code
/// duplication across render paths.
///
/// Thread Safety:
/// - All properties are immutable after init.
/// - `createBaseTransform()` and `createTransform()` are pure functions.
/// - Safe to call from any thread.
struct VideoTransformCalculator: Sendable {

    // MARK: - Properties

    /// Natural size of the source video (before rotation).
    let naturalSize: CGSize

    /// Preferred transform from source video track (handles rotation).
    let preferredTransform: CGAffineTransform

    /// Source width after applying preferred transform (display width).
    let sourceWidth: CGFloat

    /// Source height after applying preferred transform (display height).
    let sourceHeight: CGFloat

    /// Target output dimensions.
    let outputSize: CGSize

    // MARK: - Initialization from AVAssetTrack

    /// Initialize with source video track and optional target output size.
    ///
    /// Extracts `naturalSize` and `preferredTransform` from the track,
    /// calculates display dimensions after rotation, and sets the output
    /// size (defaulting to display dimensions if not specified).
    ///
    /// - Parameters:
    ///   - videoTrack: Source video track to extract dimensions and transform from.
    ///   - outputSize: Target render size. If nil, uses source dimensions after rotation.
    init(videoTrack: AVAssetTrack, outputSize: CGSize? = nil) {
        self.naturalSize = videoTrack.naturalSize
        self.preferredTransform = videoTrack.preferredTransform

        // Calculate source dimensions after rotation
        let rect = CGRect(origin: .zero, size: naturalSize)
        let transformedRect = rect.applying(preferredTransform)
        self.sourceWidth = abs(transformedRect.width)
        self.sourceHeight = abs(transformedRect.height)

        self.outputSize = outputSize ?? CGSize(width: sourceWidth, height: sourceHeight)
    }

    /// Initialize with explicit values (for testing or custom configurations).
    ///
    /// - Parameters:
    ///   - naturalSize: Natural size of source video.
    ///   - preferredTransform: Transform from source video.
    ///   - outputSize: Target render size.
    init(naturalSize: CGSize, preferredTransform: CGAffineTransform, outputSize: CGSize) {
        self.naturalSize = naturalSize
        self.preferredTransform = preferredTransform

        let rect = CGRect(origin: .zero, size: naturalSize)
        let transformedRect = rect.applying(preferredTransform)
        self.sourceWidth = abs(transformedRect.width)
        self.sourceHeight = abs(transformedRect.height)

        self.outputSize = outputSize
    }

    // MARK: - Base Transform

    /// Creates the base transform that handles video rotation and scaling to output size.
    ///
    /// Steps:
    /// 1. Applies the video's preferred transform (rotation).
    /// 2. Scales to fit the output size.
    /// 3. Translates to position content at origin (0,0).
    ///
    /// - Returns: Affine transform correcting rotation and scaling to output.
    func createBaseTransform() -> CGAffineTransform {
        // Scale factors from source (rotated) to output
        let scaleX = outputSize.width / sourceWidth
        let scaleY = outputSize.height / sourceHeight

        // Apply scale transform
        let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)

        // Concatenate: preferredTransform THEN scale
        var transform = preferredTransform.concatenating(scaleTransform)

        // Calculate where content ended up after rotation+scale
        let testRect = CGRect(origin: .zero, size: naturalSize)
        let resultRect = testRect.applying(transform)

        // Translate so content starts at (0,0)
        let fixTranslation = CGAffineTransform(
            translationX: -resultRect.origin.x,
            y: -resultRect.origin.y
        )
        transform = transform.concatenating(fixTranslation)

        return transform
    }

    // MARK: - User Transform

    /// Creates a combined transform with user transformations applied.
    ///
    /// For identity user values (sx=1, sy=1, tx=0, ty=0, rotation=0),
    /// returns `createBaseTransform()` directly.
    ///
    /// Steps:
    /// 1. Apply preferredTransform (handles source video rotation).
    /// 2. Translate center of rotated content to origin.
    /// 3. Apply user rotation around center.
    /// 4. Apply combined scale (base + user).
    /// 5. Apply user translation and move to output center.
    ///
    /// - Parameters:
    ///   - sx: User scale X (1.0 = no scale).
    ///   - sy: User scale Y (1.0 = no scale).
    ///   - tx: User translation X (normalized, 0.0 = centered).
    ///   - ty: User translation Y (normalized, 0.0 = centered).
    ///   - rotation: User rotation in radians (0.0 = no rotation).
    /// - Returns: Combined affine transform for video composition.
    func createTransform(
        sx: Double,
        sy: Double,
        tx: Double,
        ty: Double,
        rotation: Double = 0.0
    ) -> CGAffineTransform {
        // For identity transform, just return base transform
        if sx == 1.0 && sy == 1.0 && tx == 0.0 && ty == 0.0 && rotation == 0.0 {
            return createBaseTransform()
        }

        // Scale factors from source to output
        let baseScaleX = outputSize.width / sourceWidth
        let baseScaleY = outputSize.height / sourceHeight

        // Combined scale (base * user)
        let totalScaleX = baseScaleX * sx
        let totalScaleY = baseScaleY * sy

        // User translation in output pixels
        let pixelTx = tx * outputSize.width
        let pixelTy = ty * outputSize.height

        // Center of output (scale/rotate pivot)
        let outputCenterX = outputSize.width / 2
        let outputCenterY = outputSize.height / 2

        // 1. Apply preferredTransform (handles rotation of source video)
        var transform = preferredTransform

        // After preferredTransform, find where the source rect ended up
        let afterRotation = CGRect(origin: .zero, size: naturalSize).applying(transform)

        // 2. Move center of rotated content to origin
        let rotatedCenterX = afterRotation.midX
        let rotatedCenterY = afterRotation.midY
        transform = transform.concatenating(
            CGAffineTransform(translationX: -rotatedCenterX, y: -rotatedCenterY)
        )

        // 3. Apply user rotation (around origin, which is now the center)
        if rotation != 0.0 {
            transform = transform.concatenating(
                CGAffineTransform(rotationAngle: rotation)
            )
        }

        // 4. Apply combined scale
        transform = transform.concatenating(
            CGAffineTransform(scaleX: totalScaleX, y: totalScaleY)
        )

        // 5. Apply user translation and move to output center
        transform = transform.concatenating(
            CGAffineTransform(translationX: outputCenterX + pixelTx, y: outputCenterY + pixelTy)
        )

        return transform
    }

    // MARK: - Convenience

    /// Identity user transform values.
    static let identityUserValues: (sx: Double, sy: Double, tx: Double, ty: Double, rotation: Double) =
        (sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0, rotation: 0.0)

    /// Whether the source video is rotated (90 or 270 degrees).
    var isRotated: Bool {
        sourceWidth != naturalSize.width || sourceHeight != naturalSize.height
    }

    /// Aspect ratio of the source video (after rotation).
    var sourceAspectRatio: CGFloat {
        guard sourceHeight > 0 else { return 1.0 }
        return sourceWidth / sourceHeight
    }

    /// Aspect ratio of the output.
    var outputAspectRatio: CGFloat {
        guard outputSize.height > 0 else { return 1.0 }
        return outputSize.width / outputSize.height
    }
}
