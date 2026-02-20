// TransformInterpolator.swift
// LiquidEditor
//
// Interpolates VideoTransform values between keyframes with LRU cache (120 entries).
//
// Uses the existing InterpolationUtils for easing functions.
// Cache is keyed by `{modificationHash}_{frameIndex}` for O(1) lookups.

import Foundation
import CoreGraphics
import OrderedCollections

// MARK: - TransformInterpolator

/// Interpolates `VideoTransform` values between keyframes.
///
/// ## Caching Strategy
/// Uses an LRU cache (120 entries = 2 seconds at 60fps) via `OrderedDictionary`
/// for O(1) access and eviction. Cache is keyed by
/// `{timeline.modificationHash}_{frameIndex}`.
///
/// ## Thread Safety
/// Static state -- NOT thread-safe. Must be called from `@MainActor` only.
///
/// ## Performance
/// - Cache hit: O(1)
/// - Cache miss: O(log n) for keyframe lookup + O(1) for interpolation
/// - Bezier evaluation: O(8) Newton-Raphson iterations
@MainActor
enum TransformInterpolator {

    // MARK: - Cache Configuration

    private static let maxCacheSize = 120
    private static let cacheFrameRate = 60

    /// LRU cache: ordered dictionary preserves insertion order.
    /// Most recently used entries are moved to the end.
    private static var transformCache = OrderedDictionary<String, VideoTransform>()

    // MARK: - Public API

    /// Clear cache when timeline changes.
    static func invalidateCache() {
        transformCache.removeAll()
    }

    /// Interpolate transform at a given timestamp within a timeline.
    ///
    /// Returns the cached result if available, otherwise computes and caches it.
    static func transform(
        at timestampMicros: TimeMicros,
        timeline: KeyframeTimeline
    ) -> VideoTransform {
        let targetMs = timestampMicros.toMilliseconds
        let frameIndex = Int((targetMs * Double(cacheFrameRate)) / 1_000.0)
        let cacheKey = "\(timeline.modificationHash)_\(frameIndex)"

        // Check cache -- remove and re-add to maintain LRU order
        if let cached = transformCache.removeValue(forKey: cacheKey) {
            transformCache[cacheKey] = cached
            return cached
        }

        // Compute transform
        let result = computeTransform(at: timestampMicros, timeline: timeline)

        // Store in cache
        transformCache[cacheKey] = result

        // Evict oldest (first entry) if over limit
        if transformCache.count > maxCacheSize {
            transformCache.removeFirst()
        }

        return result
    }

    /// Interpolate between two transforms at a given progress.
    static func interpolate(
        from: VideoTransform,
        to: VideoTransform,
        progress: Double
    ) -> VideoTransform {
        VideoTransform(
            scale: InterpolationUtils.lerpDouble(from.scale, to.scale, progress),
            translation: InterpolationUtils.lerpOffset(from.translation, to.translation, progress),
            rotation: InterpolationUtils.lerpAngle(from.rotation, to.rotation, progress),
            anchor: InterpolationUtils.lerpOffset(from.anchor, to.anchor, progress)
        )
    }

    /// Current number of cached entries (for testing).
    static var cacheCount: Int { transformCache.count }

    // MARK: - Private

    /// Core transform computation (without caching).
    private static func computeTransform(
        at timestampMicros: TimeMicros,
        timeline: KeyframeTimeline
    ) -> VideoTransform {
        let (before, after) = timeline.surroundingKeyframes(timestampMicros)

        // No keyframes at all -- return identity
        guard let before else {
            return after?.transform ?? .identity
        }

        // No keyframe after -- use last keyframe's transform
        guard let after else {
            return before.transform
        }

        // Calculate progress between keyframes
        let startMicros = before.timestampMicros
        let endMicros = after.timestampMicros
        let duration = endMicros - startMicros

        guard duration > 0 else { return before.transform }

        let linearProgress = Double(timestampMicros - startMicros) / Double(duration)
        let clampedProgress = min(max(linearProgress, 0.0), 1.0)

        // Apply easing function
        let easedProgress = InterpolationUtils.applyEasing(
            clampedProgress,
            before.interpolation,
            before.bezierPoints
        )

        // Interpolate transform
        return interpolate(from: before.transform, to: after.transform, progress: easedProgress)
    }
}
