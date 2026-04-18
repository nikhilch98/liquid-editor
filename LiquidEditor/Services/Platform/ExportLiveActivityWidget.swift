// ExportLiveActivityWidget.swift
// LiquidEditor
//
// OS17-2: Live Activity widget UI for export progress per spec §10.10.1
// and §17.2.
//
// Renders:
//   - Lock-screen banner: project name + linear progress + ETA
//   - Dynamic Island compact: progress ring + percent
//   - Dynamic Island minimal: progress ring only
//   - Dynamic Island expanded: project name + bar + Cancel button
//
// NOTE: This file references `ExportLiveActivityAttributes` defined in
// `DynamicIslandPresenter.swift`. Both files must be a member of the
// widget extension target (when one is configured) as well as the main
// app target so `ActivityConfiguration(for:)` resolves the same type.
//
// The Cancel button currently no-ops; wiring it to actually cancel the
// underlying export job is deferred (see §17.2 follow-up in the spec).

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - ExportLiveActivityWidget

public struct ExportLiveActivityWidget: Widget {

    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExportLiveActivityAttributes.self) { context in
            // Lock-screen / banner presentation.
            LockScreenExportView(
                projectName: context.attributes.projectName,
                progress: context.state.progress,
                etaSeconds: context.state.etaSeconds
            )
            .padding(16)
            .background(.ultraThinMaterial)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.projectName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .foregroundStyle(.tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Self.etaLabel(context.state.etaSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    ProgressView(value: context.state.progress)
                        .progressViewStyle(.linear)
                        .tint(.orange)
                        .padding(.horizontal, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Exporting…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel", action: {})
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                    }
                }
            } compactLeading: {
                ProgressRing(progress: context.state.progress)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                Text(Self.percentLabel(context.state.progress))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange)
            } minimal: {
                ProgressRing(progress: context.state.progress)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(.orange)
        }
    }

    // MARK: - Formatting helpers

    static func percentLabel(_ progress: Double) -> String {
        let pct = Int((min(max(progress, 0), 1) * 100).rounded())
        return "\(pct)%"
    }

    static func etaLabel(_ etaSeconds: Int?) -> String {
        guard let eta = etaSeconds, eta > 0 else { return "--:--" }
        let minutes = eta / 60
        let seconds = eta % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Lock-screen view

struct LockScreenExportView: View {
    let projectName: String
    let progress: Double
    let etaSeconds: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.and.arrow.up.on.square")
                    .foregroundStyle(.orange)
                Text(projectName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(ExportLiveActivityWidget.percentLabel(progress))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.orange)

            HStack {
                Text("Exporting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("ETA \(ExportLiveActivityWidget.etaLabel(etaSeconds))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(
                    Color.orange,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}
