import Testing
import Foundation
@testable import LiquidEditor

// MARK: - TransitionCategory Tests

@Suite("TransitionCategory Tests")
struct TransitionCategoryTests {

    @Test("All categories exist")
    func allCases() {
        #expect(TransitionCategory.allCases.count == 5)
    }

    @Test("Display names")
    func displayNames() {
        #expect(TransitionCategory.basic.displayName == "Basic")
        #expect(TransitionCategory.wipe.displayName == "Wipe")
        #expect(TransitionCategory.slide.displayName == "Slide")
        #expect(TransitionCategory.zoom.displayName == "Zoom")
        #expect(TransitionCategory.special.displayName == "Special")
    }

    @Test("Types list returns correct types for basic")
    func basicTypes() {
        let types = TransitionCategory.basic.types
        #expect(types.contains(.crossDissolve))
        #expect(types.contains(.crossfade))
        #expect(types.contains(.dip))
        #expect(types.contains(.fadeToBlack))
        #expect(types.contains(.fadeToWhite))
        #expect(types.count == 5)
    }

    @Test("Types list returns correct types for wipe")
    func wipeTypes() {
        let types = TransitionCategory.wipe.types
        #expect(types.contains(.wipe))
        #expect(types.contains(.wipeClock))
        #expect(types.contains(.wipeIris))
        #expect(types.count == 3)
    }

    @Test("Types list returns correct types for slide")
    func slideTypes() {
        let types = TransitionCategory.slide.types
        #expect(types.contains(.slide))
        #expect(types.contains(.push))
        #expect(types.contains(.slideOver))
        #expect(types.contains(.slideUnder))
        #expect(types.count == 4)
    }

    @Test("Types list returns correct types for zoom")
    func zoomTypes() {
        let types = TransitionCategory.zoom.types
        #expect(types.contains(.zoom))
        #expect(types.contains(.zoomIn))
        #expect(types.contains(.zoomOut))
        #expect(types.count == 3)
    }

    @Test("Types list returns correct types for special")
    func specialTypes() {
        let types = TransitionCategory.special.types
        #expect(types.contains(.blur))
        #expect(types.contains(.rotation))
        #expect(types.contains(.pageCurl))
        #expect(types.contains(.custom))
        #expect(types.count == 4)
    }

    @Test("All types accounted for in categories")
    func allTypesHaveCategory() {
        var totalFromCategories = 0
        for category in TransitionCategory.allCases {
            totalFromCategories += category.types.count
        }
        #expect(totalFromCategories == TransitionType.allCases.count)
    }
}

// MARK: - TransitionType Tests

@Suite("TransitionType Tests")
struct TransitionTypeTests {

    @Test("All cases exist")
    func allCases() {
        #expect(TransitionType.allCases.count == 19)
    }

