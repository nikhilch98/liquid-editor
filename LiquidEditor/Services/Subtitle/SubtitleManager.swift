// SubtitleManager.swift
// LiquidEditor
//
// Subtitle import/export service.
//
// Parses SRT and VTT subtitle files into TextClip instances
// and exports subtitle clips back to SRT/VTT format.
//

import Foundation
import os

// MARK: - SubtitleManager

/// Service for importing and exporting subtitle files.
///
/// Supports SRT (SubRip Text) and WebVTT formats.
/// Implements lenient parsing that skips malformed entries
/// rather than failing the entire import.
///
/// Uses `enum` as a pure namespace (no instances needed).
enum SubtitleManager {

    /// Logger for subtitle operations.
    private static let logger = Logger(subsystem: "LiquidEditor", category: "SubtitleManager")

    // MARK: - Default Style

    /// Default style for subtitles (white text with black outline).
    static let defaultSubtitleStyle = TextOverlayStyle(
        fontSize: 32.0,
        fontWeight: .w600,
        outline: TextOutlineStyle(
            color: .fromARGB32(0xFF00_0000),
            width: 1.5
        )
    )

    // MARK: - SRT Import

    /// Parse SRT content and return a list of ``TextClip`` instances.
    ///
    /// Each subtitle entry becomes a ``TextClip`` with `isSubtitle: true`,
    /// positioned at bottom-center (0.5, 0.85).
    ///
    /// Edge cases handled:
    /// - UTF-8 BOM at file start
    /// - Missing blank lines between entries
    /// - HTML formatting tags (stripped)
    /// - Non-sequential indices (re-indexed)
    /// - Empty entries (skipped)
    static func importSRT(_ srtContent: String, style: TextOverlayStyle? = nil) -> [TextClip] {
        // Validate input
        guard !srtContent.isEmpty else {
            logger.warning("Attempted to import empty SRT content")
            return []
        }

        let effectiveStyle = style ?? defaultSubtitleStyle
        let entries = parseSRT(srtContent)

        if entries.isEmpty {
            logger.info("No valid subtitle entries found in SRT content")
        }

        return entriesToClips(entries, style: effectiveStyle)
    }

    // MARK: - VTT Import

    /// Parse VTT content and return a list of ``TextClip`` instances.
    ///
    /// The content must start with the "WEBVTT" header.
    /// NOTE and STYLE blocks are skipped.
    static func importVTT(_ vttContent: String, style: TextOverlayStyle? = nil) -> [TextClip] {
        // Validate input
        guard !vttContent.isEmpty else {
            logger.warning("Attempted to import empty VTT content")
            return []
        }

        guard vttContent.hasPrefix("WEBVTT") else {
            logger.warning("VTT content missing WEBVTT header")
            return []
        }

        let effectiveStyle = style ?? defaultSubtitleStyle
        let entries = parseVTT(vttContent)

        if entries.isEmpty {
            logger.info("No valid subtitle entries found in VTT content")
        }

        return entriesToClips(entries, style: effectiveStyle)
    }

    // MARK: - SRT Export

    /// Export text clips to SRT format.
    ///
    /// - Parameters:
    ///   - clips: The subtitle clips to export.
    ///   - startTimes: Map of clip ID to absolute start time in microseconds.
    /// - Returns: SRT formatted string.
    static func exportSRT(clips: [TextClip], startTimes: [String: Int64]) -> String {
        let sortedClips = sortClipsByStartTime(clips, startTimes: startTimes)
        var result = ""

        for (i, clip) in sortedClips.enumerated() {
            let start = startTimes[clip.id] ?? 0
            let end = start + clip.durationMicroseconds

            result += "\(i + 1)\n"
            result += "\(formatSRTTime(start)) --> \(formatSRTTime(end))\n"
            result += "\(clip.text)\n"
            result += "\n"
        }

        return result
    }

    // MARK: - VTT Export

