/// LUT file parser for .cube, .3dl, and .vlt formats.
///
/// Parses Look-Up Table files and provides validation + metadata extraction.
/// Actual LUT cube data loading for CIFilter application is handled by
/// `ColorGradingPipeline`. This parser performs validation, format detection,
/// and metadata extraction for import workflows.
///
/// Supported formats:
/// - `.cube` (Adobe / DaVinci Resolve) - text-based, RGB float triplets
/// - `.3dl` (Autodesk) - text-based, RGB integer triplets
/// - `.vlt` (Panasonic VariCam) - text-based, similar to .cube
///
/// Usage: All methods are static on a caseless enum (no instances needed).

import Foundation

// MARK: - ParsedLUT

/// Metadata extracted from a LUT file after parsing.
struct ParsedLUT: Equatable, Sendable {
    /// LUT title from the file header (or a default).
    let title: String

    /// LUT dimension (e.g., 17 for 17x17x17, 33 for 33x33x33).
    let dimension: Int

    /// Number of RGB data entries found.
    let entryCount: Int

    /// Whether the file passed validation.
    let isValid: Bool

    /// Error message if validation failed.
    let error: String?
}

// MARK: - LUTParseError

/// Error types for LUT parsing failures.
enum LUTParseError: String, Sendable, CaseIterable {
    /// File not found at path.
    case fileNotFound

    /// File is empty (zero bytes).
    case emptyFile

    /// Missing or invalid dimension header.
    case invalidDimension

    /// Data line count does not match expected dimension^3.
    case dataMismatch

    /// A data line could not be parsed.
    case malformedData

    /// 1D LUT files are not supported.
    case unsupported1D

    /// File exceeds the 50 MB size limit.
    case fileTooLarge

    /// LUT dimension exceeds the maximum of 65.
    case dimensionTooLarge

    /// File extension is not a recognized LUT format.
    case unknownFormat
}

// MARK: - LUTParseResult

/// Result of a LUT parse operation.
struct LUTParseResult: Sendable, Error {
    /// The parsed LUT metadata, if successful.
    let lut: ParsedLUT?

    /// Error type, if failed.
    let error: LUTParseError?

    /// Human-readable error message.
    let errorMessage: String?

    /// Whether parsing succeeded.
    var isSuccess: Bool { lut != nil }

    /// Whether parsing failed.
    var isFailure: Bool { error != nil }

    /// Create a successful result.
    static func success(_ lut: ParsedLUT) -> LUTParseResult {
        LUTParseResult(lut: lut, error: nil, errorMessage: nil)
    }

    /// Create a failure result.
    static func failure(_ error: LUTParseError, _ message: String) -> LUTParseResult {
        LUTParseResult(lut: nil, error: error, errorMessage: message)
    }
}

// MARK: - LUTParser

/// Stateless parser for LUT file formats.
///
/// All methods are static. Use the caseless enum pattern (no instances).
enum LUTParser {

    /// Maximum file size: 50 MB.
    static let maxFileSize: Int = 50 * 1024 * 1024

    /// Maximum LUT dimension supported.
    static let maxDimension: Int = 65

    // MARK: - Public API

    /// Detect file format from extension and parse accordingly.
    ///
    /// Supports `.cube`, `.3dl`, and `.vlt` extensions.
    static func parseFile(at path: String) -> LUTParseResult {
        let lowerPath = path.lowercased()
        if lowerPath.hasSuffix(".cube") {
            return parseCubeFile(at: path)
        } else if lowerPath.hasSuffix(".3dl") {
            return parse3dlFile(at: path)
        } else if lowerPath.hasSuffix(".vlt") {
            return parseVLTFile(at: path)
        } else {
            return .failure(.unknownFormat, "Unsupported LUT format. Use .cube, .3dl, or .vlt files.")
        }
    }

    /// Validate and extract metadata from a .cube file at path.
    static func parseCubeFile(at path: String) -> LUTParseResult {
        switch readFileContent(at: path) {
        case .success(let content):
            return parseCubeContent(content)
        case .failure(let result):
            return result
        }
    }

