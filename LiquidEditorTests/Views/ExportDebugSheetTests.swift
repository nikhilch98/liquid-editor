import Testing
import Foundation
@testable import LiquidEditor

@Suite("ExportDebugSheet Tests")
struct ExportDebugSheetTests {

    // MARK: - ExportDebugMode

    @Suite("ExportDebugMode")
    struct ExportDebugModeTests {

        @Test("allCases contains exactly 2 modes")
        func allCasesCount() {
            #expect(ExportDebugMode.allCases.count == 2)
        }

        @Test("allCases contains sideBySide and overlay")
        func allCasesContent() {
            let cases = ExportDebugMode.allCases
            #expect(cases.contains(.sideBySide))
            #expect(cases.contains(.overlay))
        }

        @Test("label returns correct display names")
        func labels() {
            #expect(ExportDebugMode.sideBySide.label == "Side by Side")
            #expect(ExportDebugMode.overlay.label == "Overlay")
        }

        @Test("id returns rawValue")
        func identifiable() {
            #expect(ExportDebugMode.sideBySide.id == "sideBySide")
            #expect(ExportDebugMode.overlay.id == "overlay")
        }

        @Test("rawValue roundtrips correctly")
        func rawValueRoundtrip() {
            for mode in ExportDebugMode.allCases {
                let recreated = ExportDebugMode(rawValue: mode.rawValue)
                #expect(recreated == mode)
            }
        }
    }

    // MARK: - ExportDebugInfo

    @Suite("ExportDebugInfo")
    struct ExportDebugInfoTests {

        @Test("Default init has nil values and zero clips")
        func defaults() {
            let info = ExportDebugInfo()
            #expect(info.previewWidth == nil)
            #expect(info.previewHeight == nil)
            #expect(info.exportWidth == nil)
            #expect(info.exportHeight == nil)
            #expect(info.sourceWidth == nil)
            #expect(info.sourceHeight == nil)
            #expect(info.scale == nil)
            #expect(info.tx == nil)
            #expect(info.ty == nil)
            #expect(info.rotation == nil)
            #expect(info.codec == nil)
            #expect(info.bitrateMbps == nil)
            #expect(info.fps == nil)
            #expect(info.clipCount == 0)
            #expect(info.clips.isEmpty)
            #expect(info.elapsedSeconds == nil)
            #expect(info.framesRendered == nil)
        }

        @Test("Custom init preserves all values")
        func customInit() {
            let info = ExportDebugInfo(
                previewWidth: 375.0,
                previewHeight: 667.0,
                exportWidth: 1920,
                exportHeight: 1080,
                sourceWidth: 1920.0,
                sourceHeight: 1080.0,
                scale: 0.1953,
                tx: 10.0,
                ty: 20.0,
                rotation: 1.5708,
                codec: "H.264",
                bitrateMbps: 20.0,
                fps: 30,
                clipCount: 2,
                clips: [
                    ClipDebugInfo(index: 0, orderIndex: 0, sourceInMs: 0, sourceOutMs: 5000),
                    ClipDebugInfo(index: 1, orderIndex: 1, sourceInMs: 5000, sourceOutMs: 10000),
                ],
                elapsedSeconds: 4.5,
                framesRendered: 360
            )

            #expect(info.previewWidth == 375.0)
            #expect(info.previewHeight == 667.0)
            #expect(info.exportWidth == 1920)
            #expect(info.exportHeight == 1080)
            #expect(info.sourceWidth == 1920.0)
            #expect(info.sourceHeight == 1080.0)
            #expect(info.scale == 0.1953)
            #expect(info.tx == 10.0)
            #expect(info.ty == 20.0)
            #expect(info.rotation == 1.5708)
            #expect(info.codec == "H.264")
            #expect(info.bitrateMbps == 20.0)
            #expect(info.fps == 30)
            #expect(info.clipCount == 2)
            #expect(info.clips.count == 2)
            #expect(info.elapsedSeconds == 4.5)
            #expect(info.framesRendered == 360)
        }

