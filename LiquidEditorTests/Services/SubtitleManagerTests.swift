// SubtitleManagerTests.swift
// LiquidEditorTests
//
// Tests for SubtitleManager SRT/VTT import and export.

import Testing
@testable import LiquidEditor

// MARK: - SRT Import Tests

@Suite("SubtitleManager SRT Import")
struct SubtitleManagerSRTImportTests {

    @Test("imports basic SRT entry")
    func importBasicSRTEntry() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Hello, world!
        """

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Hello, world!")
        #expect(clips[0].isSubtitle == true)
        #expect(clips[0].durationMicroseconds == 3_000_000)
        #expect(clips[0].positionX == 0.5)
        #expect(clips[0].positionY == 0.85)
    }

    @Test("imports multiple SRT entries")
    func importMultipleSRTEntries() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        First subtitle

        2
        00:00:05,000 --> 00:00:08,500
        Second subtitle

        3
        00:00:10,000 --> 00:00:12,000
        Third subtitle
        """

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 3)
        #expect(clips[0].text == "First subtitle")
        #expect(clips[1].text == "Second subtitle")
        #expect(clips[2].text == "Third subtitle")
        #expect(clips[1].durationMicroseconds == 3_500_000)
    }

    @Test("handles UTF-8 BOM")
    func handleUTF8BOM() {
        let srt = "\u{FEFF}1\n00:00:01,000 --> 00:00:04,000\nBOM test"

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "BOM test")
    }

    @Test("parses full format timestamp HH:MM:SS,mmm")
    func parseFullFormatTimestamp() {
        let srt = """
        1
        01:23:45,678 --> 01:23:50,000
        Timed text
        """

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 1)
        // 1*3600 + 23*60 + 45 = 5025 seconds, + 678ms = 5025678ms = 5025678000us
        let expectedDuration: Int64 = (50_000 - 45_678) * 1000  // 4322ms = 4_322_000us
        #expect(clips[0].durationMicroseconds == expectedDuration)
    }

    @Test("parses short format timestamp MM:SS,mmm")
    func parseShortFormatTimestamp() {
        let srt = """
        1
        01:30,000 --> 01:35,500
        Short format
        """

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 1)
        // 1:30.000 = 90s = 90000ms, 1:35.500 = 95.5s = 95500ms
        // Duration = 5500ms = 5_500_000us
        #expect(clips[0].durationMicroseconds == 5_500_000)
    }

    @Test("accepts dot separator in SRT timestamps")
    func parseDotSeparatorInSRT() {
        let srt = """
        1
        00:00:01.000 --> 00:00:04.000
        Dot separator
        """

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Dot separator")
        #expect(clips[0].durationMicroseconds == 3_000_000)
    }

    @Test("skips malformed entries leniently")
    func skipMalformedEntries() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Valid entry

        2
        INVALID TIMESTAMP LINE
        Bad entry

        3
        00:00:05,000 --> 00:00:08,000
        Another valid entry
        """

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 2)
        #expect(clips[0].text == "Valid entry")
        #expect(clips[1].text == "Another valid entry")
    }

    @Test("strips HTML tags from text")
    func stripHTMLTags() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        <b>Bold</b> and <i>italic</i> text
        """

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Bold and italic text")
    }

    @Test("re-indexes entries sequentially")
    func reIndexSequentially() {
        let srt = """
        5
        00:00:01,000 --> 00:00:02,000
        First

        10
        00:00:03,000 --> 00:00:04,000
        Second

        99
        00:00:05,000 --> 00:00:06,000
        Third
        """

        let clips = SubtitleManager.importSRT(srt)

        // Re-indexing happens internally; clips should be in order
        #expect(clips.count == 3)
        #expect(clips[0].text == "First")
        #expect(clips[1].text == "Second")
        #expect(clips[2].text == "Third")
    }

    @Test("handles multi-line subtitle text")
    func handleMultiLineText() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Line one
        Line two
        """

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Line one\nLine two")
    }

    @Test("applies custom style when provided")
    func applyCustomStyle() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Styled text
        """

        let customStyle = TextOverlayStyle(fontSize: 64.0, fontWeight: .w900)
        let clips = SubtitleManager.importSRT(srt, style: customStyle)

        #expect(clips.count == 1)
        #expect(clips[0].style.fontSize == 64.0)
        #expect(clips[0].style.fontWeight == .w900)
    }

    @Test("returns empty array for empty input")
    func emptyInputReturnsEmptyArray() {
        let clips = SubtitleManager.importSRT("")
        #expect(clips.isEmpty)
    }

    @Test("skips entries where end time equals start time")
    func skipZeroDuration() {
        let srt = """
        1
        00:00:01,000 --> 00:00:01,000
        Zero duration

        2
        00:00:02,000 --> 00:00:05,000
        Valid
        """

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Valid")
    }

    @Test("handles Windows-style line endings")
    func handleWindowsLineEndings() {
        let srt = "1\r\n00:00:01,000 --> 00:00:04,000\r\nWindows text\r\n"

        let clips = SubtitleManager.importSRT(srt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Windows text")
    }
}

