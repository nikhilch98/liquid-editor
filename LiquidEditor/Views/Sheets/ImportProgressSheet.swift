// ImportProgressSheet.swift
// LiquidEditor
//
// Import progress indicator with per-file status and cancel support.
// Pure iOS 26 SwiftUI with Liquid Glass styling.

import SwiftUI

// MARK: - ImportFileState

/// State of a single file import operation.
enum ImportFileState: String, CaseIterable, Sendable {
    case queued
    case copying
    case hashing
    case extractingMetadata
    case generatingThumbnail
    case complete
    case duplicate
    case failed
    case cancelled

    /// Whether this state represents an in-progress operation.
    var isInProgress: Bool {
        switch self {
        case .copying, .hashing, .extractingMetadata, .generatingThumbnail:
            return true
        default:
            return false
        }
    }

    /// Whether this state is terminal (no further transitions).
    var isTerminal: Bool {
        switch self {
        case .complete, .duplicate, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

// MARK: - ImportFileProgress

/// Progress information for a single file import.
struct ImportFileProgress: Identifiable, Sendable {
    /// Unique identifier for this file progress entry.
    let id: String

    /// Original filename for display.
    let filename: String

    /// Current state of the import.
    let state: ImportFileState

    /// Progress from 0.0 to 1.0 (meaningful only when in progress).
    let progress: Double

    /// Error message if the import failed.
    let errorMessage: String?

    init(
        id: String = UUID().uuidString,
        filename: String,
        state: ImportFileState = .queued,
        progress: Double = 0.0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.state = state
        self.progress = progress
        self.errorMessage = errorMessage
    }

    func with(
        state: ImportFileState? = nil,
        progress: Double? = nil,
        errorMessage: String?? = nil
    ) -> ImportFileProgress {
        ImportFileProgress(
            id: id,
            filename: filename,
            state: state ?? self.state,
            progress: progress ?? self.progress,
            errorMessage: errorMessage ?? self.errorMessage
        )
    }
}

// MARK: - ImportQueueProgress

/// Overall progress summary for the import queue.
struct ImportQueueProgress: Sendable {
    /// Total number of files in the queue.
    let totalFiles: Int

    /// Number of successfully completed files.
    let completedFiles: Int

    /// Number of failed files.
    let failedFiles: Int

    /// Number of duplicate files skipped.
    let duplicateFiles: Int

    /// Per-file progress entries.
    let fileProgress: [ImportFileProgress]

    /// Whether the import was cancelled.
    let isCancelled: Bool

    init(
        totalFiles: Int = 0,
        completedFiles: Int = 0,
        failedFiles: Int = 0,
        duplicateFiles: Int = 0,
        fileProgress: [ImportFileProgress] = [],
        isCancelled: Bool = false
    ) {
        self.totalFiles = totalFiles
        self.completedFiles = completedFiles
        self.failedFiles = failedFiles
        self.duplicateFiles = duplicateFiles
        self.fileProgress = fileProgress
        self.isCancelled = isCancelled
    }

    /// Overall progress as a fraction from 0.0 to 1.0.
    var overallProgress: Double {
        guard totalFiles > 0 else { return 0.0 }
        return Double(completedFiles + failedFiles + duplicateFiles) / Double(totalFiles)
    }

    /// Whether all files have been processed.
    var isComplete: Bool {
        completedFiles + failedFiles + duplicateFiles >= totalFiles
    }

    /// Number of files still remaining.
    var remainingFiles: Int {
        totalFiles - completedFiles - failedFiles - duplicateFiles
    }

    /// Human-readable summary text.
    var summaryText: String {
        var parts: [String] = []
        if completedFiles > 0 { parts.append("\(completedFiles) complete") }
        if duplicateFiles > 0 { parts.append("\(duplicateFiles) duplicate") }
        if failedFiles > 0 { parts.append("\(failedFiles) failed") }
        let remaining = remainingFiles
        if remaining > 0 { parts.append("\(remaining) remaining") }
        return parts.joined(separator: " | ")
    }
}

// MARK: - ImportProgressSheet

/// Displays import queue progress as a sheet overlay.
///
/// Shows per-file progress (up to 5 visible at once) with status icons,
/// an overall summary line, and cancel/retry/dismiss actions.
struct ImportProgressSheet: View {

    /// Current import queue progress.
    let progress: ImportQueueProgress

    /// Whether imports are currently being processed.
    let isProcessing: Bool

    /// Called when the user taps Cancel.
    var onCancel: (() -> Void)?

    /// Called when the user taps Done to dismiss.
    var onDismiss: (() -> Void)?

    /// Called when the user taps Retry Failed.
    var onRetryFailed: (() -> Void)?

    /// Maximum number of file rows to show before truncating.
    static let maxVisibleFiles = 5

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.md) {
            // Header row
            headerRow

            // Per-file progress rows
            fileProgressList

            // Summary
            Text(progress.summaryText)
                .font(LiquidTypography.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Import summary: \(progress.summaryText)")
        }
        .padding(LiquidSpacing.lg)
        .glassEffect(style: .thick, cornerRadius: LiquidSpacing.cornerLarge)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 4)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack {
            Text("Importing Media")
                .font(LiquidTypography.subheadlineSemibold)

            Spacer()

            if isProcessing {
                Button("Cancel", role: .destructive) {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    onCancel?()
                }
                .font(LiquidTypography.subheadline)
                .accessibilityHint("Cancels the ongoing media import")
            } else {
                HStack(spacing: LiquidSpacing.md) {
                    if progress.failedFiles > 0, onRetryFailed != nil {
                        Button("Retry Failed") {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            onRetryFailed?()
                        }
                        .font(LiquidTypography.subheadline)
                        .accessibilityHint("Retries importing the failed files")
                    }

                    Button("Done") {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onDismiss?()
                    }
                    .font(LiquidTypography.subheadline)
                }
            }
        }
    }

    // MARK: - File Progress List

    @ViewBuilder
    private var fileProgressList: some View {
        let visibleFiles = Array(progress.fileProgress.prefix(Self.maxVisibleFiles))

        ForEach(visibleFiles) { file in
            fileProgressRow(file)
        }

        if progress.fileProgress.count > Self.maxVisibleFiles {
            Text("+\(progress.fileProgress.count - Self.maxVisibleFiles) more...")
                .font(LiquidTypography.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - File Row

    @ViewBuilder
    private func fileProgressRow(_ file: ImportFileProgress) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
            HStack(spacing: LiquidSpacing.sm) {
                // Status icon
                statusIcon(for: file.state)
                    .frame(width: LiquidSpacing.iconSmall, height: LiquidSpacing.iconSmall)

                // Filename
                Text(file.filename)
                    .font(LiquidTypography.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Status text
                statusText(for: file)
                    .frame(width: 60, alignment: .trailing)
            }

            // Error detail for failed imports
            if file.state == .failed, let error = file.errorMessage {
                Text(error)
                    .font(LiquidTypography.caption2)
                    .foregroundStyle(LiquidColors.error)
                    .lineLimit(2)
                    .padding(.leading, LiquidSpacing.xxl)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.filename), \(file.state.rawValue)")
    }

    // MARK: - Status Icon

    @ViewBuilder
    private func statusIcon(for state: ImportFileState) -> some View {
        switch state {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LiquidColors.success)
                .font(LiquidTypography.caption)
                .accessibilityLabel("Complete")
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(LiquidColors.error)
                .font(LiquidTypography.caption)
                .accessibilityLabel("Failed")
        case .duplicate:
            Image(systemName: "doc.on.doc")
                .foregroundStyle(LiquidColors.warning)
                .font(LiquidTypography.caption)
                .accessibilityLabel("Duplicate")
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
                .font(LiquidTypography.caption)
                .accessibilityLabel("Cancelled")
        default:
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("In progress")
        }
    }

    // MARK: - Status Text

    @ViewBuilder
    private func statusText(for file: ImportFileProgress) -> some View {
        switch file.state {
        case .complete:
            Text("Done")
                .font(LiquidTypography.caption)
                .foregroundStyle(LiquidColors.success)
        case .failed:
            Text("Failed")
                .font(LiquidTypography.caption)
                .foregroundStyle(LiquidColors.error)
        case .duplicate:
            Text("Duplicate")
                .font(LiquidTypography.caption)
                .foregroundStyle(LiquidColors.warning)
        case .cancelled:
            Text("Cancelled")
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)
        case .queued:
            Text("Queued")
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)
        default:
            Text("\(Int(file.progress * 100))%")
                .font(LiquidTypography.caption)
                .foregroundStyle(LiquidColors.primary)
                .monospacedDigit()
        }
    }
}

// MARK: - Preview

#Preview("Importing") {
    ZStack {
        Color.black.ignoresSafeArea()

        ImportProgressSheet(
            progress: ImportQueueProgress(
                totalFiles: 5,
                completedFiles: 2,
                failedFiles: 1,
                duplicateFiles: 0,
                fileProgress: [
                    ImportFileProgress(filename: "vacation.mov", state: .complete),
                    ImportFileProgress(filename: "sunset_clip.mp4", state: .complete),
                    ImportFileProgress(
                        filename: "broken_file.avi",
                        state: .failed,
                        errorMessage: "Unsupported codec"
                    ),
                    ImportFileProgress(filename: "beach.mov", state: .copying, progress: 0.65),
                    ImportFileProgress(filename: "mountains.mp4", state: .queued),
                ]
            ),
            isProcessing: true,
            onCancel: {}
        )
        .padding()
    }
}

#Preview("Complete with failures") {
    ZStack {
        Color.black.ignoresSafeArea()

        ImportProgressSheet(
            progress: ImportQueueProgress(
                totalFiles: 3,
                completedFiles: 2,
                failedFiles: 1,
                duplicateFiles: 0,
                fileProgress: [
                    ImportFileProgress(filename: "clip1.mov", state: .complete),
                    ImportFileProgress(filename: "clip2.mov", state: .complete),
                    ImportFileProgress(filename: "clip3.avi", state: .failed, errorMessage: "File corrupted"),
                ]
            ),
            isProcessing: false,
            onDismiss: {},
            onRetryFailed: {}
        )
        .padding()
    }
}
