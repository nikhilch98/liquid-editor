// MemoryOptimizer.swift
// LiquidEditor
//
// Memory pressure handling and coordinated cache eviction for timeline caches.
//
// Features:
// - Coordinates ThumbnailCache and WaveformCache memory budgets
// - Responds to iOS system memory warnings via NotificationCenter
// - Periodic memory usage monitoring (every 5 seconds)
// - Three-tier pressure levels: normal, warning, critical
// - Protects visible assets during critical eviction
// - Playback preload support (only during normal pressure)
// - Memory statistics reporting
// - Thread-safe via Swift actor isolation

import Foundation
import UIKit
import os

// MARK: - TimelineCacheMemoryPressureLevel

/// Memory pressure levels for timeline cache management.
///
/// Using a distinct name to avoid collision with `MemoryPressureLevel`
/// in FrameCache (which is used for the composition frame cache).
enum TimelineCacheMemoryPressureLevel: Sendable {
    /// Normal memory usage -- full cache capacity.
    case normal
    /// Memory warning -- reduce usage by 50%.
    case warning
    /// Critical memory -- clear thumbnails, keep only visible waveforms.
    case critical
}

// MARK: - MemoryStats

/// Snapshot of memory usage across timeline caches.
struct TimelineCacheMemoryStats: Sendable {
    let thumbnailCacheBytes: Int
    let thumbnailCacheCount: Int
    let thumbnailPendingCount: Int
    let waveformCacheBytes: Int
    let waveformCacheCount: Int
    let pressureLevel: TimelineCacheMemoryPressureLevel

    /// Total memory usage across both caches.
    var totalBytes: Int { thumbnailCacheBytes + waveformCacheBytes }

    /// Human-readable summary.
    var formatted: String {
        let totalMB = Double(totalBytes) / (1024.0 * 1024.0)
        return "Memory: \(String(format: "%.1f", totalMB))MB "
            + "(Thumbs: \(thumbnailCacheCount), Waves: \(waveformCacheCount), "
            + "Pressure: \(pressureLevel))"
    }
}

// MARK: - MemoryOptimizer

