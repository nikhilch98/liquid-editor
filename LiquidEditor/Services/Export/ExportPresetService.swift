// ExportPresetService.swift
// LiquidEditor
//
// Manages built-in and custom export presets for quick-access
// export configurations and social media platforms.

import Foundation
import os

// MARK: - ExportPreset

/// A named export preset with configuration.
struct ExportPreset: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Unique identifier.
    let id: String

    /// User-visible name.
    let name: String

    /// Description of the preset.
    let description: String

    /// SF Symbol name for the preset icon.
    let sfSymbolName: String

    /// The export configuration.
    let config: ExportConfig

    /// Whether this is a built-in preset (cannot be deleted).
    let isBuiltIn: Bool

    init(
        id: String,
        name: String,
        description: String,
        sfSymbolName: String,
        config: ExportConfig,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sfSymbolName = sfSymbolName
        self.config = config
        self.isBuiltIn = isBuiltIn
    }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        name: String? = nil,
        description: String? = nil,
        sfSymbolName: String? = nil,
        config: ExportConfig? = nil,
        isBuiltIn: Bool? = nil
    ) -> ExportPreset {
        ExportPreset(
            id: id ?? self.id,
            name: name ?? self.name,
            description: description ?? self.description,
            sfSymbolName: sfSymbolName ?? self.sfSymbolName,
            config: config ?? self.config,
            isBuiltIn: isBuiltIn ?? self.isBuiltIn
        )
    }

    // MARK: - Equatable / Hashable by ID

    static func == (lhs: ExportPreset, rhs: ExportPreset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ExportPresetService

/// Manages export presets: built-in presets, social media presets,
/// and custom user-created presets.
///
/// ## Built-in Presets
///
/// Provides five standard presets:
/// - Quick Share (720p, H.264)
/// - Standard (1080p, H.264)
/// - High Quality (1080p 60fps, HEVC)
/// - 4K (4K, HEVC)
/// - Audio Only (AAC)
///
/// ## Social Presets
///
/// Generated from `SocialMediaPreset` values (Instagram, TikTok, etc.).
///
/// ## Custom Presets
///
/// Users can create, update, and delete custom presets.
/// Custom presets are persisted to disk.
enum ExportPresetService {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "LiquidEditor", category: "ExportPresetService")

    // MARK: - Built-in Presets

    /// Built-in presets for common use cases.
    static let builtInPresets: [ExportPreset] = [
        ExportPreset(
            id: "quick_share",
            name: "Quick Share",
            description: "720p, fast encode for sharing",
            sfSymbolName: "bolt",
            config: ExportConfig(
                resolution: .r720p,
                fps: 30,
                codec: .h264,
                format: .mp4,
                quality: .standard,
                bitrateMbps: 8.0
            ),
            isBuiltIn: true
        ),
        ExportPreset(
            id: "standard",
            name: "Standard",
            description: "1080p, balanced quality and size",
            sfSymbolName: "film",
            config: ExportConfig(
                resolution: .r1080p,
                fps: 30,
                codec: .h264,
                format: .mp4,
                quality: .high,
                bitrateMbps: 20.0
            ),
            isBuiltIn: true
        ),
        ExportPreset(
            id: "high_quality",
            name: "High Quality",
            description: "1080p, high bitrate for maximum quality",
            sfSymbolName: "sparkles",
            config: ExportConfig(
                resolution: .r1080p,
                fps: 60,
                codec: .h265,
                format: .mp4,
                quality: .maximum,
                bitrateMbps: 40.0
            ),
            isBuiltIn: true
        ),
        ExportPreset(
            id: "4k",
            name: "4K",
            description: "4K resolution, HEVC codec",
            sfSymbolName: "4k.tv",
            config: ExportConfig(
                resolution: .r4K,
                fps: 30,
                codec: .h265,
                format: .mp4,
                quality: .high,
                bitrateMbps: 50.0
            ),
            isBuiltIn: true
        ),
        ExportPreset(
            id: "audio_only",
            name: "Audio Only",
            description: "AAC audio, no video",
            sfSymbolName: "waveform",
            config: ExportConfig(
                audioCodec: .aac,
                audioBitrate: 256,
                audioOnly: true
            ),
            isBuiltIn: true
        ),
    ]

    // MARK: - Social Presets

    /// Social media presets generated from platform definitions.
    static var socialPresets: [ExportPreset] {
        SocialMediaPreset.allCases.map { preset in
            ExportPreset(
                id: "social_\(preset.rawValue)",
                name: preset.displayName,
                description: "\(preset.width)x\(preset.height), "
                    + "\(preset.maxFps)fps, \(preset.codec.displayName)",
                sfSymbolName: preset.sfSymbolName,
                config: preset.toExportConfig(),
                isBuiltIn: true
            )
        }
    }

    // MARK: - All Presets

    /// All available presets (built-in + social).
    static var allPresets: [ExportPreset] {
        builtInPresets + socialPresets
    }

    // MARK: - Lookup

    /// Find a preset by ID.
    ///
    /// - Parameter id: The preset identifier to search for.
    /// - Returns: The matching preset, or nil if not found.
    static func findById(_ id: String) -> ExportPreset? {
        allPresets.first { $0.id == id }
    }

    // MARK: - Custom Preset Persistence

    /// Lock serializing all file I/O to prevent concurrent read/write corruption.
    private static let ioLock = OSAllocatedUnfairLock(initialState: ())

    /// File URL for custom presets storage.
    private static var customPresetsFileURL: URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return documentsDir.appendingPathComponent("custom_export_presets.json")
    }

    /// Load custom presets from disk.
    ///
    /// Thread-safe: serialized by internal lock.
    ///
    /// - Returns: Array of custom presets, or empty array if none exist.
    static func loadCustomPresets() -> [ExportPreset] {
        ioLock.withLock {
            _loadCustomPresetsUnsafe()
        }
    }

    /// Save custom presets to disk.
    ///
    /// Thread-safe: serialized by internal lock.
    ///
    /// - Parameter presets: The custom presets to save.
    static func saveCustomPresets(_ presets: [ExportPreset]) {
        ioLock.withLock {
            _saveCustomPresetsUnsafe(presets)
        }
    }

    /// Add a custom preset.
    ///
    /// Thread-safe: serialized by internal lock.
    ///
    /// - Parameter preset: The preset to add.
    /// - Returns: Updated list of custom presets.
    @discardableResult
    static func addCustomPreset(_ preset: ExportPreset) -> [ExportPreset] {
        ioLock.withLock {
            var presets = _loadCustomPresetsUnsafe()
            presets.append(preset.with(isBuiltIn: false))
            _saveCustomPresetsUnsafe(presets)
            return presets
        }
    }

    /// Update an existing custom preset.
    ///
    /// Thread-safe: serialized by internal lock.
    ///
    /// - Parameter preset: The preset with updated values.
    /// - Returns: Updated list of custom presets.
    @discardableResult
    static func updateCustomPreset(_ preset: ExportPreset) -> [ExportPreset] {
        ioLock.withLock {
            var presets = _loadCustomPresetsUnsafe()
            if let index = presets.firstIndex(where: { $0.id == preset.id }) {
                presets[index] = preset.with(isBuiltIn: false)
                _saveCustomPresetsUnsafe(presets)
            }
            return presets
        }
    }

    /// Delete a custom preset.
    ///
    /// Thread-safe: serialized by internal lock.
    /// Built-in presets cannot be deleted.
    ///
    /// - Parameter presetId: The ID of the preset to delete.
    /// - Returns: Updated list of custom presets.
    @discardableResult
    static func deleteCustomPreset(_ presetId: String) -> [ExportPreset] {
        ioLock.withLock {
            var presets = _loadCustomPresetsUnsafe()
            presets.removeAll { $0.id == presetId && !$0.isBuiltIn }
            _saveCustomPresetsUnsafe(presets)
            return presets
        }
    }

    // MARK: - Unsafe I/O (must be called under ioLock)

    /// Load custom presets without locking. Caller must hold `ioLock`.
    private static func _loadCustomPresetsUnsafe() -> [ExportPreset] {
        let fileURL = customPresetsFileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode([ExportPreset].self, from: data)
        } catch {
            logger.error("Failed to load custom presets: \(error)")
            return []
        }
    }

    /// Save custom presets without locking. Caller must hold `ioLock`.
    private static func _saveCustomPresetsUnsafe(_ presets: [ExportPreset]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(presets)
            try data.write(to: customPresetsFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save custom presets: \(error)")
        }
    }
}
