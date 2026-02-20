import Testing
import Foundation
@testable import LiquidEditor

@Suite("ParameterValue Tests")
struct ParameterValueTests {

    // MARK: - Value Types

    @Test("Double value creation and extraction")
    func doubleValue() {
        let value = ParameterValue.double_(3.14)
        #expect(value.asDouble == 3.14)
        #expect(value.asInt == 3) // Coerced
        #expect(value.asBool == nil)
        #expect(value.asColorInt == nil)
        #expect(value.asPoint == nil)
        #expect(value.asRange == nil)
        #expect(value.asEnumChoice == nil)
    }

    @Test("Int value creation and extraction")
    func intValue() {
        let value = ParameterValue.int_(42)
        #expect(value.asInt == 42)
        #expect(value.asDouble == 42.0) // Coerced
        #expect(value.asBool == nil)
        #expect(value.asColorInt == nil)
    }

    @Test("Bool value creation and extraction")
    func boolValue() {
        let trueVal = ParameterValue.bool_(true)
        #expect(trueVal.asBool == true)
        #expect(trueVal.asDouble == nil)
        #expect(trueVal.asInt == nil)

        let falseVal = ParameterValue.bool_(false)
        #expect(falseVal.asBool == false)
    }

    @Test("Color value creation and extraction")
    func colorValue() {
        let value = ParameterValue.color(0xFFFF0000) // Red
        #expect(value.asColorInt == 0xFFFF0000)
        #expect(value.asDouble == nil)
        #expect(value.asBool == nil)
    }

    @Test("Point value creation and extraction")
    func pointValue() {
        let value = ParameterValue.point(x: 0.5, y: 0.75)
        let point = value.asPoint
        #expect(point != nil)
        #expect(point?.x == 0.5)
        #expect(point?.y == 0.75)
        #expect(value.asDouble == nil)
    }

    @Test("Range value creation and extraction")
    func rangeValue() {
        let value = ParameterValue.range(start: 0.2, end: 0.8)
        let range = value.asRange
        #expect(range != nil)
        #expect(range?.start == 0.2)
        #expect(range?.end == 0.8)
        #expect(value.asDouble == nil)
    }

    @Test("EnumChoice value creation and extraction")
    func enumChoiceValue() {
        let value = ParameterValue.enumChoice("overdrive")
        #expect(value.asEnumChoice == "overdrive")
        #expect(value.asDouble == nil)
        #expect(value.asBool == nil)
    }

    // MARK: - Equatable

    @Test("Same double values are equal")
    func doubleEquality() {
        #expect(ParameterValue.double_(1.0) == ParameterValue.double_(1.0))
    }

    @Test("Different double values are not equal")
    func doubleInequality() {
        #expect(ParameterValue.double_(1.0) != ParameterValue.double_(2.0))
    }

    @Test("Different types are not equal")
    func crossTypeInequality() {
        #expect(ParameterValue.double_(1.0) != ParameterValue.int_(1))
    }

    @Test("Point values with same coordinates are equal")
    func pointEquality() {
        #expect(ParameterValue.point(x: 0.5, y: 0.5) == ParameterValue.point(x: 0.5, y: 0.5))
    }

    @Test("Range values with same bounds are equal")
    func rangeEquality() {
        #expect(ParameterValue.range(start: 0.1, end: 0.9) == ParameterValue.range(start: 0.1, end: 0.9))
    }

    // MARK: - Codable Roundtrip

    @Test("Double Codable roundtrip")
    func doubleCodable() throws {
        let original = ParameterValue.double_(2.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParameterValue.self, from: data)
        #expect(decoded.asDouble == 2.5)
    }

    @Test("Bool Codable roundtrip")
    func boolCodable() throws {
        let original = ParameterValue.bool_(true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParameterValue.self, from: data)
        #expect(decoded.asBool == true)
    }

