import Testing
import Foundation
@testable import LiquidEditor

// MARK: - MediaType Tests

@Suite("MediaType Tests")
struct MediaTypeTests {

    @Test("all cases")
    func allCases() {
        #expect(MediaType.allCases.count == 3)
        #expect(MediaType.video.rawValue == "video")
        #expect(MediaType.image.rawValue == "image")
        #expect(MediaType.audio.rawValue == "audio")
    }
}

// MARK: - ImportSource Tests

@Suite("ImportSource Tests")
struct ImportSourceTests {

    @Test("all cases")
    func allCases() {
        #expect(ImportSource.allCases.count == 6)
        #expect(ImportSource.photoLibrary.rawValue == "photoLibrary")
        #expect(ImportSource.files.rawValue == "files")
        #expect(ImportSource.camera.rawValue == "camera")
        #expect(ImportSource.url.rawValue == "url")
        #expect(ImportSource.googleDrive.rawValue == "googleDrive")
        #expect(ImportSource.dropbox.rawValue == "dropbox")
    }
}

// MARK: - TagColor Tests

@Suite("TagColor Tests")
struct TagColorTests {

    @Test("all cases")
    func allCases() {
        #expect(TagColor.allCases.count == 6)
        #expect(TagColor.red.rawValue == "red")
        #expect(TagColor.orange.rawValue == "orange")
        #expect(TagColor.yellow.rawValue == "yellow")
        #expect(TagColor.green.rawValue == "green")
        #expect(TagColor.blue.rawValue == "blue")
        #expect(TagColor.purple.rawValue == "purple")
    }
}

// MARK: - MediaAsset Tests