    @Test("Display names are non-empty")
    func displayNames() {
        for type in TransitionType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test("Specific display names")
    func specificDisplayNames() {
        #expect(TransitionType.crossDissolve.displayName == "Cross Dissolve")
        #expect(TransitionType.fadeToBlack.displayName == "Fade to Black")
        #expect(TransitionType.pageCurl.displayName == "Page Curl")
    }

    @Test("Categories are assigned correctly")
    func categories() {
        #expect(TransitionType.crossDissolve.category == .basic)
        #expect(TransitionType.wipe.category == .wipe)
        #expect(TransitionType.slide.category == .slide)
        #expect(TransitionType.zoom.category == .zoom)
        #expect(TransitionType.blur.category == .special)
    }

    @Test("Default durations are positive")
    func defaultDurations() {
        for type in TransitionType.allCases {
            #expect(type.defaultDuration > 0)
        }
    }

    @Test("Specific default durations")
    func specificDefaultDurations() {
        #expect(TransitionType.crossDissolve.defaultDuration == 500_000)
        #expect(TransitionType.dip.defaultDuration == 1_000_000)
        #expect(TransitionType.wipeClock.defaultDuration == 750_000)
        #expect(TransitionType.pageCurl.defaultDuration == 800_000)
    }

    @Test("Supports direction for directional types")
    func supportsDirection() {
        #expect(TransitionType.wipe.supportsDirection == true)
        #expect(TransitionType.slide.supportsDirection == true)
        #expect(TransitionType.push.supportsDirection == true)
        #expect(TransitionType.crossDissolve.supportsDirection == false)
        #expect(TransitionType.zoom.supportsDirection == false)
    }

    @Test("Supports color for dip/fade types")
    func supportsColor() {
        #expect(TransitionType.dip.supportsColor == true)
        #expect(TransitionType.fadeToBlack.supportsColor == true)
        #expect(TransitionType.fadeToWhite.supportsColor == true)
        #expect(TransitionType.crossDissolve.supportsColor == false)
    }

    @Test("Supports softness for wipe types")
    func supportsSoftness() {
        #expect(TransitionType.wipe.supportsSoftness == true)
        #expect(TransitionType.wipeClock.supportsSoftness == true)
        #expect(TransitionType.wipeIris.supportsSoftness == true)
        #expect(TransitionType.slide.supportsSoftness == false)
    }

    @Test("Requires dual frames for most types")
    func requiresDualFrames() {
        #expect(TransitionType.crossDissolve.requiresDualFrames == true)
        #expect(TransitionType.crossfade.requiresDualFrames == false)
    }

    @Test("Supports audio only for crossfade")
    func supportsAudio() {
        #expect(TransitionType.crossfade.supportsAudio == true)
        #expect(TransitionType.crossDissolve.supportsAudio == false)
    }

    @Test("Supports video for non-crossfade")
    func supportsVideo() {
        #expect(TransitionType.crossDissolve.supportsVideo == true)
        #expect(TransitionType.crossfade.supportsVideo == false)
    }

    @Test("SF symbol names are non-empty")
    func sfSymbolNames() {
        for type in TransitionType.allCases {
            #expect(!type.sfSymbolName.isEmpty)
        }
    }
}

// MARK: - TransitionAlignment Tests

@Suite("TransitionAlignment Tests")
struct TransitionAlignmentTests {

    @Test("All cases exist")
    func allCases() {
        #expect(TransitionAlignment.allCases.count == 3)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for alignment in TransitionAlignment.allCases {
            let data = try JSONEncoder().encode(alignment)
            let decoded = try JSONDecoder().decode(TransitionAlignment.self, from: data)
            #expect(decoded == alignment)
        }
    }
}

// MARK: - TransitionDirection Tests

@Suite("TransitionDirection Tests")
struct TransitionDirectionTests {

    @Test("All cases exist")
    func allCases() {
        #expect(TransitionDirection.allCases.count == 4)
    }
}

// MARK: - EasingCurve Tests

@Suite("EasingCurve Tests")
struct EasingCurveTests {

    @Test("All cases exist")
    func allCases() {
        #expect(EasingCurve.allCases.count == 8)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for curve in EasingCurve.allCases {
            let data = try JSONEncoder().encode(curve)
            let decoded = try JSONDecoder().decode(EasingCurve.self, from: data)
            #expect(decoded == curve)
        }
    }
}

// MARK: - ClipTransition Tests

@Suite("ClipTransition Tests")
struct ClipTransitionTests {

    func makeTransition(
        editPointTime: TimeMicros = 5_000_000,
        duration: TimeMicros = 500_000,
        alignment: TransitionAlignment = .centerOnCut
    ) -> ClipTransition {
        ClipTransition(
            id: "trans-1",
            leftClipId: "clip-1",
            rightClipId: "clip-2",
            trackId: "track-1",
            type: .crossDissolve,
            duration: duration,
            alignment: alignment,
            editPointTime: editPointTime
        )
    }

    @Test("Creation with defaults")
    func creation() {
        let transition = makeTransition()
        #expect(transition.id == "trans-1")
        #expect(transition.leftClipId == "clip-1")
        #expect(transition.rightClipId == "clip-2")
        #expect(transition.trackId == "track-1")
        #expect(transition.type == .crossDissolve)
        #expect(transition.duration == 500_000)
        #expect(transition.alignment == .centerOnCut)
        #expect(transition.direction == .left)
        #expect(transition.easing == .easeInOut)
        #expect(transition.parameters.isEmpty)
    }

    @Test("Time range - centerOnCut alignment")
    func timeRangeCenterOnCut() {
        let transition = makeTransition(
            editPointTime: 5_000_000,
            duration: 500_000,
            alignment: .centerOnCut
        )
        #expect(transition.startTime == 4_750_000) // 5M - 250K
        #expect(transition.endTime == 5_250_000)   // 5M + 250K
    }

