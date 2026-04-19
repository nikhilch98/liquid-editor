// SourceMonitorView.swift
// LiquidEditor
//
// E4-13: Source Monitor + 3/4-point Editing (XL).
//
// Full-screen sheet presenting a source monitor (left) and program
// monitor (right) side-by-side, with a timecode rail along the bottom
// exposing In / Out / Insert / Overwrite controls. Supports classic
// non-linear editor workflows:
//
//   - 3-point edit: source In + source Out + program In → Out is
//     computed as program In + (source Out − source In).
//   - 4-point edit: source In + source Out + program In + program Out →
//     "fit to fill" via an automatic speed adjustment that retimes the
//     source selection to exactly match the program range.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §4.
//
// Notes:
// - Pure SwiftUI + Liquid Glass surfaces.
// - Preview surfaces are placeholder glass cards — actual frame
//   rendering is wired by the editor when a clip URL is supplied.
// - @Observable VM holds the source clip + edit points; the sheet
//   reads/writes that VM only (no global state).

import SwiftUI
import Foundation

// MARK: - SourceMonitorViewModel

/// State holder for the source monitor sheet. Tracks the current
/// source clip, playhead position, and the in / out marks for both
/// source and program sides.
@MainActor
@Observable
final class SourceMonitorViewModel {

    // MARK: - Source side

    /// URL of the source clip being scrubbed in the monitor.
    var sourceURL: URL?

    /// Duration of the source clip in seconds.
    var sourceDurationSeconds: Double

    /// Current playhead position in the source, in seconds.
    var sourcePlayheadSeconds: Double

    /// Source In mark (seconds into the source clip).
    var sourceInSeconds: Double?

    /// Source Out mark (seconds into the source clip).
    var sourceOutSeconds: Double?

    // MARK: - Program side

    /// Program (timeline) playhead in seconds.
    var programPlayheadSeconds: Double

    /// Program In mark (seconds along the program timeline).
    var programInSeconds: Double?

    /// Program Out mark (seconds along the program timeline).
    var programOutSeconds: Double?

    // MARK: - Init

    init(
        sourceURL: URL? = nil,
        sourceDurationSeconds: Double = 0,
        sourcePlayheadSeconds: Double = 0,
        programPlayheadSeconds: Double = 0
    ) {
        self.sourceURL = sourceURL
        self.sourceDurationSeconds = sourceDurationSeconds
        self.sourcePlayheadSeconds = sourcePlayheadSeconds
        self.programPlayheadSeconds = programPlayheadSeconds
    }

    // MARK: - Mark controls

    func markSourceIn() { sourceInSeconds = sourcePlayheadSeconds }
    func markSourceOut() { sourceOutSeconds = sourcePlayheadSeconds }
    func markProgramIn() { programInSeconds = programPlayheadSeconds }
    func markProgramOut() { programOutSeconds = programPlayheadSeconds }

    func clearMarks() {
        sourceInSeconds = nil
        sourceOutSeconds = nil
        programInSeconds = nil
        programOutSeconds = nil
    }

    // MARK: - Edit computations

    /// Duration of the source selection in seconds, or `nil` if
    /// incomplete.
    var sourceSelectionDurationSeconds: Double? {
        guard let sIn = sourceInSeconds, let sOut = sourceOutSeconds, sOut > sIn else {
            return nil
        }
        return sOut - sIn
    }

    /// Duration of the program selection in seconds, or `nil` if
    /// incomplete.
    var programSelectionDurationSeconds: Double? {
        guard let pIn = programInSeconds, let pOut = programOutSeconds, pOut > pIn else {
            return nil
        }
        return pOut - pIn
    }

    /// Whether a 3-point edit can be performed (source In + source Out
    /// + program In, program Out inferred from source duration).
    var canPerform3PointEdit: Bool {
        sourceSelectionDurationSeconds != nil && programInSeconds != nil
    }

    /// Whether a 4-point edit can be performed (source In + Out + both
    /// program marks; resolves via speed fit-to-fill).
    var canPerform4PointEdit: Bool {
        sourceSelectionDurationSeconds != nil && programSelectionDurationSeconds != nil
    }

    // MARK: - Edit results

    /// Resolves the 3-point edit to the equivalent `SourceMonitorEdit`.
    /// Returns `nil` when the required marks are missing.
    func resolve3PointEdit(kind: SourceMonitorEditKind) -> SourceMonitorEdit? {
        guard let sIn = sourceInSeconds,
              let sOut = sourceOutSeconds,
              let pIn = programInSeconds,
              let sourceDur = sourceSelectionDurationSeconds else {
            return nil
        }
        let pOut = pIn + sourceDur
        return SourceMonitorEdit(
            kind: kind,
            sourceInSeconds: sIn,
            sourceOutSeconds: sOut,
            programInSeconds: pIn,
            programOutSeconds: pOut,
            speedMultiplier: 1.0
        )
    }

