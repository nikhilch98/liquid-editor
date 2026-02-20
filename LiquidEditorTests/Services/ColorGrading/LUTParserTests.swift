import Testing
import Foundation
@testable import LiquidEditor

@Suite("LUT Parser Tests")
struct LUTParserTests {

    // MARK: - .cube Format: Valid Files

    @Test("Parses valid .cube content with title and dimension")
    func validCubeContent() {
        let content = makeCubeContent(dimension: 2, title: "Test LUT")
        let result = LUTParser.parseCubeContent(content)

        #expect(result.isSuccess)
        #expect(result.lut?.title == "Test LUT")
        #expect(result.lut?.dimension == 2)
        #expect(result.lut?.entryCount == 8)  // 2^3
        #expect(result.lut?.isValid == true)
    }

    @Test("Parses .cube with comments and blank lines")
    func cubeWithComments() {
        var lines = [
            "# This is a comment",
            "TITLE \"My Filter\"",
            "",
            "# Another comment",
            "LUT_3D_SIZE 2",
            "DOMAIN_MIN 0.0 0.0 0.0",
            "DOMAIN_MAX 1.0 1.0 1.0",
            "",
        ]
        // 2^3 = 8 data lines
        for _ in 0..<8 {
            lines.append("0.0 0.5 1.0")
        }
        let content = lines.joined(separator: "\n")
        let result = LUTParser.parseCubeContent(content)

        #expect(result.isSuccess)
        #expect(result.lut?.title == "My Filter")
        #expect(result.lut?.dimension == 2)
    }

    @Test("Parses .cube without title defaults to Untitled LUT")
    func cubeNoTitle() {
        let content = makeCubeContent(dimension: 2, title: nil)
        let result = LUTParser.parseCubeContent(content)

        #expect(result.isSuccess)
        #expect(result.lut?.title == "Untitled LUT")
    }

    @Test("Parses .cube with dimension 17")
    func cubeDimension17() {
        let content = makeCubeContent(dimension: 17, title: "17x17x17")
        let result = LUTParser.parseCubeContent(content)

        #expect(result.isSuccess)
        #expect(result.lut?.dimension == 17)
        #expect(result.lut?.entryCount == 17 * 17 * 17)
    }

    @Test("Parses .cube with dimension 33")
    func cubeDimension33() {
        let content = makeCubeContent(dimension: 33, title: "Standard")
        let result = LUTParser.parseCubeContent(content)

        #expect(result.isSuccess)
        #expect(result.lut?.dimension == 33)
        #expect(result.lut?.entryCount == 33 * 33 * 33)
    }

    // MARK: - .cube Format: Error Cases

    @Test("Rejects empty .cube content")
    func emptyContent() {
        let result = LUTParser.parseCubeContent("")
        #expect(result.isFailure)
        #expect(result.error == .emptyFile)
    }

    @Test("Rejects 1D LUT")
    func rejects1DLUT() {
        let content = "LUT_1D_SIZE 256\n0.0 0.0 0.0\n"
        let result = LUTParser.parseCubeContent(content)
        #expect(result.isFailure)
        #expect(result.error == .unsupported1D)
    }

    @Test("Rejects missing LUT_3D_SIZE header")
    func missingDimension() {
        let content = "0.0 0.5 1.0\n0.5 0.5 0.5\n"
        let result = LUTParser.parseCubeContent(content)
        #expect(result.isFailure)
        #expect(result.error == .invalidDimension)
    }

    @Test("Rejects dimension exceeding maximum")
    func dimensionTooLarge() {
        var content = "LUT_3D_SIZE 66\n"
        for _ in 0..<(66 * 66 * 66) {
            content += "0.0 0.5 1.0\n"
        }
        let result = LUTParser.parseCubeContent(content)
        #expect(result.isFailure)
        #expect(result.error == .dimensionTooLarge)
    }

    @Test("Rejects data count mismatch")
    func dataMismatch() {
        var content = "LUT_3D_SIZE 2\n"
        // Only 5 data lines instead of 8
        for _ in 0..<5 {
            content += "0.0 0.5 1.0\n"
        }
        let result = LUTParser.parseCubeContent(content)
        #expect(result.isFailure)
        #expect(result.error == .dataMismatch)
    }

    // MARK: - .3dl Format

    @Test("Parses valid .3dl content with dimension 17")
    func valid3dlDimension17() {
        let content = make3dlContent(dimension: 17)
        let result = LUTParser.parse3dlContent(content)

        #expect(result.isSuccess)
        #expect(result.lut?.dimension == 17)
        #expect(result.lut?.entryCount == 17 * 17 * 17)
        #expect(result.lut?.title == "Imported 3DL")
    }

