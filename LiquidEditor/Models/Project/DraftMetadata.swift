// DraftMetadata.swift
// LiquidEditor
//
// Draft metadata for auto-save ring buffer and crash recovery.

import Foundation

// MARK: - DraftTriggerReason

/// Reason a draft was saved.
enum DraftTriggerReason: String, Codable, CaseIterable, Sendable {
    /// Regular 2-second debounced auto-save.
    case autoSave
    /// User explicitly saved.
    case manualSave
    /// Major operation (add/delete clip, aspect ratio change).
    case significantEdit
    /// App moved to background.
    case appBackground

    var displayName: String {
        switch self {
        case .autoSave: return "Auto-save"
        case .manualSave: return "Manual save"
        case .significantEdit: return "After edit"
        case .appBackground: return "Background save"
        }
    }
}

// MARK: - DraftEntry

/// A single draft entry in the ring buffer.
struct DraftEntry: Codable, Equatable, Hashable, Sendable {

    /// Ring buffer slot index (0 to maxDrafts-1).
    let index: Int

    /// When this draft was saved.
    let savedAt: Date

    /// Number of clips at save time.
    let clipCount: Int

    /// Timeline duration in microseconds at save time.
    let timelineDurationMicros: TimeMicros

    /// What triggered this save.
    let triggerReason: DraftTriggerReason

    /// Formatted duration string.
    var formattedDuration: String {
        let totalSeconds = Int(timelineDurationMicros / 1_000_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    // MARK: - with(...)

    func with(
        index: Int? = nil,
        savedAt: Date? = nil,
        clipCount: Int? = nil,
        timelineDurationMicros: TimeMicros? = nil,
        triggerReason: DraftTriggerReason? = nil
    ) -> DraftEntry {
        DraftEntry(
            index: index ?? self.index,
            savedAt: savedAt ?? self.savedAt,
            clipCount: clipCount ?? self.clipCount,
            timelineDurationMicros: timelineDurationMicros ?? self.timelineDurationMicros,
            triggerReason: triggerReason ?? self.triggerReason
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: DraftEntry, rhs: DraftEntry) -> Bool {
        lhs.index == rhs.index && lhs.savedAt == rhs.savedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(index)
        hasher.combine(savedAt)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case index
        case savedAt
        case clipCount
        case timelineDurationMicros
        case timelineDurationMs
        case triggerReason
    }

    // MARK: - Custom Decoding

    init(
        index: Int,
        savedAt: Date,
        clipCount: Int,
        timelineDurationMicros: TimeMicros,
        triggerReason: DraftTriggerReason
    ) {
        self.index = index
        self.savedAt = savedAt
        self.clipCount = clipCount
        self.timelineDurationMicros = timelineDurationMicros
        self.triggerReason = triggerReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)

        let savedAtStr = try container.decode(String.self, forKey: .savedAt)
        savedAt = ISO8601DateFormatter().date(from: savedAtStr) ?? Date()

        clipCount = try container.decode(Int.self, forKey: .clipCount)

        // Support both microsecond and millisecond keys (migration compat)
        if let micros = try container.decodeIfPresent(TimeMicros.self, forKey: .timelineDurationMicros) {
            timelineDurationMicros = micros
        } else if let ms = try container.decodeIfPresent(Int.self, forKey: .timelineDurationMs) {
            timelineDurationMicros = TimeMicros(ms) * 1000
        } else {
            timelineDurationMicros = 0
        }

        let reasonStr = try container.decodeIfPresent(String.self, forKey: .triggerReason)
        triggerReason = reasonStr.flatMap { DraftTriggerReason(rawValue: $0) } ?? .autoSave
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(ISO8601DateFormatter().string(from: savedAt), forKey: .savedAt)
        try container.encode(clipCount, forKey: .clipCount)
        try container.encode(timelineDurationMicros, forKey: .timelineDurationMicros)
        try container.encode(triggerReason.rawValue, forKey: .triggerReason)
    }
}

// MARK: - DraftMetadata

/// Draft metadata for a project's auto-save ring buffer.
struct DraftMetadata: Codable, Equatable, Hashable, Sendable {

    /// Project this draft metadata belongs to.
    let projectId: String

    /// Current write position in the ring buffer.
    let currentIndex: Int

    /// All draft entries (up to maxDrafts).
    let drafts: [DraftEntry]

    /// Whether the last session shut down cleanly.
    ///
    /// If false on project open, crash recovery should be offered.
    let cleanShutdown: Bool

    /// Maximum number of drafts in the ring buffer.
    static let maxDrafts: Int = 5

    // MARK: - Init

    init(
        projectId: String,
        currentIndex: Int,
        drafts: [DraftEntry],
        cleanShutdown: Bool
    ) {
        self.projectId = projectId
        self.currentIndex = currentIndex
        self.drafts = drafts
        self.cleanShutdown = cleanShutdown
    }

    /// Empty metadata for a new project.
    static func empty(projectId: String) -> DraftMetadata {
        DraftMetadata(
            projectId: projectId,
            currentIndex: 0,
            drafts: [],
            cleanShutdown: true
        )
    }

    /// Get the most recent draft entry.
    var latestDraft: DraftEntry? {
        drafts.max(by: { $0.savedAt < $1.savedAt })
    }

    /// Next ring buffer index for writing.
    var nextIndex: Int { (currentIndex + 1) % Self.maxDrafts }

    /// Create a copy with a new draft added.
    func withNewDraft(_ draft: DraftEntry) -> DraftMetadata {
        var newDrafts = drafts
        if let existingIdx = newDrafts.firstIndex(where: { $0.index == draft.index }) {
            newDrafts[existingIdx] = draft
        } else {
            newDrafts.append(draft)
        }
        return DraftMetadata(
            projectId: projectId,
            currentIndex: draft.index,
            drafts: newDrafts,
            cleanShutdown: false
        )
    }

    /// Mark as cleanly shut down.
    func markCleanShutdown() -> DraftMetadata {
        DraftMetadata(
            projectId: projectId,
            currentIndex: currentIndex,
            drafts: drafts,
            cleanShutdown: true
        )
    }

    /// Mark as dirty (session started).
    func markSessionStarted() -> DraftMetadata {
        DraftMetadata(
            projectId: projectId,
            currentIndex: currentIndex,
            drafts: drafts,
            cleanShutdown: false
        )
    }

    // MARK: - with(...)

    func with(
        projectId: String? = nil,
        currentIndex: Int? = nil,
        drafts: [DraftEntry]? = nil,
        cleanShutdown: Bool? = nil
    ) -> DraftMetadata {
        DraftMetadata(
            projectId: projectId ?? self.projectId,
            currentIndex: currentIndex ?? self.currentIndex,
            drafts: drafts ?? self.drafts,
            cleanShutdown: cleanShutdown ?? self.cleanShutdown
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: DraftMetadata, rhs: DraftMetadata) -> Bool {
        lhs.projectId == rhs.projectId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(projectId)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case projectId
        case currentIndex
        case drafts
        case cleanShutdown
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectId = try container.decode(String.self, forKey: .projectId)
        currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        drafts = try container.decode([DraftEntry].self, forKey: .drafts)
        cleanShutdown = try container.decodeIfPresent(Bool.self, forKey: .cleanShutdown) ?? true
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(currentIndex, forKey: .currentIndex)
        try container.encode(drafts, forKey: .drafts)
        try container.encode(cleanShutdown, forKey: .cleanShutdown)
    }
}
