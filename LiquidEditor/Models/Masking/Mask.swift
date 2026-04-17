import Foundation
import CoreGraphics

// MARK: - MaskType

/// Type of mask.
enum MaskType: String, Codable, CaseIterable, Sendable {
    /// Rectangle with optional corner radius.
    case rectangle
    /// Ellipse defined by center and radii.
    case ellipse
    /// Arbitrary polygon with N vertices.
    case polygon
    /// Freehand painted brush strokes.
    case brush
    /// Mask based on luminance (brightness) range.
    case luminance
    /// Mask based on color range (hue/saturation).
    case color
}

// MARK: - MaskBlurMode

/// Blur mode for mask edges.
enum MaskBlurMode: String, Codable, CaseIterable, Sendable {
    case gaussian
    case box
    case motion
}

// MARK: - BrushStroke

/// A single brush stroke for freeform masks.
struct BrushStroke: Codable, Equatable, Hashable, Sendable {
    /// Path points in normalized coordinates (0.0-1.0).
    let points: [CGPoint]

    /// Stroke width in normalized coordinates.
    let width: Double

    /// Edge softness per stroke (0.0 = hard, 1.0 = soft).
    let softness: Double

    init(
        points: [CGPoint],
        width: Double = 0.05,
        softness: Double = 0.3
    ) {
        self.points = points
        self.width = width
        self.softness = softness
    }

    /// Create a copy with optional overrides.
    func with(
        points: [CGPoint]? = nil,
        width: Double? = nil,
        softness: Double? = nil
    ) -> BrushStroke {
        BrushStroke(
            points: points ?? self.points,
            width: width ?? self.width,
            softness: softness ?? self.softness
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case points, width, softness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPoints = try container.decode([CodablePoint].self, forKey: .points)
        self.points = rawPoints.map { CGPoint(x: $0.x, y: $0.y) }
        self.width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0.05
        self.softness = try container.decodeIfPresent(Double.self, forKey: .softness) ?? 0.3
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let codablePoints = points.map { CodablePoint(x: $0.x, y: $0.y) }
        try container.encode(codablePoints, forKey: .points)
        try container.encode(width, forKey: .width)
        try container.encode(softness, forKey: .softness)
    }
}

// MARK: - MaskParameters

/// Animatable mask parameters.
struct MaskParameters: Codable, Equatable, Hashable, Sendable {
    /// Feather amount (0.0 = hard edge, 1.0 = maximum blur).
    let feather: Double

    /// Mask opacity (0.0 = transparent, 1.0 = fully opaque).
    let opacity: Double

    /// Mask boundary expansion (negative = shrink).
    let expansion: Double

    /// Shape-specific: rectangle/ellipse rect in normalized coords.
    let rect: CGRect?

    /// Shape-specific: corner radius for rectangles.
    let cornerRadius: Double?

    /// Shape-specific: rotation angle in radians.
    let rotation: Double?

    /// Shape-specific: polygon vertices.
    let vertices: [CGPoint]?

    init(
        feather: Double = 0.0,
        opacity: Double = 1.0,
        expansion: Double = 0.0,
        rect: CGRect? = nil,
        cornerRadius: Double? = nil,
        rotation: Double? = nil,
        vertices: [CGPoint]? = nil
    ) {
        self.feather = feather
        self.opacity = opacity
        self.expansion = expansion
        self.rect = rect
        self.cornerRadius = cornerRadius
        self.rotation = rotation
        self.vertices = vertices
    }

