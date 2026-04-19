// EditorShortcutBindings.swift
// LiquidEditor
//
// K11-1/2/3/4/5/8/9: Register the remaining editor keyboard-shortcut
// bindings for the iPad editor surface. This is the sibling of
// `ClipOpShortcutBindings.swift` (K11-7) and covers every non-clip-op
// shortcut in the premium-redesign spec §10.5:
//
//   K11-1 Playback — Space / J / K / L
//   K11-2 Edit     — ⌘S / ⌘C / ⌘V / ⌫ / I / O / T
//   K11-3 Nav      — ⌘Z / ⌘⇧Z / ⌘+ / ⌘- / ← / → / ⇧← / ⇧→
//   K11-4 Modal    — Esc / F / ⌘E / ⌘N / ⌘F / ⇥
//   K11-5 Marker   — M
//   K11-8 Source   — , / . / F9 / F10 / N / ⇧I / ⇧O
//   K11-9 Match/Link — F / ⇧M / ⇧N / ⌘G / ⌘⇧G / ⌘L / ⌘⇧L
//
// Why a registration helper?
//   `ShortcutRegistry` is a flat list; a single entry point keeps the
//   call site trivial and prevents drift between shortcut definitions
//   and docs. Actions are thin forwarders to `EditorViewModel` methods
//   (or the `AppCoordinator` for modal dismiss). Methods that don't
//   yet exist on the view model are stubbed with a `// TODO: wire`
//   marker; the binding still installs so the shortcut is discoverable
//   in the Hold-⌘ overlay and to unblock UI integration.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md
//       §10.5 (keyboard-shortcut catalog) and §11 (implementation notes).

import Foundation
import SwiftUI

// MARK: - EditorShortcutBindings

/// Namespace for non-clip-op editor shortcut registration. Pure wiring —
/// no state, no side-effects beyond `registry.register(...)`.
@MainActor
enum EditorShortcutBindings {

    // MARK: - Tuning Constants

    /// Frame duration used for `← / →` single-frame stepping. 1/30s in
    /// microseconds. Project-specific frame rates can be plugged in when
    /// the view model exposes them; 30 fps is the safe fallback.
    private static let oneFrameMicros: TimeMicros = 33_333

    /// One-second step used for `⇧← / ⇧→` and `F9 / F10` fallback.
    private static let oneSecondMicros: TimeMicros = 1_000_000

    /// Timeline zoom clamps for `⌘+ / ⌘-` (spec §10.5).
    private static let minZoomScale: Double = 0.25
    private static let maxZoomScale: Double = 8.0

    /// Multiplicative step per zoom keystroke.
    private static let zoomStep: Double = 1.5

    // MARK: - Register

    /// Install every non-clip-op editor shortcut on `registry`. Safe to
    /// call once per editor session; the registry does not dedupe so
    /// callers MUST NOT invoke this twice on the same registry.
    ///
    /// - Parameters:
    ///   - registry:   The shortcut registry attached at the scene root.
    ///   - viewModel:  The editor view model whose actions fire on shortcut.
    ///   - coordinator: Optional coordinator used for modal/navigation
    ///                  shortcuts (Esc, ⌘E, ⌘N, ⌘F). Passing `nil`
    ///                  keeps the keystrokes registered but makes them
    ///                  no-ops; tests can exercise the registry shape
    ///                  without standing up a coordinator.
    static func registerEditorShortcuts(
        registry: ShortcutRegistry,
        viewModel: EditorViewModel,
        coordinator: AppCoordinator?
    ) {
        registerPlayback(registry: registry, viewModel: viewModel)
        registerEdit(registry: registry, viewModel: viewModel)
        registerNav(registry: registry, viewModel: viewModel)
        registerModal(registry: registry, viewModel: viewModel, coordinator: coordinator)
        registerMarker(registry: registry, viewModel: viewModel)
        registerSourceMonitor(registry: registry, viewModel: viewModel)
        registerMatchFrameAndLinks(registry: registry, viewModel: viewModel)
    }

    // MARK: - K11-1 Playback