    @Test("EnumChoice Codable roundtrip")
    func enumChoiceCodable() throws {
        let original = ParameterValue.enumChoice("linear")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParameterValue.self, from: data)
        #expect(decoded.asEnumChoice == "linear")
    }

    @Test("Point Codable roundtrip")
    func pointCodable() throws {
        let original = ParameterValue.point(x: 0.3, y: 0.7)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParameterValue.self, from: data)
        let point = decoded.asPoint
        #expect(point?.x == 0.3)
        #expect(point?.y == 0.7)
    }

    @Test("Range Codable roundtrip")
    func rangeCodable() throws {
        let original = ParameterValue.range(start: 0.1, end: 0.9)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParameterValue.self, from: data)
        let range = decoded.asRange
        #expect(range?.start == 0.1)
        #expect(range?.end == 0.9)
    }

    @Test("Int Codable roundtrip")
    func intCodable() throws {
        let original = ParameterValue.int_(42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParameterValue.self, from: data)
        #expect(decoded.asInt == 42)
    }

    @Test("Color Codable roundtrip")
    func colorCodable() throws {
        let original = ParameterValue.color(0xFFFF0000)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParameterValue.self, from: data)
        #expect(decoded.asColorInt == 0xFFFF0000)
    }
}

// MARK: - EffectParameter Tests

@Suite("EffectParameter Tests")
struct EffectParameterTests {

    // MARK: - Creation

    @Test("EffectParameter creation with all fields")
    func creation() {
        let param = EffectParameter(
            name: "radius",
            displayName: "Blur Radius",
            type: .double_,
            defaultValue: .double_(10.0),
            currentValue: .double_(15.0),
            minValue: .double_(0.0),
            maxValue: .double_(100.0),
            step: 0.5,
            unit: "px",
            isKeyframeable: true
        )
        #expect(param.name == "radius")
        #expect(param.displayName == "Blur Radius")
        #expect(param.type == .double_)
        #expect(param.defaultValue == .double_(10.0))
        #expect(param.currentValue == .double_(15.0))
        #expect(param.minValue == .double_(0.0))
        #expect(param.maxValue == .double_(100.0))
        #expect(param.step == 0.5)
        #expect(param.unit == "px")
        #expect(param.isKeyframeable == true)
    }

    @Test("withDefault sets currentValue to defaultValue")
    func withDefault() {
        let param = EffectParameter.withDefault(
            name: "intensity",
            displayName: "Intensity",
            type: .double_,
            defaultValue: .double_(0.5)
        )
        #expect(param.currentValue == param.defaultValue)
        #expect(param.isDefault == true)
    }

    @Test("isDefault returns false when current differs from default")
    func isDefaultFalse() {
        let param = EffectParameter(
            name: "radius",
            displayName: "Radius",
            type: .double_,
            defaultValue: .double_(10.0),
            currentValue: .double_(20.0)
        )
        #expect(param.isDefault == false)
    }

    // MARK: - Validation

    @Test("isValidValue returns true for value within range")
    func validValueInRange() {
        let param = EffectParameter.withDefault(
            name: "radius",
            displayName: "Radius",
            type: .double_,
            defaultValue: .double_(10.0),
            minValue: .double_(0.0),
            maxValue: .double_(100.0)
        )
        #expect(param.isValidValue(.double_(50.0)) == true)
    }

    @Test("isValidValue returns false for value below min")
    func invalidValueBelowMin() {
        let param = EffectParameter.withDefault(
            name: "radius",
            displayName: "Radius",
            type: .double_,
            defaultValue: .double_(10.0),
            minValue: .double_(0.0),
            maxValue: .double_(100.0)
        )
        #expect(param.isValidValue(.double_(-5.0)) == false)
    }

    @Test("isValidValue returns false for value above max")
    func invalidValueAboveMax() {
        let param = EffectParameter.withDefault(
            name: "radius",
            displayName: "Radius",
            type: .double_,
            defaultValue: .double_(10.0),
            minValue: .double_(0.0),
            maxValue: .double_(100.0)
        )
        #expect(param.isValidValue(.double_(150.0)) == false)
    }

    @Test("isValidValue for bool accepts bool values")
    func validBool() {
        let param = EffectParameter.withDefault(
            name: "flip",
            displayName: "Flip",
            type: .bool_,
            defaultValue: .bool_(false)
        )
        #expect(param.isValidValue(.bool_(true)) == true)
        #expect(param.isValidValue(.double_(1.0)) == false)
    }

    @Test("isValidValue for int validates range")
    func validInt() {
        let param = EffectParameter.withDefault(
            name: "levels",
            displayName: "Levels",
            type: .int_,
            defaultValue: .int_(6),
            minValue: .int_(2),
            maxValue: .int_(30)
        )
        #expect(param.isValidValue(.int_(10)) == true)
        #expect(param.isValidValue(.int_(1)) == false)
        #expect(param.isValidValue(.int_(31)) == false)
    }