    /// Interpolate between two parameter sets.
    static func lerp(_ a: MaskParameters, _ b: MaskParameters, t: Double) -> MaskParameters {
        var lerpedRect: CGRect?
        if let ar = a.rect, let br = b.rect {
            lerpedRect = CGRect(
                x: ar.origin.x + (br.origin.x - ar.origin.x) * t,
                y: ar.origin.y + (br.origin.y - ar.origin.y) * t,
                width: ar.size.width + (br.size.width - ar.size.width) * t,
                height: ar.size.height + (br.size.height - ar.size.height) * t
            )
        } else {
            lerpedRect = b.rect ?? a.rect
        }

        var lerpedCornerRadius: Double?
        if let ac = a.cornerRadius, let bc = b.cornerRadius {
            lerpedCornerRadius = ac + (bc - ac) * t
        } else {
            lerpedCornerRadius = b.cornerRadius ?? a.cornerRadius
        }

        var lerpedRotation: Double?
        if let ar = a.rotation, let br = b.rotation {
            lerpedRotation = ar + (br - ar) * t
        } else {
            lerpedRotation = b.rotation ?? a.rotation
        }

        var lerpedVertices: [CGPoint]?
        if let av = a.vertices, let bv = b.vertices, av.count == bv.count {
            lerpedVertices = zip(av, bv).map { va, vb in
                CGPoint(
                    x: va.x + (vb.x - va.x) * t,
                    y: va.y + (vb.y - va.y) * t
                )
            }
        } else {
            lerpedVertices = b.vertices ?? a.vertices
        }

        return MaskParameters(
            feather: a.feather + (b.feather - a.feather) * t,
            opacity: a.opacity + (b.opacity - a.opacity) * t,
            expansion: a.expansion + (b.expansion - a.expansion) * t,
            rect: lerpedRect,
            cornerRadius: lerpedCornerRadius,
            rotation: lerpedRotation,
            vertices: lerpedVertices
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case feather, opacity, expansion, rect, cornerRadius, rotation, vertices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feather = try container.decodeIfPresent(Double.self, forKey: .feather) ?? 0.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        expansion = try container.decodeIfPresent(Double.self, forKey: .expansion) ?? 0.0

        if let rectDict = try container.decodeIfPresent(CodableRect.self, forKey: .rect) {
            rect = CGRect(
                x: rectDict.left,
                y: rectDict.top,
                width: rectDict.right - rectDict.left,
                height: rectDict.bottom - rectDict.top
            )
        } else {
            rect = nil
        }

        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation)

        if let rawVertices = try container.decodeIfPresent([CodablePoint].self, forKey: .vertices) {
            vertices = rawVertices.map { CGPoint(x: $0.x, y: $0.y) }
        } else {
            vertices = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(feather, forKey: .feather)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(expansion, forKey: .expansion)

        if let r = rect {
            let codableRect = CodableRect(
                left: r.origin.x,
                top: r.origin.y,
                right: r.origin.x + r.size.width,
                bottom: r.origin.y + r.size.height
            )
            try container.encode(codableRect, forKey: .rect)
        }

        try container.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
        try container.encodeIfPresent(rotation, forKey: .rotation)

        if let verts = vertices {
            let codableVerts = verts.map { CodablePoint(x: $0.x, y: $0.y) }
            try container.encode(codableVerts, forKey: .vertices)
        }
    }
}

// MARK: - MaskKeyframe

/// Keyframe for animated mask parameters.
struct MaskKeyframe: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Time position (microseconds from clip start).
    let timeMicros: TimeMicros

    /// Mask parameters at this keyframe.
    let parameters: MaskParameters

    /// Interpolation type to the next keyframe.
    let interpolation: InterpolationType

    init(
        id: String,
        timeMicros: TimeMicros,
        parameters: MaskParameters,
        interpolation: InterpolationType = .easeInOut
    ) {
        self.id = id
        self.timeMicros = timeMicros
        self.parameters = parameters
        self.interpolation = interpolation
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: MaskKeyframe, rhs: MaskKeyframe) -> Bool {
        lhs.id == rhs.id && lhs.timeMicros == rhs.timeMicros
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timeMicros)
    }
}

// MARK: - Mask