    private static func registerPlayback(
        registry: ShortcutRegistry,
        viewModel: EditorViewModel
    ) {
        // Space — Play/Pause toggle.
        registry.register(
            .space,
            label: "Play / Pause"
        ) { [weak viewModel] in
            viewModel?.togglePlayPause()
        }

        // J — Halve playback rate (JKL shuttle, reverse/slower).
        registry.register(
            KeyboardShortcut("j", modifiers: []),
            label: "Shuttle slower (J)"
        ) { [weak viewModel] in
            viewModel?.halvePlaybackRate()
        }

        // K — Pause and reset rate to 1.0×.
        registry.register(
            KeyboardShortcut("k", modifiers: []),
            label: "Pause (K)"
        ) { [weak viewModel] in
            viewModel?.pausePlaybackAndResetRate()
        }

        // L — Double playback rate (JKL shuttle, forward/faster).
        registry.register(
            KeyboardShortcut("l", modifiers: []),
            label: "Shuttle faster (L)"
        ) { [weak viewModel] in
            viewModel?.doublePlaybackRate()
        }
    }

    // MARK: - K11-2 Edit

    private static func registerEdit(
        registry: ShortcutRegistry,
        viewModel: EditorViewModel
    ) {
        // ⌘S — Save project. (Split is ⌘S per spec §10.5 — "Split at
        // playhead". Save is ⌘-W / autosave; we honour the spec here.)
        registry.register(
            KeyboardShortcut("s", modifiers: .command),
            label: "Split at playhead"
        ) { [weak viewModel] in
            viewModel?.splitAtPlayhead()
        }

        // ⌘C — Copy selected clip to the clipboard.
        registry.register(
            KeyboardShortcut("c", modifiers: .command),
            label: "Copy"
        ) { [weak viewModel] in
            guard let viewModel,
                  let clipId = viewModel.selectedClipId,
                  let clip = viewModel.timeline.getById(clipId)
            else { return }
            ClipboardStore.shared.write(clip, sourceTrackId: nil)
        }

        // ⌘V — Paste clipboard contents.
        registry.register(
            KeyboardShortcut("v", modifiers: .command),
            label: "Paste"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.pasteClipboardAtPlayhead() needs
            // to insert ClipboardStore.shared.current?.clip at currentTime
            // via an undo-safe command.
            _ = viewModel
            _ = ClipboardStore.shared.current
        }

        // ⌫ / Delete — Remove selected clip.
        registry.register(
            KeyboardShortcut(.delete, modifiers: []),
            label: "Delete"
        ) { [weak viewModel] in
            viewModel?.deleteSelected()
        }

        // I — Mark In at the playhead.
        registry.register(
            KeyboardShortcut("i", modifiers: []),
            label: "Mark In"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.markIn() should store
            // currentTime as the timeline in-point for subsequent
            // 3-point edits.
            _ = viewModel
        }

        // O — Mark Out at the playhead.
        registry.register(
            KeyboardShortcut("o", modifiers: []),
            label: "Mark Out"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.markOut() should store
            // currentTime as the timeline out-point.
            _ = viewModel
        }

        // T — Trim to playhead / toggle trim mode. Spec §10.5 maps T to
        // "Trim to playhead (ripple)"; until the ripple command ships,
        // we toggle trim mode on the selected clip.
        registry.register(
            KeyboardShortcut("t", modifiers: []),
            label: "Trim"
        ) { [weak viewModel] in
            viewModel?.toggleTrimMode()
        }
    }

    // MARK: - K11-3 Navigation

