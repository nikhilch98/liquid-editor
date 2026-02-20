import Foundation

// MARK: - SFXCategory

/// Category of bundled sound effect.
enum SFXCategory: String, Codable, CaseIterable, Sendable {
    case transitions
    case ui
    case impacts
    case nature
    case ambience
    case musical
    case foley

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .transitions: "Transitions"
        case .ui: "UI"
        case .impacts: "Impacts"
        case .nature: "Nature"
        case .ambience: "Ambience"
        case .musical: "Musical"
        case .foley: "Foley"
        }
    }

    /// SF Symbol icon for this category.
    var sfSymbolName: String {
        switch self {
        case .transitions: "arrow.right.arrow.left"
        case .ui: "hand.tap"
        case .impacts: "bolt.fill"
        case .nature: "leaf.fill"
        case .ambience: "waveform"
        case .musical: "music.note"
        case .foley: "shoe.fill"
        }
    }
}

// MARK: - SoundEffectAsset

/// Metadata for a bundled sound effect.
struct SoundEffectAsset: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Display name.
    let name: String

    /// Category for browsing.
    let category: SFXCategory

    /// Duration in microseconds.
    let durationMicros: TimeMicros

    /// Asset bundle path (relative to assets/).
    let assetPath: String

    /// Tags for search.
    let tags: [String]

    init(
        id: String,
        name: String,
        category: SFXCategory,
        durationMicros: TimeMicros,
        assetPath: String,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.durationMicros = durationMicros
        self.assetPath = assetPath
        self.tags = tags
    }

    /// Duration in seconds.
    var durationSeconds: Double { Double(durationMicros) / 1_000_000.0 }

    /// Whether the name or tags match a search query.
    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let lowerQuery = query.lowercased()
        if name.lowercased().contains(lowerQuery) { return true }
        return tags.contains { $0.lowercased().contains(lowerQuery) }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case durationMicros
        case assetPath
        case tags
    }

    // MARK: - Equatable / Hashable by ID

    static func == (lhs: SoundEffectAsset, rhs: SoundEffectAsset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
