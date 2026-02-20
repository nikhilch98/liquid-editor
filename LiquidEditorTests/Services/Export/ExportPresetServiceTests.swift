import Testing
import Foundation
@testable import LiquidEditor

@Suite("ExportPresetService Tests")
struct ExportPresetServiceTests {

    // MARK: - Built-in Presets

    @Test("Built-in presets contains five standard presets")
    func builtInPresetsCount() {
        let presets = ExportPresetService.builtInPresets
        #expect(presets.count == 5)
    }

    @Test("Built-in presets are all marked as built-in")
    func builtInPresetsMarked() {
        for preset in ExportPresetService.builtInPresets {
            #expect(preset.isBuiltIn)
        }
    }

    @Test("Quick Share preset has correct config")
    func quickSharePreset() {
        let preset = ExportPresetService.builtInPresets.first { $0.id == "quick_share" }
        #expect(preset != nil)
        #expect(preset?.name == "Quick Share")
        #expect(preset?.config.resolution == .r720p)
        #expect(preset?.config.fps == 30)
        #expect(preset?.config.codec == .h264)
        #expect(preset?.config.format == .mp4)
        #expect(preset?.config.quality == .standard)
    }

    @Test("Standard preset has correct config")
    func standardPreset() {
        let preset = ExportPresetService.builtInPresets.first { $0.id == "standard" }
        #expect(preset != nil)
        #expect(preset?.config.resolution == .r1080p)
        #expect(preset?.config.codec == .h264)
        #expect(preset?.config.quality == .high)
        #expect(preset?.config.bitrateMbps == 20.0)
    }

    @Test("High Quality preset has 60fps HEVC")
    func highQualityPreset() {
        let preset = ExportPresetService.builtInPresets.first { $0.id == "high_quality" }
        #expect(preset != nil)
        #expect(preset?.config.fps == 60)
        #expect(preset?.config.codec == .h265)
        #expect(preset?.config.quality == .maximum)
    }

    @Test("4K preset has correct resolution and codec")
    func fourKPreset() {
        let preset = ExportPresetService.builtInPresets.first { $0.id == "4k" }
        #expect(preset != nil)
        #expect(preset?.config.resolution == .r4K)
        #expect(preset?.config.codec == .h265)
    }

    @Test("Audio Only preset is audio-only")
    func audioOnlyPreset() {
        let preset = ExportPresetService.builtInPresets.first { $0.id == "audio_only" }
        #expect(preset != nil)
        #expect(preset?.config.audioOnly == true)
        #expect(preset?.config.audioCodec == .aac)
        #expect(preset?.config.audioBitrate == 256)
    }