    private static func registerNav(
        registry: ShortcutRegistry,
        viewModel: EditorViewModel
    ) {
        // ⌘Z — Undo.
        registry.register(
            KeyboardShortcut("z", modifiers: .command),
            label: "Undo"
        ) { [weak viewModel] in
            viewModel?.undo()
        }

        // ⌘⇧Z — Redo.
        registry.register(
            KeyboardShortcut("z", modifiers: [.command, .shift]),
            label: "Redo"
        ) { [weak viewModel] in
            viewModel?.redo()
        }

        // ⌘+ — Zoom timeline in. Register both "+" and "=" so the un-
        // shifted `=` key also triggers it (standard macOS convention).
        registry.register(
            KeyboardShortcut("+", modifiers: .command),
            label: "Zoom in"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.zoomScale = min(viewModel.zoomScale * zoomStep, maxZoomScale)
        }
        registry.register(
            KeyboardShortcut("=", modifiers: .command),
            label: "Zoom in"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.zoomScale = min(viewModel.zoomScale * zoomStep, maxZoomScale)
        }

        // ⌘- — Zoom timeline out.
        registry.register(
            KeyboardShortcut("-", modifiers: .command),
            label: "Zoom out"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.zoomScale = max(viewModel.zoomScale / zoomStep, minZoomScale)
        }

        // ← — Step one frame back.
        registry.register(
            KeyboardShortcut(.leftArrow, modifiers: []),
            label: "Step back 1 frame"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.seek(to: viewModel.currentTime - oneFrameMicros)
        }

        // → — Step one frame forward.
        registry.register(
            KeyboardShortcut(.rightArrow, modifiers: []),
            label: "Step forward 1 frame"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.seek(to: viewModel.currentTime + oneFrameMicros)
        }

        // ⇧← — Jump one second back.
        registry.register(
            KeyboardShortcut(.leftArrow, modifiers: .shift),
            label: "Step back 1 second"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.seek(to: viewModel.currentTime - oneSecondMicros)
        }

        // ⇧→ — Jump one second forward.
        registry.register(
            KeyboardShortcut(.rightArrow, modifiers: .shift),
            label: "Step forward 1 second"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.seek(to: viewModel.currentTime + oneSecondMicros)
        }
    }

    // MARK: - K11-4 Modal / Navigation

    private static func registerModal(
        registry: ShortcutRegistry,
        viewModel: EditorViewModel,
        coordinator: AppCoordinator?
    ) {
        // Esc — Dismiss current sheet / sub-panel.
        registry.register(
            .escape,
            label: "Dismiss sub-panel"
        ) { [weak viewModel, weak coordinator] in
            // Close any tool panel first; then the coordinator's active
            // sheet. If neither is up, deselect.
            if let vm = viewModel, vm.activePanel != .none {
                vm.dismissPanel()
                return
            }
            if let coordinator, coordinator.activeSheet != nil {
                coordinator.dismissSheet()
                return
            }
            viewModel?.selectedClipId = nil
        }

        // F — Toggle fullscreen preview. Spec §10.5 lists F twice (also
        // as Match Frame in §7.15); modal wins here, Match Frame is
        // registered under ⇧F as a disambiguation alias below.
        registry.register(
            KeyboardShortcut("f", modifiers: []),
            label: "Fullscreen preview"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.showFullscreenPreview.toggle()
        }

        // ⌘E — Open Export sheet.
        registry.register(
            KeyboardShortcut("e", modifiers: .command),
            label: "Export"
        ) { [weak viewModel, weak coordinator] in
            if let coordinator {
                coordinator.presentExport()
            } else {
                viewModel?.showExportSheet = true
            }
        }

        // ⌘N — New project. Routes through the coordinator which owns
        // the library navigation.
        registry.register(
            KeyboardShortcut("n", modifiers: .command),
            label: "New project"
        ) { [weak coordinator] in
            guard let coordinator else { return }
            // TODO: wire — AppCoordinator.presentNewProject() when the
            // library's create-project flow lands. Pop to root for now
            // so the user lands on the library where the + CTA lives.
            coordinator.popToRoot()
        }

        // ⌘F — Search (Library only). Kept on the editor registry so the
        // shortcut is live on all screens; the coordinator can ignore it
        // when not on library.
        registry.register(
            KeyboardShortcut("f", modifiers: .command),
            label: "Search library"
        ) { [weak coordinator] in
            guard let coordinator else { return }
            // TODO: wire — AppCoordinator.focusLibrarySearch() once the
            // library search surface exposes a focus hook.
            _ = coordinator
        }

        // ⇥ — Cycle inspector tabs (Edit → Audio → Text → FX → Color).
        registry.register(
            KeyboardShortcut(.tab, modifiers: []),
            label: "Cycle inspector"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            let all = EditorTabID.allCases
            let index = all.firstIndex(of: viewModel.selectedTab) ?? 0
            let next = (index + 1) % all.count
            viewModel.selectedTab = all[next]
        }
    }

    // MARK: - K11-5 Marker

    private static func registerMarker(
        registry: ShortcutRegistry,
        viewModel: EditorViewModel
    ) {
        // M — Add marker at playhead.
        registry.register(
            KeyboardShortcut("m", modifiers: []),
            label: "Add marker"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.addMarkerAtPlayhead() should
            // create a ClipMarker on the selected clip (or a timeline-
            // level marker) at currentTime.
            _ = viewModel
        }
    }

