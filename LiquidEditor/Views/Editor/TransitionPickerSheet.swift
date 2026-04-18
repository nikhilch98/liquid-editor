// TransitionPickerSheet.swift
// LiquidEditor
//
// C5-3: Sheet for picking a transition between two adjacent clips
// per spec §8.2.
//
// Layout:
// - top: two-clip stage with live transition overlay + active-transition badge
// - duration slider (seconds + frames readout)
// - 5 category chips (Popular / Cut-Fade / Motion / 3D / Morph)
// - 4×2 thumbnail grid; tapping a thumb sets `selection`
// - bottom: Apply-to-all-cuts toggle

import SwiftUI

// MARK: - TransitionKind

enum TransitionKind: String, CaseIterable, Identifiable, Sendable {
    case fade, dissolve, zoom, slideLeft, slideRight, flip, spin, glitch
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fade: return "Fade"
        case .dissolve: return "Dissolve"
        case .zoom: return "Zoom"
        case .slideLeft: return "Slide ←"
        case .slideRight: return "Slide →"
        case .flip: return "Flip"
        case .spin: return "Spin"
        case .glitch: return "Glitch"
        }
    }
    var symbol: String {
        switch self {
        case .fade: return "circle.lefthalf.filled"
        case .dissolve: return "sparkles"
        case .zoom: return "plus.magnifyingglass"
        case .slideLeft: return "arrow.left"
        case .slideRight: return "arrow.right"
        case .flip: return "rectangle.portrait.rotate"
        case .spin: return "arrow.triangle.2.circlepath"
        case .glitch: return "waveform.path.ecg"
        }
    }
    var category: String {
        switch self {
        case .fade, .dissolve: return "Cut-Fade"
        case .zoom, .slideLeft, .slideRight: return "Motion"
        case .flip, .spin: return "3D"
        case .glitch: return "Morph"
        }
    }
}

// MARK: - TransitionPickerSheet

struct TransitionPickerSheet: View {
    @Binding var selection: TransitionKind
    @Binding var durationSeconds: Double
    @Binding var applyToAll: Bool
    let frameRate: Int
    let onClose: () -> Void

    @State private var category: String = "Popular"
    private let categories = ["Popular", "Cut-Fade", "Motion", "3D", "Morph"]

    var body: some View {
        VStack(spacing: 12) {
            stage
            durationRow
            categoryChips
            grid
            HStack {
                Toggle("Apply to all cuts", isOn: $applyToAll)
                    .font(.caption)
                    .tint(LiquidColors.Accent.amber)
                Spacer()
                Button("Done", action: onClose)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LiquidColors.Accent.amber)
            }
        }
        .padding(16)
        .background(LiquidColors.Canvas.base.ignoresSafeArea())
    }

    // MARK: - Subviews

    private var stage: some View {
        ZStack {
            HStack(spacing: 0) {
                LinearGradient(colors: [Color(red: 0.22, green: 0.27, blue: 0.33), Color(red: 0.10, green: 0.12, blue: 0.15)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(colors: [Color(red: 0.23, green: 0.16, blue: 0.16), Color(red: 0.10, green: 0.05, blue: 0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            LinearGradient(colors: [.clear, LiquidColors.Accent.amberGlow, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 80, height: 100)
            HStack(spacing: 4) {
                Image(systemName: selection.symbol).font(.caption.weight(.semibold))
                Text(selection.label).font(.caption.weight(.bold))
            }
            .foregroundStyle(LiquidColors.Accent.amber)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(LiquidColors.Accent.amberGlow))
        }
    }

    private var durationRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Duration").font(.caption).foregroundStyle(LiquidColors.Text.tertiary)
                Spacer()
                Text(durationLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(LiquidColors.Text.primary)
            }
            Slider(value: $durationSeconds, in: 0.05...3.0).tint(LiquidColors.Accent.amber)
        }
    }

    private var durationLabel: String {
        let frames = Int(durationSeconds * Double(frameRate))
        return String(format: "%.2f s · %d fr", durationSeconds, frames)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(categories, id: \.self) { c in
                    Button { category = c } label: {
                        Text(c).font(.caption2.weight(.semibold))
                            .foregroundStyle(category == c ? LiquidColors.Accent.amber : LiquidColors.Text.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(category == c ? LiquidColors.Accent.amberGlow : LiquidColors.Canvas.elev))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var visibleKinds: [TransitionKind] {
        if category == "Popular" { return TransitionKind.allCases }
        return TransitionKind.allCases.filter { $0.category == category }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(visibleKinds) { kind in
                Button { selection = kind } label: {
                    VStack(spacing: 3) {
                        Image(systemName: kind.symbol)
                            .font(.body)
                            .foregroundStyle(selection == kind ? LiquidColors.Accent.amber : LiquidColors.Text.secondary)
                        Text(kind.label)
                            .font(.caption2)
                            .foregroundStyle(selection == kind ? LiquidColors.Accent.amber : LiquidColors.Text.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(selection == kind ? LiquidColors.Accent.amberGlow : LiquidColors.Canvas.elev)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.label)
            }
        }
    }
}
