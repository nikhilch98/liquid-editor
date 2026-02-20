import Testing
import Foundation
@testable import LiquidEditor

@Suite("VideoClip Tests")
struct VideoClipTests {

    // MARK: - Helpers

    private func makeClip(
        id: String = "vc-1",
        mediaAssetId: String = "video-asset",
        sourceIn: Int64 = 0,
        sourceOut: Int64 = 5_000_000,
        name: String? = nil
    ) -> VideoClip {
        VideoClip(
            id: id,
            mediaAssetId: mediaAssetId,
            sourceInMicros: sourceIn,
            sourceOutMicros: sourceOut,
            name: name
        )
    }

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let clip = makeClip()
        #expect(clip.id == "vc-1")
        #expect(clip.mediaAssetId == "video-asset")
        #expect(clip.sourceInMicros == 0)
        #expect(clip.sourceOutMicros == 5_000_000)
        #expect(clip.keyframes.isEmpty)
        #expect(clip.name == nil)
        #expect(clip.effectChain.isEmpty)
        #expect(clip.speedSettings == nil)
        #expect(clip.masks == nil)
        #expect(clip.panScanKeyframes == nil)
        #expect(clip.trackingPathId == nil)
        #expect(clip.multiCamGroupId == nil)
    }

    // MARK: - Computed Properties

    @Test("durationMicroseconds is sourceOut - sourceIn")
    func duration() {
        let clip = makeClip(sourceIn: 1_000_000, sourceOut: 4_000_000)
        #expect(clip.durationMicroseconds == 3_000_000)
    }

    @Test("displayName defaults to Video Clip")
    func displayNameDefault() {
        let clip = makeClip()
        #expect(clip.displayName == "Video Clip")
    }

    @Test("displayName uses custom name")
    func displayNameCustom() {
        let clip = makeClip(name: "Interview")
        #expect(clip.displayName == "Interview")
    }

    @Test("itemType is video")
    func itemType() {
        let clip = makeClip()
        #expect(clip.itemType == "video")
    }

    @Test("isMediaClip is true")
    func isMediaClip() {
        let clip = makeClip()
        #expect(clip.isMediaClip == true)
    }

    @Test("hasKeyframes when keyframes exist")
    func hasKeyframes() {
        let clip = makeClip()
        #expect(clip.hasKeyframes == false)
        #expect(clip.keyframeCount == 0)
    }

    @Test("hasSpeedSettings returns false for nil")
    func hasSpeedSettings() {
        let clip = makeClip()
        #expect(clip.hasSpeedSettings == false)
    }

    @Test("hasMasks returns false for nil")
    func hasMasks() {
        let clip = makeClip()
        #expect(clip.hasMasks == false)
    }

    @Test("hasPanScan returns false for nil")
    func hasPanScan() {
        let clip = makeClip()
        #expect(clip.hasPanScan == false)
    }

    @Test("hasTrackingPath returns false for nil")
    func hasTrackingPath() {
        let clip = makeClip()
        #expect(clip.hasTrackingPath == false)
    }

    @Test("isMultiCam returns false for nil")
    func isMultiCam() {
        let clip = makeClip()
        #expect(clip.isMultiCam == false)
    }

    @Test("sourceRange tuple")
    func sourceRange() {
        let clip = makeClip(sourceIn: 1_000_000, sourceOut: 3_000_000)
        #expect(clip.sourceRange.start == 1_000_000)
        #expect(clip.sourceRange.end == 3_000_000)
    }

    // MARK: - Source Time Mapping

    @Test("timelineToSource maps correctly")
    func timelineToSource() {
        let clip = makeClip(sourceIn: 2_000_000, sourceOut: 6_000_000)
        #expect(clip.timelineToSource(1_000_000) == 3_000_000)
    }

    @Test("sourceToTimeline maps correctly")
    func sourceToTimeline() {
        let clip = makeClip(sourceIn: 2_000_000, sourceOut: 6_000_000)
        #expect(clip.sourceToTimeline(3_000_000) == 1_000_000)
    }

    @Test("containsSourceTime")
    func containsSourceTime() {
        let clip = makeClip(sourceIn: 1_000_000, sourceOut: 3_000_000)
        #expect(clip.containsSourceTime(1_000_000) == true)
        #expect(clip.containsSourceTime(2_000_000) == true)
        #expect(clip.containsSourceTime(3_000_000) == false)  // Exclusive
        #expect(clip.containsSourceTime(0) == false)
    }

    // MARK: - Split

    @Test("split at valid offset")
    func splitValid() {
        let clip = makeClip(sourceIn: 0, sourceOut: 2_000_000, name: "Test")
        let result = clip.splitAt(1_000_000)
        #expect(result != nil)

        let (left, right) = result!
        #expect(left.sourceInMicros == 0)
        #expect(left.sourceOutMicros == 1_000_000)
        #expect(right.sourceInMicros == 1_000_000)
        #expect(right.sourceOutMicros == 2_000_000)
        #expect(left.name == "Test (1)")
        #expect(right.name == "Test (2)")
        #expect(left.id != clip.id)
        #expect(right.id != clip.id)
    }

    @Test("split at offset too close to start returns nil")
    func splitTooCloseStart() {
        let clip = makeClip(sourceIn: 0, sourceOut: 2_000_000)
        #expect(clip.splitAt(50_000) == nil)
    }

    @Test("split at offset too close to end returns nil")
    func splitTooCloseEnd() {
        let clip = makeClip(sourceIn: 0, sourceOut: 2_000_000)
        #expect(clip.splitAt(1_950_000) == nil)
    }

    // MARK: - Trim

    @Test("trimStart returns trimmed clip")
    func trimStart() {
        let clip = makeClip(sourceIn: 0, sourceOut: 3_000_000)
        let trimmed = clip.trimStart(1_000_000)
        #expect(trimmed != nil)
        #expect(trimmed!.sourceInMicros == 1_000_000)
        #expect(trimmed!.sourceOutMicros == 3_000_000)
        #expect(trimmed!.id == clip.id)
    }

    @Test("trimStart returns nil for invalid in point")
    func trimStartInvalid() {
        let clip = makeClip(sourceIn: 0, sourceOut: 1_000_000)
        #expect(clip.trimStart(0) == nil)
        #expect(clip.trimStart(1_000_000) == nil)
    }

    @Test("trimEnd returns trimmed clip")
    func trimEnd() {
        let clip = makeClip(sourceIn: 0, sourceOut: 3_000_000)
        let trimmed = clip.trimEnd(2_000_000)
        #expect(trimmed != nil)
        #expect(trimmed!.sourceInMicros == 0)
        #expect(trimmed!.sourceOutMicros == 2_000_000)
    }

    @Test("trimEnd returns nil for invalid out point")
    func trimEndInvalid() {
        let clip = makeClip(sourceIn: 0, sourceOut: 1_000_000)
        #expect(clip.trimEnd(1_000_000) == nil)
        #expect(clip.trimEnd(0) == nil)
    }

    // MARK: - Effect Chain Operations

    @Test("clearingEffects returns empty chain")
    func clearingEffects() {
        let clip = makeClip()
        let cleared = clip.clearingEffects()
        #expect(cleared.effectChain.isEmpty)
    }

    @Test("clearingKeyframes returns empty keyframes")
    func clearingKeyframes() {
        let clip = makeClip()
        let cleared = clip.clearingKeyframes()
        #expect(cleared.keyframes.isEmpty)
    }

    // MARK: - Duplicate

    @Test("duplicate creates new ID")
    func duplicate() {
        let clip = makeClip(name: "Original")
        let dupe = clip.duplicate()
        #expect(dupe.id != clip.id)
        #expect(dupe.mediaAssetId == clip.mediaAssetId)
        #expect(dupe.name == "Original (copy)")
    }

    // MARK: - Copy-With

    @Test("with() preserves unchanged fields")
    func withPreserves() {
        let clip = makeClip(name: "Orig")
        let modified = clip.with(name: "New")
        #expect(modified.name == "New")
        #expect(modified.id == clip.id)
        #expect(modified.mediaAssetId == clip.mediaAssetId)
    }

    @Test("with clearName sets name to nil")
    func withClearName() {
        let clip = makeClip(name: "Named")
        let modified = clip.with(clearName: true)
        #expect(modified.name == nil)
    }

    @Test("with clear optional fields")
    func withClearOptionals() {
        let clip = VideoClip(
            mediaAssetId: "a",
            sourceInMicros: 0,
            sourceOutMicros: 1_000_000,
            trackingPathId: "track-1",
            multiCamGroupId: "mc-1"
        )
        let modified = clip.with(clearTrackingPathId: true, clearMultiCamGroupId: true)
        #expect(modified.trackingPathId == nil)
        #expect(modified.multiCamGroupId == nil)
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves core fields")
    func codableRoundTrip() throws {
        let clip = VideoClip(
            id: "vc-rt",
            mediaAssetId: "asset-rt",
            sourceInMicros: 500_000,
            sourceOutMicros: 3_500_000,
            name: "Round Trip",
            trackingPathId: "track-1",
            multiCamGroupId: "mc-1"
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(VideoClip.self, from: data)
        #expect(decoded.id == "vc-rt")
        #expect(decoded.mediaAssetId == "asset-rt")
        #expect(decoded.sourceInMicros == 500_000)
        #expect(decoded.sourceOutMicros == 3_500_000)
        #expect(decoded.name == "Round Trip")
        #expect(decoded.trackingPathId == "track-1")
        #expect(decoded.multiCamGroupId == "mc-1")
    }

    @Test("Codable decoding with missing optionals uses defaults")
    func codableDefaults() throws {
        let json: [String: Any] = [
            "id": "vc-min",
            "mediaAssetId": "asset-min",
            "sourceInMicros": 0,
            "sourceOutMicros": 1_000_000,
            "itemType": "video"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(VideoClip.self, from: data)
        #expect(decoded.keyframes.isEmpty)
        #expect(decoded.name == nil)
        #expect(decoded.effectChain.isEmpty)
        #expect(decoded.speedSettings == nil)
    }

    // MARK: - Hashable

    @Test("hash is based on ID")
    func hashable() {
        let a = makeClip(id: "same")
        let b = VideoClip(id: "same", mediaAssetId: "diff", sourceInMicros: 0, sourceOutMicros: 999)
        #expect(a.hashValue == b.hashValue)
    }
}
