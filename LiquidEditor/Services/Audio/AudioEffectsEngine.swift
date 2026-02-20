// AudioEffectsEngine.swift
// LiquidEditor
//
// Real-time audio effects processing via AVAudioEngine.
// Manages per-clip effect chains with live parameter updates.

import AVFoundation
import Accelerate
import os

// MARK: - AudioEffectsError

/// Errors thrown by AudioEffectsEngine operations.
enum AudioEffectsError: Error, LocalizedError, Sendable {
    case engineNotInitialized
    case formatCreationFailed
    case engineStartFailed(String)
    case clipNotFound(String)
    case effectNotFound(effectId: String, clipId: String)
    case nodeCreationFailed(AudioEffectType)

    var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            "Audio engine has not been initialized"
        case .formatCreationFailed:
            "Failed to create AVAudioFormat"
        case .engineStartFailed(let reason):
            "Failed to start audio engine: \(reason)"
        case .clipNotFound(let clipId):
            "No effect chain found for clip: \(clipId)"
        case .effectNotFound(let effectId, let clipId):
            "Effect '\(effectId)' not found in clip '\(clipId)'"
        case .nodeCreationFailed(let type):
            "Failed to create audio node for effect type: \(type.rawValue)"
        }
    }
}

// MARK: - AudioEffectsEngine

