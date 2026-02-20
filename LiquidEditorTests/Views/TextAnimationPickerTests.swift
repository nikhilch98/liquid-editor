import Testing
@testable import LiquidEditor

// MARK: - TextAnimationPicker Tests

@Suite("TextAnimationPicker")
struct TextAnimationPickerTests {

    @Test("Enter animations has 12 entries")
    func enterAnimationsCount() {
        #expect(enterAnimations.count == 12)
    }

    @Test("Exit animations has 11 entries")
    func exitAnimationsCount() {
        #expect(exitAnimations.count == 11)
    }

    @Test("Sustain animations has 5 entries")
    func sustainAnimationsCount() {
        #expect(sustainAnimations.count == 5)
    }

    @Test("Enter animations start with fadeIn")
    func enterAnimationsStartWithFadeIn() {
        #expect(enterAnimations.first == .fadeIn)
    }

    @Test("Exit animations start with fadeOut")
    func exitAnimationsStartWithFadeOut() {
        #expect(exitAnimations.first == .fadeOut)
    }

    @Test("Sustain animations include breathe, pulse, float, shake, flicker")
    func sustainAnimationsContainExpected() {
        #expect(sustainAnimations.contains(.breathe))
        #expect(sustainAnimations.contains(.pulse))
        #expect(sustainAnimations.contains(.float))
        #expect(sustainAnimations.contains(.shake))
        #expect(sustainAnimations.contains(.flicker))
    }

    @Test("Enter and exit animations do not overlap")
    func enterExitNoOverlap() {
        let enterSet = Set(enterAnimations)
        let exitSet = Set(exitAnimations)
        let intersection = enterSet.intersection(exitSet)
        #expect(intersection.isEmpty)
    }

    @Test("Sustain animations do not overlap with enter or exit")
    func sustainNoOverlapWithEnterExit() {
        let sustainSet = Set(sustainAnimations)
        let enterSet = Set(enterAnimations)
        let exitSet = Set(exitAnimations)
        #expect(sustainSet.intersection(enterSet).isEmpty)
        #expect(sustainSet.intersection(exitSet).isEmpty)
    }

    @Test("All animation types have display names")
    func allTypesHaveDisplayNames() {
        for type in TextAnimationPresetType.allCases {
            let name = animationDisplayName(type)
            #expect(!name.isEmpty, "Display name for \(type) should not be empty")
        }
    }

    @Test("All animation types have SF Symbol names")
    func allTypesHaveSFSymbols() {
        for type in TextAnimationPresetType.allCases {
            let symbol = animationSFSymbol(type)
            #expect(!symbol.isEmpty, "SF Symbol for \(type) should not be empty")
        }
    }

    @Test("Display name for fadeIn is 'Fade In'")
    func fadeInDisplayName() {
        #expect(animationDisplayName(.fadeIn) == "Fade In")
    }

    @Test("Display name for slideInLeft is 'Slide Left'")
    func slideInLeftDisplayName() {
        #expect(animationDisplayName(.slideInLeft) == "Slide Left")
    }

    @Test("Display name for typewriter is 'Typewriter'")
    func typewriterDisplayName() {
        #expect(animationDisplayName(.typewriter) == "Typewriter")
    }

    @Test("Display name for breathe is 'Breathe'")
    func breatheDisplayName() {
        #expect(animationDisplayName(.breathe) == "Breathe")
    }

    @Test("SF Symbol for fadeIn is circle.lefthalf.filled")
    func fadeInSymbol() {
        #expect(animationSFSymbol(.fadeIn) == "circle.lefthalf.filled")
    }

    @Test("SF Symbol for slideInLeft matches slideOutLeft")
    func slideSymbolsMatch() {
        #expect(animationSFSymbol(.slideInLeft) == animationSFSymbol(.slideOutLeft))
    }

    @Test("SF Symbol for bounceIn matches bounceOut")
    func bounceSymbolsMatch() {
        #expect(animationSFSymbol(.bounceIn) == animationSFSymbol(.bounceOut))
    }

    @Test("All enter/exit animation type pairs have matching SF symbols")
    func pairedAnimationsShareSymbols() {
        let pairs: [(TextAnimationPresetType, TextAnimationPresetType)] = [
            (.fadeIn, .fadeOut),
            (.slideInLeft, .slideOutLeft),
            (.slideInRight, .slideOutRight),
            (.slideInTop, .slideOutTop),
            (.slideInBottom, .slideOutBottom),
            (.scaleUp, .scaleDown),
            (.bounceIn, .bounceOut),
            (.glitchIn, .glitchOut),
            (.rotateIn, .rotateOut),
            (.blurIn, .blurOut),
            (.popIn, .popOut),
        ]
        for (enter, exit) in pairs {
            #expect(
                animationSFSymbol(enter) == animationSFSymbol(exit),
                "\(enter) and \(exit) should share the same SF Symbol"
            )
        }
    }
}
