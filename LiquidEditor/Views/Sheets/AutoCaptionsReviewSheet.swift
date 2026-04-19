// AutoCaptionsReviewSheet.swift
// LiquidEditor
//
// Auto-Captions Review (F6-3).
//
// Displays the output of the auto-caption engine (STT) so the user can
// edit, delete, or re-run transcription before committing the result
// back to the timeline.
//
// This file intentionally bundles:
//   • `CaptionSegment` — simple value type for one caption row.
//   • `AutoCaptionEngine`     — minimal stub wrapper around
//     `SFSpeechRecognizer` / `SFSpeechURLRecognitionRequest`. Real STT
//     integration is deferred; the stub returns a deterministic sample
//     so the UI can be exercised end-to-end.
//   • `AutoCaptionsReviewViewModel` — state + commands.
//   • `AutoCaptionsReviewSheet`     — the SwiftUI sheet.
//
// Microphone + speech authorisation is routed through the injected
// `PermissionCoordinator` (never `.shared`).

import Foundation
import Observation
import Speech
import SwiftUI

// MARK: - CaptionSegment

/// A single caption row in seconds, with mutable text.
///
/// `id` is stable (UUID) so the SwiftUI `ForEach` can track edits across
/// re-runs without losing focus on an in-flight `TextField`.
struct CaptionSegment: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let startSec: Double
    let endSec: Double
    var text: String

    init(id: UUID = UUID(), startSec: Double, endSec: Double, text: String) {
        self.id = id
        self.startSec = startSec
        self.endSec = endSec
        self.text = text
    }

    /// Human-readable "mm:ss.t" timestamp, e.g. `00:04.2`.
    var formattedTimestamp: String {
        let total = max(0, startSec)
        let minutes = Int(total) / 60
        let seconds = total - Double(minutes * 60)
        return String(format: "%02d:%04.1f", minutes, seconds)
    }
}

// MARK: - CaptionLanguage

/// Locale options exposed in the language picker.
enum CaptionLanguage: String, CaseIterable, Identifiable, Sendable {
    case englishUS = "en-US"
    case englishGB = "en-GB"
    case spanishES = "es-ES"
    case frenchFR = "fr-FR"
    case germanDE = "de-DE"
    case japaneseJP = "ja-JP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .englishUS: return "English (US)"
        case .englishGB: return "English (UK)"
        case .spanishES: return "Spanish"
        case .frenchFR: return "French"
        case .germanDE: return "German"
        case .japaneseJP: return "Japanese"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

// MARK: - AutoCaptionEngine (stub)

/// Minimal stub of the Speech-To-Text engine.
///
/// Real implementation would use `SFSpeechRecognizer` with
/// `SFSpeechURLRecognitionRequest`. The stub returns a deterministic
/// three-segment transcript so the review UI can be used in the
/// simulator without audio I/O and without requiring actual speech
/// permission at review-sheet boot time.
///
/// Callers must have requested `.speech` + `.microphone` authorisation
/// before calling `transcribe(...)`.
@MainActor
@Observable
final class AutoCaptionEngine {

    // MARK: - Observable State

    /// True while a transcription job is running.
    private(set) var isTranscribing: Bool = false

    /// Error message surfaced to the UI (nil on success).
    var errorMessage: String?

    // MARK: - Init

    init() {}

    // MARK: - API

    /// Request `SFSpeechRecognizer` authorisation. Returns `true` when
    /// the user authorises speech recognition.
    static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Transcribe audio from `url` in the given language and return an
    /// ordered list of caption segments.
    ///
    /// Stub behaviour: returns three canned segments keyed off the
    /// selected language so the UI exercises editing / delete / re-run.
    /// The real implementation should stream partial results and
    /// convert `SFTranscriptionSegment` timestamps to `CaptionSegment`.
    func transcribe(
        audioURL: URL?,
        language: CaptionLanguage
    ) async -> [CaptionSegment] {
        isTranscribing = true
        defer { isTranscribing = false }

        // Simulated latency so the progress state is observable.
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Locale-aware canned transcript (stub only).
        let phrases: [String]
        switch language {
        case .englishUS, .englishGB:
            phrases = [
                "Welcome to Liquid Editor.",
                "Drag clips onto the timeline.",
                "Then export when you're happy."
            ]
        case .spanishES:
            phrases = [
                "Bienvenido a Liquid Editor.",
                "Arrastra clips a la línea de tiempo.",
                "Luego exporta cuando estés listo."
            ]
        case .frenchFR:
            phrases = [
                "Bienvenue sur Liquid Editor.",
                "Faites glisser des clips sur la timeline.",
                "Exportez ensuite quand vous êtes prêt."
            ]
        case .germanDE:
            phrases = [
                "Willkommen bei Liquid Editor.",
                "Ziehen Sie Clips auf die Timeline.",
                "Dann exportieren, wenn Sie zufrieden sind."
            ]
        case .japaneseJP:
            phrases = [
                "Liquid Editorへようこそ。",
                "クリップをタイムラインにドラッグします。",
                "準備ができたらエクスポートします。"
            ]
        }

        return phrases.enumerated().map { idx, text in
            let start = Double(idx) * 2.5
            return CaptionSegment(startSec: start, endSec: start + 2.3, text: text)
        }
    }
}

// MARK: - AutoCaptionsReviewViewModel

/// Owns the mutable list of caption segments, the selected language,
/// and coordinates re-running transcription via the engine.
@MainActor
@Observable
final class AutoCaptionsReviewViewModel {

