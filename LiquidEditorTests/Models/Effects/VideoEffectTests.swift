import Testing
import Foundation
@testable import LiquidEditor

@Suite("VideoEffect Tests")
struct VideoEffectTests {

    // MARK: - Helpers

    /// Create a simple blur effect for testing.
    private func makeBlurEffect(
        id: String = "fx1",
        isEnabled: Bool = true,
        mix: Double = 1.0
    ) -> VideoEffect {
        VideoEffect(
            id: id,
            type: .blur,
            isEnabled: isEnabled,
            mix: mix,
            parameters: EffectRegistry.defaultParameters(.blur)
        )
    }

    /// Create a vignette effect for testing.
    private func makeVignetteEffect(id: String = "fx2") -> VideoEffect {
        VideoEffect(
            id: id,
            type: .vignette,
            parameters: EffectRegistry.defaultParameters(.vignette)
        )
    }

    // MARK: - Creation

    @Test("VideoEffect creation with parameters")
    func creation() {
        let effect = makeBlurEffect()
        #expect(effect.id == "fx1")
        #expect(effect.type == .blur)
        #expect(effect.isEnabled == true)
        #expect(effect.mix == 1.0)
        #expect(!effect.parameters.isEmpty)
    }

    @Test("VideoEffect.create uses registry defaults")
    func createFromType() {
        let effect = VideoEffect.create(.vignette)
        #expect(effect.type == .vignette)
        #expect(effect.isEnabled == true)
        #expect(effect.mix == 1.0)
        #expect(!effect.id.isEmpty)
        #expect(effect.parameters["intensity"] != nil)
    }

    @Test("Display name comes from effect type")
    func displayName() {
        let effect = makeBlurEffect()
        #expect(effect.displayName == "Blur")
    }

    @Test("Category comes from effect type")
    func category() {
        let effect = makeBlurEffect()
        #expect(effect.category == .blur)
    }

    @Test("sfSymbol comes from effect type")
    func sfSymbol() {
        let effect = makeBlurEffect()
        #expect(!effect.sfSymbol.isEmpty)
    }

    // MARK: - Parameters

    @Test("getParameterValue returns current value")
    func getParameter() {
        let effect = makeBlurEffect()
        let value = effect.getParameterValue("radius")
        #expect(value?.asDouble == 10.0) // Default
    }

    @Test("getParameterValue returns nil for unknown param")
    func getUnknownParameter() {
        let effect = makeBlurEffect()
        #expect(effect.getParameterValue("nonexistent") == nil)
    }

    @Test("updateParameter changes value")
    func updateParameter() {
        let effect = makeBlurEffect()
        let updated = effect.updateParameter("radius", value: .double_(25.0))
        #expect(updated.getParameterValue("radius")?.asDouble == 25.0)
        #expect(updated.id == effect.id) // Same id
    }

    @Test("updateParameter clamps to valid range")
    func updateParameterClamped() {
        let effect = makeBlurEffect()
        let updated = effect.updateParameter("radius", value: .double_(200.0))
        // Should clamp to maxValue of 100
        #expect(updated.getParameterValue("radius")?.asDouble == 100.0)
    }

    @Test("updateParameter for unknown param returns self")
    func updateUnknownParameter() {
        let effect = makeBlurEffect()
        let updated = effect.updateParameter("nonexistent", value: .double_(5.0))
        #expect(updated == effect)
    }

    @Test("resetParameter restores default")
    func resetParameter() {
        let effect = makeBlurEffect()
            .updateParameter("radius", value: .double_(50.0))
        let reset = effect.resetParameter("radius")
        #expect(reset.getParameterValue("radius")?.asDouble == 10.0) // Back to default
    }

    @Test("resetAllParameters restores all defaults and clears keyframes")
    func resetAllParameters() {
        let effect = makeBlurEffect()
            .updateParameter("radius", value: .double_(50.0))
            .addKeyframe("radius", keyframe: EffectKeyframe(
                id: "kf1",
                timestampMicros: 500_000,
                value: .double_(20.0)
            ))
        let reset = effect.resetAllParameters()
        #expect(reset.getParameterValue("radius")?.asDouble == 10.0)
        #expect(reset.hasKeyframes == false)
    }

    @Test("resolvedParameters returns all parameters")
    func resolvedParameters() {
        let effect = makeBlurEffect()
        let params = effect.resolvedParameters()
        #expect(params["radius"] != nil)
    }

