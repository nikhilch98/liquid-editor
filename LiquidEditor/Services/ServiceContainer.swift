// ServiceContainer.swift
// LiquidEditor
//
// Dependency injection container for all service instances.
// Provides a shared singleton with default implementations and
// an initializer for injecting test doubles.
//
// Follows the same pattern as RepositoryContainer.swift.

import Foundation

// MARK: - ServiceContainer

/// Dependency injection container for all service instances.
///
/// Holds references to every service used across the application, allowing
/// the app to access services through a single entry point. The shared
/// singleton uses default (production) implementations; the custom
/// initializer accepts any conforming types for testing.
///
/// ## Production Usage
/// ```swift
/// let container = ServiceContainer.shared
/// let builder = container.compositionBuilder
/// try await container.compositionManager.play()
/// ```
///
/// ## Testing Usage
/// ```swift
/// let testContainer = ServiceContainer(
///     repositories: mockRepositories,
///     compositionManager: MockCompositionManager(),
///     ...
/// )
/// ```
///
/// Thread safety: The container itself is `@MainActor` for SwiftUI integration.
/// Individual services handle their own concurrency (actors, locks, or Sendable).
/// Heavy services use lazy initialization to avoid app launch delays.
@MainActor
final class ServiceContainer {

    // MARK: - Shared Instance

    /// Shared singleton instance with default implementations.
    static let shared = ServiceContainer()

    // MARK: - Repository Reference

    /// Reference to the repository container for persistence access.
    let repositories: RepositoryContainer

    // MARK: - Composition & Playback Services

    /// Double-buffered composition manager for zero-interruption playback.
    let compositionManager: CompositionManager

    /// Builds AVMutableComposition from timeline segments.
    let compositionBuilder: CompositionBuilder

    /// Central playback orchestrator coordinating composition, scrubbing, and caching.
    ///
    /// **Important:** Lazily initialized because it depends on compositionManager, frameCache,
    /// decoderPool, and scrubController. Must be accessed from `@MainActor` context only.
    lazy var playbackEngine: PlaybackEngine = {
        PlaybackEngine(
            compositionManager: compositionManager,
            frameCache: frameCache,
            decoderPool: decoderPool,
            scrubController: scrubController
        )
    }()

    /// LRU frame cache with predictive prefetching for ultra-low latency scrubbing.
    let frameCache: FrameCache

    /// Native decoder pool for multi-source frame extraction.
    let decoderPool: NativeDecoderPool

    /// Scrub controller coordinating frame cache with user scrubbing gestures.
    ///
    /// **Important:** Lazily initialized because it depends on frameCache and decoderPool.
    /// Must be accessed from `@MainActor` context only.
    lazy var scrubController: ScrubController = {
        ScrubController(
            frameCache: frameCache,
            decoderPool: decoderPool,
            timeline: PersistentTimeline()
        )
    }()

    // MARK: - Export Service

    /// Main export orchestrator managing the full video export lifecycle.
    let exportService: ExportService

    // MARK: - Audio Services

    /// Real-time audio effects processing via AVAudioEngine.
    let audioEffectsEngine: AudioEffectsEngine

    /// Waveform peak data extraction from audio assets.
    let waveformExtractor: WaveformExtractor

    /// Voiceover recording via the device microphone.
    let voiceoverRecorder: VoiceoverRecorder

    // MARK: - Project Services

    /// Versioned backup snapshot management for project directories.
    let projectBackupService: ProjectBackupService

    // MARK: - Media Import

    /// Media import from Photos library and file system.
    let mediaImportService: MediaImportService

    // MARK: - Tracking

    /// Video tracking using Apple Vision framework.
    let trackingService: TrackingService

    // MARK: - Effects & Rendering

    /// GPU-accelerated video effects processing pipeline.
    let effectPipeline: EffectPipeline

    /// CIFilter-based clip transition rendering.
    let transitionRenderer: TransitionRenderer

    /// 12-stage color grading pipeline.
    let colorGradingPipeline: ColorGradingPipeline

    /// GPU-accelerated mask rendering.
    let maskRenderer: MaskRenderer

    // MARK: - Default Initialization

    /// Create a container with default (production) implementations.
    ///
    /// Heavy services (PlaybackEngine, ScrubController) are lazily
    /// initialized to avoid blocking app launch.
    init() {
        self.repositories = RepositoryContainer.shared
        self.compositionManager = CompositionManager()
        self.compositionBuilder = CompositionBuilder()
        self.frameCache = FrameCache()
        self.decoderPool = NativeDecoderPool()
        self.exportService = ExportService()
        self.audioEffectsEngine = AudioEffectsEngine()
        self.waveformExtractor = WaveformExtractor()
        self.voiceoverRecorder = VoiceoverRecorder()
        self.projectBackupService = .shared
        self.mediaImportService = MediaImportService()
        self.trackingService = TrackingService()
        self.effectPipeline = EffectPipeline()
        self.transitionRenderer = TransitionRenderer()
        self.colorGradingPipeline = ColorGradingPipeline()
        self.maskRenderer = MaskRenderer()
    }

    // MARK: - Custom Initialization (Testing)

    /// Create a container with custom service implementations.
    ///
    /// Use this initializer to inject mock or stub services for
    /// unit and integration testing.
    ///
    /// - Parameters:
    ///   - repositories: Repository container (defaults to shared).
    ///   - compositionManager: Composition manager implementation.
    ///   - compositionBuilder: Composition builder implementation.
    ///   - frameCache: Frame cache implementation.
    ///   - decoderPool: Decoder pool implementation.
    ///   - exportService: Export service implementation.
    ///   - audioEffectsEngine: Audio effects engine implementation.
    ///   - waveformExtractor: Waveform extractor implementation.
    ///   - voiceoverRecorder: Voiceover recorder implementation.
    ///   - projectBackupService: Project backup service implementation.
    ///   - mediaImportService: Media import service implementation.
    ///   - trackingService: Tracking service implementation.
    ///   - effectPipeline: Effect pipeline implementation.
    ///   - transitionRenderer: Transition renderer implementation.
    ///   - colorGradingPipeline: Color grading pipeline implementation.
    ///   - maskRenderer: Mask renderer implementation.
    init(
        repositories: RepositoryContainer = .shared,
        compositionManager: CompositionManager,
        compositionBuilder: CompositionBuilder,
        frameCache: FrameCache,
        decoderPool: NativeDecoderPool,
        exportService: ExportService,
        audioEffectsEngine: AudioEffectsEngine,
        waveformExtractor: WaveformExtractor,
        voiceoverRecorder: VoiceoverRecorder,
        projectBackupService: ProjectBackupService = .shared,
        mediaImportService: MediaImportService,
        trackingService: TrackingService,
        effectPipeline: EffectPipeline,
        transitionRenderer: TransitionRenderer,
        colorGradingPipeline: ColorGradingPipeline,
        maskRenderer: MaskRenderer
    ) {
        self.repositories = repositories
        self.compositionManager = compositionManager
        self.compositionBuilder = compositionBuilder
        self.frameCache = frameCache
        self.decoderPool = decoderPool
        self.exportService = exportService
        self.audioEffectsEngine = audioEffectsEngine
        self.waveformExtractor = waveformExtractor
        self.voiceoverRecorder = voiceoverRecorder
        self.projectBackupService = projectBackupService
        self.mediaImportService = mediaImportService
        self.trackingService = trackingService
        self.effectPipeline = effectPipeline
        self.transitionRenderer = transitionRenderer
        self.colorGradingPipeline = colorGradingPipeline
        self.maskRenderer = maskRenderer
    }
}
