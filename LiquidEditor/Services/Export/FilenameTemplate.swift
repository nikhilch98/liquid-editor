// FilenameTemplate.swift
// LiquidEditor
//
// Export filename template (F6-23).
//
// Users configure a token-based pattern for export filenames. Supported
// tokens are substituted from a `TemplateContext` at export time.
//
// Tokens:
//   {projectName} - sanitised project name
//   {date}        - yyyy-MM-dd
//   {time}        - HHmmss
//   {preset}      - preset name
//   {counter}     - zero-padded counter (e.g. 001)

import Foundation

// MARK: - TemplateContext

/// Values supplied at resolve time.
struct TemplateContext: Sendable {
    let projectName: String
    let date: Date
    let preset: String
    let counter: Int

    init(projectName: String, date: Date, preset: String, counter: Int) {
        self.projectName = projectName
        self.date = date
        self.preset = preset
        self.counter = counter
    }
}

// MARK: - FilenameTemplate

/// A user-editable export filename pattern.
///
/// Thread Safety: `@MainActor` because the editing UI lives on the main
/// actor. The type itself is `Sendable`, so values can be snapshotted and
/// passed across actors; the `resolve(context:)` API is pure and does not
/// require main-actor isolation.
struct FilenameTemplate: Codable, Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The raw pattern string, e.g. `"{projectName}_{date}_{counter}"`.
    let pattern: String

    // MARK: - Init

    init(pattern: String) {
        self.pattern = pattern
    }

    // MARK: - Defaults

    /// Default pattern: `ProjectName_YYYY-MM-DD_001`.
    static let `default` = FilenameTemplate(pattern: "{projectName}_{date}_{counter}")

    // MARK: - API

    /// Resolve the pattern into a filename-safe string for `context`.
    ///
    /// - Parameter context: Values to substitute into tokens.
    /// - Returns: Resolved filename (without extension).
    func resolve(context: TemplateContext) -> String {
        var result = pattern
        let substitutions: [(String, String)] = [
            ("{projectName}", Self.sanitize(context.projectName)),
            ("{date}", Self.dateFormatter.string(from: context.date)),
            ("{time}", Self.timeFormatter.string(from: context.date)),
            ("{preset}", Self.sanitize(context.preset)),
            ("{counter}", Self.formatCounter(context.counter)),
        ]
        for (token, value) in substitutions {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return Self.sanitize(result)
    }

    // MARK: - Formatters

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "HHmmss"
        return df
    }()

    private static func formatCounter(_ counter: Int) -> String {
        String(format: "%03d", max(0, counter))
    }

    /// Strip filesystem-hostile characters and collapse whitespace.
    private static func sanitize(_ input: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let whitespace = CharacterSet.whitespaces
        let cleaned = input.unicodeScalars.map { scalar -> Character in
            if illegal.contains(scalar) { return "_" }
            if whitespace.contains(scalar) { return "_" }
            return Character(scalar)
        }
        let collapsed = String(cleaned)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return collapsed.isEmpty ? "export" : collapsed
    }
}
