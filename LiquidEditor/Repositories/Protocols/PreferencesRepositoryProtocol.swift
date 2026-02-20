// PreferencesRepositoryProtocol.swift
// LiquidEditor
//
// Protocol for user preferences persistence.
// Type-safe wrapper around UserDefaults with Codable support.

import Foundation

// MARK: - PreferencesRepositoryProtocol

/// Protocol for reading and writing user preferences.
///
/// Implementations provide a type-safe layer over `UserDefaults`,
/// supporting arbitrary `Codable & Sendable` values as well as
/// convenience accessors for common primitive types.
///
/// Preference operations are synchronous (backed by in-memory cache)
/// and do not throw, except for `set(_:forKey:)` which may fail if
/// the value cannot be encoded.
///
/// References:
/// - `RepositoryError` from Repositories/RepositoryError.swift
protocol PreferencesRepositoryProtocol: Sendable {

    /// Read a typed preference value.
    ///
    /// Returns `nil` if the key does not exist or the stored value
    /// cannot be decoded to the requested type.
    ///
    /// - Parameters:
    ///   - key: The preference key.
    ///   - type: The expected value type.
    /// - Returns: The decoded value, or `nil`.
    func get<T: Codable & Sendable>(key: String, type: T.Type) -> T?

    /// Write a typed preference value.
    ///
    /// Encodes the value as JSON and persists it under the given key.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - key: The preference key.
    /// - Throws: `RepositoryError.encodingFailed` if the value cannot be encoded.
    func set<T: Codable & Sendable>(_ value: T, forKey key: String) throws

    /// Remove a preference value.
    ///
    /// No-op if the key does not exist.
    ///
    /// - Parameter key: The preference key to remove.
    func remove(key: String)

    /// Check whether a preference key exists.
    ///
    /// - Parameter key: The preference key.
    /// - Returns: `true` if the key has a stored value, `false` otherwise.
    func contains(key: String) -> Bool

    /// Remove all stored preferences.
    ///
    /// Clears the entire preference store. Use with caution.
    func clearAll()

    // MARK: - Convenience Typed Accessors

    /// Read a `String` preference.
    ///
    /// - Parameter key: The preference key.
    /// - Returns: The stored string, or `nil`.
    func string(forKey key: String) -> String?

    /// Read an `Int` preference.
    ///
    /// - Parameter key: The preference key.
    /// - Returns: The stored integer, or `nil`.
    func int(forKey key: String) -> Int?

    /// Read a `Double` preference.
    ///
    /// - Parameter key: The preference key.
    /// - Returns: The stored double, or `nil`.
    func double(forKey key: String) -> Double?

    /// Read a `Bool` preference.
    ///
    /// - Parameter key: The preference key.
    /// - Returns: The stored boolean, or `nil`.
    func bool(forKey key: String) -> Bool?

    /// Read a `Date` preference.
    ///
    /// - Parameter key: The preference key.
    /// - Returns: The stored date, or `nil`.
    func date(forKey key: String) -> Date?
}
