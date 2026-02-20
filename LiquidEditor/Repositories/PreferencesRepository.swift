// PreferencesRepository.swift
// LiquidEditor
//
// Thread-safe preferences persistence backed by UserDefaults.
// Uses OSAllocatedUnfairLock for lightweight synchronization since
// UserDefaults operations are fast and actor overhead is unnecessary.

@preconcurrency import Foundation
import os

// MARK: - PreferencesRepository

/// Thread-safe repository for reading and writing user preferences.
///
/// All keys are prefixed with `"LiquidEditor."` to avoid collisions with
/// other UserDefaults entries. Codable values are JSON-encoded to Data
/// before storage; primitive types use native UserDefaults methods.
///
/// Uses `OSAllocatedUnfairLock` for synchronization rather than actor
/// isolation, since UserDefaults access is fast and does not benefit
/// from cooperative task suspension.
///
/// ## Usage
/// ```swift
/// let prefs = PreferencesRepository()
/// try prefs.set(30.0, forKey: PreferencesRepository.keyDefaultFrameRate)
/// let fps: Double? = try prefs.double(forKey: PreferencesRepository.keyDefaultFrameRate)
/// ```
final class PreferencesRepository: PreferencesRepositoryProtocol, @unchecked Sendable {

    // MARK: - Known Preference Keys

    /// Default frame rate for new projects (Double).
    static let keyDefaultFrameRate = "defaultFrameRate"

    /// Default resolution preset for new projects (String, e.g. "1080p").
    static let keyDefaultResolution = "defaultResolution"

    /// Whether auto-save is enabled (Bool).
    static let keyAutoSaveEnabled = "autoSaveEnabled"

    /// Auto-save debounce interval in seconds (Double).
    static let keyAutoSaveIntervalSeconds = "autoSaveIntervalSeconds"

    /// ID of the last opened project (String).
    static let keyLastOpenedProjectId = "lastOpenedProjectId"

    /// Whether waveform display is enabled in the timeline (Bool).
    static let keyShowWaveforms = "showWaveforms"

    /// Whether snap-to-grid is enabled (Bool).
    static let keySnapToGrid = "snapToGrid"

    /// Number of grid subdivisions for snapping (Int).
    static let keyGridDivisions = "gridDivisions"

    /// Export quality preset (String, e.g. "high", "medium", "low").
    static let keyExportQuality = "exportQuality"

    /// Maximum number of undo steps to retain (Int).
    static let keyMaxUndoSteps = "maxUndoSteps"

    // MARK: - Logger

    private static let logger = Logger(subsystem: "LiquidEditor", category: "PreferencesRepository")

    // MARK: - Lock State

    /// Internal state protected by the unfair lock.
    private struct LockState: @unchecked Sendable {
        let prefix: String
        let defaults: UserDefaults
        let encoder: JSONEncoder
        let decoder: JSONDecoder
    }

    /// Unfair lock wrapping the shared state.
    private let lock: OSAllocatedUnfairLock<LockState>

    // MARK: - Initialization

    /// Create a preferences repository with standard UserDefaults.
    init() {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        enc.dateEncodingStrategy = .iso8601

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601

        self.lock = OSAllocatedUnfairLock(initialState: LockState(
            prefix: "LiquidEditor.",
            defaults: .standard,
            encoder: enc,
            decoder: dec
        ))
    }

    /// Create a preferences repository with a custom UserDefaults suite (for testing).
    ///
    /// - Parameter suiteName: The UserDefaults suite name.
    init(suiteName: String) {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        enc.dateEncodingStrategy = .iso8601

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.lock = OSAllocatedUnfairLock(initialState: LockState(
            prefix: "LiquidEditor.",
            defaults: defaults,
            encoder: enc,
            decoder: dec
        ))
    }

    // MARK: - Primitive Getters

    /// Read a string value.
    ///
    /// - Parameter key: The preference key (without prefix).
    /// - Returns: The stored string, or `nil` if not set.
    func string(forKey key: String) -> String? {
        lock.withLock { state in
            state.defaults.string(forKey: state.prefix + key)
        }
    }

