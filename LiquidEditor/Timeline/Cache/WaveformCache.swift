// WaveformCache.swift
// LiquidEditor
//
// Waveform data caching system for audio visualization in the timeline.
//
// Features:
// - Multi-LOD waveform storage (low/medium/high detail)
// - LRU eviction with configurable memory budget
// - Automatic LOD selection based on zoom level
// - Fallback to lower LOD while preferred LOD generates
// - Priority-based generation queue with concurrent generation (up to 2)
// - Per-asset cache invalidation and selective retention
// - Thread-safe via Swift actor isolation
//
// Reuses `WaveformLOD` from AudioServiceProtocol.swift and
// `WaveformData` from WaveformExtractor.swift.
// Cache-specific types use the `WaveformCache` prefix.

import Foundation
import OrderedCollections

// MARK: - WaveformLOD Extensions

extension WaveformLOD: CaseIterable {
    static var allCases: [WaveformLOD] { [.low, .medium, .high] }
}

extension WaveformLOD {
    /// Microseconds per sample for this LOD.
    var microsPerSample: Int {
        switch self {
        case .low: 100_000      // 100ms
        case .medium: 10_000    // 10ms
        case .high: 1_000       // 1ms
        }
    }

    /// Selects the appropriate LOD based on the current zoom level.
    ///
    /// Targets approximately 1-2 pixels per sample.
    ///
    /// - Parameter microsPerPixel: Current timeline zoom expressed as
    ///   microseconds per screen pixel.
    /// - Returns: The best-matching LOD.
    static func selectForZoom(_ microsPerPixel: Double) -> WaveformLOD {
        if microsPerPixel > 50_000 {
            return .low
        } else if microsPerPixel > 5_000 {
            return .medium
        } else {
            return .high
        }
    }
}

// MARK: - WaveformData Extensions

extension WaveformData {
    /// Memory size estimate in bytes (4 bytes per Float).
    var sizeBytes: Int { samples.count * 4 }

    /// Number of samples.
    var sampleCount: Int { samples.count }

    /// Whether the waveform is empty.
    var isEmpty: Bool { samples.isEmpty }

    /// Whether the waveform contains data.
    var isNotEmpty: Bool { !samples.isEmpty }

    /// Extracts samples for a time range, downsampling to the target count
    /// using peak detection.
    ///
    /// - Parameters:
    ///   - startMicros: Start of range (microseconds).
    ///   - endMicros: End of range (microseconds).
    ///   - targetSamples: Desired number of output samples.
    /// - Returns: Array of peak amplitudes for the range.
    func getSamplesForRange(
        startMicros: TimeMicros,
        endMicros: TimeMicros,
        targetSamples: Int
    ) -> [Float] {
        guard !samples.isEmpty, targetSamples > 0 else { return [] }

        let startSample = Int((Double(startMicros) * Double(sampleRate) / 1_000_000.0).rounded())
        let endSample = Int((Double(endMicros) * Double(sampleRate) / 1_000_000.0).rounded())

        let clampedStart = min(max(startSample, 0), samples.count)
        let clampedEnd = min(max(endSample, 0), samples.count)
        let actualSourceSamples = clampedEnd - clampedStart

        guard actualSourceSamples > 0 else { return [] }

        if actualSourceSamples <= targetSamples {
            return Array(samples[clampedStart..<clampedEnd])
        }

        // Downsample via peak detection per bucket.
        var result = [Float](repeating: 0.0, count: targetSamples)
        let bucketSize = Double(actualSourceSamples) / Double(targetSamples)

        for i in 0..<targetSamples {
            let bucketStart = clampedStart + Int((Double(i) * bucketSize).rounded())
            let bucketEnd = clampedStart + Int((Double(i + 1) * bucketSize).rounded())

            var peak: Float = 0.0
            for j in bucketStart..<min(bucketEnd, samples.count) {
                let value = abs(samples[j])
                if value > peak { peak = value }
            }
            result[i] = peak
        }

        return result
    }
}

// MARK: - WaveformCacheKey

/// Cache key identifying a waveform by asset and LOD.
struct WaveformCacheKey: Hashable, Sendable {
    let assetId: String
    let lod: WaveformLOD
}

