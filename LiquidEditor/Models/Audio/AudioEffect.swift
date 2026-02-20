import Foundation

// MARK: - AudioEffectType

/// Type identifier for audio effects.
enum AudioEffectType: String, Codable, CaseIterable, Sendable {
    case reverb
    case echo
    case pitchShift
    case eq
    case compressor
    case distortion
    case noiseGate

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .reverb: "Reverb"
        case .echo: "Echo"
        case .pitchShift: "Pitch Shift"
        case .eq: "EQ (3-Band)"
        case .compressor: "Compressor"
        case .distortion: "Distortion"
        case .noiseGate: "Noise Gate"
        }
    }

    /// SF Symbol icon name for this effect type.
    var sfSymbolName: String {
        switch self {
        case .reverb: "waveform.badge.plus"
        case .echo: "repeat"
        case .pitchShift: "arrow.up.arrow.down"
        case .eq: "slider.horizontal.3"
        case .compressor: "arrow.down.right.and.arrow.up.left"
        case .distortion: "waveform.path.ecg"
        case .noiseGate: "door.left.hand.closed"
        }
    }
}

// MARK: - DistortionType

/// Distortion sub-type.
enum DistortionType: String, Codable, CaseIterable, Sendable {
    case overdrive
    case fuzz
    case bitcrush

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .overdrive: "Overdrive"
        case .fuzz: "Fuzz"
        case .bitcrush: "Bitcrush"
        }
    }
}

// MARK: - AudioEffect (enum with associated values)

/// Audio effect descriptor.
///
/// Each case is a lightweight descriptor that gets translated
/// to AVAudioEngine nodes on the native side.
/// Uses an enum with associated values to model the Dart abstract
/// class hierarchy (ReverbEffect, EchoEffect, etc.).
enum AudioEffect: Codable, Equatable, Hashable, Sendable {
    case reverb(ReverbParams)
    case echo(EchoParams)
    case pitchShift(PitchShiftParams)
    case eq(EQParams)
    case compressor(CompressorParams)
    case distortion(DistortionParams)
    case noiseGate(NoiseGateParams)

    // MARK: - Common Properties

    /// Unique identifier.
    var id: String {
        switch self {
        case .reverb(let p): p.id
        case .echo(let p): p.id
        case .pitchShift(let p): p.id
        case .eq(let p): p.id
        case .compressor(let p): p.id
        case .distortion(let p): p.id
        case .noiseGate(let p): p.id
        }
    }

    /// Effect type.
    var type: AudioEffectType {
        switch self {
        case .reverb: .reverb
        case .echo: .echo
        case .pitchShift: .pitchShift
        case .eq: .eq
        case .compressor: .compressor
        case .distortion: .distortion
        case .noiseGate: .noiseGate
        }
    }

    /// Whether the effect is enabled.
    var isEnabled: Bool {
        switch self {
        case .reverb(let p): p.isEnabled
        case .echo(let p): p.isEnabled
        case .pitchShift(let p): p.isEnabled
        case .eq(let p): p.isEnabled
        case .compressor(let p): p.isEnabled
        case .distortion(let p): p.isEnabled
        case .noiseGate(let p): p.isEnabled
        }
    }

    /// Wet/dry mix (0.0 = fully dry, 1.0 = fully wet).
    var mix: Double {
        switch self {
        case .reverb(let p): p.mix
        case .echo(let p): p.mix
        case .pitchShift(let p): p.mix
        case .eq(let p): p.mix
        case .compressor(let p): p.mix
        case .distortion(let p): p.mix
        case .noiseGate(let p): p.mix
        }
    }

    /// Toggle enabled state.
    func toggled() -> AudioEffect {
        switch self {
        case .reverb(let p): .reverb(p.with(isEnabled: !p.isEnabled))
        case .echo(let p): .echo(p.with(isEnabled: !p.isEnabled))
        case .pitchShift(let p): .pitchShift(p.with(isEnabled: !p.isEnabled))
        case .eq(let p): .eq(p.with(isEnabled: !p.isEnabled))
        case .compressor(let p): .compressor(p.with(isEnabled: !p.isEnabled))
        case .distortion(let p): .distortion(p.with(isEnabled: !p.isEnabled))
        case .noiseGate(let p): .noiseGate(p.with(isEnabled: !p.isEnabled))
        }
    }

