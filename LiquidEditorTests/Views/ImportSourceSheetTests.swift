import Testing
import Foundation
@testable import LiquidEditor

@Suite("ImportSourceSheet Tests")
struct ImportSourceSheetTests {

    // MARK: - ImportSourceOption

    @Suite("ImportSourceOption")
    struct ImportSourceOptionTests {

        @Test("allCases contains exactly 4 options")
        func allCasesCount() {
            #expect(ImportSourceOption.allCases.count == 4)
        }

        @Test("allCases contains all expected options")
        func allCasesContent() {
            let cases = ImportSourceOption.allCases
            #expect(cases.contains(.photoLibrary))
            #expect(cases.contains(.files))
            #expect(cases.contains(.camera))
            #expect(cases.contains(.url))
        }

        @Test("id returns rawValue for each option")
        func identifiable() {
            #expect(ImportSourceOption.photoLibrary.id == "photoLibrary")
            #expect(ImportSourceOption.files.id == "files")
            #expect(ImportSourceOption.camera.id == "camera")
            #expect(ImportSourceOption.url.id == "url")
        }

        @Test("rawValue matches expected strings")
        func rawValues() {
            #expect(ImportSourceOption.photoLibrary.rawValue == "photoLibrary")
            #expect(ImportSourceOption.files.rawValue == "files")
            #expect(ImportSourceOption.camera.rawValue == "camera")
            #expect(ImportSourceOption.url.rawValue == "url")
        }

        @Test("label returns human-readable names")
        func labels() {
            #expect(ImportSourceOption.photoLibrary.label == "Photo Library")
            #expect(ImportSourceOption.files.label == "Files")
            #expect(ImportSourceOption.camera.label == "Camera")
            #expect(ImportSourceOption.url.label == "URL")
        }

        @Test("sfSymbol returns valid SF Symbol names")
        func sfSymbols() {
            #expect(ImportSourceOption.photoLibrary.sfSymbol == "photo.on.rectangle")
            #expect(ImportSourceOption.files.sfSymbol == "folder")
            #expect(ImportSourceOption.camera.sfSymbol == "camera")
            #expect(ImportSourceOption.url.sfSymbol == "link")
        }

        @Test("sfSymbol is non-empty for all options")
        func sfSymbolsNonEmpty() {
            for option in ImportSourceOption.allCases {
                #expect(!option.sfSymbol.isEmpty)
            }
        }

        @Test("label is non-empty for all options")
        func labelsNonEmpty() {
            for option in ImportSourceOption.allCases {
                #expect(!option.label.isEmpty)
            }
        }

        @Test("asImportSource maps to correct ImportSource values")
        func asImportSource() {
            #expect(ImportSourceOption.photoLibrary.asImportSource == .photoLibrary)
            #expect(ImportSourceOption.files.asImportSource == .files)
            #expect(ImportSourceOption.camera.asImportSource == .camera)
            #expect(ImportSourceOption.url.asImportSource == .url)
        }

        @Test("each option maps to a unique ImportSource")
        func uniqueImportSources() {
            let sources = ImportSourceOption.allCases.map(\.asImportSource)
            let uniqueSources = Set(sources.map(\.rawValue))
            #expect(uniqueSources.count == sources.count)
        }

        @Test("init from rawValue roundtrips correctly")
        func rawValueRoundtrip() {
            for option in ImportSourceOption.allCases {
                let recreated = ImportSourceOption(rawValue: option.rawValue)
                #expect(recreated == option)
            }
        }

        @Test("init from invalid rawValue returns nil")
        func invalidRawValue() {
            let invalid = ImportSourceOption(rawValue: "dropbox")
            #expect(invalid == nil)
        }
    }
}