/// Base mask model.
///
/// All mask types share common properties: id, type, inversion,
/// feather, and opacity. Type-specific data is stored via MaskShape.
struct Mask: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Type of mask.
    let type: MaskType

    /// Whether the mask is inverted (effect applied outside mask).
    let isInverted: Bool

    /// Edge softness (0.0 = hard edge, 1.0 = maximum blur).
    let feather: Double

    /// Mask strength (0.0 = transparent, 1.0 = fully opaque).
    let opacity: Double

    /// Boundary expansion (negative = shrink).
    let expansion: Double

    /// Keyframes for animated mask parameters.
    let keyframes: [MaskKeyframe]

    // Shape-specific fields
    /// Shape region in normalized coordinates (for rect/ellipse).
    let rect: CGRect?

    /// Corner radius for rectangle masks (normalized).
    let cornerRadius: Double?

    /// Rotation angle in radians.
    let rotation: Double?

    /// Polygon vertices (for polygon type only).
    let vertices: [CGPoint]?

    /// Brush strokes (for brush type only).
    let strokes: [BrushStroke]?

    /// Luminance min (for luminance type only).
    let luminanceMin: Double?

    /// Luminance max (for luminance type only).
    let luminanceMax: Double?

    /// Target hue (for color type only, 0.0 to 360.0).
    let targetHue: Double?

    /// Hue tolerance (for color type only).
    let hueTolerance: Double?

    /// Saturation min (for color type only).
    let saturationMin: Double?

    /// Saturation max (for color type only).
    let saturationMax: Double?

    init(
        id: String,
        type: MaskType,
        isInverted: Bool = false,
        feather: Double = 0.0,
        opacity: Double = 1.0,
        expansion: Double = 0.0,
        keyframes: [MaskKeyframe] = [],
        rect: CGRect? = nil,
        cornerRadius: Double? = nil,
        rotation: Double? = nil,
        vertices: [CGPoint]? = nil,
        strokes: [BrushStroke]? = nil,
        luminanceMin: Double? = nil,
        luminanceMax: Double? = nil,
        targetHue: Double? = nil,
        hueTolerance: Double? = nil,
        saturationMin: Double? = nil,
        saturationMax: Double? = nil
    ) {
        precondition(!id.isEmpty, "Mask id must not be empty")
        precondition(feather >= 0.0, "Mask feather must be non-negative, got \(feather)")
        precondition(opacity >= 0.0 && opacity <= 1.0, "Mask opacity must be in 0...1, got \(opacity)")

        // Validate type-specific required fields.
        switch type {
        case .rectangle, .ellipse:
            precondition(rect != nil, "Mask type \(type) requires a non-nil rect")
        case .polygon:
            precondition(vertices != nil && (vertices?.count ?? 0) >= 3,
                         "Polygon mask requires at least 3 vertices")
        case .brush:
            precondition(strokes != nil && !(strokes?.isEmpty ?? true),
                         "Brush mask requires at least one stroke")
        case .luminance:
            precondition(luminanceMin != nil && luminanceMax != nil,
                         "Luminance mask requires luminanceMin and luminanceMax")
        case .color:
            precondition(targetHue != nil && hueTolerance != nil,
                         "Color mask requires targetHue and hueTolerance")
        }

        self.id = id
        self.type = type
        self.isInverted = isInverted
        self.feather = feather
        self.opacity = opacity
        self.expansion = expansion
        self.keyframes = keyframes
        self.rect = rect
        self.cornerRadius = cornerRadius
        self.rotation = rotation
        self.vertices = vertices
        self.strokes = strokes
        self.luminanceMin = luminanceMin
        self.luminanceMax = luminanceMax
        self.targetHue = targetHue
        self.hueTolerance = hueTolerance
        self.saturationMin = saturationMin
        self.saturationMax = saturationMax
    }

    /// Whether this mask has animation keyframes.
    var isAnimated: Bool { !keyframes.isEmpty }

    /// Luminance range for luminance masks.
    var luminanceRange: Double? {
        guard let lMin = luminanceMin, let lMax = luminanceMax else { return nil }
        return lMax - lMin
    }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        type: MaskType? = nil,
        isInverted: Bool? = nil,
        feather: Double? = nil,
        opacity: Double? = nil,
        expansion: Double? = nil,
        keyframes: [MaskKeyframe]? = nil,
        rect: CGRect?? = nil,
        cornerRadius: Double?? = nil,
        rotation: Double?? = nil,
        vertices: [CGPoint]?? = nil,
        strokes: [BrushStroke]?? = nil,
        luminanceMin: Double?? = nil,
        luminanceMax: Double?? = nil,
        targetHue: Double?? = nil,
        hueTolerance: Double?? = nil,
        saturationMin: Double?? = nil,
        saturationMax: Double?? = nil
    ) -> Mask {
        Mask(
            id: id ?? self.id,
            type: type ?? self.type,
            isInverted: isInverted ?? self.isInverted,
            feather: feather ?? self.feather,
            opacity: opacity ?? self.opacity,
            expansion: expansion ?? self.expansion,
            keyframes: keyframes ?? self.keyframes,
            rect: rect ?? self.rect,
            cornerRadius: cornerRadius ?? self.cornerRadius,
            rotation: rotation ?? self.rotation,
            vertices: vertices ?? self.vertices,
            strokes: strokes ?? self.strokes,
            luminanceMin: luminanceMin ?? self.luminanceMin,
            luminanceMax: luminanceMax ?? self.luminanceMax,
            targetHue: targetHue ?? self.targetHue,
            hueTolerance: hueTolerance ?? self.hueTolerance,
            saturationMin: saturationMin ?? self.saturationMin,
            saturationMax: saturationMax ?? self.saturationMax
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, isInverted, feather, opacity, expansion, keyframes
        case rect, cornerRadius, rotation, vertices, strokes
        case luminanceMin, luminanceMax
        case targetHue, hueTolerance, saturationMin, saturationMax
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        let typeStr = try container.decode(String.self, forKey: .type)
        type = MaskType(rawValue: typeStr) ?? .rectangle

        isInverted = try container.decodeIfPresent(Bool.self, forKey: .isInverted) ?? false
        feather = try container.decodeIfPresent(Double.self, forKey: .feather) ?? 0.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        expansion = try container.decodeIfPresent(Double.self, forKey: .expansion) ?? 0.0
        keyframes = try container.decodeIfPresent([MaskKeyframe].self, forKey: .keyframes) ?? []

        if let rectDict = try container.decodeIfPresent(CodableRect.self, forKey: .rect) {
            rect = CGRect(
                x: rectDict.left,
                y: rectDict.top,
                width: rectDict.right - rectDict.left,
                height: rectDict.bottom - rectDict.top
            )
        } else {
            rect = nil
        }

        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation)

        if let rawVerts = try container.decodeIfPresent([CodablePoint].self, forKey: .vertices) {
            vertices = rawVerts.map { CGPoint(x: $0.x, y: $0.y) }
        } else {
            vertices = nil
        }

        strokes = try container.decodeIfPresent([BrushStroke].self, forKey: .strokes)
        luminanceMin = try container.decodeIfPresent(Double.self, forKey: .luminanceMin)
        luminanceMax = try container.decodeIfPresent(Double.self, forKey: .luminanceMax)
        targetHue = try container.decodeIfPresent(Double.self, forKey: .targetHue)
        hueTolerance = try container.decodeIfPresent(Double.self, forKey: .hueTolerance)
        saturationMin = try container.decodeIfPresent(Double.self, forKey: .saturationMin)
        saturationMax = try container.decodeIfPresent(Double.self, forKey: .saturationMax)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(isInverted, forKey: .isInverted)
        try container.encode(feather, forKey: .feather)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(expansion, forKey: .expansion)
        try container.encode(keyframes, forKey: .keyframes)

        if let r = rect {
            let codableRect = CodableRect(
                left: r.origin.x,
                top: r.origin.y,
                right: r.origin.x + r.size.width,
                bottom: r.origin.y + r.size.height
            )
            try container.encode(codableRect, forKey: .rect)
        }

        try container.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
        try container.encodeIfPresent(rotation, forKey: .rotation)

        if let verts = vertices {
            let codableVerts = verts.map { CodablePoint(x: $0.x, y: $0.y) }
            try container.encode(codableVerts, forKey: .vertices)
        }

        try container.encodeIfPresent(strokes, forKey: .strokes)
        try container.encodeIfPresent(luminanceMin, forKey: .luminanceMin)
        try container.encodeIfPresent(luminanceMax, forKey: .luminanceMax)
        try container.encodeIfPresent(targetHue, forKey: .targetHue)
        try container.encodeIfPresent(hueTolerance, forKey: .hueTolerance)
        try container.encodeIfPresent(saturationMin, forKey: .saturationMin)
        try container.encodeIfPresent(saturationMax, forKey: .saturationMax)
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: Mask, rhs: Mask) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CodableRect (Shared helper)

/// Internal helper for encoding/decoding CGRect as {left, top, right, bottom} JSON.
struct CodableRect: Codable, Equatable, Hashable, Sendable {
    let left: Double
    let top: Double
    let right: Double
    let bottom: Double
}