    // MARK: - Keyframes

    @Test("hasKeyframes is false by default")
    func noKeyframes() {
        let effect = makeBlurEffect()
        #expect(effect.hasKeyframes == false)
        #expect(effect.totalKeyframeCount == 0)
    }

    @Test("addKeyframe adds to track")
    func addKeyframe() {
        let effect = makeBlurEffect()
        let kf = EffectKeyframe(
            id: "kf1",
            timestampMicros: 500_000,
            value: .double_(20.0)
        )
        let updated = effect.addKeyframe("radius", keyframe: kf)
        #expect(updated.hasKeyframes == true)
        #expect(updated.totalKeyframeCount == 1)
    }

    @Test("addKeyframe keeps track sorted by timestamp")
    func addKeyframeSorted() {
        let effect = makeBlurEffect()
        let kf1 = EffectKeyframe(id: "kf1", timestampMicros: 1_000_000, value: .double_(20.0))
        let kf2 = EffectKeyframe(id: "kf2", timestampMicros: 500_000, value: .double_(10.0))
        let updated = effect.addKeyframe("radius", keyframe: kf1)
            .addKeyframe("radius", keyframe: kf2)
        let track = updated.keyframeTracks["radius"]!
        #expect(track[0].timestampMicros == 500_000) // kf2 first
        #expect(track[1].timestampMicros == 1_000_000) // kf1 second
    }

    @Test("removeKeyframe removes from track")
    func removeKeyframe() {
        let effect = makeBlurEffect()
        let kf = EffectKeyframe(id: "kf1", timestampMicros: 500_000, value: .double_(20.0))
        let updated = effect.addKeyframe("radius", keyframe: kf)
            .removeKeyframe("radius", keyframeId: "kf1")
        #expect(updated.hasKeyframes == false)
    }

    @Test("removeKeyframe cleans up empty tracks")
    func removeLastKeyframe() {
        let effect = makeBlurEffect()
        let kf = EffectKeyframe(id: "kf1", timestampMicros: 500_000, value: .double_(20.0))
        let updated = effect.addKeyframe("radius", keyframe: kf)
            .removeKeyframe("radius", keyframeId: "kf1")
        #expect(updated.keyframeTracks["radius"] == nil) // Key removed entirely
    }

    @Test("updateKeyframe modifies existing keyframe")
    func updateKeyframe() {
        let effect = makeBlurEffect()
        let kf = EffectKeyframe(id: "kf1", timestampMicros: 500_000, value: .double_(20.0))
        let updatedKf = kf.with(value: .double_(30.0))
        let updated = effect.addKeyframe("radius", keyframe: kf)
            .updateKeyframe("radius", keyframe: updatedKf)
        let track = updated.keyframeTracks["radius"]!
        #expect(track[0].value.asDouble == 30.0)
    }

    @Test("clearKeyframes removes all keyframes for a parameter")
    func clearKeyframes() {
        let effect = makeBlurEffect()
        let kf1 = EffectKeyframe(id: "kf1", timestampMicros: 500_000, value: .double_(20.0))
        let kf2 = EffectKeyframe(id: "kf2", timestampMicros: 1_000_000, value: .double_(30.0))
        let updated = effect
            .addKeyframe("radius", keyframe: kf1)
            .addKeyframe("radius", keyframe: kf2)
            .clearKeyframes("radius")
        #expect(updated.hasKeyframes == false)
    }

    @Test("clearAllKeyframes removes all tracks")
    func clearAllKeyframes() {
        let effect = VideoEffect(
            id: "fx1",
            type: .vignette,
            parameters: EffectRegistry.defaultParameters(.vignette)
        )
        let updated = effect
            .addKeyframe("intensity", keyframe: EffectKeyframe(
                id: "kf1", timestampMicros: 0, value: .double_(0.0)
            ))
            .addKeyframe("radius", keyframe: EffectKeyframe(
                id: "kf2", timestampMicros: 0, value: .double_(1.0)
            ))
            .clearAllKeyframes()
        #expect(updated.hasKeyframes == false)
        #expect(updated.totalKeyframeCount == 0)
    }

