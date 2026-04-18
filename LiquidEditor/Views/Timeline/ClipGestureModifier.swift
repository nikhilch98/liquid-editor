// ClipGestureModifier.swift
// LiquidEditor
//
// T7-1 (Premium UI §10.3): Composite tap / double-tap / long-press
// gesture modifier for a single ClipView on the timeline.
//
// Semantics:
// - Single tap              -> select clip (drives the existing selection store).
// - Double-tap              -> emit `onDoubleTapped` callback (Trim Precision entry point).
// - Long-press (>= 0.45s)   -> toggles `isLongPressActive` via the
//                              `onLongPressChanged` callback so the parent can
//                              dim the timeline UI, then presents the
//                              GlassContextMenu sections provided by the caller.
//
// Haptics:
// - Tap selection: `HapticService.shared.trigger(.timelineScrub)`.
// - Long-press opens: `HapticService.shared.trigger(.selection)`.
//
// This modifier is kept additive — ClipView's existing `.onTapGesture`
// continues to be a no-op by default when this modifier is attached, so
// the callback pipeline is explicit and double-tap doesn't race with
// tap.
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

// MARK: - ClipGestureModifier

/// Attaches tap / double-tap / long-press gestures + a GlassContextMenu
/// to an arbitrary View (typically a ClipView).
struct ClipGestureModifier: ViewModifier {

    // MARK: - Inputs

    /// Sections shown in the long-press GlassContextMenu.
    let menuSections: [ContextMenuSection]

    /// Minimum duration for the long-press to register. Spec §10.3: 0.45s.
    let longPressMinimumDuration: Double

    /// Select-clip callback (single tap).
    let onTap: () -> Void

    /// Trim-precision entry point (double-tap).
    let onDoubleTapped: () -> Void

    /// Fires with `true` when long-press is engaged (parent dims UI),
    /// and `false` when the gesture ends.
    let onLongPressChanged: (Bool) -> Void

    // MARK: - Init

    init(
        menuSections: [ContextMenuSection],
        longPressMinimumDuration: Double = 0.45,
        onTap: @escaping () -> Void,
        onDoubleTapped: @escaping () -> Void,
        onLongPressChanged: @escaping (Bool) -> Void
    ) {
        self.menuSections = menuSections
        self.longPressMinimumDuration = longPressMinimumDuration
        self.onTap = onTap
        self.onDoubleTapped = onDoubleTapped
        self.onLongPressChanged = onLongPressChanged
    }

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            // Double-tap is placed BEFORE single-tap so SwiftUI prefers it
            // when the user taps twice in succession.
            .onTapGesture(count: 2) {
                onDoubleTapped()
            }
            .onTapGesture(count: 1) {
                HapticService.shared.trigger(.timelineScrub)
                onTap()
            }
            .onLongPressGesture(
                minimumDuration: longPressMinimumDuration,
                maximumDistance: 10,
                perform: {
                    HapticService.shared.trigger(.selection)
                    onLongPressChanged(true)
                },
                onPressingChanged: { isPressing in
                    // When the long-press state ends (finger lifts), flip the
                    // dim back off. Note: the `perform` closure fires AFTER
                    // `minimumDuration` elapses with the finger still down —
                    // so ordering here is correct.
                    if !isPressing {
                        onLongPressChanged(false)
                    }
                }
            )
            .glassContextMenu(sections: menuSections)
    }
}

// MARK: - View extension

extension View {

    /// Attach tap / double-tap / long-press gestures + GlassContextMenu.
    ///
    /// Use on a ClipView (or any selectable timeline element) to wire the
    /// canonical interaction set per spec §10.3.
    func clipGestures(
        menuSections: [ContextMenuSection],
        onTap: @escaping () -> Void,
        onDoubleTapped: @escaping () -> Void,
        onLongPressChanged: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            ClipGestureModifier(
                menuSections: menuSections,
                onTap: onTap,
                onDoubleTapped: onDoubleTapped,
                onLongPressChanged: onLongPressChanged
            )
        )
    }
}
