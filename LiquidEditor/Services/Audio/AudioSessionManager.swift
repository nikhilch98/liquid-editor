// AudioSessionManager.swift
// LiquidEditor
//
// Centralized audio session management for the application.
// Handles AVAudioSession configuration, interruption handling,
// and route change notifications.

@preconcurrency import AVFoundation

// MARK: - AudioSessionMode

/// Application-level audio session modes.
///
/// Each mode configures `AVAudioSession` with the appropriate
/// category, options, and mode for the use case.
enum AudioSessionMode: Sendable {
    /// Playback-only mode for timeline preview.
    ///
    /// Category: `.playback`
    /// Allows mixing with other apps if `mixWithOthers` is true.
    case playback(mixWithOthers: Bool = false)

    /// Recording mode for voiceover capture.
    ///
    /// Category: `.playAndRecord`
    /// Enables speaker output and Bluetooth input.
    case recording

    /// Monitoring mode for recording with playthrough.
    ///
    /// Category: `.playAndRecord`
    /// Enables speaker output and allows Bluetooth.
    case monitoring

    /// Editing mode with no active audio.
    ///
    /// Category: `.ambient`
    /// Mixes with other apps and allows silent switch.
    case editing

    /// Export mode for audio rendering.
    ///
    /// Category: `.playback`
    /// No mixing. Dedicated to audio rendering.
    case exporting
}

// MARK: - AudioSessionError

/// Errors thrown by AudioSessionManager operations.
enum AudioSessionError: Error, LocalizedError, Sendable {
    case configurationFailed(String)
    case activationFailed(String)
    case deactivationFailed(String)

    var errorDescription: String? {
        switch self {
        case .configurationFailed(let reason):
            "Audio session configuration failed: \(reason)"
        case .activationFailed(let reason):
            "Audio session activation failed: \(reason)"
        case .deactivationFailed(let reason):
            "Audio session deactivation failed: \(reason)"
        }
    }
}

// MARK: - AudioRouteInfo

/// Information about the current audio route.
struct AudioRouteInfo: Sendable {
    /// Output device names.
    let outputs: [String]

    /// Input device names.
    let inputs: [String]

    /// Whether headphones are connected.
    let hasHeadphones: Bool

    /// Whether Bluetooth audio is connected.
    let hasBluetooth: Bool

    /// Whether using the built-in speaker.
    let isBuiltInSpeaker: Bool
}

// MARK: - AudioSessionManager