    @Test("isValidValue for enumChoice validates against choices")
    func validEnumChoice() {
        let param = EffectParameter.withDefault(
            name: "mode",
            displayName: "Mode",
            type: .enumChoice,
            defaultValue: .enumChoice("normal"),
            enumValues: ["normal", "vivid", "muted"]
        )
        #expect(param.isValidValue(.enumChoice("vivid")) == true)
        #expect(param.isValidValue(.enumChoice("unknown")) == false)
    }

    @Test("isValidValue for enumChoice without choices accepts any")
    func validEnumChoiceNoRestrictions() {
        let param = EffectParameter.withDefault(
            name: "mode",
            displayName: "Mode",
            type: .enumChoice,
            defaultValue: .enumChoice("normal")
        )
        #expect(param.isValidValue(.enumChoice("anything")) == true)
    }

    @Test("isValidValue for color accepts color int")
    func validColor() {
        let param = EffectParameter.withDefault(
            name: "tint",
            displayName: "Tint",
            type: .color,
            defaultValue: .color(0xFFFF0000)
        )
        #expect(param.isValidValue(.color(0xFF00FF00)) == true)
        #expect(param.isValidValue(.double_(1.0)) == false)
    }

    @Test("isValidValue for point accepts point")
    func validPoint() {
        let param = EffectParameter.withDefault(
            name: "center",
            displayName: "Center",
            type: .point,
            defaultValue: .point(x: 0.5, y: 0.5)
        )
        #expect(param.isValidValue(.point(x: 0.3, y: 0.7)) == true)
        #expect(param.isValidValue(.double_(1.0)) == false)
    }

    @Test("isValidValue for range accepts range")
    func validRange() {
        let param = EffectParameter.withDefault(
            name: "freq",
            displayName: "Frequency Range",
            type: .range,
            defaultValue: .range(start: 0.0, end: 1.0)
        )
        #expect(param.isValidValue(.range(start: 0.2, end: 0.8)) == true)
        #expect(param.isValidValue(.double_(1.0)) == false)
    }

    // MARK: - Clamping

    @Test("clampValue clamps double to range")
    func clampDouble() {
        let param = EffectParameter.withDefault(
            name: "radius",
            displayName: "Radius",
            type: .double_,
            defaultValue: .double_(10.0),
            minValue: .double_(0.0),
            maxValue: .double_(100.0)
        )
        #expect(param.clampValue(.double_(150.0)) == .double_(100.0))
        #expect(param.clampValue(.double_(-5.0)) == .double_(0.0))
        #expect(param.clampValue(.double_(50.0)) == .double_(50.0))
    }

    @Test("clampValue clamps int to range")
    func clampInt() {
        let param = EffectParameter.withDefault(
            name: "levels",
            displayName: "Levels",
            type: .int_,
            defaultValue: .int_(6),
            minValue: .int_(2),
            maxValue: .int_(30)
        )
        #expect(param.clampValue(.int_(50)) == .int_(30))
        #expect(param.clampValue(.int_(1)) == .int_(2))
        #expect(param.clampValue(.int_(15)) == .int_(15))
    }

    @Test("clampValue passes through non-numeric types unchanged")
    func clampPassthrough() {
        let param = EffectParameter.withDefault(
            name: "flip",
            displayName: "Flip",
            type: .bool_,
            defaultValue: .bool_(false)
        )
        #expect(param.clampValue(.bool_(true)) == .bool_(true))
    }

    // MARK: - Reset

    @Test("reset returns parameter with default value as current")
    func reset() {
        let param = EffectParameter(
            name: "radius",
            displayName: "Radius",
            type: .double_,
            defaultValue: .double_(10.0),
            currentValue: .double_(50.0)
        )
        let resetParam = param.reset()
        #expect(resetParam.currentValue == .double_(10.0))
        #expect(resetParam.isDefault == true)
    }

    // MARK: - with() Copy

