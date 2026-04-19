// ClipOpShortcutBindings.swift
// LiquidEditor
//
// K11-7: Register the keyboard-shortcut bindings that drive the primary
// clip-ops surface (select-all, cut, group, nudge, lock, clear, inspector).
// Called once during editor setup after the shortcut registry is attached
// at the scene root.
//
// Why a registration helper?
// - `ShortcutRegistry` is a flat list of bindings. A single function that
//   wires all clip-op shortcuts keeps the call site trivial and prevents
//   drift between the shortcut definitions and the docs.
// - The bound actions target `EditorViewModel` stubs. Where the method
//   doesn't exist yet we call a no-op placeholder and leave a `TODO`
//   for later wiring.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §10.5
//       (keyboard-shortcut catalog — clip operations).

import Foundation
import SwiftUI

// MARK: - ClipOpShortcutBindings

/// Namespace for clip-op shortcut registration. Pure wiring — no state.
@MainActor
enum ClipOpShortcutBindings {

    // MARK: - Register

    /// Install every clip-op shortcut on `registry`. Safe to call once
    /// per editor session; the registry does not dedupe so callers MUST
    /// NOT invoke this twice on the same registry.
    ///
    /// - Parameters:
    ///   - registry: The shortcut registry attached at the scene root.
    ///   - viewModel: The editor view model whose actions fire on shortcut.
    static func registerClipOpShortcuts(
        registry: ShortcutRegistry,
        viewModel: EditorViewModel
    ) {
        // ⌘A — Select all clips.
        registry.register(
            KeyboardShortcut("a", modifiers: .command),
            label: "Select all"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel has no selectAllClips() yet.
            _ = viewModel
        }

        // ⌘X — Cut selected clip via TimelineCutCommand.
        registry.register(
            KeyboardShortcut("x", modifiers: .command),
            label: "Cut selection"
        ) { [weak viewModel] in
            guard let viewModel, let clipId = viewModel.selectedClipId else {
                return
            }
            // TODO: wire — plumb ripple controller + setTimeline() here.
            // For now, capture the clip on the clipboard so paste can
            // still round-trip even without the delete step.
            if let clip = viewModel.timeline.getById(clipId) {
                ClipboardStore.shared.write(clip, sourceTrackId: nil)
            }
        }

        // ⌘G — Group selection into a compound clip.
        registry.register(
            KeyboardShortcut("g", modifiers: .command),
            label: "Group into compound"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.groupSelectionIntoCompound().
            _ = viewModel
        }

        // ⌥← — Nudge selected clip left by one frame.
        registry.register(
            KeyboardShortcut(.leftArrow, modifiers: .option),
            label: "Nudge left 1 frame"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.nudgeSelection(frames:-1).
            _ = viewModel
        }

        // ⌥→ — Nudge selected clip right by one frame.
        registry.register(
            KeyboardShortcut(.rightArrow, modifiers: .option),
            label: "Nudge right 1 frame"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.nudgeSelection(frames:+1).
            _ = viewModel
        }

        // ⌘\ — Toggle lock on selected clip/track.
        registry.register(
            KeyboardShortcut("\\", modifiers: .command),
            label: "Toggle lock"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.toggleLockOnSelection().
            _ = viewModel
        }

        // ⌘⇧0 — Clear all selection.
        registry.register(
            KeyboardShortcut("0", modifiers: [.command, .shift]),
            label: "Clear selection"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // Clearing is safe & already modeled on the view model.
            viewModel.selectedClipId = nil
        }

        // ⌘I — Toggle inspector visibility.
        registry.register(
            KeyboardShortcut("i", modifiers: .command),
            label: "Toggle inspector"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.toggleInspectorVisibility().
            _ = viewModel
        }
    }
}
