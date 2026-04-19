// MediaDropReceiverModifier.swift
// LiquidEditor
//
// T7-6 (Premium UI §10.3): Track lane accepts MediaAsset drags from the
// Media Browser and fires a callback with resolved track index + time.
//
// While a drag hovers, the lane is highlighted with a translucent accent
// fill so the user can see the drop target. The caller provides a
// `resolve(location) -> (trackIndex, seconds)` closure for mapping the
// local drop location to timeline coordinates.
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Transferable conformance

/// `MediaAsset` is already `Codable + Sendable`, so it can be shuttled as
/// JSON between drag source (Media Browser) and drop target (timeline).
extension MediaAsset: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .liquidEditorMediaAsset)
    }
}

extension UTType {
    /// Custom UTType for dragging `MediaAsset` payloads inside the app.
    static let liquidEditorMediaAsset = UTType(
        exportedAs: "com.liquideditor.media-asset"
    )
}

/// Accepts `MediaAsset` drops on a track lane.
struct MediaDropReceiverModifier: ViewModifier {

    /// Index of the track this lane represents.
    let trackIndex: Int

    /// Resolver from local drop point -> timeline seconds.
    let resolveSeconds: (CGPoint) -> Double

    /// Fires when assets are dropped. Caller inserts them on the timeline.
    let onDrop: ([MediaAsset], Int, Double) -> Void

    @State private var isTargeted: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(isTargeted ? 0.18 : 0))
                    .allowsHitTesting(false)
            )
            .animation(.liquid(LiquidMotion.easeOut, reduceMotion: reduceMotion), value: isTargeted)
            .dropDestination(for: MediaAsset.self) { assets, location in
                let seconds = resolveSeconds(location)
                onDrop(assets, trackIndex, seconds)
                return !assets.isEmpty
            } isTargeted: { isTargeted = $0 }
    }
}

extension View {
    /// Accept `MediaAsset` drops from the Media Browser on this lane.
    func mediaDropReceiver(
        trackIndex: Int,
        resolveSeconds: @escaping (CGPoint) -> Double,
        onDrop: @escaping ([MediaAsset], Int, Double) -> Void
    ) -> some View {
        modifier(MediaDropReceiverModifier(
            trackIndex: trackIndex,
            resolveSeconds: resolveSeconds,
            onDrop: onDrop
        ))
    }
}
