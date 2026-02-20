// StickerPreviewRenderer.swift
// LiquidEditor
//
// SwiftUI Canvas renderer for sticker overlay previews during drag.
// Renders sticker images with transforms (position, rotation, scale, flip)
// and selection handles.
//

import SwiftUI

// MARK: - StickerRenderData

/// Lightweight render data computed per-frame from a StickerClip
/// and the current playhead time, ready for painting.
struct StickerRenderData: Equatable, Sendable, Identifiable {

    var id: String { clipId }

    let clipId: String
    let stickerAssetId: String

    /// Position after keyframe interpolation (normalized 0.0-1.0).
    let position: CGPoint

    /// Scale after keyframe interpolation.
    let scale: Double

    /// Rotation in radians after keyframe interpolation.
    let rotation: Double

    /// Opacity after keyframe interpolation (0.0-1.0).
    let opacity: Double

    let isFlippedHorizontally: Bool
    let isFlippedVertically: Bool
    let tintColorValue: UInt32?

    /// Render dimensions in canvas pixels.
    let renderWidth: Double
    let renderHeight: Double

    /// Resolved sticker image (CGImage for Canvas drawing).
    let image: CGImage?

    /// Source rect within the image.
    let sourceRect: CGRect

    /// Track index for z-order.
    let trackIndex: Int

    /// Whether this is an animated sticker.
    let isAnimated: Bool

    static let identity = StickerRenderData(
        clipId: "",
        stickerAssetId: "",
        position: CGPoint(x: 0.5, y: 0.5),
        scale: 1.0,
        rotation: 0.0,
        opacity: 1.0,
        isFlippedHorizontally: false,
        isFlippedVertically: false,
        tintColorValue: nil,
        renderWidth: 0,
        renderHeight: 0,
        image: nil,
        sourceRect: .zero,
        trackIndex: 0,
        isAnimated: false
    )
}

// MARK: - StickerPreviewRenderer

/// Renders sticker overlays on the video preview canvas.
struct StickerPreviewRenderer: View, Equatable {

    /// All sticker clips visible at current time, sorted by track z-order.
    let visibleStickers: [StickerRenderData]

    /// Current playhead time (for animation progress calculation).
    let currentTimeMicros: TimeMicros

    /// Video render size (to convert normalized positions to pixels).
    let videoSize: CGSize

    /// Selected sticker clip ID (to draw selection handles).
    let selectedStickerId: String?

    init(
        visibleStickers: [StickerRenderData],
        currentTimeMicros: TimeMicros,
        videoSize: CGSize,
        selectedStickerId: String? = nil
    ) {
        self.visibleStickers = visibleStickers
        self.currentTimeMicros = currentTimeMicros
        self.videoSize = videoSize
        self.selectedStickerId = selectedStickerId
    }

    var body: some View {
        Canvas { context, size in
            let calculations = StickerPreviewCalculations(
                visibleStickers: visibleStickers,
                selectedStickerId: selectedStickerId
            )
            calculations.draw(into: &context, size: size)
        }
    }
}

// MARK: - StickerPreviewCalculations

/// Extracted calculation and drawing logic for testability.
struct StickerPreviewCalculations: Sendable {

    let visibleStickers: [StickerRenderData]
    let selectedStickerId: String?

    // MARK: - Constants

    static let handleRadius: Double = 5.0
    static let rotationHandleOffset: Double = 25.0
    static let selectionBorderWidth: Double = 1.5

    // MARK: - Animation Progress

    /// Compute animation progress for animated stickers.
    static func computeAnimationProgress(
        clipOffsetMicros: TimeMicros,
        animationSpeed: Double,
        animationLoops: Bool,
        animationDurationMs: Int?
    ) -> Double {
        guard let animDurationMs = animationDurationMs, animDurationMs > 0 else { return 0 }

        let animDurationMicros = Int64(animDurationMs) * 1000
        let adjustedOffset = Int64((Double(clipOffsetMicros) * animationSpeed).rounded())

        if animationLoops {
            return Double(adjustedOffset % animDurationMicros) / Double(animDurationMicros)
        } else {
            return min(max(Double(adjustedOffset) / Double(animDurationMicros), 0.0), 1.0)
        }
    }