    /// Convert to native params for platform channel.
    func toNativeParams() -> [String: Any] {
        switch self {
        case .reverb(let p):
            return [
                "type": AudioEffectType.reverb.rawValue,
                "id": p.id,
                "mix": p.mix,
                "roomSize": p.roomSize,
                "damping": p.damping,
            ]
        case .echo(let p):
            return [
                "type": AudioEffectType.echo.rawValue,
                "id": p.id,
                "mix": p.mix,
                "delayTime": p.delayTime,
                "feedback": p.feedback,
            ]
        case .pitchShift(let p):
            return [
                "type": AudioEffectType.pitchShift.rawValue,
                "id": p.id,
                "mix": p.mix,
                "semitones": p.semitones,
                "cents": p.cents,
            ]
        case .eq(let p):
            return [
                "type": AudioEffectType.eq.rawValue,
                "id": p.id,
                "mix": p.mix,
                "bassGain": p.bassGain,
                "bassFrequency": p.bassFrequency,
                "midGain": p.midGain,
                "midFrequency": p.midFrequency,
                "midQ": p.midQ,
                "trebleGain": p.trebleGain,
                "trebleFrequency": p.trebleFrequency,
            ]
        case .compressor(let p):
            return [
                "type": AudioEffectType.compressor.rawValue,
                "id": p.id,
                "mix": p.mix,
                "threshold": p.threshold,
                "ratio": p.ratio,
                "attack": p.attack,
                "release": p.release,
                "makeupGain": p.makeupGain,
            ]
        case .distortion(let p):
            return [
                "type": AudioEffectType.distortion.rawValue,
                "id": p.id,
                "mix": p.mix,
                "drive": p.drive,
                "distortionType": p.distortionType.rawValue,
            ]
        case .noiseGate(let p):
            return [
                "type": AudioEffectType.noiseGate.rawValue,
                "id": p.id,
                "mix": p.mix,
                "threshold": p.threshold,
                "attack": p.attack,
                "release": p.release,
            ]
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeStr = try container.decode(String.self, forKey: .type)
        let effectType = AudioEffectType(rawValue: typeStr) ?? .reverb

        switch effectType {
        case .reverb:
            self = .reverb(try ReverbParams(from: decoder))
        case .echo:
            self = .echo(try EchoParams(from: decoder))
        case .pitchShift:
            self = .pitchShift(try PitchShiftParams(from: decoder))
        case .eq:
            self = .eq(try EQParams(from: decoder))
        case .compressor:
            self = .compressor(try CompressorParams(from: decoder))
        case .distortion:
            self = .distortion(try DistortionParams(from: decoder))
        case .noiseGate:
            self = .noiseGate(try NoiseGateParams(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .reverb(let p): try p.encode(to: encoder)
        case .echo(let p): try p.encode(to: encoder)
        case .pitchShift(let p): try p.encode(to: encoder)
        case .eq(let p): try p.encode(to: encoder)
        case .compressor(let p): try p.encode(to: encoder)
        case .distortion(let p): try p.encode(to: encoder)
        case .noiseGate(let p): try p.encode(to: encoder)
        }
    }

    // MARK: - Equatable / Hashable by ID

    static func == (lhs: AudioEffect, rhs: AudioEffect) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ReverbParams

/// Reverb effect parameters (AVAudioUnitReverb).
struct ReverbParams: Codable, Equatable, Hashable, Sendable {
    let id: String
    let isEnabled: Bool
    let mix: Double
    /// Room size: 0.0 (small room) to 1.0 (large hall).
    let roomSize: Double
    /// High frequency damping: 0.0 (bright) to 1.0 (dark).
    let damping: Double

    init(
        id: String,
        isEnabled: Bool = true,
        mix: Double = 0.3,
        roomSize: Double = 0.5,
        damping: Double = 0.5
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.mix = mix
        self.roomSize = roomSize
        self.damping = damping
    }

    func with(
        id: String? = nil,
        isEnabled: Bool? = nil,
        mix: Double? = nil,
        roomSize: Double? = nil,
        damping: Double? = nil
    ) -> ReverbParams {
        ReverbParams(
            id: id ?? self.id,
            isEnabled: isEnabled ?? self.isEnabled,
            mix: mix ?? self.mix,
            roomSize: roomSize ?? self.roomSize,
            damping: damping ?? self.damping
        )
    }

    enum CodingKeys: String, CodingKey {
        case type, id, isEnabled, mix, roomSize, damping
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mix = try container.decodeIfPresent(Double.self, forKey: .mix) ?? 0.3
        roomSize = try container.decodeIfPresent(Double.self, forKey: .roomSize) ?? 0.5
        damping = try container.decodeIfPresent(Double.self, forKey: .damping) ?? 0.5
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AudioEffectType.reverb.rawValue, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mix, forKey: .mix)
        try container.encode(roomSize, forKey: .roomSize)
        try container.encode(damping, forKey: .damping)
    }
}

// MARK: - EchoParams

/// Echo/Delay effect parameters (AVAudioUnitDelay).
struct EchoParams: Codable, Equatable, Hashable, Sendable {
    let id: String
    let isEnabled: Bool
    let mix: Double
    /// Delay time in seconds: 0.01 - 2.0.
    let delayTime: Double
    /// Feedback amount: 0.0 - 0.95.
    let feedback: Double

    init(
        id: String,
        isEnabled: Bool = true,
        mix: Double = 0.3,
        delayTime: Double = 0.3,
        feedback: Double = 0.4
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.mix = mix
        self.delayTime = delayTime
        self.feedback = feedback
    }

    func with(
        id: String? = nil,
        isEnabled: Bool? = nil,
        mix: Double? = nil,
        delayTime: Double? = nil,
        feedback: Double? = nil
    ) -> EchoParams {
        EchoParams(
            id: id ?? self.id,
            isEnabled: isEnabled ?? self.isEnabled,
            mix: mix ?? self.mix,
            delayTime: delayTime ?? self.delayTime,
            feedback: feedback ?? self.feedback
        )
    }

    enum CodingKeys: String, CodingKey {
        case type, id, isEnabled, mix, delayTime, feedback
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mix = try container.decodeIfPresent(Double.self, forKey: .mix) ?? 0.3
        delayTime = try container.decodeIfPresent(Double.self, forKey: .delayTime) ?? 0.3
        feedback = try container.decodeIfPresent(Double.self, forKey: .feedback) ?? 0.4
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AudioEffectType.echo.rawValue, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mix, forKey: .mix)
        try container.encode(delayTime, forKey: .delayTime)
        try container.encode(feedback, forKey: .feedback)
    }
}

// MARK: - PitchShiftParams

/// Pitch shift effect parameters (AVAudioUnitTimePitch).
struct PitchShiftParams: Codable, Equatable, Hashable, Sendable {
    let id: String
    let isEnabled: Bool
    let mix: Double
    /// Pitch shift in semitones: -24 to +24.
    let semitones: Double
    /// Fine tuning in cents: -50 to +50.
    let cents: Double

    init(
        id: String,
        isEnabled: Bool = true,
        mix: Double = 1.0,
        semitones: Double = 0.0,
        cents: Double = 0.0
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.mix = mix
        self.semitones = semitones
        self.cents = cents
    }

    func with(
        id: String? = nil,
        isEnabled: Bool? = nil,
        mix: Double? = nil,
        semitones: Double? = nil,
        cents: Double? = nil
    ) -> PitchShiftParams {
        PitchShiftParams(
            id: id ?? self.id,
            isEnabled: isEnabled ?? self.isEnabled,
            mix: mix ?? self.mix,
            semitones: semitones ?? self.semitones,
            cents: cents ?? self.cents
        )
    }

    enum CodingKeys: String, CodingKey {
        case type, id, isEnabled, mix, semitones, cents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mix = try container.decodeIfPresent(Double.self, forKey: .mix) ?? 1.0
        semitones = try container.decodeIfPresent(Double.self, forKey: .semitones) ?? 0.0
        cents = try container.decodeIfPresent(Double.self, forKey: .cents) ?? 0.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AudioEffectType.pitchShift.rawValue, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mix, forKey: .mix)
        try container.encode(semitones, forKey: .semitones)
        try container.encode(cents, forKey: .cents)
    }
}

// MARK: - EQParams

/// Parametric EQ effect parameters (AVAudioUnitEQ - 3 band).
struct EQParams: Codable, Equatable, Hashable, Sendable {
    let id: String
    let isEnabled: Bool
    let mix: Double
    /// Bass gain in dB: -12 to +12.
    let bassGain: Double
    /// Bass frequency: 60 - 250 Hz.
    let bassFrequency: Double
    /// Mid gain in dB: -12 to +12.
    let midGain: Double
    /// Mid frequency: 500 - 4000 Hz.
    let midFrequency: Double
    /// Mid Q factor: 0.1 - 10.0.
    let midQ: Double
    /// Treble gain in dB: -12 to +12.
    let trebleGain: Double
    /// Treble frequency: 4000 - 16000 Hz.
    let trebleFrequency: Double

