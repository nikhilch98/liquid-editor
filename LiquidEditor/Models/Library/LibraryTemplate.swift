// LibraryTemplate.swift
// LiquidEditor
//
// Library template system: hand-curated project starter templates surfaced
// in the Library tab. Separate from `ProjectTemplate` (which configures
// resolution/FPS/aspect presets) -- this model adds a pre-populated set of
// placeholder clips so users can remix a ready-made structure.
//
// Introduced for S2-17 (premium UI redesign: Library templates).

import Foundation

// MARK: - LibraryTemplateCategory

/// High-level use-case grouping for a `LibraryTemplate`.
///
/// Distinct from `TemplateCategory` in `ProjectTemplate.swift`: that enum
/// classifies project configuration presets, while this one classifies
/// starter-content templates surfaced to the user in the Library tab.
enum LibraryTemplateCategory: String, Codable, CaseIterable, Sendable {
    case social
    case cinematic
    case promo
    case tutorial
    case vlog

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .social: return "Social"
        case .cinematic: return "Cinematic"
        case .promo: return "Promo"
        case .tutorial: return "Tutorial"
        case .vlog: return "Vlog"
        }
    }

    /// SF Symbol name used in the Library tab chip UI.
    var iconSymbol: String {
        switch self {
        case .social: return "heart.circle"
        case .cinematic: return "film"
        case .promo: return "megaphone"
        case .tutorial: return "graduationcap"
        case .vlog: return "video.badge.waveform"
        }
    }
}

// MARK: - TemplatePresetClip

/// A lightweight description of a clip placeholder within a `LibraryTemplate`.
///
/// The `kind` is a free-form string ("title", "bRoll", "main", "outro", ...)
/// that the project creation flow interprets when materializing placeholders
/// into real clips on the timeline.
struct TemplatePresetClip: Codable, Sendable, Hashable {

    /// Free-form clip role identifier.
    let kind: String

    /// Target duration for this placeholder in seconds.
    let durationSec: Double

    init(kind: String, durationSec: Double) {
        self.kind = kind
        self.durationSec = durationSec
    }
}

// MARK: - LibraryTemplate

/// A featured starter template shown in the Library tab.
///
/// Contains display metadata (`name`, `thumbnailName`) alongside a structural
/// recipe (`presetClips`) the editor can instantiate when the user picks the
/// template during project creation.
struct LibraryTemplate: Identifiable, Codable, Sendable, Hashable {

    /// Stable identity used by SwiftUI `ForEach`.
    let id: UUID

    /// Display name shown in the Library grid.
    let name: String

    /// High-level category (drives filter chips and iconography).
    let category: LibraryTemplateCategory

    /// Approximate total duration in seconds of the generated project.
    let durationSec: Double

    /// Suggested project aspect ratio (16:9, 9:16, 1:1, 4:5, ...).
    let aspectRatio: AspectRatioSetting

    /// Asset-catalog name for the template thumbnail (fallback is SF Symbol).
    let thumbnailName: String

    /// Ordered list of placeholder clips this template will generate.
    let presetClips: [TemplatePresetClip]

    init(
        id: UUID = UUID(),
        name: String,
        category: LibraryTemplateCategory,
        durationSec: Double,
        aspectRatio: AspectRatioSetting,
        thumbnailName: String,
        presetClips: [TemplatePresetClip]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.durationSec = durationSec
        self.aspectRatio = aspectRatio
        self.thumbnailName = thumbnailName
        self.presetClips = presetClips
    }

    // MARK: - Built-in Templates

    /// Stable UUIDs for built-in templates so identity survives app restarts
    /// (allowing "recently used" tracking against them in the future).
    private enum BuiltInID {
        static let reelsQuickCut = UUID(uuidString: "A0000001-0000-0000-0000-000000000001")!
        static let tiktokTrend = UUID(uuidString: "A0000001-0000-0000-0000-000000000002")!
        static let cinematicTrailer = UUID(uuidString: "A0000001-0000-0000-0000-000000000003")!
        static let moodyBRoll = UUID(uuidString: "A0000001-0000-0000-0000-000000000004")!
        static let productPromo = UUID(uuidString: "A0000001-0000-0000-0000-000000000005")!
        static let tutorialHowTo = UUID(uuidString: "A0000001-0000-0000-0000-000000000006")!
        static let dailyVlog = UUID(uuidString: "A0000001-0000-0000-0000-000000000007")!
        static let travelMontage = UUID(uuidString: "A0000001-0000-0000-0000-000000000008")!
    }