// MARK: - VTT Import Tests

@Suite("SubtitleManager VTT Import")
struct SubtitleManagerVTTImportTests {

    @Test("imports basic VTT entry")
    func importBasicVTTEntry() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        Hello VTT!
        """

        let clips = SubtitleManager.importVTT(vtt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Hello VTT!")
        #expect(clips[0].isSubtitle == true)
        #expect(clips[0].durationMicroseconds == 3_000_000)
    }

    @Test("requires WEBVTT header")
    func requireWEBVTTHeader() {
        let noHeader = """
        00:00:01.000 --> 00:00:04.000
        No header
        """

        // Without WEBVTT header, the parser rejects the content.
        let clips = SubtitleManager.importVTT(noHeader)

        // Content without WEBVTT header is rejected (returns empty).
        #expect(clips.isEmpty)
    }

    @Test("skips NOTE blocks")
    func skipNOTEBlocks() {
        let vtt = """
        WEBVTT

        NOTE
        This is a comment

        00:00:01.000 --> 00:00:04.000
        Actual subtitle
        """

        let clips = SubtitleManager.importVTT(vtt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Actual subtitle")
    }

    @Test("skips STYLE blocks")
    func skipSTYLEBlocks() {
        let vtt = """
        WEBVTT

        STYLE
        ::cue { color: white; }

        00:00:01.000 --> 00:00:04.000
        Styled subtitle
        """

        let clips = SubtitleManager.importVTT(vtt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Styled subtitle")
    }

    @Test("parses VTT short format MM:SS.mmm")
    func parseVTTShortFormat() {
        let vtt = """
        WEBVTT

        01:30.000 --> 01:35.500
        Short format
        """

        let clips = SubtitleManager.importVTT(vtt)

        #expect(clips.count == 1)
        #expect(clips[0].durationMicroseconds == 5_500_000)
    }

    @Test("ignores positioning settings after timestamp")
    func ignorePositioningSettings() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000 position:10% align:start
        Positioned subtitle
        """