    init(
        id: String,
        isEnabled: Bool = true,
        mix: Double = 1.0,
        bassGain: Double = 0.0,
        bassFrequency: Double = 100.0,
        midGain: Double = 0.0,
        midFrequency: Double = 1000.0,
        midQ: Double = 1.0,
        trebleGain: Double = 0.0,
        trebleFrequency: Double = 8000.0
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.mix = mix
        self.bassGain = bassGain
        self.bassFrequency = bassFrequency
        self.midGain = midGain
        self.midFrequency = midFrequency
        self.midQ = midQ
        self.trebleGain = trebleGain
        self.trebleFrequency = trebleFrequency
    }

    func with(
        id: String? = nil,
        isEnabled: Bool? = nil,
        mix: Double? = nil,
        bassGain: Double? = nil,
        bassFrequency: Double? = nil,
        midGain: Double? = nil,
        midFrequency: Double? = nil,
        midQ: Double? = nil,
        trebleGain: Double? = nil,
        trebleFrequency: Double? = nil
    ) -> EQParams {
        EQParams(
            id: id ?? self.id,
            isEnabled: isEnabled ?? self.isEnabled,
            mix: mix ?? self.mix,
            bassGain: bassGain ?? self.bassGain,
            bassFrequency: bassFrequency ?? self.bassFrequency,
            midGain: midGain ?? self.midGain,
            midFrequency: midFrequency ?? self.midFrequency,
            midQ: midQ ?? self.midQ,
            trebleGain: trebleGain ?? self.trebleGain,
            trebleFrequency: trebleFrequency ?? self.trebleFrequency
        )
    }

