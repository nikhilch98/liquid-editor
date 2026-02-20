import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("VideoTransform Tests")
struct VideoTransformTests {

    // MARK: - Creation

    @Test("creation with defaults is identity")
    func creationDefaults() {
        let transform = VideoTransform()
        #expect(transform.scale == 1.0)
        #expect(transform.translation == .zero)
        #expect(transform.rotation == 0.0)
        #expect(transform.anchor == CGPoint(x: 0.5, y: 0.5))
    }

    @Test("creation with custom values")
    func creationCustom() {
        let transform = VideoTransform(
            scale: 2.0,
            translation: CGPoint(x: 0.5, y: -0.3),
            rotation: 1.57,
            anchor: CGPoint(x: 0.0, y: 1.0)
        )
        #expect(transform.scale == 2.0)
        #expect(transform.translation == CGPoint(x: 0.5, y: -0.3))
        #expect(abs(transform.rotation - 1.57) < 0.001)
        #expect(transform.anchor == CGPoint(x: 0.0, y: 1.0))
    }

    // MARK: - Static Properties

    @Test("identity is default transform")
    func identityStatic() {
        let identity = VideoTransform.identity
        #expect(identity.scale == 1.0)
        #expect(identity.translation == .zero)
        #expect(identity.rotation == 0.0)
        #expect(identity.anchor == CGPoint(x: 0.5, y: 0.5))
    }

    // MARK: - isIdentity

    @Test("default transform is identity")
    func isIdentityTrue() {
        let transform = VideoTransform()
        #expect(transform.isIdentity == true)
    }

    @Test("scaled transform is not identity")
    func isIdentityScaled() {
        let transform = VideoTransform(scale: 2.0)
        #expect(transform.isIdentity == false)
    }

    @Test("translated transform is not identity")
    func isIdentityTranslated() {
        let transform = VideoTransform(translation: CGPoint(x: 0.1, y: 0.0))
        #expect(transform.isIdentity == false)
    }

    @Test("rotated transform is not identity")
    func isIdentityRotated() {
        let transform = VideoTransform(rotation: 0.5)
        #expect(transform.isIdentity == false)
    }

    @Test("near-identity within tolerance is identity")
    func isIdentityNearIdentity() {
        let transform = VideoTransform(
            scale: 1.0005,
            translation: CGPoint(x: 0.0005, y: -0.0005),
            rotation: 0.0005
        )
        #expect(transform.isIdentity == true)
    }

    // MARK: - clamped

    @Test("clamped clamps scale to 0.1-5.0")
    func clampedScale() {
        let low = VideoTransform(scale: 0.01).clamped()
        #expect(low.scale == 0.1)

        let high = VideoTransform(scale: 10.0).clamped()
        #expect(high.scale == 5.0)

        let normal = VideoTransform(scale: 2.0).clamped()
        #expect(normal.scale == 2.0)
    }

    @Test("clamped clamps translation to -1.0 to 1.0")
    func clampedTranslation() {
        let clamped = VideoTransform(
            translation: CGPoint(x: -2.0, y: 3.0)
        ).clamped()
        #expect(clamped.translation.x == -1.0)
        #expect(clamped.translation.y == 1.0)
    }

    @Test("clamped clamps anchor to 0.0-1.0")
    func clampedAnchor() {
        let clamped = VideoTransform(
            anchor: CGPoint(x: -0.5, y: 1.5)
        ).clamped()
        #expect(clamped.anchor.x == 0.0)
        #expect(clamped.anchor.y == 1.0)
    }

    @Test("clamped preserves rotation")
    func clampedRotation() {
        let transform = VideoTransform(rotation: 6.28).clamped()
        #expect(abs(transform.rotation - 6.28) < 0.001)
    }

    // MARK: - with()

    @Test("with() preserves unchanged fields")
    func withPreserves() {
        let original = VideoTransform(scale: 2.0, rotation: 1.0)
        let modified = original.with(scale: 3.0)
        #expect(modified.scale == 3.0)
        #expect(modified.rotation == 1.0)
        #expect(modified.translation == .zero)
    }

    @Test("with() can override all fields")
    func withOverridesAll() {
        let original = VideoTransform()
        let modified = original.with(
            scale: 2.5,
            translation: CGPoint(x: 0.3, y: -0.3),
            rotation: 3.14,
            anchor: CGPoint(x: 0.0, y: 0.0)
        )
        #expect(modified.scale == 2.5)
        #expect(modified.translation == CGPoint(x: 0.3, y: -0.3))
        #expect(abs(modified.rotation - 3.14) < 0.001)
        #expect(modified.anchor == CGPoint(x: 0.0, y: 0.0))
    }

    // MARK: - Equatable / Hashable

    @Test("equal transforms are equal")
    func equality() {
        let a = VideoTransform(scale: 2.0, rotation: 1.0)
        let b = VideoTransform(scale: 2.0, rotation: 1.0)
        #expect(a == b)
    }

    @Test("different transforms are not equal")
    func inequality() {
        let a = VideoTransform(scale: 1.0)
        let b = VideoTransform(scale: 2.0)
        #expect(a != b)
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = VideoTransform(
            scale: 2.5,
            translation: CGPoint(x: 0.3, y: -0.4),
            rotation: 1.57,
            anchor: CGPoint(x: 0.25, y: 0.75)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VideoTransform.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable decoding with missing fields uses defaults")
    func codableDefaults() throws {
        let json: [String: Any] = [:]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(VideoTransform.self, from: data)
        #expect(decoded.scale == 1.0)
        #expect(decoded.translation == .zero)
        #expect(decoded.rotation == 0.0)
        #expect(decoded.anchor == CGPoint(x: 0.5, y: 0.5))
    }
}
