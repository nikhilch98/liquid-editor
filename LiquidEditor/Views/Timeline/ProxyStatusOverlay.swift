// ProxyStatusOverlay.swift
// LiquidEditor
//
// PP12-12: Clip-tile overlay that surfaces proxy state.
//
// Renders two elements:
// 1. A small "PXY" chip in the top-right when a proxy is ready.
// 2. A thin progress bar pinned to the bottom edge while a proxy is
//    actively being generated.
//
// The overlay is a thin, zero-state SwiftUI view — all state lives in the
// caller's `ProxyStatus` binding. Consumers compose it on top of a clip
// cell via `.overlay { ProxyStatusOverlay(status: $clip.proxyStatus) }`.

import SwiftUI

// MARK: - ProxyStatus

/// State machine describing the proxy status of a single clip.
///
/// - `none`: No proxy exists and none is queued.
/// - `generating(progress:)`: A proxy transcode is in flight — `progress`
///   is the normalised `[0, 1]` progress value from the export session.
/// - `ready`: A proxy file exists on disk and is registered.
enum ProxyStatus: Sendable, Equatable {
    case none
    case generating(progress: Double)
    case ready
}

// MARK: - ProxyStatusOverlay

/// SwiftUI overlay showing proxy state for a single clip tile.
///
/// ### Visuals
/// - **PXY chip**: top-right, Liquid Glass amber accent, appears when
///   `status == .ready`.
/// - **Progress bar**: bottom edge, amber fill, appears when
///   `status == .generating`.
///
/// ### Tokens
/// Uses `LiquidColors.Accent.amber`, `LiquidColors.Text.onAccent`, and
/// `LiquidSpacing` — NO hard-coded values.
///
/// ### Accessibility
/// The chip is announced as "Proxy ready". The progress bar exposes its
/// progress via `.accessibilityValue`.
@MainActor
struct ProxyStatusOverlay: View {

    // MARK: - Input

    /// Binding to the clip's proxy status. Declared `@Binding` so the
    /// caller's @Observable clip model can drive animation updates as
    /// progress changes.
    @Binding var status: ProxyStatus

    // MARK: - Init

    /// Convenience initializer for static consumption (non-mutating state).
    /// Bridges a plain `ProxyStatus` into a read-only binding.
    init(status: Binding<ProxyStatus>) {
        self._status = status
    }

    /// Static initializer — when the caller just wants to display state and
    /// has no reason to mutate it, pass the value directly.
    init(_ status: ProxyStatus) {
        self._status = .constant(status)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            chip
            progressBar
        }
        .allowsHitTesting(false) // Overlay is purely informational.
    }

    // MARK: - Sub-views

    /// Top-right "PXY" chip rendered on `.ready`.
    @ViewBuilder
    private var chip: some View {
        if case .ready = status {
            VStack {
                HStack {
                    Spacer()
                    Text("PXY")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidColors.Text.onAccent)
                        .padding(.horizontal, LiquidSpacing.xs)
                        .padding(.vertical, LiquidSpacing.xxs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(LiquidColors.Accent.amber)
                        )
                        .padding(LiquidSpacing.xs)
                        .accessibilityLabel(Text("Proxy ready"))
                }
                Spacer()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    /// Bottom-edge progress bar rendered on `.generating`.
    @ViewBuilder
    private var progressBar: some View {
        if case let .generating(progress) = status {
            VStack {
                Spacer()
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(LiquidColors.Accent.amber.opacity(0.25))
                        Rectangle()
                            .fill(LiquidColors.Accent.amber)
                            .frame(
                                width: proxy.size.width * CGFloat(max(0, min(progress, 1)))
                            )
                            .animation(.easeOut(duration: 0.2), value: progress)
                    }
                }
                .frame(height: 2)
                .clipShape(Capsule(style: .continuous))
                .padding(.horizontal, LiquidSpacing.xxs)
                .padding(.bottom, LiquidSpacing.xxs)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Generating proxy"))
                .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ProxyStatusOverlay — states") {
    VStack(spacing: LiquidSpacing.lg) {
        clipTile(status: .none, label: "none")
        clipTile(status: .generating(progress: 0.35), label: "generating 35%")
        clipTile(status: .generating(progress: 0.85), label: "generating 85%")
        clipTile(status: .ready, label: "ready")
    }
    .padding()
    .background(LiquidColors.Canvas.base)
}

@MainActor
private func clipTile(status: ProxyStatus, label: String) -> some View {
    RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
        .fill(LiquidColors.Canvas.elev)
        .frame(width: 180, height: 60)
        .overlay(
            Text(label)
                .font(.caption2)
                .foregroundStyle(LiquidColors.Text.secondary)
        )
        .overlay(ProxyStatusOverlay(status))
}
#endif
