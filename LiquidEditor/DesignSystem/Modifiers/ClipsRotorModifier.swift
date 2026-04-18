// ClipsRotorModifier.swift
// LiquidEditor
//
// Custom "Clips" VoiceOver rotor for the timeline.
//
// VoiceOver users can rotate two fingers on the timeline to cycle between
// rotors. Selecting the "Clips" rotor and swiping up/down then jumps
// through each clip in order, moving the playhead and selection to that
// clip. Each entry announces the clip's display name.
//
// Apple docs: `accessibilityRotor(_:entries:)` and `AccessibilityRotorEntry`.

import SwiftUI

// MARK: - ClipsRotorEntry

/// Lightweight `Identifiable` wrapper for a rotor entry so the modifier
/// does not need access to the full `TimelineItem` model.
struct ClipsRotorEntry: Identifiable, Hashable {

    /// Clip identifier (matches `TimelineItemProtocol.id`).
    let id: String

    /// Human-readable clip name announced by VoiceOver.
    let displayName: String

    /// Absolute timeline start position in microseconds. The rotor
    /// navigation moves the playhead here when the user activates the entry.
    let startTimeMicros: TimeMicros
}

// MARK: - ClipsRotorModifier

/// Adds a "Clips" VoiceOver rotor to a view.
///
/// On activation the entry's `onActivate` closure is called with the clip
/// `id`; the caller is responsible for selecting the clip and seeking the
/// playhead. Entries are rebuilt whenever the array identity changes.
struct ClipsRotorModifier: ViewModifier {

    let label: LocalizedStringKey
    let entries: [ClipsRotorEntry]
    let onActivate: (String) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityRotor(label) {
                ForEach(entries) { entry in
                    // The `prepare` closure runs on the main thread before
                    // VoiceOver focuses the entry, so we use it to jump
                    // selection + playhead to the clip.
                    AccessibilityRotorEntry(
                        Text(entry.displayName),
                        id: entry.id,
                        prepare: {
                            onActivate(entry.id)
                        }
                    )
                }
            }
    }
}

extension View {

    /// Attach a "Clips" rotor listing every clip on the timeline.
    ///
    /// - Parameters:
    ///   - entries: Ordered clip entries (name + start time).
    ///   - label: Optional custom rotor label (defaults to "Clips").
    ///   - onActivate: Closure invoked with the clip id when the user
    ///     activates that rotor entry via VoiceOver.
    func clipsRotor(
        entries: [ClipsRotorEntry],
        label: LocalizedStringKey = "Clips",
        onActivate: @escaping (String) -> Void
    ) -> some View {
        modifier(ClipsRotorModifier(label: label, entries: entries, onActivate: onActivate))
    }
}
