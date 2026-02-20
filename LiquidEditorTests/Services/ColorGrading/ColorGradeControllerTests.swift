import Testing
import Foundation
@testable import LiquidEditor

@Suite("ColorGradeController Tests")
struct ColorGradeControllerTests {

    // MARK: - Lifecycle

    @Test("Initially has no active clip")
    @MainActor func initialState() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)

        #expect(controller.activeClipId == nil)
        #expect(controller.currentGrade == nil)
        #expect(!controller.hasModifications)
        #expect(!controller.isInteracting)
    }

    @Test("Set active clip loads grade from store")
    @MainActor func setActiveClip() {
        let store = ColorGradeStore()
        let grade = makeGrade(exposure: 1.0)
        store.setGrade("clip1", grade)

        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        #expect(controller.activeClipId == "clip1")
        #expect(controller.currentGrade?.exposure == 1.0)
    }

    @Test("Set active clip creates default for new clip")
    @MainActor func setActiveClipNewClip() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)

        controller.setActiveClip("newClip")

        #expect(controller.activeClipId == "newClip")
        #expect(controller.currentGrade != nil)
        #expect(controller.currentGrade?.isIdentity == true)
    }

    @Test("Setting same clip ID is no-op")
    @MainActor func setActiveClipIdempotent() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)

        controller.setActiveClip("clip1")
        let firstGrade = controller.currentGrade

        controller.setActiveClip("clip1")
        #expect(controller.currentGrade?.id == firstGrade?.id)
    }

    @Test("Clear active clip resets state")
    @MainActor func clearActiveClip() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)

        controller.setActiveClip("clip1")
        controller.clearActiveClip()

        #expect(controller.activeClipId == nil)
        #expect(controller.currentGrade == nil)
    }

    // MARK: - Parameter Updates

    @Test("Update parameter modifies working copy")
    @MainActor func updateParameter() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        controller.updateParameter("exposure", value: 1.5)

        #expect(controller.currentGrade?.exposure == 1.5)
        #expect(controller.hasModifications)
    }

    @Test("Update parameter with no active clip is no-op")
    @MainActor func updateParameterNoClip() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)

        controller.updateParameter("exposure", value: 1.5)
        #expect(controller.currentGrade == nil)
    }

    @Test("Begin/end interaction lifecycle")
    @MainActor func interactionLifecycle() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        #expect(!controller.isInteracting)

        controller.beginInteraction()
        #expect(controller.isInteracting)

        controller.updateParameter("brightness", value: 0.5)

        controller.endInteraction()
        #expect(!controller.isInteracting)

        // Should be committed to store
        #expect(store.gradeForClip("clip1")?.brightness == 0.5)
    }

    // MARK: - HSL Updates

    @Test("Update HSL shadows")
    @MainActor func updateHSLShadows() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        let adj = HSLAdjustment(hue: 200, saturation: 0.3, luminance: -0.1)
        controller.updateHSL(.shadows, adjustment: adj)

        #expect(controller.currentGrade?.hslShadows.hue == 200)
    }

    @Test("Update HSL midtones")
    @MainActor func updateHSLMidtones() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        let adj = HSLAdjustment(hue: 100, saturation: 0.2, luminance: 0.0)
        controller.updateHSL(.midtones, adjustment: adj)

        #expect(controller.currentGrade?.hslMidtones.hue == 100)
    }

    @Test("Update HSL highlights")
    @MainActor func updateHSLHighlights() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        let adj = HSLAdjustment(hue: 50, saturation: 0.15, luminance: 0.05)
        controller.updateHSL(.highlights, adjustment: adj)

        #expect(controller.currentGrade?.hslHighlights.hue == 50)
    }

    // MARK: - Curve Updates

    @Test("Update luminance curve")
    @MainActor func updateLuminanceCurve() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        let curve = CurveData(points: [
            CurvePoint(0, 0.1), CurvePoint(0.5, 0.6), CurvePoint(1, 0.9),
        ])
        controller.updateCurve(.luminance, curve: curve)

        #expect(controller.currentGrade?.curveLuminance.points.count == 3)
    }

    // MARK: - LUT Operations

    @Test("Apply LUT commits to store")
    @MainActor func applyLUT() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        let lut = LUTReference(
            id: "test_lut",
            name: "Test",
            lutAssetPath: "bundled://test",
            source: .bundled
        )
        controller.applyLUT(lut)

        #expect(controller.currentGrade?.lutFilter?.id == "test_lut")
        #expect(store.gradeForClip("clip1")?.lutFilter?.id == "test_lut")
    }

    @Test("Remove LUT clears filter")
    @MainActor func removeLUT() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        let lut = LUTReference(
            id: "test_lut",
            name: "Test",
            lutAssetPath: "bundled://test",
            source: .bundled
        )
        controller.applyLUT(lut)
        controller.removeLUT()

        #expect(controller.currentGrade?.lutFilter == nil)
    }

    @Test("Update LUT intensity modifies existing LUT")
    @MainActor func updateLUTIntensity() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        let lut = LUTReference(
            id: "test_lut",
            name: "Test",
            lutAssetPath: "bundled://test",
            source: .bundled,
            intensity: 1.0
        )
        controller.applyLUT(lut)
        controller.updateLUTIntensity(0.5)

        #expect(controller.currentGrade?.lutFilter?.intensity == 0.5)
    }

    // MARK: - Preset Application

    @Test("Apply preset with full intensity")
    @MainActor func applyPresetFull() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        controller.applyPreset(BuiltinPresets.vivid)

        #expect(controller.currentGrade?.contrast == 0.2)
        #expect(controller.currentGrade?.saturation == 0.35)
    }

    @Test("Apply preset with partial intensity")
    @MainActor func applyPresetPartial() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        controller.applyPreset(BuiltinPresets.vivid, intensity: 0.5)

        // At 0.5 intensity, values should be roughly half the preset values
        #expect(controller.currentGrade?.contrast != nil)
        let contrast = controller.currentGrade?.contrast ?? 0
        #expect(abs(contrast - 0.1) < 0.02) // ~0.1 (half of 0.2)
    }

    // MARK: - Reset & Copy

    @Test("Reset grade restores defaults")
    @MainActor func resetGrade() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")
        controller.updateParameter("exposure", value: 2.0)
        controller.endInteraction()

        controller.resetGrade()

        #expect(controller.currentGrade?.isIdentity == true)
    }

    @Test("Copy grade to another clip")
    @MainActor func copyGrade() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")
        controller.updateParameter("saturation", value: 0.8)
        controller.endInteraction()

        controller.copyGradeTo("clip2")

        #expect(store.gradeForClip("clip2")?.saturation == 0.8)
    }

    @Test("Toggle enabled flips state")
    @MainActor func toggleEnabled() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        #expect(controller.currentGrade?.isEnabled == true)

        controller.toggleEnabled()
        #expect(controller.currentGrade?.isEnabled == false)

        controller.toggleEnabled()
        #expect(controller.currentGrade?.isEnabled == true)
    }

    // MARK: - Color Keyframes

    @Test("Add and retrieve color keyframes")
    @MainActor func addKeyframe() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")
        controller.updateParameter("exposure", value: 1.0)

        controller.addColorKeyframe(at: 1_000_000)

        #expect(controller.hasColorKeyframes)
        #expect(controller.colorKeyframes.count == 1)
        #expect(controller.colorKeyframes[0].timestampMicros == 1_000_000)
    }

    @Test("Remove color keyframe")
    @MainActor func removeKeyframe() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        controller.addColorKeyframe(at: 1_000_000)
        let kfId = controller.colorKeyframes[0].id

        controller.removeColorKeyframe(kfId)
        #expect(!controller.hasColorKeyframes)
    }

    @Test("Interpolate between keyframes")
    @MainActor func interpolateKeyframes() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        // Create two keyframes with different exposure
        let now = Date()
        let grade1 = ColorGrade(id: "g1", exposure: 0.0, createdAt: now, modifiedAt: now)
        let grade2 = ColorGrade(id: "g2", exposure: 2.0, createdAt: now, modifiedAt: now)

        let kf1 = ColorKeyframe(id: "kf1", timestampMicros: 0, grade: grade1)
        let kf2 = ColorKeyframe(id: "kf2", timestampMicros: 1_000_000, grade: grade2)

        store.addKeyframe("clip1", kf1)
        store.addKeyframe("clip1", kf2)

        // Interpolate at midpoint (linear)
        let result = controller.interpolateAt(500_000)
        #expect(result != nil)
        #expect(abs((result?.exposure ?? 0) - 1.0) < 0.01) // halfway = 1.0
    }

    @Test("Interpolate before first keyframe returns first grade")
    @MainActor func interpolateBeforeFirst() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        let now = Date()
        let grade = ColorGrade(id: "g1", exposure: 1.5, createdAt: now, modifiedAt: now)
        store.addKeyframe("clip1", ColorKeyframe(id: "kf1", timestampMicros: 1_000_000, grade: grade))

        let result = controller.interpolateAt(0)
        #expect(result?.exposure == 1.5)
    }

    @Test("Interpolate with hold returns before grade")
    @MainActor func interpolateHold() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        controller.setActiveClip("clip1")

        let now = Date()
        let grade1 = ColorGrade(id: "g1", exposure: 0.0, createdAt: now, modifiedAt: now)
        let grade2 = ColorGrade(id: "g2", exposure: 2.0, createdAt: now, modifiedAt: now)

        let kf1 = ColorKeyframe(id: "kf1", timestampMicros: 0, grade: grade1, interpolation: .hold)
        let kf2 = ColorKeyframe(id: "kf2", timestampMicros: 1_000_000, grade: grade2)

        store.addKeyframe("clip1", kf1)
        store.addKeyframe("clip1", kf2)

        let result = controller.interpolateAt(500_000)
        #expect(result?.exposure == 0.0) // Hold = use "before" grade
    }

    // MARK: - Preview Mode

    @Test("Default preview mode is normal")
    @MainActor func defaultPreviewMode() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        #expect(controller.previewMode == .normal)
    }

    @Test("Set preview mode")
    @MainActor func setPreviewMode() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)

        controller.previewMode = .splitComparison
        #expect(controller.previewMode == .splitComparison)
    }

    // MARK: - Active Panel

    @Test("Default panel is adjustments")
    @MainActor func defaultPanel() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)
        #expect(controller.activePanel == .adjustments)
    }

    @Test("Set active panel")
    @MainActor func setActivePanel() {
        let store = ColorGradeStore()
        let controller = ColorGradeController(store: store)

        controller.activePanel = .curves
        #expect(controller.activePanel == .curves)
    }

    // MARK: - Helpers

    private func makeGrade(
        exposure: Double = 0.0,
        contrast: Double = 0.0
    ) -> ColorGrade {
        let now = Date()
        return ColorGrade(
            id: UUID().uuidString,
            exposure: exposure,
            contrast: contrast,
            createdAt: now,
            modifiedAt: now
        )
    }
}
