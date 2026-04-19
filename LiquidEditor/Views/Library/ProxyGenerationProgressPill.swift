// ProxyGenerationProgressPill.swift
// LiquidEditor
//
// F6-20: Compact pill that summarises live proxy-generation activity in the
// media library. Shows "Generating proxies: N of M" alongside a circular
// progress ring, and can be tapped to expose a queue-detail sheet.
//
// Pure iOS 26 SwiftUI with Liquid Glass styling. All state is passed in
// through a `Sendable` stub (`ProxyGenerationStatus`) so this view stays
// completely decoupled from the concrete `ProxyGenerator` actor.

import SwiftUI

// MARK: - ProxyGenerationStatus

/// Lightweight, `Sendable` snapshot of the proxy-generation queue.
///
/// Views observe this as an opaque value — the live counts come from a
/// higher-level coordinator (e.g. the observer on `ProxyService`).
struct ProxyGenerationStatus: Sendable, Equatable {
    /// Files still waiting to finish transcoding (queued + in-flight).
    let remaining: Int

    /// Total files submitted to the current generation batch.
    let total: Int

    /// Currently transcoding file's display name, if any.
    let currentFileName: String?

    /// Convenience empty/idle status.
    static let idle = ProxyGenerationStatus(
        remaining: 0,
        total: 0,
        currentFileName: nil
    )

    /// Count of files already completed in this batch.
    var completed: Int { max(0, total - remaining) }

    /// Normalised 0…1 progress; `0` when the queue is empty or not yet started.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completed) / Double(total)))
    }

    /// Whether the pill should appear at all.
    var isActive: Bool { remaining > 0 && total > 0 }
}

// MARK: - ProxyGenerationProgressPill

/// Compact Liquid-Glass pill that surfaces live proxy-generation progress.
///
/// Layout:
///   [ring]  Generating proxies: N of M  [chevron]
///
/// Tapping the pill invokes the provided `onTap` callback (typically used
/// to present a queue-detail sheet).
@MainActor
struct ProxyGenerationProgressPill: View {

    // MARK: - Inputs

    /// Current status snapshot.
    let status: ProxyGenerationStatus

    /// Invoked when the user taps the pill.
    let onTap: () -> Void

    // MARK: - Local Animation State

    /// Drives the subtle "pulse" animation each time `completed` changes.
    @State private var pulseScale: CGFloat = 1.0

    // MARK: - Body

    var body: some View {
        if status.isActive {
            pill
                .onChange(of: status.completed) { _, _ in
                    triggerPulse()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: - Subviews

    private var pill: some View {
        Button(action: onTap) {
            HStack(spacing: LiquidSpacing.sm) {
                progressRing
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLabel)
                        .font(LiquidTypography.footnoteSemibold)
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(1)
                    if let current = status.currentFileName, !current.isEmpty {
                        Text(current)
                            .font(LiquidTypography.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .padding(.horizontal, LiquidSpacing.md)
            .padding(.vertical, LiquidSpacing.sm)
            .background(.ultraThinMaterial)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: LiquidRadius.xl,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: LiquidRadius.xl,
                    style: .continuous
                )
                .strokeBorder(LiquidColors.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .scaleEffect(pulseScale)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: pulseScale)
        }
        .buttonStyle(.plain)
        .frame(minHeight: LiquidSpacing.minTouchTarget)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(LiquidColors.fillTertiary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(status.progress))
                .stroke(
                    LiquidColors.Accent.amber,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.24), value: status.progress)
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Derived Text

    private var primaryLabel: String {
        "Generating proxies: \(status.completed) of \(status.total)"
    }

    private var accessibilityLabel: String {
        if let current = status.currentFileName, !current.isEmpty {
            return "\(primaryLabel). Current file: \(current). Double tap for details."
        }
        return "\(primaryLabel). Double tap for details."
    }

    // MARK: - Pulse Animation

    /// Briefly scales the pill up and back down to draw attention to the
    /// count change, giving the user a visual confirmation that progress
    /// advanced without being jarring.
    private func triggerPulse() {
        pulseScale = 1.05
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            pulseScale = 1.0
        }
    }
}

// MARK: - Preview

#Preview("Active progress") {
    ProxyGenerationProgressPill(
        status: ProxyGenerationStatus(
            remaining: 3,
            total: 8,
            currentFileName: "IMG_8421.MOV"
        ),
        onTap: {}
    )
    .padding()
    .background(LiquidColors.Canvas.base)
}

#Preview("Idle (hidden)") {
    ProxyGenerationProgressPill(
        status: .idle,
        onTap: {}
    )
    .padding()
    .background(LiquidColors.Canvas.base)
}
