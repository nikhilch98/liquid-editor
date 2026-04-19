// AudioDSPPipeline.swift
// LiquidEditor
//
// PP12-13: Audio DSP pipeline extensions — ordered, reorderable stage graph.
//
// The pipeline holds an array of `DSPStage`s and runs `process(samples:)`
// through them in order. Each stage currently uses a pass-through stub so
// the public surface is stable while the individual algorithms land in
// follow-up tasks (see docs/APP_LOGIC.md — "Audio DSP pipeline").
//
// All stages run on the `@MainActor` because pipeline mutations (adding,
// removing, reordering stages) are driven from the UI. Real-time rendering
// should hop off-main into `AudioEffectsEngine` once the stubs are replaced.

import Foundation
import Observation

// MARK: - Stages

/// Ordered DSP stages supported by the pipeline. Add cases conservatively —
/// each stage ships with a real implementation plus unit tests.
enum DSPStage: Sendable, Hashable, CaseIterable {
    case eq
    case compressor
    case reverb
    case delay
    case limiter
    case pitch
}

// MARK: - Pipeline

/// Ordered chain of DSP stages. Stages run in the order they appear in
/// `stages`. Duplicates are permitted (e.g. two EQs around a compressor).
@MainActor
@Observable
final class AudioDSPPipeline {

    /// Current stage order. Mutated via `addStage`, `removeStage`,
    /// `reorderStages`. Publicly readable for UI binding.
    private(set) var stages: [DSPStage]

    init(stages: [DSPStage] = []) {
        self.stages = stages
    }

    // MARK: - Mutators

    /// Append a stage to the end of the chain. Duplicates are allowed.
    func addStage(_ stage: DSPStage) {
        stages.append(stage)
    }

    /// Remove the first occurrence of the given stage. No-op if absent.
    func removeStage(_ stage: DSPStage) {
        if let idx = stages.firstIndex(of: stage) {
            stages.remove(at: idx)
        }
    }

    /// Move a stage from one index to another. Both indices must lie in
    /// `0..<stages.count`. Out-of-range moves are no-ops.
    func reorderStages(from source: Int, to destination: Int) {
        guard stages.indices.contains(source) else { return }
        guard destination >= 0 && destination <= stages.count else { return }
        guard source != destination else { return }

        let stage = stages.remove(at: source)
        // When removing lowered the destination, clamp.
        let clamped = min(destination, stages.count)
        stages.insert(stage, at: clamped)
    }

    // MARK: - Processing

    /// Run `samples` through every stage in order and return the result.
    ///
    /// Current stages are pass-through stubs; real implementations land in
    /// follow-up tasks. The function is kept synchronous so callers that
    /// already run on a dedicated audio queue don't pay suspension cost.
    func process(samples: [Float], sampleRate: Double) -> [Float] {
        var buffer = samples
        for stage in stages {
            buffer = Self.apply(stage: stage, to: buffer, sampleRate: sampleRate)
        }
        return buffer
    }

    // MARK: - Stage Implementations (stubs)

    /// Dispatch to the per-stage implementation. Each branch is a
    /// pass-through placeholder — replace with real DSP as stages land.
    private static func apply(
        stage: DSPStage,
        to samples: [Float],
        sampleRate: Double
    ) -> [Float] {
        switch stage {
        case .eq:
            // TODO(PP12-13.eq): Parametric EQ via vDSP biquad cascade.
            return samples
        case .compressor:
            // TODO(PP12-13.compressor): Feed-forward compressor with
            // threshold / ratio / attack / release controls.
            return samples
        case .reverb:
            // TODO(PP12-13.reverb): Convolution reverb using an impulse
            // response; fall back to AVAudioUnitReverb for previews.
            return samples
        case .delay:
            // TODO(PP12-13.delay): Single-tap delay with feedback + mix.
            return samples
        case .limiter:
            // TODO(PP12-13.limiter): Look-ahead brickwall limiter sitting
            // after every other stage to guarantee -1 dBFS ceiling.
            return samples
        case .pitch:
            // TODO(PP12-13.pitch): Pitch shift via phase vocoder / AUPitch.
            return samples
        }
    }
}
