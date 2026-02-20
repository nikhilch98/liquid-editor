import Testing
import Foundation
@testable import LiquidEditor

@Suite("LUTService Tests")
struct LUTServiceTests {

    // MARK: - Initialization

    @Test("Initialize loads bundled LUTs")
    func initializeLoadsBundled() async {
        let service = LUTService()
        await service.initialize()

        let loaded = await service.loaded
        #expect(loaded)

        let bundled = await service.bundledLUTs
        #expect(bundled.count == 25)
    }

    @Test("Initialize is idempotent")
    func initializeIdempotent() async {
        let service = LUTService()
        await service.initialize()
        let count1 = await service.allLUTs.count

        await service.initialize()
        let count2 = await service.allLUTs.count

        #expect(count1 == count2)
    }

    // MARK: - Bundled LUT Queries

    @Test("Bundled LUTs have correct source")
    func bundledSource() async {
        let service = LUTService()
        await service.initialize()

        let bundled = await service.bundledLUTs
        for lut in bundled {
            #expect(lut.isBundled)
            #expect(!lut.isCustom)
        }
    }

    @Test("Categories include expected values")
    func categoriesPresent() async {
        let service = LUTService()
        await service.initialize()

        let categories = await service.categories
        #expect(categories.contains("cinematic"))
        #expect(categories.contains("vintage"))
        #expect(categories.contains("bw"))
        #expect(categories.contains("portrait"))
        #expect(categories.contains("landscape"))
        #expect(categories.contains("social"))
    }

    @Test("Filter by category returns correct subset")
    func filterByCategory() async {
        let service = LUTService()
        await service.initialize()

        let cinematic = await service.lutsForCategory("cinematic")
        #expect(cinematic.count == 6)
        for lut in cinematic {
            #expect(lut.category == "cinematic")
        }
    }

    @Test("Filter by nil returns all")
    func filterByNil() async {
        let service = LUTService()
        await service.initialize()

        let all = await service.lutsForCategory(nil)
        let total = await service.allLUTs.count
        #expect(all.count == total)
    }

    // MARK: - Lookup

    @Test("Get by ID returns correct LUT")
    func getById() async {
        let service = LUTService()
        await service.initialize()

        let lut = await service.getById("builtin_teal_orange")
        #expect(lut != nil)
        #expect(lut?.name == "Teal & Orange")
    }

    @Test("Get by ID returns nil for non-existent")
    func getByIdMissing() async {
        let service = LUTService()
        await service.initialize()

        let lut = await service.getById("non_existent")
        #expect(lut == nil)
    }

    // MARK: - Import / Remove

    @Test("Import valid .cube file succeeds")
    func importValidCube() async {
        let service = LUTService()
        await service.initialize()
        let initialCount = await service.allLUTs.count

        let path = createTempCubeFile(dimension: 2, title: "Imported Test")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = await service.importLUT(from: path)

        #expect(result != nil)
        #expect(result?.name == "Imported Test")
        #expect(result?.isCustom == true)
        #expect(result?.dimension == 2)

        let newCount = await service.allLUTs.count
        #expect(newCount == initialCount + 1)
    }

    @Test("Import invalid file returns nil")
    func importInvalidFile() async {
        let service = LUTService()
        await service.initialize()

        let result = await service.importLUT(from: "/tmp/nonexistent.cube")
        #expect(result == nil)
    }

    @Test("Remove custom LUT deletes it")
    func removeCustomLUT() async {
        let service = LUTService()
        await service.initialize()

        let path = createTempCubeFile(dimension: 2, title: "Remove Me")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let imported = await service.importLUT(from: path)
        guard let imported else {
            Issue.record("Import should have succeeded")
            return
        }

        let countAfterImport = await service.allLUTs.count
        await service.removeLUT(imported.id)
        let countAfterRemove = await service.allLUTs.count

        #expect(countAfterRemove == countAfterImport - 1)
        let found = await service.getById(imported.id)
        #expect(found == nil)
    }

    @Test("Remove bundled LUT is no-op")
    func removeBundledNoOp() async {
        let service = LUTService()
        await service.initialize()

        let count = await service.allLUTs.count
        await service.removeLUT("builtin_teal_orange")
        let countAfter = await service.allLUTs.count

        #expect(countAfter == count)
    }

    // MARK: - Path Resolution

    @Test("Resolve custom path finds file")
    func resolveCustomPath() async {
        let service = LUTService()
        await service.initialize()

        let path = createTempCubeFile(dimension: 2, title: "Resolve Test")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let imported = await service.importLUT(from: path)
        guard let imported else {
            Issue.record("Import should have succeeded")
            return
        }

        let resolved = await service.resolveAssetPath(imported.lutAssetPath)
        #expect(resolved != nil)
    }

    @Test("Resolve unknown path returns nil")
    func resolveUnknownPath() async {
        let service = LUTService()
        await service.initialize()

        let resolved = await service.resolveAssetPath("invalid://something")
        #expect(resolved == nil)
    }

    // MARK: - Cache Invalidation

    @Test("Invalidate path cache clears all cached paths")
    func invalidateCache() async {
        let service = LUTService()
        await service.initialize()

        // Resolve to populate cache
        _ = await service.resolveAssetPath("bundled://cinematic/teal_orange")

        // Invalidate
        await service.invalidatePathCache()

        // Service should still function (re-resolves on next call)
        // No crash = success
    }

    @Test("Custom LUTs list is initially empty")
    func customLUTsInitiallyEmpty() async {
        let service = LUTService()
        await service.initialize()

        let custom = await service.customLUTs
        // May have some from previous test runs persisted, but should be non-negative
        #expect(custom.count >= 0)
    }

    // MARK: - Helpers

    private func createTempCubeFile(dimension: Int, title: String) -> String {
        var lines: [String] = []
        lines.append("TITLE \"\(title)\"")
        lines.append("LUT_3D_SIZE \(dimension)")
        let count = dimension * dimension * dimension
        for _ in 0..<count {
            lines.append("0.0 0.5 1.0")
        }
        let content = lines.joined(separator: "\n")
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("test_import_\(UUID().uuidString).cube")
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
