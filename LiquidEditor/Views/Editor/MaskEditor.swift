// MaskEditor.swift
// LiquidEditor
//
// E4-4: Full-screen mask editor for drawing and editing clip masks.
//
// Supports three mask shapes:
//   - Rectangle: draggable handles for resize + drag center to move
//   - Ellipse: same handles as rectangle, rendered as an ellipse
//   - Freehand: drawable canvas with finger/pencil strokes
//
// The view is decoupled from any view model: the caller passes an optional
// initial mask (typically the current clip's mask) and an ``onApply``
// closure invoked with the completed ``Mask`` value. This keeps the editor
// focused purely on UI state.

import SwiftUI

// MARK: - MaskShapeKind

/// UI-facing mask shape selection.
enum MaskShapeKind: String, CaseIterable, Identifiable, Sendable {
    case rectangle
    case ellipse
    case freehand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .freehand: "Freehand"
        }
    }

    var iconName: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .freehand: "scribble.variable"
        }
    }
}

// MARK: - MaskEditor

/// Full-screen editor for creating/editing a clip mask.
@MainActor
struct MaskEditor: View {

    // MARK: - Input

    /// Optional starting mask (used to seed initial editor state).
    let initialMask: Mask?

    /// Called when the user taps Apply with the constructed ``Mask``.
    let onApply: (Mask) -> Void

    // MARK: - State

