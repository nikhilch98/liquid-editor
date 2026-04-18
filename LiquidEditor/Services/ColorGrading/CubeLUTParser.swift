/// CubeLUTParser - full-data parser for Adobe/DaVinci Resolve .cube LUT files.
///
/// C5-13 (Premium UI Redesign spec §5): Provides a strongly-typed `CubeLUT`
/// data container with RGBA-interleaved float payload and conversion to
/// `CIColorCubeWithColorSpace` for direct CIFilter use.
///
/// Distinct from `LUTParser` (in same folder): `LUTParser` performs metadata
/// validation and format detection; `CubeLUTParser` loads the full LUT data
/// into memory and produces a ready-to-apply `CIFilter`.
///
/// .cube format summary (Adobe spec):
/// - `TITLE "Name"` (optional)
/// - `LUT_3D_SIZE N` (required; N typically 17, 32, 33, 64)
/// - `DOMAIN_MIN R G B` (optional; default 0 0 0)
/// - `DOMAIN_MAX R G B` (optional; default 1 1 1)
/// - Then `N^3` data lines of three floats `R G B`.
/// - Comments begin with `#`; blank lines and whitespace ignored.
///
/// Thread Safety: `CubeLUT` is `Sendable` (value type, no references).
/// `CubeLUTParser` is a stateless caseless enum.

import CoreImage
import CoreGraphics
import Foundation

// MARK: - CubeLUTError

/// Errors thrown by `CubeLUTParser.parse`.
enum CubeLUTError: Error, Sendable, Equatable {
    /// The file could not be read from disk.
    case fileUnreadable(String)
    /// Missing LUT_3D_SIZE header or malformed header line.
    case invalidFormat(String)
    /// LUT size is outside the supported range (must be 2...256).
    case unsupportedSize(Int)
    /// Data section has fewer entries than `size^3`.
    case dataTruncated(expected: Int, actual: Int)
}

// MARK: - CubeLUT

/// In-memory representation of a parsed 3D .cube LUT.
///
/// - `size`: cube dimension along each axis (2...256).
/// - `domain`: the input sample range as `(min, max)` applied uniformly to R/G/B.
/// - `data`: RGBA-interleaved floats, length `size^3 * 4`. Alpha is always 1.0.
///   This layout matches what `CIColorCubeWithColorSpace` expects for
///   its `inputCubeData` parameter.
struct CubeLUT: Sendable, Equatable {
    /// Cube dimension along each axis.
    let size: Int

    /// Input sample range, applied to R/G/B. Default is `(0.0, 1.0)`.
    let domain: (CGFloat, CGFloat)

    /// RGBA-interleaved LUT data, length `size * size * size * 4`.
    let data: [Float]

    /// Optional title from the `TITLE` header line.
    let title: String

    // MARK: - Equatable

    static func == (lhs: CubeLUT, rhs: CubeLUT) -> Bool {
        lhs.size == rhs.size
            && lhs.domain.0 == rhs.domain.0
            && lhs.domain.1 == rhs.domain.1
            && lhs.title == rhs.title
            && lhs.data == rhs.data
    }

    // MARK: - CIFilter Conversion

    /// Build a `CIColorCubeWithColorSpace` CIFilter configured with this LUT.
    ///
    /// Returns `nil` if the filter cannot be instantiated (e.g., on a
    /// platform where it is unavailable) or if the data buffer is malformed.
    /// The caller is expected to set `kCIInputImageKey` before reading
    /// `outputImage`.
    func toCIColorCube() -> CIFilter? {
        let expectedCount = size * size * size * 4
        guard data.count == expectedCount else { return nil }
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }

        // Convert [Float] -> Data (little-endian on all Apple platforms).
        let payload: Data = data.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(payload, forKey: "inputCubeData")

        // sRGB working color space is a safe default for display-referred LUTs.
        if let sRGB = CGColorSpace(name: CGColorSpace.sRGB) {
            filter.setValue(sRGB, forKey: "inputColorSpace")
        }
        return filter
    }
}

// MARK: - CubeLUTParser

/// Stateless parser for .cube files producing a full `CubeLUT`.
enum CubeLUTParser {

    /// Minimum supported cube dimension.
    static let minSize: Int = 2

    /// Maximum supported cube dimension.
    /// CIColorCubeWithColorSpace accepts up to 64 in practice; we allow
    /// slightly beyond for flexibility but reject pathological sizes.
    static let maxSize: Int = 256

    // MARK: - Public API

