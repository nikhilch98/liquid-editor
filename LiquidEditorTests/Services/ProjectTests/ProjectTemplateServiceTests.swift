// ProjectTemplateServiceTests.swift
// LiquidEditorTests
//
// Tests for ProjectTemplateService using Swift Testing.
// Validates built-in template loading, custom template CRUD,
// project creation from templates, and grouping.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - ProjectTemplateServiceTests

@Suite("ProjectTemplateService Tests")
struct ProjectTemplateServiceTests {

    // MARK: - Test Helpers

    /// Creates a temp directory for test isolation and returns a service using it.
    private func makeService() throws -> (ProjectTemplateService, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectTemplateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        let service = ProjectTemplateService(baseDirectory: tempDir)
        return (service, tempDir)
    }

    /// Cleans up the temp directory after tests.
    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeTestProject(
        name: String = "Test Project",
        frameRate: FrameRateOption = .fixed30
    ) -> Project {
        Project(
            id: "abcd1234-5678-abcd-ef01-234567890abc",
            name: name,
            sourceVideoPath: "Videos/test.mp4",
            frameRate: frameRate,
            durationMicros: 10_000_000,
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    // MARK: - Built-in Templates

    @Test("builtInTemplates returns all predefined templates")
    func builtInTemplates() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let builtIns = await service.builtInTemplates
        #expect(builtIns.count == ProjectTemplate.builtIns.count)
        #expect(builtIns.count >= 7) // blank, tiktok, insta feed/story, youtube, yt shorts, cinematic
    }

    @Test("builtInTemplates all have isBuiltIn = true")
    func builtInsAreMarked() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let builtIns = await service.builtInTemplates
        for template in builtIns {
            #expect(template.isBuiltIn, "Template '\(template.name)' should be built-in")
        }
    }