    /// Export text clips to WebVTT format.
    ///
    /// - Parameters:
    ///   - clips: The subtitle clips to export.
    ///   - startTimes: Map of clip ID to absolute start time in microseconds.
    /// - Returns: WebVTT formatted string.
    static func exportVTT(clips: [TextClip], startTimes: [String: Int64]) -> String {
        let sortedClips = sortClipsByStartTime(clips, startTimes: startTimes)
        var result = "WEBVTT\n\n"

        for clip in sortedClips {
            let start = startTimes[clip.id] ?? 0
            let end = start + clip.durationMicroseconds

            result += "\(formatVTTTime(start)) --> \(formatVTTTime(end))\n"
            result += "\(clip.text)\n"
            result += "\n"
        }

        return result
    }

    // MARK: - HTML Tag Stripping

    /// Strip HTML tags from subtitle text (e.g., `<b>`, `<i>`, `<u>`).
    static func stripHtmlTags(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
    }

    // MARK: - Block Splitting

    /// Split content into blocks separated by blank lines.
    static func splitIntoBlocks(_ content: String) -> [String] {
        var blocks: [String] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var currentBlock: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock.joined(separator: "\n"))
                    currentBlock.removeAll()
                }
            } else {
                currentBlock.append(line)
            }
        }

        if !currentBlock.isEmpty {
            blocks.append(currentBlock.joined(separator: "\n"))
        }

        return blocks
    }
}

// MARK: - Private Helpers

private extension SubtitleManager {

    // MARK: SRT Parsing

    /// Parse SRT content into intermediate ``SubtitleEntry`` objects.
    static func parseSRT(_ content: String) -> [SubtitleEntry] {
        var cleaned = content

        // Remove UTF-8 BOM if present
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned = String(cleaned.dropFirst())
        }

        // Normalize line endings
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = splitIntoBlocks(cleaned)
        var entries: [SubtitleEntry] = []
        var skippedCount = 0

