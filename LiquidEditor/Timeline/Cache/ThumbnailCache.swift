// ThumbnailCache.swift
// LiquidEditor
//
// LRU thumbnail caching system for timeline clip preview images.
//
// Features:
// - LRU eviction with configurable max memory and max thumbnail count
// - Priority-based load queue with concurrent loading (up to 4 simultaneous)
// - Preload support for time ranges
// - Dynamic priority updates based on viewport visibility and playhead proximity
// - Pause/resume loading for fast scroll optimization
// - Per-asset cache invalidation
// - Thread-safe via Swift actor isolation
//
// Note: Reuses `ThumbnailKey` from ClipThumbnailService.swift.

import Foundation
import OrderedCollections
import UIKit

// MARK: - ThumbnailCacheRequest

/// A pending thumbnail load request with priority ordering.
struct ThumbnailCacheRequest: Sendable {
    let key: ThumbnailKey
    let priority: Int
    let requestTime: Date
}

// MARK: - CachedThumbnail

/// Internal cache entry holding the image and its estimated memory footprint.
struct CachedThumbnail: Sendable {
    let image: UIImage
    let sizeBytes: Int
}

// MARK: - ThumbnailLoadCallback

/// Callback invoked when a thumbnail finishes loading.
typealias ThumbnailLoadCallback = @Sendable (ThumbnailKey, UIImage?) -> Void

/// Async closure that loads a thumbnail from the media subsystem.
typealias ThumbnailLoader = @Sendable (String, TimeMicros, Int) async -> UIImage?

// MARK: - ThumbnailCache

