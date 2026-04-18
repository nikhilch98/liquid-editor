// VoiceOverSheet.swift
// LiquidEditor
//
// Voice-over recording modal (F6-2).
//
// Implements a six-state machine (idle → countdown → recording → paused →
// reviewing → saving) for recording a voice over. Presents a large record
// button that morphs per state, a 3-2-1 countdown overlay, a real-time
// waveform during recording, and a review step with Save / Discard.
//
// Uses `AVAudioRecorder` for capture; microphone authorisation is routed
// through `PermissionCoordinator` (injected; no `.shared`).

import AVFoundation
import Observation
import SwiftUI

// MARK: - VOState

/// Six-state machine driving the voice-over flow.
enum VOState: Equatable, Sendable {
    case idle
    case countdown(secondsLeft: Int)
    case recording
    case paused
    case reviewing
    case saving
}

// MARK: - VoiceOverViewModel

/// Internal view model for the voice-over sheet.
///
/// Owns the state machine, the `AVAudioRecorder`, the optional playback
/// `AVAudioPlayer`, and a short rolling buffer of peak amplitudes for the
/// live waveform.
@MainActor
@Observable
final class VoiceOverViewModel {

    // MARK: - Public State

    /// Current state of the recorder.
    private(set) var state: VOState = .idle

    /// Rolling amplitude history (0...1), newest at the end.
    /// Size is bounded by `Self.maxAmplitudeSamples`.
    private(set) var amplitudes: [Float] = []

    /// Elapsed recorded seconds, updated live during `.recording`.
    private(set) var elapsedSeconds: TimeInterval = 0

    /// Error to present to the user (authorisation / recorder failure).
    var errorMessage: String?

    // MARK: - Constants

    /// Maximum number of samples kept in the rolling waveform buffer.
    static let maxAmplitudeSamples = 120

    /// Countdown start value (seconds).
    static let countdownStart = 3

    // MARK: - Dependencies

    @ObservationIgnored
    private let permissions: PermissionCoordinator

    // MARK: - Private state

    @ObservationIgnored
    private var recorder: AVAudioRecorder?

    @ObservationIgnored
    private var player: AVAudioPlayer?

    @ObservationIgnored
    private var countdownTask: Task<Void, Never>?

    @ObservationIgnored
    private var meterTask: Task<Void, Never>?

    @ObservationIgnored
    private var recordingURL: URL?

    @ObservationIgnored
    private var recordingStart: Date?

    // MARK: - Init

    init(permissions: PermissionCoordinator) {
        self.permissions = permissions
    }

    deinit {
        // AVAudioRecorder cleanup is safe from deinit; Task cancellation too.
        countdownTask?.cancel()
        meterTask?.cancel()
    }

    // MARK: - Public API