        @Test("fromMap creates correct info from dictionary")
        func fromMap() {
            let map: [String: Any] = [
                "previewWidth": 375.0,
                "previewHeight": 667.0,
                "exportWidth": 1920,
                "exportHeight": 1080,
                "sourceWidth": 1920.0,
                "sourceHeight": 1080.0,
                "scale": 0.5,
                "tx": 10.0,
                "ty": 20.0,
                "rotation": 0.0,
                "codec": "H.265 (HEVC)",
                "bitrateMbps": 50.0,
                "fps": 60,
                "clipCount": 2,
                "clips": [
                    ["orderIndex": 0, "sourceIn": 0, "sourceOut": 3000],
                    ["orderIndex": 1, "sourceIn": 3000, "sourceOut": 8000],
                ] as [[String: Any]],
                "elapsedSeconds": 2.3,
                "framesRendered": 180,
            ]

            let info = ExportDebugInfo.fromMap(map)
            #expect(info.previewWidth == 375.0)
            #expect(info.previewHeight == 667.0)
            #expect(info.exportWidth == 1920)
            #expect(info.exportHeight == 1080)
            #expect(info.scale == 0.5)
            #expect(info.tx == 10.0)
            #expect(info.ty == 20.0)
            #expect(info.rotation == 0.0)
            #expect(info.codec == "H.265 (HEVC)")
            #expect(info.bitrateMbps == 50.0)
            #expect(info.fps == 60)
            #expect(info.clipCount == 2)
            #expect(info.clips.count == 2)
            #expect(info.clips[0].orderIndex == 0)
            #expect(info.clips[0].sourceInMs == 0)
            #expect(info.clips[0].sourceOutMs == 3000)
            #expect(info.clips[1].orderIndex == 1)
            #expect(info.clips[1].sourceInMs == 3000)
            #expect(info.clips[1].sourceOutMs == 8000)
            #expect(info.elapsedSeconds == 2.3)
            #expect(info.framesRendered == 180)
        }

        @Test("fromMap handles empty dictionary gracefully")
        func fromMapEmpty() {
            let info = ExportDebugInfo.fromMap([:])
            #expect(info.previewWidth == nil)
            #expect(info.exportWidth == nil)
            #expect(info.scale == nil)
            #expect(info.codec == nil)
            #expect(info.clipCount == 0)
            #expect(info.clips.isEmpty)
        }

        @Test("fromMap handles missing clips gracefully")
        func fromMapNoClips() {
            let map: [String: Any] = [
                "previewWidth": 100.0,
                "clipCount": 0,
            ]
            let info = ExportDebugInfo.fromMap(map)
            #expect(info.previewWidth == 100.0)
            #expect(info.clipCount == 0)
            #expect(info.clips.isEmpty)
        }

        @Test("fromMap derives clipCount from clips array when not provided")
        func fromMapDeriveClipCount() {
            let map: [String: Any] = [
                "clips": [
                    ["orderIndex": 0, "sourceIn": 0, "sourceOut": 1000],
                ] as [[String: Any]],
            ]
            let info = ExportDebugInfo.fromMap(map)
            #expect(info.clipCount == 1)
            #expect(info.clips.count == 1)
        }
    }

    // MARK: - ClipDebugInfo

    @Suite("ClipDebugInfo")
    struct ClipDebugInfoTests {

        @Test("Properties are stored correctly")
        func properties() {
            let clip = ClipDebugInfo(
                index: 2,
                orderIndex: 3,
                sourceInMs: 5000,
                sourceOutMs: 12000
            )
            #expect(clip.index == 2)
            #expect(clip.orderIndex == 3)
            #expect(clip.sourceInMs == 5000)
            #expect(clip.sourceOutMs == 12000)
        }

        @Test("Each instance has a unique id")
        func uniqueIds() {
            let a = ClipDebugInfo(index: 0, orderIndex: 0, sourceInMs: 0, sourceOutMs: 1000)
            let b = ClipDebugInfo(index: 0, orderIndex: 0, sourceInMs: 0, sourceOutMs: 1000)
            #expect(a.id != b.id)
        }
    }
}