    /// Parse .cube format content string directly.
    static func parseCubeContent(_ content: String) -> LUTParseResult {
        if content.isEmpty {
            return .failure(.emptyFile, "LUT content is empty")
        }

        var title = ""
        var dimension = 0
        var dataLineCount = 0
        var has1DSize = false

        let lines = content.components(separatedBy: .newlines)

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("TITLE") {
                title = String(trimmed.dropFirst(5))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
            } else if trimmed.hasPrefix("LUT_1D_SIZE") {
                has1DSize = true
            } else if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
                if parts.count >= 2, let dim = Int(parts.last!) {
                    dimension = dim
                } else {
                    return .failure(.invalidDimension,
                                    "Invalid LUT_3D_SIZE value on line \(lineIndex + 1)")
                }
            } else if trimmed.hasPrefix("DOMAIN_MIN") || trimmed.hasPrefix("DOMAIN_MAX") {
                continue
            } else {
                // Attempt to parse as a data line (3 floats).
                let components = trimmed.split(whereSeparator: { $0.isWhitespace })
                let values = components.compactMap { Double($0) }

                // A valid data line must have exactly 3 parseable float components.
                if components.count >= 3 && values.count == components.count {
                    if values.count != 3 {
                        return .failure(.malformedData,
                                        "Expected 3 values on data line \(lineIndex + 1), found \(values.count)")
                    }
                    // Validate value range (standard .cube uses 0.0-1.0).
                    for value in values {
                        if value < -0.1 || value > 1.1 {
                            return .failure(.malformedData,
                                            "Value \(value) out of expected range [0.0, 1.0] on line \(lineIndex + 1)")
                        }
                    }
                    dataLineCount += 1
                } else if !components.isEmpty {
                    // Non-empty line that is not a recognized header and has unparseable values.
                    let allNumbers = components.allSatisfy { Double($0) != nil || Int($0) != nil }
                    if allNumbers {
                        return .failure(.malformedData,
                                        "Malformed data line \(lineIndex + 1): '\(trimmed)'")
                    }
                    // Unrecognized header lines are skipped (some .cube files have vendor extensions).
                }
            }
        }

        if dimension == 0 && !has1DSize {
            return .failure(.invalidDimension, "Missing LUT_3D_SIZE header in .cube file")
        }

        return validateParsedCube(
            title: title.isEmpty ? "Untitled LUT" : title,
            dimension: dimension,
            dataLineCount: dataLineCount,
            has1DSize: has1DSize
        )
    }

    /// Validate and extract metadata from a .3dl file at path.
    static func parse3dlFile(at path: String) -> LUTParseResult {
        switch readFileContent(at: path) {
        case .success(let content):
            return parse3dlContent(content)
        case .failure(let result):
            return result
        }
    }

    /// Parse .3dl format content string directly.
    static func parse3dlContent(_ content: String) -> LUTParseResult {
        if content.isEmpty {
            return .failure(.emptyFile, ".3dl content is empty")
        }

        var dataLineCount = 0
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // .3dl files have integer triplets (0-1023 or 0-4095)
            let values = trimmed.split(whereSeparator: { $0.isWhitespace })
                .filter { Int($0) != nil }
            if values.count >= 3 {
                dataLineCount += 1
            }
        }

        // Common .3dl dimensions: 17, 33, 65
        var dimension = 0
        for d in [17, 33, 65] {
            if dataLineCount == d * d * d {
                dimension = d
                break
            }
        }

        if dimension == 0 {
            return .failure(.dataMismatch,
                            "Cannot determine .3dl dimension from \(dataLineCount) data lines")
        }

        return .success(ParsedLUT(
            title: "Imported 3DL",
            dimension: dimension,
            entryCount: dataLineCount,
            isValid: true,
            error: nil
        ))
    }

    /// Validate and extract metadata from a .vlt (Panasonic VariCam) file at path.
    static func parseVLTFile(at path: String) -> LUTParseResult {
        switch readFileContent(at: path) {
        case .success(let content):
            return parseVLTContent(content)
        case .failure(let result):
            return result
        }
    }

    /// Parse .vlt format content string directly.
    ///
    /// VLT files are similar to .cube files with `LUT_3D_SIZE` headers
    /// and float RGB data lines. They may also include `IN_RANGE` and
    /// `OUT_RANGE` headers.
    static func parseVLTContent(_ content: String) -> LUTParseResult {
        if content.isEmpty {
            return .failure(.emptyFile, ".vlt content is empty")
        }

        var title = ""
        var dimension = 0
        var dataLineCount = 0
        var has1DSize = false

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("TITLE") {
                title = String(trimmed.dropFirst(5))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
            } else if trimmed.hasPrefix("LUT_1D_SIZE") {
                has1DSize = true
            } else if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
                if parts.count >= 2, let dim = Int(parts.last!) {
                    dimension = dim
                }
            } else if trimmed.hasPrefix("DOMAIN_MIN") || trimmed.hasPrefix("DOMAIN_MAX")
                        || trimmed.hasPrefix("IN_RANGE") || trimmed.hasPrefix("OUT_RANGE") {
                continue
            } else {
                let values = trimmed.split(whereSeparator: { $0.isWhitespace })
                    .filter { Double($0) != nil }
                if values.count >= 3 {
                    dataLineCount += 1
                }
            }
        }

        return validateParsedCube(
            title: title.isEmpty ? "Imported VLT" : title,
            dimension: dimension,
            dataLineCount: dataLineCount,
            has1DSize: has1DSize
        )
    }

    // MARK: - Private Helpers

    /// Read file content with size and existence validation.
    private static func readFileContent(at path: String) -> Result<String, LUTParseResult> {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: path) else {
            return .failure(.failure(.fileNotFound, "LUT file not found"))
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? Int else {
            return .failure(.failure(.malformedData, "Cannot read file attributes"))
        }

        if fileSize == 0 {
            return .failure(.failure(.emptyFile, "LUT file is empty"))
        }

        if fileSize > maxFileSize {
            return .failure(.failure(.fileTooLarge, "LUT file exceeds maximum size of 50MB"))
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .failure(.failure(.malformedData, "Failed to read LUT file as UTF-8 text"))
        }

        return .success(content)
    }

    /// Shared validation logic for .cube and .vlt parsed data.
    private static func validateParsedCube(
        title: String,
        dimension: Int,
        dataLineCount: Int,
        has1DSize: Bool
    ) -> LUTParseResult {
        if has1DSize {
            return .failure(.unsupported1D,
                            "1D LUTs are not supported. Please use a 3D LUT file.")
        }

        if dimension == 0 {
            return .failure(.invalidDimension,
                            "Missing or invalid LUT_3D_SIZE header")
        }

        if dimension > maxDimension {
            return .failure(.dimensionTooLarge,
                            "LUT dimension \(dimension) exceeds maximum of \(maxDimension)")
        }

        let expectedDataLines = dimension * dimension * dimension
        if dataLineCount != expectedDataLines {
            return .failure(.dataMismatch,
                            "Expected \(expectedDataLines) data lines, found \(dataLineCount)")
        }

        return .success(ParsedLUT(
            title: title,
            dimension: dimension,
            entryCount: dataLineCount,
            isValid: true,
            error: nil
        ))
    }
}