    @State private var shapeKind: MaskShapeKind
    @State private var rectNormalized: CGRect
    @State private var strokes: [BrushStroke] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var featherPoints: Double
    @State private var isInverted: Bool

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(initialMask: Mask? = nil, onApply: @escaping (Mask) -> Void) {
        self.initialMask = initialMask
        self.onApply = onApply

        let seededKind: MaskShapeKind = {
            switch initialMask?.type {
            case .rectangle: .rectangle
            case .ellipse: .ellipse
            case .brush: .freehand
            default: .rectangle
            }
        }()
        _shapeKind = State(initialValue: seededKind)

        let seededRect = initialMask?.rect ?? CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        _rectNormalized = State(initialValue: seededRect)

        _strokes = State(initialValue: initialMask?.strokes ?? [])
        // Map normalized 0.0-1.0 feather to 0-50 pt UI range.
        _featherPoints = State(initialValue: (initialMask?.feather ?? 0.0) * 50.0)
        _isInverted = State(initialValue: initialMask?.isInverted ?? false)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    LiquidColors.background.ignoresSafeArea()

                    VStack(spacing: LiquidSpacing.md) {
                        shapePicker

                        canvas(in: proxy.size)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        controlsPanel
                        actionBar
                    }
                    .padding(LiquidSpacing.lg)
                }
            }
            .navigationTitle("Mask Editor")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Shape Picker

    private var shapePicker: some View {
        Picker("Mask Shape", selection: $shapeKind) {
            ForEach(MaskShapeKind.allCases) { kind in
                Label(kind.displayName, systemImage: kind.iconName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Canvas

    @ViewBuilder
    private func canvas(in size: CGSize) -> some View {
        let canvasSize = CGSize(
            width: max(size.width, 1),
            height: max(size.height * 0.5, 1)
        )

        ZStack {
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous)
                .fill(LiquidColors.fillTertiary)

            // Checkerboard-style placeholder overlay for the source frame.
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(LiquidColors.textTertiary)

            switch shapeKind {
            case .rectangle:
                rectangleShapeOverlay(canvasSize: canvasSize)
            case .ellipse:
                ellipseShapeOverlay(canvasSize: canvasSize)
            case .freehand:
                freehandOverlay(canvasSize: canvasSize)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous)
                .strokeBorder(LiquidColors.glassBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous))
    }

    // MARK: - Rectangle / Ellipse

    private func rectangleShapeOverlay(canvasSize: CGSize) -> some View {
        ZStack {
            Rectangle()
                .stroke(LiquidColors.accent, lineWidth: 2)
                .frame(
                    width: rectNormalized.width * canvasSize.width,
                    height: rectNormalized.height * canvasSize.height
                )
                .position(
                    x: rectCenter(in: canvasSize).x,
                    y: rectCenter(in: canvasSize).y
                )
                .gesture(dragCenterGesture(in: canvasSize))

            resizeHandles(in: canvasSize)
        }
    }

    private func ellipseShapeOverlay(canvasSize: CGSize) -> some View {
        ZStack {
            Ellipse()
                .stroke(LiquidColors.accent, lineWidth: 2)
                .frame(
                    width: rectNormalized.width * canvasSize.width,
                    height: rectNormalized.height * canvasSize.height
                )
                .position(
                    x: rectCenter(in: canvasSize).x,
                    y: rectCenter(in: canvasSize).y
                )
                .gesture(dragCenterGesture(in: canvasSize))

            resizeHandles(in: canvasSize)
        }
    }

    private func rectCenter(in canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: (rectNormalized.midX) * canvasSize.width,
            y: (rectNormalized.midY) * canvasSize.height
        )
    }

    private func dragCenterGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let normalizedDX = value.translation.width / canvasSize.width
                let normalizedDY = value.translation.height / canvasSize.height

                var newOrigin = rectNormalized.origin
                newOrigin.x += normalizedDX
                newOrigin.y += normalizedDY

                // Clamp so the rect remains within normalized 0..1.
                newOrigin.x = min(max(newOrigin.x, 0), 1 - rectNormalized.width)
                newOrigin.y = min(max(newOrigin.y, 0), 1 - rectNormalized.height)

                rectNormalized = CGRect(
                    origin: newOrigin,
                    size: rectNormalized.size
                )
            }
    }

    @ViewBuilder
    private func resizeHandles(in canvasSize: CGSize) -> some View {
        let handles: [(CGPoint, ResizeCorner)] = [
            (CGPoint(x: rectNormalized.minX, y: rectNormalized.minY), .topLeft),
            (CGPoint(x: rectNormalized.maxX, y: rectNormalized.minY), .topRight),
            (CGPoint(x: rectNormalized.minX, y: rectNormalized.maxY), .bottomLeft),
            (CGPoint(x: rectNormalized.maxX, y: rectNormalized.maxY), .bottomRight)
        ]
        ForEach(handles, id: \.1) { point, corner in
            handleView(corner: corner)
                .position(
                    x: point.x * canvasSize.width,
                    y: point.y * canvasSize.height
                )
                .gesture(resizeGesture(for: corner, in: canvasSize))
        }
    }

    private func handleView(corner: ResizeCorner) -> some View {
        Circle()
            .fill(LiquidColors.accent)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .accessibilityLabel("Resize handle \(corner.accessibilityLabel)")
    }

    private enum ResizeCorner: Hashable {
        case topLeft, topRight, bottomLeft, bottomRight

        var accessibilityLabel: String {
            switch self {
            case .topLeft: "top left"
            case .topRight: "top right"
            case .bottomLeft: "bottom left"
            case .bottomRight: "bottom right"
            }
        }
    }

    private func resizeGesture(for corner: ResizeCorner, in canvasSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let dx = value.translation.width / canvasSize.width
                let dy = value.translation.height / canvasSize.height

                var minX = rectNormalized.minX
                var minY = rectNormalized.minY
                var maxX = rectNormalized.maxX
                var maxY = rectNormalized.maxY

                switch corner {
                case .topLeft:
                    minX += dx
                    minY += dy
                case .topRight:
                    maxX += dx
                    minY += dy
                case .bottomLeft:
                    minX += dx
                    maxY += dy
                case .bottomRight:
                    maxX += dx
                    maxY += dy
                }

                // Clamp to [0, 1] and enforce a minimum size of 5% canvas.
                let minSize: CGFloat = 0.05
                minX = min(max(minX, 0), 1 - minSize)
                minY = min(max(minY, 0), 1 - minSize)
                maxX = min(max(maxX, minX + minSize), 1)
                maxY = min(max(maxY, minY + minSize), 1)

                rectNormalized = CGRect(
                    x: minX,
                    y: minY,
                    width: maxX - minX,
                    height: maxY - minY
                )
            }
    }

    // MARK: - Freehand

    @ViewBuilder
    private func freehandOverlay(canvasSize: CGSize) -> some View {
        Canvas { context, _ in
            for stroke in strokes {
                drawStroke(context: &context, points: stroke.points, canvasSize: canvasSize)
            }
            if !currentStroke.isEmpty {
                drawStroke(context: &context, points: currentStroke, canvasSize: canvasSize)
            }
        }
        .contentShape(Rectangle())
        .gesture(freehandGesture(in: canvasSize))
    }

    private func drawStroke(
        context: inout GraphicsContext,
        points: [CGPoint],
        canvasSize: CGSize
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(
            to: CGPoint(
                x: first.x * canvasSize.width,
                y: first.y * canvasSize.height
            )
        )
        for point in points.dropFirst() {
            path.addLine(
                to: CGPoint(
                    x: point.x * canvasSize.width,
                    y: point.y * canvasSize.height
                )
            )
        }
        context.stroke(
            path,
            with: .color(LiquidColors.accent),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }

    private func freehandGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let normalized = CGPoint(
                    x: min(max(value.location.x / canvasSize.width, 0), 1),
                    y: min(max(value.location.y / canvasSize.height, 0), 1)
                )
                currentStroke.append(normalized)
            }
            .onEnded { _ in
                guard currentStroke.count > 1 else {
                    currentStroke = []
                    return
                }
                strokes.append(BrushStroke(points: currentStroke))
                currentStroke = []
            }
    }

    // MARK: - Controls

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.md) {
            VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
                HStack {
                    Text("Feather")
                        .font(LiquidTypography.subheadlineSemibold)
                        .foregroundStyle(LiquidColors.textPrimary)
                    Spacer()
                    Text("\(Int(featherPoints)) pt")
                        .font(LiquidTypography.monoCaption)
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                Slider(value: $featherPoints, in: 0...50, step: 1)
                    .accessibilityLabel("Feather amount")
            }

            Toggle(isOn: $isInverted) {
                Text("Inverted")
                    .font(LiquidTypography.subheadlineSemibold)
                    .foregroundStyle(LiquidColors.textPrimary)
            }

            if shapeKind == .freehand && !strokes.isEmpty {
                Button(role: .destructive) {
                    strokes.removeAll()
                } label: {
                    Label("Clear Strokes", systemImage: "eraser")
                        .font(LiquidTypography.footnoteSemibold)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(LiquidSpacing.lg)
        .glassEffect(style: .thin, cornerRadius: LiquidSpacing.cornerLarge)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: LiquidSpacing.md) {
            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(LiquidTypography.bodySemibold)
                    .frame(maxWidth: .infinity, minHeight: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.bordered)

            Button {
                if let mask = buildMask() {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onApply(mask)
                    dismiss()
                }
            } label: {
                Text("Apply")
                    .font(LiquidTypography.bodySemibold)
                    .frame(maxWidth: .infinity, minHeight: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canApply)
        }
    }

    // MARK: - Validation & Build

    private var canApply: Bool {
        switch shapeKind {
        case .rectangle, .ellipse:
            return rectNormalized.width > 0 && rectNormalized.height > 0
        case .freehand:
            return !strokes.isEmpty
        }
    }

    /// Construct a ``Mask`` from the current UI state, or nil if invalid.
    private func buildMask() -> Mask? {
        let id = initialMask?.id ?? UUID().uuidString
        let normalizedFeather = min(max(featherPoints / 50.0, 0.0), 1.0)

        switch shapeKind {
        case .rectangle:
            guard rectNormalized.width > 0, rectNormalized.height > 0 else { return nil }
            return Mask(
                id: id,
                type: .rectangle,
                isInverted: isInverted,
                feather: normalizedFeather,
                opacity: initialMask?.opacity ?? 1.0,
                rect: rectNormalized
            )

        case .ellipse:
            guard rectNormalized.width > 0, rectNormalized.height > 0 else { return nil }
            return Mask(
                id: id,
                type: .ellipse,
                isInverted: isInverted,
                feather: normalizedFeather,
                opacity: initialMask?.opacity ?? 1.0,
                rect: rectNormalized
            )

        case .freehand:
            guard !strokes.isEmpty else { return nil }
            return Mask(
                id: id,
                type: .brush,
                isInverted: isInverted,
                feather: normalizedFeather,
                opacity: initialMask?.opacity ?? 1.0,
                strokes: strokes
            )
        }
    }
}