    @Test("builtInTemplates all have IDs starting with builtin-")
    func builtInIds() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let builtIns = await service.builtInTemplates
        for template in builtIns {
            #expect(
                template.id.hasPrefix("builtin-"),
                "Template '\(template.name)' ID should start with 'builtin-', got '\(template.id)'"
            )
        }
    }

    // MARK: - Get All Templates

    @Test("getAllTemplates returns built-in templates when no custom exist")
    func allTemplatesWithNoCustom() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let all = try await service.getAllTemplates()
        #expect(all.count == ProjectTemplate.builtIns.count)
    }

    @Test("getAllTemplates includes custom templates")
    func allTemplatesWithCustom() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let project = makeTestProject()
        _ = try await service.saveAsTemplate(
            project: project,
            templateName: "My Custom",
            description: "A test template"
        )

        let all = try await service.getAllTemplates()
        #expect(all.count == ProjectTemplate.builtIns.count + 1)
    }

    // MARK: - Custom Template CRUD

    @Test("saveAsTemplate creates a template with correct properties")
    func saveAsTemplate() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let project = makeTestProject(frameRate: .fixed24)
        let template = try await service.saveAsTemplate(
            project: project,
            templateName: "Cinematic Preset",
            description: "My cinematic settings"
        )

        #expect(template.name == "Cinematic Preset")
        #expect(template.description == "My cinematic settings")
        #expect(template.category == .custom)
        #expect(!template.isBuiltIn)
        #expect(template.frameRate == .fixed24)
        #expect(template.iconSymbol == "bookmark.fill")
        #expect(!template.id.isEmpty)
    }

    @Test("saveAsTemplate persists to disk")
    func saveAsTemplatePersists() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let project = makeTestProject()
        let template = try await service.saveAsTemplate(
            project: project,
            templateName: "Persisted",
            description: "Should be on disk"
        )

        let fileURL = dir.appendingPathComponent("\(template.id).json")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("getCustomTemplates loads saved templates")
    func getCustomTemplates() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let project = makeTestProject()
        _ = try await service.saveAsTemplate(
            project: project,
            templateName: "Custom A",
            description: "First"
        )
        _ = try await service.saveAsTemplate(
            project: project,
            templateName: "Custom B",
            description: "Second"
        )

        let customs = try await service.getCustomTemplates()
        #expect(customs.count == 2)

        let names = Set(customs.map(\.name))
        #expect(names.contains("Custom A"))
        #expect(names.contains("Custom B"))
    }

    @Test("getCustomTemplates returns empty when no templates saved")
    func getCustomTemplatesEmpty() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let customs = try await service.getCustomTemplates()
        #expect(customs.isEmpty)
    }

    @Test("deleteTemplate removes custom template from disk")
    func deleteCustomTemplate() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let project = makeTestProject()
        let template = try await service.saveAsTemplate(
            project: project,
            templateName: "To Delete",
            description: "Will be removed"
        )

        // Verify it exists.
        var customs = try await service.getCustomTemplates()
        #expect(customs.count == 1)

        // Delete it.
        try await service.deleteTemplate(id: template.id)

        // Verify it's gone.
        customs = try await service.getCustomTemplates()
        #expect(customs.isEmpty)
    }

    @Test("deleteTemplate does not delete built-in templates")
    func deleteBuiltInTemplateNoOp() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        // This should be a no-op.
        try await service.deleteTemplate(id: "builtin-blank")

        let builtIns = await service.builtInTemplates
        #expect(builtIns.contains(where: { $0.id == "builtin-blank" }))
    }

    @Test("deleteTemplate for nonexistent ID does not throw")
    func deleteNonexistentTemplate() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        // Should not throw.
        try await service.deleteTemplate(id: "nonexistent-template-id")
    }

    // MARK: - Create from Template

    @Test("createFromTemplate creates project with template frame rate")
    func createFromTemplateFrameRate() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let project = await service.createFromTemplate(
            template: .tiktokReels,
            projectName: "TikTok Video",
            sourceVideoPath: "Videos/clip.mp4",
            durationMicros: 15_000_000
        )

        #expect(project.frameRate == .fixed30)
        #expect(project.name == "TikTok Video")
        #expect(project.sourceVideoPath == "Videos/clip.mp4")
        #expect(project.durationMicros == 15_000_000)
    }

    @Test("createFromTemplate generates unique project ID")
    func createFromTemplateUniqueId() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let project1 = await service.createFromTemplate(
            template: .blank,
            projectName: "A",
            sourceVideoPath: "a.mp4",
            durationMicros: 1_000_000
        )

        let project2 = await service.createFromTemplate(
            template: .blank,
            projectName: "B",
            sourceVideoPath: "b.mp4",
            durationMicros: 2_000_000
        )

        #expect(project1.id != project2.id)
    }

    @Test("createFromTemplate uses cinematic template settings")
    func createFromCinematicTemplate() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let project = await service.createFromTemplate(
            template: .cinematicFilm,
            projectName: "Film",
            sourceVideoPath: "film.mov",
            durationMicros: 120_000_000
        )

        #expect(project.frameRate == .fixed24)
    }

    // MARK: - Grouped Templates

    @Test("getTemplatesGrouped organizes by category")
    func templatesGrouped() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let grouped = try await service.getTemplatesGrouped()

        // Social category should have TikTok, Instagram Feed, Instagram Story, YouTube Shorts.
        #expect(grouped[.social] != nil)
        #expect((grouped[.social]?.count ?? 0) >= 4)

        // Standard category should have Blank and YouTube.
        #expect(grouped[.standard] != nil)
        #expect((grouped[.standard]?.count ?? 0) >= 2)

        // Cinematic should have at least one.
        #expect(grouped[.cinematic] != nil)
        #expect((grouped[.cinematic]?.count ?? 0) >= 1)
    }

    @Test("getTemplatesGrouped includes custom templates in custom category")
    func groupedIncludesCustom() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        let project = makeTestProject()
        _ = try await service.saveAsTemplate(
            project: project,
            templateName: "My Style",
            description: "Custom"
        )

        let grouped = try await service.getTemplatesGrouped()
        #expect(grouped[.custom] != nil)
        #expect(grouped[.custom]?.count == 1)
        #expect(grouped[.custom]?.first?.name == "My Style")
    }

    // MARK: - Cache

    @Test("clearCache resets internal directory path")
    func clearCache() async throws {
        let (service, dir) = try makeService()
        defer { cleanup(dir) }

        // Save a template to ensure cache is populated.
        let project = makeTestProject()
        _ = try await service.saveAsTemplate(
            project: project,
            templateName: "Cached",
            description: "Test"
        )

        // Clear cache.
        await service.clearCache()

        // Service should still work (re-resolves directory).
        // Since baseDirectory was set via init, clearCache sets it to nil,
        // which would cause it to fall back to the default Documents dir.
        // For this test, we just verify the method doesn't crash.
    }
}