    enum CodingKeys: String, CodingKey {
        case type, id, isEnabled, mix
        case bassGain, bassFrequency
        case midGain, midFrequency, midQ
        case trebleGain, trebleFrequency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mix = try container.decodeIfPresent(Double.self, forKey: .mix) ?? 1.0
        bassGain = try container.decodeIfPresent(Double.self, forKey: .bassGain) ?? 0.0
        bassFrequency = try container.decodeIfPresent(Double.self, forKey: .bassFrequency) ?? 100.0
        midGain = try container.decodeIfPresent(Double.self, forKey: .midGain) ?? 0.0
        midFrequency = try container.decodeIfPresent(Double.self, forKey: .midFrequency) ?? 1000.0
        midQ = try container.decodeIfPresent(Double.self, forKey: .midQ) ?? 1.0
        trebleGain = try container.decodeIfPresent(Double.self, forKey: .trebleGain) ?? 0.0
        trebleFrequency = try container.decodeIfPresent(Double.self, forKey: .trebleFrequency) ?? 8000.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AudioEffectType.eq.rawValue, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mix, forKey: .mix)
        try container.encode(bassGain, forKey: .bassGain)
        try container.encode(bassFrequency, forKey: .bassFrequency)
        try container.encode(midGain, forKey: .midGain)
        try container.encode(midFrequency, forKey: .midFrequency)
        try container.encode(midQ, forKey: .midQ)
        try container.encode(trebleGain, forKey: .trebleGain)
        try container.encode(trebleFrequency, forKey: .trebleFrequency)
    }
}

// MARK: - CompressorParams