    /// Read an integer value.
    ///
    /// - Parameter key: The preference key (without prefix).
    /// - Returns: The stored integer, or `nil` if not set.
    func int(forKey key: String) -> Int? {
        lock.withLock { state in
            guard state.defaults.object(forKey: state.prefix + key) != nil else { return nil }
            return state.defaults.integer(forKey: state.prefix + key)
        }
    }

    /// Read a double value.
    ///
    /// - Parameter key: The preference key (without prefix).
    /// - Returns: The stored double, or `nil` if not set.
    func double(forKey key: String) -> Double? {
        lock.withLock { state in
            guard state.defaults.object(forKey: state.prefix + key) != nil else { return nil }
            return state.defaults.double(forKey: state.prefix + key)
        }
    }

    /// Read a boolean value.
    ///
    /// - Parameter key: The preference key (without prefix).
    /// - Returns: The stored boolean, or `nil` if not set.
    func bool(forKey key: String) -> Bool? {
        lock.withLock { state in
            guard state.defaults.object(forKey: state.prefix + key) != nil else { return nil }
            return state.defaults.bool(forKey: state.prefix + key)
        }
    }

    /// Read a date value (stored as ISO 8601 string).
    ///
    /// - Parameter key: The preference key (without prefix).
    /// - Returns: The stored date, or `nil` if not set or unparseable.
    func date(forKey key: String) -> Date? {
        lock.withLock { state in
            guard let str = state.defaults.string(forKey: state.prefix + key) else { return nil }
            return ISO8601DateFormatter().date(from: str)
        }
    }

    // MARK: - Generic Getter (Protocol Requirement)

