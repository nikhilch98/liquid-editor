/// VideoEffectsCache - Thread-safe cache for video effect configurations.
///
/// Stores the current video effects for clips during real-time preview
/// and export rendering. The cache is consumed by the composition renderer
/// and EffectPipeline.
///
/// Thread Safety: `@unchecked Sendable` with `OSAllocatedUnfairLock`
/// for GPU hot-path lock protection. OSAllocatedUnfairLock is preferred
/// over NSLock for minimal overhead on the render thread.
///
/// References:
/// - `VideoEffect` from Models/Effects/VideoEffect.swift
/// - `EffectChain` from Models/Effects/EffectChain.swift

import Foundation
import os

// MARK: - VideoEffectsCache

/// Thread-safe cache for video effect configurations.
///
/// Stores per-clip effect chains for real-time preview and export.
/// All access is lock-protected for concurrent render thread safety.
final class VideoEffectsCache: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = VideoEffectsCache()

    // MARK: - Properties

    /// Lock for protecting all mutable state.
    private let lock = OSAllocatedUnfairLock()

    /// Per-clip effect chains, keyed by clip ID.
    private var _clipEffects: [String: [VideoEffect]] = [:]

    /// Global effect chain applied to the output composition.
    private var _globalEffects: [VideoEffect] = []

    // MARK: - Init

    private init() {}

    // MARK: - Per-Clip Effects

    /// Get effects for a specific clip.
    ///
    /// - Parameter clipId: The clip identifier.
    /// - Returns: Array of effects for the clip, or empty array if none cached.
    func effects(forClip clipId: String) -> [VideoEffect] {
        lock.withLock { _clipEffects[clipId] ?? [] }
    }

    /// Whether any effects are cached for a specific clip.
    ///
    /// - Parameter clipId: The clip identifier.
    /// - Returns: True if effects exist for this clip.
    func hasEffects(forClip clipId: String) -> Bool {
        lock.withLock { !(_clipEffects[clipId]?.isEmpty ?? true) }
    }

    /// Set effects for a specific clip.
    ///
    /// - Parameters:
    ///   - effects: Array of video effects.
    ///   - clipId: The clip identifier.
    func setEffects(_ effects: [VideoEffect], forClip clipId: String) {
        lock.withLock { _clipEffects[clipId] = effects }
    }

    /// Set an effect chain for a specific clip.
    ///
    /// - Parameters:
    ///   - chain: The effect chain model.
    ///   - clipId: The clip identifier.
    func setEffectChain(_ chain: EffectChain, forClip clipId: String) {
        lock.withLock { _clipEffects[clipId] = chain.effects }
    }

    /// Remove cached effects for a specific clip.
    ///
    /// - Parameter clipId: The clip identifier.
    func removeEffects(forClip clipId: String) {
        lock.withLock { _clipEffects.removeValue(forKey: clipId) }
    }

    // MARK: - Global Effects

    /// Current global effects applied to the composition output.
    var globalEffects: [VideoEffect] {
        lock.withLock { _globalEffects }
    }

    /// Whether any global effects are cached.
    var hasGlobalEffects: Bool {
        lock.withLock { !_globalEffects.isEmpty }
    }

    /// Set global effects.
    ///
    /// - Parameter effects: Array of video effects to apply globally.
    func setGlobalEffects(_ effects: [VideoEffect]) {
        lock.withLock { _globalEffects = effects }
    }

    // MARK: - Bulk Operations

    /// Get all clip IDs that have cached effects.
    var cachedClipIds: [String] {
        lock.withLock { Array(_clipEffects.keys) }
    }

    /// Total number of clips with cached effects.
    var clipCount: Int {
        lock.withLock { _clipEffects.count }
    }

    /// Clear effects for all clips.
    func clearAllClipEffects() {
        lock.withLock { _clipEffects.removeAll() }
    }

    /// Clear everything (clip effects and global effects).
    func clearAll() {
        lock.withLock {
            _clipEffects.removeAll()
            _globalEffects.removeAll()
        }
    }
}