    /// Hit-test whether a touch point hits a sticker.
    static func hitTestSticker(
        touchPoint: CGPoint,
        stickerPosition: CGPoint,
        stickerRotation: Double,
        stickerScale: Double,
        intrinsicWidth: Double,
        intrinsicHeight: Double,
        canvasSize: CGSize
    ) -> Bool {
        let stickerWidth = intrinsicWidth * stickerScale / canvasSize.width
        let stickerHeight = intrinsicHeight * stickerScale / canvasSize.height

        let dx = touchPoint.x - stickerPosition.x
        let dy = touchPoint.y - stickerPosition.y
        let cosR = cos(-stickerRotation)
        let sinR = sin(-stickerRotation)
        let localX = dx * cosR - dy * sinR
        let localY = dx * sinR + dy * cosR

        let halfW = stickerWidth / 2
        let halfH = stickerHeight / 2
        return localX >= -halfW && localX <= halfW && localY >= -halfH && localY <= halfH
    }

    // MARK: - Drawing

    func draw(into context: inout GraphicsContext, size: CGSize) {
        for stickerData in visibleStickers {
            renderSticker(data: stickerData, size: size, context: &context)
        }

        // Selection handles
        if let selectedId = selectedStickerId,
           let selected = visibleStickers.first(where: { $0.clipId == selectedId }) {
            drawSelectionHandles(data: selected, size: size, context: &context)
        }
    }

    private func renderSticker(data: StickerRenderData, size: CGSize, context: inout GraphicsContext) {
        guard data.opacity > 0 else { return }
        guard let image = data.image, data.renderWidth > 0, data.renderHeight > 0 else { return }

        var stickerContext = context

        // Translate to position
        let px = data.position.x * size.width
        let py = data.position.y * size.height
        stickerContext.translateBy(x: px, y: py)

        // Rotation
        stickerContext.rotate(by: Angle(radians: data.rotation))

        // Scale with flip
        let scaleX = data.scale * (data.isFlippedHorizontally ? -1 : 1)
        let scaleY = data.scale * (data.isFlippedVertically ? -1 : 1)
        stickerContext.scaleBy(x: scaleX, y: scaleY)

        // Opacity
        stickerContext.opacity = data.opacity

        // Draw image centered at origin
        let halfW = data.renderWidth / 2
        let halfH = data.renderHeight / 2
        let destRect = CGRect(x: -halfW, y: -halfH, width: data.renderWidth, height: data.renderHeight)

        let resolvedImage = stickerContext.resolve(Image(decorative: image, scale: 1.0))
        stickerContext.draw(resolvedImage, in: destRect)
    }

    private func drawSelectionHandles(data: StickerRenderData, size: CGSize, context: inout GraphicsContext) {
        let px = data.position.x * size.width
        let py = data.position.y * size.height

        var handleContext = context
        handleContext.translateBy(x: px, y: py)
        handleContext.rotate(by: Angle(radians: data.rotation))

        let halfW = data.renderWidth * data.scale / 2
        let halfH = data.renderHeight * data.scale / 2

        // Selection border
        let borderRect = CGRect(x: -halfW, y: -halfH, width: halfW * 2, height: halfH * 2)
        handleContext.stroke(
            Path(borderRect),
            with: .color(Color.white.opacity(0.8)),
            lineWidth: Self.selectionBorderWidth
        )

        // Corner handles
        let corners = [
            CGPoint(x: -halfW, y: -halfH),
            CGPoint(x: halfW, y: -halfH),
            CGPoint(x: -halfW, y: halfH),
            CGPoint(x: halfW, y: halfH),
        ]

        let radius = Self.handleRadius
        for corner in corners {
            let circlePath = Path(ellipseIn: CGRect(
                x: corner.x - radius, y: corner.y - radius,
                width: radius * 2, height: radius * 2
            ))
            handleContext.fill(circlePath, with: .color(.white))
            handleContext.stroke(
                circlePath,
                with: .color(Color(red: 0.0, green: 0.478, blue: 1.0)),
                lineWidth: Self.selectionBorderWidth
            )
        }

        // Rotation handle
        let rotationCenter = CGPoint(x: 0, y: -halfH - Self.rotationHandleOffset)

        // Line from top center to rotation handle
        var connectorPath = Path()
        connectorPath.move(to: CGPoint(x: 0, y: -halfH))
        connectorPath.addLine(to: rotationCenter)
        handleContext.stroke(
            connectorPath,
            with: .color(Color.white.opacity(0.6)),
            lineWidth: 1.0
        )

        let rotCirclePath = Path(ellipseIn: CGRect(
            x: rotationCenter.x - radius, y: rotationCenter.y - radius,
            width: radius * 2, height: radius * 2
        ))
        handleContext.fill(rotCirclePath, with: .color(.white))
        handleContext.stroke(
            rotCirclePath,
            with: .color(Color(red: 0.204, green: 0.78, blue: 0.349)),
            lineWidth: Self.selectionBorderWidth
        )
    }
}