/// Manages AVAudioEngine-based effect chains for real-time audio preview.
///
/// Each clip can have its own effect chain consisting of multiple audio
/// processing nodes. The engine is kept warm (started once) to avoid
/// cold-start latency when previewing effects.
///
/// ## Concurrency
///
/// Uses `@unchecked Sendable` with a serial `DispatchQueue` because
/// AVAudioEngine callbacks arrive on the audio render thread. Swift
/// actors cannot be used here since AudioUnit parameter updates must
/// happen synchronously on the audio thread without await points.
///
/// ## Effect Chain Layout
///
/// ```
/// PlayerNode -> [Effect1] -> [Effect2] -> ... -> MixerNode -> MainMixer
/// ```
final class AudioEffectsEngine: @unchecked Sendable {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "LiquidEditor", category: "AudioEffectsEngine")

    // MARK: - Types

    /// State for a single clip's effect chain.
    private struct ClipChainState {
        let player: AVAudioPlayerNode
        let mixer: AVAudioMixerNode
        var effectNodes: [AVAudioNode]
        var effectIds: [String]
    }

    // MARK: - Properties

    /// The underlying audio engine. `nil` until `initialize()` is called.
    private var engine: AVAudioEngine?

    /// Per-clip effect chain state, keyed by clip ID.
    private var clipChains: [String: ClipChainState] = [:]

    /// Serial queue protecting all mutable state.
    ///
    /// All access to `engine`, `clipChains` must go through this queue.
    private let stateQueue = DispatchQueue(
        label: "com.liquideditor.audioEffectsEngine.state"
    )

    /// Standard audio format used for all effect chain connections.
    private let standardSampleRate: Double = 44100
    private let standardChannelCount: AVAudioChannelCount = 2

    /// Number of EQ bands in the parametric EQ node.
    private static let eqBandCount: Int = 3

    // MARK: - AudioUnit Parameter Constants

    /// Dynamics processor parameter ranges
    private static let compressorAttackMin: Float = 0.0001
    private static let compressorAttackMax: Float = 0.2
    private static let compressorReleaseMin: Float = 0.01
    private static let compressorReleaseMax: Float = 3.0
    private static let compressorGainMin: Float = -40.0
    private static let compressorGainMax: Float = 40.0
    private static let compressorHeadRoomMin: Float = 0.1
    private static let compressorHeadRoomMax: Float = 40.0
    private static let compressorRatioToHeadRoomFactor: Float = 40.0

    /// Noise gate configuration constants
    private static let noiseGateThresholdOffset: Float = 5.0
    private static let noiseGateHeadRoom: Float = 40.0
    private static let noiseGateExpansionRatio: Float = 50.0

    // MARK: - Lifecycle

    /// Initialize the audio engine.
    ///
    /// Creates the underlying `AVAudioEngine` instance. The engine is
    /// not started until the first effect chain is set up.
    func initialize() {
        stateQueue.sync {
            guard engine == nil else { return }
            engine = AVAudioEngine()
        }
    }

    /// Shut down the engine and release all resources.
    ///
    /// Disconnects and detaches all nodes, stops the engine,
    /// and releases the engine instance.
    func shutdown() {
        stateQueue.sync {
            guard let engine else { return }

            for (_, chain) in clipChains {
                disconnectAndDetach(chain: chain, from: engine)
            }

            clipChains.removeAll()
            engine.stop()
            self.engine = nil
        }
    }

    // MARK: - Effect Chain Management

    /// Set up an effect chain for a clip.
    ///
    /// Removes any existing chain for this clip, then creates a new
    /// chain of audio processing nodes matching the provided effects.
    /// Only enabled effects are included in the chain.
    ///
    /// - Parameters:
    ///   - clipId: Unique identifier for the audio clip.
    ///   - effects: Ordered list of audio effects to apply.
    /// - Throws: `AudioEffectsError` if the engine is not initialized
    ///   or node creation fails.
    func setupEffectChain(
        clipId: String,
        effects: [AudioEffect]
    ) throws {
        try stateQueue.sync {
            guard let engine else {
                throw AudioEffectsError.engineNotInitialized
            }

            // Remove existing chain for this clip
            if let existingChain = clipChains[clipId] {
                disconnectAndDetach(chain: existingChain, from: engine)
                clipChains.removeValue(forKey: clipId)
            }

            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()

            engine.attach(player)
            engine.attach(mixer)

            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: standardSampleRate,
                channels: standardChannelCount
            ) else {
                engine.detach(player)
                engine.detach(mixer)
                throw AudioEffectsError.formatCreationFailed
            }

            var nodes: [AVAudioNode] = []
            var ids: [String] = []
            var previousNode: AVAudioNode = player

            // Only include enabled effects in the chain
            let enabledEffects = effects.filter(\.isEnabled)

            for effect in enabledEffects {
                let node = try createNode(for: effect)
                engine.attach(node)
                engine.connect(previousNode, to: node, format: format)
                nodes.append(node)
                ids.append(effect.id)
                previousNode = node
            }

            engine.connect(previousNode, to: mixer, format: format)
            engine.connect(mixer, to: engine.mainMixerNode, format: format)

            clipChains[clipId] = ClipChainState(
                player: player,
                mixer: mixer,
                effectNodes: nodes,
                effectIds: ids
            )

            // Start engine if not already running
            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    throw AudioEffectsError.engineStartFailed(error.localizedDescription)
                }
            }
        }
    }

    /// Remove the effect chain for a clip.
    ///
    /// Disconnects and detaches all nodes associated with the clip.
    ///
    /// - Parameter clipId: The clip whose chain should be removed.
    /// - Throws: `AudioEffectsError.clipNotFound` if no chain exists.
    func removeEffectChain(clipId: String) throws {
        try stateQueue.sync {
            guard let engine else {
                throw AudioEffectsError.engineNotInitialized
            }
            guard let chain = clipChains[clipId] else {
                throw AudioEffectsError.clipNotFound(clipId)
            }

            disconnectAndDetach(chain: chain, from: engine)
            clipChains.removeValue(forKey: clipId)
        }
    }

    /// Remove all effect chains.
    func removeAllEffectChains() {
        stateQueue.sync {
            guard let engine else { return }

            for (_, chain) in clipChains {
                disconnectAndDetach(chain: chain, from: engine)
            }
            clipChains.removeAll()
        }
    }

    // MARK: - Real-Time Parameter Updates

    /// Update a single effect's parameters in real time.
    ///
    /// Finds the audio node matching the given effect ID within the
    /// clip's chain and applies updated parameters without rebuilding
    /// the entire chain.
    ///
    /// - Parameters:
    ///   - clipId: The clip containing the effect.
    ///   - effect: The updated effect with new parameters.
    /// - Throws: `AudioEffectsError` if the clip or effect is not found.
    func updateEffect(clipId: String, effect: AudioEffect) throws {
        try stateQueue.sync {
            guard let chain = clipChains[clipId] else {
                throw AudioEffectsError.clipNotFound(clipId)
            }

            guard let index = chain.effectIds.firstIndex(of: effect.id),
                  index < chain.effectNodes.count else {
                throw AudioEffectsError.effectNotFound(
                    effectId: effect.id,
                    clipId: clipId
                )
            }

            let node = chain.effectNodes[index]
            applyParams(to: node, effect: effect)
        }
    }

    /// Whether the engine is currently running.
    var isRunning: Bool {
        stateQueue.sync {
            engine?.isRunning ?? false
        }
    }

    /// The number of active clip chains.
    var activeChainCount: Int {
        stateQueue.sync { clipChains.count }
    }

    // MARK: - Node Creation

    /// Create an AVAudioNode for the given audio effect.
    ///
    /// - Parameter effect: The audio effect descriptor.
    /// - Returns: A configured AVAudioNode.
    /// - Throws: `AudioEffectsError.nodeCreationFailed` if the effect
    ///   type is not supported.
    private func createNode(for effect: AudioEffect) throws -> AVAudioNode {
        switch effect {
        case .reverb(let params):
            let node = AVAudioUnitReverb()
            node.loadFactoryPreset(.largeHall2)
            node.wetDryMix = Float(params.mix * 100)
            return node

        case .echo(let params):
            let node = AVAudioUnitDelay()
            node.delayTime = params.delayTime
            node.feedback = Float(params.feedback * 100)
            node.wetDryMix = Float(params.mix * 100)
            return node

        case .pitchShift(let params):
            let node = AVAudioUnitTimePitch()
            node.pitch = Float(params.semitones * 100 + params.cents)
            return node

        case .eq(let params):
            let node = AVAudioUnitEQ(numberOfBands: Self.eqBandCount)
            configureEQ(node, params: params)
            return node

        case .compressor(let params):
            let desc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            let node = AVAudioUnitEffect(audioComponentDescription: desc)
            configureCompressor(node, params: params)
            return node

        case .distortion(let params):
            let node = AVAudioUnitDistortion()
            switch params.distortionType {
            case .overdrive:
                node.loadFactoryPreset(.drumsBitBrush)
            case .fuzz:
                node.loadFactoryPreset(.drumsBufferBeats)
            case .bitcrush:
                node.loadFactoryPreset(.speechGoldenPi)
            }
            node.wetDryMix = Float(params.mix * 100)
            return node

        case .noiseGate(let params):
            let desc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            let node = AVAudioUnitEffect(audioComponentDescription: desc)
            configureNoiseGate(node, params: params)
            return node
        }
    }

    // MARK: - Parameter Application

    /// Apply effect parameters to an existing audio node.
    private func applyParams(to node: AVAudioNode, effect: AudioEffect) {
        switch effect {
        case .reverb(let params):
            if let reverb = node as? AVAudioUnitReverb {
                reverb.wetDryMix = Float(params.mix * 100)
            }

        case .echo(let params):
            if let delay = node as? AVAudioUnitDelay {
                delay.delayTime = params.delayTime
                delay.feedback = Float(params.feedback * 100)
                delay.wetDryMix = Float(params.mix * 100)
            }

        case .pitchShift(let params):
            if let pitch = node as? AVAudioUnitTimePitch {
                pitch.pitch = Float(params.semitones * 100 + params.cents)
            }

        case .eq(let params):
            if let eq = node as? AVAudioUnitEQ {
                configureEQ(eq, params: params)
            }

        case .compressor(let params):
            if let compressor = node as? AVAudioUnitEffect {
                configureCompressor(compressor, params: params)
            }

        case .distortion(let params):
            if let dist = node as? AVAudioUnitDistortion {
                dist.wetDryMix = Float(params.mix * 100)
            }

        case .noiseGate(let params):
            if let gate = node as? AVAudioUnitEffect {
                configureNoiseGate(gate, params: params)
            }
        }
    }

    // MARK: - EQ Configuration

    /// Configure a 3-band parametric EQ node.
    private func configureEQ(_ node: AVAudioUnitEQ, params: EQParams) {
        guard node.bands.count >= Self.eqBandCount else { return }

        // Bass band (low shelf)
        let bass = node.bands[0]
        bass.filterType = .lowShelf
        bass.frequency = Float(params.bassFrequency)
        bass.gain = Float(params.bassGain)
        bass.bypass = false

        // Mid band (parametric)
        let mid = node.bands[1]
        mid.filterType = .parametric
        mid.frequency = Float(params.midFrequency)
        mid.gain = Float(params.midGain)
        mid.bandwidth = Float(params.midQ)
        mid.bypass = false

        // Treble band (high shelf)
        let treble = node.bands[2]
        treble.filterType = .highShelf
        treble.frequency = Float(params.trebleFrequency)
        treble.gain = Float(params.trebleGain)
        treble.bypass = false
    }

    // MARK: - Compressor Configuration

    /// Configure a DynamicsProcessor AudioUnit as a compressor.
    ///
    /// Maps `CompressorParams` to the AudioUnit parameters:
    /// - Threshold (-40 to 20 dB)
    /// - HeadRoom (0.1 to 40 dB) -- approximated from ratio
    /// - ExpansionRatio set to 1.0 (disable expansion for pure compression)
    /// - AttackTime (0.0001 to 0.2 seconds)
    /// - ReleaseTime (0.01 to 3.0 seconds)
    /// - OverallGain (-40 to 40 dB)
    private func configureCompressor(
        _ node: AVAudioUnitEffect,
        params: CompressorParams
    ) {
        let audioUnit = node.audioUnit

        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_Threshold,
            value: Float(params.threshold)
        )

        // Map ratio to headRoom: headRoom ~ 40 / ratio
        let headRoom = max(
            Self.compressorHeadRoomMin,
            min(Self.compressorHeadRoomMax, Self.compressorRatioToHeadRoomFactor / Float(params.ratio))
        )
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_HeadRoom,
            value: headRoom
        )

        // Disable expansion for pure compressor behavior
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_ExpansionRatio,
            value: 1.0
        )

        let clampedAttack = max(Self.compressorAttackMin, min(Self.compressorAttackMax, Float(params.attack)))
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_AttackTime,
            value: clampedAttack
        )

        let clampedRelease = max(Self.compressorReleaseMin, min(Self.compressorReleaseMax, Float(params.release)))
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_ReleaseTime,
            value: clampedRelease
        )

        let clampedGain = max(Self.compressorGainMin, min(Self.compressorGainMax, Float(params.makeupGain)))
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_OverallGain,
            value: clampedGain
        )
    }

    // MARK: - Noise Gate Configuration

    /// Configure a DynamicsProcessor AudioUnit as a noise gate (expander).
    ///
    /// A noise gate is achieved by setting a high expansion ratio so
    /// signals below the threshold are heavily attenuated.
    private func configureNoiseGate(
        _ node: AVAudioUnitEffect,
        params: NoiseGateParams
    ) {
        let audioUnit = node.audioUnit

        // Threshold set slightly above gate threshold
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_Threshold,
            value: Float(params.threshold) + Self.noiseGateThresholdOffset
        )

        // Large headroom to prevent compression above threshold
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_HeadRoom,
            value: Self.noiseGateHeadRoom
        )

        // High expansion ratio for gate-like behavior
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_ExpansionRatio,
            value: Self.noiseGateExpansionRatio
        )

        let clampedAttack = max(Self.compressorAttackMin, min(Self.compressorAttackMax, Float(params.attack)))
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_AttackTime,
            value: clampedAttack
        )

        let clampedRelease = max(Self.compressorReleaseMin, min(Self.compressorReleaseMax, Float(params.release)))
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_ReleaseTime,
            value: clampedRelease
        )

        // No makeup gain for a gate
        setAudioUnitParameter(
            audioUnit,
            param: kDynamicsProcessorParam_OverallGain,
            value: 0.0
        )
    }

    // MARK: - AudioUnit Parameter Helper

    /// Set an AudioUnit parameter with error logging.
    private func setAudioUnitParameter(
        _ unit: AudioUnit,
        param: AudioUnitParameterID,
        value: Float
    ) {
        let status = AudioUnitSetParameter(
            unit,
            param,
            kAudioUnitScope_Global,
            0,
            value,
            0
        )
        if status != noErr {
            Self.logger.warning("AudioUnitSetParameter(\(param)) failed with status \(status)")
        }
    }

    // MARK: - Internal Helpers

    /// Disconnect and detach all nodes in a clip chain.
    private func disconnectAndDetach(
        chain: ClipChainState,
        from engine: AVAudioEngine
    ) {
        for node in chain.effectNodes {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }

        chain.player.stop()
        engine.disconnectNodeOutput(chain.player)
        engine.detach(chain.player)

        engine.disconnectNodeOutput(chain.mixer)
        engine.detach(chain.mixer)
    }
}
