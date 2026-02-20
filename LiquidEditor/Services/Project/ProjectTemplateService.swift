// ProjectTemplateService.swift
// LiquidEditor
//
// Manage project templates: load built-in templates, save/load custom
// templates, and create new projects from template configurations.

import Foundation
import os

// MARK: - ProjectTemplateService

/// Service for managing project templates and creating projects from them.
///
/// Handles:
/// - Loading built-in templates (defined in `ProjectTemplate.builtIns`)
/// - Saving/loading/deleting custom user-created templates on disk
/// - Creating new `Project` instances with template-defined settings
///
/// Custom templates are stored as individual JSON files in the
/// `LiquidEditor/Templates/` directory under the app's Documents directory.
///
/// ## Usage
/// ```swift
/// let service = ProjectTemplateService()
/// let allTemplates = try await service.getAllTemplates()
/// let project = service.createFromTemplate(
///     template: .tiktokReels,
///     projectName: "My Video",
///     sourceVideoPath: "Videos/clip.mp4",
///     durationMicros: 10_000_000
/// )
/// ```
///
/// Thread safety: This service uses `actor` isolation for safe concurrent
/// access to the templates directory.
actor ProjectTemplateService {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "ProjectTemplateService"
    )

    // MARK: - Constants

    private static let templatesSubpath = "LiquidEditor/Templates"

    // MARK: - State

    /// Lazily resolved templates directory URL.
    private var templatesDirectory: URL?

    // MARK: - JSON Coders

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Initialization

    /// Create a template service using the default Documents directory.
    init() {}

    /// Create a template service with a custom base directory (for testing).
    ///
    /// - Parameter baseDirectory: The directory to use for storing custom templates.
    init(baseDirectory: URL) {
        self.templatesDirectory = baseDirectory
    }

    // MARK: - Public API

    /// Get all available templates (built-in + custom).
    ///
    /// Built-in templates are listed first, followed by custom templates
    /// sorted by creation date (newest first).
    ///
    /// - Returns: Array of all templates.
    func getAllTemplates() async throws -> [ProjectTemplate] {
        let builtIn = ProjectTemplate.builtIns
        let custom = try await getCustomTemplates()
        return builtIn + custom
    }

    /// Get built-in templates only.
    var builtInTemplates: [ProjectTemplate] {
        ProjectTemplate.builtIns
    }

    /// Get custom user-created templates.
    ///
    /// Reads all `.json` files from the templates directory. Malformed
    /// files are silently skipped.
    ///
    /// - Returns: Array of custom templates, sorted by creation date (newest first).
    func getCustomTemplates() async throws -> [ProjectTemplate] {
        let dir = try resolveTemplatesDirectory()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: dir.path) else {
            return []
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw RepositoryError.ioError(
                "Failed to list templates directory: \(error.localizedDescription)"
            )
        }

        var templates: [ProjectTemplate] = []
        for url in contents where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                let template = try decoder.decode(ProjectTemplate.self, from: data)
                templates.append(template)
            } catch {
                // Skip malformed template files.
                Self.logger.warning("Skipping malformed template: \(url.lastPathComponent)")
                continue
            }
        }

        // Sort by creation date, newest first.
        templates.sort { $0.createdAt > $1.createdAt }
        return templates
    }

    /// Save current project settings as a new custom template.
    ///
    /// - Parameters:
    ///   - project: The project whose settings to capture.
    ///   - templateName: Display name for the template.
    ///   - description: Description of what the template is for.
    /// - Returns: The newly created template.
    func saveAsTemplate(
        project: Project,
        templateName: String,
        description: String
    ) async throws -> ProjectTemplate {
        let template = ProjectTemplate(
            id: UUID().uuidString.lowercased(),
            name: templateName,
            description: description,
            category: .custom,
            isBuiltIn: false,
            frameRate: project.frameRate,
            iconSymbol: "bookmark.fill",
            createdAt: Date()
        )

        let dir = try resolveTemplatesDirectory()
        try ensureDirectory(at: dir)

        let fileURL = dir.appendingPathComponent("\(template.id).json")

        let data: Data
        do {
            data = try encoder.encode(template)
        } catch {
            throw RepositoryError.encodingFailed(
                "Failed to encode template '\(templateName)': \(error.localizedDescription)"
            )
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw RepositoryError.ioError(
                "Failed to write template '\(templateName)': \(error.localizedDescription)"
            )
        }

        Self.logger.info("Saved custom template '\(templateName)' (id: \(template.id))")
        return template
    }

    /// Delete a custom template.
    ///
    /// Built-in templates (with IDs starting with "builtin-") cannot be deleted.
    ///
    /// - Parameter templateId: The template's unique identifier.
    func deleteTemplate(id templateId: String) async throws {
        // Prevent deletion of built-in templates.
        guard !templateId.hasPrefix("builtin-") else { return }

        let dir = try resolveTemplatesDirectory()
        let fileURL = dir.appendingPathComponent("\(templateId).json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw RepositoryError.ioError(
                "Failed to delete template \(templateId): \(error.localizedDescription)"
            )
        }

        Self.logger.info("Deleted custom template (id: \(templateId))")
    }

    /// Create a new project from a template.
    ///
    /// The project is created with the template's settings applied.
    /// Media is added separately via import.
    ///
    /// - Parameters:
    ///   - template: The template to use.
    ///   - projectName: Display name for the new project.
    ///   - sourceVideoPath: Relative path to the source video file.
    ///   - durationMicros: Duration of the source video in microseconds.
    /// - Returns: A new `Project` with template settings applied.
    nonisolated func createFromTemplate(
        template: ProjectTemplate,
        projectName: String,
        sourceVideoPath: String,
        durationMicros: Int64
    ) -> Project {
        let now = Date()
        return Project(
            id: UUID().uuidString.lowercased(),
            name: projectName,
            sourceVideoPath: sourceVideoPath,
            frameRate: template.frameRate,
            durationMicros: durationMicros,
            createdAt: now,
            modifiedAt: now
        )
    }

    /// Get templates grouped by category.
    ///
    /// - Returns: Dictionary mapping each category to its templates.
    func getTemplatesGrouped() async throws -> [TemplateCategory: [ProjectTemplate]] {
        let all = try await getAllTemplates()
        var grouped: [TemplateCategory: [ProjectTemplate]] = [:]

        for template in all {
            grouped[template.category, default: []].append(template)
        }

        return grouped
    }

    /// Clear cached directory path (for testing).
    func clearCache() {
        templatesDirectory = nil
    }

    // MARK: - Private Helpers

    /// Resolve the templates directory URL, creating it lazily.
    private func resolveTemplatesDirectory() throws -> URL {
        if let dir = templatesDirectory {
            return dir
        }

        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw RepositoryError.ioError("Unable to locate Documents directory")
        }

        let dir = documentsURL.appendingPathComponent(Self.templatesSubpath)
        templatesDirectory = dir
        return dir
    }

    /// Ensure a directory exists, creating it if needed.
    private func ensureDirectory(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true
                )
            } catch {
                throw RepositoryError.ioError(
                    "Failed to create directory at \(url.path): \(error.localizedDescription)"
                )
            }
        }
    }
}