    // MARK: - Observable State

    var segments: [CaptionSegment]
    var language: CaptionLanguage
    var errorMessage: String?

    // MARK: - Dependencies

    @ObservationIgnored
    let engine: AutoCaptionEngine

    @ObservationIgnored
    private let permissions: PermissionCoordinator

    @ObservationIgnored
    private let audioURL: URL?

    // MARK: - Init

    init(
        engine: AutoCaptionEngine = AutoCaptionEngine(),
        permissions: PermissionCoordinator,
        audioURL: URL? = nil,
        initialSegments: [CaptionSegment] = [],
        initialLanguage: CaptionLanguage = .englishUS
    ) {
        self.engine = engine
        self.permissions = permissions
        self.audioURL = audioURL
        self.segments = initialSegments
        self.language = initialLanguage
    }

    // MARK: - Commands

    /// Update a segment's text (used by each row's TextField binding).
    func updateText(for id: UUID, newText: String) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[idx].text = newText
    }

    /// Delete a segment by id.
    func deleteSegment(id: UUID) {
        segments.removeAll { $0.id == id }
    }

    /// Run transcription: require microphone + speech permission, then
    /// invoke the stub engine.
    func rerunTranscription() async {
        let micOK = await permissions.requestMicrophoneAccess()
        guard micOK else {
            errorMessage = "Microphone access is required for captions."
            return
        }
        let speechOK = await AutoCaptionEngine.requestSpeechAuthorization()
        guard speechOK else {
            errorMessage = "Speech recognition access was declined."
            return
        }
        let new = await engine.transcribe(audioURL: audioURL, language: language)
        segments = new
    }
}

// MARK: - AutoCaptionsReviewSheet

/// Modal review sheet for auto-generated captions.
@MainActor
struct AutoCaptionsReviewSheet: View {

    // MARK: - Inputs

    let onAccept: ([CaptionSegment]) -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var viewModel: AutoCaptionsReviewViewModel

    // MARK: - Init

    init(
        permissions: PermissionCoordinator,
        audioURL: URL? = nil,
        initialSegments: [CaptionSegment] = [],
        initialLanguage: CaptionLanguage = .englishUS,
        onAccept: @escaping ([CaptionSegment]) -> Void
    ) {
        self.onAccept = onAccept
        _viewModel = State(
            initialValue: AutoCaptionsReviewViewModel(
                permissions: permissions,
                audioURL: audioURL,
                initialSegments: initialSegments,
                initialLanguage: initialLanguage
            )
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidColors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    toolbar
                        .padding(LiquidSpacing.md)
                        .background(.ultraThinMaterial)

                    segmentsList

                    ctaRow
                        .padding(LiquidSpacing.md)
                        .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Review Captions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Captions",
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
    private var toolbar: some View {
        HStack(spacing: LiquidSpacing.md) {
            Button {
                Task { await viewModel.rerunTranscription() }
            } label: {
                Label("Re-run", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.engine.isTranscribing)

            Spacer(minLength: 0)

            Picker("Language", selection: $viewModel.language) {
                ForEach(CaptionLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Caption language")

            if viewModel.engine.isTranscribing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Transcribing")
            }
        }
    }

    @ViewBuilder
    private var segmentsList: some View {
        if viewModel.segments.isEmpty {
            emptyState
        } else {
            List {
                ForEach(viewModel.segments) { segment in
                    row(for: segment)
                }
                .onDelete { offsets in
                    for offset in offsets {
                        let id = viewModel.segments[offset].id
                        viewModel.deleteSegment(id: id)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func row(for segment: CaptionSegment) -> some View {
        HStack(alignment: .top, spacing: LiquidSpacing.sm) {
            Text(segment.formattedTimestamp)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
                .accessibilityLabel("Starts at \(segment.formattedTimestamp)")

            TextField(
                "Caption text",
                text: Binding(
                    get: { segment.text },
                    set: { viewModel.updateText(for: segment.id, newText: $0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)

            Button {
                viewModel.deleteSegment(id: segment.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete caption")
        }
        .padding(.vertical, LiquidSpacing.xs)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: LiquidSpacing.md) {
            Spacer()
            Image(systemName: "captions.bubble")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("No captions yet")
                .font(.headline)
            Text("Tap Re-run to generate captions from the project audio.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(LiquidSpacing.xl)
    }

    @ViewBuilder
    private var ctaRow: some View {
        HStack(spacing: LiquidSpacing.md) {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer(minLength: 0)

            Button {
                onAccept(viewModel.segments)
                dismiss()
            } label: {
                Label("Accept All", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.segments.isEmpty)
        }
    }
}
