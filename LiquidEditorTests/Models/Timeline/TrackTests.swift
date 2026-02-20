import Testing
import Foundation
@testable import LiquidEditor

// MARK: - TrackType Tests

@Suite("TrackType Tests")
struct TrackTypeTests {

    @Test("All cases exist")
    func allCases() {
        #expect(TrackType.allCases.count == 8)
    }

    @Test("Display names")
    func displayNames() {
        #expect(TrackType.mainVideo.displayName == "Main Video")
        #expect(TrackType.overlayVideo.displayName == "Overlay")
        #expect(TrackType.audio.displayName == "Audio")
        #expect(TrackType.music.displayName == "Music")
        #expect(TrackType.voiceover.displayName == "Voiceover")
        #expect(TrackType.effect.displayName == "Effects")
        #expect(TrackType.text.displayName == "Text")
        #expect(TrackType.sticker.displayName == "Sticker")
    }

    @Test("Supports video")
    func supportsVideo() {
        #expect(TrackType.mainVideo.supportsVideo == true)
        #expect(TrackType.overlayVideo.supportsVideo == true)
        #expect(TrackType.audio.supportsVideo == false)
        #expect(TrackType.text.supportsVideo == false)
    }

    @Test("Supports audio")
    func supportsAudio() {
        #expect(TrackType.mainVideo.supportsAudio == true)
        #expect(TrackType.overlayVideo.supportsAudio == true)
        #expect(TrackType.audio.supportsAudio == true)
        #expect(TrackType.music.supportsAudio == true)
        #expect(TrackType.voiceover.supportsAudio == true)
        #expect(TrackType.text.supportsAudio == false)
        #expect(TrackType.sticker.supportsAudio == false)
        #expect(TrackType.effect.supportsAudio == false)
    }

    @Test("Supports effects")
    func supportsEffects() {
        #expect(TrackType.effect.supportsEffects == true)
        #expect(TrackType.mainVideo.supportsEffects == false)
    }

    @Test("Supports text")
    func supportsText() {
        #expect(TrackType.text.supportsText == true)
        #expect(TrackType.mainVideo.supportsText == false)
    }

    @Test("Supports sticker")
    func supportsSticker() {
        #expect(TrackType.sticker.supportsSticker == true)
        #expect(TrackType.mainVideo.supportsSticker == false)
    }

    @Test("Default colors are non-zero")
    func defaultColors() {
        for trackType in TrackType.allCases {
            #expect(trackType.defaultColorARGB32 != 0)
        }
    }
}

// MARK: - TrackHeightPreset Tests

@Suite("TrackHeightPreset Tests")
struct TrackHeightPresetTests {

    @Test("All presets exist")
    func allCases() {
        #expect(TrackHeightPreset.allCases.count == 4)
    }
}

// MARK: - Track Tests

@Suite("Track Tests")
struct TrackTests {

    func makeTrack(
        id: String = "track-1",
        type: TrackType = .mainVideo
    ) -> Track {
        Track(id: id, name: "Video Track", type: type, index: 0)
    }

    @Test("Creation with defaults")
    func creation() {
        let track = makeTrack()
        #expect(track.id == "track-1")
        #expect(track.name == "Video Track")
        #expect(track.type == .mainVideo)
        #expect(track.index == 0)
        #expect(track.height == Track.heightMedium)
        #expect(track.isMuted == false)
        #expect(track.isSolo == false)
        #expect(track.isLocked == false)
        #expect(track.isCollapsed == false)
        #expect(track.isVisible == true)
    }

    @Test("Default color from track type")
    func defaultColor() {
        let track = makeTrack(type: .mainVideo)
        #expect(track.colorARGB32 == TrackType.mainVideo.defaultColorARGB32)
    }

    @Test("Custom color overrides default")
    func customColor() {
        let track = Track(id: "t", name: "T", type: .audio, index: 0, colorARGB32: 0xFFFF0000)
        #expect(track.colorARGB32 == 0xFFFF0000)
    }