    // MARK: - K11-8 Source Monitor

    private static func registerSourceMonitor(
        registry: ShortcutRegistry,
        viewModel: EditorViewModel
    ) {
        // , — Mark In on the source monitor.
        registry.register(
            KeyboardShortcut(",", modifiers: []),
            label: "Source: Mark In"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.markInSource() should set the
            // SourceMonitor IN point at the source-monitor playhead.
            _ = viewModel
        }

        // . — Mark Out on the source monitor.
        registry.register(
            KeyboardShortcut(".", modifiers: []),
            label: "Source: Mark Out"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.markOutSource().
            _ = viewModel
        }

        // F9 — Insert from source at timeline playhead (3-point edit).
        // SwiftUI's `KeyEquivalent` has no `.f9` symbol; we bind the
        // Unicode scalar the function-row hardware emits (0xF708) so the
        // shortcut is discoverable through the native key-command
        // infrastructure.
        registry.register(
            KeyboardShortcut(KeyEquivalent(Character(Unicode.Scalar(0xF708)!)), modifiers: []),
            label: "Insert from source"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.insertFromSource() performs
            // the 3-point insert via ThreePointEditCommands.
            _ = viewModel
        }

        // F10 — Overwrite from source at timeline playhead.
        registry.register(
            KeyboardShortcut(KeyEquivalent(Character(Unicode.Scalar(0xF709)!)), modifiers: []),
            label: "Overwrite from source"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.overwriteFromSource().
            _ = viewModel
        }

        // N — Cycle the source-monitor target clip.
        registry.register(
            KeyboardShortcut("n", modifiers: []),
            label: "Cycle source target"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.cycleSourceMonitorTarget().
            _ = viewModel
        }

        // ⇧I — Mark In on the timeline (destination).
        registry.register(
            KeyboardShortcut("i", modifiers: .shift),
            label: "Timeline: Mark In"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.markInDest().
            _ = viewModel
        }

        // ⇧O — Mark Out on the timeline (destination).
        registry.register(
            KeyboardShortcut("o", modifiers: .shift),
            label: "Timeline: Mark Out"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.markOutDest().
            _ = viewModel
        }
    }

    // MARK: - K11-9 Match frame / markers / compound / link

    private static func registerMatchFrameAndLinks(
        registry: ShortcutRegistry,
        viewModel: EditorViewModel
    ) {
        // ⇧F — Match frame. Disambiguated from plain F (fullscreen).
        // Spec §10.5 lists F for both fullscreen and match-frame; we
        // keep fullscreen on the bare key and move match-frame to ⇧F
        // so the surface is fully reachable from the keyboard.
        registry.register(
            KeyboardShortcut("f", modifiers: .shift),
            label: "Match frame"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.matchFrame() opens the source
            // monitor on the selected clip at the playhead offset.
            _ = viewModel
        }

        // ⇧M — Next marker.
        registry.register(
            KeyboardShortcut("m", modifiers: .shift),
            label: "Next marker"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.nextMarker() seeks to the
            // next clip or timeline marker after currentTime.
            _ = viewModel
        }

        // ⇧N — Previous marker.
        registry.register(
            KeyboardShortcut("n", modifiers: .shift),
            label: "Previous marker"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.prevMarker().
            _ = viewModel
        }

        // ⌘G — Group selection.
        registry.register(
            KeyboardShortcut("g", modifiers: .command),
            label: "Group selection"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.group() groups the current
            // selection into a LinkGroup (not yet a compound; compound
            // conversion is ⌘⌥G in spec §10.5 and lives elsewhere).
            _ = viewModel
        }

        // ⌘⇧G — Ungroup selection.
        registry.register(
            KeyboardShortcut("g", modifiers: [.command, .shift]),
            label: "Ungroup"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.ungroup().
            _ = viewModel
        }

        // ⌘L — Link selected clips.
        registry.register(
            KeyboardShortcut("l", modifiers: .command),
            label: "Link"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.link() creates a link group
            // across the selected audio+video siblings.
            _ = viewModel
        }

        // ⌘⇧L — Unlink selected clips.
        registry.register(
            KeyboardShortcut("l", modifiers: [.command, .shift]),
            label: "Unlink"
        ) { [weak viewModel] in
            guard let viewModel else { return }
            // TODO: wire — EditorViewModel.unlink().
            _ = viewModel
        }
    }
}