    @Test("with() can update currentValue")
    func withCurrentValue() {
        let param = EffectParameter.withDefault(
            name: "radius",
            displayName: "Radius",
            type: .double_,
            defaultValue: .double_(10.0)
        )
        let updated = param.with(currentValue: .double_(20.0))
        #expect(updated.currentValue == .double_(20.0))
        #expect(updated.name == "radius") // Preserved
    }

    @Test("with() preserves all unchanged fields")
    func withPreservesFields() {
        let param = EffectParameter(
            name: "radius",
            displayName: "Radius",
            type: .double_,
            defaultValue: .double_(10.0),
            currentValue: .double_(10.0),
            minValue: .double_(0.0),
            maxValue: .double_(100.0),
            step: 0.5,
            unit: "px",
            isKeyframeable: true,
            group: "main"
        )
        let updated = param.with(currentValue: .double_(50.0))
        #expect(updated.name == "radius")
        #expect(updated.displayName == "Radius")
        #expect(updated.type == .double_)
        #expect(updated.defaultValue == .double_(10.0))
        #expect(updated.minValue == .double_(0.0))
        #expect(updated.maxValue == .double_(100.0))
        #expect(updated.step == 0.5)
        #expect(updated.unit == "px")
        #expect(updated.isKeyframeable == true)
        #expect(updated.group == "main")
    }

    // MARK: - Codable

    @Test("EffectParameter Codable roundtrip")
    func codableRoundtrip() throws {
        let original = EffectParameter(
            name: "radius",
            displayName: "Blur Radius",
            type: .double_,
            defaultValue: .double_(10.0),
            currentValue: .double_(25.0),
            minValue: .double_(0.0),
            maxValue: .double_(100.0),
            step: 0.5,
            unit: "px",
            isKeyframeable: true,
            group: "blur"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EffectParameter.self, from: data)
        #expect(decoded == original)
    }

    @Test("EffectParameter with bool type Codable roundtrip")
    func boolParamCodable() throws {
        let original = EffectParameter.withDefault(
            name: "flip",
            displayName: "Flip",
            type: .bool_,
            defaultValue: .bool_(false),
            isKeyframeable: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EffectParameter.self, from: data)
        #expect(decoded.name == "flip")
        #expect(decoded.currentValue.asBool == false)
    }

    @Test("EffectParameter with enumChoice type Codable roundtrip")
    func enumParamCodable() throws {
        let original = EffectParameter.withDefault(
            name: "mode",
            displayName: "Mode",
            type: .enumChoice,
            defaultValue: .enumChoice("normal"),
            enumValues: ["normal", "vivid"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EffectParameter.self, from: data)
        #expect(decoded.name == "mode")
        #expect(decoded.currentValue.asEnumChoice == "normal")
        #expect(decoded.enumValues == ["normal", "vivid"])
    }

    // MARK: - EffectParameterType

    @Test("Interpolatable types",
          arguments: [EffectParameterType.double_, .int_, .color, .point, .range])
    func interpolatableTypes(type: EffectParameterType) {
        #expect(type.isInterpolatable == true)
    }

    @Test("Non-interpolatable types",
          arguments: [EffectParameterType.bool_, .enumChoice])
    func nonInterpolatableTypes(type: EffectParameterType) {
        #expect(type.isInterpolatable == false)
    }
}

// MARK: - EffectParameterGroup Tests

@Suite("EffectParameterGroup Tests")
struct EffectParameterGroupTests {

    @Test("Group creation")
    func creation() {
        let group = EffectParameterGroup(
            name: "blur",
            displayName: "Blur Settings",
            parameterNames: ["radius", "intensity"]
        )
        #expect(group.name == "blur")
        #expect(group.displayName == "Blur Settings")
        #expect(group.parameterNames == ["radius", "intensity"])
        #expect(group.isCollapsedByDefault == false)
    }

    @Test("Group with collapsed default")
    func collapsedDefault() {
        let group = EffectParameterGroup(
            name: "advanced",
            displayName: "Advanced",
            parameterNames: ["option1"],
            isCollapsedByDefault: true
        )
        #expect(group.isCollapsedByDefault == true)
    }

    @Test("Group Codable roundtrip")
    func codableRoundtrip() throws {
        let original = EffectParameterGroup(
            name: "blur",
            displayName: "Blur Settings",
            parameterNames: ["radius", "intensity"],
            isCollapsedByDefault: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EffectParameterGroup.self, from: data)
        #expect(decoded == original)
    }
}
