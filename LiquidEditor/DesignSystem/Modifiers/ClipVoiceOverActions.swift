// ClipVoiceOverActions.swift
// LiquidEditor
//
// VoiceOver custom actions for clip views (A10-14).
//
// When the user focuses a `ClipView` and swipes up/down with the
// VoiceOver rotor positioned on "Actions", iOS 26 reads out each
// registered action and lets them activate it without exposing a
// visible control. This modifier attaches up to five canonical clip
// actions:
//
//   • "Split at playhead"
//   • "Delete clip"
//   • "Duplicate"
//   • "Adjust volume"
//   • "Trim mode"
//
// Each action is optional: pass `nil` to skip. Only registered
// actions are announced by VoiceOver.

import SwiftUI

// MARK: - ClipVoiceOverActions

/// View modifier that registers VoiceOver-only custom actions on a
/// clip view via SwiftUI's `.accessibilityActions` block.
struct ClipVoiceOverActions: ViewModifier {

    let onSplit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onDuplicate: (() -> Void)?
    let onVolume: (() -> Void)?
    let onTrim: (() -> Void)?

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let onSplit {
                Button("Split at playhead", action: onSplit)
            }
            if let onDelete {
                Button("Delete clip", role: .destructive, action: onDelete)
            }
            if let onDuplicate {
                Button("Duplicate", action: onDuplicate)
            }
            if let onVolume {
                Button("Adjust volume", action: onVolume)
            }
            if let onTrim {
                Button("Trim mode", action: onTrim)
            }
        }
    }
}

// MARK: - View extension

extension View {

    /// Attach the canonical clip VoiceOver custom actions.
    ///
    /// Pass `nil` for any action the clip does not support (e.g. an
    /// audio-only clip may omit `onVolume` only if you want to; the
    /// natural interpretation is to still expose it and let the
    /// handler no-op).
    func clipVoiceOverActions(
        onSplit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onDuplicate: (() -> Void)? = nil,
        onVolume: (() -> Void)? = nil,
        onTrim: (() -> Void)? = nil
    ) -> some View {
        modifier(ClipVoiceOverActions(
            onSplit: onSplit,
            onDelete: onDelete,
            onDuplicate: onDuplicate,
            onVolume: onVolume,
            onTrim: onTrim
        ))
    }
}
