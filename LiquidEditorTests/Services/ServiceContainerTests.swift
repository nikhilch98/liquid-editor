import Testing
import Foundation
@testable import LiquidEditor

@Suite("ServiceContainer Tests")
@MainActor
struct ServiceContainerTests {

    // MARK: - Initialization

    @Test("ServiceContainer can be initialized with default init")
    func defaultInit() {
        let container = ServiceContainer()
        // Should not crash or throw
        #expect(container.repositories === RepositoryContainer.shared)
    }

    @Test("Shared singleton is accessible")
    func sharedSingleton() {
        let shared = ServiceContainer.shared
        #expect(shared.repositories === RepositoryContainer.shared)
    }

    // MARK: - Composition & Playback Services

    @Test("CompositionManager is accessible")
    func compositionManager() {
        let container = ServiceContainer()
        let _: CompositionManager = container.compositionManager
    }

    @Test("CompositionBuilder is accessible")
    func compositionBuilder() {
        let container = ServiceContainer()
        let _: CompositionBuilder = container.compositionBuilder
    }

    @Test("FrameCache is accessible")
    func frameCache() {
        let container = ServiceContainer()
        let _: FrameCache = container.frameCache
    }

    @Test("NativeDecoderPool is accessible")
    func decoderPool() {
        let container = ServiceContainer()
        let _: NativeDecoderPool = container.decoderPool
    }

    // MARK: - Export Service

    @Test("ExportService is accessible")
    func exportService() {
        let container = ServiceContainer()
        let _: ExportService = container.exportService
    }

    // MARK: - Audio Services

    @Test("AudioEffectsEngine is accessible")
    func audioEffectsEngine() {
        let container = ServiceContainer()
        let _: AudioEffectsEngine = container.audioEffectsEngine
    }

    @Test("WaveformExtractor is accessible")
    func waveformExtractor() {
        let container = ServiceContainer()
        let _: WaveformExtractor = container.waveformExtractor
    }

    @Test("VoiceoverRecorder is accessible")
    func voiceoverRecorder() {
        let container = ServiceContainer()
        let _: VoiceoverRecorder = container.voiceoverRecorder
    }

    // MARK: - Media Import

    @Test("MediaImportService is accessible")
    func mediaImportService() {
        let container = ServiceContainer()
        let _: MediaImportService = container.mediaImportService
    }

    // MARK: - Tracking

    @Test("TrackingService is accessible")
    func trackingService() {
        let container = ServiceContainer()
        let _: TrackingService = container.trackingService
    }

    // MARK: - Effects & Rendering

    @Test("EffectPipeline is accessible")
    func effectPipeline() {
        let container = ServiceContainer()
        let _: EffectPipeline = container.effectPipeline
    }

    @Test("TransitionRenderer is accessible")
    func transitionRenderer() {
        let container = ServiceContainer()
        let _: TransitionRenderer = container.transitionRenderer
    }

    @Test("ColorGradingPipeline is accessible")
    func colorGradingPipeline() {
        let container = ServiceContainer()
        let _: ColorGradingPipeline = container.colorGradingPipeline
    }

    @Test("MaskRenderer is accessible")
    func maskRenderer() {
        let container = ServiceContainer()
        let _: MaskRenderer = container.maskRenderer
    }

    // MARK: - Repository Access

    @Test("Repositories container is accessible")
    func repositoriesAccess() {
        let container = ServiceContainer()
        let repos: RepositoryContainer = container.repositories
        #expect(repos === RepositoryContainer.shared)
    }

    // MARK: - Lazy Services

    @Test("PlaybackEngine is lazily accessible")
    func playbackEngine() {
        let container = ServiceContainer()
        let _: PlaybackEngine = container.playbackEngine
    }

    @Test("ScrubController is lazily accessible")
    func scrubController() {
        let container = ServiceContainer()
        let _: ScrubController = container.scrubController
    }
}