    /// Parse a .cube file at `url` into a `CubeLUT`.
    ///
    /// - Throws: `CubeLUTError` on file read failure, invalid format,
    ///   unsupported size, or truncated data.
    static func parse(url: URL) throws -> CubeLUT {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CubeLUTError.fileUnreadable(error.localizedDescription)
        }
        return try parse(content: content)
    }

    /// Parse .cube file content from a string.
    ///
    /// Exposed for testing and for callers that already have the content
    /// in memory (e.g., bundled resources).
    static func parse(content: String) throws -> CubeLUT {
        var title: String = ""
        var size: Int = 0
        var domainMin: CGFloat = 0.0
        var domainMax: CGFloat = 1.0
        var sawDomainMin = false
        var sawDomainMax = false
        var parsedEntries: [(r: Float, g: Float, b: Float)] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // Header lines are case-insensitive in practice.
            let upper = line.uppercased()
            if upper.hasPrefix("TITLE") {
                title = extractTitle(from: line)
                continue
            }
            if upper.hasPrefix("LUT_1D_SIZE") {
                throw CubeLUTError.invalidFormat("1D LUTs are not supported; expected LUT_3D_SIZE")
            }
            if upper.hasPrefix("LUT_3D_SIZE") {
                guard let parsedSize = extractInt(from: line) else {
                    throw CubeLUTError.invalidFormat("Malformed LUT_3D_SIZE line: '\(line)'")
                }
                guard parsedSize >= Self.minSize && parsedSize <= Self.maxSize else {
                    throw CubeLUTError.unsupportedSize(parsedSize)
                }
                size = parsedSize
                parsedEntries.reserveCapacity(size * size * size)
                continue
            }
            if upper.hasPrefix("DOMAIN_MIN") {
                guard let (r, _, _) = extractTriplet(from: line) else {
                    throw CubeLUTError.invalidFormat("Malformed DOMAIN_MIN line: '\(line)'")
                }
                domainMin = CGFloat(r)
                sawDomainMin = true
                continue
            }
            if upper.hasPrefix("DOMAIN_MAX") {
                guard let (r, _, _) = extractTriplet(from: line) else {
                    throw CubeLUTError.invalidFormat("Malformed DOMAIN_MAX line: '\(line)'")
                }
                domainMax = CGFloat(r)
                sawDomainMax = true
                continue
            }

            // Otherwise, assume data line.
            if let triplet = extractTriplet(from: line) {
                parsedEntries.append((r: triplet.0, g: triplet.1, b: triplet.2))
            } else {
                throw CubeLUTError.invalidFormat("Unrecognized or malformed line: '\(line)'")
            }
        }

        guard size > 0 else {
            throw CubeLUTError.invalidFormat("Missing LUT_3D_SIZE header")
        }

        let expectedCount = size * size * size
        guard parsedEntries.count == expectedCount else {
            throw CubeLUTError.dataTruncated(expected: expectedCount, actual: parsedEntries.count)
        }

        // Pack RGBA with alpha = 1.0 (CIColorCubeWithColorSpace requires RGBA).
        var rgba: [Float] = []
        rgba.reserveCapacity(expectedCount * 4)
        for entry in parsedEntries {
            rgba.append(entry.r)
            rgba.append(entry.g)
            rgba.append(entry.b)
            rgba.append(1.0)
        }

        // Default domain (0, 1) if no headers were present.
        let domain: (CGFloat, CGFloat) = (sawDomainMin ? domainMin : 0.0,
                                          sawDomainMax ? domainMax : 1.0)

        return CubeLUT(
            size: size,
            domain: domain,
            data: rgba,
            title: title
        )
    }

    // MARK: - Private Helpers

    /// Extract a quoted or unquoted title from a `TITLE …` line.
    private static func extractTitle(from line: String) -> String {
        // Strip the leading TITLE token (case-insensitive).
        let stripped = line
            .replacingOccurrences(of: "TITLE", with: "", options: [.caseInsensitive, .anchored])
            .trimmingCharacters(in: .whitespaces)
        return stripped.replacingOccurrences(of: "\"", with: "")
    }

    /// Extract the first integer from a line's tokens following the header keyword.
    private static func extractInt(from line: String) -> Int? {
        let tokens = line.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 2 else { return nil }
        return Int(tokens[1])
    }

    /// Extract three floats from a line's whitespace-separated tokens.
    ///
    /// Accepts either `HEADER R G B` (4 tokens) or `R G B` (3 tokens).
    private static func extractTriplet(from line: String) -> (Float, Float, Float)? {
        let tokens = line.split(whereSeparator: { $0.isWhitespace })
        // Strip a leading non-numeric header token if present.
        let numericTokens: [Substring]
        if let first = tokens.first, Float(first) == nil {
            numericTokens = Array(tokens.dropFirst())
        } else {
            numericTokens = Array(tokens)
        }
        guard numericTokens.count >= 3,
              let r = Float(numericTokens[0]),
              let g = Float(numericTokens[1]),
              let b = Float(numericTokens[2]) else {
            return nil
        }
        return (r, g, b)
    }
}