    @Test("partitionKeyframes splits at offset")
    func partitionKeyframes() {
        let effect = makeBlurEffect()
        let kf1 = EffectKeyframe(id: "kf1", timestampMicros: 300_000, value: .double_(10.0))
        let kf2 = EffectKeyframe(id: "kf2", timestampMicros: 700_000, value: .double_(30.0))
        let kf3 = EffectKeyframe(id: "kf3", timestampMicros: 1_000_000, value: .double_(50.0))
        let withKfs = effect
            .addKeyframe("radius", keyframe: kf1)
            .addKeyframe("radius", keyframe: kf2)
            .addKeyframe("radius", keyframe: kf3)

        let (left, right) = withKfs.partitionKeyframes(500_000)
        #expect(left["radius"]?.count == 1) // kf1 only (< 500_000)
        #expect(right["radius"]?.count == 2) // kf2 and kf3 (>= 500_000)
        // Right timestamps are adjusted by subtracting offset
        #expect(right["radius"]?[0].timestampMicros == 200_000) // 700_000 - 500_000
        #expect(right["radius"]?[1].timestampMicros == 500_000) // 1_000_000 - 500_000
    }

    // MARK: - with() Copy Method

    @Test("with() creates copy preserving unchanged fields")
    func withPreservesFields() {
        let effect = makeBlurEffect()
        let copy = effect.with(isEnabled: false)
        #expect(copy.isEnabled == false)
        #expect(copy.id == "fx1")
        #expect(copy.type == .blur)
        #expect(copy.mix == 1.0)
    }

    @Test("with() can change mix")
    func withMix() {
        let effect = makeBlurEffect()
        let copy = effect.with(mix: 0.5)
        #expect(copy.mix == 0.5)
    }

    @Test("with() can change multiple fields")
    func withMultiple() {
        let effect = makeBlurEffect()
        let copy = effect.with(isEnabled: false, mix: 0.3)
        #expect(copy.isEnabled == false)
        #expect(copy.mix == 0.3)
    }

    // MARK: - Duplicate

    @Test("duplicate creates copy with new ID")
    func duplicate() {
        let effect = makeBlurEffect()
        let dupe = effect.duplicate()
        #expect(dupe.id != effect.id)
        #expect(dupe.type == effect.type)
        #expect(dupe.isEnabled == effect.isEnabled)
        #expect(dupe.mix == effect.mix)
        #expect(dupe.parameters == effect.parameters)
    }

    // MARK: - Codable

    @Test("VideoEffect Codable roundtrip")
    func codableRoundtrip() throws {
        let effect = makeBlurEffect()
            .updateParameter("radius", value: .double_(25.0))
        let data = try JSONEncoder().encode(effect)
        let decoded = try JSONDecoder().decode(VideoEffect.self, from: data)
        #expect(decoded == effect)
        #expect(decoded.id == "fx1")
        #expect(decoded.type == EffectType.blur)
        #expect(decoded.getParameterValue("radius")?.asDouble == 25.0)
    }

    @Test("VideoEffect with keyframes Codable roundtrip")
    func codableWithKeyframes() throws {
        let kf = EffectKeyframe(
            id: "kf1",
            timestampMicros: 500_000,
            value: .double_(20.0),
            interpolation: .easeInOut
        )
        let effect = makeBlurEffect().addKeyframe("radius", keyframe: kf)
        let data = try JSONEncoder().encode(effect)
        let decoded = try JSONDecoder().decode(VideoEffect.self, from: data)
        #expect(decoded.hasKeyframes == true)
        #expect(decoded.totalKeyframeCount == 1)
    }

    // MARK: - Equality

    @Test("Effects with same content are equal")
    func equality() {
        let a = makeBlurEffect(id: "fx1")
        let b = makeBlurEffect(id: "fx1")
        #expect(a == b)
    }

    @Test("Effects with different IDs are not equal")
    func inequalityById() {
        let a = makeBlurEffect(id: "fx1")
        let b = makeBlurEffect(id: "fx2")
        #expect(a != b)
    }

    @Test("Effects with different enabled state are not equal")
    func inequalityByEnabled() {
        let a = makeBlurEffect(id: "fx1", isEnabled: true)
        let b = makeBlurEffect(id: "fx1", isEnabled: false)
        #expect(a != b)
    }

    @Test("Effects with different mix are not equal")
    func inequalityByMix() {
        let a = makeBlurEffect(id: "fx1", mix: 1.0)
        let b = makeBlurEffect(id: "fx1", mix: 0.5)
        #expect(a != b)
    }
}