/// Coordinates memory management across ThumbnailCache and WaveformCache.
///
/// Monitors combined memory usage, responds to system memory warnings,
/// and applies tiered eviction strategies to keep the app within budget.
///
/// Thread Safety: Actor-isolated. The system memory warning observer
/// dispatches into the actor via a Task.
actor MemoryOptimizer {

    private static let logger = Logger(subsystem: "LiquidEditor", category: "MemoryOptimizer")

    // MARK: - Dependencies

    /// Thumbnail cache to manage.
    private let thumbnailCache: ThumbnailCache

    /// Waveform cache to manage.
    private let waveformCache: WaveformCache

    // MARK: - Configuration

    /// Maximum combined memory for both caches (bytes).
    let maxCombinedBytes: Int

    /// Memory check interval in seconds (default: 5 seconds).
    let memoryCheckInterval: UInt64

    /// Critical pressure threshold as fraction of max bytes (default: 0.9 = 90%).
    let criticalThreshold: Double

    /// Warning pressure threshold as fraction of max bytes (default: 0.7 = 70%).
    let warningThreshold: Double

    // MARK: - State

    /// Current memory pressure level.
    private var currentLevel: TimelineCacheMemoryPressureLevel = .normal

    /// Visible asset IDs (protected from eviction during critical pressure).
    private var visibleAssetIds: Set<String> = []

    /// Whether the optimizer is actively monitoring.
    private var isActive: Bool = false

    /// Periodic memory check task.
    private var memoryCheckTask: Task<Void, Never>?

    /// System memory warning observer token.
    private var memoryWarningObserver: (any NSObjectProtocol)?

    // MARK: - Init

    /// Creates a memory optimizer for the given caches.
    ///
    /// - Parameters:
    ///   - thumbnailCache: Thumbnail cache to manage.
    ///   - waveformCache: Waveform cache to manage.
    ///   - maxCombinedBytes: Maximum combined memory budget. Default 80 MB.
    ///   - memoryCheckInterval: Check interval in seconds. Default 5s.
    ///   - criticalThreshold: Critical pressure threshold (0.0-1.0). Default 0.9 (90%).
    ///   - warningThreshold: Warning pressure threshold (0.0-1.0). Default 0.7 (70%).
    init(
        thumbnailCache: ThumbnailCache,
        waveformCache: WaveformCache,
        maxCombinedBytes: Int = 80 * 1024 * 1024,
        memoryCheckInterval: UInt64 = 5,
        criticalThreshold: Double = 0.9,
        warningThreshold: Double = 0.7
    ) {
        self.thumbnailCache = thumbnailCache
        self.waveformCache = waveformCache
        self.maxCombinedBytes = maxCombinedBytes
        self.memoryCheckInterval = memoryCheckInterval
        self.criticalThreshold = criticalThreshold
        self.warningThreshold = warningThreshold
    }

    // MARK: - Lifecycle

    /// Starts memory monitoring.
    ///
    /// Registers for system memory warnings and begins periodic checks.
    func start() {
        guard !isActive else { return }
        isActive = true

        // Register for system memory warnings.
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleMemoryWarning(.critical)
            }
        }
        memoryWarningObserver = observer

        // Start periodic memory checks.
        let intervalNanos = memoryCheckInterval * 1_000_000_000
        memoryCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanos)
                } catch {
                    Self.logger.error("Memory check task interrupted: \(error.localizedDescription)")
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.checkMemory()
            }
        }
    }

    /// Stops memory monitoring.
    func stop() {
        isActive = false
        memoryCheckTask?.cancel()
        memoryCheckTask = nil

        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryWarningObserver = nil
        }
    }

    // MARK: - Visible Assets

    /// Updates the set of visible asset IDs.
    ///
    /// Visible assets are protected from eviction during critical memory pressure.
    ///
    /// - Parameter assetIds: Currently visible asset IDs.
    func updateVisibleAssets(_ assetIds: Set<String>) {
        visibleAssetIds = assetIds
    }

    // MARK: - Memory Pressure Handling

    /// Handles a memory pressure notification.
    ///
    /// - Parameter level: The pressure level to respond to.
    func handleMemoryWarning(_ level: TimelineCacheMemoryPressureLevel) {
        currentLevel = level
        applyMemoryPressure(level)
    }

    // MARK: - Playback Preload

    /// Preloads waveforms for upcoming assets during playback.
    ///
    /// Only preloads when memory pressure is normal.
    ///
    /// - Parameters:
    ///   - upcomingAssetIds: Asset IDs that will be needed soon.
    ///   - currentTimeMicros: Current playhead position.
    ///   - lookAheadMicros: How far ahead to prepare.
    func preloadForPlayback(
        upcomingAssetIds: [String],
        currentTimeMicros: TimeMicros,
        lookAheadMicros: TimeMicros
    ) {
        guard currentLevel == .normal else { return }

        for assetId in upcomingAssetIds {
            Task {
                await waveformCache.preload(assetId: assetId)
            }
        }
    }

    // MARK: - Statistics

    /// Current memory statistics.
    func stats() async -> TimelineCacheMemoryStats {
        let thumbBytes = await thumbnailCache.currentMemoryBytes
        let thumbCount = await thumbnailCache.cachedCount
        let thumbPending = await thumbnailCache.pendingCount
        let waveBytes = await waveformCache.currentMemoryBytes
        let waveCount = await waveformCache.cachedCount

        return TimelineCacheMemoryStats(
            thumbnailCacheBytes: thumbBytes,
            thumbnailCacheCount: thumbCount,
            thumbnailPendingCount: thumbPending,
            waveformCacheBytes: waveBytes,
            waveformCacheCount: waveCount,
            pressureLevel: currentLevel
        )
    }

    // MARK: - Dispose

    /// Stops monitoring and disposes both caches.
    func dispose() async {
        stop()
        await thumbnailCache.dispose()
        await waveformCache.dispose()
    }

    // MARK: - Private Helpers

    /// Periodic memory check. Adjusts pressure level based on combined usage.
    private func checkMemory() async {
        let thumbnailBytes = await thumbnailCache.currentMemoryBytes
        let waveformBytes = await waveformCache.currentMemoryBytes
        let totalBytes = thumbnailBytes + waveformBytes

        if totalBytes > Int(Double(maxCombinedBytes) * criticalThreshold) {
            applyMemoryPressure(.critical)
        } else if totalBytes > Int(Double(maxCombinedBytes) * warningThreshold) {
            applyMemoryPressure(.warning)
        } else if currentLevel != .normal {
            currentLevel = .normal
        }
    }

    /// Applies cache eviction based on the pressure level.
    private func applyMemoryPressure(_ level: TimelineCacheMemoryPressureLevel) {
        switch level {
        case .normal:
            break

        case .warning:
            // Reduce both caches by 50%.
            Task {
                await thumbnailCache.reduceSize(0.5)
                await waveformCache.reduceSize(0.5)
            }

        case .critical:
            // Clear all thumbnails; keep only visible waveforms.
            let visibleIds = visibleAssetIds
            Task {
                await thumbnailCache.clear()
                await waveformCache.clearAllExcept(visibleIds)
            }
        }

        currentLevel = level
    }
}
