// LinkGroupIndicator.swift
// LiquidEditor
//
// E4-16: Link/Unlink indicator + gesture.
//
// A small chain-icon indicator shown in the top-right corner of a
// timeline clip when the clip participates in a `LinkGroup`. The
// indicator displays a short hash of the link group ID and exposes a
// long-press menu offering:
//
//   - Unlink     — remove this clip from the link group.
//   - Link to others — prompt the caller to add more clips.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §4.
//
// Notes:
// - Pure SwiftUI + Liquid Glass surface.
// - Callers own the link-group mutation logic; this component only
//   surfaces the gesture + menu.

import SwiftUI

// MARK: - LinkGroupIndicator

@MainActor
struct LinkGroupIndicator: View {

    // MARK: - Inputs

    /// The link group the clip belongs to.
    let group: LinkGroup

    /// The clip the indicator is anchored to (used so the "Unlink"
    /// action knows which member to remove).
    let clipID: String

    /// Invoked when the user taps "Unlink".
    let onUnlink: (_ clipID: String, _ group: LinkGroup) -> Void

    /// Invoked when the user taps "Link to others".
    let onLinkToOthers: (_ group: LinkGroup) -> Void

    // MARK: - Body

    var body: some View {
        Menu {
            Button(role: .destructive) {
                onUnlink(clipID, group)
            } label: {
                Label("Unlink", systemImage: "link.badge.minus")
            }

            Button {
                onLinkToOthers(group)
            } label: {
                Label("Link to others", systemImage: "link.badge.plus")
            }

            Section {
                Label(kindLabel, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        } label: {
            indicatorLabel
        }
        .menuStyle(.button)
        .accessibilityLabel("Linked clip — group \(shortHash)")
        .accessibilityHint("Double-tap for link actions")
    }

    // MARK: - Pieces

    private var indicatorLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "link")
                .font(.system(size: 9, weight: .bold))
            Text(shortHash)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(tint.opacity(0.85))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        )
    }

    // MARK: - Derived display bits

    /// First 6 chars of the group ID with hyphens stripped for a stable
    /// short identifier shown on the chip.
    var shortHash: String {
        let cleaned = group.id.replacingOccurrences(of: "-", with: "")
        return String(cleaned.prefix(6))
    }

    private var kindLabel: String {
        switch group.kind {
        case .sync: return "Sync-linked (auto)"
        case .manual: return "Manually linked"
        }
    }

    private var tint: Color {
        switch group.kind {
        case .sync: return .cyan
        case .manual: return .purple
        }
    }
}
