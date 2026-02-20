import Foundation

/// A single subtitle entry parsed from SRT or VTT.
///
/// This is an intermediate type used during import/export.
/// After parsing, entries are converted to text clips
/// with `isSubtitle: true`.
struct SubtitleEntry: Codable, Equatable, Hashable, Sendable {
    /// Sequential index (1-based for SRT compatibility).
    let index: Int

    /// Start time in microseconds from video start.
    let startMicros: TimeMicros

    /// End time in microseconds from video start.
    let endMicros: TimeMicros

    /// Subtitle text content (may contain newlines for multi-line subtitles).
    let text: String

    /// Optional speaker label (for multi-speaker SRT with tags).
    let speaker: String?

    /// Style overrides (nil = use track default style).
    let styleOverride: TextOverlayStyle?

    init(
        index: Int,
        startMicros: TimeMicros,
        endMicros: TimeMicros,
        text: String,
        speaker: String? = nil,
        styleOverride: TextOverlayStyle? = nil
    ) {
        self.index = index
        self.startMicros = startMicros
        self.endMicros = endMicros
        self.text = text
        self.speaker = speaker
        self.styleOverride = styleOverride
    }

    /// Duration in microseconds.
    var durationMicros: TimeMicros { endMicros - startMicros }

    /// Whether this entry has valid timing (end > start).
    var isValid: Bool { endMicros > startMicros && !text.isEmpty }

    /// Create a copy with optional overrides.
    func with(
        index: Int? = nil,
        startMicros: TimeMicros? = nil,
        endMicros: TimeMicros? = nil,
        text: String? = nil,
        speaker: String? = nil,
        styleOverride: TextOverlayStyle? = nil,
        clearSpeaker: Bool = false,
        clearStyleOverride: Bool = false
    ) -> SubtitleEntry {
        SubtitleEntry(
            index: index ?? self.index,
            startMicros: startMicros ?? self.startMicros,
            endMicros: endMicros ?? self.endMicros,
            text: text ?? self.text,
            speaker: clearSpeaker ? nil : (speaker ?? self.speaker),
            styleOverride: clearStyleOverride ? nil : (styleOverride ?? self.styleOverride)
        )
    }

    // MARK: - Equatable

    static func == (lhs: SubtitleEntry, rhs: SubtitleEntry) -> Bool {
        lhs.index == rhs.index
            && lhs.startMicros == rhs.startMicros
            && lhs.endMicros == rhs.endMicros
            && lhs.text == rhs.text
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(index)
        hasher.combine(startMicros)
        hasher.combine(endMicros)
        hasher.combine(text)
    }
}
