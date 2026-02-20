// VideoPlayerView.swift
// LiquidEditor
//
// UIViewRepresentable wrapping an AVPlayerLayer for video playback.
// Provides a SwiftUI-compatible video rendering surface backed by
// AVFoundation's hardware-accelerated player layer.
//
// Usage:
//   VideoPlayerView(player: avPlayer)
//     .aspectRatio(16.0 / 9.0, contentMode: .fit)

import AVFoundation
import SwiftUI

// MARK: - VideoPlayerView

/// UIViewRepresentable that wraps an AVPlayerLayer for video playback.
///
/// Renders video content using AVFoundation's hardware-accelerated
/// AVPlayerLayer. The player can be swapped at any time; the layer
/// updates automatically via `updateUIView`.
///
/// This is an **acceptable use of UIViewRepresentable** because SwiftUI
/// does not provide a native equivalent for AVPlayerLayer integration.
struct VideoPlayerView: UIViewRepresentable {

    // MARK: - Properties

    /// The AVPlayer instance to display. Nil when no media is loaded.
    let player: AVPlayer?

    /// Video gravity controls how content is scaled within the layer bounds.
    /// Default is `.resizeAspect` (maintain aspect ratio, fit within bounds).
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView(videoGravity: videoGravity)
        view.playerLayer.player = player
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Video player"
        view.accessibilityTraits = .image
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        // Update the player reference when it changes (e.g., hot-swap).
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        // Update video gravity if changed.
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }

    // MARK: - PlayerUIView

    /// UIView subclass whose backing layer is an AVPlayerLayer.
    ///
    /// By overriding `layerClass`, the view's root layer is an
    /// AVPlayerLayer, which avoids an extra sublayer and ensures
    /// the video scales correctly with Auto Layout.
    final class PlayerUIView: UIView {

        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        /// Typed accessor for the view's backing AVPlayerLayer.
        var playerLayer: AVPlayerLayer {
            // swiftlint:disable:next force_cast
            layer as! AVPlayerLayer
        }

        init(videoGravity: AVLayerVideoGravity = .resizeAspect) {
            super.init(frame: .zero)
            playerLayer.videoGravity = videoGravity
            backgroundColor = .clear
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }
    }
}