// MARK: - WaveformCacheLoadCallback

/// Callback invoked when a waveform finishes generating.
typealias WaveformCacheLoadCallback = @Sendable (String, WaveformData?) -> Void

/// Async closure that generates waveform data from the audio subsystem.
typealias WaveformCacheGenerator = @Sendable (String, WaveformLOD) async -> WaveformData?

// MARK: - WaveformCache

/// Actor-isolated cache for waveform data with multi-LOD support.
///
/// Provides:
/// - `getWaveformSamples` for zoom-adaptive sample retrieval
/// - `preload` for low-LOD prefetching
/// - `reduceSize` / `clear` / `clearAsset` / `clearAllExcept` for memory management
/// - Thread-safe via Swift actor isolation
actor WaveformCache {

    // MARK: - Configuration

    /// Maximum memory budget for waveforms (bytes).
    let maxMemoryBytes: Int

    /// Maximum concurrent waveform generations.
    private let maxConcurrentGenerations: Int = 2

    // MARK: - State

    /// LRU-ordered cache: first entry is least recently used.
    private var cache: OrderedDictionary<WaveformCacheKey, WaveformData> = [:]

    /// Keys currently being generated.
    private var generating: Set<WaveformCacheKey> = []

    /// Pending generation queue.
    private var generateQueue: [WaveformCacheKey] = []

    /// Current memory usage in bytes.
    private var _currentMemoryBytes: Int = 0

    // MARK: - Callbacks

    /// Optional callback invoked when a waveform is generated.
    var onWaveformLoaded: WaveformCacheLoadCallback?

    /// Platform-specific waveform generator.
    var waveformGenerator: WaveformCacheGenerator?

    // MARK: - Init

    /// Creates a waveform cache with a configurable memory limit.
    ///
    /// - Parameter maxMemoryBytes: Maximum memory budget in bytes. Default 20 MB.
    init(maxMemoryBytes: Int = 20 * 1024 * 1024) {
        self.maxMemoryBytes = maxMemoryBytes
    }

    /// Set the waveform generator (convenience for tests).
    func setWaveformGenerator(_ generator: WaveformCacheGenerator?) {
        self.waveformGenerator = generator
    }

    // MARK: - Sample Retrieval

    /// Gets waveform samples for a visible range at the appropriate LOD.
    ///
    /// Automatically selects the LOD based on `microsPerPixel`. Falls back
    /// to a lower LOD if the preferred one is not yet generated.
    ///
    /// - Parameters:
    ///   - assetId: Audio asset identifier.
    ///   - startMicros: Start of the visible range (microseconds).
    ///   - endMicros: End of the visible range (microseconds).
    ///   - targetSamples: Number of samples to return.
    ///   - microsPerPixel: Zoom level for LOD selection.
    /// - Returns: Peak amplitude array, or empty if no data available.
    func getWaveformSamples(
        assetId: String,
        startMicros: TimeMicros,
        endMicros: TimeMicros,
        targetSamples: Int,
        microsPerPixel: Double
    ) -> [Float] {
        let lod = WaveformLOD.selectForZoom(microsPerPixel)
        let key = WaveformCacheKey(assetId: assetId, lod: lod)

        // Check cache and promote on hit.
        if let data = cache.removeValue(forKey: key) {
            cache[key] = data  // Update LRU order
            return data.getSamplesForRange(
                startMicros: startMicros,
                endMicros: endMicros,
                targetSamples: targetSamples
            )
        }

        // Try lower LOD as fallback.
        for fallbackLOD in WaveformLOD.allCases where fallbackLOD != lod {
            let fallbackKey = WaveformCacheKey(assetId: assetId, lod: fallbackLOD)
            if let fallbackData = cache[fallbackKey] {
                // Schedule generation of preferred LOD.
                scheduleGeneration(key)
                return fallbackData.getSamplesForRange(
                    startMicros: startMicros,
                    endMicros: endMicros,
                    targetSamples: targetSamples
                )
            }
        }

        // Schedule generation.
        scheduleGeneration(key)
        return []
    }

    // MARK: - Preload

    /// Preloads the low-LOD waveform for an asset.
    func preload(assetId: String) {
        let key = WaveformCacheKey(assetId: assetId, lod: .low)
        if cache[key] == nil && !generating.contains(key) {
            scheduleGeneration(key)
        }
    }

    /// Checks whether a waveform is cached for any LOD.
    func hasWaveform(assetId: String) -> Bool {
        for lod in WaveformLOD.allCases {
            if cache[WaveformCacheKey(assetId: assetId, lod: lod)] != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Cache Management

    /// Clears all cached waveforms and cancels pending generations.
    func clear() {
        cache.removeAll()
        generateQueue.removeAll()
        generating.removeAll()
        _currentMemoryBytes = 0
    }

    /// Clears all waveforms except for the specified assets.
    func clearAllExcept(_ keepAssetIds: Set<String>) {
        let keysToRemove = cache.keys.filter { !keepAssetIds.contains($0.assetId) }
        for key in keysToRemove {
            if let data = cache.removeValue(forKey: key) {
                _currentMemoryBytes -= data.sizeBytes
            }
        }
    }

    /// Clears waveforms for a specific asset.
    func clearAsset(_ assetId: String) {
        for lod in WaveformLOD.allCases {
            let key = WaveformCacheKey(assetId: assetId, lod: lod)
            if let data = cache.removeValue(forKey: key) {
                _currentMemoryBytes -= data.sizeBytes
            }
        }

        generateQueue.removeAll { $0.assetId == assetId }
        generating = generating.filter { $0.assetId != assetId }
    }

    /// Reduces cache to a target percentage of the memory budget.
    func reduceSize(_ keepPercentage: Double) {
        let targetBytes = Int(Double(maxMemoryBytes) * keepPercentage)
        while _currentMemoryBytes > targetBytes && !cache.isEmpty {
            evictOldest()
        }
    }

    // MARK: - Read-Only Properties

    /// Current memory usage in bytes.
    var currentMemoryBytes: Int { _currentMemoryBytes }

    /// Number of cached waveforms.
    var cachedCount: Int { cache.count }

    // MARK: - Dispose

    /// Releases all resources.
    func dispose() {
        clear()
    }

    // MARK: - Private Helpers

    /// Schedules waveform generation if not already queued or in progress.
    private func scheduleGeneration(_ key: WaveformCacheKey) {
        guard !generating.contains(key), !generateQueue.contains(key) else { return }
        generateQueue.append(key)
        processGenerationQueue()
    }

    /// Processes the generation queue, launching generations up to the limit.
    private func processGenerationQueue() {
        guard waveformGenerator != nil else { return }

        while generating.count < maxConcurrentGenerations && !generateQueue.isEmpty {
            let key = generateQueue.removeFirst()

            // Skip if already cached.
            if cache[key] != nil { continue }

            generating.insert(key)
            generateWaveform(key)
        }
    }

    /// Generates a single waveform asynchronously.
    private func generateWaveform(_ key: WaveformCacheKey) {
        guard let generator = waveformGenerator else { return }

        Task { [weak self] in
            let data = await generator(key.assetId, key.lod)

            guard let self else { return }

            if let data {
                await self.addToCache(key: key, data: data)
                await self.onWaveformLoaded?(key.assetId, data)
            }

            await self.finishGenerating(key)
        }
    }

    /// Adds waveform data to the cache, evicting LRU entries if needed.
    private func addToCache(key: WaveformCacheKey, data: WaveformData) {
        while _currentMemoryBytes + data.sizeBytes > maxMemoryBytes {
            if cache.isEmpty { break }
            evictOldest()
        }

        cache[key] = data
        _currentMemoryBytes += data.sizeBytes
    }

    /// Marks a key as finished generating and triggers more queue processing.
    private func finishGenerating(_ key: WaveformCacheKey) {
        generating.remove(key)
        processGenerationQueue()
    }

    /// Evicts the least recently used (first) entry from the cache.
    private func evictOldest() {
        guard !cache.isEmpty else { return }
        let (_, data) = cache.removeFirst()
        _currentMemoryBytes -= data.sizeBytes
    }
}