    @Test("Height constants")
    func heightConstants() {
        #expect(Track.heightSmall == 44.0)
        #expect(Track.heightMedium == 64.0)
        #expect(Track.heightLarge == 88.0)
        #expect(Track.heightFilmstrip == 120.0)
    }

    @Test("EffectiveHeight when collapsed")
    func effectiveHeightCollapsed() {
        let track = Track(id: "t", name: "T", type: .audio, index: 0, isCollapsed: true)
        #expect(track.effectiveHeight == Track.heightSmall)
    }

    @Test("EffectiveHeight when not collapsed")
    func effectiveHeightNormal() {
        let track = makeTrack()
        #expect(track.effectiveHeight == Track.heightMedium)
    }

    @Test("isVideoTrack")
    func isVideoTrack() {
        #expect(makeTrack(type: .mainVideo).isVideoTrack == true)
        #expect(makeTrack(type: .overlayVideo).isVideoTrack == true)
        #expect(makeTrack(type: .audio).isVideoTrack == false)
    }

    @Test("isAudioOnlyTrack")
    func isAudioOnlyTrack() {
        #expect(makeTrack(type: .audio).isAudioOnlyTrack == true)
        #expect(makeTrack(type: .music).isAudioOnlyTrack == true)
        #expect(makeTrack(type: .voiceover).isAudioOnlyTrack == true)
        #expect(makeTrack(type: .mainVideo).isAudioOnlyTrack == false)
    }

    @Test("toggleMute")
    func toggleMute() {
        let track = makeTrack()
        #expect(track.isMuted == false)
        let muted = track.toggleMute()
        #expect(muted.isMuted == true)
        let unmuted = muted.toggleMute()
        #expect(unmuted.isMuted == false)
    }

    @Test("toggleSolo")
    func toggleSolo() {
        let track = makeTrack()
        #expect(track.isSolo == false)
        let soloed = track.toggleSolo()
        #expect(soloed.isSolo == true)
    }

    @Test("toggleLock")
    func toggleLock() {
        let track = makeTrack()
        let locked = track.toggleLock()
        #expect(locked.isLocked == true)
    }

    @Test("toggleCollapsed")
    func toggleCollapsed() {
        let track = makeTrack()
        let collapsed = track.toggleCollapsed()
        #expect(collapsed.isCollapsed == true)
    }

    @Test("withHeightPreset sets correct heights")
    func withHeightPreset() {
        let track = makeTrack()
        #expect(track.withHeightPreset(.small).height == Track.heightSmall)
        #expect(track.withHeightPreset(.medium).height == Track.heightMedium)
        #expect(track.withHeightPreset(.large).height == Track.heightLarge)
        #expect(track.withHeightPreset(.filmstrip).height == Track.heightFilmstrip)
    }

    @Test("with() copy method")
    func withCopy() {
        let original = makeTrack()
        let modified = original.with(name: "Renamed", index: 3, isVisible: false)
        #expect(modified.name == "Renamed")
        #expect(modified.index == 3)
        #expect(modified.isVisible == false)
        #expect(modified.id == "track-1")
    }

    @Test("create() factory method")
    func createFactory() {
        let track = Track.create(id: "t-1", name: "Audio", type: .audio, index: 2)
        #expect(track.id == "t-1")
        #expect(track.name == "Audio")
        #expect(track.type == .audio)
        #expect(track.index == 2)
        #expect(track.colorARGB32 == TrackType.audio.defaultColorARGB32)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = Track(
            id: "t-1",
            name: "Main",
            type: .mainVideo,
            index: 0,
            height: Track.heightLarge,
            isMuted: true,
            isSolo: false,
            isLocked: true,
            colorARGB32: 0xFF5856D6,
            isCollapsed: false,
            isVisible: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.type == original.type)
        #expect(decoded.height == original.height)
        #expect(decoded.isMuted == true)
        #expect(decoded.isLocked == true)
        #expect(decoded.colorARGB32 == original.colorARGB32)
    }

    @Test("Codable JSON uses 'color' key for colorARGB32")
    func codableJsonKey() throws {
        let track = makeTrack()
        let data = try JSONEncoder().encode(track)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["color"] != nil)
    }
}