/// Centralized manager for the application's AVAudioSession.
///
/// Provides a single point of control for audio session configuration
/// across the app. Handles:
/// - Mode-based session configuration (playback, recording, editing)
/// - Audio interruption handling (phone calls, alarms)
/// - Route change notifications (headphones plugged/unplugged)
/// - Audio route information queries
///
/// ## Concurrency
///
/// Uses `actor` isolation for state management. Notification
/// observers are registered on the main RunLoop and dispatch
/// into the actor for state updates.
///
/// ## Usage
///
/// ```swift
/// let manager = AudioSessionManager()
/// try await manager.configure(for: .playback())
/// try await manager.activate()
/// // ... use audio ...
/// try await manager.configure(for: .editing)
/// ```
actor AudioSessionManager {

    // MARK: - Properties

    /// The shared AVAudioSession instance.
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }

    /// Current audio session mode.
    private var currentMode: AudioSessionMode?

    /// Whether the session is currently active.
    private var isActive = false

    /// Callback invoked when an audio interruption begins.
    ///
    /// The Bool parameter indicates whether playback should be
    /// suspended (true) or can continue (false).
    private var onInterruptionBegan: (@Sendable (Bool) -> Void)?

    /// Callback invoked when an audio interruption ends.
    ///
    /// The Bool parameter indicates whether playback should resume.
    private var onInterruptionEnded: (@Sendable (Bool) -> Void)?

    /// Callback invoked when the audio route changes.
    private var onRouteChanged: (@Sendable (AudioRouteInfo) -> Void)?

    /// Notification observer tokens for cleanup.
    /// `nonisolated(unsafe)` allows access from deinit (nonisolated context).
    /// Safe because deinit is guaranteed to run after all actor-isolated access completes.
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?
    nonisolated(unsafe) private var routeChangeObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        // Notification observers are set up lazily when callbacks are registered
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    // MARK: - Configuration

    /// Configure the audio session for a specific mode.
    ///
    /// Sets the appropriate `AVAudioSession` category, mode, and
    /// options based on the requested application mode.
    ///
    /// - Parameter mode: The desired audio session mode.
    /// - Throws: `AudioSessionError.configurationFailed` on failure.
    func configure(for mode: AudioSessionMode) throws {
        do {
            switch mode {
            case .playback(let mixWithOthers):
                var options: AVAudioSession.CategoryOptions = []
                if mixWithOthers {
                    options.insert(.mixWithOthers)
                }
                try session.setCategory(.playback, mode: .default, options: options)

            case .recording:
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .allowBluetooth]
                )

            case .monitoring:
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .allowBluetooth]
                )

            case .editing:
                try session.setCategory(
                    .ambient,
                    mode: .default,
                    options: [.mixWithOthers]
                )

            case .exporting:
                try session.setCategory(.playback, mode: .default, options: [])
            }

            currentMode = mode
        } catch {
            throw AudioSessionError.configurationFailed(error.localizedDescription)
        }
    }

    /// Activate the audio session.
    ///
    /// - Throws: `AudioSessionError.activationFailed` on failure.
    func activate() throws {
        do {
            try session.setActive(true, options: [])
            isActive = true
        } catch {
            throw AudioSessionError.activationFailed(error.localizedDescription)
        }
    }

    /// Deactivate the audio session.
    ///
    /// Uses `.notifyOthersOnDeactivation` to allow other apps
    /// to resume their audio.
    ///
    /// - Throws: `AudioSessionError.deactivationFailed` on failure.
    func deactivate() throws {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
        } catch {
            throw AudioSessionError.deactivationFailed(error.localizedDescription)
        }
    }

    /// Configure and activate in a single call.
    ///
    /// - Parameter mode: The desired audio session mode.
    /// - Throws: `AudioSessionError` on failure.
    func configureAndActivate(for mode: AudioSessionMode) throws {
        try configure(for: mode)
        try activate()
    }

    // MARK: - Route Information

    /// Get information about the current audio route.
    ///
    /// - Returns: `AudioRouteInfo` describing the current inputs and outputs.
    nonisolated func currentRouteInfo() -> AudioRouteInfo {
        let route = AVAudioSession.sharedInstance().currentRoute

        let outputs = route.outputs.map(\.portName)
        let inputs = route.inputs.map(\.portName)

        let hasHeadphones = route.outputs.contains { output in
            output.portType == .headphones ||
            output.portType == .headsetMic
        }

        let hasBluetooth = route.outputs.contains { output in
            output.portType == .bluetoothA2DP ||
            output.portType == .bluetoothLE ||
            output.portType == .bluetoothHFP
        }

        let isBuiltInSpeaker = route.outputs.contains { output in
            output.portType == .builtInSpeaker
        }

        return AudioRouteInfo(
            outputs: outputs,
            inputs: inputs,
            hasHeadphones: hasHeadphones,
            hasBluetooth: hasBluetooth,
            isBuiltInSpeaker: isBuiltInSpeaker
        )
    }

    /// The current preferred sample rate.
    nonisolated var preferredSampleRate: Double {
        AVAudioSession.sharedInstance().sampleRate
    }

    /// Whether the session is currently active.
    var sessionIsActive: Bool { isActive }

    /// The current audio session mode.
    var activeMode: AudioSessionMode? { currentMode }

    // MARK: - Interruption Handling

    /// Register a callback for audio interruption events.
    ///
    /// - Parameters:
    ///   - onBegan: Called when an interruption begins. The Bool indicates
    ///     whether the app should suspend audio (true = should suspend).
    ///   - onEnded: Called when an interruption ends. The Bool indicates
    ///     whether the app should resume audio (true = should resume).
    func setInterruptionHandler(
        onBegan: @escaping @Sendable (Bool) -> Void,
        onEnded: @escaping @Sendable (Bool) -> Void
    ) {
        self.onInterruptionBegan = onBegan
        self.onInterruptionEnded = onEnded

        // Remove existing observer if any
        if let existing = interruptionObserver {
            NotificationCenter.default.removeObserver(existing)
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // Extract Sendable data from notification before crossing actor boundary
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt else {
                return
            }
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { await self.handleInterruption(typeValue: typeValue, optionsValue: optionsValue) }
        }
    }

    /// Register a callback for audio route change events.
    ///
    /// - Parameter handler: Called with the new route information
    ///   whenever the audio route changes.
    func setRouteChangeHandler(
        _ handler: @escaping @Sendable (AudioRouteInfo) -> Void
    ) {
        self.onRouteChanged = handler

        // Remove existing observer if any
        if let existing = routeChangeObserver {
            NotificationCenter.default.removeObserver(existing)
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleRouteChange() }
        }
    }

    // MARK: - Notification Handling

    /// Handle an audio interruption with pre-extracted Sendable values.
    private func handleInterruption(typeValue: UInt, optionsValue: UInt?) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            isActive = false
            let shouldSuspend = true
            onInterruptionBegan?(shouldSuspend)

        case .ended:
            var shouldResume = false
            if let optionsValue {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            }

            if shouldResume {
                try? session.setActive(true, options: [])
                isActive = true
            }
            onInterruptionEnded?(shouldResume)

        @unknown default:
            break
        }
    }

    /// Handle an audio route change notification.
    private func handleRouteChange() {
        let routeInfo = currentRouteInfo()
        onRouteChanged?(routeInfo)
    }
}