    /// User tapped the record button in `.idle`.
    func beginCountdown() async {
        guard case .idle = state else { return }
        let granted = await permissions.requestMicrophoneAccess()
        guard granted else {
            errorMessage = "Microphone access is required to record voice over."
            return
        }
        state = .countdown(secondsLeft: Self.countdownStart)
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: Self.countdownStart, through: 1, by: -1) {
                if Task.isCancelled { return }
                self.state = .countdown(secondsLeft: remaining)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if Task.isCancelled { return }
            await self.startRecording()
        }
    }

    /// Pause recording.
    func pause() {
        guard case .recording = state else { return }
        recorder?.pause()
        meterTask?.cancel()
        state = .paused
    }

    /// Resume from paused state.
    func resume() {
        guard case .paused = state else { return }
        recorder?.record()
        state = .recording
        startMetering()
    }

    /// Stop recording and move to review.
    func stopRecording() {
        let canStop: Bool = {
            if case .recording = state { return true }
            if case .paused = state { return true }
            return false
        }()
        guard canStop else { return }
        recorder?.stop()
        meterTask?.cancel()
        countdownTask?.cancel()
        recorder = nil
        if let url = recordingURL {
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
            } catch {
                errorMessage = "Could not prepare playback: \(error.localizedDescription)"
            }
        }
        state = .reviewing
    }

    /// Play the reviewed recording.
    func playReview() {
        guard case .reviewing = state else { return }
        player?.play()
    }

    /// Stop review playback.
    func stopReviewPlayback() {
        player?.stop()
        player?.currentTime = 0
    }

    /// Discard the recording and return to idle.
    func discard() {
        stopReviewPlayback()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        amplitudes.removeAll()
        elapsedSeconds = 0
        state = .idle
    }

    /// Save the recording; invokes `onSave` with the file URL.
    /// Transitions through `.saving` back to `.idle`.
    func save(onSave: (URL) -> Void) {
        guard case .reviewing = state, let url = recordingURL else { return }
        stopReviewPlayback()
        state = .saving
        onSave(url)
        // Reset for a potential next recording; caller owns the URL now.
        recordingURL = nil
        amplitudes.removeAll()
        elapsedSeconds = 0
        state = .idle
    }

    /// Cancel any pending work (called on sheet dismiss).
    func cancelAll() {
        countdownTask?.cancel()
        meterTask?.cancel()
        recorder?.stop()
        player?.stop()
        recorder = nil
        player = nil
    }

    // MARK: - Private

    private func startRecording() async {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("voiceover-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            guard rec.record() else {
                errorMessage = "Could not start recording."
                state = .idle
                return
            }
            recorder = rec
            recordingURL = url
            recordingStart = Date()
            amplitudes.removeAll()
            elapsedSeconds = 0
            state = .recording
            startMetering()
        } catch {
            errorMessage = "Recording failed: \(error.localizedDescription)"
            state = .idle
        }
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                if case .recording = self.state {
                    self.recorder?.updateMeters()
                    let power = self.recorder?.averagePower(forChannel: 0) ?? -160
                    // Map -60..0 dB to 0..1
                    let normalised = max(0, min(1, (power + 60) / 60))
                    var next = self.amplitudes
                    next.append(Float(normalised))
                    if next.count > Self.maxAmplitudeSamples {
                        next.removeFirst(next.count - Self.maxAmplitudeSamples)
                    }
                    self.amplitudes = next
                    if let start = self.recordingStart {
                        self.elapsedSeconds = Date().timeIntervalSince(start)
                    }
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 20Hz
            }
        }
    }
}

// MARK: - VoiceOverSheet

/// Modal voice-over recorder. Call `onSave` when the user commits a take.
@MainActor
struct VoiceOverSheet: View {

    // MARK: - Inputs

    /// Invoked with the final recording URL when the user saves.
    let onSave: (URL) -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var viewModel: VoiceOverViewModel

    // MARK: - Init

