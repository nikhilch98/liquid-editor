// VoiceOverHints.swift
// LiquidEditor
//
// Standardized VoiceOver hint strings for common gesture affordances.
// Keeps hint phrasing consistent across the editor so assistive
// technology users receive predictable instructions regardless of
// which control they're inspecting.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §10.6 (A10-12)

import SwiftUI

// MARK: - VoiceOverGestureHint

/// Canonical gesture-hint strings shown by VoiceOver after the
/// control's label is announced.
///
/// The raw values are intentionally phrased in the Apple HIG voice:
/// lower-case, imperative, separated by commas.
enum VoiceOverGestureHint: String, Sendable, CaseIterable {

    /// Double tap to select; swipe up with one finger for more actions.
    case selectWithActions

    /// Double tap and hold, then drag to move.
    case dragToMove

    /// Double tap and hold, then drag left or right to trim.
    case dragToTrim

    /// Pinch open or closed to zoom.
    case pinchToZoom

    /// Double tap to toggle.
    case doubleTapToToggle

    /// Double tap to activate; long-press for additional options.
    case longPressForOptions

    /// Swipe left or right to scrub; double tap to play or pause.
    case scrubOrPlay

    /// The fully formed hint string surfaced to VoiceOver.
    var text: String {
        switch self {
        case .selectWithActions:
            "Double tap to select, swipe up for more actions"
        case .dragToMove:
            "Double tap and hold, then drag to move"
        case .dragToTrim:
            "Double tap and hold, then drag to trim"
        case .pinchToZoom:
            "Pinch open or closed to zoom"
        case .doubleTapToToggle:
            "Double tap to toggle"
        case .longPressForOptions:
            "Double tap to activate, long-press for options"
        case .scrubOrPlay:
            "Swipe left or right to scrub, double tap to play or pause"
        }
    }
}

// MARK: - View Extension

extension View {

    /// Apply a standardized VoiceOver hint describing a gesture
    /// affordance.
    ///
    /// Uses the canonical phrasing from ``VoiceOverGestureHint`` so
    /// hints remain consistent across the editor.
    ///
    /// - Parameter hint: The canonical hint to apply.
    /// - Returns: A view with `.accessibilityHint(_:)` set.
    func accessibilityHintForGesture(_ hint: VoiceOverGestureHint) -> some View {
        self.accessibilityHint(Text(hint.text))
    }

    /// Apply a custom VoiceOver hint string with a leading formatting
    /// convention that matches the canonical set.
    ///
    /// Prefer the ``VoiceOverGestureHint`` overload where one of the
    /// presets fits. Use this variant only for bespoke gestures that
    /// don't map onto the standard list.
    ///
    /// - Parameter hint: Raw hint text. Should end without a trailing period.
    /// - Returns: A view with `.accessibilityHint(_:)` set.
    func accessibilityHintForGesture(_ hint: String) -> some View {
        self.accessibilityHint(Text(hint))
    }
}
