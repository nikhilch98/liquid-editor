import Testing
import Foundation
@testable import LiquidEditor

@Suite("FilterPresetService Tests")
struct FilterPresetServiceTests {

    // MARK: - Initialization

    @Test("Initialize loads built-in presets")
    @MainActor func initializeLoadsBuiltins() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        #expect(service.isLoaded)
        #expect(!service.presets.isEmpty)
        #expect(service.builtinPresets.count == BuiltinPresets.all.count)
    }

    @Test("Initialize is idempotent")
    @MainActor func initializeIdempotent() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()
        let count = service.presets.count

        await service.initialize()
        #expect(service.presets.count == count)
    }

    // MARK: - Built-in Presets

    @Test("Built-in presets include all 15 standard presets")
    @MainActor func builtinPresetsCount() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        #expect(service.builtinPresets.count == 15)
    }

    @Test("Built-in presets have correct source")
    @MainActor func builtinPresetsSource() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        for preset in service.builtinPresets {
            #expect(preset.isBuiltin)
            #expect(!preset.isUser)
        }
    }

    @Test("Categories include expected values")
    @MainActor func categoriesPresent() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        let categories = service.categories
        #expect(categories.contains("enhance"))
        #expect(categories.contains("tone"))
        #expect(categories.contains("bw"))
        #expect(categories.contains("cinematic"))
    }

    // MARK: - Custom Preset CRUD

    @Test("Save and retrieve a custom preset")
    @MainActor func savePreset() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()
        let initialCount = service.presets.count

        let grade = makeGrade(contrast: 0.5)
        let preset = await service.savePreset(
            name: "My Preset",
            grade: grade,
            description: "Test description",
            category: "custom"
        )

        #expect(service.presets.count == initialCount + 1)
        #expect(preset.name == "My Preset")
        #expect(preset.description == "Test description")
        #expect(preset.source == .user)
        #expect(preset.category == "custom")
        #expect(preset.grade.contrast == 0.5)

        // Retrieve by ID
        let found = service.getById(preset.id)
        #expect(found != nil)
        #expect(found?.name == "My Preset")
    }

    @Test("Delete a custom preset")
    @MainActor func deletePreset() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        let preset = await service.savePreset(
            name: "Delete Me",
            grade: makeGrade()
        )
        let countAfterAdd = service.presets.count

        await service.deletePreset(preset.id)

        #expect(service.presets.count == countAfterAdd - 1)
        #expect(service.getById(preset.id) == nil)
    }

    @Test("Delete built-in preset is no-op")
    @MainActor func deleteBuiltinNoOp() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        let builtinId = service.builtinPresets.first!.id
        let count = service.presets.count

        await service.deletePreset(builtinId)

        #expect(service.presets.count == count)
    }

    @Test("Update a custom preset")
    @MainActor func updatePreset() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        let preset = await service.savePreset(
            name: "Original Name",
            grade: makeGrade()
        )

        let updated = preset.with(name: "Updated Name")
        await service.updatePreset(updated)

        let found = service.getById(preset.id)
        #expect(found?.name == "Updated Name")
    }

    @Test("Update built-in preset is no-op")
    @MainActor func updateBuiltinNoOp() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        let builtin = service.builtinPresets.first!
        let updatedBuiltin = builtin.with(name: "Hacked Name", source: .builtin)
        await service.updatePreset(updatedBuiltin)

        let found = service.getById(builtin.id)
        #expect(found?.name == builtin.name)
    }

    // MARK: - Filtering

    @Test("Filter by category returns correct subset")
    @MainActor func filterByCategory() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        let bwPresets = service.presetsForCategory("bw")
        #expect(!bwPresets.isEmpty)
        for preset in bwPresets {
            #expect(preset.category == "bw")
        }
    }

    @Test("Filter by nil category returns all")
    @MainActor func filterByNilCategory() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        let all = service.presetsForCategory(nil)
        #expect(all.count == service.presets.count)
    }

    @Test("User presets list filters correctly")
    @MainActor func userPresetsList() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        #expect(service.userPresets.isEmpty)

        _ = await service.savePreset(name: "Custom1", grade: makeGrade())
        _ = await service.savePreset(name: "Custom2", grade: makeGrade())

        #expect(service.userPresets.count == 2)
    }

    // MARK: - Lookup

    @Test("getById returns nil for non-existent ID")
    @MainActor func getByIdMissing() async {
        let (service, tempDir) = makeIsolatedService()
        defer { cleanup(tempDir) }
        await service.initialize()

        #expect(service.getById("non_existent_id") == nil)
    }

    // MARK: - Helpers

    /// Create a service with an isolated temporary storage directory.
    @MainActor
    private func makeIsolatedService() -> (FilterPresetService, String) {
        let tempDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("FilterPresetServiceTests-\(UUID().uuidString)")
        return (FilterPresetService(storageDirectory: tempDir), tempDir)
    }

    /// Remove the temporary directory after test completes.
    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeGrade(
        contrast: Double = 0.0,
        saturation: Double = 0.0
    ) -> ColorGrade {
        let now = Date()
        return ColorGrade(
            id: UUID().uuidString,
            contrast: contrast,
            saturation: saturation,
            createdAt: now,
            modifiedAt: now
        )
    }
}
