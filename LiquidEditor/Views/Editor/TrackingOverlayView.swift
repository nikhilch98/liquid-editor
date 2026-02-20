// TrackingOverlayView.swift
// LiquidEditor
//
// Overlay view for visualizing object tracking results on the video preview.
// Draws bounding boxes, confidence/person labels, and per-body-region skeleton
// connections using Canvas for efficient rendering.
//
// Matches Flutter TrackingOverlay behavior:
// - Single primaryColor for ALL tracked objects (no per-object color cycling)
// - Per-body-region skeleton coloring: left=cyan, right=orange, torso=white, face=light green
// - Label text color is black (on colored background pill)
// - Person index integrated into label text (e.g., "Person 1 85%")
// - No separate person index circle badge
// - Border only on bounding box (no semi-transparent fill)

import SwiftUI

// MARK: - TrackingOverlayConfig

/// Configuration for tracking visualization rendering.
struct TrackingOverlayConfig: Sendable {
    /// Primary color for all tracked objects.
    var primaryColor: Color = .green

    /// Stroke width for bounding box borders.
    var strokeWidth: CGFloat = 2.0

    /// Minimum confidence to display a bounding box.
    var minDisplayConfidence: Float = 0.3

    /// Joint dot radius.
    var jointRadius: CGFloat = 3.0

    /// Skeleton line width.
    var skeletonLineWidth: CGFloat = 2.0

    /// Whether to show confidence percentage in labels.
    var showConfidence: Bool = true

    /// Whether to show person index in labels.
    var showPersonIndex: Bool = true

    /// Whether to show skeleton visualization.
    var showSkeleton: Bool = true
}

// MARK: - TrackedBoundingBox

/// Data for a single tracked object's bounding box.
///
/// Coordinates are normalized (0-1) relative to the video frame.
/// Origin is top-left.
struct TrackedBoundingBox: Sendable, Identifiable {
    /// Unique identifier for this tracked object.
    let id: String

    /// Normalized bounding box (0-1 range, top-left origin).
    let normalizedRect: CGRect

    /// Tracking confidence (0-1).
    let confidence: Float

    /// Optional label (e.g., "Person", "Face").
    let label: String?

    /// Person index for multi-person tracking (nil if not applicable).
    let personIndex: Int?

    /// Body pose skeleton joints, if available.
    /// Each joint is a normalized (0-1) point. Nil entries are undetected joints.
    let skeletonJoints: [SkeletonJoint]?
}

// MARK: - SkeletonJoint

/// A single skeleton joint with position and connection info.
struct SkeletonJoint: Sendable {
    /// Joint name (e.g., "leftShoulder", "rightHip").
    let name: String

    /// Normalized position (0-1, top-left origin).
    let position: CGPoint

    /// Confidence for this joint detection (0-1).
    let confidence: Float

    /// Names of joints this joint connects to for drawing limb lines.
    let connections: [String]
}

// MARK: - LimbGroup

/// Limb groups for per-body-region color coding of skeleton bones.
private enum LimbGroup {
    case left
    case right
    case torso
    case face

    /// Color for this limb group.
    var color: Color {
        switch self {
        case .left: Color(red: 0, green: 0.898, blue: 1.0)     // Cyan #00E5FF
        case .right: Color(red: 1.0, green: 0.569, blue: 0)    // Orange #FF9100
        case .torso: .white
        case .face: Color(red: 0.412, green: 0.941, blue: 0.682) // Light green #69F0AE
        }
    }

    /// Determine the limb group for a joint name.
    static func forJoint(_ name: String) -> LimbGroup {
        let faceJoints = ["nose", "leftEye", "rightEye", "leftEar", "rightEar"]
        if faceJoints.contains(name) { return .face }
        if name.hasPrefix("left") { return .left }
        if name.hasPrefix("right") { return .right }
        return .torso // neck, root
    }
}

// MARK: - Bone Connection

/// A connection between two skeleton joints with its limb group.
private struct BoneConnection {
    let from: String
    let to: String
    let group: LimbGroup

    static let all: [BoneConnection] = [
        // Face
        BoneConnection(from: "leftEye", to: "nose", group: .face),
        BoneConnection(from: "rightEye", to: "nose", group: .face),
        BoneConnection(from: "nose", to: "neck", group: .face),
        // Torso
        BoneConnection(from: "neck", to: "leftShoulder", group: .torso),
        BoneConnection(from: "neck", to: "rightShoulder", group: .torso),
        BoneConnection(from: "neck", to: "root", group: .torso),
        BoneConnection(from: "root", to: "leftHip", group: .torso),
        BoneConnection(from: "root", to: "rightHip", group: .torso),
        // Left limbs
        BoneConnection(from: "leftShoulder", to: "leftElbow", group: .left),
        BoneConnection(from: "leftElbow", to: "leftWrist", group: .left),
        BoneConnection(from: "leftHip", to: "leftKnee", group: .left),
        BoneConnection(from: "leftKnee", to: "leftAnkle", group: .left),
        // Right limbs
        BoneConnection(from: "rightShoulder", to: "rightElbow", group: .right),
        BoneConnection(from: "rightElbow", to: "rightWrist", group: .right),
        BoneConnection(from: "rightHip", to: "rightKnee", group: .right),
        BoneConnection(from: "rightKnee", to: "rightAnkle", group: .right),
    ]
}

// MARK: - TrackingOverlayView

/// Renders tracking visualization overlays on the video preview.
///
/// Draws:
/// - Bounding boxes with single `primaryColor` border (no fill)
/// - Integrated label with person index + confidence (black text on color pill)
/// - Per-body-region colored skeleton (cyan left, orange right, white torso, green face)
///
/// Uses `Canvas` for efficient rendering of multiple tracked objects
/// without creating individual SwiftUI views for each element.
struct TrackingOverlayView: View {