    @Test("Time range - startAtCut alignment")
    func timeRangeStartAtCut() {
        let transition = makeTransition(
            editPointTime: 5_000_000,
            duration: 500_000,
            alignment: .startAtCut
        )
        #expect(transition.startTime == 5_000_000)
        #expect(transition.endTime == 5_500_000)
    }

    @Test("Time range - endAtCut alignment")
    func timeRangeEndAtCut() {
        let transition = makeTransition(
            editPointTime: 5_000_000,
            duration: 500_000,
            alignment: .endAtCut
        )
        #expect(transition.startTime == 4_500_000)
        #expect(transition.endTime == 5_000_000)
    }

    @Test("Left overlap required - centerOnCut")
    func leftOverlapCenterOnCut() {
        let transition = makeTransition(duration: 500_000, alignment: .centerOnCut)
        #expect(transition.leftOverlapRequired == 250_000)
    }

    @Test("Left overlap required - startAtCut")
    func leftOverlapStartAtCut() {
        let transition = makeTransition(alignment: .startAtCut)
        #expect(transition.leftOverlapRequired == 0)
    }

    @Test("Left overlap required - endAtCut")
    func leftOverlapEndAtCut() {
        let transition = makeTransition(duration: 500_000, alignment: .endAtCut)
        #expect(transition.leftOverlapRequired == 500_000)
    }

    @Test("Right overlap required - centerOnCut")
    func rightOverlapCenterOnCut() {
        let transition = makeTransition(duration: 500_000, alignment: .centerOnCut)
        #expect(transition.rightOverlapRequired == 250_000)
    }

    @Test("Right overlap required - startAtCut")
    func rightOverlapStartAtCut() {
        let transition = makeTransition(duration: 500_000, alignment: .startAtCut)
        #expect(transition.rightOverlapRequired == 500_000)
    }

    @Test("Right overlap required - endAtCut")
    func rightOverlapEndAtCut() {
        let transition = makeTransition(alignment: .endAtCut)
        #expect(transition.rightOverlapRequired == 0)
    }

    @Test("withDuration clamps to min")
    func withDurationClampsMin() {
        let transition = makeTransition()
        let clamped = transition.withDuration(100) // below minDuration
        #expect(clamped.duration == ClipTransition.minDuration)
    }

    @Test("withDuration clamps to max")
    func withDurationClampsMax() {
        let transition = makeTransition()
        let clamped = transition.withDuration(10_000_000) // above maxDuration
        #expect(clamped.duration == ClipTransition.maxDuration)
    }

    @Test("withDuration accepts valid duration")
    func withDurationValid() {
        let transition = makeTransition()
        let updated = transition.withDuration(1_000_000)
        #expect(updated.duration == 1_000_000)
    }

    @Test("Min and max duration constants")
    func durationConstants() {
        #expect(ClipTransition.minDuration == 66_666)
        #expect(ClipTransition.maxDuration == 5_000_000)
    }

    @Test("withType changes type")
    func withType() {
        let transition = makeTransition()
        let updated = transition.withType(.fadeToBlack)
        #expect(updated.type == .fadeToBlack)
        #expect(updated.id == "trans-1") // unchanged
    }

    @Test("withAlignment changes alignment")
    func withAlignment() {
        let transition = makeTransition()
        let updated = transition.withAlignment(.startAtCut)
        #expect(updated.alignment == .startAtCut)
    }

    @Test("with() copy method")
    func withCopy() {
        let original = makeTransition()
        let modified = original.with(
            direction: .right,
            easing: .bounceOut,
            parameters: ["softness": "0.5"]
        )
        #expect(modified.direction == .right)
        #expect(modified.easing == .bounceOut)
        #expect(modified.parameters["softness"] == "0.5")
        #expect(modified.id == "trans-1")
    }

    @Test("Equatable compares all relevant fields")
    func equatable() {
        let a = makeTransition()
        let b = makeTransition()
        #expect(a == b)
    }

    @Test("Equatable detects differences")
    func equatableDifferent() {
        let a = makeTransition()
        let b = a.with(type: .fadeToBlack)
        #expect(a != b)
    }

    @Test("Hashable is consistent")
    func hashable() {
        let a = makeTransition()
        let b = makeTransition()
        #expect(a.hashValue == b.hashValue)
    }
}
