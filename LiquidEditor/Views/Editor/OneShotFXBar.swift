// OneShotFXBar.swift
// LiquidEditor
//
// TD8-10: ContextSubPanel-hosted horizontal row of three large
// one-shot FX actions — Mirror, Freeze, Cutout.
//
// Per docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §8.10.
//
// Each button:
//  - fires a `UISelectionFeedbackGenerator` via `HapticService.shared.trigger(.selection)`
//  - invokes the caller-supplied `onAction` callback with the chosen action.
//
// The bar wraps ContextSubPanel (title: "FX"), forwarding the ✕ tap to
// the caller via `onDismiss` — callers are expected to hide the bar
// when dismissed.

import SwiftUI

// MARK: - OneShotFXAction

/// A single-shot FX action invoked from the bar.
enum OneShotFXAction: String, CaseIterable, Identifiable, Sendable {
    case mirror
    case freeze
    case cutout

    var id: String { rawValue }

    /// SF Symbol shown on the button.
    var systemImage: String {
        switch self {
        case .mirror: return "rectangle.2.swap"
        case .freeze: return "snowflake"
        case .cutout: return "scissors"
        }
    }

    /// Human-readable label shown under the symbol.
    var label: String {
        switch self {
        case .mirror: return "Mirror"
        case .freeze: return "Freeze"
        case .cutout: return "Cutout"
        }
    }

    /// VoiceOver label.
    var accessibilityLabel: String {
        switch self {
        case .mirror: return "Mirror clip"
        case .freeze: return "Freeze frame"
        case .cutout: return "Cutout subject"
        }
    }
}

// MARK: - OneShotFXBar

/// A `ContextSubPanel`-hosted horizontal row of three large FX buttons.
///
/// Parent view controls presentation. On ✕ the parent receives
/// `onDismiss`; on tap the parent receives the chosen `OneShotFXAction`
/// via `onAction`.
@MainActor
struct OneShotFXBar: View {

    // MARK: - Inputs

    /// Invoked when the user taps a one-shot action.
    let onAction: (OneShotFXAction) -> Void

    /// Invoked when the user dismisses the sub-panel (✕ in header).
    let onDismiss: () -> Void

    // MARK: - Body

    var body: some View {
        ContextSubPanel(title: "FX", onDismiss: onDismiss) {
            HStack(spacing: LiquidSpacing.md) {
                ForEach(OneShotFXAction.allCases) { action in
                    actionButton(action)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Subviews

    private func actionButton(_ action: OneShotFXAction) -> some View {
        Button {
            HapticService.shared.trigger(.selection)
            onAction(action)
        } label: {
            VStack(spacing: LiquidSpacing.xs) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LiquidColors.Accent.amber)
                    .frame(height: 26)

                Text(action.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .padding(.vertical, LiquidSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .stroke(LiquidColors.Accent.amber.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.accessibilityLabel)
    }
}

// MARK: - Previews

#Preview("OneShotFXBar") {
    VStack {
        Spacer()
        OneShotFXBar(
            onAction: { _ in },
            onDismiss: { }
        )
        .padding(.horizontal, 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LiquidColors.Canvas.base)
    .preferredColorScheme(.dark)
}
