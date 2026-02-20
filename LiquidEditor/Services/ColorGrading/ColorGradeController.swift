/// ColorGradeController - UI state management for color grading.
///
/// Manages the active color grade editing state for the selected clip.
/// Handles parameter updates, preset application, and undo coalescing
/// for slider interactions. Communicates with the native CIFilter pipeline
/// via `ColorGradingPipeline` for real-time preview.
///
/// Thread Safety: `@Observable @MainActor` for SwiftUI integration.
/// All mutations happen on the main actor; native pipeline calls
/// are dispatched to the render thread by the pipeline itself.

import Foundation
import Observation

// MARK: - PreviewMode

/// Preview comparison mode for the color grading UI.
enum PreviewMode: String, Sendable, CaseIterable {
    /// Normal preview with color grade applied.
    case normal

    /// Side-by-side split comparison (original | graded).
    case splitComparison

    /// Toggle between original and graded on tap.
    case toggleComparison
}

// MARK: - ColorPanel

/// Active tab in the color grading interface.
enum ColorPanel: String, Sendable, CaseIterable {
    case adjustments
    case filters
    case hsl
    case curves
    case vignette
}

// MARK: - TonalRange

/// Tonal range for HSL adjustments.
enum TonalRange: String, Sendable, CaseIterable {
    case shadows
    case midtones
    case highlights
}

// MARK: - CurveChannel

/// Curve channel type.
enum CurveChannel: String, Sendable, CaseIterable {
    case luminance
    case red
    case green
    case blue
}

// MARK: - ColorGradeController

/// Controller for the color grading interface.
///
/// Manages the lifecycle of color grade editing for a single clip.
/// Handles parameter throttling, undo coalescing during slider
/// interactions, and communication with the native CIFilter pipeline.
@Observable
@MainActor
final class ColorGradeController {

    // MARK: - Dependencies

    /// The color grade store (source of truth).
    private let store: ColorGradeStore

    /// The native pipeline for real-time preview.
    private let pipeline: ColorGradingPipeline

    // MARK: - State

    /// The currently active clip ID.
    private(set) var activeClipId: String?

    /// Current working copy of the color grade.
    private(set) var currentGrade: ColorGrade?

    /// Current preview mode.
    var previewMode: PreviewMode = .normal

    /// Active panel tab.
    var activePanel: ColorPanel = .adjustments

    /// Whether a slider interaction is in progress.
    private(set) var isInteracting: Bool = false

    /// Debounce task for native updates.
    private var debounceTask: Task<Void, Never>?

    // MARK: - Init

    /// Creates a controller with the given store and pipeline.
    init(store: ColorGradeStore, pipeline: ColorGradingPipeline = .shared) {
        self.store = store
        self.pipeline = pipeline
    }

    // MARK: - Computed Properties

    /// Whether the current grade has been modified from default.
    var hasModifications: Bool {
        guard let grade = currentGrade else { return false }
        return !grade.isIdentity
    }

    /// Color keyframes for the active clip.
    var colorKeyframes: [ColorKeyframe] {
        guard let clipId = activeClipId else { return [] }
        return store.keyframesForClip(clipId)
    }

    /// Whether the active clip has color keyframes.
    var hasColorKeyframes: Bool {
        guard let clipId = activeClipId else { return false }
        return store.hasKeyframes(clipId)
    }

    // MARK: - Lifecycle

    /// Set the active clip for editing.
    func setActiveClip(_ clipId: String) {
        guard activeClipId != clipId else { return }

        activeClipId = clipId
        currentGrade = store.getOrCreateGrade(clipId)
    }

