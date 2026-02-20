// CompositeLayer.swift
// LiquidEditor
//
// Composite layer for per-frame rendering instructions.
// Generated at a specific playhead time and passed to the native compositor.

import Foundation

/// A single layer in the composite stack at a specific time.
///
/// Represents one track's contribution to the composited output
/// at a specific playhead position. Contains all information needed
/// for the native compositor to render this layer.
struct CompositeLayer: Equatable, Hashable, Sendable {
    /// Track ID this layer belongs to.
    let trackId: String

    /// Track index in the rendering order.
    let trackIndex: Int

    /// The clip ID providing content at this time.
    let clipId: String

    /// Clip type identifier (e.g., "video", "image", "color").
    let clipType: String

    /// Media asset ID if the clip references external media, nil otherwise.
    let mediaAssetId: String?

    /// Source time in microseconds (for media clips with speed/offset mapping).
    let sourceTimeMicros: Int?

    /// Offset within the clip (microseconds from clip start).
    let clipOffsetMicros: Int

    /// Absolute timeline position (microseconds).
    let timelineMicros: Int

    /// Composite configuration for this track.
    let compositeConfig: TrackCompositeConfig

    /// Serialize for platform channel communication.
    func toChannelMap() -> [String: Any] {
        var map: [String: Any] = [
            "trackId": trackId,
            "trackIndex": trackIndex,
            "clipId": clipId,
            "clipType": clipType,
            "layout": compositeConfig.layout.rawValue,
            "opacity": compositeConfig.opacity,
            "blendMode": compositeConfig.blendMode.ciFilterName,
            "volume": compositeConfig.volume,
        ]

        if let mediaAssetId {
            map["mediaAssetId"] = mediaAssetId
        }
        if let sourceTimeMicros {
            map["sourceTimeMicros"] = sourceTimeMicros
        }
        if let pipRegion = compositeConfig.pipRegion {
            map["pipRegion"] = [
                "x": pipRegion.x,
                "y": pipRegion.y,
                "width": pipRegion.width,
                "height": pipRegion.height,
            ]
        }
        if let chromaKey = compositeConfig.chromaKey {
            map["chromaKey"] = [
                "targetColor": chromaKey.targetColor.rawValue,
                "customColorValue": chromaKey.customColorValue as Any,
                "sensitivity": chromaKey.sensitivity,
                "smoothness": chromaKey.smoothness,
                "spillSuppression": chromaKey.spillSuppression,
                "isEnabled": chromaKey.isEnabled,
            ]
        }

        return map
    }
}

// MARK: - CustomStringConvertible

extension CompositeLayer: CustomStringConvertible {
    var description: String {
        "CompositeLayer(track: \(trackId), clip: \(clipId), offset: \(clipOffsetMicros))"
    }
}