        for (i, block) in blocks.enumerated() {
            if let entry = parseSRTBlock(block, fallbackIndex: i + 1), entry.isValid {
                entries.append(entry)
            } else if !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                skippedCount += 1
            }
        }

        if skippedCount > 0 {
            logger.info("Skipped \(skippedCount) malformed SRT entries during import")
        }

        // Re-index sequentially
        return entries.enumerated().map { index, entry in
            entry.with(index: index + 1)
        }
    }

    /// Parse a single SRT block (index + timestamp + text).
    static func parseSRTBlock(_ block: String, fallbackIndex: Int) -> SubtitleEntry? {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return nil }

        // Find the timestamp line (contains -->)
        var timestampLineIndex = -1
        for (i, line) in lines.enumerated() {
            if line.contains("-->") {
                timestampLineIndex = i
                break
            }
        }

        guard timestampLineIndex >= 0 else { return nil }

        // Parse timestamps
        guard let timestamps = parseSRTTimestampLine(lines[timestampLineIndex]) else {
            return nil
        }

        // Parse index (line before timestamp, if it exists and is a number)
        var index = fallbackIndex
        if timestampLineIndex > 0,
           let parsed = Int(lines[timestampLineIndex - 1].trimmingCharacters(in: .whitespaces)) {
            index = parsed
        }

        // Collect text lines (everything after timestamp line)
        let textLines = lines.suffix(from: timestampLineIndex + 1)
            .map { stripHtmlTags($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }

        guard !textLines.isEmpty else { return nil }

        return SubtitleEntry(
            index: index,
            startMicros: timestamps.start,
            endMicros: timestamps.end,
            text: textLines.joined(separator: "\n")
        )
    }

    /// Parse SRT timestamp line: "HH:MM:SS,mmm --> HH:MM:SS,mmm".
    static func parseSRTTimestampLine(_ line: String) -> (start: TimeMicros, end: TimeMicros)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        guard let start = parseSRTTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseSRTTimestamp(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        guard end > start else { return nil }

        return (start: start, end: end)
    }

    /// Parse SRT timestamp: "HH:MM:SS,mmm" -> microseconds.
    ///
    /// Also accepts dots instead of commas (common variant).
    static func parseSRTTimestamp(_ timestamp: String) -> TimeMicros? {
        // Normalize comma to dot
        let normalized = timestamp.replacingOccurrences(of: ",", with: ".")

        // Try full format: HH:MM:SS.mmm
        if let result = parseFullTimestamp(normalized) {
            return result
        }

        // Try short format: MM:SS.mmm
        if let result = parseShortTimestamp(normalized) {
            return result
        }

        return nil
    }

    // MARK: VTT Parsing

    /// Parse VTT content into intermediate ``SubtitleEntry`` objects.
    static func parseVTT(_ content: String) -> [SubtitleEntry] {
        var cleaned = content

        // Remove UTF-8 BOM
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned = String(cleaned.dropFirst())
        }

        // Normalize line endings
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Must start with "WEBVTT"
        let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var startLine = 0
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("WEBVTT") {
                startLine = i + 1
                break
            }
        }

        // Skip NOTE blocks, STYLE blocks, and blank lines
        let cueContent = lines.suffix(from: startLine).joined(separator: "\n")
        let blocks = splitIntoBlocks(cueContent)

        var entries: [SubtitleEntry] = []
        var index = 1
        var skippedCount = 0

        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespaces)
            // Skip NOTE and STYLE blocks
            if trimmed.hasPrefix("NOTE") || trimmed.hasPrefix("STYLE") {
                continue
            }

            if let entry = parseVTTBlock(block, fallbackIndex: index), entry.isValid {
                entries.append(entry)
                index += 1
            } else if !trimmed.isEmpty {
                skippedCount += 1
            }
        }

        if skippedCount > 0 {
            logger.info("Skipped \(skippedCount) malformed VTT entries during import")
        }

        return entries
    }

    /// Parse a single VTT cue block.
    static func parseVTTBlock(_ block: String, fallbackIndex: Int) -> SubtitleEntry? {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return nil }

        // Find the timestamp line (contains -->)
        var timestampLineIndex = -1
        for (i, line) in lines.enumerated() {
            if line.contains("-->") {
                timestampLineIndex = i
                break
            }
        }

        guard timestampLineIndex >= 0 else { return nil }

        // Parse timestamps (VTT may have positioning after timestamps)
        let timestampParts = lines[timestampLineIndex].components(separatedBy: "-->")
        guard timestampParts.count == 2 else { return nil }

        // VTT can have settings after the end timestamp
        let endPartFull = timestampParts[1].trimmingCharacters(in: .whitespaces)
        let endPart = endPartFull.split(separator: " ", maxSplits: 1).first.map(String.init)
            ?? endPartFull

        guard let start = parseVTTTimestamp(timestampParts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseVTTTimestamp(endPart) else {
            return nil
        }

        guard end > start else { return nil }

        // Collect text lines (everything after timestamp line)
        let textLines = lines.suffix(from: timestampLineIndex + 1)
            .map { stripHtmlTags($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }

        guard !textLines.isEmpty else { return nil }

        return SubtitleEntry(
            index: fallbackIndex,
            startMicros: start,
            endMicros: end,
            text: textLines.joined(separator: "\n")
        )
    }

    /// Parse VTT timestamp: "HH:MM:SS.mmm" or "MM:SS.mmm" -> microseconds.
    static func parseVTTTimestamp(_ timestamp: String) -> TimeMicros? {
        // Full format: HH:MM:SS.mmm
        if let result = parseFullTimestamp(timestamp) {
            return result
        }

        // Short format: MM:SS.mmm
        if let result = parseShortTimestamp(timestamp) {
            return result
        }

        return nil
    }

    // MARK: Shared Timestamp Parsing

    /// Full timestamp regex pattern.
    private static let fullTimestampRegex = try! NSRegularExpression(
        pattern: #"^(\d+):(\d{2}):(\d{2})\.(\d{1,3})$"#
    )

    /// Short timestamp regex pattern.
    private static let shortTimestampRegex = try! NSRegularExpression(
        pattern: #"^(\d+):(\d{2})\.(\d{1,3})$"#
    )

    /// Parse full format timestamp: "HH:MM:SS.mmm" -> microseconds.
    static func parseFullTimestamp(_ timestamp: String) -> TimeMicros? {
        let range = NSRange(timestamp.startIndex..., in: timestamp)
        guard let match = fullTimestampRegex.firstMatch(in: timestamp, range: range),
              match.numberOfRanges == 5 else {
            return nil
        }

        guard let hoursRange = Range(match.range(at: 1), in: timestamp),
              let minutesRange = Range(match.range(at: 2), in: timestamp),
              let secondsRange = Range(match.range(at: 3), in: timestamp),
              let millisRange = Range(match.range(at: 4), in: timestamp) else {
            return nil
        }

        guard let hours = Int64(timestamp[hoursRange]),
              let minutes = Int64(timestamp[minutesRange]),
              let seconds = Int64(timestamp[secondsRange]) else {
            return nil
        }

        let milliStr = String(timestamp[millisRange]).padding(toLength: 3, withPad: "0", startingAt: 0)
        guard let millis = Int64(milliStr) else { return nil }

        return ((hours * 3600 + minutes * 60 + seconds) * 1000 + millis) * 1000
    }

    /// Parse short format timestamp: "MM:SS.mmm" -> microseconds.
    static func parseShortTimestamp(_ timestamp: String) -> TimeMicros? {
        let range = NSRange(timestamp.startIndex..., in: timestamp)
        guard let match = shortTimestampRegex.firstMatch(in: timestamp, range: range),
              match.numberOfRanges == 4 else {
            return nil
        }

        guard let minutesRange = Range(match.range(at: 1), in: timestamp),
              let secondsRange = Range(match.range(at: 2), in: timestamp),
              let millisRange = Range(match.range(at: 3), in: timestamp) else {
            return nil
        }

        guard let minutes = Int64(timestamp[minutesRange]),
              let seconds = Int64(timestamp[secondsRange]) else {
            return nil
        }

        let milliStr = String(timestamp[millisRange]).padding(toLength: 3, withPad: "0", startingAt: 0)
        guard let millis = Int64(milliStr) else { return nil }

        return ((minutes * 60 + seconds) * 1000 + millis) * 1000
    }

    // MARK: Time Formatting

    /// Format microseconds to SRT time format: "HH:MM:SS,mmm".
    static func formatSRTTime(_ micros: TimeMicros) -> String {
        let totalMillis = micros / 1000
        let millis = totalMillis % 1000
        let totalSeconds = totalMillis / 1000
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(format: "%02lld:%02lld:%02lld,%03lld", hours, minutes, seconds, millis)
    }

    /// Format microseconds to VTT time format: "HH:MM:SS.mmm".
    static func formatVTTTime(_ micros: TimeMicros) -> String {
        let totalMillis = micros / 1000
        let millis = totalMillis % 1000
        let totalSeconds = totalMillis / 1000
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(format: "%02lld:%02lld:%02lld.%03lld", hours, minutes, seconds, millis)
    }

    // MARK: Clip Conversion

    /// Convert subtitle entries to text clips.
    static func entriesToClips(
        _ entries: [SubtitleEntry],
        style: TextOverlayStyle
    ) -> [TextClip] {
        entries.map { entry in
            TextClip(
                durationMicroseconds: entry.durationMicros,
                text: entry.text,
                style: entry.styleOverride ?? style,
                positionX: 0.5,
                positionY: 0.85, // Bottom center
                enterDurationMicros: 0,
                exitDurationMicros: 0,
                isSubtitle: true
            )
        }
    }

    /// Sort clips by their start time on the timeline.
    static func sortClipsByStartTime(
        _ clips: [TextClip],
        startTimes: [String: Int64]
    ) -> [TextClip] {
        clips.sorted { a, b in
            let aStart = startTimes[a.id] ?? 0
            let bStart = startTimes[b.id] ?? 0
            return aStart < bStart
        }
    }
}