/// Compressor effect parameters (kAudioUnitSubType_DynamicsProcessor).
struct CompressorParams: Codable, Equatable, Hashable, Sendable {
    let id: String
    let isEnabled: Bool
    let mix: Double
    /// Threshold in dB: -60 to 0.
    let threshold: Double
    /// Compression ratio: 1.0 to 20.0.
    let ratio: Double
    /// Attack time in seconds: 0.001 - 0.5.
    let attack: Double
    /// Release time in seconds: 0.01 - 2.0.
    let release: Double
    /// Makeup gain in dB: 0 to 40.
    let makeupGain: Double

    init(
        id: String,
        isEnabled: Bool = true,
        mix: Double = 1.0,
        threshold: Double = -20.0,
        ratio: Double = 4.0,
        attack: Double = 0.01,
        release: Double = 0.1,
        makeupGain: Double = 0.0
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.mix = mix
        self.threshold = threshold
        self.ratio = ratio
        self.attack = attack
        self.release = release
        self.makeupGain = makeupGain
    }

    func with(
        id: String? = nil,
        isEnabled: Bool? = nil,
        mix: Double? = nil,
        threshold: Double? = nil,
        ratio: Double? = nil,
        attack: Double? = nil,
        release: Double? = nil,
        makeupGain: Double? = nil
    ) -> CompressorParams {
        CompressorParams(
            id: id ?? self.id,
            isEnabled: isEnabled ?? self.isEnabled,
            mix: mix ?? self.mix,
            threshold: threshold ?? self.threshold,
            ratio: ratio ?? self.ratio,
            attack: attack ?? self.attack,
            release: release ?? self.release,
            makeupGain: makeupGain ?? self.makeupGain
        )
    }

    enum CodingKeys: String, CodingKey {
        case type, id, isEnabled, mix
        case threshold, ratio, attack, release, makeupGain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mix = try container.decodeIfPresent(Double.self, forKey: .mix) ?? 1.0
        threshold = try container.decodeIfPresent(Double.self, forKey: .threshold) ?? -20.0
        ratio = try container.decodeIfPresent(Double.self, forKey: .ratio) ?? 4.0
        attack = try container.decodeIfPresent(Double.self, forKey: .attack) ?? 0.01
        release = try container.decodeIfPresent(Double.self, forKey: .release) ?? 0.1
        makeupGain = try container.decodeIfPresent(Double.self, forKey: .makeupGain) ?? 0.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AudioEffectType.compressor.rawValue, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mix, forKey: .mix)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(ratio, forKey: .ratio)
        try container.encode(attack, forKey: .attack)
        try container.encode(release, forKey: .release)
        try container.encode(makeupGain, forKey: .makeupGain)
    }
}

// MARK: - DistortionParams

/// Distortion effect parameters (AVAudioUnitDistortion).
struct DistortionParams: Codable, Equatable, Hashable, Sendable {
    let id: String
    let isEnabled: Bool
    let mix: Double
    /// Drive amount: 0.0 - 1.0.
    let drive: Double
    /// Distortion type.
    let distortionType: DistortionType

    init(
        id: String,
        isEnabled: Bool = true,
        mix: Double = 0.5,
        drive: Double = 0.3,
        distortionType: DistortionType = .overdrive
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.mix = mix
        self.drive = drive
        self.distortionType = distortionType
    }

    func with(
        id: String? = nil,
        isEnabled: Bool? = nil,
        mix: Double? = nil,
        drive: Double? = nil,
        distortionType: DistortionType? = nil
    ) -> DistortionParams {
        DistortionParams(
            id: id ?? self.id,
            isEnabled: isEnabled ?? self.isEnabled,
            mix: mix ?? self.mix,
            drive: drive ?? self.drive,
            distortionType: distortionType ?? self.distortionType
        )
    }

    enum CodingKeys: String, CodingKey {
        case type, id, isEnabled, mix, drive, distortionType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mix = try container.decodeIfPresent(Double.self, forKey: .mix) ?? 0.5
        drive = try container.decodeIfPresent(Double.self, forKey: .drive) ?? 0.3
        let distTypeStr = try container.decodeIfPresent(String.self, forKey: .distortionType)
        distortionType = distTypeStr.flatMap { DistortionType(rawValue: $0) } ?? .overdrive
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AudioEffectType.distortion.rawValue, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mix, forKey: .mix)
        try container.encode(drive, forKey: .drive)
        try container.encode(distortionType.rawValue, forKey: .distortionType)
    }
}

