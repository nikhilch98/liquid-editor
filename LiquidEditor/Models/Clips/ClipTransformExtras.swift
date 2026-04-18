// ClipTransformExtras.swift
// LiquidEditor
//
// M15-8 (supplementary): Additional per-clip transform + mixdown data
// that complements the existing types:
//
// - OverlayTransform (Models/Compositing/OverlayTransform.swift) already
//   covers position, scale, rotation, opacity, anchor.
// - CompBlendMode (Models/Compositing/CompBlendMode.swift) already
//   covers track-level blend modes.
// - NormalizedRect (Models/Compositing/NormalizedRect.swift) already
//   provides the primitive for rect-based crop.
//
// This file adds ONLY the net-new pieces per spec §7.12:
// - Flip horizontal / flip vertical (toggle, distinct from free rotation)
// - Rect crop (wraps NormalizedRect)
// - Audio pan / normalize target for audio clips
//
// Wiring into existing Clip types (VideoClip, ImageClip, AudioClip)
// happens incrementally — new optional fields with default values so
// existing call sites keep compiling.

import CoreGraphics
import Foundation

// MARK: - ClipFlipState

/// Per-clip horizontal / vertical flip. Applied AFTER OverlayTransform's
/// rotation, so flip+rotate combinations behave predictably across
/// render and inspector readouts.
struct ClipFlipState: Codable, Equatable, Hashable, Sendable {
    var horizontal: Bool
    var vertical: Bool

    init(horizontal: Bool = false, vertical: Bool = false) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    static let none = ClipFlipState()
}

// MARK: - ClipCrop

/// Per-clip rect crop distinct from masks (§7.5 is free-form; this is
/// a simple top/right/bottom/left rectangular crop rendered by the
/// composition pipeline as a NormalizedRect).
struct ClipCrop: Codable, Equatable, Hashable, Sendable {
    /// Crop amount from each edge in normalized units (0.0 = no crop,
    /// 0.25 = 25% shaved off that edge).
    var top: Double
    var right: Double
    var bottom: Double
    var left: Double

    init(top: Double = 0, right: Double = 0, bottom: Double = 0, left: Double = 0) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    /// No crop.
    static let none = ClipCrop()

    /// Whether any edge has a non-zero crop value.
    var isActive: Bool {
        top > 0 || right > 0 || bottom > 0 || left > 0
    }
}

// MARK: - AudioMixdown

/// Per-audio-clip pan + normalization target per spec §7.12 audio subset.
struct AudioMixdown: Codable, Equatable, Hashable, Sendable {

    /// Stereo pan, -1.0 (hard left) ... +1.0 (hard right). 0 = center.
    var pan: Double

    /// Optional loudness-normalization target in LUFS.
    /// nil = no normalization applied.
    var lufsTarget: LufsTarget?

    init(pan: Double = 0, lufsTarget: LufsTarget? = nil) {
        self.pan = pan
        self.lufsTarget = lufsTarget
    }

    static let neutral = AudioMixdown()
}

// MARK: - LufsTarget

/// Loudness-normalization target chips per spec §7.12 / §6.2.
enum LufsTarget: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    /// Streaming (Apple Music / Spotify default).
    case streaming     // -16 LUFS
    /// Loud / broadcast-quiet target.
    case loud          // -14 LUFS
    /// Broadcast (EBU R128).
    case broadcast     // -23 LUFS

    var dbfs: Double {
        switch self {
        case .streaming: return -16
        case .loud:      return -14
        case .broadcast: return -23
        }
    }
}