    @Test("Parses valid .3dl content with dimension 33")
    func valid3dlDimension33() {
        let content = make3dlContent(dimension: 33)
        let result = LUTParser.parse3dlContent(content)

        #expect(result.isSuccess)
        #expect(result.lut?.dimension == 33)
    }

    @Test("Rejects empty .3dl content")
    func empty3dl() {
        let result = LUTParser.parse3dlContent("")
        #expect(result.isFailure)
        #expect(result.error == .emptyFile)
    }

    @Test("Rejects .3dl with unrecognized data line count")
    func invalid3dlDataCount() {
        var content = ""
        for _ in 0..<100 {
            content += "0 512 1023\n"
        }
        let result = LUTParser.parse3dlContent(content)
        #expect(result.isFailure)
        #expect(result.error == .dataMismatch)
    }

    // MARK: - .vlt Format

    @Test("Parses valid .vlt content")
    func validVLT() {
        var lines = [
            "TITLE \"Panasonic V-Log\"",
            "LUT_3D_SIZE 2",
            "IN_RANGE 0.0 1.0",
            "OUT_RANGE 0.0 1.0",
        ]
        for _ in 0..<8 {
            lines.append("0.1 0.5 0.9")
        }
        let content = lines.joined(separator: "\n")
        let result = LUTParser.parseVLTContent(content)

        #expect(result.isSuccess)
        #expect(result.lut?.title == "Panasonic V-Log")
        #expect(result.lut?.dimension == 2)
    }

    @Test("Rejects empty .vlt content")
    func emptyVLT() {
        let result = LUTParser.parseVLTContent("")
        #expect(result.isFailure)
        #expect(result.error == .emptyFile)
    }

    // MARK: - File Format Detection

    @Test("parseFile at path detects .cube extension")
    func detectsCubeExtension() {
        // Create temp file
        let content = makeCubeContent(dimension: 2, title: "Temp")
        let path = writeTempFile(content: content, ext: "cube")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = LUTParser.parseFile(at: path)
        #expect(result.isSuccess)
        #expect(result.lut?.dimension == 2)
    }

    @Test("parseFile at path detects .3dl extension")
    func detects3dlExtension() {
        let content = make3dlContent(dimension: 17)
        let path = writeTempFile(content: content, ext: "3dl")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = LUTParser.parseFile(at: path)
        #expect(result.isSuccess)
        #expect(result.lut?.dimension == 17)
    }

    @Test("parseFile at path detects .vlt extension")
    func detectsVLTExtension() {
        var lines = ["LUT_3D_SIZE 2"]
        for _ in 0..<8 { lines.append("0.0 0.5 1.0") }
        let content = lines.joined(separator: "\n")
        let path = writeTempFile(content: content, ext: "vlt")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = LUTParser.parseFile(at: path)
        #expect(result.isSuccess)
    }

    @Test("parseFile rejects unknown extension")
    func rejectsUnknownExtension() {
        let result = LUTParser.parseFile(at: "/tmp/test.xyz")
        #expect(result.isFailure)
        #expect(result.error == .unknownFormat)
    }

    @Test("parseFile rejects non-existent file")
    func rejectsNonExistentFile() {
        let result = LUTParser.parseCubeFile(at: "/tmp/nonexistent_lut_file.cube")
        #expect(result.isFailure)
        #expect(result.error == .fileNotFound)
    }

    // MARK: - Constants

    @Test("maxFileSize is 50MB")
    func maxFileSize() {
        #expect(LUTParser.maxFileSize == 50 * 1024 * 1024)
    }

    @Test("maxDimension is 65")
    func maxDimension() {
        #expect(LUTParser.maxDimension == 65)
    }

    // MARK: - Helpers

    private func makeCubeContent(dimension: Int, title: String?) -> String {
        var lines: [String] = []
        if let title {
            lines.append("TITLE \"\(title)\"")
        }
        lines.append("LUT_3D_SIZE \(dimension)")
        let count = dimension * dimension * dimension
        for _ in 0..<count {
            lines.append("0.0 0.5 1.0")
        }
        return lines.joined(separator: "\n")
    }

    private func make3dlContent(dimension: Int) -> String {
        var lines: [String] = []
        let count = dimension * dimension * dimension
        for _ in 0..<count {
            lines.append("0 512 1023")
        }
        return lines.joined(separator: "\n")
    }

    private func writeTempFile(content: String, ext: String) -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("test_lut_\(UUID().uuidString).\(ext)")
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
