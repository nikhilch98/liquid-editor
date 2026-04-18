// ExportQueueSheet.swift
// LiquidEditor
//
// Sheet listing every export job currently known to the queue, with a
// "Clear completed" affordance. Each row renders the project label, the
// preset summary, a progress bar, ETA, and a Cancel button (for active
// jobs) or a Remove button (for terminal jobs).
//
// Wiring:
//   Consumes a concrete `[ExportJob]` snapshot and a callback surface so
//   the sheet stays driver-agnostic. The editor chrome is responsible for
//   polling `ExportQueue.allJobs` on open / refresh. Observing the actor
//   directly from SwiftUI is out of scope for this task.

import SwiftUI

// MARK: - ExportQueueSheet

struct ExportQueueSheet: View {

    // MARK: - Inputs

    /// Current queue snapshot. Pass `[]` when empty.
    let jobs: [ExportJob]

    /// Invoked to cancel a job by id.
    var onCancel: (String) -> Void = { _ in }

    /// Invoked to remove a terminal job by id.
    var onRemove: (String) -> Void = { _ in }

    /// Invoked when the "Clear completed" button is tapped.
    var onClearCompleted: () -> Void = { }

    @Environment(\.dismiss) private var dismiss

    // MARK: - Derived

    private var activeJobs: [ExportJob] { jobs.filter { $0.isActive } }
    private var completedJobs: [ExportJob] { jobs.filter { $0.isTerminal } }
    private var hasCompleted: Bool { !completedJobs.isEmpty }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if jobs.isEmpty {
                    emptyState
                } else {
                    queueList
                }
            }
            .navigationTitle("Export Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onClearCompleted()
                    } label: {
                        Label("Clear completed", systemImage: "trash")
                    }
                    .disabled(!hasCompleted)
                    .accessibilityHint("Removes every finished or failed export")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: LiquidSpacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(LiquidColors.textTertiary)
            Text("No exports yet")
                .font(LiquidTypography.headline)
            Text("Exports you start will appear here while they render.")
                .font(LiquidTypography.footnote)
                .foregroundStyle(LiquidColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiquidSpacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var queueList: some View {
        List {
            if !activeJobs.isEmpty {
                Section("Active") {
                    ForEach(activeJobs, id: \.id) { job in
                        ExportQueueRow(
                            job: job,
                            onCancel: { onCancel(job.id) },
                            onRemove: { onRemove(job.id) }
                        )
                    }
                }
            }
            if !completedJobs.isEmpty {
                Section("Completed") {
                    ForEach(completedJobs, id: \.id) { job in
                        ExportQueueRow(
                            job: job,
                            onCancel: { onCancel(job.id) },
                            onRemove: { onRemove(job.id) }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - ExportQueueRow

private struct ExportQueueRow: View {

    let job: ExportJob
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            HStack(spacing: LiquidSpacing.sm) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.label)
                        .font(LiquidTypography.bodySemibold)
                        .lineLimit(1)
                    Text(presetSummary)
                        .font(LiquidTypography.caption)
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if job.isRunning {
                    Button(role: .destructive, action: onCancel) {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LiquidColors.error)
                    .accessibilityLabel("Cancel \(job.label)")
                } else if job.isTerminal {
                    Button(action: onRemove) {
                        Label("Remove", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .accessibilityLabel("Remove \(job.label) from queue")
                }
            }

            if job.isRunning || job.status == .queued {
                VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
                    ProgressView(value: job.progress)
                        .tint(statusColor)
                    HStack {
                        Text(job.status.rawValue.capitalized)
                            .font(LiquidTypography.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                        Spacer()
                        Text(etaLabel)
                            .font(LiquidTypography.caption2)
                            .foregroundStyle(LiquidColors.textTertiary)
                            .monospacedDigit()
                    }
                }
            } else if job.status == .completed, !job.outputSizeString.isEmpty {
                Text("Completed · \(job.outputSizeString)")
                    .font(LiquidTypography.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
            } else if let err = job.errorMessage {
                Text(err)
                    .font(LiquidTypography.caption2)
                    .foregroundStyle(LiquidColors.error)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, LiquidSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived

    private var statusIcon: String {
        switch job.status {
        case .queued: return "hourglass"
        case .preparing, .rendering, .encoding, .saving: return "arrow.up.to.line.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        case .paused: return "pause.circle.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .queued, .preparing: return .blue
        case .rendering, .encoding, .saving: return .blue
        case .completed: return LiquidColors.success
        case .failed: return LiquidColors.error
        case .cancelled: return LiquidColors.textSecondary
        case .paused: return .orange
        }
    }

    private var presetSummary: String {
        let cfg = job.config
        let resolution = cfg.resolution == .custom
            ? "\(cfg.outputWidth)x\(cfg.outputHeight)"
            : cfg.resolution.label
        return "\(cfg.codec.displayName) · \(resolution) · \(cfg.fps)fps"
    }

    private var etaLabel: String {
        guard job.isRunning else { return "" }
        if let duration = job.exportDuration, duration > 0, job.progress > 0.01 {
            let total = duration / job.progress
            let remaining = max(total - duration, 0)
            if remaining >= 60 {
                let minutes = Int(remaining) / 60
                let seconds = Int(remaining) % 60
                return seconds > 0 ? "~\(minutes)m \(seconds)s left" : "~\(minutes)m left"
            }
            return "~\(Int(remaining))s left"
        }
        return "Calculating…"
    }
}

#Preview("Populated") {
    ExportQueueSheet(
        jobs: [
            ExportJob(
                id: "1",
                label: "Beach Trip 4K",
                config: ExportConfig(resolution: .r4K, fps: 30, codec: .h265),
                status: .rendering,
                progress: 0.42,
                createdAt: Date(),
                startedAt: Date().addingTimeInterval(-20)
            ),
            ExportJob(
                id: "2",
                label: "Tutorial Reel",
                config: ExportConfig(resolution: .r1080p),
                status: .completed,
                progress: 1.0,
                outputSizeBytes: 128 * 1024 * 1024,
                createdAt: Date().addingTimeInterval(-300),
                startedAt: Date().addingTimeInterval(-270),
                completedAt: Date().addingTimeInterval(-30)
            ),
        ]
    )
}

#Preview("Empty") {
    ExportQueueSheet(jobs: [])
}