@Suite("MediaAsset Tests")
struct MediaAssetTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1700000000)

    private func makeVideoAsset() -> MediaAsset {
        MediaAsset(
            id: "ma-1",
            contentHash: "abc123",
            relativePath: "media/video1.mp4",
            originalFilename: "video1.mp4",
            type: .video,
            durationMicroseconds: 10_000_000,
            frameRate: .fps30,
            width: 1920,
            height: 1080,
            codec: "h264",
            audioSampleRate: 48000,
            audioChannels: 2,
            fileSize: 50_000_000,
            importedAt: Self.fixedDate,
            importSource: .photoLibrary
        )
    }

    private func makeImageAsset() -> MediaAsset {
        MediaAsset(
            id: "ma-img",
            contentHash: "img123",
            relativePath: "media/photo.jpg",
            originalFilename: "photo.jpg",
            type: .image,
            durationMicroseconds: 0,
            width: 4032,
            height: 3024,
            fileSize: 5_000_000,
            importedAt: Self.fixedDate
        )
    }

    @Test("creation video asset")
    func creationVideo() {
        let asset = makeVideoAsset()
        #expect(asset.id == "ma-1")
        #expect(asset.contentHash == "abc123")
        #expect(asset.type == .video)
        #expect(asset.isVideo)
        #expect(!asset.isImage)
        #expect(!asset.isAudio)
        #expect(asset.hasVideo)
        #expect(asset.hasAudio)
        #expect(asset.isLinked == true)
        #expect(asset.isFavorite == false)
        #expect(asset.colorTags.isEmpty)
        #expect(asset.textTags.isEmpty)
    }

    @Test("creation image asset")
    func creationImage() {
        let asset = makeImageAsset()
        #expect(asset.isImage)
        #expect(asset.hasVideo)
        #expect(!asset.hasAudio) // No audio channels
        #expect(asset.durationMicroseconds == 0)
    }

    @Test("aspectRatio computed property")
    func aspectRatio() {
        let asset = makeVideoAsset()
        let expected = 1920.0 / 1080.0
        #expect(abs(asset.aspectRatio - expected) < 0.001)
    }

    @Test("aspectRatio for zero height")
    func aspectRatioZeroHeight() {
        let asset = MediaAsset(
            id: "z", contentHash: "h", relativePath: "p",
            originalFilename: "f", type: .video, durationMicroseconds: 0,
            width: 100, height: 0, fileSize: 0, importedAt: Self.fixedDate
        )
        #expect(asset.aspectRatio == 1.0)
    }

    @Test("frameCount computed property")
    func frameCount() {
        let asset = makeVideoAsset()
        // 10 seconds at 30fps = 300 frames
        #expect(asset.frameCount == 300)
    }

    @Test("frameCount for image is 0")
    func frameCountImage() {
        let asset = makeImageAsset()
        #expect(asset.frameCount == 0)
    }

    @Test("with() copy")
    func withCopy() {
        let asset = makeVideoAsset()
        let modified = asset.with(isFavorite: true, colorTags: [.red, .blue])
        #expect(modified.isFavorite == true)
        #expect(modified.colorTags == [.red, .blue])
        #expect(modified.id == asset.id)
        #expect(modified.contentHash == asset.contentHash)
    }

    @Test("markLinked updates path and linked status")
    func markLinked() {
        let asset = makeVideoAsset().with(isLinked: false)
        #expect(asset.isLinked == false)
        let linked = asset.markLinked("new/path.mp4")
        #expect(linked.isLinked == true)
        #expect(linked.relativePath == "new/path.mp4")
        #expect(linked.lastVerifiedAt != nil)
    }

    @Test("markUnlinked sets isLinked false")
    func markUnlinked() {
        let asset = makeVideoAsset()
        #expect(asset.isLinked == true)
        let unlinked = asset.markUnlinked()
        #expect(unlinked.isLinked == false)
    }

    @Test("Equatable is by id")
    func equatableById() {
        let a = MediaAsset(
            id: "same", contentHash: "h1", relativePath: "p1",
            originalFilename: "f1", type: .video, durationMicroseconds: 0,
            width: 100, height: 100, fileSize: 0, importedAt: Self.fixedDate
        )
        let b = MediaAsset(
            id: "same", contentHash: "h2", relativePath: "p2",
            originalFilename: "f2", type: .image, durationMicroseconds: 0,
            width: 200, height: 200, fileSize: 0, importedAt: Self.fixedDate
        )
        #expect(a == b)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let asset = MediaAsset(
            id: "ma-codec",
            contentHash: "codec123",
            relativePath: "media/test.mp4",
            originalFilename: "test.mp4",
            type: .video,
            durationMicroseconds: 5_000_000,
            frameRate: .fps29_97,
            width: 3840,
            height: 2160,
            codec: "hevc",
            audioSampleRate: 44100,
            audioChannels: 1,
            fileSize: 100_000_000,
            importedAt: Self.fixedDate,
            isFavorite: true,
            colorTags: [.green],
            textTags: ["vacation"],
            colorSpace: "HDR10",
            bitDepth: 10,
            importSource: .camera
        )
        let data = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(MediaAsset.self, from: data)
        #expect(decoded.id == asset.id)
        #expect(decoded.contentHash == asset.contentHash)
        #expect(decoded.relativePath == asset.relativePath)
        #expect(decoded.type == .video)
        #expect(decoded.frameRate == .fps29_97)
        #expect(decoded.width == 3840)
        #expect(decoded.height == 2160)
        #expect(decoded.codec == "hevc")
        #expect(decoded.audioSampleRate == 44100)
        #expect(decoded.audioChannels == 1)
        #expect(decoded.isFavorite == true)
        #expect(decoded.colorTags == [.green])
        #expect(decoded.textTags == ["vacation"])
        #expect(decoded.colorSpace == "HDR10")
        #expect(decoded.bitDepth == 10)
        #expect(decoded.importSource == .camera)
    }

    @Test("Codable roundtrip with nil optionals")
    func codableNilOptionals() throws {
        let asset = MediaAsset(
            id: "ma-nil",
            contentHash: "h",
            relativePath: "p",
            originalFilename: "f",
            type: .image,
            durationMicroseconds: 0,
            width: 100,
            height: 100,
            fileSize: 1000,
            importedAt: Self.fixedDate
        )
        let data = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(MediaAsset.self, from: data)
        #expect(decoded.frameRate == nil)
        #expect(decoded.codec == nil)
        #expect(decoded.audioSampleRate == nil)
        #expect(decoded.audioChannels == nil)
        #expect(decoded.lastKnownAbsolutePath == nil)
        #expect(decoded.lastVerifiedAt == nil)
        #expect(decoded.colorSpace == nil)
        #expect(decoded.bitDepth == nil)
        #expect(decoded.importSource == nil)
    }
}