    @Test("All built-in presets have unique IDs")
    func builtInPresetsUniqueIds() {
        let ids = ExportPresetService.builtInPresets.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("All built-in presets have non-empty names and descriptions")
    func builtInPresetsMetadata() {
        for preset in ExportPresetService.builtInPresets {
            #expect(!preset.name.isEmpty)
            #expect(!preset.description.isEmpty)
            #expect(!preset.sfSymbolName.isEmpty)
        }
    }

    // MARK: - Social Presets

    @Test("Social presets are generated for all platforms")
    func socialPresetsCount() {
        let presets = ExportPresetService.socialPresets
        #expect(presets.count == SocialMediaPreset.allCases.count)
    }

    @Test("Social presets have correct ID prefix")
    func socialPresetsIdPrefix() {
        for preset in ExportPresetService.socialPresets {
            #expect(preset.id.hasPrefix("social_"))
        }
    }

    @Test("Social presets are all marked built-in")
    func socialPresetsBuiltIn() {
        for preset in ExportPresetService.socialPresets {
            #expect(preset.isBuiltIn)
        }
    }

    @Test("Instagram social preset has correct dimensions")
    func instagramPreset() {
        let preset = ExportPresetService.socialPresets.first { $0.id == "social_instagram" }
        #expect(preset != nil)
        #expect(preset?.config.customWidth == 1080)
        #expect(preset?.config.customHeight == 1920)
        #expect(preset?.config.fps == 30)
    }

    @Test("YouTube social preset has 4K dimensions")
    func youtubePreset() {
        let preset = ExportPresetService.socialPresets.first { $0.id == "social_youtube" }
        #expect(preset != nil)
        #expect(preset?.config.customWidth == 3840)
        #expect(preset?.config.customHeight == 2160)
        #expect(preset?.config.fps == 60)
    }

    // MARK: - All Presets

    @Test("allPresets combines built-in and social presets")
    func allPresetsCount() {
        let all = ExportPresetService.allPresets
        let expected = ExportPresetService.builtInPresets.count
            + ExportPresetService.socialPresets.count
        #expect(all.count == expected)
    }

    @Test("All presets have unique IDs")
    func allPresetsUniqueIds() {
        let ids = ExportPresetService.allPresets.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Lookup

    @Test("findById returns built-in preset")
    func findByIdBuiltIn() {
        let preset = ExportPresetService.findById("standard")
        #expect(preset != nil)
        #expect(preset?.name == "Standard")
    }

    @Test("findById returns social preset")
    func findByIdSocial() {
        let preset = ExportPresetService.findById("social_tiktok")
        #expect(preset != nil)
        #expect(preset?.name == "TikTok")
    }

    @Test("findById returns nil for non-existent ID")
    func findByIdMissing() {
        let preset = ExportPresetService.findById("non_existent_id")
        #expect(preset == nil)
    }

    // MARK: - Custom Preset CRUD

    @Test("Add and load custom preset roundtrip")
    func addAndLoadCustomPreset() {
        // Clean up first
        ExportPresetService.saveCustomPresets([])

        let custom = ExportPreset(
            id: "custom_test_\(UUID().uuidString)",
            name: "Test Custom",
            description: "Test description",
            sfSymbolName: "star",
            config: ExportConfig(resolution: .r720p, fps: 24, codec: .h264)
        )

        let result = ExportPresetService.addCustomPreset(custom)
        #expect(result.count == 1)
        #expect(result[0].name == "Test Custom")
        #expect(result[0].isBuiltIn == false) // forced to non-built-in

        let loaded = ExportPresetService.loadCustomPresets()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Test Custom")

        // Cleanup
        ExportPresetService.saveCustomPresets([])
    }

    @Test("Update custom preset modifies in place")
    func updateCustomPreset() {
        ExportPresetService.saveCustomPresets([])

        let custom = ExportPreset(
            id: "custom_update_test",
            name: "Before",
            description: "Desc",
            sfSymbolName: "star",
            config: ExportConfig()
        )
        ExportPresetService.addCustomPreset(custom)

        let updated = custom.with(name: "After")
        let result = ExportPresetService.updateCustomPreset(updated)

        #expect(result.first { $0.id == "custom_update_test" }?.name == "After")

        ExportPresetService.saveCustomPresets([])
    }

    @Test("Delete custom preset removes it")
    func deleteCustomPreset() {
        ExportPresetService.saveCustomPresets([])

        let custom = ExportPreset(
            id: "custom_delete_test",
            name: "Delete Me",
            description: "Desc",
            sfSymbolName: "trash",
            config: ExportConfig()
        )
        ExportPresetService.addCustomPreset(custom)
        #expect(ExportPresetService.loadCustomPresets().count == 1)

        let result = ExportPresetService.deleteCustomPreset("custom_delete_test")
        #expect(result.isEmpty)
        #expect(ExportPresetService.loadCustomPresets().isEmpty)
    }

    @Test("Delete built-in preset from custom list is no-op")
    func deleteBuiltInFromCustom() {
        ExportPresetService.saveCustomPresets([])

        // Add a preset marked as built-in
        let builtIn = ExportPreset(
            id: "fake_builtin",
            name: "Builtin",
            description: "Desc",
            sfSymbolName: "star",
            config: ExportConfig(),
            isBuiltIn: true
        )
        // Directly save to simulate it being in the list
        ExportPresetService.saveCustomPresets([builtIn])

        let result = ExportPresetService.deleteCustomPreset("fake_builtin")
        // Built-in presets cannot be deleted
        #expect(result.count == 1)

        ExportPresetService.saveCustomPresets([])
    }

    @Test("Update non-existent custom preset is no-op")
    func updateNonExistent() {
        ExportPresetService.saveCustomPresets([])

        let phantom = ExportPreset(
            id: "does_not_exist",
            name: "Ghost",
            description: "",
            sfSymbolName: "ghost",
            config: ExportConfig()
        )
        let result = ExportPresetService.updateCustomPreset(phantom)
        #expect(result.isEmpty)

        ExportPresetService.saveCustomPresets([])
    }

    @Test("Load custom presets from empty state returns empty array")
    func loadEmptyCustomPresets() {
        ExportPresetService.saveCustomPresets([])
        let presets = ExportPresetService.loadCustomPresets()
        #expect(presets.isEmpty)
    }

    // MARK: - ExportPreset Model

    @Test("ExportPreset.with creates copy with overrides")
    func presetWithOverrides() {
        let original = ExportPreset(
            id: "orig",
            name: "Original",
            description: "Desc",
            sfSymbolName: "star",
            config: ExportConfig()
        )
        let modified = original.with(name: "Modified", sfSymbolName: "heart")

        #expect(modified.id == "orig")
        #expect(modified.name == "Modified")
        #expect(modified.sfSymbolName == "heart")
        #expect(modified.description == "Desc")
    }

    @Test("ExportPreset equality is by ID")
    func presetEquality() {
        let a = ExportPreset(
            id: "same", name: "A", description: "", sfSymbolName: "a",
            config: ExportConfig()
        )
        let b = ExportPreset(
            id: "same", name: "B", description: "", sfSymbolName: "b",
            config: ExportConfig(fps: 60)
        )
        #expect(a == b)
    }

    @Test("ExportPreset hash is by ID")
    func presetHash() {
        let a = ExportPreset(
            id: "hash_test", name: "A", description: "", sfSymbolName: "a",
            config: ExportConfig()
        )
        let b = ExportPreset(
            id: "hash_test", name: "B", description: "", sfSymbolName: "b",
            config: ExportConfig()
        )
        #expect(a.hashValue == b.hashValue)
    }
}