// MARK: - NoiseGateParams

/// Noise gate effect parameters (custom implementation via AVAudioUnitEQ high-pass).
struct NoiseGateParams: Codable, Equatable, Hashable, Sendable {
    let id: String
    let isEnabled: Bool
    let mix: Double
    /// Threshold in dB below which audio is gated: -80 to 0.
    let threshold: Double
    /// Attack time in seconds: 0.0001 - 0.1.
    let attack: Double
    /// Release time in seconds: 0.01 - 1.0.
    let release: Double

    init(
        id: String,
        isEnabled: Bool = true,
        mix: Double = 1.0,
        threshold: Double = -40.0,
        attack: Double = 0.005,
        release: Double = 0.05
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.mix = mix
        self.threshold = threshold
        self.attack = attack
        self.release = release
    }

    func with(
        id: String? = nil,
        isEnabled: Bool? = nil,
        mix: Double? = nil,
        threshold: Double? = nil,
        attack: Double? = nil,
        release: Double? = nil
    ) -> NoiseGateParams {
        NoiseGateParams(
            id: id ?? self.id,
            isEnabled: isEnabled ?? self.isEnabled,
            mix: mix ?? self.mix,
            threshold: threshold ?? self.threshold,
            attack: attack ?? self.attack,
            release: release ?? self.release
        )
    }

    enum CodingKeys: String, CodingKey {
        case type, id, isEnabled, mix, threshold, attack, release
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mix = try container.decodeIfPresent(Double.self, forKey: .mix) ?? 1.0
        threshold = try container.decodeIfPresent(Double.self, forKey: .threshold) ?? -40.0
        attack = try container.decodeIfPresent(Double.self, forKey: .attack) ?? 0.005
        release = try container.decodeIfPresent(Double.self, forKey: .release) ?? 0.05
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(AudioEffectType.noiseGate.rawValue, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mix, forKey: .mix)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(attack, forKey: .attack)
        try container.encode(release, forKey: .release)
    }
}

// MARK: - AudioEffectChain

/// Ordered list of effects for an audio clip.
///
/// The chain processes audio in order: first effect receives the
/// source audio, last effect outputs to the clip mixer.
struct AudioEffectChain: Codable, Equatable, Hashable, Sendable {
    /// Ordered list of effects.
    let effects: [AudioEffect]

    init(effects: [AudioEffect] = []) {
        self.effects = effects
    }

    /// Empty effect chain.
    static let empty = AudioEffectChain()

    /// Number of effects in the chain.
    var count: Int { effects.count }

    /// Whether the chain has any effects.
    var isEmpty: Bool { effects.isEmpty }

    /// Number of enabled effects.
    var enabledCount: Int { effects.filter(\.isEnabled).count }

    /// Add an effect to the end of the chain.
    func adding(_ effect: AudioEffect) -> AudioEffectChain {
        AudioEffectChain(effects: effects + [effect])
    }

    /// Remove an effect by ID.
    func removing(effectId: String) -> AudioEffectChain {
        AudioEffectChain(effects: effects.filter { $0.id != effectId })
    }

    /// Update an effect in the chain.
    func updating(_ effect: AudioEffect) -> AudioEffectChain {
        AudioEffectChain(
            effects: effects.map { $0.id == effect.id ? effect : $0 }
        )
    }

    /// Reorder effects.
    func reordered(from oldIndex: Int, to newIndex: Int) -> AudioEffectChain {
        var newEffects = effects
        let item = newEffects.remove(at: oldIndex)
        let adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex
        newEffects.insert(item, at: adjustedIndex)
        return AudioEffectChain(effects: newEffects)
    }

    /// Toggle an effect's enabled state.
    func toggling(effectId: String) -> AudioEffectChain {
        AudioEffectChain(
            effects: effects.map { $0.id == effectId ? $0.toggled() : $0 }
        )
    }

    /// Get effect by ID.
    func effect(withId effectId: String) -> AudioEffect? {
        effects.first { $0.id == effectId }
    }

    /// Convert all enabled effects to native params for platform channel.
    func toNativeParams() -> [[String: Any]] {
        effects
            .filter(\.isEnabled)
            .map { $0.toNativeParams() }
    }
}
