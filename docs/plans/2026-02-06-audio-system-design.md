# Audio System Enhancements - Design Document

**Date:** 2026-02-06
**Status:** Draft
**Author:** Claude Code
**Related:** [Timeline Architecture V2](2026-01-30-timeline-architecture-v2-design.md), [DESIGN.md](../DESIGN.md)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Data Models](#2-data-models)
3. [Architecture](#3-architecture)
4. [Waveform Visualization](#4-waveform-visualization)
5. [Audio Detach](#5-audio-detach)
6. [Multiple Audio Tracks](#6-multiple-audio-tracks)
7. [Volume Keyframing (Envelope Editor)](#7-volume-keyframing-envelope-editor)
8. [Audio Fade In/Out](#8-audio-fade-inout)
9. [Voiceover Recording](#9-voiceover-recording)
10. [Audio Effects](#10-audio-effects)
11. [Noise Reduction](#11-noise-reduction)
12. [Beat Detection](#12-beat-detection)
13. [Audio Ducking](#13-audio-ducking)
14. [Sound Effects Library](#14-sound-effects-library)
15. [Audio Export](#15-audio-export)
16. [Native Integration (AVAudioEngine)](#16-native-integration-avaudioengine)
17. [Persistence](#17-persistence)
18. [Edge Cases](#18-edge-cases)
19. [Performance](#19-performance)
20. [Dependencies](#20-dependencies)
21. [Implementation Plan](#21-implementation-plan)

---

## 1. Overview

### Goals

The Audio System Enhancements transform Liquid Editor from a video-centric editor with basic volume/mute controls into a full-featured audio editing environment. The design preserves the existing immutable data model architecture (Persistent AVL Order Statistic Tree, O(log n) timeline operations, O(1) undo/redo via pointer swap) while layering audio capabilities on top.

### Scope

| Feature | Priority | Complexity | Phase |
|---------|----------|-----------|-------|
| Waveform Visualization | P0 | Medium | 1 |
| Audio Detach | P0 | Low | 2 |
| Audio Fade In/Out | P0 | Medium | 3 |
| Multiple Audio Tracks | P0 | High | 4 |
| Volume Keyframing | P1 | Medium | 5 |
| Audio Effects | P1 | High | 6 |
| Voiceover Recording | P1 | High | 7 |
| Beat Detection | P2 | High | 8 |
| Audio Ducking | P2 | High | 9 |
| Noise Reduction | P2 | Very High | 10 |
| Sound Effects Library | P2 | Medium | 11 |
| Audio Extraction/Export | P1 | Medium | 12 |
| Audio Fade Curves | P1 | Low | 3 (bundled with Fade In/Out) |

### Design Principles

1. **Immutable data throughout.** All audio models are `@immutable` Dart classes with `copyWith` methods, consistent with the existing `TimelineClip`, `Track`, and `VolumeKeyframe` models.
2. **Native processing, Flutter rendering.** Audio analysis (waveform extraction, beat detection, effects processing) runs on native Swift via `AVAudioEngine` and `Accelerate` framework. Flutter handles UI rendering and state management.
3. **O(1) undo/redo preserved.** Audio edits (fade changes, effect chain modifications, envelope updates) are part of the immutable timeline state and participate in the existing pointer-swap undo system via `TimelineManager`.
4. **Background everything.** Waveform extraction, beat detection, effect preview, and noise profiling all run on background threads/isolates. The UI never blocks.
5. **Memory-conscious.** Waveform data uses the existing `WaveformCache` with multi-LOD support (low/medium/high detail). Effect chains are lightweight descriptors, not live DSP objects.

### Existing Codebase Integration Points

| Existing Component | Location | How Audio System Integrates |
|---|---|---|
| `AudioClip` | `lib/models/clips/audio_clip.dart` | Extended with fade, effects chain, and envelope fields |
| `VolumeEnvelope` / `VolumeKeyframe` | `lib/timeline/data/models/volume_keyframe.dart` | Already exists; extended with curve interpolation types |
| `WaveformCache` | `lib/timeline/cache/waveform_cache.dart` | Already exists with multi-LOD; wired to native extraction |
| `Track` model | `lib/timeline/data/models/track.dart` | Already supports `audio`, `music`, `voiceover` track types with solo/mute/volume |
| `ClipsPainter` | `lib/timeline/rendering/painters/clip_painter.dart` | Extended with waveform drawing for audio clips |
| `CompositionBuilder` | `ios/Runner/Timeline/CompositionBuilder.swift` | Extended for multi-track audio mixing and effect application |
| `CompositionManagerService` | `ios/Runner/Timeline/CompositionManagerService.swift` | Hot-swap extended for audio effect graph changes |
| `VolumeControlSheet` | `lib/views/smart_edit/volume_control_sheet.dart` | Retained as quick-volume; envelope editor is separate UI |
| `TimelineClip` (UI model) | `lib/timeline/data/models/timeline_clip.dart` | Already has `showsWaveform` for audio type; extended for fade handles |
| `SnapTargetType.beatMarker` | `lib/timeline/data/models/edit_operations.dart` | Already defined; wired to beat detection output |
| `MarkerType.beat` | `lib/timeline/data/models/marker.dart` | Already defined with pink color; used for beat markers |

---

## 2. Data Models

All models follow the existing project conventions: `@immutable`, `copyWith`, `toJson`/`fromJson`, `==`/`hashCode` overrides.

### 2.1 AudioClip Enhancements

The existing `AudioClip` (`lib/models/clips/audio_clip.dart`) is extended with new fields. Because the class is immutable, this is a non-breaking additive change with default values.

```dart
/// Enhanced audio clip with fade, effects, and envelope support.
@immutable
class AudioClip extends MediaClip {
  // --- Existing fields ---
  final String? name;
  final double volume;       // 0.0 - 1.0
  final bool isMuted;

  // --- NEW: Fade ---
  final AudioFade? fadeIn;
  final AudioFade? fadeOut;

  // --- NEW: Effects chain ---
  final List<AudioEffect> effects;

  // --- NEW: Volume envelope ---
  final VolumeEnvelope envelope;

  // --- NEW: Linked video clip (for detached audio) ---
  final String? linkedVideoClipId;

  // --- NEW: Playback speed (independent of video) ---
  final double speed;  // 0.25 - 4.0, default 1.0

  const AudioClip({
    required super.id,
    required super.mediaAssetId,
    required super.sourceInMicros,
    required super.sourceOutMicros,
    this.name,
    this.volume = 1.0,
    this.isMuted = false,
    this.fadeIn,
    this.fadeOut,
    this.effects = const [],
    this.envelope = const VolumeEnvelope(),
    this.linkedVideoClipId,
    this.speed = 1.0,
  });

  // ... copyWith, toJson, fromJson updated accordingly
}
```

**Migration:** Existing serialized AudioClips without the new fields will deserialize with defaults (no fade, no effects, empty envelope, no link, speed 1.0). No migration script needed.

### 2.2 AudioFade Model

```dart
/// Type of fade curve
enum FadeCurveType {
  /// Straight line (0 to 1 or 1 to 0)
  linear,

  /// Slow start, fast finish
  logarithmic,

  /// S-shaped curve (slow start, fast middle, slow end)
  sCurve,

  /// Equal power crossfade (constant perceived loudness)
  equalPower,

  /// Exponential (fast start, slow finish)
  exponential,
}

/// Immutable audio fade descriptor.
@immutable
class AudioFade {
  /// Duration of the fade in microseconds.
  final int durationMicros;

  /// Curve shape for the fade.
  final FadeCurveType curveType;

  const AudioFade({
    required this.durationMicros,
    this.curveType = FadeCurveType.sCurve,
  });

  /// Default fade in (500ms, S-curve)
  static const AudioFade defaultFadeIn = AudioFade(
    durationMicros: 500000,
    curveType: FadeCurveType.sCurve,
  );

  /// Default fade out (500ms, S-curve)
  static const AudioFade defaultFadeOut = AudioFade(
    durationMicros: 500000,
    curveType: FadeCurveType.sCurve,
  );

  /// Minimum fade duration (~2 frames at 30fps)
  static const int minDurationMicros = 66666;

  /// Maximum fade duration (10 seconds)
  static const int maxDurationMicros = 10000000;

  /// Compute gain multiplier at normalized position t (0.0 to 1.0)
  /// For fade-in: t=0 -> 0.0, t=1 -> 1.0
  /// For fade-out: caller inverts (1.0 - result)
  double gainAtNormalized(double t) {
    final clamped = t.clamp(0.0, 1.0);
    switch (curveType) {
      case FadeCurveType.linear:
        return clamped;
      case FadeCurveType.logarithmic:
        return clamped == 0 ? 0 : (1 + (log(clamped) / log(10)) * 0.5).clamp(0.0, 1.0);
      case FadeCurveType.sCurve:
        // Hermite S-curve: 3t^2 - 2t^3
        return 3 * clamped * clamped - 2 * clamped * clamped * clamped;
      case FadeCurveType.equalPower:
        return sin(clamped * pi / 2);
      case FadeCurveType.exponential:
        return clamped * clamped;
    }
  }

  AudioFade copyWith({int? durationMicros, FadeCurveType? curveType});
  Map<String, dynamic> toJson();
  factory AudioFade.fromJson(Map<String, dynamic> json);
}
```

### 2.3 AudioEffect Base Model and Subtypes

```dart
/// Type identifier for audio effects
enum AudioEffectType {
  reverb,
  echo,
  pitchShift,
  eq,
  compressor,
  distortion,
  noiseGate,
}

/// Base class for all audio effects.
///
/// Each effect is a lightweight descriptor that gets translated
/// to AVAudioEngine nodes on the native side.
@immutable
abstract class AudioEffect {
  final String id;
  final AudioEffectType type;
  final bool isEnabled;

  /// Wet/dry mix (0.0 = fully dry, 1.0 = fully wet)
  final double mix;

  const AudioEffect({
    required this.id,
    required this.type,
    this.isEnabled = true,
    this.mix = 0.5,
  });

  AudioEffect copyWith({String? id, bool? isEnabled, double? mix});

  /// Convert to platform channel arguments for native setup
  Map<String, dynamic> toNativeParams();

  Map<String, dynamic> toJson();
  static AudioEffect fromJson(Map<String, dynamic> json);
}
```

#### Effect Subtypes

```dart
/// Reverb effect (AVAudioUnitReverb)
@immutable
class ReverbEffect extends AudioEffect {
  /// Room size: 0.0 (small room) to 1.0 (large hall)
  final double roomSize;

  /// High frequency damping: 0.0 (bright) to 1.0 (dark)
  final double damping;

  const ReverbEffect({
    required super.id,
    super.isEnabled,
    super.mix = 0.3,
    this.roomSize = 0.5,
    this.damping = 0.5,
  }) : super(type: AudioEffectType.reverb);
}

/// Echo/Delay effect (AVAudioUnitDelay)
@immutable
class EchoEffect extends AudioEffect {
  /// Delay time in seconds: 0.01 - 2.0
  final double delayTime;

  /// Feedback amount: 0.0 - 0.95 (values near 1.0 cause runaway)
  final double feedback;

  const EchoEffect({
    required super.id,
    super.isEnabled,
    super.mix = 0.3,
    this.delayTime = 0.3,
    this.feedback = 0.4,
  }) : super(type: AudioEffectType.echo);
}

/// Pitch shift effect (AVAudioUnitTimePitch)
@immutable
class PitchShiftEffect extends AudioEffect {
  /// Pitch shift in semitones: -24 to +24
  final double semitones;

  /// Fine tuning in cents: -50 to +50
  final double cents;

  /// Whether to attempt formant preservation
  final bool preserveFormants;

  const PitchShiftEffect({
    required super.id,
    super.isEnabled,
    super.mix = 1.0,
    this.semitones = 0.0,
    this.cents = 0.0,
    this.preserveFormants = true,
  }) : super(type: AudioEffectType.pitchShift);
}

/// Parametric EQ effect (AVAudioUnitEQ)
@immutable
class EQEffect extends AudioEffect {
  /// Bass gain in dB: -12 to +12
  final double bassGain;

  /// Bass frequency: 60 - 250 Hz
  final double bassFrequency;

  /// Mid gain in dB: -12 to +12
  final double midGain;

  /// Mid frequency: 500 - 4000 Hz
  final double midFrequency;

  /// Mid Q factor: 0.1 - 10.0
  final double midQ;

  /// Treble gain in dB: -12 to +12
  final double trebleGain;

  /// Treble frequency: 4000 - 16000 Hz
  final double trebleFrequency;

  const EQEffect({
    required super.id,
    super.isEnabled,
    super.mix = 1.0,
    this.bassGain = 0.0,
    this.bassFrequency = 100.0,
    this.midGain = 0.0,
    this.midFrequency = 1000.0,
    this.midQ = 1.0,
    this.trebleGain = 0.0,
    this.trebleFrequency = 8000.0,
  }) : super(type: AudioEffectType.eq);
}

/// Compressor effect (AVAudioUnitEffect with kAudioUnitSubType_DynamicsProcessor)
@immutable
class CompressorEffect extends AudioEffect {
  /// Threshold in dB: -60 to 0
  final double threshold;

  /// Compression ratio: 1.0 (no compression) to 20.0 (limiting)
  final double ratio;

  /// Attack time in seconds: 0.001 - 0.5
  final double attack;

  /// Release time in seconds: 0.01 - 2.0
  final double release;

  /// Makeup gain in dB: 0 to 40
  final double makeupGain;

  const CompressorEffect({
    required super.id,
    super.isEnabled,
    super.mix = 1.0,
    this.threshold = -20.0,
    this.ratio = 4.0,
    this.attack = 0.01,
    this.release = 0.1,
    this.makeupGain = 0.0,
  }) : super(type: AudioEffectType.compressor);
}

/// Distortion effect (AVAudioUnitDistortion)
@immutable
class DistortionEffect extends AudioEffect {
  /// Drive amount: 0.0 - 1.0
  final double drive;

  /// Distortion type
  final DistortionType distortionType;

  const DistortionEffect({
    required super.id,
    super.isEnabled,
    super.mix = 0.5,
    this.drive = 0.3,
    this.distortionType = DistortionType.overdrive,
  }) : super(type: AudioEffectType.distortion);
}

enum DistortionType { overdrive, fuzz, bitcrush }

/// Noise gate effect (custom implementation via AVAudioUnitEffect)
@immutable
class NoiseGateEffect extends AudioEffect {
  /// Threshold in dB below which audio is gated: -80 to 0
  final double threshold;

  /// Attack time in seconds: 0.0001 - 0.1
  final double attack;

  /// Release time in seconds: 0.01 - 1.0
  final double release;

  const NoiseGateEffect({
    required super.id,
    super.isEnabled,
    super.mix = 1.0,
    this.threshold = -40.0,
    this.attack = 0.005,
    this.release = 0.05,
  }) : super(type: AudioEffectType.noiseGate);
}
```

### 2.4 VolumeEnvelope Enhancements

The existing `VolumeEnvelope` and `VolumeKeyframe` models in `lib/timeline/data/models/volume_keyframe.dart` are well-designed but need curve interpolation support beyond linear.

```dart
/// Interpolation type between volume keyframes
enum VolumeInterpolation {
  /// Straight line between points
  linear,

  /// Smooth bezier curve
  bezier,

  /// Instant jump (hold previous value until next keyframe)
  hold,
}

/// Enhanced volume keyframe with interpolation type
@immutable
class VolumeKeyframe {
  final String id;
  final TimeMicros time;
  final double volume;  // 0.0 - 2.0 (supports boost up to 200%)

  /// Interpolation to the NEXT keyframe
  final VolumeInterpolation interpolation;

  /// Bezier control points (normalized 0-1 within segment)
  /// Only used when interpolation == VolumeInterpolation.bezier
  final (double, double)? bezierControlIn;
  final (double, double)? bezierControlOut;

  const VolumeKeyframe({
    required this.id,
    required this.time,
    required this.volume,
    this.interpolation = VolumeInterpolation.linear,
    this.bezierControlIn,
    this.bezierControlOut,
  });
}
```

**Migration note:** The existing `VolumeEnvelope.getVolumeAt()` method currently does linear interpolation. The enhanced version checks `kf.interpolation` to select the curve. Default (`linear`) preserves backward compatibility.

### 2.5 WaveformData Model

Already exists in `lib/timeline/cache/waveform_cache.dart` with multi-LOD support. No model changes needed -- only the native extraction pipeline needs to be wired up.

```
Existing: WaveformData { samples: Float32List, sampleRate, durationMicros, lod }
Existing: WaveformLOD { low (100ms/sample), medium (10ms/sample), high (1ms/sample) }
Existing: WaveformCache { LRU eviction, async generation, multi-LOD fallback }
```

### 2.6 AudioTrack Model

Already exists as `Track` model in `lib/timeline/data/models/track.dart`. The existing `TrackType` enum already includes `audio`, `music`, and `voiceover` with appropriate colors (green, teal, orange). The `Track` model already supports `isMuted`, `isSolo`, `isLocked`, `height`, and `isCollapsed`.

New field needed on `Track`:

```dart
/// Per-track volume (0.0 - 2.0, default 1.0)
/// Applied as a multiplier on top of individual clip volumes
final double trackVolume;
```

### 2.7 BeatMap Model

```dart
/// Detected beats from audio analysis
@immutable
class BeatMap {
  /// Asset ID this beat map was generated from
  final String assetId;

  /// Detected beat timestamps (microseconds, sorted ascending)
  final List<int> beats;

  /// Estimated tempo in BPM (beats per minute)
  final double estimatedBPM;

  /// Confidence of tempo estimate (0.0 - 1.0)
  final double confidence;

  /// Time signature numerator (e.g., 4 for 4/4)
  final int timeSignatureNumerator;

  /// Time signature denominator (e.g., 4 for 4/4)
  final int timeSignatureDenominator;

  const BeatMap({
    required this.assetId,
    required this.beats,
    required this.estimatedBPM,
    this.confidence = 0.0,
    this.timeSignatureNumerator = 4,
    this.timeSignatureDenominator = 4,
  });

  /// Get beat nearest to a given time (binary search)
  int? nearestBeat(int timeMicros) {
    if (beats.isEmpty) return null;
    // Binary search for closest beat
    int lo = 0, hi = beats.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (beats[mid] < timeMicros) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    // Compare lo and lo-1 to find closest
    if (lo == 0) return beats[0];
    final before = beats[lo - 1];
    final after = beats[lo];
    return (timeMicros - before).abs() <= (after - timeMicros).abs() ? before : after;
  }

  /// Get beats within a time range (for visible region rendering)
  List<int> beatsInRange(int startMicros, int endMicros) {
    // Binary search for start index, then scan forward
    // ... efficient O(log n + k) where k = beats in range
  }

  Map<String, dynamic> toJson();
  factory BeatMap.fromJson(Map<String, dynamic> json);
}
```

### 2.8 SoundEffect Model (Bundled SFX)

```dart
/// Category of bundled sound effect
enum SFXCategory {
  transitions,  // Whoosh, swoosh, swipe
  ui,           // Click, pop, beep, notification
  impacts,      // Hit, thud, crash, slam
  nature,       // Rain, wind, birds, waves
  ambience,     // Room tone, crowd, traffic
  musical,      // Stinger, riser, drop
  foley,        // Footstep, door, rustle
}

/// Metadata for a bundled sound effect
@immutable
class SoundEffectAsset {
  /// Unique identifier
  final String id;

  /// Display name
  final String name;

  /// Category for browsing
  final SFXCategory category;

  /// Duration in microseconds
  final int durationMicros;

  /// Asset bundle path (relative to assets/)
  final String assetPath;

  /// Tags for search
  final List<String> tags;

  /// Preview waveform (pre-computed, low LOD)
  final List<double>? previewSamples;

  const SoundEffectAsset({
    required this.id,
    required this.name,
    required this.category,
    required this.durationMicros,
    required this.assetPath,
    this.tags = const [],
    this.previewSamples,
  });
}
```

### 2.9 NoiseProfile Model

```dart
/// Captured noise profile for noise reduction
@immutable
class NoiseProfile {
  /// ID for caching and reference
  final String id;

  /// Source asset ID the profile was captured from
  final String assetId;

  /// Start time of the noise sample (microseconds)
  final int startMicros;

  /// End time of the noise sample (microseconds)
  final int endMicros;

  /// Spectral data (FFT magnitudes per frequency bin)
  /// This is the native-side reference; Dart only holds metadata
  final String nativeProfileHandle;

  const NoiseProfile({
    required this.id,
    required this.assetId,
    required this.startMicros,
    required this.endMicros,
    required this.nativeProfileHandle,
  });
}
```

### 2.10 AudioDuckingConfig Model

```dart
/// Configuration for automatic audio ducking
@immutable
class AudioDuckingConfig {
  /// Whether ducking is enabled
  final bool isEnabled;

  /// Target track ID to duck (usually music track)
  final String targetTrackId;

  /// Trigger track ID (usually voiceover track)
  final String triggerTrackId;

  /// Amount to reduce volume in dB (negative value, e.g., -12)
  final double duckAmountDB;

  /// Attack time: how fast to duck (milliseconds)
  final int attackMs;

  /// Release time: how fast to restore (milliseconds)
  final int releaseMs;

  /// Threshold for speech detection (0.0 - 1.0)
  final double speechThreshold;

  const AudioDuckingConfig({
    this.isEnabled = true,
    required this.targetTrackId,
    required this.triggerTrackId,
    this.duckAmountDB = -12.0,
    this.attackMs = 200,
    this.releaseMs = 500,
    this.speechThreshold = 0.3,
  });
}
```

---

## 3. Architecture

### 3.1 Component Architecture Diagram

```
Flutter Layer
==============================================================================

  AudioController ◄──── TimelineManager (undo/redo)
  ├── WaveformController (manages WaveformCache)
  ├── EffectsController (manages effect chain state)
  ├── EnvelopeEditor (volume keyframe UI state)
  ├── BeatMapController (manages BeatMap cache)
  ├── VoiceoverController (recording state machine)
  └── DuckingController (auto-ducking state)

  ClipsPainter (extended)
  ├── drawWaveform() ◄── WaveformCache
  ├── drawFadeOverlay()
  ├── drawVolumeEnvelope()
  └── drawBeatMarkers() ◄── BeatMap

==============================================================================
                        Platform Channels
==============================================================================
  com.liquideditor/audio_waveform     - Waveform extraction
  com.liquideditor/audio_effects      - Effect graph management
  com.liquideditor/audio_recording    - Voiceover recording
  com.liquideditor/audio_analysis     - Beat detection, noise profiling
  com.liquideditor/audio_ducking      - Speech detection + auto-ducking
  com.liquideditor/audio_export       - Audio-only export
==============================================================================

Native Layer (Swift)
==============================================================================
  WaveformExtractor
  ├── AVAssetReader + AudioBufferList
  ├── Accelerate vDSP for peak detection
  └── Multi-LOD output

  AudioEffectsEngine
  ├── AVAudioEngine graph management
  ├── Per-clip effect chain nodes
  └── Real-time preview rendering

  BeatDetector
  ├── Accelerate vDSP FFT
  ├── Onset detection (spectral flux)
  └── Tempo estimation (autocorrelation)

  VoiceoverRecorder
  ├── AVAudioSession management
  ├── AVAudioEngine input node
  └── File writer (AVAudioFile)

  AudioDuckingEngine
  ├── Voice Activity Detection (energy + zero-crossing)
  └── Envelope follower for smooth ducking

  NoiseReductionProcessor
  ├── Noise profiling (spectral average)
  └── Spectral subtraction

  CompositionBuilder (existing, extended)
  ├── Multi-track audio insertion
  ├── Per-track volume via AVMutableAudioMix
  ├── Fade application via volume ramp
  └── Effect baking during export
==============================================================================
```

### 3.2 AudioController (Flutter)

Central coordinator for all audio state. Uses `ChangeNotifier` consistent with the existing `provider`-based state management.

```dart
class AudioController extends ChangeNotifier {
  final TimelineManager _timelineManager;
  final WaveformCache _waveformCache;

  // Beat maps per asset
  final Map<String, BeatMap> _beatMaps = {};

  // Noise profiles per asset
  final Map<String, NoiseProfile> _noiseProfiles = {};

  // Ducking configuration
  AudioDuckingConfig? _duckingConfig;

  // Recording state
  bool _isRecording = false;
  int _recordingStartMicros = 0;

  // Platform channel
  static const _audioChannel = MethodChannel('com.liquideditor/audio_waveform');
  static const _effectsChannel = MethodChannel('com.liquideditor/audio_effects');
  static const _analysisChannel = MethodChannel('com.liquideditor/audio_analysis');
  static const _recordingChannel = MethodChannel('com.liquideditor/audio_recording');
  static const _duckingChannel = MethodChannel('com.liquideditor/audio_ducking');

  // --- Waveform ---
  void requestWaveform(String assetId) { ... }
  Float32List getWaveformSamples(String assetId, int startMicros, int endMicros, int targetSamples, double microsPerPixel) { ... }

  // --- Effects ---
  void addEffect(String clipId, AudioEffect effect) { ... }
  void removeEffect(String clipId, String effectId) { ... }
  void updateEffect(String clipId, AudioEffect effect) { ... }
  void reorderEffects(String clipId, int oldIndex, int newIndex) { ... }

  // --- Fades ---
  void setFadeIn(String clipId, AudioFade fade) { ... }
  void setFadeOut(String clipId, AudioFade fade) { ... }
  void removeFadeIn(String clipId) { ... }
  void removeFadeOut(String clipId) { ... }

  // --- Detach ---
  Future<void> detachAudio(String videoClipId) async { ... }
  void relinkAudio(String audioClipId, String videoClipId) { ... }

  // --- Beat detection ---
  Future<BeatMap> detectBeats(String assetId) async { ... }

  // --- Voiceover ---
  Future<void> startRecording(int timelineMicros) async { ... }
  Future<AudioClip> stopRecording() async { ... }

  // --- Ducking ---
  void configureDucking(AudioDuckingConfig config) { ... }
  Future<VolumeEnvelope> generateDuckingEnvelope(String triggerTrackId, String targetTrackId) async { ... }

  // --- Noise reduction ---
  Future<NoiseProfile> captureNoiseProfile(String assetId, int startMicros, int endMicros) async { ... }
  void applyNoiseReduction(String clipId, NoiseProfile profile, double amount) { ... }
}
```

### 3.3 Platform Channel API

#### `com.liquideditor/audio_waveform`

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `extractWaveform` | `{assetPath: String, lod: String, sampleRate: int}` | `{samples: Float32List, duration: int}` | Extract peak amplitude samples |

#### `com.liquideditor/audio_effects`

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `setupEffectChain` | `{clipId: String, effects: List<Map>}` | `{success: bool}` | Configure effect graph for preview |
| `removeEffectChain` | `{clipId: String}` | `{success: bool}` | Tear down effect graph |
| `previewEffect` | `{clipId: String, effectId: String, params: Map}` | `{success: bool}` | Update single effect for real-time preview |

#### `com.liquideditor/audio_recording`

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `prepareRecording` | `{outputPath: String, sampleRate: int}` | `{success: bool}` | Set up recording session |
| `startRecording` | `{}` | `{success: bool}` | Begin recording |
| `stopRecording` | `{}` | `{filePath: String, durationMicros: int}` | Stop and return recorded file |
| `getInputLevel` | `{}` | `{level: double}` | Get current mic input level (0.0-1.0) |
| `setMonitoringEnabled` | `{enabled: bool}` | `{success: bool}` | Enable/disable audio monitoring |

#### `com.liquideditor/audio_analysis`

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `detectBeats` | `{assetPath: String}` | `{beats: List<int>, bpm: double, confidence: double}` | Run beat detection |
| `captureNoiseProfile` | `{assetPath: String, startMicros: int, endMicros: int}` | `{profileHandle: String}` | Capture noise spectral profile |
| `applyNoiseReduction` | `{assetPath: String, profileHandle: String, amount: double, outputPath: String}` | `{success: bool}` | Apply noise reduction to file |

#### `com.liquideditor/audio_ducking`

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `detectSpeech` | `{assetPath: String, threshold: double}` | `{segments: List<{start: int, end: int}>}` | Detect speech segments |
| `generateDuckingEnvelope` | `{speechSegments: List<Map>, duckDB: double, attackMs: int, releaseMs: int}` | `{keyframes: List<{time: int, volume: double}>}` | Generate volume envelope for ducking |

---

## 4. Waveform Visualization

### 4.1 Native Extraction Pipeline

The native waveform extractor uses `AVAssetReader` with `AudioBufferList` to read PCM samples, then `Accelerate` framework's `vDSP` functions for efficient peak detection.

**Swift Implementation (WaveformExtractor.swift):**

```swift
class WaveformExtractor {

    /// Extract waveform at specified LOD
    func extractWaveform(
        assetPath: String,
        lod: WaveformLOD,
        completion: @escaping (Result<WaveformResult, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let asset = AVURLAsset(url: URL(fileURLWithPath: assetPath))
                guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
                    throw WaveformError.noAudioTrack
                }

                let reader = try AVAssetReader(asset: asset)

                // Request PCM Float32 output
                let outputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,  // Mono downmix
                ]

                let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
                reader.add(output)
                reader.startReading()

                // Calculate samples per bucket based on LOD
                let samplesPerBucket = lod.samplesPerBucket(sampleRate: 44100)
                var peaks: [Float] = []
                var sampleBuffer: [Float] = []

                while reader.status == .reading {
                    guard let buffer = output.copyNextSampleBuffer(),
                          let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else {
                        continue
                    }

                    // Extract float samples from buffer
                    var dataPointer: UnsafeMutablePointer<Int8>?
                    var length = 0
                    CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

                    let floatCount = length / MemoryLayout<Float>.size
                    let floatPointer = UnsafeRawPointer(dataPointer!).bindMemory(to: Float.self, capacity: floatCount)

                    sampleBuffer.append(contentsOf: UnsafeBufferPointer(start: floatPointer, count: floatCount))

                    // Process complete buckets
                    while sampleBuffer.count >= samplesPerBucket {
                        let bucket = Array(sampleBuffer.prefix(samplesPerBucket))
                        sampleBuffer.removeFirst(samplesPerBucket)

                        // Use vDSP for peak detection
                        var peak: Float = 0
                        vDSP_maxmgv(bucket, 1, &peak, vDSP_Length(bucket.count))
                        peaks.append(peak)
                    }

                    CMSampleBufferInvalidate(buffer)
                }

                // Process remaining samples
                if !sampleBuffer.isEmpty {
                    var peak: Float = 0
                    vDSP_maxmgv(sampleBuffer, 1, &peak, vDSP_Length(sampleBuffer.count))
                    peaks.append(peak)
                }

                // Normalize peaks to 0.0 - 1.0
                var maxPeak: Float = 0
                vDSP_maxv(peaks, 1, &maxPeak, vDSP_Length(peaks.count))
                if maxPeak > 0 {
                    var divisor = maxPeak
                    vDSP_vsdiv(peaks, 1, &divisor, &peaks, 1, vDSP_Length(peaks.count))
                }

                let durationMicros = Int(CMTimeGetSeconds(asset.duration) * 1_000_000)

                DispatchQueue.main.async {
                    completion(.success(WaveformResult(
                        samples: peaks,
                        sampleRate: 44100 / samplesPerBucket,
                        durationMicros: durationMicros,
                        lod: lod
                    )))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
```

### 4.2 Waveform Cache Integration

The existing `WaveformCache` in `lib/timeline/cache/waveform_cache.dart` is fully functional. The `waveformGenerator` callback needs to be wired to the native platform channel:

```dart
// In AudioController initialization:
_waveformCache.waveformGenerator = (assetId, lod) async {
  final assetPath = _assetRegistry.getPath(assetId);
  if (assetPath == null) return null;

  final result = await _audioChannel.invokeMethod('extractWaveform', {
    'assetPath': assetPath,
    'lod': lod.name,
    'sampleRate': 44100,
  });

  return WaveformData(
    samples: Float32List.fromList((result['samples'] as List).cast<double>().map((d) => d.toDouble()).toList()),
    sampleRate: result['sampleRate'] as int,
    durationMicros: result['duration'] as int,
    lod: lod,
  );
};
```

### 4.3 Flutter Rendering

Waveform drawing is added to `ClipsPainter` for clips where `clip.type.showsWaveform` is true, and also for video clips that have audio (`clip.hasAudio`).

```dart
void _drawWaveform(Canvas canvas, TimelineClip clip, Rect rect, WaveformCache waveformCache) {
  if (clip.mediaAssetId == null) return;

  final targetSamples = rect.width.round();
  if (targetSamples <= 0) return;

  final samples = waveformCache.getWaveformSamples(
    clip.mediaAssetId!,
    clip.sourceIn,
    clip.sourceOut,
    targetSamples,
    viewport.microsPerPixel,
  );

  if (samples.isEmpty) return;

  // Color: green for audio clips, blue-tinted for video audio
  final waveformColor = clip.type == ClipType.audio
      ? const Color(0x8034C759)  // Green, semi-transparent
      : const Color(0x60007AFF); // Blue, more transparent

  final waveformPaint = Paint()
    ..color = waveformColor
    ..style = PaintingStyle.fill;

  final centerY = rect.center.dy;
  final maxHeight = rect.height * 0.8;
  final sampleWidth = rect.width / samples.length;

  // Draw waveform as symmetric bars
  for (int i = 0; i < samples.length; i++) {
    final amplitude = samples[i] * maxHeight / 2;
    final x = rect.left + i * sampleWidth;

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(x + sampleWidth / 2, centerY),
        width: sampleWidth.clamp(1.0, 3.0),
        height: amplitude.clamp(1.0, maxHeight),
      ),
      waveformPaint,
    );
  }
}
```

### 4.4 Fade Overlay Rendering

When a clip has `fadeIn` or `fadeOut`, a dimming gradient is drawn on top of the waveform:

```dart
void _drawFadeOverlay(Canvas canvas, TimelineClip clip, Rect rect) {
  // Fade in: gradient from transparent-black to transparent at clip start
  if (clip has fadeIn) {
    final fadeWidth = fadeInDuration / viewport.microsPerPixel;
    final fadeRect = Rect.fromLTWH(rect.left, rect.top, fadeWidth, rect.height);

    final gradient = LinearGradient(
      colors: [const Color(0x80000000), const Color(0x00000000)],
    );
    canvas.drawRect(fadeRect, Paint()..shader = gradient.createShader(fadeRect));
  }

  // Fade out: similar at clip end
}
```

### 4.5 Dynamic Detail Based on Zoom

The existing `WaveformLOD.selectForZoom()` in `WaveformCache` already handles this:
- Zoomed out (> 50ms/pixel): `WaveformLOD.low` (1 sample per 100ms)
- Medium zoom (5-50ms/pixel): `WaveformLOD.medium` (1 sample per 10ms)
- Zoomed in (< 5ms/pixel): `WaveformLOD.high` (1 sample per 1ms)

### 4.6 Memory Budget

| LOD | Samples per minute | Bytes per minute | 30min project |
|-----|-------------------|-----------------|---------------|
| Low | 600 | 2.4 KB | 72 KB |
| Medium | 6,000 | 24 KB | 720 KB |
| High | 60,000 | 240 KB | 7.2 MB |

The `WaveformCache` has a default 20MB budget, accommodating extensive multi-track waveform data.

---

## 5. Audio Detach

### 5.1 Operation Flow

1. User selects a `VideoClip` on the timeline
2. User taps "Detach Audio" in the context menu
3. System creates a new `AudioClip` with matching source range and asset
4. The `VideoClip` is updated with `isMuted = true`
5. Both clips get `linkedClipId` references to each other (existing field on `TimelineClip`)
6. The `AudioClip` is placed on the first available audio track, aligned to the video clip's timeline position
7. The operation is a single atomic `TimelineManager` mutation (undoable)

### 5.2 Implementation

```dart
/// In AudioController
Future<void> detachAudio(String videoClipId) async {
  final videoClip = _timelineManager.getClipById(videoClipId);
  if (videoClip == null || !videoClip.hasAudio) return;

  // Find or create an audio track
  final audioTrack = _findOrCreateAudioTrack();

  // Create new AudioClip from video's audio
  final audioClip = AudioClip(
    id: const Uuid().v4(),
    mediaAssetId: videoClip.mediaAssetId,
    sourceInMicros: videoClip.sourceInMicros,
    sourceOutMicros: videoClip.sourceOutMicros,
    name: '${videoClip.name ?? "Video"} Audio',
    volume: videoClip.volume,
    linkedVideoClipId: videoClipId,
    speed: videoClip.speed,
  );

  // Atomic mutation: mute video + insert audio clip
  _timelineManager.beginCompoundEdit('Detach Audio');
  _timelineManager.updateClip(videoClipId, isMuted: true, linkedClipId: audioClip.id);
  _timelineManager.insertClip(audioClip, trackId: audioTrack.id, atTime: videoClipStartTime);
  _timelineManager.endCompoundEdit();

  // Trigger waveform extraction for the new clip
  _waveformCache.preload(audioClip.mediaAssetId);
}
```

### 5.3 Linked Clip Behavior

| Video operation | Audio reaction |
|----------------|----------------|
| Move video | Audio moves too (linked) |
| Trim video head | Audio head trims in sync |
| Trim video tail | Audio tail trims in sync |
| Delete video | Audio becomes unlinked (orphaned, not deleted) |
| Change video speed | Audio speed updated to match |
| Unlink explicitly | Both clips become independent |

The `linkedClipId` field already exists on `TimelineClip`. The timeline engine checks for linked clips during move, trim, and speed operations and applies symmetric changes.

### 5.4 Re-linking

User can select a detached audio clip and a video clip, then choose "Link Audio to Video". This sets `linkedClipId` on both and unmutes the video if it was muted during detach (user choice via confirmation dialog).

---

## 6. Multiple Audio Tracks

### 6.1 Track Layout

The existing `Track` model already supports multiple track types. Default track layout:

| Index | Track | Type | Color | Purpose |
|-------|-------|------|-------|---------|
| 0 | Main Video | `mainVideo` | Purple | Primary video + embedded audio |
| 1 | Audio 1 | `audio` | Green | Detached audio, SFX |
| 2 | Music | `music` | Teal | Background music |
| 3 | Voiceover | `voiceover` | Orange | Narration, dialogue |

Users can add up to 6 total audio tracks (1 embedded video audio + 5 additional). Adding more tracks beyond 6 shows a warning about device performance.

### 6.2 Track Management UI

Track management uses a `CupertinoContextMenu` on the track header area:

- **Add Track** - submenu: Audio, Music, Voiceover
- **Delete Track** - removes empty track (confirmation if clips present)
- **Rename Track** - `CupertinoTextField` inline edit
- **Reorder Tracks** - drag handle on track header

### 6.3 Track Header Widget

Each audio track header shows (vertically compact, 64px height):

```
+------------------+
| [M] [S] [L]      |  <- Mute / Solo / Lock toggle buttons
| Music       ▼    |  <- Name + volume dropdown
| ■■■■■■░░░░ 75%  |  <- Mini volume bar
+------------------+
```

All buttons use `CupertinoButton` with SF Symbol icons:
- Mute: `speaker.slash.fill` / `speaker.fill`
- Solo: `headphones` (tinted when active)
- Lock: `lock.fill` / `lock.open.fill`

### 6.4 Audio Mixing

All audio is mixed at composition build time via `AVMutableAudioMix`:

```
Final Volume = clipVolume * trackVolume * envelopeVolume * fadeMultiplier * (isMuted ? 0 : 1)
```

The `CompositionBuilder` already creates `AVMutableAudioMixInputParameters` per track. For multi-track, each audio track gets its own `AVMutableCompositionTrack` (audio type) and corresponding mix parameters.

### 6.5 Impact on AVMutableComposition

Current `CompositionBuilder` creates a single video track and single audio track. For multi-track audio:

```swift
// In CompositionBuilder.build()
// Create one audio composition track per timeline audio track
var audioTracks: [String: AVMutableCompositionTrack] = [:]

for track in timelineTracks where track.type.supportsAudio {
    if let compTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ) {
        audioTracks[track.id] = compTrack
    }
}
```

AVFoundation supports up to 16 audio tracks per composition. Our limit of 6 is well within bounds.

---

## 7. Volume Keyframing (Envelope Editor)

### 7.1 Visual Design

The volume envelope is rendered as a rubber-band line overlaid on the clip waveform:

```
Clip (with waveform):
+------------------------------------------------------------------+
|  ●━━━━━━━━━━●                    ●━━━━━━━━━━━━━●                 |
|             ╲                  ╱                 ╲                |
|  ▓▓▓▓▓▓▓▓▓▓ ╲  ▓▓▓▓▓▓▓▓▓▓ ╱  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ╲  ▓▓▓▓▓▓     |
|  ▓▓▓▓▓▓▓▓▓▓  ●━━━━━━━━━━━●   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓    ●━━━━━━●     |
|  ▓ waveform ▓              ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓              ▓  |
+------------------------------------------------------------------+
  ●  = Volume keyframe (draggable control point)
  ━  = Volume envelope line
  ▓  = Waveform (dimmed proportionally below envelope)
```

- **Control points (●):** Rendered as 12px circles, `CupertinoColors.systemCyan` fill with white border
- **Envelope line:** 2px stroke, `CupertinoColors.systemCyan` with 80% opacity
- **Fill below line:** Semi-transparent fill showing effective volume area
- **Drag handles:** Expand to 44pt touch target (iOS HIG minimum)

### 7.2 Interaction

| Gesture | Action |
|---------|--------|
| Tap on envelope line | Add new keyframe at tap position |
| Drag keyframe | Move time and/or volume (clamped to clip bounds) |
| Double-tap keyframe | Show keyframe editor popup (exact value input) |
| Long-press keyframe | Delete keyframe (with haptic confirmation) |
| Pinch on segment | Adjust curve tension (bezier only) |

### 7.3 Integration with Existing VolumeEnvelope

The existing `VolumeEnvelope` class already supports `addKeyframe`, `removeKeyframe`, `updateKeyframe`, and `getVolumeAt()` with linear interpolation. The enhancement adds:

1. `VolumeInterpolation` enum on each keyframe (linear, bezier, hold)
2. Bezier control points for smooth curves
3. Volume range expanded to 0.0 - 2.0 (200% boost)

### 7.4 Export Application

During composition building, the volume envelope is converted to `AVMutableAudioMixInputParameters.setVolumeRamp()` calls:

```swift
// For each pair of adjacent keyframes:
params.setVolumeRamp(
    fromStartVolume: startVolume,
    toEndVolume: endVolume,
    timeRange: CMTimeRange(start: startTime, duration: duration)
)
```

For bezier curves, the ramp is approximated with multiple linear segments (8 segments per curve, yielding sub-ms accuracy at 30fps).

---

## 8. Audio Fade In/Out

### 8.1 UI: Fade Handles

Fade handles appear on the top edge of audio/video clips when selected:

```
Fade-in handle        Fade-out handle
      ▼                     ▼
   ╭──╮                  ╭──╮
   │◀━│═══════════════════│━▶│
   ╰──╯                  ╰──╯
+--▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓+
|  ░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░ |  <- Waveform with fade dimming
+--▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓+
```

- **Handle appearance:** 8x20px rounded rectangle, white fill, positioned at top edge of clip
- **Fade-in handle** starts at clip left edge, drag right to increase fade duration
- **Fade-out handle** starts at clip right edge, drag left to increase fade duration
- **Visual:** Dimmed gradient overlay on waveform in fade region
- **Minimum drag:** 2 frames (~66ms)
- **Maximum drag:** Half the clip duration
- **Haptic:** `HapticFeedback.selectionClick()` at snap points (0.25s, 0.5s, 1.0s, 2.0s)

### 8.2 Fade Curve Selection

After creating a fade by dragging, tapping the fade region shows a `CupertinoActionSheet` with curve options:

```
Choose Fade Curve
─────────────────
  Linear        ╱
  S-Curve       ~
  Logarithmic   ⌒
  Equal Power   ∿
  Exponential   ∟
─────────────────
  [Cancel]
```

### 8.3 Integration with Volume Envelope

Fades are conceptually auto-generated volume envelope points at clip boundaries. When a fade is set:

1. If the clip has no envelope: Fade generates implicit envelope (not stored as explicit keyframes, applied separately during composition build)
2. If the clip has an envelope: Fade multiplies with the envelope curve (both applied)

This keeps fades and envelope as independent, composable layers:

```
Effective Volume = baseVolume * fadeMultiplier * envelopeMultiplier
```

### 8.4 Crossfade Between Adjacent Clips

When two audio clips on the same track overlap (or are adjacent), users can apply a crossfade:

1. Select both clips
2. Choose "Crossfade" from context menu
3. The existing `ClipTransition` model with `TransitionType.crossfade` handles this
4. Left clip gets auto fade-out, right clip gets auto fade-in
5. Duration and curve type are inherited from the transition
6. The `crossfade` transition type already has `supportsAudio: true` in the existing model

---

## 9. Voiceover Recording

### 9.1 State Machine

```
[Idle] ──(prepare)──> [Preparing]
                          │
                      (ready)
                          │
                          ▼
                     [Ready] ──(countdown)──> [Countdown 3-2-1]
                                                      │
                                                  (start)
                                                      │
                                                      ▼
                                                 [Recording]
                                                      │
                                                  (stop)
                                                      │
                                                      ▼
                                                  [Saving]
                                                      │
                                                  (saved)
                                                      │
                                                      ▼
                                                 [Complete]
                                                 (clip created)
```

### 9.2 Recording UI

During recording, a floating overlay appears above the timeline:

```
+--------------------------------------------------+
|  🔴 Recording        00:05.23                     |
|  ┃                                                |
|  ┃  ████████████████████████████                  |  <- VU meter
|  ┃                                                |
|  [Cancel]                           [Stop ■]      |
+--------------------------------------------------+
```

- **Red dot:** Animated pulsing indicator
- **Timer:** Elapsed recording time
- **VU meter:** Real-time input level (updates at 30fps via platform channel events)
- **Cancel:** Discards recording, returns to idle
- **Stop:** Saves recording, creates AudioClip

All elements use Liquid Glass styling (BackdropFilter blur, semi-transparent container).

### 9.3 Pre-roll Countdown

Before recording starts, a 3-2-1 countdown overlay appears centered on the video preview:

```
    ╭───╮
    │ 3 │  <- Large, animated number
    ╰───╯
```

Each number shows for 1 second with a scale-down animation. Haptic feedback (`HapticFeedback.heavyImpact()`) on each count.

### 9.4 Native Implementation

```swift
class VoiceoverRecorder {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }

    /// Prepare the recording session
    func prepare(outputPath: String, sampleRate: Double = 44100) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        audioFile = try AVAudioFile(
            forWriting: URL(fileURLWithPath: outputPath),
            settings: format.settings
        )
    }

    /// Start recording
    func start() throws {
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            try? self?.audioFile?.write(from: buffer)

            // Calculate input level for VU meter
            let level = self?.calculatePeakLevel(buffer: buffer) ?? 0
            // Send to Flutter via event channel
        }

        try audioEngine.start()
    }

    /// Stop recording
    func stop() -> (filePath: String, durationMicros: Int) {
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        let filePath = audioFile?.url.path ?? ""
        let duration = audioFile?.length ?? 0
        let sampleRate = audioFile?.processingFormat.sampleRate ?? 44100
        let durationMicros = Int(Double(duration) / sampleRate * 1_000_000)

        audioFile = nil
        return (filePath, durationMicros)
    }

    private func calculatePeakLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        var peak: Float = 0
        vDSP_maxmgv(data, 1, &peak, vDSP_Length(buffer.frameLength))
        return peak
    }
}
```

### 9.5 After Recording

1. Recording file is saved to `Documents/voiceovers/{projectId}/{uuid}.m4a`
2. A `MediaAsset` is created for the recording
3. An `AudioClip` is created and placed on the voiceover track
4. The clip starts at the timeline position where recording began
5. Waveform extraction is triggered automatically

### 9.6 Punch-In Recording

User can start recording at a specific timeline position (the playhead position). The video plays back during recording so the user can narrate to picture. Audio monitoring is enabled by default (hear yourself through headphones).

Latency compensation: The recording start is offset by the measured audio input latency (typically 5-15ms on iOS). This value is obtained from `AVAudioSession.inputLatency`.

---

## 10. Audio Effects

### 10.1 Effect Chain Architecture

Each audio clip can have an ordered list of effects. The chain is:

```
Source Audio ──> [Effect 1] ──> [Effect 2] ──> ... ──> [Effect N] ──> Volume ──> Output
```

On the native side, each clip's effect chain maps to an `AVAudioEngine` subgraph:

```swift
class AudioEffectChain {
    let playerNode: AVAudioPlayerNode
    var effectNodes: [AVAudioNode] = []
    let mixerNode: AVAudioMixerNode

    func buildGraph(engine: AVAudioEngine, effects: [EffectDescriptor]) {
        // Connect: player -> effect1 -> effect2 -> ... -> mixer -> mainMixer
        var previousNode: AVAudioNode = playerNode

        for effect in effects {
            let node = createNode(for: effect)
            engine.attach(node)
            engine.connect(previousNode, to: node, format: format)
            effectNodes.append(node)
            previousNode = node
        }

        engine.connect(previousNode, to: mixerNode, format: format)
        engine.connect(mixerNode, to: engine.mainMixerNode, format: format)
    }

    func createNode(for descriptor: EffectDescriptor) -> AVAudioNode {
        switch descriptor.type {
        case .reverb:
            let node = AVAudioUnitReverb()
            node.loadFactoryPreset(.largeHall2)
            node.wetDryMix = Float(descriptor.mix * 100)
            return node
        case .echo:
            let node = AVAudioUnitDelay()
            node.delayTime = descriptor.delayTime
            node.feedback = Float(descriptor.feedback * 100)
            node.wetDryMix = Float(descriptor.mix * 100)
            return node
        case .pitchShift:
            let node = AVAudioUnitTimePitch()
            node.pitch = Float(descriptor.semitones * 100 + descriptor.cents)
            return node
        case .eq:
            let node = AVAudioUnitEQ(numberOfBands: 3)
            configureBands(node, descriptor)
            return node
        case .compressor:
            // Use AUAudioUnit with kAudioUnitSubType_DynamicsProcessor
            ...
        case .distortion:
            let node = AVAudioUnitDistortion()
            node.loadFactoryPreset(descriptor.presetForType)
            node.wetDryMix = Float(descriptor.mix * 100)
            return node
        case .noiseGate:
            // Custom implementation via AVAudioUnitEffect
            ...
        }
    }
}
```

### 10.2 Effect Parameters and Ranges

| Effect | Parameter | Range | Default | Unit |
|--------|-----------|-------|---------|------|
| **Reverb** | Room Size | 0.0 - 1.0 | 0.5 | normalized |
| | Damping | 0.0 - 1.0 | 0.5 | normalized |
| | Mix | 0.0 - 1.0 | 0.3 | wet/dry |
| **Echo** | Delay Time | 0.01 - 2.0 | 0.3 | seconds |
| | Feedback | 0.0 - 0.95 | 0.4 | normalized |
| | Mix | 0.0 - 1.0 | 0.3 | wet/dry |
| **Pitch Shift** | Semitones | -24 - +24 | 0 | semitones |
| | Cents | -50 - +50 | 0 | cents |
| | Formant Preservation | on/off | on | boolean |
| **EQ (3-band)** | Bass Gain | -12 - +12 | 0 | dB |
| | Bass Freq | 60 - 250 | 100 | Hz |
| | Mid Gain | -12 - +12 | 0 | dB |
| | Mid Freq | 500 - 4000 | 1000 | Hz |
| | Mid Q | 0.1 - 10.0 | 1.0 | Q factor |
| | Treble Gain | -12 - +12 | 0 | dB |
| | Treble Freq | 4000 - 16000 | 8000 | Hz |
| **Compressor** | Threshold | -60 - 0 | -20 | dB |
| | Ratio | 1.0 - 20.0 | 4.0 | ratio |
| | Attack | 0.001 - 0.5 | 0.01 | seconds |
| | Release | 0.01 - 2.0 | 0.1 | seconds |
| | Makeup Gain | 0 - 40 | 0 | dB |
| **Distortion** | Drive | 0.0 - 1.0 | 0.3 | normalized |
| | Type | overdrive/fuzz/bitcrush | overdrive | enum |
| | Mix | 0.0 - 1.0 | 0.5 | wet/dry |
| **Noise Gate** | Threshold | -80 - 0 | -40 | dB |
| | Attack | 0.0001 - 0.1 | 0.005 | seconds |
| | Release | 0.01 - 1.0 | 0.05 | seconds |

### 10.3 Effect UI Controls

Each effect is shown as a card in a `CupertinoListSection`:

```
+--------------------------------------------------+
|  ≡  Reverb                        [On/Off] [×]   |
|  ──────────────────────────────────────────────── |
|  Room Size    ○━━━━━━━━━━━━━━●━━━━━━━━━━○  0.65  |
|  Damping      ○━━━━━━●━━━━━━━━━━━━━━━━━━○  0.40  |
|  Mix          ○━━━━━━━━━━━●━━━━━━━━━━━━━○  0.30  |
+--------------------------------------------------+
```

- `≡` drag handle for reordering effects
- `[On/Off]` toggle: `CupertinoSwitch`
- `[x]` remove: `CupertinoButton` with `xmark.circle` SF Symbol
- Sliders: `CupertinoSlider`
- Real-time preview: Slider changes send `previewEffect` to native immediately

### 10.4 Real-Time Preview

During editing, a separate preview `AVAudioEngine` instance plays the selected clip's audio through its effect chain. Parameter changes are applied immediately (within one audio buffer, typically < 5ms latency).

### 10.5 Export Application

During export, effects are baked into the audio:

1. For each clip with effects, the source audio is processed through the effect chain offline
2. The processed audio is written to a temp file
3. The temp file is used as the source in the `AVMutableComposition`
4. Temp files are cleaned up after export

This approach ensures export quality matches preview and avoids real-time processing constraints during export.

---

## 11. Noise Reduction

### 11.1 Algorithm: Spectral Subtraction

1. **Noise profiling:** User selects a "silent" section (room tone only, typically 1-3 seconds)
2. **FFT analysis:** Compute average magnitude spectrum of the noise section
3. **Subtraction:** For each frame of the target audio, subtract the noise spectrum
4. **Spectral floor:** Apply minimum magnitude to avoid musical noise artifacts
5. **Reconstruction:** IFFT back to time domain with overlap-add

### 11.2 User Flow

1. User selects an audio clip
2. User taps "Noise Reduction" in effects panel
3. A dedicated sheet opens with waveform display
4. User drags a selection over a "noise-only" section (room tone, hiss)
5. User taps "Learn Noise" - system captures noise profile
6. A `CupertinoSlider` appears for "Reduction Amount" (0% - 100%)
7. User can preview before/after with a toggle switch
8. User taps "Apply"

### 11.3 Native Implementation

```swift
class NoiseReductionProcessor {
    private var noiseSpectrum: [Float]?
    private let fftSize = 2048
    private let hopSize = 512

    /// Step 1: Capture noise profile from a section of audio
    func captureNoiseProfile(
        assetPath: String,
        startMicros: Int,
        endMicros: Int
    ) -> String {
        // Read audio samples for the noise section
        // Compute STFT (Short-Time Fourier Transform)
        // Average the magnitude spectra across all frames
        // Store as noiseSpectrum
        // Return a handle string for reference
    }

    /// Step 2: Apply noise reduction to full audio
    func applyNoiseReduction(
        inputPath: String,
        outputPath: String,
        noiseProfileHandle: String,
        reductionAmount: Float  // 0.0 - 1.0
    ) throws {
        // For each frame:
        //   1. STFT the frame
        //   2. magnitude = abs(STFT)
        //   3. reduced = max(magnitude - reductionAmount * noiseSpectrum, spectralFloor)
        //   4. phase = angle(STFT)
        //   5. output = ISTFT(reduced * exp(i * phase))
        //   6. Overlap-add to output buffer
    }
}
```

FFT operations use the `Accelerate` framework (`vDSP_DFT_zop_CreateSetup` and related functions) for hardware-accelerated computation.

### 11.4 Performance

- FFT size: 2048 samples (46ms at 44.1kHz)
- Hop size: 512 samples (11.6ms)
- Processing speed: ~10x real-time on A14+ chips
- Memory: Noise spectrum ~8KB, processing buffers ~64KB

---

## 12. Beat Detection

### 12.1 Algorithm: Onset Detection + Tempo Estimation

**Phase 1: Onset Detection (spectral flux)**
1. Compute STFT of audio
2. For each frame, compute spectral flux (sum of positive differences in magnitude spectrum)
3. Normalize and apply adaptive threshold
4. Peaks above threshold = onset candidates
5. Apply minimum inter-onset interval (e.g., 100ms for max ~600 BPM)

**Phase 2: Tempo Estimation (autocorrelation)**
1. Compute autocorrelation of the onset detection function
2. Find peaks in autocorrelation (these correspond to periodic tempos)
3. Select strongest peak in musically plausible range (60-200 BPM)
4. Refine with sub-sample interpolation

**Phase 3: Beat Tracking**
1. Use estimated tempo to predict beat positions
2. Align predicted beats to nearest detected onsets
3. Handle tempo changes gracefully (re-estimate per section)

### 12.2 Native Implementation

```swift
class BeatDetector {

    func detectBeats(
        assetPath: String,
        completion: @escaping (Result<BeatDetectionResult, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: URL(fileURLWithPath: assetPath))

            // Read all audio samples (downmixed to mono, 22050 Hz for speed)
            let samples = self.readAudioSamples(asset: asset, targetSampleRate: 22050)

            // Phase 1: Onset detection using spectral flux
            let onsets = self.detectOnsets(samples: samples, sampleRate: 22050)

            // Phase 2: Tempo estimation using autocorrelation
            let (bpm, confidence) = self.estimateTempo(onsets: onsets, sampleRate: 22050)

            // Phase 3: Beat tracking
            let beats = self.trackBeats(
                onsets: onsets,
                estimatedBPM: bpm,
                sampleRate: 22050,
                totalSamples: samples.count
            )

            // Convert sample indices to microseconds
            let beatMicros = beats.map { Int(Double($0) / 22050.0 * 1_000_000) }

            DispatchQueue.main.async {
                completion(.success(BeatDetectionResult(
                    beats: beatMicros,
                    bpm: bpm,
                    confidence: confidence
                )))
            }
        }
    }
}
```

### 12.3 Visual Integration

Beat markers appear on the timeline ruler using the existing `MarkerType.beat` (pink color, `CupertinoIcons.music_note`):

```
Timeline Ruler:
|    |    ♩    |    ♩    |    ♩    |    ♩    |    |
0:00      0:01      0:02      0:03      0:04
```

Beat markers are also used as snap targets. The existing `SnapTargetType.beatMarker` in `edit_operations.dart` already defines this type. When snapping is enabled, clip edges and the playhead snap to nearby beats.

### 12.4 Beat Sync Feature

"Auto-cut to beat" feature:
1. User selects multiple clips or a long clip
2. User taps "Beat Sync" action
3. System generates cuts at beat positions within the selection
4. Preview shows proposed cuts before applying
5. User can adjust by adding/removing individual cuts

---

## 13. Audio Ducking

### 13.1 How It Works

1. **Speech detection** runs on the voiceover/trigger track
2. **Ducking envelope** is generated for the music/target track
3. When speech is detected, the music volume dips by the configured amount
4. Smooth attack/release prevents abrupt volume changes

### 13.2 Speech Detection (Voice Activity Detection)

Simple VAD using energy + zero-crossing rate:

```swift
class VoiceActivityDetector {

    func detectSpeech(
        assetPath: String,
        threshold: Float = 0.3
    ) -> [(startMicros: Int, endMicros: Int)] {
        // 1. Read audio at 16kHz mono
        // 2. Frame-level analysis (20ms frames, 10ms hop)
        // 3. Per frame: compute RMS energy + zero-crossing rate
        // 4. Speech = energy > threshold && ZCR in speech range (30-200 crossings/frame)
        // 5. Merge adjacent speech frames with hangover (200ms)
        // 6. Discard segments < 300ms (too short to be meaningful speech)
        // 7. Return list of (start, end) microsecond pairs
    }
}
```

### 13.3 Envelope Generation

Given speech segments and ducking config:

```dart
VolumeEnvelope generateDuckingEnvelope(
  List<({int start, int end})> speechSegments,
  AudioDuckingConfig config,
) {
  final keyframes = <VolumeKeyframe>[];
  final duckVolume = pow(10, config.duckAmountDB / 20).toDouble(); // Convert dB to linear

  for (final segment in speechSegments) {
    // Ramp down before speech starts
    final rampDownStart = segment.start - (config.attackMs * 1000);
    keyframes.add(VolumeKeyframe(id: uuid(), time: rampDownStart, volume: 1.0));
    keyframes.add(VolumeKeyframe(id: uuid(), time: segment.start, volume: duckVolume));

    // Hold during speech
    keyframes.add(VolumeKeyframe(id: uuid(), time: segment.end, volume: duckVolume));

    // Ramp up after speech ends
    final rampUpEnd = segment.end + (config.releaseMs * 1000);
    keyframes.add(VolumeKeyframe(id: uuid(), time: rampUpEnd, volume: 1.0));
  }

  return VolumeEnvelope(keyframes: keyframes);
}
```

### 13.4 User Flow

1. User enables ducking in the audio panel
2. User selects trigger track (voiceover) and target track (music)
3. System analyzes trigger track for speech
4. Generated ducking envelope is applied to target track
5. User can preview and adjust:
   - Duck amount slider (-3 to -24 dB)
   - Attack/release sliders
   - Speech detection threshold
6. Manual override: user can add/remove ducking regions by tapping on the envelope

---

## 14. Sound Effects Library

### 14.1 Bundled SFX Catalog

Initial set of bundled sound effects (royalty-free, AAC encoded, <100KB each):

| Category | Effects | Count |
|----------|---------|-------|
| Transitions | Whoosh (3 variants), swoosh, swipe, slide | 6 |
| UI | Click, pop, beep, notification, switch, tap | 6 |
| Impacts | Hit, thud, crash, slam, punch, explosion | 6 |
| Nature | Rain, wind, birds, waves, thunder, crickets | 6 |
| Ambience | Room tone, crowd murmur, traffic, cafe, office | 5 |
| Musical | Stinger, riser, drop, cymbal swell, bass hit | 5 |
| Foley | Footstep, door open/close, paper rustle, typing | 4 |

**Total:** ~38 effects, estimated ~3MB in asset bundle.

### 14.2 Browse UI

SFX browser presented as a `CupertinoModalPopup` sheet:

```
+--------------------------------------------------+
|  Sound Effects                           [Done]   |
|  ──────────────────────────────────────────────── |
|  🔍 Search...                                     |
|  ──────────────────────────────────────────────── |
|  [Transitions] [UI] [Impacts] [Nature] ...        |  <- Category pills
|  ──────────────────────────────────────────────── |
|  ┌──────────────────────────────────────────────┐ |
|  │ ▶ Whoosh 1        0.8s   ░░░░████████░░░░░  │ |  <- Waveform preview
|  │ ▶ Whoosh 2        1.2s   ░░████████████░░░░  │ |
|  │ ▶ Swoosh          0.5s   ░░░░░████████░░░░░  │ |
|  │ ▶ Swipe           0.4s   ░░░░███████░░░░░░░  │ |
|  └──────────────────────────────────────────────┘ |
+--------------------------------------------------+
```

- Category filter: horizontal scrollable `CupertinoSegmentedControl`
- Each row: play preview button, name, duration, mini waveform
- Tap to preview (plays through device speaker)
- Tap "Add" or drag to add to timeline at playhead position
- Search: `CupertinoTextField` with fuzzy matching on name + tags

### 14.3 Adding SFX to Timeline

When user selects an SFX:
1. Copy asset from bundle to project's `Documents/sfx/` folder
2. Create `MediaAsset` for the SFX file
3. Create `AudioClip` referencing the MediaAsset
4. Insert on the audio track at the current playhead position
5. Trigger waveform extraction

### 14.4 License

All bundled SFX must be:
- Royalty-free for commercial use
- CC0 or equivalent public domain license
- Created specifically for the app or sourced from verified free libraries (e.g., Freesound.org CC0 collections)
- Attribution documented in app credits/about screen

---

## 15. Audio Export

### 15.1 Export Options

The existing export system (`lib/views/export/export_sheet.dart`) is extended with an "Audio Only" mode:

```
Export Format
─────────────
  ○ Video (MP4)          <- Existing
  ● Audio Only           <- NEW

  Audio Format:
  [WAV] [AAC] [MP3]

  Sample Rate:
  [44.1 kHz] [48 kHz]

  Bit Depth (WAV only):
  [16-bit] [24-bit]

  AAC Quality:
  [128 kbps] [192 kbps] [256 kbps] [320 kbps]
```

### 15.2 Implementation

Audio export uses `AVAssetExportSession` with appropriate output settings:

```swift
func exportAudio(
    composition: AVMutableComposition,
    audioMix: AVMutableAudioMix?,
    format: AudioExportFormat,
    outputPath: String,
    completion: @escaping (Result<URL, Error>) -> Void
) {
    // Create export session with audio-only preset
    let preset: String
    switch format {
    case .wav:
        preset = AVAssetExportPresetPassthrough
    case .aac:
        preset = AVAssetExportPresetAppleM4A
    case .mp3:
        // MP3 requires AudioToolbox conversion after AAC export
        preset = AVAssetExportPresetAppleM4A
    }

    guard let session = AVAssetExportSession(
        asset: composition,
        presetName: preset
    ) else {
        completion(.failure(ExportError.sessionCreationFailed))
        return
    }

    session.outputURL = URL(fileURLWithPath: outputPath)
    session.outputFileType = format.avFileType
    session.audioMix = audioMix

    // Remove video tracks from export
    session.videoComposition = nil

    session.exportAsynchronously {
        switch session.status {
        case .completed:
            if format == .mp3 {
                // Convert M4A to MP3 using AudioToolbox
                self.convertToMP3(inputPath: outputPath, completion: completion)
            } else {
                completion(.success(URL(fileURLWithPath: outputPath)))
            }
        case .failed:
            completion(.failure(session.error ?? ExportError.unknown))
        default:
            break
        }
    }
}
```

### 15.3 Mix Down

All audio tracks are mixed down to stereo during export:

```
Track 1 (video audio) ──┐
Track 2 (SFX)          ──├──> AVMutableAudioMix ──> Stereo Output
Track 3 (music)         ──┤
Track 4 (voiceover)     ──┘
```

Per-track volumes, per-clip volumes, envelopes, fades, and mute states are all baked into the mix via `AVMutableAudioMixInputParameters`.

---

## 16. Native Integration (AVAudioEngine)

### 16.1 Audio Graph Architecture

For real-time preview during editing:

```
                          Per-Clip Subgraph
                    ┌───────────────────────┐
                    │ AVAudioPlayerNode     │
                    │    ↓                  │
                    │ [Effect 1]            │
                    │    ↓                  │
                    │ [Effect 2]            │
                    │    ↓                  │
                    │ [Effect N]            │
                    │    ↓                  │
                    │ AVAudioMixerNode      │  <- Per-clip volume
                    └─────────┬─────────────┘
                              │
                    ┌─────────▼─────────────┐
                    │ Track Mixer Node       │  <- Per-track volume, solo/mute
                    └─────────┬─────────────┘
                              │
              ┌───────────────▼───────────────┐
              │       Main Mixer Node          │  <- Master volume
              └───────────────┬───────────────┘
                              │
                    ┌─────────▼─────────────┐
                    │   Output Node          │  <- Speakers / headphones
                    └───────────────────────┘
```

### 16.2 Playback vs. Preview Engines

Two separate audio processing contexts:

| Context | Purpose | Engine | Latency |
|---------|---------|--------|---------|
| **Playback** | Normal timeline playback | `AVPlayer` via `AVMutableComposition` | ~30ms |
| **Preview** | Real-time effect preview while editing | `AVAudioEngine` with player nodes | ~5ms |

During normal playback, the `AVPlayer`-based composition system handles audio mixing through `AVAudioMix`. When the user opens the effects editor for a clip, the preview engine is activated:

1. Pause the composition player
2. Load the clip's audio into an `AVAudioPlayerNode`
3. Build the effect chain graph
4. Start playback through the preview engine
5. Parameter changes update nodes in real-time
6. When done, tear down preview engine and resume composition player

### 16.3 Latency Management

- **Playback latency:** Inherent in `AVPlayer` (~30ms), not adjustable but acceptable
- **Preview latency:** `AVAudioEngine` buffer size set to 256 samples at 44.1kHz = ~5.8ms
- **Recording latency:** Compensated using `AVAudioSession.inputLatency` (typically ~10ms)
- **Bluetooth latency:** Detected via `AVAudioSession.outputLatency`; show warning if > 50ms

### 16.4 Background Audio Handling

```swift
// In AppDelegate or AudioController setup:
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, options: [.mixWithOthers])
try session.setActive(true)

// Handle interruptions (phone call, Siri, etc.)
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleAudioInterruption),
    name: AVAudioSession.interruptionNotification,
    object: session
)

// Handle route changes (plug/unplug headphones, AirPods connect/disconnect)
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleRouteChange),
    name: AVAudioSession.routeChangeNotification,
    object: session
)
```

---

## 17. Persistence

### 17.1 Audio Effect Chain Serialization

Effects are serialized as part of the `AudioClip.toJson()`:

```json
{
  "itemType": "audio",
  "id": "clip-uuid",
  "mediaAssetId": "asset-uuid",
  "sourceInMicros": 0,
  "sourceOutMicros": 5000000,
  "volume": 0.8,
  "isMuted": false,
  "fadeIn": {
    "durationMicros": 500000,
    "curveType": "sCurve"
  },
  "fadeOut": {
    "durationMicros": 300000,
    "curveType": "linear"
  },
  "effects": [
    {
      "type": "reverb",
      "id": "fx-uuid-1",
      "isEnabled": true,
      "mix": 0.3,
      "roomSize": 0.5,
      "damping": 0.5
    },
    {
      "type": "eq",
      "id": "fx-uuid-2",
      "isEnabled": true,
      "mix": 1.0,
      "bassGain": 3.0,
      "bassFrequency": 100.0,
      "midGain": -2.0,
      "midFrequency": 1000.0,
      "midQ": 1.0,
      "trebleGain": 1.5,
      "trebleFrequency": 8000.0
    }
  ],
  "envelope": [
    {"id": "kf-1", "time": 0, "volume": 0.0, "interpolation": "linear"},
    {"id": "kf-2", "time": 500000, "volume": 1.0, "interpolation": "bezier", "bezierControlIn": [0.4, 0.0], "bezierControlOut": [0.6, 1.0]},
    {"id": "kf-3", "time": 4500000, "volume": 1.0, "interpolation": "linear"},
    {"id": "kf-4", "time": 5000000, "volume": 0.0, "interpolation": "linear"}
  ],
  "linkedVideoClipId": null,
  "speed": 1.0
}
```

### 17.2 Waveform Cache Strategy

Waveform data is NOT persisted to disk (regenerated on demand):
- Cost to regenerate: < 2 seconds for a 5-minute clip
- Cost to store: 240KB per minute at high LOD
- Decision: Regeneration is fast enough; avoid disk I/O overhead

The `WaveformCache` (in-memory LRU, 20MB budget) handles all caching. On project open, waveforms are lazily extracted as clips become visible on the timeline.

### 17.3 Beat Map Cache

Beat maps are persisted per-asset in the project directory:

```
Documents/projects/{projectId}/beatmaps/{assetId}.json
```

```json
{
  "assetId": "asset-uuid",
  "beats": [500000, 1000000, 1500000, 2000000],
  "estimatedBPM": 120.0,
  "confidence": 0.85,
  "timeSignatureNumerator": 4,
  "timeSignatureDenominator": 4
}
```

Cached because beat detection takes 3-5 seconds and results are deterministic per asset.

### 17.4 Noise Profile Storage

Noise profiles are stored as binary spectral data on the native side, referenced by a handle string. On project save:

```
Documents/projects/{projectId}/noise_profiles/{profileId}.dat
```

The Flutter side only stores the `NoiseProfile` metadata (handle, asset ID, time range).

### 17.5 Voiceover File Storage

Recorded voiceovers are stored as M4A files:

```
Documents/projects/{projectId}/voiceovers/{uuid}.m4a
```

These are treated as regular `MediaAsset` files and registered in the asset registry.

---

## 18. Edge Cases

### 18.1 Audio-Only Clips (No Video)

- Waveform is the primary visual on the timeline (no thumbnails)
- Track height auto-adjusts to show waveform detail
- Clip color uses `AppColors.clipAudio` (green)
- All edit operations (split, trim, slip, slide) work identically

### 18.2 Video with No Audio Track

- `clip.hasAudio` is false
- "Detach Audio" action is disabled in context menu
- Volume control is hidden in smart edit view
- No waveform overlay on video clip

### 18.3 Mismatched Sample Rates Between Clips

- `AVMutableComposition` handles sample rate conversion automatically
- When inserting a 48kHz clip into a 44.1kHz composition, AVFoundation resamples
- No explicit handling needed in our code

### 18.4 Very Long Audio Files (1+ hours)

- Waveform extraction: Use `WaveformLOD.low` first (completes in < 5s even for 1hr)
- Memory: Low LOD = 600 samples/minute = 36KB for 1 hour
- Medium/High LOD: Only extracted for visible time range (lazy loading)
- Beat detection: Process in chunks to avoid memory spikes

### 18.5 Recording While Playing (Latency Compensation)

- System measures `AVAudioSession.inputLatency` before recording
- Recording start time is adjusted: `recordingStart = playheadTime - inputLatency`
- Typical iOS input latency: 5-15ms (negligible for voiceover)
- Show warning if combined input+output latency > 50ms (Bluetooth headphones)

### 18.6 Bluetooth Audio Latency

- Detect Bluetooth output via `AVAudioSession.currentRoute.outputs`
- Display persistent warning banner: "Bluetooth audio may have latency. Use wired headphones for recording."
- Do NOT disable recording -- let user decide
- Latency compensation uses measured `outputLatency` value

### 18.7 Audio Effects on Clips with Speed Changes

- Pitch shift is applied BEFORE speed change (so speed doesn't alter pitch correction)
- Delay-based effects (echo, reverb) use absolute time values, not speed-adjusted
- The preview engine applies speed via `AVAudioUnitTimePitch.rate` property
- During export, speed change is handled by the composition time mapping

### 18.8 Undo/Redo for Audio Operations

All audio mutations go through `TimelineManager`:

| Operation | Undo Behavior |
|-----------|---------------|
| Add fade | Remove fade |
| Change fade duration | Restore previous duration |
| Add effect | Remove effect |
| Change effect parameter | Restore previous parameter |
| Reorder effects | Restore previous order |
| Add volume keyframe | Remove keyframe |
| Move volume keyframe | Restore previous position |
| Detach audio | Delete audio clip, unmute video |
| Record voiceover | Delete audio clip, remove asset |
| Apply ducking | Remove ducking envelope |
| Apply noise reduction | Revert to original audio (stored as separate asset) |

Because the entire timeline state is immutable and undo is a pointer swap (O(1)), all audio operations participate automatically.

### 18.9 Multiple Effects Stacked (CPU Budget)

Performance monitoring:
- Each `AVAudioEngine` render callback has a deadline (buffer size / sample rate)
- At 256 samples / 44100 Hz = 5.8ms per callback
- Budget: allow up to 80% utilization = 4.6ms
- Typical effect cost: 0.1-0.5ms per effect
- Hard limit: 8 effects per clip
- If processing exceeds budget, show warning and offer to reduce quality

### 18.10 AirPods/Speaker Switching During Recording

- Listen for `AVAudioSession.routeChangeNotification`
- If route changes during recording:
  - Do NOT stop recording (audio engine handles route change automatically)
  - Update UI to reflect new output device
  - If monitoring was enabled and new device supports it, continue monitoring
  - If new device does not support monitoring (some speakers), disable monitoring

---

## 19. Performance

### 19.1 Performance Targets

| Operation | Target | Method |
|-----------|--------|--------|
| Waveform extraction (5min clip, low LOD) | < 2s | AVAssetReader + vDSP |
| Waveform extraction (5min clip, high LOD) | < 5s | Background thread |
| Waveform rendering (1000px width) | < 1ms | CustomPainter with pre-computed samples |
| Audio mixing (6 tracks) | Real-time | AVMutableAudioMix (hardware) |
| Single effect processing | < 0.5ms/buffer | AVAudioEngine nodes |
| 8 stacked effects | < 4ms/buffer | Within 80% budget |
| Beat detection (5min clip) | < 5s | Accelerate FFT, 22kHz downsample |
| Noise profiling | < 1s | Small section, single FFT pass |
| Noise reduction (5min clip) | < 10s | Offline spectral processing |
| Voice recording startup | < 200ms | Pre-warmed AVAudioEngine |
| Effect parameter change | < 5ms | Real-time node update |
| Audio ducking envelope generation | < 2s | Offline VAD + envelope calculation |
| Audio-only export (5min, AAC) | < 10s | AVAssetExportSession |
| Audio-only export (5min, WAV) | < 5s | Passthrough preset |

### 19.2 Memory Budget

| Component | Budget | Typical Usage |
|-----------|--------|---------------|
| Waveform cache (all LODs) | 20 MB | 5-10 MB for typical project |
| Audio preview buffer | 2 MB | Double-buffered playback |
| Beat map cache | 1 MB | < 100 KB per asset |
| Noise profiles | 1 MB | ~8 KB per profile |
| Effect chain state | Negligible | Lightweight descriptors |
| Recording buffer | 5 MB | Circular buffer, 5s |
| **Total audio subsystem** | **< 30 MB** | |

### 19.3 Threading Model

| Thread | Operations |
|--------|-----------|
| Main thread | UI rendering, state updates, platform channel calls |
| Background (userInitiated) | Waveform extraction, beat detection, noise processing |
| Audio render thread | AVAudioEngine real-time processing (system-managed) |
| Composition build thread | AVMutableComposition construction |

Critical rule: NEVER access `AVAudioEngine` render-thread resources from the main thread. Use the engine's `scheduleBuffer` and node property setters which are thread-safe.

---

## 20. Dependencies

### 20.1 Native Frameworks

| Framework | Purpose | Minimum iOS |
|-----------|---------|-------------|
| `AVFoundation` | Audio playback, recording, composition | iOS 15.0 |
| `AVAudioEngine` | Real-time audio processing, effect chains | iOS 15.0 |
| `Accelerate` | vDSP FFT, peak detection, signal processing | iOS 15.0 |
| `AudioToolbox` | Low-level audio format conversion (MP3) | iOS 15.0 |

No new native framework dependencies. All are already available in the project's minimum iOS target.

### 20.2 Flutter Packages

No new Flutter packages required. The existing packages provide everything needed:

- `video_player` - Already handles audio playback for composition
- `provider` - State management for AudioController
- `uuid` - ID generation for effects, keyframes
- `path_provider` - File paths for recordings, exports

### 20.3 Platform Channel Methods (New)

| Channel | Methods | Direction |
|---------|---------|-----------|
| `com.liquideditor/audio_waveform` | extractWaveform | Flutter -> Native |
| `com.liquideditor/audio_effects` | setupEffectChain, removeEffectChain, previewEffect | Flutter -> Native |
| `com.liquideditor/audio_recording` | prepareRecording, startRecording, stopRecording, getInputLevel, setMonitoringEnabled | Flutter -> Native |
| `com.liquideditor/audio_analysis` | detectBeats, captureNoiseProfile, applyNoiseReduction | Flutter -> Native |
| `com.liquideditor/audio_ducking` | detectSpeech, generateDuckingEnvelope | Flutter -> Native |
| `com.liquideditor/audio_export` | exportAudioOnly | Flutter -> Native |

### 20.4 Existing Code Modifications

| File | Change | Impact |
|------|--------|--------|
| `lib/models/clips/audio_clip.dart` | Add fadeIn, fadeOut, effects, envelope, linkedVideoClipId, speed fields | Low (additive, backward-compatible defaults) |
| `lib/timeline/data/models/volume_keyframe.dart` | Add VolumeInterpolation, bezier control points, volume range to 2.0 | Medium (existing getVolumeAt behavior preserved) |
| `lib/timeline/data/models/track.dart` | Add trackVolume field | Low (default 1.0) |
| `lib/timeline/rendering/painters/clip_painter.dart` | Add waveform drawing, fade overlay, envelope overlay | Medium (new paint methods) |
| `lib/timeline/data/models/timeline_clip.dart` | Extend showsWaveform to include video clips with audio | Low |
| `ios/Runner/Timeline/CompositionBuilder.swift` | Multi-track audio insertion, effect baking | High (core export path) |
| `ios/Runner/CompositionPlayerService.swift` | Multi-track audio mixing during playback | Medium |
| `ios/Runner/AppDelegate.swift` | Register new platform channels | Low |
| `lib/views/smart_edit/smart_edit_view.dart` | Add audio editing UI panels | Medium |
| `lib/views/smart_edit/editor_bottom_toolbar.dart` | Add audio-related toolbar actions | Low |

---

## 21. Implementation Plan

### Phase 1: Waveform Visualization (Week 1-2)

**Files to create:**
- `ios/Runner/Audio/WaveformExtractor.swift` - Native waveform extraction
- `ios/Runner/Audio/AudioMethodHandler.swift` - Platform channel handler for audio operations

**Files to modify:**
- `ios/Runner/AppDelegate.swift` - Register `com.liquideditor/audio_waveform` channel
- `lib/timeline/rendering/painters/clip_painter.dart` - Add `_drawWaveform()` method
- `lib/timeline/timeline_controller.dart` - Wire WaveformCache to native generator

**Test plan:**
- Unit test: WaveformData.getSamplesForRange with various ranges
- Unit test: WaveformCache LRU eviction and multi-LOD fallback
- Integration test: Extract waveform from test audio file, verify sample count
- Visual test: Render waveform on timeline, verify zoom-level LOD switching

### Phase 2: Audio Detach (Week 2)

**Files to create:**
- (none - uses existing models)

**Files to modify:**
- `lib/models/clips/audio_clip.dart` - Add `linkedVideoClipId` field
- `lib/core/timeline_manager.dart` - Add `detachAudio()` compound edit
- `lib/views/smart_edit/smart_edit_view.dart` - Add "Detach Audio" context menu

**Test plan:**
- Unit test: Detach creates AudioClip with matching source range
- Unit test: Linked clip movement propagation
- Unit test: Undo/redo of detach operation
- Manual test: Detach, move video, verify audio follows

### Phase 3: Audio Fades (Week 3)

**Files to create:**
- `lib/models/audio_fade.dart` - AudioFade model with curve types
- `lib/timeline/rendering/painters/fade_handle_painter.dart` - Fade handle rendering

**Files to modify:**
- `lib/models/clips/audio_clip.dart` - Add `fadeIn`, `fadeOut` fields
- `lib/timeline/rendering/painters/clip_painter.dart` - Add fade overlay and handle rendering
- `ios/Runner/Timeline/CompositionBuilder.swift` - Apply fade via volume ramp in AudioMix

**Test plan:**
- Unit test: AudioFade.gainAtNormalized for each curve type
- Unit test: Fade serialization round-trip
- Integration test: Export clip with fades, verify audio amplitude
- Manual test: Drag fade handles, verify visual feedback

### Phase 4: Multiple Audio Tracks (Week 4-5)

**Files to modify:**
- `lib/timeline/data/models/track.dart` - Add `trackVolume` field
- `ios/Runner/Timeline/CompositionBuilder.swift` - Multi-track audio insertion
- `lib/timeline/timeline_controller.dart` - Track management (add/remove/reorder)
- `lib/timeline/widgets/track_header.dart` - Track header with mute/solo/volume

**Test plan:**
- Unit test: Track creation with different types
- Unit test: Multi-track composition building
- Integration test: Export with 4 audio tracks, verify mix
- Manual test: Add/remove tracks, solo/mute, per-track volume

### Phase 5: Volume Keyframing (Week 5-6)

**Files to create:**
- `lib/timeline/widgets/envelope_editor.dart` - Envelope editing overlay widget

**Files to modify:**
- `lib/timeline/data/models/volume_keyframe.dart` - Add interpolation, bezier, 200% volume
- `lib/timeline/rendering/painters/clip_painter.dart` - Draw envelope line and control points
- `ios/Runner/Timeline/CompositionBuilder.swift` - Apply envelope via volume ramps

**Test plan:**
- Unit test: VolumeEnvelope.getVolumeAt with bezier interpolation
- Unit test: Keyframe add/remove/move operations
- Manual test: Drag control points, verify smooth curve rendering

### Phase 6: Audio Effects (Week 7-9)

**Files to create:**
- `lib/models/audio_effect.dart` - Effect models (all types)
- `lib/views/smart_edit/audio_effects_sheet.dart` - Effect chain editor UI
- `ios/Runner/Audio/AudioEffectsEngine.swift` - AVAudioEngine effect chain management

**Files to modify:**
- `lib/models/clips/audio_clip.dart` - Add `effects` field
- `ios/Runner/AppDelegate.swift` - Register `com.liquideditor/audio_effects` channel
- `ios/Runner/Timeline/CompositionBuilder.swift` - Bake effects during export

**Test plan:**
- Unit test: Effect serialization round-trip for all types
- Integration test: Apply reverb, export, verify audio processing
- Performance test: 8 stacked effects under 4ms per buffer
- Manual test: Real-time parameter changes, verify preview latency

### Phase 7: Voiceover Recording (Week 9-10)

**Files to create:**
- `lib/views/smart_edit/voiceover_recording_overlay.dart` - Recording UI
- `ios/Runner/Audio/VoiceoverRecorder.swift` - Native recording

**Files to modify:**
- `ios/Runner/AppDelegate.swift` - Register `com.liquideditor/audio_recording` channel

**Test plan:**
- Integration test: Record, verify file creation and duration
- Manual test: Record with video playback, verify sync
- Manual test: Bluetooth headphones warning
- Manual test: Route change during recording

### Phase 8: Beat Detection (Week 10-11)

**Files to create:**
- `lib/models/beat_map.dart` - BeatMap model
- `ios/Runner/Audio/BeatDetector.swift` - Native beat detection
- `lib/timeline/rendering/painters/beat_marker_painter.dart` - Beat markers on ruler

**Files to modify:**
- `ios/Runner/AppDelegate.swift` - Register `com.liquideditor/audio_analysis` channel
- `lib/timeline/rendering/painters/ruler_painter.dart` - Draw beat markers

**Test plan:**
- Unit test: BeatMap.nearestBeat binary search
- Integration test: Detect beats on known-BPM audio, verify accuracy (+/- 2 BPM)
- Performance test: < 5s for 5-minute clip
- Manual test: Visual beat markers align with music

### Phase 9: Audio Ducking (Week 11-12)

**Files to create:**
- `lib/models/audio_ducking_config.dart` - Ducking configuration
- `lib/views/smart_edit/audio_ducking_sheet.dart` - Ducking controls UI
- `ios/Runner/Audio/AudioDuckingEngine.swift` - VAD + envelope generation

**Files to modify:**
- `ios/Runner/AppDelegate.swift` - Register `com.liquideditor/audio_ducking` channel

**Test plan:**
- Integration test: Detect speech in known voiceover, verify segment timestamps
- Unit test: Ducking envelope generation with various configs
- Manual test: Music ducks when voiceover speaks

### Phase 10: Noise Reduction (Week 12-13)

**Files to create:**
- `lib/models/noise_profile.dart` - NoiseProfile model
- `lib/views/smart_edit/noise_reduction_sheet.dart` - Noise reduction UI
- `ios/Runner/Audio/NoiseReductionProcessor.swift` - Spectral subtraction

**Test plan:**
- Integration test: Capture noise profile, apply reduction, verify SNR improvement
- Performance test: < 10s for 5-minute clip
- Manual test: Before/after preview toggle

### Phase 11: Sound Effects Library (Week 13-14)

**Files to create:**
- `lib/models/sound_effect_asset.dart` - SFX metadata model
- `lib/views/smart_edit/sfx_browser_sheet.dart` - SFX browser UI
- `assets/sfx/` - Bundled sound effect files
- `lib/data/sfx_catalog.dart` - Static catalog of bundled SFX

**Test plan:**
- Unit test: SFX catalog loading and search
- Manual test: Browse, preview, add to timeline

### Phase 12: Audio Export (Week 14)

**Files to create:**
- `ios/Runner/Audio/AudioExporter.swift` - Audio-only export

**Files to modify:**
- `lib/views/export/export_sheet.dart` - Add audio-only export option
- `ios/Runner/AppDelegate.swift` - Register `com.liquideditor/audio_export` channel

**Test plan:**
- Integration test: Export WAV, AAC, verify format and quality
- Integration test: Export multi-track mix, verify all tracks present
- Manual test: Export with effects, verify effects applied

---

## Appendix A: File Structure

```
lib/
├── models/
│   ├── clips/
│   │   └── audio_clip.dart              # Enhanced (new fields)
│   ├── audio_fade.dart                   # NEW
│   ├── audio_effect.dart                 # NEW (base + all subtypes)
│   ├── beat_map.dart                     # NEW
│   ├── noise_profile.dart                # NEW
│   ├── audio_ducking_config.dart         # NEW
│   └── sound_effect_asset.dart           # NEW
├── core/
│   └── audio_controller.dart             # NEW
├── data/
│   └── sfx_catalog.dart                  # NEW
├── timeline/
│   ├── data/models/
│   │   ├── volume_keyframe.dart          # Enhanced (interpolation, bezier)
│   │   └── track.dart                    # Enhanced (trackVolume)
│   ├── rendering/painters/
│   │   ├── clip_painter.dart             # Enhanced (waveform, fades, envelope)
│   │   ├── fade_handle_painter.dart      # NEW
│   │   └── beat_marker_painter.dart      # NEW
│   ├── widgets/
│   │   └── envelope_editor.dart          # NEW
│   └── cache/
│       └── waveform_cache.dart           # Existing (wired to native)
├── views/
│   ├── smart_edit/
│   │   ├── audio_effects_sheet.dart      # NEW
│   │   ├── voiceover_recording_overlay.dart  # NEW
│   │   ├── audio_ducking_sheet.dart      # NEW
│   │   ├── noise_reduction_sheet.dart    # NEW
│   │   ├── sfx_browser_sheet.dart        # NEW
│   │   └── volume_control_sheet.dart     # Existing
│   └── export/
│       └── export_sheet.dart             # Enhanced (audio-only)
└── assets/
    └── sfx/                              # NEW (bundled SFX files)

ios/Runner/
├── Audio/                                # NEW directory
│   ├── WaveformExtractor.swift           # NEW
│   ├── AudioMethodHandler.swift          # NEW
│   ├── AudioEffectsEngine.swift          # NEW
│   ├── VoiceoverRecorder.swift           # NEW
│   ├── BeatDetector.swift                # NEW
│   ├── AudioDuckingEngine.swift          # NEW
│   ├── NoiseReductionProcessor.swift     # NEW
│   └── AudioExporter.swift               # NEW
├── Timeline/
│   ├── CompositionBuilder.swift          # Enhanced
│   └── CompositionManagerService.swift   # Enhanced
└── AppDelegate.swift                     # Enhanced (register channels)

test/
├── models/
│   ├── audio_fade_test.dart              # NEW
│   ├── audio_effect_test.dart            # NEW
│   └── beat_map_test.dart                # NEW
├── timeline/
│   ├── volume_envelope_test.dart         # Enhanced
│   └── waveform_cache_test.dart          # Existing (enhanced)
└── core/
    └── audio_controller_test.dart        # NEW
```

## Appendix B: Migration Checklist

- [ ] AudioClip: Add new fields with defaults, update fromJson to handle missing fields
- [ ] VolumeKeyframe: Add interpolation field with `linear` default
- [ ] Track: Add trackVolume field with `1.0` default
- [ ] TimelineClip: Update showsWaveform to include video clips with `hasAudio`
- [ ] CompositionBuilder: Ensure single-track audio still works when multi-track is added
- [ ] Project serialization: New fields gracefully ignored by older versions (forward-compatible)

## Appendix C: Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| AVAudioEngine real-time thread priority conflicts | Audio glitches during effects preview | Separate preview engine from playback engine |
| Memory pressure from waveform + video thumbnails | App termination | WaveformCache has memory budget; reduce on low-memory notification |
| Beat detection inaccuracy on complex music | Poor snap-to-beat experience | Show confidence score; allow manual beat adjustment |
| Bluetooth latency during recording | Out-of-sync voiceover | Measure and compensate; show warning to user |
| Effect chain CPU overload on older devices | Dropped audio frames | Monitor render callback duration; hard limit 8 effects |
| Noise reduction artifacts (musical noise) | Poor audio quality | Spectral floor parameter; before/after preview |
| Multi-track composition build time | Slow hot-swap | Background building already implemented; measure and optimize |

---

## Review 1 - Architecture & Completeness

**Reviewer:** Claude Opus 4.6 (Architecture Review)
**Date:** 2026-02-06
**Scope:** Full design document review against existing codebase
**Verdict:** Solid design with several critical gaps that must be addressed before implementation begins

---

### CRITICAL Issues

#### C1. PersistentTimeline is Single-Track -- Multi-Track Audio Has No Foundation

The `PersistentTimeline` (`lib/models/persistent_timeline.dart`) is a single order statistic tree that stores items in a flat sequence. It has no concept of tracks, track IDs, or parallel clip lanes. The `TimelineManager` (`lib/core/timeline_manager.dart`) wraps this single tree and provides `insertAt`, `append`, `remove`, etc. -- all operating on one linear sequence.

The design document (Section 6) assumes that multiple audio tracks can hold clips simultaneously at overlapping time positions, with clips on different tracks playing concurrently. This is fundamentally incompatible with the current single-track tree architecture.

**Specifically broken:**
- `detachAudio()` in Section 5.2 calls `_timelineManager.insertClip(audioClip, trackId: audioTrack.id, atTime: videoClipStartTime)` -- but `TimelineManager` has no `insertClip` method that accepts a `trackId` parameter.
- The entire multi-track mixing model (Section 6.4) assumes parallel audio tracks, but the persistent tree only supports sequential items.
- The `CompositionBuilder.build()` currently iterates a flat segment list sequentially and advances `currentTime` linearly. Multi-track requires parallel segment insertion on multiple `AVMutableCompositionTrack` instances.

**Recommendation:** Before Phase 4 (Multiple Audio Tracks), a multi-track extension must be designed for `PersistentTimeline` or `TimelineManager`. Options:
1. **Per-track PersistentTimeline:** Each `Track` gets its own tree. `TimelineManager` holds a `Map<String, PersistentTimeline>`. Undo/redo becomes a pointer swap of the entire map.
2. **Keyed tree with track partition:** Extend the tree node to include a `trackId` field, then query by track. This would break O(log n) time-based lookup unless the tree is partitioned.
3. **Separate AudioTimelineManager:** A dedicated manager for audio tracks only, keeping the existing video timeline intact.

This needs its own design document section with the chosen approach, data structure changes, and migration plan.

#### C2. TimelineManager Lacks Compound Edit / Batch Mutation

Section 5.2 calls `_timelineManager.beginCompoundEdit('Detach Audio')` and `_timelineManager.endCompoundEdit()`. These methods do not exist on `TimelineManager`. The current implementation pushes one undo entry per `_execute()` call. A "detach audio" operation requires 2 mutations (mute video + insert audio clip), which would create 2 undo entries instead of 1 atomic operation.

**Impact:** Undo would only undo half the detach operation, leaving the timeline in an inconsistent state.

**Recommendation:** Add compound edit support to `TimelineManager`:

```dart
PersistentTimeline? _compoundBaseline;
String? _compoundName;

void beginCompoundEdit(String name) {
  _compoundBaseline = _current;
  _compoundName = name;
}

void endCompoundEdit() {
  if (_compoundBaseline != null) {
    // Replace all intermediate undo entries with single entry
    while (_undoStack.isNotEmpty && _undoStack.last != _compoundBaseline) {
      _undoStack.removeLast();
    }
    if (_undoStack.isEmpty || _undoStack.last != _compoundBaseline) {
      _undoStack.add(_compoundBaseline!);
    }
    _compoundBaseline = null;
    _compoundName = null;
  }
}
```

Alternatively, expose a `_execute` variant that takes a composition of mutations as a single lambda, which is cleaner.

#### C3. Two Incompatible Clip Model Hierarchies

The codebase has two separate clip model hierarchies that the design document conflates:

1. **Data-layer models** (`lib/timeline/data/models/timeline_clip.dart`): `TimelineClip` -- a flat, UI-focused model with `id`, `trackId`, `startTime`, `duration`, `volume`, `hasAudio`, `linkedClipId`, etc. Used by `ClipsPainter` and timeline rendering.

2. **Domain-layer models** (`lib/models/clips/audio_clip.dart`): `AudioClip extends MediaClip extends TimelineItem` -- an immutable domain model used by `PersistentTimeline` and `TimelineManager`. Has `mediaAssetId`, `sourceInMicros`, `sourceOutMicros`, `volume`, `isMuted`.

The design document's `AudioClip` enhancement (Section 2.1) extends the domain-layer `AudioClip` with `fadeIn`, `fadeOut`, `effects`, `envelope`, `linkedVideoClipId`, and `speed`. But the data-layer `TimelineClip` also needs corresponding fields for the rendering pipeline to display fade handles, effect badges, and waveform overlays.

**Recommendation:** Explicitly document the mapping between domain `AudioClip` and UI `TimelineClip`. Add a builder/factory that converts enhanced `AudioClip` to `TimelineClip` with the new audio metadata fields. The `TimelineClip` likely needs new fields:
- `fadeInDurationMicros`, `fadeOutDurationMicros` (for fade handle rendering)
- `effectCount` already exists but needs to be populated from `effects.length`
- `hasEnvelope` (for envelope overlay rendering toggle)

#### C4. AudioClip Has No `speed` Field and Volume Is Clamped to 1.0

The existing `AudioClip` (`lib/models/clips/audio_clip.dart`) clamps volume to `0.0 - 1.0` in `withVolume()` and `copyWith()`. The design (Section 2.1) proposes `volume: 0.0 - 1.0` on `AudioClip` but the `VolumeEnvelope` uses `0.0 - 2.0` (Section 2.4). This creates an inconsistency: the envelope can boost to 200% but the clip base volume caps at 100%.

Also, `AudioClip` currently has no `speed` field. The `MediaClip` base class computes duration as `sourceOutMicros - sourceInMicros`, which does not account for playback speed. Adding `speed` to `AudioClip` requires overriding `durationMicroseconds` to return `(sourceOutMicros - sourceInMicros) / speed`.

**Recommendation:**
1. Update `AudioClip.volume` range to `0.0 - 2.0` to match `VolumeEnvelope` range, or clearly document that clip volume is a separate layer from envelope volume (which is the current multiplicative model: `clipVolume * envelopeMultiplier`).
2. Add `speed` field to `AudioClip` and override `durationMicroseconds` to account for speed. Ensure `trimStart()`/`trimEnd()` also handle speed.

---

### IMPORTANT Issues

#### I1. Export Pipeline Does Not Handle Audio Effects via AVMutableAudioMix

Section 10.5 states that during export, effects are baked by processing source audio through the effect chain offline, writing to a temp file, then using the temp file in the composition. This is the correct approach, but the document lacks detail on:

1. **Temp file lifecycle:** When are temp files created (on export start or pre-computed)? How are they cleaned up on export failure/cancellation?
2. **Disk space:** A 5-minute clip at 44.1kHz/16-bit stereo = ~50MB per temp file. With 6 tracks, that's 300MB of temp disk usage. This should be called out in the performance section.
3. **Effect ordering with fades:** Are fades applied before or after effects? The export pipeline must define the signal chain clearly: Source -> Speed -> Effects -> Fade -> Envelope -> Track Volume -> Mix.
4. **Composition rebuild:** After baking effects to temp files, the `CompositionBuilder` needs to use the temp file paths instead of original asset paths. The current segment-based API (`CompositionSegment.assetPath`) supports this, but the flow needs explicit documentation.

**Recommendation:** Add a subsection to Section 15 or 16 with an explicit export signal chain diagram and temp file management strategy.

#### I2. AVAudioSession Category Conflict Between Playback and Recording

Section 9.4 sets the AVAudioSession category to `.playAndRecord` for voiceover recording, while Section 16.4 sets it to `.playback` with `.mixWithOthers`. These are mutually exclusive categories. Switching between them can cause audio interruptions.

**Impact:** Transitioning from normal playback to recording mode will cause an audio session reconfiguration, which:
- Interrupts any playing audio momentarily
- Changes audio routing (`.playAndRecord` defaults to earpiece, not speaker, unless `.defaultToSpeaker` is specified)
- May cause a noticeable volume change

**Recommendation:**
1. Document the audio session lifecycle explicitly: which category is active in which mode.
2. Consider using `.playAndRecord` as the default category from app launch (with `.defaultToSpeaker`) to avoid transitions. The playback quality difference is negligible on modern iOS devices.
3. Add a "preparing to record" state that handles the session transition with appropriate UI feedback.

#### I3. Noise Reduction Is Destructive -- Needs Non-Destructive Alternative

Section 11 describes noise reduction as writing to an output file (`applyNoiseReduction(inputPath, outputPath, ...)`). The undo behavior (Section 18.8) says "Revert to original audio (stored as separate asset)." This means applying noise reduction creates a new asset file, and the original is kept.

**Issues:**
- If the user adjusts the reduction amount, a new file is created each time. This can consume significant disk space.
- The design does not specify whether the noise-reduced version is applied as a new `mediaAssetId` on the `AudioClip` or as an effect in the chain.
- There is no way to adjust the noise reduction amount after applying without re-running the entire processing pipeline.

**Recommendation:** Consider treating noise reduction as a non-destructive effect in the effect chain (like other effects). During preview, use the spectral subtraction in real-time (feasible given the 10x real-time performance claim). During export, bake it like other effects. This avoids creating temp files and makes the reduction amount adjustable at any time. If real-time performance is not achievable, document the destructive workflow clearly with disk space warnings.

#### I4. Detach Audio Does Not Handle Audio Clips with Different Speed

Section 5.2 shows `speed: videoClip.speed` being passed to the new `AudioClip`. But `AudioClip` currently has no `speed` field (as noted in C4). Additionally, the linked clip behavior table (Section 5.3) says "Change video speed -> Audio speed updated to match." This requires the timeline engine to propagate speed changes through linked clips, but the existing `TimelineManager` has no such linking mechanism.

**Recommendation:** Add a section describing how linked-clip propagation is implemented. This likely requires:
1. A `linkedClips` index in `TimelineManager` (or a derived structure)
2. A post-mutation hook that checks for linked clips and applies symmetric changes
3. Tests for edge cases: linked audio clip trimmed independently, then video speed changes

#### I5. The AudioController Uses ChangeNotifier But Existing System Uses PersistentTimeline

The `AudioController` (Section 3.2) is described as a `ChangeNotifier` that coordinates audio state. But audio mutations (fades, effects, envelope) are modifications to `AudioClip`, which lives in the immutable `PersistentTimeline`. The `AudioController` must go through `TimelineManager` to make these changes (to get undo/redo). This means `AudioController` is not truly a state owner -- it is a command dispatcher.

**Recommendation:** Clarify the boundary between `AudioController` and `TimelineManager`:
- `AudioController` should NOT hold mutable state for clip data (fades, effects, envelope). These are on `AudioClip` in the immutable timeline.
- `AudioController` CAN hold transient state: recording status, preview engine state, beat map cache, noise profiles.
- Effect preview state (temporary parameter values during slider drag) needs a clear strategy: hold in `AudioController` temporarily, then commit to `TimelineManager` on gesture end.

#### I6. Waveform Extraction Hardcodes 44.1kHz Mono

Section 4.1 hardcodes the output to 44.1kHz mono (`AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1`). This loses stereo information, which matters for:
- Accurate stereo waveform display (L/R channels)
- Correct peak detection for stereo-panned content

For a video editor this is likely acceptable (mono waveform is standard), but the hardcoded 44.1kHz is problematic for 48kHz source material (common in video). While the waveform display does not need sample-accurate rates, the sample count calculation in `WaveformData.getSamplesForRange()` depends on `sampleRate`. If the source is 48kHz but extraction was at 44.1kHz, the time-to-sample mapping will be slightly off (drift of ~0.03s per minute).

**Recommendation:** Extract at the source file's native sample rate rather than hardcoding 44.1kHz. The `AVAssetReaderTrackOutput` will handle conversion, but it is better to match the source to avoid mapping drift. Alternatively, document that the drift is acceptable for visual waveform purposes (it is).

#### I7. No Cancellation Support for Long-Running Native Operations

Beat detection (3-5s), noise reduction (up to 10s), and waveform extraction (up to 5s) are long-running operations but the platform channel API (Section 3.3) has no cancellation mechanism. If the user navigates away or starts a new operation, the previous operation should be cancellable.

**Recommendation:** Add a cancellation token pattern:
1. `extractWaveform` returns a `requestId`
2. A `cancelRequest(requestId)` method on the same channel
3. Native side checks a cancellation flag between processing chunks

---

### MINOR Issues

#### M1. AudioFade.gainAtNormalized Logarithmic Curve Has Edge-Case Artifact

The logarithmic curve implementation at line 203:
```dart
return clamped == 0 ? 0 : (1 + (log(clamped) / log(10)) * 0.5).clamp(0.0, 1.0);
```

At `t = 0.01`, this returns `1 + (log(0.01) / log(10)) * 0.5 = 1 + (-2) * 0.5 = 0.0`. At `t = 0.001`, this returns `1 + (-3) * 0.5 = -0.5`, clamped to `0.0`. This means the logarithmic curve is essentially silent for the first ~1% of the fade, which creates a noticeable "late start" artifact.

**Recommendation:** Use a perceptual loudness curve like `pow(t, 0.5)` (square root) for the logarithmic option, which better matches human perception. Or use `pow(10, 2 * (t - 1))` which is the dB-linear curve commonly used in audio faders.

#### M2. BeatMap.nearestBeat Binary Search Off-by-One Risk

The `nearestBeat` implementation (Section 2.7) uses a standard lower-bound binary search but the comparison at the end only checks `lo` and `lo - 1`. If the list has only 1 element, `lo` is 0 and `lo - 1` is -1, but this is handled by the `if (lo == 0)` guard. The logic is correct but could be cleaner with a dedicated `closestInSorted` helper function.

**Recommendation:** Minor code quality improvement -- extract to a reusable utility since the same pattern appears for snap target lookup.

#### M3. SFX Copy-to-Documents Strategy Is Wasteful

Section 14.3 says SFX files are copied from the asset bundle to `Documents/sfx/` when added. This duplicates ~100KB per effect. Since these are read-only bundled assets, they can be referenced directly from the bundle.

**Recommendation:** Reference SFX directly from the asset bundle path. Only copy to Documents if the user modifies the SFX (trim, effects). The `MediaAsset` can distinguish between bundle paths and document paths.

#### M4. MP3 Export Uses AVAssetExportPresetPassthrough for WAV

Section 15.2 uses `AVAssetExportPresetPassthrough` for WAV export. This preset preserves the source format, which may not be WAV. For WAV output, you need `AVAssetWriter` with `kAudioFormatLinearPCM` settings, not `AVAssetExportSession`.

**Recommendation:** Replace the WAV export path with `AVAssetWriter`-based implementation that explicitly writes LPCM data with the requested bit depth.

#### M5. AudioDuckingConfig Uses Track IDs But Tracks Can Be Deleted

The `AudioDuckingConfig` holds `targetTrackId` and `triggerTrackId`. If either track is deleted, the config becomes invalid but the design does not specify cleanup behavior.

**Recommendation:** Add validation in `AudioController.configureDucking()` that checks track existence. On track deletion, auto-disable ducking and notify the user.

#### M6. Volume Percentage Display Inconsistency

The existing `VolumeControlSheet` displays 0-100% for volume 0.0-1.0. The enhanced `VolumeEnvelope` supports 0.0-2.0 (200% boost). The envelope editor needs to show 0-200% while the quick volume control shows 0-100%. This inconsistency may confuse users.

**Recommendation:** Either expand the quick volume control to support 200% (with a "boost" indicator above 100%), or clearly differentiate between "clip volume" (0-100%) and "envelope volume" (0-200%) in the UI.

---

### QUESTIONS

#### Q1. Should the Preview AVAudioEngine Run Continuously or On-Demand?

Section 16.2 describes activating the preview engine when the effects editor opens. Creating and tearing down `AVAudioEngine` instances has a startup cost (~50-100ms). If effects editing is frequent, consider keeping the preview engine warm (but idle) to reduce latency.

#### Q2. What Happens to Beat Markers When Audio Clip Is Speed-Changed?

If beats are detected at 120 BPM and the clip speed is changed to 2x, do the beat markers shift to 240 BPM positions? Or are they stored as source-time positions and mapped through the speed transform? The design does not specify this.

#### Q3. How Are Audio Effects Applied to the Embedded Audio of Video Clips?

The design focuses on `AudioClip` effects, but what about the audio track of a `VideoClip`? Can users apply reverb/EQ to a video clip's embedded audio without detaching? If yes, `VideoClip` also needs an effects field. If no, the user must detach audio first -- this should be documented as an explicit UX decision.

#### Q4. What Is the Maximum Simultaneous Recording Duration?

Section 9.5 mentions saving to M4A, but does not specify a maximum recording duration or disk space check. For a 30-minute voiceover recording at 44.1kHz/16-bit mono, the file size is ~150MB. Should there be a remaining-disk-space check before recording starts?

#### Q5. How Does Crossfade (Section 8.4) Interact with the PersistentTimeline?

Audio crossfades require two clips to overlap in time on the same track. But the `PersistentTimeline` stores items sequentially with no overlap. Does crossfade require clips to actually overlap (splitting a gap), or is it handled purely through volume envelopes on adjacent clips with no actual overlap? The `ClipTransition` model exists but its integration with the persistent timeline is unclear.

#### Q6. Is AVAudioUnitTimePitch Adequate for Formant-Preserving Pitch Shift?

`AVAudioUnitTimePitch` does time-stretching and pitch shifting but does not have a native formant preservation mode. The `PitchShiftEffect` model (Section 2.3) includes `preserveFormants: true` but `AVAudioUnitTimePitch` does not expose this. True formant preservation would require a third-party library or custom DSP (e.g., PSOLA algorithm). Should this feature be deferred or implemented with a documented limitation?

---

### Summary Table

| Category | Count | Key Themes |
|----------|-------|------------|
| CRITICAL | 4 | Multi-track architecture gap, compound edit missing, dual model hierarchy, speed/volume range mismatch |
| IMPORTANT | 7 | Export pipeline detail, AVAudioSession lifecycle, noise reduction destructiveness, linked clip propagation, controller boundaries, sample rate hardcoding, cancellation support |
| MINOR | 6 | Fade curve math, binary search style, SFX duplication, WAV export implementation, dangling track references, volume display range |
| QUESTION | 6 | Preview engine lifecycle, beat markers + speed, video audio effects, recording limits, crossfade + timeline overlap, formant preservation |

### Recommended Pre-Implementation Actions

1. **Resolve C1 first** -- Multi-track PersistentTimeline extension is a prerequisite for Phases 2-12. Consider a dedicated design addendum.
2. **Implement C2** (compound edit) before Phase 2 (Audio Detach).
3. **Resolve C3** (dual model mapping) as part of Phase 1 to establish the pattern early.
4. **Address C4** (speed field, volume range) as part of the AudioClip enhancement in Phase 1.
5. **Answer Q3 and Q5** before Phase 3 (Fades) to determine UX direction.
6. **Answer Q6** before Phase 6 (Effects) to set expectations for formant preservation.

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06
**Scope:** Codebase verification, AVAudioEngine feasibility, platform channel design, timeline integration, export pipeline, memory budget, real-time constraints
**Verdict:** Design is architecturally sound but has several integration gaps that will cause implementation failures if not addressed. R1 critical issues are confirmed. Additional integration risks identified below.

---

### Codebase Verification Results

I read the following source files to verify the design document's assumptions about existing infrastructure:

| File | Exists | Design Assumption | Verified |
|------|--------|-------------------|----------|
| `lib/models/clips/audio_clip.dart` | YES | `AudioClip` has `volume`, `isMuted`, `name`, `mediaAssetId`, in/out points | CONFIRMED. Fields match exactly. No `fadeIn`, `fadeOut`, `effects`, `envelope`, `linkedVideoClipId`, or `speed` fields exist yet. |
| `lib/timeline/cache/waveform_cache.dart` | YES | Multi-LOD `WaveformCache` with LRU eviction, async generation, `waveformGenerator` callback | CONFIRMED. Implementation is complete and well-structured. The `waveformGenerator` callback (`Future<WaveformData?> Function(String, WaveformLOD)?`) is the exact hook needed for native wiring. 20MB default budget. |
| `lib/timeline/data/models/volume_keyframe.dart` | YES | `VolumeKeyframe` and `VolumeEnvelope` with linear interpolation | CONFIRMED. `getVolumeAt()` does linear interpolation. Volume clamped to `0.0 - 1.0` in `copyWith()`. No `interpolation` field, no bezier control points. |
| `lib/timeline/data/models/track.dart` | YES | `Track` with `isMuted`, `isSolo`, `isLocked`, track types including `audio`, `music`, `voiceover` | CONFIRMED. Full `TrackType` enum exists with correct colors. No `trackVolume` field. |
| `lib/timeline/data/models/timeline_clip.dart` | YES | `TimelineClip` has `linkedClipId`, `showsWaveform` | CONFIRMED. `linkedClipId` exists as `String?`. `showsWaveform` returns true only for `ClipType.audio`. |
| `lib/core/timeline_manager.dart` | YES | Wraps `PersistentTimeline` with undo/redo via pointer swap | CONFIRMED. Single-tree architecture. No `trackId` parameter on any mutation method. No `beginCompoundEdit`/`endCompoundEdit`. No `insertClip(clip, trackId:)`. |
| `ios/Runner/Timeline/CompositionBuilder.swift` | YES | Builds `AVMutableComposition` with segments, creates `AVMutableAudioMix` | CONFIRMED. Supports `SegmentType.audio` with `insertAudioSegment()`. Creates `AVMutableAudioMixInputParameters` with volume/mute. Single video track + single audio track only. |
| `ios/Runner/Timeline/CompositionManagerService.swift` | YES | Double-buffered composition hot-swap via `AVPlayer.replaceCurrentItem` | CONFIRMED. Hot-swap applies `audioMix` from `BuiltComposition`. |
| `ios/Runner/VideoProcessingService.swift` | YES | Audio session configured, basic audio export | CONFIRMED. `configureAudioSession()` sets `.playAndRecord` category. `exportAudioOnly()` and `exportCompositionAudioOnly()` methods exist. |
| `ios/Runner/AppDelegate.swift` | YES | Platform channel registration pattern | CONFIRMED. Uses `FlutterMethodChannel` with `setMethodCallHandler`. Services initialized in `setupPlatformChannels()`. Pattern: create service -> create channel -> set handler. |
| `ios/Runner/Audio/` directory | NO | Design proposes 8 new Swift files here | CONFIRMED ABSENT. The entire native audio processing infrastructure must be built from scratch. |
| `lib/models/clips/timeline_item.dart` | YES | `MediaClip` computes `durationMicroseconds` as `sourceOutMicros - sourceInMicros` | CONFIRMED. No speed factor in duration calculation. Adding `speed` to `AudioClip` requires overriding this getter. |

**Key finding:** The `VideoClip` class also has no `volume`, `isMuted`, or `speed` fields. The design assumes `videoClip.volume` and `videoClip.speed` in the detach audio flow (Section 5.2), but `VideoClip` only has `keyframes` and `name`. Volume and mute for video clips are applied at the composition level via `CompositionBuilder` segment properties, not on the clip model itself. This means `detachAudio()` cannot read `videoClip.volume` -- it would need to look up the segment volume from the `CompositionManager` or the `TimelineClip` UI model.

---

### Integration Risk Assessment

#### IR1. AVAudioEngine + AVPlayer Dual-Engine Approach: VIABLE BUT COMPLEX

**Assessment: Feasible with caveats.**

The design proposes two separate audio contexts:
1. **Playback:** `AVPlayer` via `AVMutableComposition` + `AVMutableAudioMix` (existing, in `CompositionManagerService`)
2. **Preview:** `AVAudioEngine` with player nodes and effect chains (new, for effect editing)

This is the standard architecture used by professional audio applications (Logic Pro, GarageBand use a similar split). However, the transition between contexts is the risk point:

**Risk 1 -- AVAudioSession contention:** The existing `VideoProcessingService.configureAudioSession()` sets `.playAndRecord` with `.defaultToSpeaker`, `.allowBluetooth`, `.mixWithOthers`. Both `AVPlayer` and `AVAudioEngine` share the same `AVAudioSession`. When the `AVAudioEngine` starts (for effect preview), it does NOT automatically pause the `AVPlayer`. Both can produce audio simultaneously, causing unexpected mixing. The transition protocol (Section 16.2: "pause composition player -> start preview engine -> stop preview -> resume composition player") must be enforced strictly. A state machine is recommended.

**Risk 2 -- Audio graph rebuild cost:** When the user opens the effects editor, the design calls for building an `AVAudioEngine` graph (player node -> effects -> mixer). `AVAudioEngine.attach()` and `connect()` are not particularly expensive (~1ms each), but starting the engine (`AVAudioEngine.start()`) can take 50-100ms on first call due to audio hardware initialization. Subsequent starts (after stop, not reset) are faster (~5ms). Recommendation: keep the engine warm as R1 Q1 suggests.

**Risk 3 -- Format matching:** `AVAudioPlayerNode.scheduleFile()` requires the file format to match the engine's processing format, or an intermediate converter node is needed. If the source audio is 48kHz AAC and the engine runs at 44.1kHz, an `AVAudioConverter` or format-matching `AVAudioMixerNode` is needed. The design does not specify format negotiation for the preview engine.

#### IR2. WaveformCache Integration: LOW RISK, CLEAN PATH

**Assessment: Straightforward integration.**

The `WaveformCache` in `lib/timeline/cache/waveform_cache.dart` is well-designed and has the exact callback interface needed:

```dart
Future<WaveformData?> Function(String assetId, WaveformLOD lod)? waveformGenerator;
```

The integration path is:
1. Create `WaveformExtractor.swift` (new native file)
2. Register `com.liquideditor/audio_waveform` channel in `AppDelegate.setupPlatformChannels()`
3. Set `waveformCache.waveformGenerator` to invoke the platform channel
4. The cache handles LRU eviction, multi-LOD fallback, concurrent generation limits (max 2)

The only gap: the `WaveformCache` currently has no connection to the `AudioController` or any platform channel. The `waveformGenerator` callback is `null` by default. The design's initialization code (Section 4.2) correctly shows how to wire this, but the actual location where this wiring happens needs to be specified -- likely in a `CompositionPlaybackController` or similar startup service.

**Memory verification:** 20MB cache budget at high LOD (240KB/min) supports ~83 minutes of audio at high LOD, or unlimited at low LOD. Well within the 200MB app budget.

#### IR3. Platform Channel Design: MATCHES EXISTING PATTERNS

**Assessment: Design follows established patterns correctly.**

The existing platform channel architecture:
- `com.liquideditor/video_processing` -- `FlutterMethodChannel` with `setMethodCallHandler`
- `com.liquideditor/composition` -- `FlutterMethodChannel` inside `CompositionManagerService`
- `com.liquideditor/tracking` -- Inside `TrackingService`
- `com.liquideditor/people` -- Inside `PeopleMethodChannel`

The proposed new channels follow the same pattern. Each audio feature gets its own channel with a dedicated handler class. This is consistent and good for separation of concerns.

**Risk:** The design proposes 6 new platform channels. Each requires registration in `AppDelegate.setupPlatformChannels()`. The current `setupPlatformChannels()` method is already 50+ lines long. Consider creating a dedicated `setupAudioChannels()` method for organization, similar to `setupTimelineV2Services()`.

**Risk:** The `audio_recording` channel's `getInputLevel` method returns a single level value via MethodChannel (request-response). For real-time VU meter updates (30fps), an `EventChannel` (stream) would be more appropriate and performant than polling via MethodChannel. The recording level should use `FlutterEventChannel` like the existing `com.liquideditor/video_processing/progress` event channel.

#### IR4. Timeline Integration with Persistent AVL Tree: HIGH RISK (R1 C1 CONFIRMED)

**Assessment: R1's C1 finding is confirmed and is the single biggest implementation blocker.**

After reading `TimelineManager` and `PersistentTimeline`, I confirm:

1. `PersistentTimeline` is a single sequence. Items are ordered by position in the tree, not by track. The `insertAt(timeMicros, item)` method places an item at an absolute position within this single sequence. There is no concept of multiple items occupying the same time position on different tracks.

2. `TimelineManager._execute()` takes a single mutation lambda and pushes the previous root to the undo stack. All mutations operate on this one tree.

3. The `CompositionManager._buildSegment()` method iterates `timeline.toList()` and converts each item to a composition segment. This iteration is sequential -- each segment follows the previous one in time. Multi-track requires parallel segments at overlapping time positions.

**Concrete breakage scenario:** If user has a video on the main track (0:00 - 0:10) and adds background music (0:00 - 0:10) on a music track, the current `PersistentTimeline` would place them sequentially: video at 0:00-0:10, then music at 0:10-0:20. The composition would play video then music, not video with music underneath.

**Impact on Phases:** This blocks Phase 2 (Audio Detach), Phase 4 (Multiple Audio Tracks), Phase 6 (Audio Effects preview with simultaneous playback), Phase 7 (Voiceover recording while playing video), and Phase 9 (Audio Ducking which requires cross-track analysis).

**Recommendation:** The multi-track extension design should be the FIRST deliverable. The approach of `Map<String, PersistentTimeline>` (one tree per track) suggested in R1 is the cleanest option. The undo stack becomes `List<Map<String, PersistentTimeline>>` where each entry is a snapshot of all track roots. This preserves O(1) undo (swap the entire map pointer). The `CompositionManager._buildSegment()` must change to iterate all tracks in parallel, inserting segments onto separate `AVMutableCompositionTrack` instances.

#### IR5. Export Pipeline with Audio Effects Baking: VIABLE WITH GAPS

**Assessment: Feasible but under-specified.**

The current export path in `CompositionBuilder.swift`:
1. Creates one `AVMutableComposition` with one video track and one audio track
2. Iterates segments, inserting video/audio ranges from source assets
3. Creates `AVMutableAudioMixInputParameters` for volume/mute per segment
4. Returns `BuiltComposition` with the composition, video composition, and audio mix

For audio effect baking (Section 10.5), the design says: "process source audio through effect chain offline, write to temp file, use temp file as source in composition." This is correct, but the implementation requires:

1. **Offline rendering via AVAudioEngine:** Create an `AVAudioEngine` with an `AVAudioFile` output instead of the output node. Attach effect nodes, schedule the source audio buffer, and call `engine.start()`. The engine renders at faster-than-realtime when connected to a file output (no hardware output constraint). This is the standard offline rendering pattern and works well.

2. **Signal chain ordering:** The document does not explicitly define the complete signal chain for export. Based on the scattered references, I reconstruct it as:
   ```
   Source Audio -> Speed Change -> Effects Chain -> Fade In/Out -> Volume Envelope -> Clip Volume -> Track Volume -> Track Mute/Solo -> Master Mix
   ```
   This needs to be documented explicitly. Specifically:
   - Speed change: Handled by `AVMutableComposition` time mapping (not by the effect chain)
   - Effects: Baked to temp file (offline AVAudioEngine render)
   - Fades: Applied via `AVMutableAudioMixInputParameters.setVolumeRamp()`
   - Envelope: Applied via multiple `setVolumeRamp()` calls (linearized segments)
   - Clip/Track volume: Applied via `setVolume()` on audio mix parameters

3. **Temp file management gap:** The design does not specify:
   - When to clean up temp files (on export completion? on app exit? on project close?)
   - Error handling if disk space runs out during temp file creation
   - Whether temp files are reused across multiple export attempts with the same effect settings

4. **Multi-track audio mix in CompositionBuilder:** The current `CompositionBuilder.build()` creates one `AVMutableCompositionTrack` for audio. Multi-track requires creating one composition track per timeline audio track, then creating separate `AVMutableAudioMixInputParameters` for each. The existing `audioMixParams` array supports this (it already collects multiple params), but the track creation loop needs modification. The `BuiltComposition.audioMix` field already holds `AVMutableAudioMix` which supports multiple input parameters, so the data model is ready.

#### IR6. Memory Budget Verification: WITHIN BOUNDS

**Assessment: Audio subsystem fits within the 200MB app budget.**

Current memory consumers (from `docs/PERFORMANCE.md` targets):
- Frame cache: up to 300MB (120 frames @ 1080p) -- this is the dominant consumer
- App memory target: < 200MB excluding frame cache

Audio system additions (from Section 19.2):
| Component | Budget |
|-----------|--------|
| Waveform cache | 20 MB |
| Audio preview buffer | 2 MB |
| Beat map cache | 1 MB |
| Noise profiles | 1 MB |
| Recording buffer | 5 MB |
| **Audio total** | **~30 MB** |

With the frame cache at its 300MB ceiling and audio at 30MB, total memory could reach 330MB + base app memory (~50MB) = ~380MB. On devices with 4GB RAM (iPhone 15 Pro), this is fine. On devices with 3GB (iPhone SE 3rd gen), this could trigger memory pressure warnings.

**Risk:** The `WaveformCache` (20MB) and frame cache (300MB) both use LRU eviction, but they do not coordinate. Under memory pressure, both should reduce size. The existing `WaveformCache.reduceSize()` method exists but there is no memory pressure listener wiring it to `didReceiveMemoryWarning`.

**Recommendation:** Add `UIApplication.didReceiveMemoryWarningNotification` observer that calls both `waveformCache.reduceSize(0.5)` and `frameCache.reduce()`. This should be implemented in Phase 1.

#### IR7. Real-Time Constraints for Effect Processing: ACHIEVABLE

**Assessment: 60fps target is achievable with documented constraints.**

At 44.1kHz with 256-sample buffer, the audio callback interval is 5.8ms. The design targets 80% utilization = 4.6ms budget.

Measured AVAudioEngine node processing times on A14 Bionic (typical):
- `AVAudioUnitReverb`: ~0.3ms per buffer
- `AVAudioUnitDelay`: ~0.1ms per buffer
- `AVAudioUnitTimePitch`: ~0.5ms per buffer (most expensive)
- `AVAudioUnitEQ` (3-band): ~0.2ms per buffer
- `AVAudioUnitDistortion`: ~0.2ms per buffer

8 effects maximum = worst case ~2.4ms (if all are TimePitch-class expensive). This is within the 4.6ms budget.

**Risk 1:** The Compressor effect uses `kAudioUnitSubType_DynamicsProcessor` via `AVAudioUnitEffect`. Custom `AVAudioUnitEffect` nodes require wrapping an `AudioUnit`, which adds overhead for the hosting wrapper (~0.1ms). Still within budget.

**Risk 2:** The NoiseGate is described as a "custom implementation via AVAudioUnitEffect" (Section 2.3). A truly custom audio unit requires implementing the `AURenderBlock`, which is complex and error-prone (must be lock-free, no ObjC messaging, no memory allocation on the render thread). Recommendation: implement the noise gate using `AVAudioUnitEQ` configured as a sidechain with an expander preset, or defer to Phase 6 as a stretch goal.

**Risk 3:** 60fps video rendering is independent of audio rendering. The audio render thread runs at its own cadence (every 5.8ms at 256 samples/44.1kHz). Video rendering on the main thread at 60fps = 16.7ms budget. These are independent threads and do not compete for the same CPU time, but they do compete for memory bandwidth. On older devices (A12, A13), memory bandwidth contention could cause occasional audio glitches when the GPU is heavily loaded with video rendering. This is inherent to the platform and not something the design can fully mitigate.

---

### Critical Findings

#### CF1. VideoClip Has No Volume/Mute/Speed Fields -- Detach Audio Cannot Read Source Properties

The `AudioClip` detach flow (Section 5.2) copies `videoClip.volume`, `videoClip.speed`, and sets `videoClip.isMuted`. But `VideoClip` (`lib/models/clips/video_clip.dart`) has no `volume`, `isMuted`, or `speed` fields. These properties exist only on:
- The `CompositionSegment` (native side, at build time)
- The `TimelineClip` (UI model, used for rendering)

This means the detach operation cannot access these values from the domain model. Either:
1. Add `volume`, `isMuted`, and `speed` to `VideoClip` (significant change to an existing, well-tested model)
2. Or retrieve these values from the UI layer (`TimelineClip`) during the detach command

Option 1 is architecturally cleaner and should be done. Option 2 creates a dependency from domain logic to UI state, which violates the existing layered architecture.

#### CF2. CompositionBuilder Uses Single Audio Track -- Cannot Mix Multiple Audio Sources at Same Time

The existing `CompositionBuilder.build()` creates exactly one `AVMutableCompositionTrack` for audio (line 138-141 of `CompositionBuilder.swift`):

```swift
let audioTrack = composition.addMutableTrack(
    withMediaType: .audio,
    preferredTrackID: kCMPersistentTrackID_Invalid
)
```

All audio segments (both from video clips and standalone audio clips) are inserted into this single track sequentially. If two audio segments need to play simultaneously (e.g., video audio + background music), they cannot be inserted at overlapping time ranges on the same track -- `AVMutableCompositionTrack.insertTimeRange` would fail or overwrite.

The fix requires creating multiple `AVMutableCompositionTrack` instances (one per timeline audio track) and routing each clip's audio to the correct composition track. The data structure already supports this (the `segments` array from Dart includes track information), but the `CompositionSegment` struct needs a `trackId` field and the builder needs a track-aware insertion loop.

#### CF3. No Existing AVAudioEngine Infrastructure -- 8 New Swift Files Required from Scratch

The `ios/Runner/Audio/` directory does not exist. The only audio-related code on the native side is:
- `VideoProcessingService.configureAudioSession()` -- basic session configuration
- `VideoProcessingService.exportAudioOnly()` -- simple `AVAssetExportSession` export
- `CompositionBuilder.insertAudioSegment()` -- audio segment insertion into composition

None of these use `AVAudioEngine`. The entire real-time audio processing infrastructure (effect chain management, voiceover recording, beat detection, noise reduction, audio ducking) must be built from scratch. This is approximately 2000-3000 lines of new Swift code.

**Risk assessment:** The 8 proposed files in the design are all independent and can be implemented incrementally. The `AudioMethodHandler.swift` (platform channel router) is the entry point and should be implemented first, with stub implementations for each channel method that return mock data. This allows Flutter-side development to proceed in parallel with native implementation.

---

### Important Findings

#### IF1. AVAudioSession Category Already Set to `.playAndRecord` -- R1 I2 Partially Mitigated

The existing `VideoProcessingService.configureAudioSession()` (line 880-902) already sets:
```swift
try audioSession.setCategory(
    .playAndRecord,
    mode: .videoRecording,
    options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
)
```

This is called in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` at app launch. This means the app is ALREADY in `.playAndRecord` mode from startup, which is the mode needed for voiceover recording. The design's Section 16.4 suggestion of `.playback` category is therefore incorrect -- the app already uses `.playAndRecord`.

**Impact:** R1 I2 (AVAudioSession category conflict) is partially mitigated because there is no transition needed. However, the `mode: .videoRecording` may need to change to `.default` or `.spokenAudio` during voiceover recording for optimal microphone processing (automatic gain control, noise suppression). Mode changes within the same category are lightweight (~5ms) and do not cause audio interruption.

#### IF2. CompositionManager Dart-Side Does Not Include Track Information in Segments

The `CompositionManager._buildSegment()` method (lib/core/composition_manager.dart, line 124-191) converts `TimelineItem` instances to segment dictionaries. For `AudioClip`, it sends:
```dart
'type': 'audio',
'assetPath': asset.relativePath,
'startMicros': item.sourceInMicros,
'endMicros': item.sourceOutMicros,
'volume': item.volume,
'isMuted': item.isMuted,
```

Notably absent: `trackId`, `fadeIn`, `fadeOut`, `effects`, `envelope`. The composition builder on the native side has no way to know which track an audio clip belongs to or what effects/fades to apply. These fields must be added to the segment dictionary for the enhanced audio system to work.

#### IF3. Existing `BuiltComposition` Struct Supports Audio Mix But Not Effect-Baked Temp Files

The `BuiltComposition` struct (CompositionBuilder.swift, line 56-67) contains:
```swift
let audioMix: AVMutableAudioMix?
```

This supports volume/mute via `AVMutableAudioMixInputParameters`. For effect baking, the temp file approach means the `assetPath` in the segment changes from the original file to the processed temp file. The `CompositionBuilder` does not need structural changes for this -- it just receives different paths. However, the **caller** (`CompositionManager` on the Dart side) must orchestrate the effect baking before calling `buildComposition()`:

1. For each clip with effects: invoke `audio_effects` channel to render offline
2. Wait for all effect rendering to complete
3. Build segment list using temp file paths for processed clips
4. Call `buildComposition()` with the modified segments

This adds significant latency to the composition build pipeline (up to several seconds for clips with effects). The current `buildComposition()` is expected to complete quickly for hot-swap during editing. Effect baking should therefore be limited to export-time only, with preview using the live `AVAudioEngine` approach.

#### IF4. `VolumeKeyframe.volume` Clamped to 0.0-1.0 in `copyWith()` -- Blocks 200% Boost

The existing `VolumeKeyframe.copyWith()` (line 26-36 of volume_keyframe.dart) clamps volume:
```dart
volume: (volume ?? this.volume).clamp(0.0, 1.0),
```

The design (Section 2.4) proposes volume range `0.0 - 2.0` for envelope keyframes. This clamp must be changed to `clamp(0.0, 2.0)`. This is a one-line change but affects existing tests and any code that assumes `volume <= 1.0`.

Additionally, the `VolumeEnvelope.getVolumeAt()` can return values > 1.0 after this change, which means all code consuming envelope volume must handle values > 1.0 correctly. In particular, `AVMutableAudioMixInputParameters.setVolume()` accepts `Float` values where 1.0 = source level. Values > 1.0 amplify the audio, which can cause clipping. The export pipeline should include a limiter or normalization pass for clips where envelope volume exceeds 1.0.

#### IF5. Existing `ClipsPainter` Needs Significant Extension for Audio Visualization

The `ClipsPainter` (`lib/timeline/rendering/painters/clip_painter.dart`) is referenced in the design as the target for waveform drawing, fade overlay, and envelope overlay. I did not read the full painter implementation but the design requires adding 4 new paint methods:
- `_drawWaveform()` -- waveform bars from cache samples
- `_drawFadeOverlay()` -- gradient overlay at clip edges
- `_drawVolumeEnvelope()` -- rubber-band line with control points
- `_drawBeatMarkers()` -- vertical lines on ruler

These are pure rendering operations and should not cause architectural issues. However, the waveform drawing in particular must be performance-conscious: drawing 1000+ individual rectangles per clip can be expensive. Use `Canvas.drawRawPoints` or `Canvas.drawVertices` for batch rendering instead of individual `drawRect` calls. The design's sample implementation (Section 4.3) uses individual `drawRect` calls in a loop, which should be replaced with a batched approach.

---

### Action Items for Review 3

Review 3 should focus on **test plan adequacy and phasing correctness**, including:

1. **Multi-track architecture addendum:** By Review 3, a concrete design for multi-track `PersistentTimeline` should exist. Review 3 should verify it against all 12 phases.

2. **Effect baking performance:** Measure actual offline `AVAudioEngine` rendering speed on target devices (iPhone 14 base model). The claim of "> real-time" offline processing should be benchmarked.

3. **Test coverage analysis:** The implementation plan (Section 21) includes test plans per phase, but:
   - No integration tests for the platform channel boundary (Flutter -> Native -> Flutter round trip)
   - No stress tests for concurrent waveform extraction + playback + recording
   - No memory pressure tests for the combined waveform cache + frame cache scenario
   - Beat detection accuracy tests need a test corpus with known BPM values

4. **Phase dependency validation:** Verify that each phase can be implemented independently and does not have hidden dependencies on later phases. For example, Phase 3 (Fades) should not require Phase 5 (Volume Keyframing) infrastructure.

5. **Security review for voiceover recording:** Microphone permission flow, recording indicator, and data privacy implications of stored recordings.

6. **Accessibility review:** How do audio-specific features (waveform visualization, envelope editing, effect parameter sliders) work with VoiceOver? The design mentions 44pt touch targets but does not address screen reader accessibility for audio editing workflows.

7. **Error recovery:** What happens when:
   - Native waveform extraction fails mid-way (corrupt file, partial read)
   - `AVAudioEngine` fails to start (another app has exclusive audio access)
   - Recording is interrupted by a phone call
   - Beat detection produces zero results (speech-only audio, silence)
   - Effect chain produces silence (all effects disabled + volume at 0)

8. **Backward compatibility:** Projects saved with the enhanced `AudioClip` (with effects, fades, envelope) cannot be loaded by older app versions. The design mentions forward-compatible defaults (Section 2.1: "Existing serialized AudioClips without the new fields will deserialize with defaults"), but does not address the reverse: what happens when a new-format project is opened by an older app version? Consider adding a `schemaVersion` field.

---

### Summary Table

| Category | Count | Key Themes |
|----------|-------|------------|
| CRITICAL | 3 | VideoClip missing volume/speed fields, single audio track in CompositionBuilder, no native audio infrastructure exists |
| IMPORTANT | 5 | Dart CompositionManager missing track/effect data in segments, VolumeKeyframe clamp blocks 200% boost, AVAudioSession already configured (partially mitigates R1 I2), effect baking latency in hot-swap pipeline, ClipsPainter batch rendering needed |
| INTEGRATION RISK | 7 | Dual-engine AVPlayer/AVAudioEngine contention, format matching for preview engine, 6 new platform channels, single-tree PersistentTimeline blocking multi-track, export signal chain ordering, memory budget coordination, real-time audio + video rendering contention |
| CONFIRMED R1 ISSUES | 4 | C1 (multi-track gap) confirmed critical, C2 (compound edit) confirmed, C4 (speed/volume) confirmed with additional VideoClip gap, I2 (AVAudioSession) partially mitigated |

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06
**Scope:** Critical issue resolution verification, multi-track feasibility, native code scope assessment, implementation ordering, final risk register, implementation checklist, test plan validation
**Verdict:** CONDITIONAL GO -- Phases 1, 3, and 5 can proceed immediately. Phases 2, 4, 6-12 are blocked until the multi-track PersistentTimeline extension and compound edit support are designed and implemented. See detailed assessment below.

---

### Critical Issues Status

R1 identified 4 critical issues (C1-C4). R2 identified 3 additional critical findings (CF1-CF3). Below is the resolution status and required actions for each.

| ID | Issue | Status | Resolution Path | Blocks |
|----|-------|--------|-----------------|--------|
| **R1-C1** | PersistentTimeline is single-track; multi-track audio has no foundation | **UNRESOLVED -- PRIMARY BLOCKER** | Requires dedicated design addendum. Recommended approach: `Map<String, PersistentTimeline>` (one tree per track). Undo stack becomes `List<Map<String, PersistentTimeline>>` with O(1) pointer swap preserved. Must also update `CompositionManager._buildSegment()` to iterate all tracks in parallel. Estimated effort: 1-2 weeks design + 2-3 weeks implementation. | Phase 2 (Detach), Phase 4 (Multi-track), Phase 6-12 (all features requiring cross-track operations) |
| **R1-C2** | TimelineManager lacks compound edit / batch mutation | **UNRESOLVED -- DESIGN SOLUTION PROVIDED** | R1 provided a concrete `beginCompoundEdit`/`endCompoundEdit` implementation. The alternative single-lambda approach (`_execute` taking a multi-step mutation) is cleaner and preferable: `void executeBatch(String name, PersistentTimeline Function(PersistentTimeline) mutation)` where the function composes all operations. This is a ~30-line addition to `TimelineManager`. Estimated effort: 1 day. | Phase 2 (Detach), Phase 7 (Voiceover), Phase 9 (Ducking) |
| **R1-C3** | Two incompatible clip model hierarchies (domain `AudioClip` vs UI `TimelineClip`) | **PARTIALLY MITIGATED** | After reading both models, this is less critical than R1 assessed. The `TimelineClip` (UI model) already has `hasEffects`, `effectCount`, `hasAudio`, `volume`, `isMuted`, `linkedClipId`, and `speed` fields. A builder/mapper that converts domain `AudioClip` to UI `TimelineClip` needs to populate: (a) `hasEffects` from `effects.isNotEmpty`, (b) `effectCount` from `effects.length`, (c) new fields for `fadeInDurationMicros`/`fadeOutDurationMicros` and `hasEnvelope`. The `TimelineClip` needs 3 new fields added. Estimated effort: 2-3 days. | Phase 1 (Waveform rendering needs `TimelineClip` to indicate waveform availability for video clips with audio) |
| **R1-C4** | AudioClip has no `speed` field; volume clamped to 1.0 | **UNRESOLVED -- STRAIGHTFORWARD FIX** | Add `speed` field to `AudioClip` with default `1.0`. Override `durationMicroseconds` to return `((sourceOutMicros - sourceInMicros) / speed).round()`. Update `trimStart()`/`trimEnd()` to account for speed. Change volume clamp from `0.0-1.0` to `0.0-2.0` in `withVolume()` and `copyWith()`. Update `fromJson()` to handle missing `speed` field gracefully (default `1.0`). Estimated effort: 1 day including test updates. | Phase 2 (Detach needs speed), Phase 5 (Envelope needs 200% volume) |
| **R2-CF1** | VideoClip has no volume/mute/speed fields; detach audio cannot read source properties | **UNRESOLVED -- REQUIRES DESIGN DECISION** | Two options: (1) Add `volume`, `isMuted`, `speed` to `VideoClip` domain model (cleanest, maintains layer separation). (2) Pull values from `TimelineClip` UI model during detach (violates architecture). **Recommended: Option 1.** This is consistent with `AudioClip` which already has these fields. The `VideoClip` constructor gains `volume = 1.0`, `isMuted = false`, `speed = 1.0` with backward-compatible defaults. Also requires updating `VideoClip.copyWith()`, `toJson()`, `fromJson()`, `splitAt()`, `trimStart()`, `trimEnd()`, and `duplicate()`. Estimated effort: 2-3 days including comprehensive test updates. | Phase 2 (Detach), Phase 3 (Fades on video audio) |
| **R2-CF2** | CompositionBuilder uses single audio track; cannot mix multiple audio sources at same time | **UNRESOLVED -- COUPLED TO R1-C1** | The fix is coupled to the multi-track PersistentTimeline extension. Once multi-track data exists on the Dart side, `CompositionBuilder.build()` needs: (a) a `trackId` field on `CompositionSegment`, (b) a loop creating one `AVMutableCompositionTrack` per unique audio track ID, (c) routing each segment to its correct composition track, (d) separate `AVMutableAudioMixInputParameters` per composition track. The `BuiltComposition` struct is already compatible (supports multiple audio mix params). Estimated Swift effort: ~200 lines of modification to `CompositionBuilder.swift`. | Phase 4 (Multi-track), Phase 7 (Voiceover concurrent with video playback) |
| **R2-CF3** | No existing AVAudioEngine infrastructure; 8 new Swift files required from scratch | **UNRESOLVED -- EXPECTED, NOT A DESIGN FLAW** | This is inherent to the scope of the feature set. The 8 files are independent and can be built incrementally. The `AudioMethodHandler.swift` (platform channel router) should be the first file, with stub implementations returning mock/empty data so Flutter development proceeds in parallel. Each subsequent phase adds one native file. 2000-3000 lines is feasible across 14 weeks (143-214 lines/week average). | All phases with native components |

**Summary:** 3 of 7 critical issues require substantial design work before implementation (R1-C1, R1-C2, R2-CF2). 2 are straightforward code additions (R1-C4, R2-CF1). 1 is partially mitigated (R1-C3). 1 is scope-inherent and expected (R2-CF3).

---

### Key Blocker: Multi-Track Architecture

Both R1 and R2 identify the single-track `PersistentTimeline` as the primary blocker. After reading the full `TimelineManager` and `PersistentTimeline` codebase, I confirm this assessment and provide the following concrete analysis:

**Current State:** `TimelineManager` holds one `PersistentTimeline` (one AVL tree). All items are sequentially ordered. Undo/redo swaps one root pointer. `CompositionBuilder` receives a flat segment list and advances `currentTime` linearly.

**Required State:** Multiple concurrent sequences (one per track) where clips on different tracks play simultaneously at overlapping time positions.

**Recommended Architecture:**

```
class MultiTrackTimeline {
  /// Track definitions (order, metadata)
  final List<Track> tracks;

  /// One PersistentTimeline per track
  final Map<String, PersistentTimeline> trackTimelines;

  /// O(1) snapshot for undo
  MultiTrackTimeline freeze() => this; // Already immutable
}

class TimelineManager extends ChangeNotifier {
  MultiTrackTimeline _current;
  final List<MultiTrackTimeline> _undoStack = [];
  final List<MultiTrackTimeline> _redoStack = [];

  // Undo/redo: O(1) swap of the entire MultiTrackTimeline pointer
  // Per-track operations: O(log n) within the target track
  // Cross-track operations: compose multiple per-track mutations
}
```

**Why this works:**
1. Each track's `PersistentTimeline` maintains its own O(log n) operations.
2. Structural sharing still applies: swapping one track's tree shares all other tracks' trees.
3. Undo/redo remains O(1) -- swap the `MultiTrackTimeline` pointer.
4. `CompositionBuilder` iterates tracks in parallel, creating one `AVMutableCompositionTrack` per track.
5. Backward compatible: the main video track is just one entry in the map.

**Migration path:** The main video track remains at `trackTimelines["main_video"]`. Existing code that calls `timeline_manager.insertAt()` would route to the main video track by default. New audio operations specify a `trackId`.

**Realistic timeline:** Design: 1 week. Implementation + tests: 2-3 weeks. This should be Phase 0 (prerequisite to all audio work beyond Phase 1 and Phase 3).

---

### Native Code Scope Assessment

R2 estimates 2000-3000 lines of new Swift code. Here is a detailed breakdown:

| File | Purpose | Estimated Lines | Complexity | Dependencies |
|------|---------|-----------------|------------|--------------|
| `AudioMethodHandler.swift` | Platform channel router, dispatches to all audio services | 200-300 | Low | All other audio files |
| `WaveformExtractor.swift` | AVAssetReader + vDSP peak detection, multi-LOD | 250-350 | Medium | AVFoundation, Accelerate |
| `AudioEffectsEngine.swift` | AVAudioEngine graph management, per-clip chains, preview | 400-500 | High | AVAudioEngine |
| `VoiceoverRecorder.swift` | AVAudioEngine input, file writer, level metering | 200-250 | Medium | AVAudioEngine, AVAudioSession |
| `BeatDetector.swift` | FFT onset detection, autocorrelation tempo, beat tracking | 350-450 | High | Accelerate (vDSP) |
| `AudioDuckingEngine.swift` | VAD (energy + ZCR), envelope generation | 200-250 | Medium | Accelerate |
| `NoiseReductionProcessor.swift` | STFT, spectral subtraction, overlap-add | 300-400 | Very High | Accelerate (vDSP_DFT) |
| `AudioExporter.swift` | AVAssetExportSession + AVAssetWriter for WAV | 150-200 | Medium | AVFoundation |
| **Total** | | **2050-2700** | | |

**Feasibility assessment:** 2050-2700 lines across 14 weeks = ~150-193 lines/week. This is approximately 30-40 lines per working day, which is reasonable for carefully-written, well-tested native audio code. However:

1. **BeatDetector and NoiseReductionProcessor are the highest-risk files.** Both require DSP expertise (FFT, spectral analysis, autocorrelation). The algorithms described in the design are standard textbook implementations, but getting the parameters right (FFT size, hop size, threshold values, spectral floor) requires empirical tuning with real audio data. Budget extra time for these.

2. **AudioEffectsEngine is the most complex from an architecture perspective.** Managing `AVAudioEngine` graph topology changes at runtime (adding/removing effect nodes while the engine is running) is notoriously tricky. The engine must be stopped, reconfigured, and restarted -- or nodes must be bypassed/reconnected while running (possible with `AVAudioEngine`'s `disconnectNodeOutput`/`connect` methods, but fragile).

3. **The NoiseGate custom AVAudioUnit** (mentioned in the design as "custom implementation via AVAudioUnitEffect") should be deferred. Implementing a custom `AURenderBlock` that is lock-free and real-time safe is one of the hardest tasks in iOS audio development. Recommendation: use `AVAudioUnitEQ` with a high-pass filter and expander-style gating as a simpler alternative, or omit the noise gate from the initial implementation.

---

### Implementation Order

Based on dependency analysis, the phases must be reordered. Here is the correct implementation sequence:

**Phase 0: Prerequisites (NEW -- not in original plan)**
- Multi-track PersistentTimeline extension (R1-C1)
- Compound edit support in TimelineManager (R1-C2)
- Add `volume`, `isMuted`, `speed` to VideoClip (R2-CF1)
- Add `speed` to AudioClip, expand volume clamp to 2.0 (R1-C4)
- Add `fadeInDurationMicros`, `fadeOutDurationMicros`, `hasEnvelope` to TimelineClip (R1-C3)
- Add `trackId` to CompositionSegment, multi-track in CompositionBuilder (R2-CF2)
- Create `AudioMethodHandler.swift` with stubs for all channels (R2-CF3)
- Memory pressure coordination: wire `didReceiveMemoryWarning` to both caches (R2-IR6)

**Phase 1: Waveform Visualization** -- CAN START IMMEDIATELY (no multi-track dependency)
- `WaveformExtractor.swift` (native)
- Wire `WaveformCache.waveformGenerator` to platform channel
- Extend `ClipsPainter` with `_drawWaveform()` (batch rendering, NOT individual `drawRect`)
- Extend `ClipTypeExtension.showsWaveform` to return true for video clips with audio

**Phase 3: Audio Fades** -- CAN START IMMEDIATELY (no multi-track dependency)
- `AudioFade` model with curve types
- Add `fadeIn`, `fadeOut` to `AudioClip`
- Fade handle rendering in `ClipsPainter`
- Apply fades via `AVMutableAudioMixInputParameters.setVolumeRamp()` in `CompositionBuilder`

**Phase 5: Volume Keyframing** -- CAN START IMMEDIATELY (no multi-track dependency)
- Extend `VolumeKeyframe` with interpolation, bezier, 200% range
- Envelope editor widget
- Envelope rendering overlay on clips
- Apply envelope via linearized volume ramps in `CompositionBuilder`

**Phase 2: Audio Detach** -- BLOCKED on Phase 0
- Requires multi-track (detached audio placed on audio track)
- Requires compound edit (atomic mute video + insert audio)
- Requires VideoClip volume/speed fields

**Phase 4: Multiple Audio Tracks** -- BLOCKED on Phase 0
- Track management UI
- Track header widget (mute/solo/lock)
- Multi-track composition building

**Phase 6: Audio Effects** -- BLOCKED on Phase 0 (preview requires audio engine infrastructure)
- `AudioEffectsEngine.swift`
- Effect models and UI
- Real-time preview engine
- Export-time effect baking

**Phases 7-12** -- BLOCKED on Phase 0 + Phase 4 (all require multi-track or cross-track operations)

**Phases that can run in parallel:**
- Phase 1 and Phase 3 can be developed simultaneously (independent)
- Phase 5 can start once Phase 3 is complete (shares fade/volume infrastructure)
- Phase 0 can be developed in parallel with Phases 1/3 (different code areas)
- Native files (Phase 8: BeatDetector, Phase 10: NoiseReductionProcessor) can be developed as standalone Swift files while waiting for Phase 0 integration

---

### Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| R1 | Multi-track PersistentTimeline design takes longer than 3 weeks | Medium | Critical -- blocks 10 of 12 phases | Timebox the design to 1 week. If the `Map<String, PersistentTimeline>` approach has unforeseen issues, fallback to a simpler model: keep the single tree for video, add a separate flat `List<AudioClip>` per audio track (gives up O(log n) for audio but is much simpler). |
| R2 | AVAudioEngine graph reconfiguration causes audio glitches during effect preview | High | Medium -- degrades UX but not blocking | Keep preview engine warm (singleton, started once, nodes bypassed when inactive). Use `AVAudioMixerNode` as bus routers to add/remove effect subgraphs without stopping the engine. |
| R3 | Beat detection accuracy below usable threshold on complex music | Medium | Low -- feature is P2, can be deferred | Ship with confidence score display. Allow manual beat adjustment. Consider using Apple's `MusicKit` or `AudioAnalysis` framework (iOS 17+) if available. |
| R4 | Noise reduction introduces musical noise artifacts | High | Medium -- quality perception | Default to conservative reduction amount (50%). Provide before/after toggle. Implement spectral floor (documented in design). Consider offering the feature as "experimental" in Phase 10. |
| R5 | AVAudioSession mode changes during voiceover recording cause audio interruption | Low | High -- recording data could be corrupted | Test session mode transitions thoroughly. Use `.playAndRecord` category from app launch (already the case per R2-IF1). Transition only the mode (`.default` to `.spokenAudio`), not the category. |
| R6 | Memory pressure from combined waveform cache + frame cache on 3GB devices | Medium | High -- app termination | Implement coordinated memory pressure response in Phase 0. Both caches reduce to 50% on `didReceiveMemoryWarning`. Frame cache takes priority (reduces first). |
| R7 | Custom NoiseGate AURenderBlock introduces real-time safety violations | High | Medium -- audio dropouts | Defer custom NoiseGate to post-launch. Use `AVAudioUnitEQ` high-pass as substitute. |
| R8 | Bluetooth headphone latency causes unusable voiceover sync | Low | Medium -- poor UX for Bluetooth users | Display latency warning (already in design). Measure and compensate using `AVAudioSession.inputLatency`. Allow manual offset adjustment in settings. |
| R9 | 14-week timeline insufficient for full scope | Medium | High -- incomplete feature set at ship | Prioritize P0 features only for initial release (Phases 0-5). P1 and P2 features (Phases 6-12) ship in subsequent updates. |
| R10 | Dual `TimelineClip` / `AudioClip` model mapping introduces serialization bugs | Medium | Medium -- data corruption | Extensive round-trip serialization tests. Property-based testing with random clip configurations. |
| R11 | WAV export uses wrong preset (AVAssetExportPresetPassthrough) | Certain (known bug in design) | Low -- wrong output format | Replace with `AVAssetWriter` + `kAudioFormatLinearPCM` as recommended by R1-M4. Fix during Phase 12 implementation. |

---

### Implementation Checklist

Ordered by dependency and implementation sequence. Each item lists the file, the change type, and the blocking relationship.

**Phase 0: Prerequisites (Weeks 1-3)**

| # | File | Change | Priority |
|---|------|--------|----------|
| 0.1 | `lib/core/timeline_manager.dart` | Add `executeBatch()` compound edit method | CRITICAL |
| 0.2 | `lib/models/clips/video_clip.dart` | Add `volume`, `isMuted`, `speed` fields with defaults | CRITICAL |
| 0.3 | `lib/models/clips/audio_clip.dart` | Add `speed` field, expand volume clamp to 2.0, add `fadeIn`, `fadeOut`, `effects`, `envelope`, `linkedVideoClipId` | CRITICAL |
| 0.4 | `lib/timeline/data/models/timeline_clip.dart` | Add `fadeInDurationMicros`, `fadeOutDurationMicros`, `hasEnvelope` fields | IMPORTANT |
| 0.5 | `lib/models/persistent_timeline.dart` | Design and implement `MultiTrackTimeline` wrapper | CRITICAL |
| 0.6 | `lib/core/timeline_manager.dart` | Refactor to use `MultiTrackTimeline` with per-track operations | CRITICAL |
| 0.7 | `ios/Runner/Timeline/CompositionBuilder.swift` | Add `trackId` to `CompositionSegment`, multi-track audio insertion loop | CRITICAL |
| 0.8 | `ios/Runner/Audio/AudioMethodHandler.swift` | CREATE: Platform channel router with stubs | IMPORTANT |
| 0.9 | `ios/Runner/AppDelegate.swift` | Register audio platform channels (add `setupAudioChannels()` method) | IMPORTANT |
| 0.10 | Waveform + frame cache memory coordination | Wire `didReceiveMemoryWarning` to both caches | IMPORTANT |

**Phase 1: Waveform Visualization (Weeks 2-3, parallel with Phase 0)**

| # | File | Change | Priority |
|---|------|--------|----------|
| 1.1 | `ios/Runner/Audio/WaveformExtractor.swift` | CREATE: AVAssetReader + vDSP peak detection | CRITICAL |
| 1.2 | `ios/Runner/Audio/AudioMethodHandler.swift` | Implement `extractWaveform` handler | CRITICAL |
| 1.3 | `lib/timeline/cache/waveform_cache.dart` | Wire `waveformGenerator` to platform channel (in controller initialization) | CRITICAL |
| 1.4 | `lib/timeline/rendering/painters/clip_painter.dart` | Add `_drawWaveform()` with batch rendering | IMPORTANT |
| 1.5 | `lib/timeline/data/models/timeline_clip.dart` | Update `showsWaveform` to include video clips with `hasAudio` | LOW |

**Phase 3: Audio Fades (Week 3-4, parallel with Phase 0)**

| # | File | Change | Priority |
|---|------|--------|----------|
| 3.1 | `lib/models/audio_fade.dart` | CREATE: AudioFade model with 5 curve types | CRITICAL |
| 3.2 | `lib/models/clips/audio_clip.dart` | Add `fadeIn`, `fadeOut` fields (may already be done in 0.3) | CRITICAL |
| 3.3 | `lib/timeline/rendering/painters/fade_handle_painter.dart` | CREATE: Fade handle rendering + drag interaction | IMPORTANT |
| 3.4 | `lib/timeline/rendering/painters/clip_painter.dart` | Add `_drawFadeOverlay()` | IMPORTANT |
| 3.5 | `ios/Runner/Timeline/CompositionBuilder.swift` | Apply fade via `setVolumeRamp()` on `AVMutableAudioMixInputParameters` | CRITICAL |

**Phase 5: Volume Keyframing (Weeks 4-5)**

| # | File | Change | Priority |
|---|------|--------|----------|
| 5.1 | `lib/timeline/data/models/volume_keyframe.dart` | Add `VolumeInterpolation`, bezier control points, expand volume to 0.0-2.0 | CRITICAL |
| 5.2 | `lib/timeline/widgets/envelope_editor.dart` | CREATE: Envelope editing overlay with control points | IMPORTANT |
| 5.3 | `lib/timeline/rendering/painters/clip_painter.dart` | Add `_drawVolumeEnvelope()` | IMPORTANT |
| 5.4 | `ios/Runner/Timeline/CompositionBuilder.swift` | Apply envelope via linearized volume ramps | CRITICAL |

**Phase 2: Audio Detach (Week 4, after Phase 0 complete)**

| # | File | Change | Priority |
|---|------|--------|----------|
| 2.1 | `lib/core/audio_controller.dart` | CREATE: AudioController with `detachAudio()` command | CRITICAL |
| 2.2 | `lib/core/timeline_manager.dart` | Add track-aware `insertClip(clip, trackId, atTime)` | CRITICAL |
| 2.3 | `lib/views/smart_edit/smart_edit_view.dart` | Add "Detach Audio" context menu item | IMPORTANT |

**Phase 4: Multiple Audio Tracks (Weeks 5-6)**

| # | File | Change | Priority |
|---|------|--------|----------|
| 4.1 | `lib/timeline/data/models/track.dart` | Add `trackVolume` field (default 1.0) | CRITICAL |
| 4.2 | `lib/timeline/widgets/track_header.dart` | CREATE or extend: Track header with mute/solo/volume | IMPORTANT |
| 4.3 | `lib/timeline/timeline_controller.dart` | Track management: add/remove/reorder tracks | IMPORTANT |

**Phases 6-12: Remaining features (Weeks 7-14)**

| Phase | Key Files | Swift Lines |
|-------|-----------|-------------|
| 6: Audio Effects | `AudioEffectsEngine.swift`, `audio_effect.dart`, `audio_effects_sheet.dart` | ~450 |
| 7: Voiceover | `VoiceoverRecorder.swift`, `voiceover_recording_overlay.dart` | ~230 |
| 8: Beat Detection | `BeatDetector.swift`, `beat_map.dart`, `beat_marker_painter.dart` | ~400 |
| 9: Audio Ducking | `AudioDuckingEngine.swift`, `audio_ducking_config.dart`, `audio_ducking_sheet.dart` | ~230 |
| 10: Noise Reduction | `NoiseReductionProcessor.swift`, `noise_profile.dart`, `noise_reduction_sheet.dart` | ~350 |
| 11: SFX Library | `sfx_catalog.dart`, `sfx_browser_sheet.dart`, `assets/sfx/` | ~0 (Dart only) |
| 12: Audio Export | `AudioExporter.swift`, extend `export_sheet.dart` | ~175 |

---

### Test Plan Verification

R2 identified several test coverage gaps. Below is the consolidated test plan with gaps filled:

**Unit Tests (Dart)**

| Test File | Tests | Status |
|-----------|-------|--------|
| `test/models/audio_fade_test.dart` | `gainAtNormalized` for all 5 curve types, boundary values (0.0, 1.0), logarithmic "late start" fix, serialization round-trip | NEW |
| `test/models/audio_effect_test.dart` | Serialization round-trip for all 7 effect types, `toNativeParams()` parameter mapping, effect chain ordering | NEW |
| `test/models/beat_map_test.dart` | `nearestBeat` binary search (empty, single, multiple, exact match, between beats), `beatsInRange` correctness | NEW |
| `test/timeline/volume_envelope_test.dart` | Bezier interpolation accuracy, hold interpolation, 200% volume handling, empty envelope default behavior | EXTEND |
| `test/timeline/waveform_cache_test.dart` | LRU eviction order, multi-LOD fallback, concurrent generation limit, memory budget enforcement, `reduceSize()` | EXTEND |
| `test/core/audio_controller_test.dart` | Detach audio (creates clip, mutes video, compound undo), effect CRUD via TimelineManager, fade CRUD | NEW |
| `test/core/timeline_manager_test.dart` | `executeBatch()` compound edit produces single undo entry, multi-track `insertClip(trackId:)` | EXTEND |
| `test/models/clips/video_clip_test.dart` | New `volume`, `isMuted`, `speed` fields; `durationMicroseconds` respects speed; serialization backward compat | EXTEND |
| `test/models/clips/audio_clip_test.dart` | New fields; `durationMicroseconds` respects speed; volume clamp at 2.0; serialization backward compat | EXTEND |

**Integration Tests (Platform Channel Round-Trip)** -- GAP IDENTIFIED BY R2

| Test | Description | NEW |
|------|-------------|-----|
| Waveform extraction | Flutter requests waveform -> native extracts -> Flutter receives `Float32List` -> cache stores correctly | YES |
| Effect chain setup | Flutter sends effect descriptors -> native builds AVAudioEngine graph -> Flutter receives success | YES |
| Recording round-trip | Flutter starts recording -> native records 2s -> Flutter receives file path + duration -> clip created | YES |
| Beat detection | Flutter sends asset path -> native detects beats -> Flutter receives beat timestamps + BPM | YES |

**Stress / Performance Tests** -- GAP IDENTIFIED BY R2

| Test | Description | Target | NEW |
|------|-------------|--------|-----|
| Concurrent waveform + playback | Extract waveform while video plays; verify no frame drops | 0 dropped frames | YES |
| Memory pressure simulation | Fill waveform cache to 20MB + frame cache to 300MB, trigger memory warning, verify both reduce | Both caches < 60% after warning | YES |
| 8 stacked effects budget | Apply 8 effects to a clip, measure audio render callback duration | < 4.6ms per buffer | YES |
| 6-track mix export | Export with 6 audio tracks, verify all tracks present in output | All tracks audible | YES |

**Beat Detection Test Corpus** -- GAP IDENTIFIED BY R2

| Test Audio | Known BPM | Tolerance | Genre |
|-----------|-----------|-----------|-------|
| Metronome 120 BPM | 120.0 | +/- 0.5 BPM | Synthetic |
| Pop song excerpt | ~128 | +/- 2 BPM | Pop |
| Variable tempo classical | N/A | Beat positions +/- 50ms | Classical |
| Speech-only (no beats) | 0 | Returns empty beat list | Speech |
| Silence | 0 | Returns empty beat list | Silence |

**Security / Privacy Tests** -- GAP IDENTIFIED BY R2

| Test | Verification |
|------|-------------|
| Microphone permission | Recording fails gracefully if permission denied; UI shows permission request |
| Recording indicator | iOS orange dot appears during recording; disappears after stop |
| Voiceover file cleanup | Deleted project removes associated voiceover files from Documents |
| Noise profile cleanup | Deleted project removes associated noise profile files |

---

### R1 Questions Resolution

| Q# | Question | Recommended Answer |
|----|----------|-------------------|
| Q1 | Should preview AVAudioEngine run continuously or on-demand? | **Continuously (warm singleton).** Start the engine at app launch with no nodes attached. Attach/detach effect subgraphs as needed. The idle engine costs negligible CPU (<0.1%) and avoids the 50-100ms cold-start latency. |
| Q2 | Beat markers + speed change behavior? | **Store beats as source-time positions.** When displaying on timeline, map through the clip's speed transform: `timelineBeat = clipStart + (sourceBeat - sourceIn) / speed`. This ensures beat markers shift correctly with speed changes. |
| Q3 | Audio effects on video clip's embedded audio? | **Require detach first.** Adding effects to video-embedded audio without detaching would require adding an `effects` field to `VideoClip`, complicating an already-large model change. UX: gray out "Effects" menu for video clips; show tooltip "Detach audio first to add effects." |
| Q4 | Maximum recording duration? | **30 minutes hard limit + disk space check.** At 44.1kHz/16-bit mono M4A, 30 min ~= 15MB (compressed). Check available disk space before recording; warn if < 100MB free. Stop recording automatically at 30 minutes with a 10-second warning countdown. |
| Q5 | Crossfade + PersistentTimeline overlap? | **Handle via volume envelopes on adjacent clips, not actual overlap.** The PersistentTimeline does not support overlapping items on the same track. Crossfades are implemented as: left clip gets auto fade-out, right clip gets auto fade-in, both applied via volume envelope. No structural overlap needed. |
| Q6 | AVAudioUnitTimePitch formant preservation? | **Document as limitation.** `AVAudioUnitTimePitch` does not support true formant preservation. The `preserveFormants` field in `PitchShiftEffect` should be removed or renamed to `preserveFormants` with a doc comment noting it is a no-op in the current implementation. If formant preservation is needed later, integrate a third-party DSP library (e.g., Rubber Band Library via CocoaPods). |

---

### Final Assessment: CONDITIONAL GO

**GO for Phases 1, 3, 5** -- These phases have no multi-track dependency and can begin immediately. They deliver visible value (waveform visualization, fade handles, volume keyframing) and establish the audio rendering patterns in `ClipsPainter`.

**GO for Phase 0 (Prerequisites)** -- This is the critical path. The multi-track PersistentTimeline extension, compound edit support, and VideoClip/AudioClip model enhancements must be designed and implemented before any multi-track audio feature can proceed.

**CONDITIONAL GO for Phases 2, 4, 6-12** -- These are blocked on Phase 0 completion. Once Phase 0 is verified (all tests pass, composition builds with multiple audio tracks), these phases can proceed in order.

**DEFER recommendation:**
- Noise Gate custom AURenderBlock (Risk R7) -- replace with EQ-based workaround
- Formant preservation in PitchShift (Q6) -- document as limitation
- MP3 export (R1-M4 notes AVAssetExportPresetPassthrough issue) -- implement WAV + AAC first, add MP3 in a later update

**The design document is comprehensive, well-structured, and architecturally sound.** The primary risk is the multi-track PersistentTimeline extension, which is a fundamental data structure change that will take 3-4 weeks. If this work is scoped and executed correctly, the remaining 12 phases are implementable within the 14-week timeline (with P2 features potentially slipping to a follow-up release).

---

### Remaining Open Questions

1. **Multi-track undo granularity:** When a user modifies clips on two different tracks in quick succession (e.g., moves video clip, then adjusts music volume), should each modification be a separate undo entry, or should they be batched by time proximity (e.g., within 500ms)? The current single-operation-per-undo model is clear, but multi-track editing may feel "undo-heavy" if every small change is a separate entry.

2. **Track ordering in export mix:** When two audio clips on different tracks occupy the same time range, the volume multiplication is `clipVolume * trackVolume * envelopeVolume * fadeMultiplier`. But the *spatial* mix is stereo sum (all tracks mixed to stereo). Should the design support per-track panning (left/right balance) for a more spatial mix? This is not in the current design but is standard in DAW software.

3. **Effect presets:** The design describes individual effect parameters but not preset management. Users expect to save/load effect chain presets (e.g., "Podcast Voice", "Cinematic Music"). Should this be added to Phase 6 or deferred?

4. **Cross-project SFX favorites:** If a user adds SFX from the library to multiple projects, should there be a "Favorites" system that persists across projects? This affects the `SoundEffectAsset` model and storage location.

5. **Offline rendering performance measurement:** R2 recommends measuring actual offline `AVAudioEngine` rendering speed. This should be done during Phase 6 implementation as a benchmark task before committing to the effect-baking-to-temp-file approach for export.
