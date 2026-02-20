import Testing
import Foundation
@testable import LiquidEditor

@Suite("MediaDetailSheet Tests")
struct MediaDetailSheetTests {

    // MARK: - Duration Formatting

    @Suite("Duration Formatting")
    struct DurationFormattingTests {

        @Test("Zero duration returns --:--")
        func zeroDuration() {
            #expect(MediaDetailSheet.formatDuration(0) == "--:--")
        }

        @Test("60 seconds formats as 1:00")
        func oneMinute() {
            #expect(MediaDetailSheet.formatDuration(60_000_000) == "1:00")
        }

        @Test("90 seconds formats as 1:30")
        func ninetySeconds() {
            #expect(MediaDetailSheet.formatDuration(90_000_000) == "1:30")
        }

        @Test("3661 seconds formats as 1:01:01")
        func withHours() {
            #expect(MediaDetailSheet.formatDuration(3_661_000_000) == "1:01:01")
        }

        @Test("5 seconds formats as 0:05")
        func fiveSeconds() {
            #expect(MediaDetailSheet.formatDuration(5_000_000) == "0:05")
        }

        @Test("125 seconds formats as 2:05")
        func twoMinutesFive() {
            #expect(MediaDetailSheet.formatDuration(125_000_000) == "2:05")
        }
    }

    // MARK: - File Size Formatting

    @Suite("File Size Formatting")
    struct FileSizeFormattingTests {

        @Test("0 bytes formats as '0 bytes'")
        func zeroBytes() {
            #expect(MediaDetailSheet.formatFileSize(0) == "0 bytes")
        }

        @Test("500 bytes formats as '500 bytes'")
        func smallBytes() {
            #expect(MediaDetailSheet.formatFileSize(500) == "500 bytes")
        }

        @Test("2048 bytes formats as '2 KB'")
        func kilobytes() {
            #expect(MediaDetailSheet.formatFileSize(2048) == "2 KB")
        }

        @Test("5.5 MB formats correctly")
        func megabytes() {
            let size = 5_767_168 // ~5.5 MB
            let result = MediaDetailSheet.formatFileSize(size)
            #expect(result == "5.5 MB")
        }

        @Test("2.5 GB formats correctly")
        func gigabytes() {
            let size = 2_684_354_560 // ~2.5 GB
            let result = MediaDetailSheet.formatFileSize(size)
            #expect(result == "2.5 GB")
        }

        @Test("1024 bytes formats as KB not bytes")
        func boundaryKB() {
            let result = MediaDetailSheet.formatFileSize(1024)
            #expect(result == "1 KB")
        }

        @Test("1 MB formats correctly")
        func oneMB() {
            let result = MediaDetailSheet.formatFileSize(1_048_576)
            #expect(result == "1.0 MB")
        }

        @Test("1 GB formats correctly")
        func oneGB() {
            let result = MediaDetailSheet.formatFileSize(1_073_741_824)
            #expect(result == "1.0 GB")
        }
    }

    // MARK: - Channel Description

    @Suite("Channel Description")
    struct ChannelDescriptionTests {

        @Test("1 channel is Mono")
        func mono() {
            #expect(MediaDetailSheet.channelDescription(1) == "Mono")
        }

        @Test("2 channels is Stereo")
        func stereo() {
            #expect(MediaDetailSheet.channelDescription(2) == "Stereo")
        }

        @Test("6 channels is 5.1 Surround")
        func surround51() {
            #expect(MediaDetailSheet.channelDescription(6) == "5.1 Surround")
        }

        @Test("8 channels is 7.1 Surround")
        func surround71() {
            #expect(MediaDetailSheet.channelDescription(8) == "7.1 Surround")
        }

        @Test("4 channels shows generic format")
        func genericChannels() {
            #expect(MediaDetailSheet.channelDescription(4) == "4 ch")
        }

        @Test("0 channels shows generic format")
        func zeroChannels() {
            #expect(MediaDetailSheet.channelDescription(0) == "0 ch")
        }
    }

    // MARK: - Sample Rate Formatting

    @Suite("Sample Rate Formatting")
    struct SampleRateFormattingTests {

        @Test("48000 Hz formats as 48 kHz")
        func standard48k() {
            #expect(MediaDetailSheet.formatSampleRate(48000) == "48 kHz")
        }

        @Test("44100 Hz formats as 44.1 kHz")
        func standard44k() {
            #expect(MediaDetailSheet.formatSampleRate(44100) == "44.1 kHz")
        }