        let clips = SubtitleManager.importVTT(vtt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "Positioned subtitle")
        #expect(clips[0].durationMicroseconds == 3_000_000)
    }

    @Test("imports multiple VTT cues")
    func importMultipleVTTCues() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        First cue

        00:00:05.000 --> 00:00:08.000
        Second cue
        """

        let clips = SubtitleManager.importVTT(vtt)

        #expect(clips.count == 2)
        #expect(clips[0].text == "First cue")
        #expect(clips[1].text == "Second cue")
    }

    @Test("returns empty array for empty VTT input")
    func emptyVTTInput() {
        let clips = SubtitleManager.importVTT("")
        #expect(clips.isEmpty)
    }

    @Test("handles VTT with cue identifiers")
    func handleCueIdentifiers() {
        let vtt = """
        WEBVTT

        intro
        00:00:01.000 --> 00:00:04.000
        With identifier
        """

        let clips = SubtitleManager.importVTT(vtt)

        #expect(clips.count == 1)
        #expect(clips[0].text == "With identifier")
    }
}

// MARK: - SRT Export Tests

@Suite("SubtitleManager SRT Export")
struct SubtitleManagerSRTExportTests {

    @Test("exports correct SRT format with sequential indices")
    func exportCorrectSRTFormat() {
        let clip1 = TextClip(
            id: "clip-1",
            durationMicroseconds: 3_000_000,
            text: "First subtitle",
            style: SubtitleManager.defaultSubtitleStyle,
            isSubtitle: true
        )
        let clip2 = TextClip(
            id: "clip-2",
            durationMicroseconds: 2_000_000,
            text: "Second subtitle",
            style: SubtitleManager.defaultSubtitleStyle,
            isSubtitle: true
        )

        let startTimes: [String: Int64] = [
            "clip-1": 1_000_000,
            "clip-2": 5_000_000,
        ]

        let result = SubtitleManager.exportSRT(clips: [clip1, clip2], startTimes: startTimes)

        #expect(result.contains("1\n"))
        #expect(result.contains("2\n"))
        #expect(result.contains("00:00:01,000 --> 00:00:04,000"))
        #expect(result.contains("00:00:05,000 --> 00:00:07,000"))
        #expect(result.contains("First subtitle"))
        #expect(result.contains("Second subtitle"))
    }

    @Test("exports SRT with comma separator")
    func exportSRTComma() {
        let clip = TextClip(
            id: "clip-1",
            durationMicroseconds: 1_500_000,
            text: "Test",
            style: SubtitleManager.defaultSubtitleStyle,
            isSubtitle: true
        )

        let startTimes: [String: Int64] = ["clip-1": 500_000]

        let result = SubtitleManager.exportSRT(clips: [clip], startTimes: startTimes)

        #expect(result.contains("00:00:00,500 --> 00:00:02,000"))
    }

    @Test("sorts clips by start time in export")
    func sortClipsByStartTime() {
        let clipA = TextClip(
            id: "a",
            durationMicroseconds: 1_000_000,
            text: "Second",
            style: SubtitleManager.defaultSubtitleStyle,
            isSubtitle: true
        )
        let clipB = TextClip(
            id: "b",
            durationMicroseconds: 1_000_000,
            text: "First",
            style: SubtitleManager.defaultSubtitleStyle,
            isSubtitle: true
        )

        let startTimes: [String: Int64] = [
            "a": 5_000_000,
            "b": 1_000_000,
        ]

        let result = SubtitleManager.exportSRT(clips: [clipA, clipB], startTimes: startTimes)

        // "First" should appear before "Second" in output
        let firstIndex = result.range(of: "First")!.lowerBound
        let secondIndex = result.range(of: "Second")!.lowerBound
        #expect(firstIndex < secondIndex)
    }
}

// MARK: - VTT Export Tests

@Suite("SubtitleManager VTT Export")
struct SubtitleManagerVTTExportTests {

    @Test("exports with WEBVTT header")
    func exportWithHeader() {
        let clip = TextClip(
            id: "clip-1",
            durationMicroseconds: 3_000_000,
            text: "Hello",
            style: SubtitleManager.defaultSubtitleStyle,
            isSubtitle: true
        )

        let startTimes: [String: Int64] = ["clip-1": 1_000_000]

        let result = SubtitleManager.exportVTT(clips: [clip], startTimes: startTimes)

        #expect(result.hasPrefix("WEBVTT\n\n"))
    }

    @Test("exports VTT with dot separator and no indices")
    func exportVTTDotSeparator() {
        let clip = TextClip(
            id: "clip-1",
            durationMicroseconds: 1_500_000,
            text: "Test",
            style: SubtitleManager.defaultSubtitleStyle,
            isSubtitle: true
        )

        let startTimes: [String: Int64] = ["clip-1": 500_000]

        let result = SubtitleManager.exportVTT(clips: [clip], startTimes: startTimes)

        #expect(result.contains("00:00:00.500 --> 00:00:02.000"))
        // Should NOT contain sequential index lines (unlike SRT)
        #expect(!result.contains("1\n00:00:00.500"))
    }

    @Test("exports empty clips as header only")
    func exportEmptyClips() {
        let result = SubtitleManager.exportVTT(clips: [], startTimes: [:])
        #expect(result == "WEBVTT\n\n")
    }
}

// MARK: - Roundtrip Tests

@Suite("SubtitleManager Roundtrip")
struct SubtitleManagerRoundtripTests {

    @Test("SRT import then export preserves content")
    func srtRoundtrip() {
        let originalSRT = """
        1
        00:00:01,000 --> 00:00:04,000
        First subtitle

        2
        00:00:05,000 --> 00:00:08,500
        Second subtitle

        """

        let clips = SubtitleManager.importSRT(originalSRT)
        #expect(clips.count == 2)

        // Build start times from original data
        var startTimes: [String: Int64] = [:]
        startTimes[clips[0].id] = 1_000_000
        startTimes[clips[1].id] = 5_000_000

        let exported = SubtitleManager.exportSRT(clips: clips, startTimes: startTimes)

        #expect(exported.contains("00:00:01,000 --> 00:00:04,000"))
        #expect(exported.contains("First subtitle"))
        #expect(exported.contains("00:00:05,000 --> 00:00:08,500"))
        #expect(exported.contains("Second subtitle"))
    }
}

// MARK: - Default Style Tests

@Suite("SubtitleManager Default Style")
struct SubtitleManagerDefaultStyleTests {

    @Test("default subtitle style has correct values")
    func defaultStyleValues() {
        let style = SubtitleManager.defaultSubtitleStyle

        #expect(style.fontSize == 32.0)
        #expect(style.fontWeight == .w600)
        #expect(style.color == .fromARGB32(0xFFFF_FFFF))  // white (default)
        #expect(style.outline != nil)
        #expect(style.outline?.color == .fromARGB32(0xFF00_0000))  // black
        #expect(style.outline?.width == 1.5)
    }
}

// MARK: - Helper Method Tests

@Suite("SubtitleManager Helpers")
struct SubtitleManagerHelperTests {

    @Test("stripHtmlTags removes HTML tags")
    func stripHtmlTagsRemovesTags() {
        #expect(SubtitleManager.stripHtmlTags("<b>bold</b>") == "bold")
        #expect(SubtitleManager.stripHtmlTags("<i>italic</i>") == "italic")
        #expect(SubtitleManager.stripHtmlTags("no tags") == "no tags")
        #expect(SubtitleManager.stripHtmlTags("<font color=\"red\">colored</font>") == "colored")
        #expect(SubtitleManager.stripHtmlTags("") == "")
    }

    @Test("splitIntoBlocks splits by blank lines")
    func splitIntoBlocksByBlankLines() {
        let content = "block1 line1\nblock1 line2\n\nblock2 line1\n\nblock3 line1"
        let blocks = SubtitleManager.splitIntoBlocks(content)

        #expect(blocks.count == 3)
        #expect(blocks[0] == "block1 line1\nblock1 line2")
        #expect(blocks[1] == "block2 line1")
        #expect(blocks[2] == "block3 line1")
    }

    @Test("splitIntoBlocks handles multiple consecutive blank lines")
    func splitIntoBlocksMultipleBlanks() {
        let content = "block1\n\n\n\nblock2"
        let blocks = SubtitleManager.splitIntoBlocks(content)

        #expect(blocks.count == 2)
        #expect(blocks[0] == "block1")
        #expect(blocks[1] == "block2")
    }

    @Test("splitIntoBlocks returns empty for empty input")
    func splitIntoBlocksEmpty() {
        let blocks = SubtitleManager.splitIntoBlocks("")
        #expect(blocks.isEmpty)
    }
}
