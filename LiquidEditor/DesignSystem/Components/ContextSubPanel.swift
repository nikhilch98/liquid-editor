// ContextSubPanel.swift
// LiquidEditor
//
// P1-1: Reusable container for tool-specific parametric panels that
// slide up between the timeline and the tool shelf when an active tool
// needs parameters.
//
// Visual per spec §2.5 / §6:
// - amber 1px border
// - downward-pointing caret (4pt) centered on top edge, pointing at the
//   active tool button in the strip above
// - 8px drop shadow
// - slide-up-from-bottom appearance (LiquidMotion.smooth)
// - dismiss: tap ✕ in header or tap the tool button again (caller handles)
//
// Consumers: Speed panel, Volume panel, Tracking (inline variant),
// Keyframes (inline), LUT category chip panel, and every other per-tool
// drill-down that shows inline parameters above the tool shelf.

import SwiftUI

// MARK: - ContextSubPanel

/// Amber-bordered sub-panel container with caret + dismiss.
///
/// Arguments:
///   - `title`: short uppercase section label (e.g., "SPEED")
///   - `onDismiss`: closure invoked when the user taps ✕
///   - `content`: the parametric controls to show
struct ContextSubPanel<Content: View>: View {

    // MARK: - Inputs

    let title: String
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var appeared = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            caret
            panelBody
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear(perform: animateIn)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) controls")
    }

    // MARK: - Subviews

    private var caret: some View {
        CaretShape()
            .fill(LiquidColors.Canvas.raised)
            .overlay(
                CaretShape().stroke(LiquidColors.Accent.amber, lineWidth: 1)
            )
            .frame(width: 10, height: 5)
            .accessibilityHidden(true)
    }

    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LiquidColors.Canvas.raised)
                .shadow(color: .black.opacity(0.35), radius: 8, y: -2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LiquidColors.Accent.amber, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(LiquidColors.Accent.amber)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.Text.tertiary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(title) panel")
        }
    }

    // MARK: - Animation

    private func animateIn() {
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(LiquidMotion.smooth) { appeared = true }
        }
    }
}

// MARK: - CaretShape

/// Small upward-pointing triangle used as the sub-panel caret.
private struct CaretShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Speed panel") {
    VStack {
        Spacer()
        ContextSubPanel(title: "Speed", onDismiss: { }) {
            HStack(spacing: 6) {
                ForEach(["0.25x", "0.5x", "1x", "2x", "Curve..."], id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(
                            label == "1x" ? LiquidColors.Accent.amber : LiquidColors.Text.secondary
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(LiquidColors.Canvas.elev)
                        )
                }
            }
        }
        .padding(.horizontal, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LiquidColors.Canvas.base)
    .preferredColorScheme(.dark)
}
