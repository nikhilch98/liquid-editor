// TrackHeaderView.swift
// LiquidEditor
//
// T7-10 + T7-11 (Premium UI §10.3): Extracted track-header pill that
// lives in the left sidebar of `TimelineView`.
//
// Shows:
// - Track name (truncated to one line).
// - Mute toggle (speaker.slash/speaker.2) — binds to `Track.isMuted`.
// - Lock toggle (lock/lock.open)          — binds to `Track.isLocked`.
//
// On long-press the header presents a `GlassContextMenu` with Rename /
// Mute all / Lock / Delete-track actions. Callers pass closures for each
// action; the viewmodel layer is responsible for the actual mutation.
//
// History: the same inline markup previously lived in
// TimelineView.swift (trackHeaderItem). This file extracts it so
// TimelineView stays under 800 lines and so the long-press menu (T7-11)
// has a clean attachment point.
//
// Pure SwiftUI, iOS 26 native styling.

import SwiftUI
import UIKit

// MARK: - TrackHeaderView

/// Sidebar header item for a single `Track`.
struct TrackHeaderView: View {

    // MARK: - Inputs

    let track: Track

    /// Mute toggle. The caller mutates the track-store; this view is pure.
    let onToggleMute: () -> Void

    /// Lock toggle.
    let onToggleLock: () -> Void

    /// Rename action — caller presents a rename sheet.
    let onRename: () -> Void

    /// Mute-all action — caller iterates every track and toggles mute.
    let onMuteAll: () -> Void

    /// Delete-track action — caller prompts for confirmation.
    let onDelete: () -> Void

    // MARK: - Constants

    private static let nameFontSize: CGFloat = 10
    private static let nameOpacity: Double = 0.8
    private static let iconFontSize: CGFloat = 14
    private static let iconOpacity: Double = 0.5
    private static let buttonMinSize: CGFloat = 24
    private static let horizontalPadding: CGFloat = 4
    private static let verticalPadding: CGFloat = 2
    private static let controlSpacing: CGFloat = 6

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
            // Track name.
            Text(track.name)
                .font(.system(size: Self.nameFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(Self.nameOpacity))
                .lineLimit(1)

            // Mute + Lock controls.
            HStack(spacing: Self.controlSpacing) {
                muteButton
                lockButton
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .glassContextMenu(sections: menuSections)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Track \(track.name)")
    }

    // MARK: - Mute Button

    private var muteButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onToggleMute()
        } label: {
            Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.2.fill")
                .font(.system(size: Self.iconFontSize))
                .foregroundStyle(
                    track.isMuted ? Color.red : .white.opacity(Self.iconOpacity)
                )
        }
        .buttonStyle(.plain)
        .frame(minWidth: Self.buttonMinSize, minHeight: Self.buttonMinSize)
        .accessibilityLabel(track.isMuted ? "Unmute track \(track.name)" : "Mute track \(track.name)")
    }

    // MARK: - Lock Button

    private var lockButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onToggleLock()
        } label: {
            Image(systemName: track.isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: Self.iconFontSize))
                .foregroundStyle(
                    track.isLocked ? Color.orange : .white.opacity(Self.iconOpacity)
                )
        }
        .buttonStyle(.plain)
        .frame(minWidth: Self.buttonMinSize, minHeight: Self.buttonMinSize)
        .accessibilityLabel(track.isLocked ? "Unlock track \(track.name)" : "Lock track \(track.name)")
    }

    // MARK: - Context Menu Sections (T7-11)

    /// Long-press context-menu sections per spec §10.3.
    /// Order: Rename (primary) -> Mute all / Lock (secondary) -> Delete (destructive).
    private var menuSections: [ContextMenuSection] {
        [
            ContextMenuSection([
                ContextMenuItem("Rename", systemImage: "pencil") {
                    onRename()
                }
            ]),
            ContextMenuSection([
                ContextMenuItem(
                    "Mute all",
                    systemImage: "speaker.slash"
                ) { onMuteAll() },
                ContextMenuItem(
                    track.isLocked ? "Unlock" : "Lock",
                    systemImage: track.isLocked ? "lock.open" : "lock"
                ) { onToggleLock() }
            ]),
            ContextMenuSection([
                ContextMenuItem(
                    "Delete track",
                    systemImage: "trash",
                    role: .destructive
                ) { onDelete() }
            ])
        ]
    }
}