    /// Read a typed preference value (protocol requirement).
    ///
    /// Returns `nil` if the key does not exist or decoding fails.
    ///
    /// - Parameters:
    ///   - key: The preference key (without prefix).
    ///   - type: The expected value type.
    /// - Returns: The decoded value, or `nil`.
    func get<T: Codable & Sendable>(key: String, type: T.Type) -> T? {
        do {
            return try lock.withLock { state in
                guard let data = state.defaults.data(forKey: state.prefix + key) else { return nil }
                return try state.decoder.decode(T.self, from: data)
            }
        } catch {
            Self.logger.error("Failed to decode preference key '\(key)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Read a Codable value.
    ///
    /// - Parameters:
    ///   - type: The expected Codable type.
    ///   - key: The preference key (without prefix).
    /// - Returns: The decoded value, or `nil` if not set.
    /// - Throws: `RepositoryError.decodingFailed` if stored data cannot be decoded.
    func codable<T: Codable & Sendable>(_ type: T.Type, forKey key: String) throws -> T? {
        try lock.withLock { state in
            guard let data = state.defaults.data(forKey: state.prefix + key) else { return nil }
            do {
                return try state.decoder.decode(T.self, from: data)
            } catch {
                throw RepositoryError.decodingFailed(
                    "Failed to decode \(T.self) for key '\(key)': \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Generic Setter (Protocol Requirement)

    /// Store a Codable value (protocol requirement).
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - key: The preference key (without prefix).
    /// - Throws: `RepositoryError.encodingFailed` if encoding fails.
    func set<T: Codable & Sendable>(_ value: T, forKey key: String) throws {
        try lock.withLock { state in
            do {
                let data = try state.encoder.encode(value)
                state.defaults.set(data, forKey: state.prefix + key)
            } catch {
                throw RepositoryError.encodingFailed(
                    "Failed to encode \(T.self) for key '\(key)': \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Primitive Setters

    /// Store a string value.
    ///
    /// - Parameters:
    ///   - value: The string to store.
    ///   - key: The preference key (without prefix).
    func set(_ value: String, forKey key: String) {
        lock.withLock { state in
            state.defaults.set(value, forKey: state.prefix + key)
        }
    }

    /// Store an integer value.
    ///
    /// - Parameters:
    ///   - value: The integer to store.
    ///   - key: The preference key (without prefix).
    func set(_ value: Int, forKey key: String) {
        lock.withLock { state in
            state.defaults.set(value, forKey: state.prefix + key)
        }
    }

    /// Store a double value.
    ///
    /// - Parameters:
    ///   - value: The double to store.
    ///   - key: The preference key (without prefix).
    func set(_ value: Double, forKey key: String) {
        lock.withLock { state in
            state.defaults.set(value, forKey: state.prefix + key)
        }
    }

    /// Store a boolean value.
    ///
    /// - Parameters:
    ///   - value: The boolean to store.
    ///   - key: The preference key (without prefix).
    func set(_ value: Bool, forKey key: String) {
        lock.withLock { state in
            state.defaults.set(value, forKey: state.prefix + key)
        }
    }

    /// Store a date value as ISO 8601 string.
    ///
    /// - Parameters:
    ///   - value: The date to store.
    ///   - key: The preference key (without prefix).
    func set(_ value: Date, forKey key: String) {
        lock.withLock { state in
            let str = ISO8601DateFormatter().string(from: value)
            state.defaults.set(str, forKey: state.prefix + key)
        }
    }

    /// Store a Codable value as JSON data.
    ///
    /// - Parameters:
    ///   - value: The Codable value to store.
    ///   - key: The preference key (without prefix).
    /// - Throws: `RepositoryError.encodingFailed` if serialization fails.
    func setCodable<T: Codable & Sendable>(_ value: T, forKey key: String) throws {
        try lock.withLock { state in
            let data: Data
            do {
                data = try state.encoder.encode(value)
            } catch {
                throw RepositoryError.encodingFailed(
                    "Failed to encode \(T.self) for key '\(key)': \(error.localizedDescription)"
                )
            }
            state.defaults.set(data, forKey: state.prefix + key)
        }
    }

    // MARK: - Removal

    /// Remove a stored preference.
    ///
    /// - Parameter key: The preference key (without prefix).
    func remove(key: String) {
        lock.withLock { state in
            state.defaults.removeObject(forKey: state.prefix + key)
        }
    }

    /// Check whether a preference exists.
    ///
    /// - Parameter key: The preference key (without prefix).
    /// - Returns: `true` if a value is stored for this key.
    func contains(key: String) -> Bool {
        lock.withLock { state in
            state.defaults.object(forKey: state.prefix + key) != nil
        }
    }

    /// Remove all preferences with the LiquidEditor prefix.
    ///
    /// This is a destructive operation that resets all user preferences.
    /// Primarily used for testing or factory reset functionality.
    func clearAll() {
        lock.withLock { state in
            let allKeys = state.defaults.dictionaryRepresentation().keys
            let keysToRemove = allKeys.filter { $0.hasPrefix(state.prefix) }

            if !keysToRemove.isEmpty {
                Self.logger.warning("Clearing \(keysToRemove.count) LiquidEditor preferences. This action cannot be undone.")
            }

            for key in keysToRemove {
                state.defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Convenience Methods

    /// Read the default frame rate preference.
    ///
    /// - Returns: The stored frame rate, or `nil` if not set.
    func defaultFrameRate() -> Double? {
        double(forKey: Self.keyDefaultFrameRate)
    }

    /// Read the auto-save enabled preference.
    ///
    /// - Returns: The stored value, or `true` if not set (auto-save on by default).
    func isAutoSaveEnabled() -> Bool {
        bool(forKey: Self.keyAutoSaveEnabled) ?? true
    }

    /// Read the auto-save interval in seconds.
    ///
    /// - Returns: The stored interval, or `2.0` if not set.
    func autoSaveIntervalSeconds() -> Double {
        double(forKey: Self.keyAutoSaveIntervalSeconds) ?? 2.0
    }

    /// Read the last opened project ID.
    ///
    /// - Returns: The project ID, or `nil` if no project was opened.
    func lastOpenedProjectId() -> String? {
        string(forKey: Self.keyLastOpenedProjectId)
    }

    /// Read the maximum undo steps.
    ///
    /// - Returns: The stored value, or `50` if not set.
    func maxUndoSteps() -> Int {
        int(forKey: Self.keyMaxUndoSteps) ?? 50
    }
}
