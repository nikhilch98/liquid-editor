// StickerImageCache.swift
// LiquidEditor
//
// LRU image cache for decoded sticker UIImages.
// Uses OrderedDictionary from swift-collections for O(1) LRU operations.
// Responds to memory pressure via NotificationCenter.
//
// Thread Safety: `actor` isolation ensures all cache operations
// are accessed serially.

import Foundation
import OrderedCollections
import UIKit
import os

// MARK: - CacheEntry

/// Internal entry in the sticker image cache.
private struct CacheEntry: Sendable {
    /// The decoded image.
    let image: UIImage

    /// Estimated memory usage in bytes (width * height * 4 for RGBA).
    let memorySizeBytes: Int

    /// When this entry was last accessed.
    let lastAccessed: Date

    /// Create a copy with updated access time.
    func touched() -> CacheEntry {
        CacheEntry(
            image: image,
            memorySizeBytes: memorySizeBytes,
            lastAccessed: Date()
        )
    }
}

// MARK: - StickerImageCache

/// LRU cache for decoded sticker images.
///
/// Keyed by sticker asset ID. Evicts least-recently-used entries
/// when capacity is exceeded (by count or memory).
///
/// Responds to `UIApplication.didReceiveMemoryWarningNotification`
/// by evicting half the cache.
///
/// Thread Safety: `actor` isolation ensures serial access to all
/// mutable state. Images are `UIImage` which is `Sendable`.
actor StickerImageCache {

    // MARK: - Configuration

    /// Maximum number of cached images.
    let maxEntries: Int

    /// Maximum total memory usage in bytes.
    let maxMemoryBytes: Int

    // MARK: - State

    /// LRU cache using OrderedDictionary (insertion order = access order).
    /// Most recently used entries are at the end.
    private var cache: OrderedDictionary<String, CacheEntry> = [:]

    /// Current total memory usage in bytes.
    private(set) var currentMemoryBytes: Int = 0

    // MARK: - Logger

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.liquideditor",
        category: "StickerImageCache"
    )

    // MARK: - Memory Pressure Observer

    /// Task handle for memory pressure observation.
    private var memoryPressureTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a sticker image cache.
    ///
    /// - Parameters:
    ///   - maxEntries: Maximum number of cached images (default 100).
    ///   - maxMemoryBytes: Maximum total memory in bytes (default 50 MB).
    init(maxEntries: Int = 100, maxMemoryBytes: Int = 50 * 1024 * 1024) {
        self.maxEntries = maxEntries
        self.maxMemoryBytes = maxMemoryBytes
    }

    deinit {
        memoryPressureTask?.cancel()
    }

    // MARK: - Memory Pressure

    /// Start observing memory pressure warnings.
    ///
    /// Call once after initialization. Listens to
    /// `UIApplication.didReceiveMemoryWarningNotification`.
    func startObservingMemoryPressure() {
        memoryPressureTask?.cancel()
        memoryPressureTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: UIApplication.didReceiveMemoryWarningNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await self?.handleMemoryPressure()
            }
        }
    }

    /// Stop observing memory pressure warnings.
    func stopObservingMemoryPressure() {
        memoryPressureTask?.cancel()
        memoryPressureTask = nil
    }

    // MARK: - Computed Properties

    /// Number of cached images.
    var count: Int { cache.count }

    /// Current memory usage in megabytes.
    var currentMemoryMB: Double { Double(currentMemoryBytes) / (1024 * 1024) }

    /// Whether the cache is empty.
    var isEmpty: Bool { cache.isEmpty }

    // MARK: - Get

    /// Get a cached image by asset ID, or nil if not cached.
    ///
    /// Updates the LRU access order on hit (moves to end).
    ///
    /// - Parameter assetId: The sticker asset ID.
    /// - Returns: The cached `UIImage`, or `nil` if not in cache.
    func get(_ assetId: String) -> UIImage? {
        guard let entry = cache.removeValue(forKey: assetId) else {
            return nil
        }

        // Re-insert at end (most recently used position)
        let touched = entry.touched()
        cache[assetId] = touched
        return touched.image
    }

    // MARK: - Contains

    /// Check if an asset is cached (without updating access order).
    ///
    /// - Parameter assetId: The sticker asset ID.
    /// - Returns: `true` if the image is in the cache.
    func contains(_ assetId: String) -> Bool {
        cache[assetId] != nil
    }

    // MARK: - Put

    /// Cache a decoded image for an asset.
    ///
    /// If the cache is full, evicts the least-recently-used entry.
    /// If the single image exceeds `maxMemoryBytes`, it is not cached.
    ///
    /// - Parameters:
    ///   - assetId: The sticker asset ID.
    ///   - image: The decoded `UIImage` to cache.
    func put(_ assetId: String, image: UIImage) {
        // Remove existing entry if present
        if let existing = cache.removeValue(forKey: assetId) {
            currentMemoryBytes -= existing.memorySizeBytes
        }

        let memorySize = Int(image.size.width * image.scale)
            * Int(image.size.height * image.scale) * 4 // RGBA

        // Don't cache if single image exceeds total budget
        guard memorySize <= maxMemoryBytes else {
            logger.debug("Image \(assetId) too large to cache (\(memorySize) bytes)")
            return
        }

        // Evict until we have room
        while cache.count >= maxEntries ||
              currentMemoryBytes + memorySize > maxMemoryBytes {
            if cache.isEmpty { break }
            evictOldest()
        }

        cache[assetId] = CacheEntry(
            image: image,
            memorySizeBytes: memorySize,
            lastAccessed: Date()
        )
        currentMemoryBytes += memorySize
    }

    // MARK: - Remove

    /// Remove a specific asset from cache.
    ///
    /// - Parameter assetId: The sticker asset ID to remove.
    func remove(_ assetId: String) {
        if let entry = cache.removeValue(forKey: assetId) {
            currentMemoryBytes -= entry.memorySizeBytes
        }
    }

    // MARK: - Clear

    /// Clear all cached images and release memory.
    func clear() {
        cache.removeAll()
        currentMemoryBytes = 0
    }

    // MARK: - Memory Pressure

    /// Handle memory pressure warning from the system.
    ///
    /// Evicts half the cache to free memory.
    func handleMemoryPressure() {
        let targetCount = cache.count / 2
        while cache.count > targetCount {
            evictOldest()
        }
        logger.info("Memory pressure: evicted to \(self.cache.count) entries (\(self.currentMemoryMB, format: .fixed(precision: 1)) MB)")
    }

    // MARK: - Load and Cache

    /// Load an image from a file path and cache it.
    ///
    /// Returns the decoded `UIImage`, or nil if loading fails.
    /// If already cached, returns the cached version.
    ///
    /// - Parameters:
    ///   - assetId: The sticker asset ID.
    ///   - filePath: Absolute path to the image file.
    /// - Returns: The loaded `UIImage`, or `nil` if loading fails.
    func loadAndCache(assetId: String, filePath: String) -> UIImage? {
        // Check cache first
        if let cached = get(assetId) {
            return cached
        }

        guard let image = UIImage(contentsOfFile: filePath) else {
            logger.debug("Failed to load image at \(filePath)")
            return nil
        }

        put(assetId, image: image)
        return image
    }

    /// Load an image from raw bytes and cache it.
    ///
    /// Used for user-imported stickers loaded from the documents directory.
    ///
    /// - Parameters:
    ///   - assetId: The sticker asset ID.
    ///   - data: Raw image data.
    /// - Returns: The loaded `UIImage`, or `nil` if decoding fails.
    func loadFromDataAndCache(assetId: String, data: Data) -> UIImage? {
        // Check cache first
        if let cached = get(assetId) {
            return cached
        }

        guard let image = UIImage(data: data) else {
            logger.debug("Failed to decode image for \(assetId)")
            return nil
        }

        put(assetId, image: image)
        return image
    }

    // MARK: - Private

    /// Evict the least-recently-used entry (first in ordered dictionary).
    private func evictOldest() {
        guard !cache.isEmpty else { return }
        // First element in OrderedDictionary is the oldest (least recently used)
        let (_, entry) = cache.removeFirst()
        currentMemoryBytes -= entry.memorySizeBytes
    }
}
