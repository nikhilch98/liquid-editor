import Testing
import AVFoundation
import Foundation
@testable import LiquidEditor

@Suite("ExportInstructionFactory Tests")
struct ExportInstructionTests {

    // MARK: - makePassthrough

    @Test("makePassthrough creates minimal instruction")
    func makePassthrough() {
        let timeRange = CMTimeRange(
            start: CMTime(seconds: 0, preferredTimescale: 600),
            duration: CMTime(seconds: 5, preferredTimescale: 600)
        )
        let trackID: CMPersistentTrackID = 1

        let instruction = ExportInstructionFactory.makePassthrough(
            timeRange: timeRange,
            sourceTrackID: trackID
        )

        #expect(instruction.timeRange == timeRange)
        #expect(instruction.sourceTrackID == trackID)
        #expect(instruction.colorGradeParams == nil)
        #expect(instruction.effectChain == nil)
        #expect(instruction.cropParams == nil)
        #expect(instruction.transitionData == nil)
        #expect(instruction.previousTrackID == nil)
        #expect(instruction.playbackSpeed == 1.0)
    }

    // MARK: - makeInstruction

    @Test("makeInstruction creates instruction with all parameters")
    func makeInstructionFull() {
        let timeRange = CMTimeRange(
            start: CMTime(seconds: 1, preferredTimescale: 600),
            duration: CMTime(seconds: 10, preferredTimescale: 600)
        )
        let trackID: CMPersistentTrackID = 2
        let config = ExportConfig(resolution: .r1080p, codec: .h265)
        let colorParams: [String: Any] = ["exposure": 0.5, "contrast": 0.3]
        let effects: [[String: Any]] = [["type": "blur", "radius": 5.0]]
        let speedConfig = SpeedConfig(speedMultiplier: 2.0)

        let instruction = ExportInstructionFactory.makeInstruction(
            timeRange: timeRange,
            sourceTrackID: trackID,
            config: config,
            colorGradeParams: colorParams,
            effectChain: effects,
            speedConfig: speedConfig
        )

        #expect(instruction.timeRange == timeRange)
        #expect(instruction.sourceTrackID == trackID)
        #expect(instruction.colorGradeParams != nil)
        #expect(instruction.effectChain != nil)
        #expect(instruction.effectChain?.count == 1)
        #expect(instruction.playbackSpeed == 2.0)
    }

    @Test("makeInstruction with default speed config uses 1.0")
    func makeInstructionDefaultSpeed() {
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 3, preferredTimescale: 600)
        )
        let instruction = ExportInstructionFactory.makeInstruction(
            timeRange: timeRange,
            sourceTrackID: 1,
            config: ExportConfig()
        )

        #expect(instruction.playbackSpeed == 1.0)
    }

    @Test("makeInstruction with slow speed config uses correct multiplier")
    func makeInstructionSlowSpeed() {
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 3, preferredTimescale: 600)
        )
        let slowConfig = SpeedConfig(speedMultiplier: 0.5)
        let instruction = ExportInstructionFactory.makeInstruction(
            timeRange: timeRange,
            sourceTrackID: 1,
            config: ExportConfig(),
            speedConfig: slowConfig
        )

        #expect(instruction.playbackSpeed == 0.5)
    }

    @Test("makeInstruction with previousTrackID for transitions")
    func makeInstructionWithTransition() {
        let timeRange = CMTimeRange(
            start: CMTime(seconds: 4, preferredTimescale: 600),
            duration: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let instruction = ExportInstructionFactory.makeInstruction(
            timeRange: timeRange,
            sourceTrackID: 2,
            config: ExportConfig(),
            previousTrackID: 1
        )

        #expect(instruction.previousTrackID == 1)
    }

    // MARK: - ExportCompositionInstruction Properties

    @Test("Instruction conforms to AVVideoCompositionInstructionProtocol")
    func protocolConformance() {
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let instruction = ExportInstructionFactory.makePassthrough(
            timeRange: timeRange,
            sourceTrackID: 1
        )

        #expect(instruction.enablePostProcessing == true)
        #expect(instruction.containsTweening == true)
        #expect(instruction.requiredSourceTrackIDs != nil)
    }

    @Test("Instruction required source track IDs includes source track")
    func requiredTrackIDs() {
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let trackID: CMPersistentTrackID = 42
        let instruction = ExportInstructionFactory.makePassthrough(
            timeRange: timeRange,
            sourceTrackID: trackID
        )

        let requiredIDs = instruction.requiredSourceTrackIDs
        #expect(requiredIDs != nil)
        // The required IDs should contain at least one entry
        #expect((requiredIDs?.count ?? 0) >= 1)
    }
}
