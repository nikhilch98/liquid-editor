import Foundation
import CoreGraphics

// MARK: - EffectParameterType

/// Type of effect parameter value.
enum EffectParameterType: String, Codable, CaseIterable, Sendable {
    /// Floating-point numeric slider.
    case double_ = "double_"

    /// Integer value.
    case int_ = "int_"

    /// Boolean toggle.
    case bool_ = "bool_"

    /// Color value (stored as ARGB int).
    case color

    /// 2D point (x, y) in normalized coordinates.
    case point

    /// Range value (start, end).
    case range

    /// Dropdown selection from enum values.
    case enumChoice

    /// Whether this parameter type can be interpolated.
    var isInterpolatable: Bool {
        switch self {
        case .double_, .int_, .color, .point, .range:
            return true
        case .bool_, .enumChoice:
            return false
        }
    }
}

// MARK: - ParameterValue

/// Type-safe wrapper for effect parameter values.
///
/// Replaces Dart's `dynamic` with an explicit sum type for
/// compile-time safety and `Codable` support.
///
/// ## Legacy Format Decoding
/// For backward compatibility with older project files, this type supports
/// decoding from untagged JSON values:
/// - Point: `{x, y}` (without type tag)
/// - Range: `{start, end}` (without type tag)
/// - Int/Color disambiguation: Values >= 0xFF000000 are treated as colors
/// - Scalars: Bool, Int, Double, String decoded directly from single values
///
/// Modern format uses tagged encoding: `{"type": "double_", "value": 1.5}`
enum ParameterValue: Codable, Equatable, Hashable, Sendable {

    /// Threshold for distinguishing color ARGBs from regular integers in legacy format.
    /// Values >= this threshold are decoded as colors (alpha channel is typically 0xFF).
    private static let legacyColorThreshold: Int = 0xFF00_0000
    case double_(Double)
    case int_(Int)
    case bool_(Bool)
    case color(Int)
    case point(x: Double, y: Double)
    case range(start: Double, end: Double)
    case enumChoice(String)

    // MARK: - Convenience Accessors

    /// Extract as Double, coercing Int if needed.
    var asDouble: Double? {
        switch self {
        case .double_(let v): return v
        case .int_(let v): return Double(v)
        default: return nil
        }
    }

    /// Extract as Int, coercing Double if needed.
    var asInt: Int? {
        switch self {
        case .int_(let v): return v
        case .double_(let v): return Int(v)
        default: return nil
        }
    }

    /// Extract as Bool.
    var asBool: Bool? {
        if case .bool_(let v) = self { return v }
        return nil
    }

    /// Extract as color ARGB int.
    var asColorInt: Int? {
        if case .color(let v) = self { return v }
        return nil
    }

    /// Extract as point (x, y).
    var asPoint: (x: Double, y: Double)? {
        if case .point(let x, let y) = self { return (x, y) }
        return nil
    }

    /// Extract as range (start, end).
    var asRange: (start: Double, end: Double)? {
        if case .range(let s, let e) = self { return (s, e) }
        return nil
    }

    /// Extract as enum choice string.
    var asEnumChoice: String? {
        if case .enumChoice(let v) = self { return v }
        return nil
    }

    // MARK: - Codable

    /// Coding keys used for tagged encoding to preserve type information.
    private enum CodingKeys: String, CodingKey {
        case type, value, x, y, start, end
    }

    /// Type tag strings for unambiguous Codable roundtrip.
    private enum TypeTag: String, Codable {
        case double_ = "double_"
        case int_ = "int_"
        case bool_ = "bool_"
        case color
        case point
        case range
        case enumChoice
    }

    init(from decoder: Decoder) throws {
        // First, try the new tagged format: { "type": "...", "value": ... }
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let tag = try? container.decode(TypeTag.self, forKey: .type) {
            switch tag {
            case .double_:
                self = .double_(try container.decode(Double.self, forKey: .value))
                return
            case .int_:
                self = .int_(try container.decode(Int.self, forKey: .value))
                return
            case .bool_:
                self = .bool_(try container.decode(Bool.self, forKey: .value))
                return
            case .color:
                self = .color(try container.decode(Int.self, forKey: .value))
                return
            case .point:
                let x = try container.decode(Double.self, forKey: .x)
                let y = try container.decode(Double.self, forKey: .y)
                self = .point(x: x, y: y)
                return
            case .range:
                let start = try container.decode(Double.self, forKey: .start)
                let end = try container.decode(Double.self, forKey: .end)
                self = .range(start: start, end: end)
                return
            case .enumChoice:
                self = .enumChoice(try container.decode(String.self, forKey: .value))
                return
            }
        }

        // Fallback: legacy untagged format for backward compatibility
        // Try keyed container for point {x, y} or range {start, end} (without type tag)
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if container.contains(.x), container.contains(.y), !container.contains(.type) {
                let x = try container.decode(Double.self, forKey: .x)
                let y = try container.decode(Double.self, forKey: .y)
                self = .point(x: x, y: y)
                return
            }
            if container.contains(.start), container.contains(.end), !container.contains(.type) {
                let start = try container.decode(Double.self, forKey: .start)
                let end = try container.decode(Double.self, forKey: .end)
                self = .range(start: start, end: end)
                return
            }
        }