        @Test("96000 Hz formats as 96 kHz")
        func highRes96k() {
            #expect(MediaDetailSheet.formatSampleRate(96000) == "96 kHz")
        }

        @Test("22050 Hz formats as 22.1 kHz")
        func lowRate() {
            #expect(MediaDetailSheet.formatSampleRate(22050) == "22.1 kHz")
        }

        @Test("500 Hz formats as 500 Hz")
        func subKHz() {
            #expect(MediaDetailSheet.formatSampleRate(500) == "500 Hz")
        }

        @Test("0 Hz formats as 0 Hz")
        func zeroRate() {
            #expect(MediaDetailSheet.formatSampleRate(0) == "0 Hz")
        }
    }

    // MARK: - Import Source Formatting

    @Suite("Import Source Formatting")
    struct ImportSourceFormattingTests {

        @Test("Photo Library source")
        func photoLibrary() {
            #expect(MediaDetailSheet.formatSource(.photoLibrary) == "Photo Library")
        }

        @Test("Files source")
        func files() {
            #expect(MediaDetailSheet.formatSource(.files) == "Files")
        }

        @Test("Camera source")
        func camera() {
            #expect(MediaDetailSheet.formatSource(.camera) == "Camera")
        }

        @Test("URL source")
        func urlSource() {
            #expect(MediaDetailSheet.formatSource(.url) == "URL")
        }

        @Test("Google Drive source")
        func googleDrive() {
            #expect(MediaDetailSheet.formatSource(.googleDrive) == "Google Drive")
        }

        @Test("Dropbox source")
        func dropbox() {
            #expect(MediaDetailSheet.formatSource(.dropbox) == "Dropbox")
        }
    }

    // MARK: - TagColor to Color Mapping

    @Suite("Tag Color Mapping")
    struct TagColorMappingTests {

        @Test("All tag colors return non-nil SwiftUI colors")
        func allTagColorsMap() {
            for tag in TagColor.allCases {
                // Just verify no crashes and coverage
                let _ = MediaDetailSheet.tagColorToSwiftUI(tag)
            }
        }
    }

    // MARK: - MediaAsset Properties

    @Suite("MediaAsset Display Properties")
    struct MediaAssetPropertiesTests {

        private func makeAsset(
            type: MediaType = .video,
            audioChannels: Int? = 2
        ) -> MediaAsset {
            MediaAsset(
                id: "test-1",
                contentHash: "abc123def456",
                relativePath: "Media/test.mp4",
                originalFilename: "test.mp4",
                type: type,
                durationMicroseconds: 10_000_000,
                width: 1920,
                height: 1080,
                audioChannels: audioChannels,
                fileSize: 50_000_000,
                importedAt: Date()
            )
        }

        @Test("Video asset isVideo")
        func videoType() {
            let asset = makeAsset(type: .video)
            #expect(asset.isVideo)
            #expect(!asset.isAudio)
            #expect(!asset.isImage)
        }

        @Test("Audio asset isAudio")
        func audioType() {
            let asset = makeAsset(type: .audio)
            #expect(asset.isAudio)
            #expect(!asset.isVideo)
        }

        @Test("Image asset isImage")
        func imageType() {
            let asset = makeAsset(type: .image)
            #expect(asset.isImage)
        }

        @Test("Video with audio channels hasAudio")
        func hasAudio() {
            let asset = makeAsset(type: .video, audioChannels: 2)
            #expect(asset.hasAudio)
        }

        @Test("Video without audio channels does not hasAudio")
        func noAudio() {
            let asset = makeAsset(type: .video, audioChannels: nil)
            #expect(!asset.hasAudio)
        }

        @Test("Favorite toggle via copyWith")
        func toggleFavorite() {
            let asset = makeAsset()
            #expect(!asset.isFavorite)
            let favorited = asset.with(isFavorite: true)
            #expect(favorited.isFavorite)
        }
    }

    // MARK: - Date Formatting

    @Suite("Date Formatting")
    struct DateFormattingTests {

        @Test("Date formats with month name")
        func dateFormat() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = DateComponents(
                calendar: calendar,
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 1,
                day: 15,
                hour: 14,
                minute: 30
            )
            let date = calendar.date(from: components)!
            let result = MediaDetailSheet.formatDate(date)
            #expect(result.contains("Jan"))
            #expect(result.contains("15"))
            #expect(result.contains("2026"))
        }
    }
}
