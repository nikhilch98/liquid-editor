// FontManager.swift
// LiquidEditor
//
// Font management service (C5-21).
//
// Manages both system-installed fonts and user-imported custom fonts.
// Custom fonts are copied into the app's Documents/Fonts directory and
// registered with the Core Text font manager so they become usable by
// SwiftUI `Font.custom(...)` immediately and across app launches.
//
// Thread Safety: `@MainActor` isolated — all state reads (including via
// `@Observable`) happen on the main thread. File copy and font
// registration are performed off-main via detached tasks.

import CoreText
import Foundation
import SwiftUI
import UIKit
import os

// MARK: - FontManagerError

/// Errors surfaced by `FontManager` operations.
enum FontManagerError: LocalizedError, Sendable {
    case invalidSource
    case copyFailed(underlying: String)
    case registrationFailed(underlying: String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "The source font file could not be read."
        case .copyFailed(let reason):
            return "Failed to copy the font file: \(reason)"
        case .registrationFailed(let reason):
            return "Failed to register the font with the system: \(reason)"
        case .unsupportedFormat:
            return "Only .ttf and .otf fonts are supported."
        }
    }
}

// MARK: - FontManager

/// @Observable, @MainActor-isolated manager for bundled (system) and
/// user-imported fonts.
///
/// On `initialize()`, scans the app's Documents/Fonts directory for
/// previously-imported fonts and registers them. `importFont(from:)`
/// copies a user-provided font URL into Documents/Fonts and registers
/// it for immediate use.
@Observable
@MainActor
final class FontManager {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "FontManager"
    )

    // MARK: - Shared

    /// Shared instance. `FontManager` is UI-bound so this is safe
    /// as a `@MainActor` singleton.
    static let shared = FontManager()

    // MARK: - Published State

    /// Names of all system (bundled) font families available to the app.
    ///
    /// Sourced from `UIFont.familyNames` and sorted alphabetically.
    private(set) var bundledFonts: [String] = []

    /// File URLs of user-imported custom fonts (in Documents/Fonts).
    private(set) var customFonts: [URL] = []

    /// PostScript names of registered custom fonts, keyed by URL.
    /// Used for the combined `availableFonts()` listing.
    private var customFontPostScriptNames: [URL: String] = [:]

    /// Whether `initialize()` has completed.
    private(set) var isInitialized: Bool = false

    // MARK: - Init

    private init() {}

    // MARK: - Initialization

    /// Load bundled system fonts and register any previously-imported custom fonts.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    func initialize() async {
        guard !isInitialized else { return }

        bundledFonts = UIFont.familyNames.sorted()
        await scanAndRegisterCustomFonts()

        isInitialized = true
    }

    // MARK: - Public: Fonts

    /// Combined list of all available font family / face names (bundled + custom).
    ///
    /// Sorted alphabetically. Custom fonts are listed by PostScript name if
    /// registration succeeded; otherwise they are omitted.
    func availableFonts() -> [String] {
        let customNames = Array(customFontPostScriptNames.values)
        return (bundledFonts + customNames).sorted()
    }

    // MARK: - Import

    /// Copy a user-provided font file into the app's Documents/Fonts directory
    /// and register it with Core Text.
    ///
    /// - Parameter url: The source font URL (typically from a document picker).
    /// - Throws: `FontManagerError` if copying or registration fails.
    func importFont(from url: URL) async throws {
        guard let ext = Self.normalizedExtension(for: url) else {
            throw FontManagerError.unsupportedFormat
        }

        // Acquire a security-scoped resource if the URL requires it.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsScope { url.stopAccessingSecurityScopedResource() }
        }

        let destinationDirectory = Self.customFontsDirectory
        try Self.ensureDirectoryExists(destinationDirectory)

        let destinationURL = Self.uniqueDestinationURL(
            in: destinationDirectory,
            preferredName: url.deletingPathExtension().lastPathComponent,
            extension: ext
        )

        // Copy the file off the main actor to avoid blocking UI.
        let source = url
        let dest = destinationURL
        try await Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.copyItem(at: source, to: dest)
            } catch {
                throw FontManagerError.copyFailed(underlying: error.localizedDescription)
            }
        }.value

        // Register the font with Core Text.
        let postScriptName = try Self.registerFont(at: destinationURL)

        // Update observable state on the main actor (we're already isolated).
        customFonts.append(destinationURL)
        customFontPostScriptNames[destinationURL] = postScriptName

        Self.logger.info(
            "Registered custom font: \(postScriptName, privacy: .public) at \(destinationURL.lastPathComponent, privacy: .public)"
        )
    }

    // MARK: - Directory

    /// Absolute URL of the Documents/Fonts directory.
    nonisolated static var customFontsDirectory: URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent("Fonts", isDirectory: true)
    }

    // MARK: - Private: Initial Scan

    private func scanAndRegisterCustomFonts() async {
        let dir = Self.customFontsDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return }

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            Self.logger.error(
                "Failed to scan custom fonts directory: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        for url in urls {
            guard Self.normalizedExtension(for: url) != nil else { continue }
            do {
                let psName = try Self.registerFont(at: url)
                customFonts.append(url)
                customFontPostScriptNames[url] = psName
            } catch {
                Self.logger.warning(
                    "Skipping unregistrable font \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Private: File Helpers

    nonisolated private static func ensureDirectoryExists(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true
                )
            } catch {
                throw FontManagerError.copyFailed(underlying: error.localizedDescription)
            }
        }
    }

    nonisolated private static func normalizedExtension(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "ttf": return "ttf"
        case "otf": return "otf"
        default:    return nil
        }
    }

    nonisolated private static func uniqueDestinationURL(
        in directory: URL,
        preferredName: String,
        extension ext: String
    ) -> URL {
        let base = preferredName.isEmpty ? "Imported" : preferredName
        let primary = directory.appendingPathComponent("\(base).\(ext)")
        if !FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }
        // Disambiguate collisions.
        for i in 2...999 {
            let candidate = directory.appendingPathComponent("\(base)-\(i).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        // Ultimate fallback — highly unlikely, but deterministic.
        return directory.appendingPathComponent("\(base)-\(UUID().uuidString).\(ext)")
    }

    // MARK: - Private: Registration

    /// Register a font at the given URL and return its PostScript name.
    nonisolated private static func registerFont(at url: URL) throws -> String {
        var unmanagedError: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(
            url as CFURL,
            .process,
            &unmanagedError
        )

        if !success {
            let message: String
            if let cfError = unmanagedError?.takeRetainedValue() {
                message = CFErrorCopyDescription(cfError) as String? ?? "Unknown Core Text error"
            } else {
                message = "Unknown Core Text error"
            }
            throw FontManagerError.registrationFailed(underlying: message)
        }

        // Extract the PostScript name from the font descriptors.
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let psName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
        else {
            throw FontManagerError.registrationFailed(underlying: "Failed to read font descriptors")
        }

        return psName
    }
}
