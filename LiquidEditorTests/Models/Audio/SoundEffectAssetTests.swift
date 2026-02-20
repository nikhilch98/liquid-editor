import Testing
import Foundation
@testable import LiquidEditor

// MARK: - SFXCategory Tests

@Suite("SFXCategory Tests")
struct SFXCategoryTests {

    @Test("all cases have display names")
    func displayNames() {
        #expect(SFXCategory.transitions.displayName == "Transitions")
        #expect(SFXCategory.ui.displayName == "UI")
        #expect(SFXCategory.impacts.displayName == "Impacts")
        #expect(SFXCategory.nature.displayName == "Nature")
        #expect(SFXCategory.ambience.displayName == "Ambience")
        #expect(SFXCategory.musical.displayName == "Musical")
        #expect(SFXCategory.foley.displayName == "Foley")
    }

    @Test("all cases have SF Symbol names")
    func sfSymbolNames() {
        for category in SFXCategory.allCases {
            #expect(!category.sfSymbolName.isEmpty)
        }
    }

    @Test("CaseIterable has all 7 cases")
    func allCases() {
        #expect(SFXCategory.allCases.count == 7)
    }

    @Test("Codable round-trip for all cases")
    func codableRoundTrip() throws {
        for category in SFXCategory.allCases {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(SFXCategory.self, from: data)
            #expect(decoded == category)
        }
    }
}

// MARK: - SoundEffectAsset Tests

@Suite("SoundEffectAsset Tests")
struct SoundEffectAssetTests {

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let asset = SoundEffectAsset(
            id: "sfx-1",
            name: "Whoosh",
            category: .transitions,
            durationMicros: 500_000,
            assetPath: "sfx/whoosh.wav"
        )
        #expect(asset.id == "sfx-1")
        #expect(asset.name == "Whoosh")
        #expect(asset.category == .transitions)
        #expect(asset.durationMicros == 500_000)
        #expect(asset.assetPath == "sfx/whoosh.wav")
        #expect(asset.tags.isEmpty)
    }

    @Test("creation with tags")
    func creationWithTags() {
        let asset = SoundEffectAsset(
            id: "sfx-2",
            name: "Thunder",
            category: .nature,
            durationMicros: 2_000_000,
            assetPath: "sfx/thunder.wav",
            tags: ["weather", "storm", "dramatic"]
        )
        #expect(asset.tags.count == 3)
        #expect(asset.tags.contains("weather"))
    }

    // MARK: - Computed Properties

    @Test("durationSeconds calculates correctly")
    func durationSeconds() {
        let asset = SoundEffectAsset(
            id: "sfx-1", name: "Test", category: .ui,
            durationMicros: 1_500_000, assetPath: "test.wav"
        )
        #expect(abs(asset.durationSeconds - 1.5) < 0.001)
    }

    // MARK: - matchesSearch

    @Test("matchesSearch returns true for empty query")
    func matchesSearchEmpty() {
        let asset = SoundEffectAsset(
            id: "sfx-1", name: "Click", category: .ui,
            durationMicros: 100_000, assetPath: "click.wav"
        )
        #expect(asset.matchesSearch("") == true)
    }

    @Test("matchesSearch matches name case-insensitive")
    func matchesSearchName() {
        let asset = SoundEffectAsset(
            id: "sfx-1", name: "Thunder Crack", category: .nature,
            durationMicros: 1_000_000, assetPath: "thunder.wav"
        )
        #expect(asset.matchesSearch("thunder") == true)
        #expect(asset.matchesSearch("THUNDER") == true)
        #expect(asset.matchesSearch("crack") == true)
    }

    @Test("matchesSearch matches tags case-insensitive")
    func matchesSearchTags() {
        let asset = SoundEffectAsset(
            id: "sfx-1", name: "Boom", category: .impacts,
            durationMicros: 500_000, assetPath: "boom.wav",
            tags: ["explosion", "dramatic"]
        )
        #expect(asset.matchesSearch("explosion") == true)
        #expect(asset.matchesSearch("DRAMATIC") == true)
        #expect(asset.matchesSearch("silent") == false)
    }

    @Test("matchesSearch returns false for non-matching query")
    func matchesSearchNoMatch() {
        let asset = SoundEffectAsset(
            id: "sfx-1", name: "Click", category: .ui,
            durationMicros: 100_000, assetPath: "click.wav",
            tags: ["button", "ui"]
        )
        #expect(asset.matchesSearch("thunder") == false)
    }

    // MARK: - Equatable / Hashable (by ID)

    @Test("assets with same ID are equal")
    func equalityById() {
        let a = SoundEffectAsset(id: "sfx-1", name: "A", category: .ui, durationMicros: 100, assetPath: "a.wav")
        let b = SoundEffectAsset(id: "sfx-1", name: "B", category: .nature, durationMicros: 200, assetPath: "b.wav")
        #expect(a == b)
    }

    @Test("assets with different IDs are not equal")
    func inequalityById() {
        let a = SoundEffectAsset(id: "sfx-1", name: "A", category: .ui, durationMicros: 100, assetPath: "a.wav")
        let b = SoundEffectAsset(id: "sfx-2", name: "A", category: .ui, durationMicros: 100, assetPath: "a.wav")
        #expect(a != b)
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = SoundEffectAsset(
            id: "sfx-test",
            name: "Test SFX",
            category: .foley,
            durationMicros: 750_000,
            assetPath: "sfx/test.wav",
            tags: ["test", "foley"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SoundEffectAsset.self, from: data)
        #expect(decoded == original)
        #expect(decoded.name == "Test SFX")
        #expect(decoded.category == .foley)
        #expect(decoded.tags == ["test", "foley"])
    }
}
