// CompoundClipShell.swift
// LiquidEditor
//
// E4-15: Compound Clip shell (XL).
//
// Full-screen shell for the *inside* of a `CompoundClip`. Shows the
// compound's name, a lightweight mini-timeline of its nested clips,
// and Edit / Save / Discard CTAs along the bottom.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §4.
//
// Notes:
// - Read-only over the compound's `memberIDs`; lookup of the actual
//   nested timeline items is the caller's responsibility (passed in
//   via `nestedClips`).
// - Liquid Glass surfaces: `.ultraThinMaterial`, continuous rounded
//   rects, semantic colors.
// - Edit / Save / Discard dispatch to caller-provided callbacks; this
//   view owns no state beyond the "is editing" toggle.

import SwiftUI

// MARK: - CompoundClipShell

@MainActor
struct CompoundClipShell: View {

    // MARK: - Inputs

    /// The compound being inspected.
    let compound: CompoundClip

    /// Nested clip summaries to render in the mini-timeline. Pass an
    /// empty array to show the empty-state placeholder.
    let nestedClips: [CompoundClipShellItem]

    /// Called when the user taps "Edit" and enters edit mode.
    let onEnterEdit: () -> Void

    /// Called when the user saves changes made inside the compound.
    let onSave: () -> Void

    /// Called when the user discards changes.
    let onDiscard: () -> Void

    /// Called when the user closes the shell without entering edit
    /// mode.
    let onClose: () -> Void

    // MARK: - Local state

    @State private var isEditing: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                miniTimeline
                Spacer(minLength: 0)
                footer
            }
            .background(Color.black.opacity(0.96))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Close compound")
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Compound: \(compound.name)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(compound.memberIDs.count) nested clip\(compound.memberIDs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isEditing {
                Label("Editing", systemImage: "pencil.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Mini-timeline

    @ViewBuilder
    private var miniTimeline: some View {
        if nestedClips.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(nestedClips) { clip in
                        clipTile(clip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .padding(.horizontal, 12)
            )
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func clipTile(_ clip: CompoundClipShellItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(clip.tint.opacity(0.6))
                .frame(width: max(40, CGFloat(clip.durationSeconds) * 24), height: 40)
                .overlay(alignment: .leading) {
                    Image(systemName: clip.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.leading, 6)
                }
            Text(clip.name)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No nested clips yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Add clips to the compound from the editor timeline.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Footer CTAs

    private var footer: some View {
        HStack(spacing: 10) {
            if !isEditing {
                Button {
                    isEditing = true
                    onEnterEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(role: .destructive) {
                    isEditing = false
                    onDiscard()
                } label: {
                    Label("Discard", systemImage: "arrow.uturn.backward")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    isEditing = false
                    onSave()
                } label: {
                    Label("Save", systemImage: "checkmark")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }
}

// MARK: - CompoundClipShellItem

/// Lightweight summary of a nested clip for the mini-timeline row.
/// The shell is intentionally decoupled from the full
/// `TimelineItemProtocol` so the caller can project whatever subset of
/// data is relevant.
struct CompoundClipShellItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let durationSeconds: Double
    let symbol: String
    let tint: Color

    init(
        id: String,
        name: String,
        durationSeconds: Double,
        symbol: String = "film",
        tint: Color = .blue
    ) {
        self.id = id
        self.name = name
        self.durationSeconds = durationSeconds
        self.symbol = symbol
        self.tint = tint
    }
}
