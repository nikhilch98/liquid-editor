// ScribbleSupport.swift
// LiquidEditor
//
// Apple Pencil Scribble support for text input (A10-13).
//
// NOTE ON PLATFORM BEHAVIOUR
// --------------------------
// iOS 14+ enables PencilKit "Scribble-to-text" **by default** on any
// first-party text control (`TextField`, `TextEditor`, `SearchBar`).
// The user writes on the field with an Apple Pencil, iPadOS converts
// the ink to characters, and the text is inserted at the cursor.
//
// In other words: a plain SwiftUI `TextField` already supports
// Scribble without any explicit configuration. This modifier therefore
// serves two concrete purposes:
//
//   1. A semantic opt-in/out flag (`isEnabled`) that callers can flip
//      in settings (e.g. a "Disable Scribble" toggle in Accessibility)
//      so that the text field ignores PencilKit writing input.
//   2. Documentation: a single, discoverable entry point in the code
//      base that asserts "yes, this field expects Scribble to work".
//
// If Apple later exposes a SwiftUI-native `.scribbleInteraction` API
// that allows fine-grained control, migrate the UIKit shim in this
// file to that API without changing the call sites.

import SwiftUI
import UIKit

// MARK: - ScribbleSupport

/// Semantic modifier that documents whether Scribble writing input is
/// accepted by the wrapped view's text fields.
///
/// Applies `.allowsHitTesting(false)` to a transparent overlay when
/// disabled, which blocks the default `UIScribbleInteraction` that
/// UIKit installs on the underlying `UITextField`.
struct ScribbleSupport: ViewModifier {

    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            // When disabled, overlay a transparent hit-testable layer
            // that swallows Pencil strokes so UIKit never sees them
            // and cannot launch its default Scribble interaction.
            .overlay {
                if !isEnabled {
                    ScribbleBlocker()
                        .accessibilityHidden(true)
                }
            }
    }
}

// MARK: - ScribbleBlocker (UIKit shim)

/// A transparent `UIView` whose sole job is to absorb Apple Pencil
/// strokes when `.scribbleEnabled(false)` is applied. It still lets
/// finger touches pass through so the user can tap the field, but
/// intercepts `.pencil` hits which is what `UIScribbleInteraction`
/// targets.
///
/// Wrapped in `UIViewRepresentable` because SwiftUI has no first-party
/// way (as of iOS 26) to declaratively suppress Scribble on a
/// `TextField`.
private struct ScribbleBlocker: UIViewRepresentable {
    func makeUIView(context: Context) -> PencilSwallowingView {
        let view = PencilSwallowingView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        return view
    }

    func updateUIView(_ uiView: PencilSwallowingView, context: Context) {}
}

/// UIKit leaf view: returns itself only for `.pencil` touches so that
/// finger input still reaches the SwiftUI text field underneath.
private final class PencilSwallowingView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let event = event else { return nil }
        // Only intercept when the active touch set contains a pencil.
        let hasPencil = event.allTouches?.contains { $0.type == .pencil } ?? false
        if hasPencil { return self }
        return nil
    }
}

// MARK: - View extension

extension View {

    /// Enable or disable Apple Pencil Scribble handwriting conversion
    /// on any text fields contained in this view.
    ///
    /// Defaults to `true`. Pass `false` from an accessibility/settings
    /// toggle to block Scribble strokes from reaching the field.
    ///
    /// Usage:
    /// ```swift
    /// TextField("Name", text: $name)
    ///     .scribbleEnabled(settings.allowScribble)
    /// ```
    func scribbleEnabled(_ enabled: Bool = true) -> some View {
        modifier(ScribbleSupport(isEnabled: enabled))
    }
}