    /// Clear the active clip.
    func clearActiveClip() {
        activeClipId = nil
        currentGrade = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Parameter Updates

    /// Update a single parameter value.
    ///
    /// During continuous interaction (slider drag), the UI updates
    /// immediately. Undo snapshots are created only on interaction end.
    func updateParameter(_ name: String, value: Double) {
        guard currentGrade != nil, activeClipId != nil else { return }

        currentGrade = currentGrade!.withParam(name, value: value)
    }

    /// Signal that a continuous interaction (slider drag) has started.
    func beginInteraction() {
        isInteracting = true
    }

    /// Signal that a continuous interaction has ended.
    /// Commits the change to the store (creating an undo point).
    func endInteraction() {
        isInteracting = false

        if let clipId = activeClipId, let grade = currentGrade {
            store.setGrade(clipId, grade)
        }
    }

    /// Update the HSL adjustment for a tonal range.
    func updateHSL(_ range: TonalRange, adjustment: HSLAdjustment) {
        guard currentGrade != nil, activeClipId != nil else { return }

        switch range {
        case .shadows:
            currentGrade = currentGrade!.with(hslShadows: adjustment)
        case .midtones:
            currentGrade = currentGrade!.with(hslMidtones: adjustment)
        case .highlights:
            currentGrade = currentGrade!.with(hslHighlights: adjustment)
        }
    }

    /// Update a curve channel.
    func updateCurve(_ channel: CurveChannel, curve: CurveData) {
        guard currentGrade != nil, activeClipId != nil else { return }

        switch channel {
        case .luminance:
            currentGrade = currentGrade!.with(curveLuminance: curve)
        case .red:
            currentGrade = currentGrade!.with(curveRed: curve)
        case .green:
            currentGrade = currentGrade!.with(curveGreen: curve)
        case .blue:
            currentGrade = currentGrade!.with(curveBlue: curve)
        }
    }

    /// Apply a LUT filter.
    func applyLUT(_ lut: LUTReference) {
        guard currentGrade != nil, let clipId = activeClipId else { return }

        currentGrade = currentGrade!.with(lutFilter: lut)
        store.setGrade(clipId, currentGrade!)
    }

    /// Remove the LUT filter.
    func removeLUT() {
        guard currentGrade != nil, let clipId = activeClipId else { return }

        currentGrade = currentGrade!.with(clearLut: true)
        store.setGrade(clipId, currentGrade!)
    }

    /// Update LUT intensity.
    func updateLUTIntensity(_ intensity: Double) {
        precondition(intensity >= 0.0 && intensity <= 1.0, "LUT intensity must be in range 0.0-1.0")

        guard var grade = currentGrade,
              activeClipId != nil,
              let existingLUT = grade.lutFilter else {
            return
        }

        let updatedLUT = existingLUT.with(intensity: intensity)
        grade = grade.with(lutFilter: updatedLUT)
        currentGrade = grade
    }

    // MARK: - Preset Application

    /// Apply a filter preset with given intensity.
    func applyPreset(_ preset: FilterPreset, intensity: Double = 1.0) {
        precondition(intensity >= 0.0 && intensity <= 1.0, "Preset intensity must be in range 0.0-1.0")

        guard let clipId = activeClipId else { return }

        let defaultGrade = ColorGrade(
            id: currentGrade?.id ?? UUID().uuidString,
            createdAt: currentGrade?.createdAt ?? Date(),
            modifiedAt: Date()
        )

        currentGrade = preset.applyWithIntensity(
            currentGrade ?? defaultGrade,
            intensity: intensity
        )
        store.setGrade(clipId, currentGrade!)
    }

    // MARK: - Reset & Copy

    /// Reset the active clip's color grade to defaults.
    func resetGrade() {
        guard let clipId = activeClipId else { return }

        store.resetGrade(clipId)
        currentGrade = store.getOrCreateGrade(clipId)
    }

    /// Copy the current grade to another clip.
    func copyGradeTo(_ targetClipId: String) {
        guard let clipId = activeClipId else { return }
        guard targetClipId != clipId else { return } // Skip copying to self
        store.copyGrade(from: clipId, to: targetClipId)
    }

    /// Toggle the grade enable/disable.
    func toggleEnabled() {
        guard let grade = currentGrade, let clipId = activeClipId else { return }

        currentGrade = grade.with(isEnabled: !grade.isEnabled)
        store.setGrade(clipId, currentGrade!)
    }

    // MARK: - Color Keyframes

    /// Add a color keyframe at the given timestamp.
    func addColorKeyframe(
        at timestampMicros: TimeMicros,
        interpolation: InterpolationType = .linear
    ) {
        guard let grade = currentGrade, let clipId = activeClipId else { return }

        let keyframe = ColorKeyframe(
            id: UUID().uuidString,
            timestampMicros: timestampMicros,
            grade: grade,
            interpolation: interpolation
        )

        store.addKeyframe(clipId, keyframe)
    }

    /// Remove a color keyframe.
    func removeColorKeyframe(_ keyframeId: String) {
        guard let clipId = activeClipId else { return }
        store.removeKeyframe(clipId, keyframeId: keyframeId)
    }

    /// Interpolate the color grade at a specific time using keyframes.
    func interpolateAt(_ timeMicros: TimeMicros) -> ColorGrade? {
        guard let clipId = activeClipId else { return currentGrade }

        let kfs = store.keyframesForClip(clipId)
        if kfs.isEmpty { return currentGrade }

        // Find surrounding keyframes
        var before: ColorKeyframe?
        var after: ColorKeyframe?

        for kf in kfs {
            if kf.timestampMicros <= timeMicros {
                before = kf
            } else {
                after = kf
                break
            }
        }

        guard let before else { return kfs.first?.grade }
        guard let after else { return before.grade }

        // Compute interpolation factor
        let range = after.timestampMicros - before.timestampMicros
        guard range > 0 else { return before.grade }

        var t = Double(timeMicros - before.timestampMicros) / Double(range)
        t = min(max(t, 0.0), 1.0)

        // Apply easing
        if before.interpolation == .hold {
            return before.grade
        }

        t = before.interpolation.apply(t)

        return ColorGrade.lerp(before.grade, after.grade, t: t)
    }
}