    /// Resolves the 4-point edit to an edit descriptor with a computed
    /// `speedMultiplier` that fits the source selection exactly into
    /// the program selection.
    func resolve4PointEdit(kind: SourceMonitorEditKind) -> SourceMonitorEdit? {
        guard let sIn = sourceInSeconds,
              let sOut = sourceOutSeconds,
              let pIn = programInSeconds,
              let pOut = programOutSeconds,
              let sourceDur = sourceSelectionDurationSeconds,
              let programDur = programSelectionDurationSeconds,
              programDur > 0 else {
            return nil
        }
        let speed = sourceDur / programDur
        return SourceMonitorEdit(
            kind: kind,
            sourceInSeconds: sIn,
            sourceOutSeconds: sOut,
            programInSeconds: pIn,
            programOutSeconds: pOut,
            speedMultiplier: speed
        )
    }
}

// MARK: - Edit kinds / descriptors

enum SourceMonitorEditKind: String, Sendable, Hashable {
    case insert
    case overwrite
}

/// The resolved edit payload emitted by a 3- or 4-point commit. Caller
/// translates this into a timeline mutation.
struct SourceMonitorEdit: Sendable, Hashable {
    let kind: SourceMonitorEditKind
    let sourceInSeconds: Double
    let sourceOutSeconds: Double
    let programInSeconds: Double
    let programOutSeconds: Double
    /// Speed applied to the source selection to fit into the program
    /// range (`1.0` for straight 3-point; computed for 4-point).
    let speedMultiplier: Double
}

// MARK: - SourceMonitorView

/// Full-screen sheet presenting source + program monitors with the
/// 3/4-point edit rail along the bottom.
@MainActor
struct SourceMonitorView: View {

    // MARK: - Inputs

    @Bindable var viewModel: SourceMonitorViewModel

    /// Commit callback — parent translates the edit into a timeline
    /// mutation.
    let onCommit: (SourceMonitorEdit) -> Void

    /// Dismiss callback.
    let onClose: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monitorsRow
                Divider().opacity(0.2)
                timecodeRail
            }
            .background(.black.opacity(0.95))
            .navigationTitle("Source Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Monitors

    private var monitorsRow: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                monitorCard(
                    title: "Source",
                    playhead: viewModel.sourcePlayheadSeconds,
                    duration: viewModel.sourceDurationSeconds,
                    inMark: viewModel.sourceInSeconds,
                    outMark: viewModel.sourceOutSeconds
                )
                .frame(width: (geo.size.width - 12) / 2)

                monitorCard(
                    title: "Program",
                    playhead: viewModel.programPlayheadSeconds,
                    duration: nil,
                    inMark: viewModel.programInSeconds,
                    outMark: viewModel.programOutSeconds
                )
                .frame(width: (geo.size.width - 12) / 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func monitorCard(
        title: String,
        playhead: Double,
        duration: Double?,
        inMark: Double?,
        outMark: Double?
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Text(Self.formatTime(playhead))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                if let inMark {
                    markerChip(symbol: "arrow.right.to.line.compact", value: inMark, tint: .green)
                }
                if let outMark {
                    markerChip(symbol: "arrow.left.to.line.compact", value: outMark, tint: .orange)
                }
                if let duration {
                    Text("/ \(Self.formatTime(duration))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private func markerChip(symbol: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2)
            Text(Self.formatTime(value))
                .font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.25))
        .foregroundStyle(tint)
        .clipShape(Capsule())
    }

    // MARK: - Timecode rail

    private var timecodeRail: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                markButton(title: "Mark In (Src)", symbol: "arrow.right.to.line.compact") {
                    viewModel.markSourceIn()
                }
                markButton(title: "Mark Out (Src)", symbol: "arrow.left.to.line.compact") {
                    viewModel.markSourceOut()
                }
                Spacer(minLength: 8)
                markButton(title: "Mark In (Prg)", symbol: "arrow.right.to.line") {
                    viewModel.markProgramIn()
                }
                markButton(title: "Mark Out (Prg)", symbol: "arrow.left.to.line") {
                    viewModel.markProgramOut()
                }
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    viewModel.clearMarks()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)

                Spacer()

                commitButton(kind: .insert, title: "Insert", symbol: "arrow.right.square")
                commitButton(kind: .overwrite, title: "Overwrite", symbol: "square.on.square")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func markButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func commitButton(kind: SourceMonitorEditKind, title: String, symbol: String) -> some View {
        Button {
            commit(kind: kind)
        } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canCommit)
    }

    private var canCommit: Bool {
        viewModel.canPerform3PointEdit || viewModel.canPerform4PointEdit
    }

    private func commit(kind: SourceMonitorEditKind) {
        let edit: SourceMonitorEdit?
        if viewModel.canPerform4PointEdit {
            edit = viewModel.resolve4PointEdit(kind: kind)
        } else {
            edit = viewModel.resolve3PointEdit(kind: kind)
        }
        guard let edit else { return }
        onCommit(edit)
    }

    // MARK: - Helpers

    private static func formatTime(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let hours = Int(total) / 3600
        let minutes = (Int(total) / 60) % 60
        let secs = Int(total) % 60
        let frames = Int((total - floor(total)) * 30.0)
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
    }
}
