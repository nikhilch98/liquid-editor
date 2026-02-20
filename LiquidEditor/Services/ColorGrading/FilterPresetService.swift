/// FilterPresetService - Filter preset management.
///
/// Manages built-in and custom filter presets.
/// Built-in presets come from `BuiltinPresets.all`.
/// Custom presets are persisted as JSON in the app's Documents directory.
///
/// Thread Safety: `@Observable @MainActor` for SwiftUI integration.
/// File I/O for custom presets is performed asynchronously.

import Foundation
import Observation
import os

// MARK: - FilterPresetService

/// Service for managing filter presets (built-in and custom).
@Observable
@MainActor
final class FilterPresetService {

    // MARK: - Properties

    private static let logger = Logger(subsystem: "LiquidEditor", category: "FilterPresetService")

    // MARK: - State

    /// All available presets (built-in + custom).
    private(set) var presets: [FilterPreset] = []

    /// Whether presets have been loaded.
    private(set) var isLoaded = false

    /// Custom storage directory (nil = default Documents/presets).
    /// Allows tests to provide an isolated temporary directory.
    private let storageDirectory: String?

    // MARK: - Init

    /// Create a preset service.
    /// - Parameter storageDirectory: Optional custom directory for preset persistence.
    ///   When nil, uses the default `Documents/presets` directory.
    init(storageDirectory: String? = nil) {
        self.storageDirectory = storageDirectory
    }

    // MARK: - Read API

    /// Built-in presets only.
    var builtinPresets: [FilterPreset] {
        presets.filter(\.isBuiltin)
    }

    /// User-created presets only.
    var userPresets: [FilterPreset] {
        presets.filter(\.isUser)
    }

    /// Get presets filtered by category.
    func presetsForCategory(_ category: String?) -> [FilterPreset] {
        guard let category else { return presets }
        return presets.filter { $0.category == category }
    }

    /// All unique categories across all presets, sorted.
    var categories: [String] {
        let cats = Set(presets.compactMap(\.category))
        return cats.sorted()
    }

    /// Get a preset by ID.
    func getById(_ id: String) -> FilterPreset? {
        presets.first { $0.id == id }
    }

    // MARK: - Initialization

    /// Load built-in presets and custom presets from disk.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    func initialize() async {
        guard !isLoaded else { return }

        // Add built-in presets
        presets.append(contentsOf: BuiltinPresets.all)

        // Load custom presets from disk
        await loadCustomPresets()

        isLoaded = true
    }

    // MARK: - CRUD for Custom Presets

    /// Save a new user preset from a color grade.
    @discardableResult
    func savePreset(
        name: String,
        grade: ColorGrade,
        description: String? = nil,
        category: String? = nil
    ) async -> FilterPreset {
        let preset = FilterPreset(
            id: UUID().uuidString,
            name: name,
            description: description,
            grade: grade,
            source: .user,
            category: category,
            createdAt: Date()
        )

        presets.append(preset)
        await persistCustomPresets()

        return preset
    }

    /// Delete a user preset.
    ///
    /// No-op if the ID is not found or refers to a built-in preset.
    func deletePreset(_ presetId: String) async {
        guard let index = presets.firstIndex(
            where: { $0.id == presetId && $0.source == .user }
        ) else {
            return
        }

        presets.remove(at: index)
        await persistCustomPresets()
    }

    /// Update a user preset.
    ///
    /// No-op if the preset is not found or is built-in.
    func updatePreset(_ preset: FilterPreset) async {
        guard preset.source == .user else { return }

        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else {
            return
        }

        presets[index] = preset
        await persistCustomPresets()
    }

    // MARK: - Private: Persistence

    private var presetsFilePath: String {
        let presetsDir: String
        if let storageDirectory {
            presetsDir = storageDirectory
        } else {
            let documentsPath = NSSearchPathForDirectoriesInDomains(
                .documentDirectory, .userDomainMask, true
            ).first ?? NSTemporaryDirectory()
            presetsDir = (documentsPath as NSString).appendingPathComponent("presets")
        }

        if !FileManager.default.fileExists(atPath: presetsDir) {
            try? FileManager.default.createDirectory(
                atPath: presetsDir, withIntermediateDirectories: true
            )
        }

        return (presetsDir as NSString).appendingPathComponent("color_presets.json")
    }

    private func loadCustomPresets() async {
        let path = presetsFilePath

        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let file = try JSONDecoder().decode(PresetsFile.self, from: data)
            presets.append(contentsOf: file.presets)
        } catch {
            Self.logger.error("Failed to load custom presets: \(error.localizedDescription)")
        }
    }

    private func persistCustomPresets() async {
        let customPresets = presets.filter { $0.source == .user }
        let file = PresetsFile(presets: customPresets)

        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: URL(fileURLWithPath: presetsFilePath))
        } catch {
            Self.logger.error("Failed to persist custom presets: \(error.localizedDescription)")
        }
    }
}

// MARK: - PresetsFile (private persistence model)

/// JSON container for the custom presets file.
private struct PresetsFile: Codable {
    let presets: [FilterPreset]
}
