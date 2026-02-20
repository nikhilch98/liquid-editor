/// LUT service for managing LUT files.
///
/// Handles importing, storing, caching, and resolving LUT files.
/// Custom LUTs are stored in the app's Documents/LUTs directory.
/// Bundled LUTs are loaded from a manifest of known presets.
///
/// Thread Safety: `actor` isolation ensures all file I/O and cache
/// mutations are serialized. The public API is fully async.

import Foundation
import os

// MARK: - LUTService

/// Manages LUT files: import, store, cache, and resolve.
///
/// Uses actor isolation for safe concurrent access to the LUT list
/// and file I/O operations.
actor LUTService {

    // MARK: - Properties

    private static let logger = Logger(subsystem: "LiquidEditor", category: "LUTService")

    /// All available LUTs (bundled + custom).
    private var luts: [LUTReference] = []

    /// Whether LUTs have been loaded.
    private var isLoaded = false

    /// Resolved path cache: asset path -> file system path.
    private var pathCache: [String: String] = [:]

    // MARK: - Public API (Read)

    /// All available LUTs.
    var allLUTs: [LUTReference] { luts }

    /// Bundled LUTs only.
    var bundledLUTs: [LUTReference] { luts.filter(\.isBundled) }

    /// Custom (user-imported) LUTs only.
    var customLUTs: [LUTReference] { luts.filter(\.isCustom) }

    /// Whether LUTs have been loaded.
    var loaded: Bool { isLoaded }

    /// Get LUTs filtered by category.
    func lutsForCategory(_ category: String?) -> [LUTReference] {
        guard let category else { return luts }
        return luts.filter { $0.category == category }
    }

    /// All unique categories across all LUTs, sorted alphabetically.
    var categories: [String] {
        let cats = Set(luts.compactMap(\.category))
        return cats.sorted()
    }

    /// Get a LUT by ID.
    func getById(_ id: String) -> LUTReference? {
        luts.first { $0.id == id }
    }

    // MARK: - Initialization

    /// Load bundled and custom LUTs.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    func initialize() async {
        guard !isLoaded else { return }

        loadBundledLUTs()
        await loadCustomLUTs()

        isLoaded = true
    }

    // MARK: - Import / Remove

    /// Import a custom LUT file.
    ///
    /// Validates the file, copies it to Documents/LUTs/, and registers it.
    /// Returns the new `LUTReference` on success, or nil on failure.
    func importLUT(from sourcePath: String) async -> LUTReference? {
        let result = LUTParser.parseFile(at: sourcePath)
        guard result.isSuccess, let parsed = result.lut else {
            Self.logger.warning("Failed to parse LUT file: \(sourcePath)")
            return nil
        }

        let lutsDir = customLUTsDirectory
        let lutId = UUID().uuidString
        let ext = sourcePath.lowercased().hasSuffix(".3dl") ? ".3dl"
                : sourcePath.lowercased().hasSuffix(".vlt") ? ".vlt"
                : ".cube"
        let destPath = (lutsDir as NSString).appendingPathComponent("\(lutId)\(ext)")

        do {
            try FileManager.default.copyItem(atPath: sourcePath, toPath: destPath)
        } catch {
            Self.logger.error("Failed to copy LUT file: \(error.localizedDescription)")
            return nil
        }

        let lutRef = LUTReference(
            id: lutId,
            name: parsed.title,
            lutAssetPath: "custom://\(lutId)",
            source: .custom,
            dimension: parsed.dimension,
            intensity: 1.0,
            category: "custom"
        )

        luts.append(lutRef)
        await persistCustomLUTIndex()

        return lutRef
    }

    /// Remove a custom LUT by ID.
    ///
    /// Deletes the file from disk and removes from the index.
    /// No-op if the ID is not found or refers to a bundled LUT.
    func removeLUT(_ lutId: String) async {
        guard let index = luts.firstIndex(where: { $0.id == lutId && $0.isCustom }) else {
            return
        }

        // Delete the file
        let lutsDir = customLUTsDirectory
        for ext in ["cube", "3dl", "vlt"] {
            let path = (lutsDir as NSString).appendingPathComponent("\(lutId).\(ext)")
            try? FileManager.default.removeItem(atPath: path)
        }

        // Remove from path cache
        pathCache.removeValue(forKey: "custom://\(lutId)")

        luts.remove(at: index)
        await persistCustomLUTIndex()
    }

    // MARK: - Path Resolution

    /// Resolve a LUT asset path to an actual file system path.
    ///
    /// - `bundled://category/name` -> Bundle resource path
    /// - `custom://uuid` -> Documents/LUTs/uuid.{cube,3dl,vlt}
    func resolveAssetPath(_ assetPath: String) -> String? {
        // Check cache
        if let cached = pathCache[assetPath] {
            return cached
        }

        let resolved: String?

        if assetPath.hasPrefix("bundled://") {
            let subpath = String(assetPath.dropFirst("bundled://".count))
            resolved = Bundle.main.path(forResource: subpath, ofType: nil)
                ?? Bundle.main.path(forResource: subpath, ofType: "cube")
                ?? Bundle.main.path(forResource: subpath, ofType: nil, inDirectory: "LUTs")
        } else if assetPath.hasPrefix("custom://") {
            let lutId = String(assetPath.dropFirst("custom://".count))
            let lutsDir = customLUTsDirectory
            let candidates = ["cube", "3dl", "vlt"].map {
                (lutsDir as NSString).appendingPathComponent("\(lutId).\($0)")
            }
            resolved = candidates.first { FileManager.default.fileExists(atPath: $0) }
        } else {
            resolved = nil
        }

        if let resolved {
            pathCache[assetPath] = resolved
        }

        return resolved
    }

    /// Invalidate the path cache (e.g. after file operations).
    func invalidatePathCache() {
        pathCache.removeAll()
    }

    /// Invalidate the cache for a specific asset path.
    func invalidatePathCache(for assetPath: String) {
        pathCache.removeValue(forKey: assetPath)
    }

    // MARK: - Private: Bundled LUTs

    private func loadBundledLUTs() {
        let bundled: [(String, String, String)] = [
            // Cinematic
            ("teal_orange", "Teal & Orange", "cinematic"),
            ("film_noir", "Film Noir", "cinematic"),
            ("golden_hour", "Golden Hour", "cinematic"),
            ("moonlight", "Moonlight", "cinematic"),
            ("blockbuster", "Blockbuster", "cinematic"),
            ("anamorphic", "Anamorphic", "cinematic"),
            // Vintage
            ("polaroid", "Polaroid", "vintage"),
            ("kodak_portra", "Kodak Portra 400", "vintage"),
            ("fuji_superia", "Fuji Superia", "vintage"),
            ("cross_process", "Cross Process", "vintage"),
            ("faded_film", "Faded Film", "vintage"),
            ("seventies_warm", "70s Warm", "vintage"),
            // B&W
            ("classic_bw", "Classic B&W", "bw"),
            ("high_contrast_bw", "High Contrast B&W", "bw"),
            ("sepia", "Sepia", "bw"),
            ("silver", "Silver", "bw"),
            // Portrait
            ("soft_glow", "Soft Glow", "portrait"),
            ("beauty", "Beauty", "portrait"),
            ("matte", "Matte", "portrait"),
            // Landscape
            ("vivid_nature", "Vivid Nature", "landscape"),
            ("sunrise", "Sunrise", "landscape"),
            ("overcast", "Overcast", "landscape"),
            // Social
            ("clean_pop", "Clean Pop", "social"),
            ("warm_glow", "Warm Glow", "social"),
            ("cool_tone", "Cool Tone", "social"),
        ]

        for (filename, name, category) in bundled {
            luts.append(LUTReference(
                id: "builtin_\(filename)",
                name: name,
                lutAssetPath: "bundled://\(category)/\(filename)",
                source: .bundled,
                dimension: 33,
                intensity: 1.0,
                category: category
            ))
        }
    }

    // MARK: - Private: Custom LUTs Persistence

    private var customLUTsDirectory: String {
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first ?? NSTemporaryDirectory()
        let lutsDir = (documentsPath as NSString).appendingPathComponent("LUTs")

        if !FileManager.default.fileExists(atPath: lutsDir) {
            try? FileManager.default.createDirectory(
                atPath: lutsDir, withIntermediateDirectories: true
            )
        }

        return lutsDir
    }

    private func loadCustomLUTs() async {
        let indexPath = (customLUTsDirectory as NSString)
            .appendingPathComponent("custom_luts.json")

        guard FileManager.default.fileExists(atPath: indexPath) else {
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: indexPath))
            let json = try JSONDecoder().decode(LUTIndexFile.self, from: data)
            luts.append(contentsOf: json.luts)
        } catch {
            Self.logger.error("Failed to load custom LUTs: \(error.localizedDescription)")
        }
    }

    private func persistCustomLUTIndex() async {
        let customLuts = luts.filter(\.isCustom)
        let indexFile = LUTIndexFile(luts: customLuts)

        let indexPath = (customLUTsDirectory as NSString)
            .appendingPathComponent("custom_luts.json")

        do {
            let data = try JSONEncoder().encode(indexFile)
            try data.write(to: URL(fileURLWithPath: indexPath))
        } catch {
            Self.logger.error("Failed to persist custom LUT index: \(error.localizedDescription)")
        }
    }
}

// MARK: - LUTIndexFile (private persistence model)

/// JSON container for the custom LUT index file.
private struct LUTIndexFile: Codable {
    let luts: [LUTReference]
}
