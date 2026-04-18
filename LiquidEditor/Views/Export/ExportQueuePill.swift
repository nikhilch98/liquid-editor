// ExportQueuePill.swift
// LiquidEditor
//
// Compact "pill" badge shown in the top-right of the editor chrome that
// surfaces the number of active exports. Tapping it opens `ExportQueueSheet`.
//
// Implementation note:
//   The pill accepts its counts as plain `Int`s and a tap handler closure so
//   it can be driven equally by a preview fixture or the real `ExportQueue`
//   actor (which must be awaited). Observing ExportQueue directly would
//   require a @MainActor bridge; out of scope for S2-11.

import SwiftUI
import UIKit

// MARK: - ExportQueuePill

struct ExportQueuePill: View {

    // MARK: - Inputs

    /// Number of currently running + queued exports.
    let activeCount: Int

    /// Whether at least one export completed (affects pill tint).
    let hasCompleted: Bool

    /// Invoked on tap to present the queue sheet.
    let onTap: () -> Void

    // MARK: - Animation State

    @State private var pulse = false
    @State private var lastCount: Int = 0

    // MARK: - Constants

    private static let pillHeight: CGFloat = 32
    private static let horizontalPadding: CGFloat = LiquidSpacing.md
    private static let dotSize: CGFloat = 6

    // MARK: - Body

    var body: some View {
        Button(action: {
            let gen = UISelectionFeedbackGenerator()
            gen.selectionChanged()
            onTap()
        }) {
            pillContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the export queue")
        .accessibilityAddTraits(.isButton)
        .onChange(of: activeCount) { _, newValue in
            defer { lastCount = newValue }
            guard newValue != lastCount else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                pulse = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.easeOut(duration: 0.2)) {
                    pulse = false
                }
            }
        }
        .opacity(activeCount > 0 || hasCompleted ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: activeCount)
    }

    private var pillContent: some View {
        HStack(spacing: LiquidSpacing.xs) {
            Circle()
                .fill(indicatorColor)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .overlay(
                    Circle()
                        .stroke(indicatorColor.opacity(0.4), lineWidth: pulse ? 6 : 0)
                        .scaleEffect(pulse ? 2.2 : 1)
                        .opacity(pulse ? 0 : 1)
                )

            Image(systemName: activeCount > 0 ? "square.and.arrow.up.on.square.fill"
                                              : "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(indicatorColor)

            Text(pillLabel)
                .font(LiquidTypography.caption2Semibold)
                .foregroundStyle(LiquidColors.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(height: Self.pillHeight)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(LiquidColors.glassBorder, lineWidth: 0.5)
        )
        .scaleEffect(pulse ? 1.06 : 1.0)
    }

    // MARK: - Derived

    private var pillLabel: String {
        if activeCount > 0 {
            return activeCount == 1 ? "1 exporting" : "\(activeCount) exporting"
        }
        return "Exports"
    }

    private var indicatorColor: Color {
        if activeCount > 0 { return .blue }
        return hasCompleted ? .green : LiquidColors.textSecondary
    }

    private var accessibilityLabel: Text {
        if activeCount > 0 {
            return Text("Export queue, \(activeCount) active")
        }
        return Text("Export queue")
    }
}

#Preview("No active") {
    ExportQueuePill(activeCount: 0, hasCompleted: true, onTap: {})
        .padding()
}

#Preview("Two active") {
    ExportQueuePill(activeCount: 2, hasCompleted: false, onTap: {})
        .padding()
}