        // Try single value (legacy untagged scalars)
        if let singleContainer = try? decoder.singleValueContainer() {
            if let boolVal = try? singleContainer.decode(Bool.self) {
                self = .bool_(boolVal)
                return
            }
            if let intVal = try? singleContainer.decode(Int.self) {
                // Legacy format: disambiguate color vs int by alpha channel presence
                if intVal >= Self.legacyColorThreshold {
                    self = .color(intVal)
                } else {
                    self = .int_(intVal)
                }
                return
            }
            if let doubleVal = try? singleContainer.decode(Double.self) {
                self = .double_(doubleVal)
                return
            }
            if let stringVal = try? singleContainer.decode(String.self) {
                self = .enumChoice(stringVal)
                return
            }
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath,
                                  debugDescription: "Cannot decode ParameterValue")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .double_(let v):
            try container.encode(TypeTag.double_, forKey: .type)
            try container.encode(v, forKey: .value)
        case .int_(let v):
            try container.encode(TypeTag.int_, forKey: .type)
            try container.encode(v, forKey: .value)
        case .bool_(let v):
            try container.encode(TypeTag.bool_, forKey: .type)
            try container.encode(v, forKey: .value)
        case .color(let v):
            try container.encode(TypeTag.color, forKey: .type)
            try container.encode(v, forKey: .value)
        case .point(let x, let y):
            try container.encode(TypeTag.point, forKey: .type)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case .range(let start, let end):
            try container.encode(TypeTag.range, forKey: .type)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case .enumChoice(let v):
            try container.encode(TypeTag.enumChoice, forKey: .type)
            try container.encode(v, forKey: .value)
        }
    }
}

// MARK: - EffectParameter

/// A single effect parameter with type, range, and current value.
///
/// Parameters are immutable value objects used by `VideoEffect`.
/// They define the schema for a single configurable value.
struct EffectParameter: Codable, Equatable, Hashable, Sendable {
    /// Internal key name (e.g., "radius", "intensity").
    let name: String

    /// Human-readable display name (e.g., "Blur Radius").
    let displayName: String

    /// Parameter value type.
    let type: EffectParameterType

    /// Default value for this parameter.
    let defaultValue: ParameterValue

    /// Current value of this parameter.
    let currentValue: ParameterValue

    /// Minimum value (nil for non-numeric types).
    let minValue: ParameterValue?

    /// Maximum value (nil for non-numeric types).
    let maxValue: ParameterValue?

    /// Step increment for slider controls (nil = continuous).
    let step: Double?

    /// Display unit label (e.g., "px", "%", "deg").
    let unit: String?

    /// Whether this parameter can be animated via keyframes.
    let isKeyframeable: Bool

    /// Available choices for `EffectParameterType.enumChoice`.
    let enumValues: [String]?

    /// Logical group name for UI grouping.
    let group: String?

    init(
        name: String,
        displayName: String,
        type: EffectParameterType,
        defaultValue: ParameterValue,
        currentValue: ParameterValue,
        minValue: ParameterValue? = nil,
        maxValue: ParameterValue? = nil,
        step: Double? = nil,
        unit: String? = nil,
        isKeyframeable: Bool = true,
        enumValues: [String]? = nil,
        group: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.type = type
        self.defaultValue = defaultValue
        self.currentValue = currentValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.unit = unit
        self.isKeyframeable = isKeyframeable
        self.enumValues = enumValues
        self.group = group
    }

    /// Create a parameter with the default value as current value.
    static func withDefault(
        name: String,
        displayName: String,
        type: EffectParameterType,
        defaultValue: ParameterValue,
        minValue: ParameterValue? = nil,
        maxValue: ParameterValue? = nil,
        step: Double? = nil,
        unit: String? = nil,
        isKeyframeable: Bool = true,
        enumValues: [String]? = nil,
        group: String? = nil
    ) -> EffectParameter {
        EffectParameter(
            name: name,
            displayName: displayName,
            type: type,
            defaultValue: defaultValue,
            currentValue: defaultValue,
            minValue: minValue,
            maxValue: maxValue,
            step: step,
            unit: unit,
            isKeyframeable: isKeyframeable,
            enumValues: enumValues,
            group: group
        )
    }