    // MARK: - Properties

    /// Tracked bounding boxes to render.
    let boundingBoxes: [TrackedBoundingBox]

    /// Size of the view for coordinate conversion.
    let viewSize: CGSize

    /// Configuration for rendering constants.
    var config: TrackingOverlayConfig = TrackingOverlayConfig()

    // MARK: - Body

    var body: some View {
        Canvas { context, size in
            let visibleBoxes = boundingBoxes.filter {
                $0.confidence >= config.minDisplayConfidence
            }

            for box in visibleBoxes {
                let rect = denormalizeRect(box.normalizedRect, in: size)

                // Draw bounding box (border only, no fill)
                drawBoundingBox(context: context, rect: rect)

                // Draw integrated label (person index + confidence)
                if config.showPersonIndex || config.showConfidence {
                    drawLabel(
                        context: context,
                        rect: rect,
                        confidence: box.confidence,
                        label: box.label,
                        personIndex: box.personIndex
                    )
                }

                // Draw skeleton with per-body-region coloring
                if config.showSkeleton, let joints = box.skeletonJoints {
                    drawSkeleton(
                        context: context,
                        joints: joints,
                        size: size
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Tracking overlay with \(boundingBoxes.count) tracked \(boundingBoxes.count == 1 ? "object" : "objects")")
        .accessibilityHint(config.showConfidence ? "Showing bounding boxes with confidence levels" : "Showing tracked object positions")
    }

    // MARK: - Drawing Functions

    /// Draw a bounding box rectangle (border only, no fill).
    private func drawBoundingBox(
        context: GraphicsContext,
        rect: CGRect
    ) {
        let path = Path(roundedRect: rect, cornerRadius: 4)
        context.stroke(
            path,
            with: .color(config.primaryColor),
            lineWidth: config.strokeWidth
        )
    }

    /// Draw an integrated label above the box with person index and confidence.
    ///
    /// Matches Flutter: "Person 1 85%" with black text on colored pill background.
    private func drawLabel(
        context: GraphicsContext,
        rect: CGRect,
        confidence: Float,
        label: String?,
        personIndex: Int?
    ) {
        var parts: [String] = []

        if config.showPersonIndex {
            if let personIndex {
                parts.append("Person \(personIndex + 1)")
            } else if let label {
                parts.append(label)
            }
        }

        if config.showConfidence {
            parts.append("\(Int(confidence * 100))%")
        }

        guard !parts.isEmpty else { return }
        let displayText = parts.joined(separator: " ")

        let text = Text(displayText)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.black) // Black text per Flutter

        let resolvedText = context.resolve(text)
        let textSize = resolvedText.measure(in: CGSize(width: 200, height: 20))

        let labelRect = CGRect(
            x: rect.minX,
            y: rect.minY - textSize.height - 4,
            width: textSize.width + 8,
            height: textSize.height + 4
        )

        // Background pill
        let backgroundPath = Path(
            roundedRect: labelRect,
            cornerRadius: 4
        )
        context.fill(backgroundPath, with: .color(config.primaryColor))

        // Text
        context.draw(
            resolvedText,
            at: CGPoint(
                x: labelRect.midX,
                y: labelRect.midY
            ),
            anchor: .center
        )
    }

    /// Draw skeleton with per-body-region coloring.
    ///
    /// Left limbs = cyan, right limbs = orange, torso = white, face = light green.
    private func drawSkeleton(
        context: GraphicsContext,
        joints: [SkeletonJoint],
        size: CGSize
    ) {
        let jointMap = Dictionary(
            uniqueKeysWithValues: joints.map { ($0.name, $0) }
        )

        // Draw bone connections with per-region coloring
        for bone in BoneConnection.all {
            guard let fromJoint = jointMap[bone.from],
                  fromJoint.confidence > config.minDisplayConfidence,
                  let toJoint = jointMap[bone.to],
                  toJoint.confidence > config.minDisplayConfidence else {
                continue
            }

            let fromPoint = denormalizePoint(fromJoint.position, in: size)
            let toPoint = denormalizePoint(toJoint.position, in: size)

            var linePath = Path()
            linePath.move(to: fromPoint)
            linePath.addLine(to: toPoint)

            context.stroke(
                linePath,
                with: .color(bone.group.color),
                lineWidth: config.skeletonLineWidth
            )
        }

        // Draw joint dots with per-region coloring
        for joint in joints {
            guard joint.confidence > config.minDisplayConfidence else { continue }
            let point = denormalizePoint(joint.position, in: size)
            let group = LimbGroup.forJoint(joint.name)

            let dotPath = Path(
                ellipseIn: CGRect(
                    x: point.x - config.jointRadius,
                    y: point.y - config.jointRadius,
                    width: config.jointRadius * 2,
                    height: config.jointRadius * 2
                )
            )

            context.fill(dotPath, with: .color(group.color))
            context.stroke(
                dotPath,
                with: .color(.white),
                lineWidth: 1
            )
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert a normalized rect (0-1) to view coordinates.
    private func denormalizeRect(_ normalizedRect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.minX * size.width,
            y: normalizedRect.minY * size.height,
            width: normalizedRect.width * size.width,
            height: normalizedRect.height * size.height
        )
    }

    /// Convert a normalized point (0-1) to view coordinates.
    private func denormalizePoint(_ normalizedPoint: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * size.width,
            y: normalizedPoint.y * size.height
        )
    }
}