    /// Hand-curated catalog of built-in templates surfaced in the Library tab.
    static let builtIn: [LibraryTemplate] = [
        LibraryTemplate(
            id: BuiltInID.reelsQuickCut,
            name: "Reels Quick-Cut",
            category: .social,
            durationSec: 15,
            aspectRatio: .portrait9x16,
            thumbnailName: "template_reels_quickcut",
            presetClips: [
                TemplatePresetClip(kind: "title", durationSec: 2),
                TemplatePresetClip(kind: "main", durationSec: 11),
                TemplatePresetClip(kind: "outro", durationSec: 2),
            ]
        ),
        LibraryTemplate(
            id: BuiltInID.tiktokTrend,
            name: "TikTok Trend",
            category: .social,
            durationSec: 30,
            aspectRatio: .portrait9x16,
            thumbnailName: "template_tiktok_trend",
            presetClips: [
                TemplatePresetClip(kind: "hook", durationSec: 3),
                TemplatePresetClip(kind: "main", durationSec: 24),
                TemplatePresetClip(kind: "cta", durationSec: 3),
            ]
        ),
        LibraryTemplate(
            id: BuiltInID.cinematicTrailer,
            name: "Cinematic Trailer",
            category: .cinematic,
            durationSec: 60,
            aspectRatio: .cinematic,
            thumbnailName: "template_cinematic_trailer",
            presetClips: [
                TemplatePresetClip(kind: "coldOpen", durationSec: 8),
                TemplatePresetClip(kind: "bRoll", durationSec: 18),
                TemplatePresetClip(kind: "main", durationSec: 24),
                TemplatePresetClip(kind: "title", durationSec: 10),
            ]
        ),
        LibraryTemplate(
            id: BuiltInID.moodyBRoll,
            name: "Moody B-Roll",
            category: .cinematic,
            durationSec: 45,
            aspectRatio: .landscape16x9,
            thumbnailName: "template_moody_broll",
            presetClips: [
                TemplatePresetClip(kind: "bRoll", durationSec: 15),
                TemplatePresetClip(kind: "bRoll", durationSec: 15),
                TemplatePresetClip(kind: "bRoll", durationSec: 15),
            ]
        ),
        LibraryTemplate(
            id: BuiltInID.productPromo,
            name: "Product Promo",
            category: .promo,
            durationSec: 20,
            aspectRatio: .square1x1,
            thumbnailName: "template_product_promo",
            presetClips: [
                TemplatePresetClip(kind: "hero", durationSec: 5),
                TemplatePresetClip(kind: "feature", durationSec: 6),
                TemplatePresetClip(kind: "feature", durationSec: 6),
                TemplatePresetClip(kind: "cta", durationSec: 3),
            ]
        ),
        LibraryTemplate(
            id: BuiltInID.tutorialHowTo,
            name: "How-To Tutorial",
            category: .tutorial,
            durationSec: 90,
            aspectRatio: .landscape16x9,
            thumbnailName: "template_tutorial_howto",
            presetClips: [
                TemplatePresetClip(kind: "intro", durationSec: 10),
                TemplatePresetClip(kind: "step", durationSec: 25),
                TemplatePresetClip(kind: "step", durationSec: 25),
                TemplatePresetClip(kind: "step", durationSec: 20),
                TemplatePresetClip(kind: "outro", durationSec: 10),
            ]
        ),
        LibraryTemplate(
            id: BuiltInID.dailyVlog,
            name: "Daily Vlog",
            category: .vlog,
            durationSec: 120,
            aspectRatio: .landscape16x9,
            thumbnailName: "template_daily_vlog",
            presetClips: [
                TemplatePresetClip(kind: "intro", durationSec: 15),
                TemplatePresetClip(kind: "main", durationSec: 45),
                TemplatePresetClip(kind: "bRoll", durationSec: 30),
                TemplatePresetClip(kind: "main", durationSec: 20),
                TemplatePresetClip(kind: "outro", durationSec: 10),
            ]
        ),
        LibraryTemplate(
            id: BuiltInID.travelMontage,
            name: "Travel Montage",
            category: .vlog,
            durationSec: 75,
            aspectRatio: .portrait4x5,
            thumbnailName: "template_travel_montage",
            presetClips: [
                TemplatePresetClip(kind: "title", durationSec: 5),
                TemplatePresetClip(kind: "bRoll", durationSec: 20),
                TemplatePresetClip(kind: "bRoll", durationSec: 25),
                TemplatePresetClip(kind: "bRoll", durationSec: 20),
                TemplatePresetClip(kind: "outro", durationSec: 5),
            ]
        ),
    ]
}