    init(permissions: PermissionCoordinator, onSave: @escaping (URL) -> Void) {
        self.onSave = onSave
        _viewModel = State(initialValue: VoiceOverViewModel(permissions: permissions))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidColors.background.ignoresSafeArea()

                VStack(spacing: LiquidSpacing.xl) {
                    header
                    waveformArea
                    Spacer(minLength: 0)
                    recordButtonRow
                    secondaryActionsRow
                }
                .padding(LiquidSpacing.xl)

                countdownOverlay
            }
            .navigationTitle("Voice Over")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.cancelAll()
                        dismiss()
                    }
                }
            }
            .alert(
                "Voice Over",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                ),
                actions: {
                    Button("OK", role: .cancel) { viewModel.errorMessage = nil }
                },
                message: { Text(viewModel.errorMessage ?? "") }
            )
        }
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var header: some View {
        VStack(spacing: LiquidSpacing.xs) {
            Text(stateTitle)
                .font(.title2.weight(.semibold))
            Text(stateSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var waveformArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                .fill(.ultraThinMaterial)

            switch viewModel.state {
            case .idle, .countdown, .saving:
                Image(systemName: "waveform")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            case .recording, .paused, .reviewing:
                WaveformView(amplitudes: viewModel.amplitudes)
                    .padding(.horizontal, LiquidSpacing.md)
            }

            if case .recording = viewModel.state {
                VStack {
                    HStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                        Text(formatElapsed(viewModel.elapsedSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(LiquidSpacing.md)
                    Spacer()
                }
            }
        }
        .frame(height: 180)
    }

    @ViewBuilder
    private var recordButtonRow: some View {
        Button(action: primaryAction) {
            ZStack {
                Circle()
                    .fill(primaryButtonColor)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                Image(systemName: primaryButtonSymbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(primaryAccessibilityLabel)
        .disabled(isPrimaryDisabled)
    }

    @ViewBuilder
    private var secondaryActionsRow: some View {
        HStack(spacing: LiquidSpacing.lg) {
            switch viewModel.state {
            case .recording:
                Button("Pause", systemImage: "pause.fill") { viewModel.pause() }
                    .buttonStyle(.bordered)
                Button("Stop", systemImage: "stop.fill") { viewModel.stopRecording() }
                    .buttonStyle(.borderedProminent)
            case .paused:
                Button("Resume", systemImage: "play.fill") { viewModel.resume() }
                    .buttonStyle(.borderedProminent)
                Button("Stop", systemImage: "stop.fill") { viewModel.stopRecording() }
                    .buttonStyle(.bordered)
            case .reviewing:
                Button("Play", systemImage: "play.fill") { viewModel.playReview() }
                    .buttonStyle(.bordered)
                Button("Discard", systemImage: "trash", role: .destructive) {
                    viewModel.discard()
                }
                .buttonStyle(.bordered)
                Button("Save", systemImage: "checkmark") {
                    viewModel.save(onSave: onSave)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            default:
                EmptyView()
            }
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var countdownOverlay: some View {
        if case .countdown(let seconds) = viewModel.state {
            Color.black.opacity(0.4).ignoresSafeArea()
            Text("\(seconds)")
                .font(.system(size: 144, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 12)
                .transition(.scale.combined(with: .opacity))
                .id(seconds)
                .accessibilityLabel("Recording in \(seconds) seconds")
        }
    }

    // MARK: - Derived

    private func primaryAction() {
        switch viewModel.state {
        case .idle:
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            Task { await viewModel.beginCountdown() }
        case .recording:
            viewModel.pause()
        case .paused:
            viewModel.resume()
        case .reviewing:
            viewModel.playReview()
        case .countdown, .saving:
            break
        }
    }

    private var primaryButtonSymbol: String {
        switch viewModel.state {
        case .idle, .paused: return "mic.fill"
        case .countdown: return "timer"
        case .recording: return "pause.fill"
        case .reviewing: return "play.fill"
        case .saving: return "checkmark"
        }
    }

    private var primaryButtonColor: Color {
        switch viewModel.state {
        case .idle, .paused: return .red
        case .countdown: return .orange
        case .recording: return .red
        case .reviewing: return .accentColor
        case .saving: return .green
        }
    }

    private var isPrimaryDisabled: Bool {
        switch viewModel.state {
        case .countdown, .saving: return true
        default: return false
        }
    }

    private var primaryAccessibilityLabel: String {
        switch viewModel.state {
        case .idle: return "Start recording"
        case .countdown: return "Countdown in progress"
        case .recording: return "Pause recording"
        case .paused: return "Resume recording"
        case .reviewing: return "Play recording"
        case .saving: return "Saving"
        }
    }

    private var stateTitle: String {
        switch viewModel.state {
        case .idle: return "Ready to record"
        case .countdown: return "Get ready…"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .reviewing: return "Review take"
        case .saving: return "Saving"
        }
    }

    private var stateSubtitle: String {
        switch viewModel.state {
        case .idle: return "Tap the mic to start a 3-second countdown."
        case .countdown: return "Recording starts automatically."
        case .recording: return "Speak clearly; watch the waveform."
        case .paused: return "Resume or finish the take."
        case .reviewing: return "Play back, then Save or Discard."
        case .saving: return "Hang on…"
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - WaveformView

/// Lightweight Canvas-based waveform renderer. Draws vertical bars whose
/// heights track the amplitude history.
private struct WaveformView: View {

    let amplitudes: [Float]

    var body: some View {
        Canvas { context, size in
            guard !amplitudes.isEmpty else { return }
            let barSpacing: CGFloat = 3
            let barCount = CGFloat(amplitudes.count)
            let totalSpacing = barSpacing * max(0, barCount - 1)
            let barWidth = max(1, (size.width - totalSpacing) / max(1, barCount))
            let midY = size.height / 2

            for (index, amplitude) in amplitudes.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                let height = max(2, CGFloat(amplitude) * size.height)
                let rect = CGRect(
                    x: x,
                    y: midY - height / 2,
                    width: barWidth,
                    height: height
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(.accentColor))
            }
        }
        .accessibilityLabel("Audio waveform")
    }
}