    /// Whether the current value equals the default value.
    var isDefault: Bool { currentValue == defaultValue }

    /// Validate that a value is within the parameter's range.
    func isValidValue(_ value: ParameterValue) -> Bool {
        switch type {
        case .double_:
            guard let v = value.asDouble else { return false }
            if let min = minValue?.asDouble, v < min { return false }
            if let max = maxValue?.asDouble, v > max { return false }
            return true

        case .int_:
            guard let v = value.asInt else { return false }
            if let min = minValue?.asInt, v < min { return false }
            if let max = maxValue?.asInt, v > max { return false }
            return true

        case .bool_:
            return value.asBool != nil

        case .color:
            return value.asColorInt != nil

        case .point:
            return value.asPoint != nil

        case .range:
            return value.asRange != nil

        case .enumChoice:
            guard let s = value.asEnumChoice else { return false }
            if let choices = enumValues {
                return choices.contains(s)
            }
            return true
        }
    }

    /// Clamp a value to the parameter's range.
    func clampValue(_ value: ParameterValue) -> ParameterValue {
        switch type {
        case .double_:
            guard var v = value.asDouble else { return value }
            if let min = minValue?.asDouble { v = Swift.max(v, min) }
            if let max = maxValue?.asDouble { v = Swift.min(v, max) }
            return .double_(v)

        case .int_:
            guard var v = value.asInt else { return value }
            if let min = minValue?.asInt { v = Swift.max(v, min) }
            if let max = maxValue?.asInt { v = Swift.min(v, max) }
            return .int_(v)

        default:
            return value
        }
    }

    /// Create a copy with updated fields.
    func with(
        name: String? = nil,
        displayName: String? = nil,
        type: EffectParameterType? = nil,
        defaultValue: ParameterValue? = nil,
        currentValue: ParameterValue? = nil,
        minValue: ParameterValue?? = nil,
        maxValue: ParameterValue?? = nil,
        step: Double?? = nil,
        unit: String?? = nil,
        isKeyframeable: Bool? = nil,
        enumValues: [String]?? = nil,
        group: String?? = nil
    ) -> EffectParameter {
        EffectParameter(
            name: name ?? self.name,
            displayName: displayName ?? self.displayName,
            type: type ?? self.type,
            defaultValue: defaultValue ?? self.defaultValue,
            currentValue: currentValue ?? self.currentValue,
            minValue: minValue ?? self.minValue,
            maxValue: maxValue ?? self.maxValue,
            step: step ?? self.step,
            unit: unit ?? self.unit,
            isKeyframeable: isKeyframeable ?? self.isKeyframeable,
            enumValues: enumValues ?? self.enumValues,
            group: group ?? self.group
        )
    }

    /// Reset to default value.
    func reset() -> EffectParameter {
        with(currentValue: defaultValue)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case name, displayName, type, defaultValue, currentValue
        case minValue, maxValue, step, unit, isKeyframeable
        case enumValues, group
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: EffectParameter, rhs: EffectParameter) -> Bool {
        lhs.name == rhs.name &&
        lhs.type == rhs.type &&
        lhs.currentValue == rhs.currentValue &&
        lhs.defaultValue == rhs.defaultValue &&
        lhs.minValue == rhs.minValue &&
        lhs.maxValue == rhs.maxValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
        hasher.combine(currentValue)
        hasher.combine(defaultValue)
        hasher.combine(minValue)
        hasher.combine(maxValue)
    }
}

// MARK: - EffectParameterGroup

/// A logical grouping of parameters for UI layout.
struct EffectParameterGroup: Codable, Equatable, Hashable, Sendable {
    /// Group name.
    let name: String

    /// Display label.
    let displayName: String

    /// Parameter keys in this group.
    let parameterNames: [String]

    /// Whether the group is collapsed by default.
    let isCollapsedByDefault: Bool

    init(
        name: String,
        displayName: String,
        parameterNames: [String],
        isCollapsedByDefault: Bool = false
    ) {
        self.name = name
        self.displayName = displayName
        self.parameterNames = parameterNames
        self.isCollapsedByDefault = isCollapsedByDefault
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case name, displayName, parameterNames, isCollapsedByDefault
    }
}
