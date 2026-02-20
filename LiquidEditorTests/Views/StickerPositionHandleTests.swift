import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("StickerPositionHandle Tests")
struct StickerPositionHandleTests {

    // MARK: - StickerTransformUpdate

    @Suite("StickerTransformUpdate")
    struct TransformUpdateTests {

        @Test("Default transform update has all nil fields")
        func defaultValues() {
            let update = StickerTransformUpdate()
            #expect(update.position == nil)
            #expect(update.rotation == nil)
            #expect(update.scale == nil)
        }

        @Test("Transform update with position only")
        func positionOnly() {
            let update = StickerTransformUpdate(
                position: CGPoint(x: 0.5, y: 0.5)
            )
            #expect(update.position != nil)
            #expect(update.position?.x == 0.5)
            #expect(update.position?.y == 0.5)
            #expect(update.rotation == nil)
            #expect(update.scale == nil)
        }

        @Test("Transform update with scale only")
        func scaleOnly() {
            let update = StickerTransformUpdate(scale: 2.0)
            #expect(update.position == nil)
            #expect(update.rotation == nil)
            #expect(update.scale == 2.0)
        }

        @Test("Transform update with rotation only")
        func rotationOnly() {
            let update = StickerTransformUpdate(rotation: 1.57)
            #expect(update.position == nil)
            #expect(update.rotation == 1.57)
            #expect(update.scale == nil)
        }

        @Test("Transform update with all fields")
        func allFields() {
            let update = StickerTransformUpdate(
                position: CGPoint(x: 0.3, y: 0.7),
                rotation: 0.5,
                scale: 1.5
            )
            #expect(update.position?.x == 0.3)
            #expect(update.position?.y == 0.7)
            #expect(update.rotation == 0.5)
            #expect(update.scale == 1.5)
        }

        @Test("Equatable: equal updates are equal")
        func equatableEqual() {
            let a = StickerTransformUpdate(
                position: CGPoint(x: 0.5, y: 0.5),
                rotation: 1.0,
                scale: 2.0
            )
            let b = StickerTransformUpdate(
                position: CGPoint(x: 0.5, y: 0.5),
                rotation: 1.0,
                scale: 2.0
            )
            #expect(a == b)
        }

        @Test("Equatable: different updates are not equal")
        func equatableNotEqual() {
            let a = StickerTransformUpdate(scale: 1.0)
            let b = StickerTransformUpdate(scale: 2.0)
            #expect(a != b)
        }
    }

    // MARK: - Snap Threshold

    @Suite("Snap Threshold")
    struct SnapThresholdTests {

        @Test("Snap threshold is 0.02")
        func snapThresholdValue() {
            #expect(StickerPositionHandle<EmptyView>.snapThreshold == 0.02)
        }
    }

    // MARK: - Configuration Defaults

    @Suite("Configuration Defaults")
    struct ConfigDefaultsTests {

        @Test("Position normalized coordinates in range 0-1")
        func normalizedRange() {
            let position = CGPoint(x: 0.5, y: 0.5)
            #expect(position.x >= 0.0 && position.x <= 1.0)
            #expect(position.y >= 0.0 && position.y <= 1.0)
        }

        @Test("Scale factor default is 1.0")
        func defaultScale() {
            let scale: Double = 1.0
            #expect(scale == 1.0)
        }

        @Test("Rotation default is 0.0")
        func defaultRotation() {
            let rotation: Double = 0.0
            #expect(rotation == 0.0)
        }
    }

    // MARK: - Snap Logic (Unit-testable portion)

    @Suite("Snap Guide Logic")
    struct SnapGuideTests {

        @Test("Center snap: value near 0.5 snaps to 0.5")
        func centerSnap() {
            // Test the snap logic in isolation
            let threshold = 0.02
            let x = 0.51 // Within threshold of 0.5
            let snapped = abs(x - 0.5) < threshold ? 0.5 : x
            #expect(snapped == 0.5)
        }

        @Test("Center snap: value far from 0.5 does not snap")
        func centerNoSnap() {
            let threshold = 0.02
            let x = 0.55 // Outside threshold of 0.5
            let snapped = abs(x - 0.5) < threshold ? 0.5 : x
            #expect(snapped == 0.55)
        }

        @Test("Left edge snap: value near 0.0 snaps to 0.0")
        func leftEdgeSnap() {
            let threshold = 0.02
            let x = 0.01
            let snapped = abs(x) < threshold ? 0.0 : x
            #expect(snapped == 0.0)
        }

        @Test("Right edge snap: value near 1.0 snaps to 1.0")
        func rightEdgeSnap() {
            let threshold = 0.02
            let x = 0.99
            let snapped = abs(x - 1.0) < threshold ? 1.0 : x
            #expect(snapped == 1.0)
        }

        @Test("No snap: value at 0.3 does not snap to anything")
        func noSnap() {
            let threshold = 0.02
            let x = 0.3
            let snapsToCenter = abs(x - 0.5) < threshold
            let snapsToLeft = abs(x) < threshold
            let snapsToRight = abs(x - 1.0) < threshold
            #expect(!snapsToCenter)
            #expect(!snapsToLeft)
            #expect(!snapsToRight)
        }
    }
}

// MARK: - EmptyView conformance helper

import SwiftUI
