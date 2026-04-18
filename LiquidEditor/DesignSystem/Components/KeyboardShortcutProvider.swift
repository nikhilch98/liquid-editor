// KeyboardShortcutProvider.swift
// LiquidEditor
//
// P1-9: Central keyboard-shortcut registry per spec §10.5.
// P1-18: Focus-aware gating is provided for free by SwiftUI's
// `.keyboardShortcut()` modifier — shortcuts attached to hidden
// buttons do not fire when a text field is first responder.
//
// Usage:
//
//   @State private var shortcuts = ShortcutRegistry()
//   ...
//   shortcuts.register(.space) { playbackToggle() }
//   shortcuts.register(KeyboardShortcut("s", modifiers: .command)) { split() }
//   ...
//   .keyboardShortcutProvider(shortcuts)
//
// At app root, `keyboardShortcutProvider` renders one hidden Button per
// registered shortcut. SwiftUI's native keyboardShortcut modifier
// attaches to the button and dispatches to the bound action. When a
// text field owns first-responder, the system swallows the keystroke
// and the button does not fire — that's our P1-18 gating.

import SwiftUI
import Observation

// MARK: - ShortcutRegistry

/// Central registry of keyboard shortcuts. Attach via
/// `.keyboardShortcutProvider(_:)` at the app or scene root.
@Observable
@MainActor
final class ShortcutRegistry {

    struct Binding: Identifiable {
        let id = UUID()
        let shortcut: KeyboardShortcut
        let label: String
        let action: () -> Void
    }

    private(set) var bindings: [Binding] = []

    func register(
        _ shortcut: KeyboardShortcut,
        label: String = "",
        action: @escaping () -> Void
    ) {
        bindings.append(Binding(shortcut: shortcut, label: label, action: action))
    }

    func unregisterAll() { bindings.removeAll() }
}

// MARK: - Built-ins

extension KeyboardShortcut {
    /// Spacebar — play/pause.
    static let space = KeyboardShortcut(.space, modifiers: [])
    /// Escape — dismiss sub-panel / deselect / exit group.
    static let escape = KeyboardShortcut(.escape, modifiers: [])
}

// MARK: - KeyboardShortcutProviderView

private struct KeyboardShortcutProviderView: View {
    let registry: ShortcutRegistry

    var body: some View {
        ZStack {
            ForEach(registry.bindings, id: \.id) { binding in
                Button(action: binding.action) {
                    Text(binding.label).opacity(0)
                }
                .keyboardShortcut(binding.shortcut)
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - View extension

extension View {
    /// Install a keyboard-shortcut registry at this level. Call ONCE at
    /// the app or scene root; downstream code calls `registry.register(...)`
    /// to add bindings.
    func keyboardShortcutProvider(_ registry: ShortcutRegistry) -> some View {
        background(KeyboardShortcutProviderView(registry: registry))
    }
}
