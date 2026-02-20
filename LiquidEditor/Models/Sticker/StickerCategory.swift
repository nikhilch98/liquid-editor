import Foundation

// MARK: - StickerCategory

/// A category grouping for sticker assets.
///
/// Categories are displayed as tabs in the sticker browser.
/// Built-in categories are not deletable.
struct StickerCategory: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Display name (e.g., "Emoji", "Shapes", "Arrows", "Decorative").
    let name: String

    /// SF Symbol icon name for the category tab.
    let iconName: String

    /// Sort order in the category tab bar.
    let sortOrder: Int

    /// Whether this is a built-in category (not deletable).
    let isBuiltIn: Bool

    init(
        id: String,
        name: String,
        iconName: String,
        sortOrder: Int = 0,
        isBuiltIn: Bool = true
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }

    /// All built-in categories in display order.
    static let builtInCategories: [StickerCategory] = [
        StickerCategory(
            id: "favorites",
            name: "Favorites",
            iconName: "heart.fill",
            sortOrder: 0
        ),
        StickerCategory(
            id: "emoji",
            name: "Emoji",
            iconName: "face.smiling",
            sortOrder: 1
        ),
        StickerCategory(
            id: "shapes",
            name: "Shapes",
            iconName: "square.on.circle",
            sortOrder: 2
        ),
        StickerCategory(
            id: "icons",
            name: "Icons",
            iconName: "sparkles",
            sortOrder: 3
        ),
        StickerCategory(
            id: "animated",
            name: "Animated",
            iconName: "play.circle",
            sortOrder: 4
        ),
        StickerCategory(
            id: "decorative",
            name: "Decorative",
            iconName: "wand.and.stars",
            sortOrder: 5
        ),
        StickerCategory(
            id: "social",
            name: "Social",
            iconName: "bubble.left.fill",
            sortOrder: 6
        ),
        StickerCategory(
            id: "imported",
            name: "Imported",
            iconName: "square.and.arrow.down",
            sortOrder: 7
        ),
    ]

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case iconName
        case sortOrder
        case isBuiltIn
    }

    // MARK: - Equatable / Hashable by ID

    static func == (lhs: StickerCategory, rhs: StickerCategory) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
