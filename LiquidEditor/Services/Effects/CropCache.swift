/// CropCache - Thread-safe cache for crop, rotation, and flip parameters.
///
/// Stores crop parameters per clip for the composition renderer
/// during preview and export. Parameters include aspect ratio,
/// rotation (90-degree increments), and horizontal/vertical flip.
///
/// Thread Safety: `@unchecked Sendable` with `OSAllocatedUnfairLock`
/// for GPU hot-path lock protection.

import Foundation
import os

// MARK: - CropParameters

/// Crop and transform parameters for a clip.
struct CropParameters: Sendable, Equatable {
    /// Target aspect ratio (nil = no crop, use source aspect).
    let aspectRatio: Double?

    /// Human-readable aspect ratio label (e.g., "16:9", "4:3").
    let aspectRatioLabel: String?

    /// Number of 90-degree clockwise rotations (0-3).
    let rotation90: Int

    /// Whether to flip horizontally after rotation.
    let flipHorizontal: Bool

    /// Whether to flip vertically after rotation.
    let flipVertical: Bool

    init(
        aspectRatio: Double? = nil,
        aspectRatioLabel: String? = nil,
        rotation90: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
    ) {
        self.aspectRatio = aspectRatio
        self.aspectRatioLabel = aspectRatioLabel
        self.rotation90 = rotation90 % 4
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    /// Whether this represents any transformation (non-identity).
    var hasTransformation: Bool {
        aspectRatio != nil || rotation90 != 0 || flipHorizontal || flipVertical
    }

    /// Identity crop (no transformation).
    static let identity = CropParameters()
}

// MARK: - CropCache

/// Thread-safe cache for per-clip crop parameters.
///
/// All access is protected by `OSAllocatedUnfairLock` for
/// safe concurrent use from render threads.
final class CropCache: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = CropCache()

    // MARK: - Properties

    /// Lock for protecting all mutable state.
    private let lock = OSAllocatedUnfairLock()

    /// Per-clip crop parameters, keyed by clip ID.
    private var _clipCrops: [String: CropParameters] = [:]

    /// Global crop applied to the composition output.
    private var _globalCrop: CropParameters?

    // MARK: - Init

    private init() {}

    // MARK: - Per-Clip Crop

    /// Get crop parameters for a specific clip.
    ///
    /// - Parameter clipId: The clip identifier.
    /// - Returns: Crop parameters, or nil if no crop is set.
    func cropParams(forClip clipId: String) -> CropParameters? {
        lock.withLock { _clipCrops[clipId] }
    }

    /// Whether crop parameters are set for a specific clip.
    ///
    /// - Parameter clipId: The clip identifier.
    /// - Returns: True if crop parameters exist for this clip.
    func hasCrop(forClip clipId: String) -> Bool {
        lock.withLock { _clipCrops[clipId] != nil }
    }

    /// Set crop parameters for a specific clip.
    ///
    /// - Parameters:
    ///   - params: The crop parameters to cache.
    ///   - clipId: The clip identifier.
    func setCropParams(_ params: CropParameters, forClip clipId: String) {
        lock.withLock { _clipCrops[clipId] = params }
    }

    /// Remove crop parameters for a specific clip.
    ///
    /// - Parameter clipId: The clip identifier.
    func removeCrop(forClip clipId: String) {
        lock.withLock { _clipCrops.removeValue(forKey: clipId) }
    }

    // MARK: - Global Crop

    /// Current global crop parameters, or nil if no global crop.
    var globalCrop: CropParameters? {
        lock.withLock { _globalCrop }
    }

    /// Whether a global crop is set.
    var hasGlobalCrop: Bool {
        lock.withLock { _globalCrop != nil }
    }

    /// Set the global crop parameters.
    ///
    /// - Parameter params: The crop parameters, or nil to clear.
    func setGlobalCrop(_ params: CropParameters?) {
        lock.withLock { _globalCrop = params }
    }

    // MARK: - Bulk Operations

    /// Clear crop parameters for all clips.
    func clearAllClipCrops() {
        lock.withLock { _clipCrops.removeAll() }
    }

    /// Clear everything (clip crops and global crop).
    func clearAll() {
        lock.withLock {
            _clipCrops.removeAll()
            _globalCrop = nil
        }
    }
}
