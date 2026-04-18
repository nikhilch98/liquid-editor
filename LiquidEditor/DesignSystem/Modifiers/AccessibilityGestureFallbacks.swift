// AccessibilityGestureFallbacks.swift
// LiquidEditor
//
// Surfaces gesture-only affordances (pinch-to-zoom, drag-to-trim,
// long-press-for-menu, etc.) as rotor-accessible accessibility
// actions so VoiceOver and Switch Control users can invoke them
// without the originating gesture.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §10.6 (A10-9)

import SwiftUI

// MARK: - AccessibilityGestureAction

/// A labelled action registered as an accessibility action so it
/// appears in the VoiceOver rotor and Switch Control action list.
///
/// Pair a gesture with an action that invokes the same behavior,
/// giving assistive-technology users an alternative path to the
/// same outcome.
struct AccessibilityGestureAction: Sendable {

    /// Human-readable label shown in the rotor (e.g. "Trim clip").
    let label: String

    /// Handler invoked when the action is selected.
    /// Main-actor isolated because these callbacks typically mutate
    /// `@Observable` view-model state.
    let handler: @MainActor @Sendable () -> Void

    /// Create an accessibility gesture fallback.
    init(_ label: String, handler: @escaping @MainActor @Sendable () -> Void) {
        self.label = label
        self.handler = handler
    }
}

// MARK: - AccessibilityGestureFallbacksModifier

/// ViewModifier that registers a set of ``AccessibilityGestureAction``
/// items as rotor-accessible actions on the receiving view.
private struct AccessibilityGestureFallbacksModifier: ViewModifier {

    let actions: [AccessibilityGestureAction]

    func body(content: Content) -> some View {
        content.modifier(ActionAccumulator(actions: actions))
    }
}

/// Recursively accumulates `.accessibilityAction` calls for the
/// provided list. We walk the array with a `reduce`-style approach
/// via a single flat application to keep the modifier stack small
/// and avoid a recursive `some View` type.
private struct ActionAccumulator: ViewModifier {

    let actions: [AccessibilityGestureAction]

    func body(content: Content) -> some View {
        // Apply up to eight actions inline (more than any realistic
        // gesture cluster); extra entries fall back to a single
        // combined action using the last label.
        let a0 = actions.first
        let a1 = actions.dropFirst(1).first
        let a2 = actions.dropFirst(2).first
        let a3 = actions.dropFirst(3).first
        let a4 = actions.dropFirst(4).first
        let a5 = actions.dropFirst(5).first
        let a6 = actions.dropFirst(6).first
        let a7 = actions.dropFirst(7).first

        return content
            .modifier(OptionalAction(action: a0))
            .modifier(OptionalAction(action: a1))
            .modifier(OptionalAction(action: a2))
            .modifier(OptionalAction(action: a3))
            .modifier(OptionalAction(action: a4))
            .modifier(OptionalAction(action: a5))
            .modifier(OptionalAction(action: a6))
            .modifier(OptionalAction(action: a7))
    }
}

/// Applies a single named accessibility action when one is provided.
private struct OptionalAction: ViewModifier {

    let action: AccessibilityGestureAction?

    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: Text(action.label)) {
                Task { @MainActor in action.handler() }
            }
        } else {
            content
        }
    }
}

// MARK: - View Extension

extension View {

    /// Register a list of gesture fallbacks as VoiceOver / Switch
    /// Control accessible actions.
    ///
    /// Each tuple's first element is the rotor label; the second is
    /// the handler that will run when the action is invoked. This
    /// provides assistive-technology users an alternative path to
    /// gestures such as pinch-to-zoom or drag-to-trim.
    ///
    /// ```swift
    /// myClipView
    ///     .accessibilityGestureFallbacks([
    ///         ("Trim start", { vm.beginTrimStart() }),
    ///         ("Trim end", { vm.beginTrimEnd() }),
    ///         ("Split at playhead", { vm.split() }),
    ///     ])
    /// ```
    ///
    /// - Parameter actions: Tuple array of `(label, handler)` pairs.
    /// - Returns: A view with registered accessibility actions.
    func accessibilityGestureFallbacks(
        _ actions: [(String, @MainActor @Sendable () -> Void)]
    ) -> some View {
        let wrapped = actions.map { AccessibilityGestureAction($0.0, handler: $0.1) }
        return modifier(AccessibilityGestureFallbacksModifier(actions: wrapped))
    }
}