/// Actor-isolated LRU cache for thumbnail images.
///
/// Provides:
/// - `getThumbnail` for synchronous cache lookup with automatic load scheduling
/// - `preload` for time-range prefetching
/// - `reduceSize` / `clear` / `clearAsset` for memory management
/// - `pauseLoading` / `resumeLoading` for scroll optimization
///
/// Thread Safety: All mutable state is actor-isolated. External callers
/// use `await` to access cache operations.
actor ThumbnailCache {

    // MARK: - Configuration

    /// Maximum memory budget for thumbnails (bytes).
    let maxMemoryBytes: Int

    /// Maximum number of thumbnails to keep in cache.
    let maxThumbnails: Int

    /// Maximum concurrent thumbnail loads.
    private let maxConcurrentLoads: Int = 4

    // MARK: - State

    /// LRU-ordered cache: first entry is least recently used.
    /// OrderedDictionary preserves insertion order; we move entries to
    /// the end on access to implement LRU.
    private var cache: OrderedDictionary<ThumbnailKey, CachedThumbnail> = [:]

    /// Keys currently being loaded.
    private var loading: Set<ThumbnailKey> = []

    /// Pending load requests sorted by priority (highest first), then by age (oldest first).
    private var loadQueue: [ThumbnailCacheRequest] = []

    /// Current memory usage in bytes.
    private var _currentMemoryBytes: Int = 0

    /// Whether loading is paused (e.g., during fast scrolling).
    private var isPaused: Bool = false

    // MARK: - Callbacks

    /// Optional callback invoked when a thumbnail is loaded.
    var onThumbnailLoaded: ThumbnailLoadCallback?

    /// Platform-specific thumbnail loader.
    var thumbnailLoader: ThumbnailLoader?

    /// Set the thumbnail loader (convenience for tests).
    func setThumbnailLoader(_ loader: ThumbnailLoader?) {
        self.thumbnailLoader = loader
    }

    // MARK: - Init

    /// Creates a thumbnail cache with configurable limits.
    ///
    /// - Parameters:
    ///   - maxMemoryBytes: Maximum memory budget in bytes. Default 50 MB.
    ///   - maxThumbnails: Maximum number of cached thumbnails. Default 500.
    init(
        maxMemoryBytes: Int = 50 * 1024 * 1024,
        maxThumbnails: Int = 500
    ) {
        self.maxMemoryBytes = maxMemoryBytes
        self.maxThumbnails = maxThumbnails
    }

    // MARK: - Cache Access

    /// Gets a cached thumbnail, or schedules a load if not cached.
    ///
    /// On cache hit, promotes the entry to most-recently-used.
    /// On cache miss, schedules an async load and returns nil.
    ///
    /// - Parameters:
    ///   - assetId: Media asset identifier.
    ///   - timeMicros: Source time in microseconds.
    ///   - width: Target thumbnail width.
    /// - Returns: The cached UIImage, or nil if not yet loaded.
    func getThumbnail(assetId: String, timeMicros: TimeMicros, width: Int) -> UIImage? {
        let key = ThumbnailKey(assetId: assetId, timeMicros: timeMicros, width: width)

        // Check cache and promote on hit.
        if let entry = cache.removeValue(forKey: key) {
            cache[key] = entry  // Re-insert at end (most recently used)
            return entry.image
        }

        // Schedule load if not already loading.
        if !loading.contains(key) {
            scheduleLoad(key: key, priority: calculatePriority(key))
        }

        return nil
    }

    /// Checks whether a thumbnail is cached.
    func hasThumbnail(assetId: String, timeMicros: TimeMicros, width: Int) -> Bool {
        let key = ThumbnailKey(assetId: assetId, timeMicros: timeMicros, width: width)
        return cache[key] != nil
    }

    // MARK: - Preload

    /// Preloads thumbnails for a time range at low priority.
    ///
    /// - Parameters:
    ///   - assetId: Media asset identifier.
    ///   - startMicros: Start of the range (microseconds).
    ///   - endMicros: End of the range (microseconds).
    ///   - width: Target thumbnail width.
    ///   - count: Number of thumbnails to generate across the range.
    func preload(
        assetId: String,
        startMicros: TimeMicros,
        endMicros: TimeMicros,
        width: Int,
        count: Int
    ) {
        guard count > 0 else { return }

        let step = (endMicros - startMicros) / TimeMicros(count)
        for i in 0..<count {
            let time = startMicros + TimeMicros(i) * step
            let key = ThumbnailKey(assetId: assetId, timeMicros: time, width: width)

            if cache[key] == nil && !loading.contains(key) {
                scheduleLoad(key: key, priority: 0)  // Low priority for preloads
            }
        }
    }

    // MARK: - Priority Updates

    /// Updates load priorities based on viewport visibility and playhead proximity.
    ///
    /// Rebuilds the load queue with recalculated priorities.
    ///
    /// - Parameters:
    ///   - visibleKeys: Keys currently visible in the viewport.
    ///   - playheadTimeMicros: Current playhead position.
    ///   - viewportCenterMicros: Center of the visible viewport.
    func updatePriorities(
        visibleKeys: Set<ThumbnailKey>,
        playheadTimeMicros: TimeMicros,
        viewportCenterMicros: TimeMicros
    ) {
        let oldRequests = loadQueue
        loadQueue.removeAll()

        for request in oldRequests {
            var priority = 0

            // Boost priority for visible thumbnails.
            if visibleKeys.contains(request.key) {
                priority += 10
            }

            // Boost priority for thumbnails near the playhead (within 5 seconds).
            let distanceToPlayhead = abs(request.key.timeMicros - playheadTimeMicros)
            if distanceToPlayhead < 5_000_000 {
                priority += 5
            }

            loadQueue.append(ThumbnailCacheRequest(
                key: request.key,
                priority: priority,
                requestTime: request.requestTime
            ))
        }

        sortLoadQueue()
    }

    // MARK: - Loading Control

    /// Pauses thumbnail loading (e.g., during fast scrolling).
    func pauseLoading() {
        isPaused = true
    }

    /// Resumes thumbnail loading.
    func resumeLoading() {
        isPaused = false
        processLoadQueue()
    }

    // MARK: - Cache Management

    /// Clears all cached thumbnails and cancels pending loads.
    func clear() {
        cache.removeAll()
        loadQueue.removeAll()
        loading.removeAll()
        _currentMemoryBytes = 0
    }

    /// Reduces cache to a target percentage of current entries.
    ///
    /// Evicts oldest entries (LRU) until the target count is reached.
    ///
    /// - Parameter keepPercentage: Fraction of entries to retain (0.0 - 1.0).
    func reduceSize(_ keepPercentage: Double) {
        let targetCount = Int(Double(cache.count) * keepPercentage)
        while cache.count > targetCount {
            evictOldest()
        }
    }

    /// Clears all thumbnails for a specific asset.
    ///
    /// Also removes pending loads and active loads for the asset.
    func clearAsset(_ assetId: String) {
        let keysToRemove = cache.keys.filter { $0.assetId == assetId }
        for key in keysToRemove {
            if let entry = cache.removeValue(forKey: key) {
                _currentMemoryBytes -= entry.sizeBytes
            }
        }

        loadQueue.removeAll { $0.key.assetId == assetId }
        loading = loading.filter { $0.assetId != assetId }
    }

    // MARK: - Read-Only Properties

    /// Current memory usage in bytes.
    var currentMemoryBytes: Int { _currentMemoryBytes }

    /// Number of cached thumbnails.
    var cachedCount: Int { cache.count }

    /// Number of pending loads in queue.
    var pendingCount: Int { loadQueue.count }

    /// Number of currently active loads.
    var loadingCount: Int { loading.count }

    // MARK: - Dispose

    /// Releases all resources.
    func dispose() {
        clear()
    }

    // MARK: - Private Helpers

    /// Calculates default priority for a thumbnail key.
    private func calculatePriority(_ key: ThumbnailKey) -> Int {
        5  // Default priority; can be overridden via updatePriorities
    }

    /// Schedules a load by appending to the queue and triggering processing.
    private func scheduleLoad(key: ThumbnailKey, priority: Int) {
        loadQueue.append(ThumbnailCacheRequest(
            key: key,
            priority: priority,
            requestTime: Date()
        ))
        sortLoadQueue()
        processLoadQueue()
    }

    /// Sorts the load queue: highest priority first, then oldest request first.
    private func sortLoadQueue() {
        loadQueue.sort { a, b in
            if a.priority != b.priority {
                return a.priority > b.priority  // Higher priority first
            }
            return a.requestTime < b.requestTime  // Older requests first
        }
    }

    /// Processes the load queue, launching loads up to the concurrency limit.
    private func processLoadQueue() {
        guard !isPaused, thumbnailLoader != nil else { return }

        while loading.count < maxConcurrentLoads && !loadQueue.isEmpty {
            let request = loadQueue.removeFirst()

            // Skip if already cached (may have loaded while queued).
            if cache[request.key] != nil { continue }

            loading.insert(request.key)
            loadThumbnail(request.key)
        }
    }

    /// Loads a single thumbnail asynchronously.
    private func loadThumbnail(_ key: ThumbnailKey) {
        guard let loader = thumbnailLoader else { return }

        Task { [weak self] in
            let image = await loader(key.assetId, key.timeMicros, key.width)

            guard let self else { return }

            if let image {
                await self.addToCache(key: key, image: image)
                await self.onThumbnailLoaded?(key, image)
            }

            await self.finishLoading(key)
        }
    }

    /// Adds a thumbnail to the cache, evicting LRU entries if needed.
    private func addToCache(key: ThumbnailKey, image: UIImage) {
        let imageBytes = estimateImageBytes(image)

        // Evict until there is room.
        while _currentMemoryBytes + imageBytes > maxMemoryBytes
            || cache.count >= maxThumbnails
        {
            if cache.isEmpty { break }
            evictOldest()
        }

        cache[key] = CachedThumbnail(image: image, sizeBytes: imageBytes)
        _currentMemoryBytes += imageBytes
    }

    /// Marks a key as finished loading and triggers more queue processing.
    private func finishLoading(_ key: ThumbnailKey) {
        loading.remove(key)
        processLoadQueue()
    }

    /// Evicts the least recently used (first) entry from the cache.
    private func evictOldest() {
        guard !cache.isEmpty else { return }

        // OrderedDictionary: index 0 is the oldest (LRU).
        let (_, entry) = cache.removeFirst()
        _currentMemoryBytes -= entry.sizeBytes
    }

    /// Estimates the memory footprint of a UIImage in bytes.
    private func estimateImageBytes(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else {
            // Fallback estimate: 4 bytes per pixel.
            let w = Int(image.size.width * image.scale)
            let h = Int(image.size.height * image.scale)
            return w * h * 4
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}
