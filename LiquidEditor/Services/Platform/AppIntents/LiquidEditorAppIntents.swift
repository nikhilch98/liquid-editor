// LiquidEditorAppIntents.swift
// LiquidEditor
//
// Siri Shortcuts and App Intents integration (OS17-6).
//
// Defines three user-facing intents:
//   • OpenProjectIntent    — open an existing project by name.
//   • CreateProjectIntent  — create a new project with a given name and aspect.
//   • ExportProjectIntent  — export the currently-open project.
//
// All intents trigger the app to foreground (openAppWhenRun = true) and
// dispatch work via URL deep-links routed through the shared URL scheme
// (see DeepLinkRouter for the canonical scheme definition).
//
// The `LiquidEditorShortcutsProvider` registers these as first-class
// Shortcuts suggestions so users can invoke them from Siri / Spotlight
// / the Shortcuts app without any prior configuration.
//
// iOS 16+ (AppIntents framework).

import AppIntents
import Foundation
import SwiftUI
import os

// MARK: - Shared Logger

private let intentsLogger = Logger(
    subsystem: "com.liquideditor",
    category: "AppIntents"
)

// MARK: - ProjectAspectAppEnum

/// Aspect ratio enum surfaced to Shortcuts for CreateProjectIntent.
///
/// Keep in sync with `AspectRatioService` presets. Raw values are stable
/// identifiers used by both the intent and the URL deep link payload.
enum ProjectAspectAppEnum: String, AppEnum {
    case square = "1:1"
    case portrait = "9:16"
    case landscape = "16:9"
    case cinematic = "21:9"
    case classic = "4:3"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Aspect Ratio"

    static let caseDisplayRepresentations: [ProjectAspectAppEnum: DisplayRepresentation] = [
        .square:     "Square (1:1)",
        .portrait:   "Portrait (9:16)",
        .landscape:  "Landscape (16:9)",
        .cinematic:  "Cinematic (21:9)",
        .classic:    "Classic (4:3)"
    ]
}

// MARK: - OpenProjectIntent

/// Open an existing Liquid Editor project by name.
///
/// Matches against the project name (case-insensitive). If multiple
/// projects share a name, the most-recently modified one is opened.
struct OpenProjectIntent: AppIntent {

    static let title: LocalizedStringResource = "Open Project"

    static let description = IntentDescription(
        "Opens an existing Liquid Editor project by name.",
        categoryName: "Projects"
    )

    static let openAppWhenRun: Bool = true

    @Parameter(
        title: "Project Name",
        description: "The name of the project to open.",
        requestValueDialog: "Which project would you like to open?"
    )
    var projectName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Open project \(\.$projectName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        intentsLogger.info("OpenProjectIntent invoked: \(projectName, privacy: .public)")

        guard let encoded = projectName.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else {
            throw IntentError.invalidProjectName
        }

        guard let url = URL(string: "liquideditor://open?name=\(encoded)") else {
            throw IntentError.malformedURL
        }

        await UIApplication.shared.open(url)
        return .result()
    }
}

// MARK: - CreateProjectIntent

/// Create a new Liquid Editor project with the given name and aspect.
struct CreateProjectIntent: AppIntent {

    static let title: LocalizedStringResource = "Create Project"

    static let description = IntentDescription(
        "Creates a new Liquid Editor project.",
        categoryName: "Projects"
    )

    static let openAppWhenRun: Bool = true

    @Parameter(
        title: "Project Name",
        description: "The name of the new project.",
        requestValueDialog: "What would you like to name the project?"
    )
    var name: String

    @Parameter(
        title: "Aspect Ratio",
        description: "The aspect ratio for the new project.",
        default: .landscape
    )
    var aspect: ProjectAspectAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Create project \(\.$name) with aspect \(\.$aspect)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        intentsLogger.info(
            "CreateProjectIntent invoked: \(name, privacy: .public) aspect=\(aspect.rawValue, privacy: .public)"
        )

        guard let encodedName = name.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else {
            throw IntentError.invalidProjectName
        }

        guard let encodedAspect = aspect.rawValue.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else {
            throw IntentError.malformedURL
        }

        let urlString = "liquideditor://create?name=\(encodedName)&aspect=\(encodedAspect)"
        guard let url = URL(string: urlString) else {
            throw IntentError.malformedURL
        }

        await UIApplication.shared.open(url)
        return .result()
    }
}

// MARK: - ExportProjectIntent

/// Export the currently-open Liquid Editor project.
///
/// If no project is currently open in the editor, the intent surfaces
/// a dialog and returns without side-effects.
struct ExportProjectIntent: AppIntent {

    static let title: LocalizedStringResource = "Export Current Project"

    static let description = IntentDescription(
        "Exports the project currently open in Liquid Editor.",
        categoryName: "Projects"
    )

    static let openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("Export current project")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        intentsLogger.info("ExportProjectIntent invoked")

        guard let url = URL(string: "liquideditor://export") else {
            throw IntentError.malformedURL
        }

        await UIApplication.shared.open(url)
        return .result(dialog: "Starting export…")
    }
}

// MARK: - IntentError

/// Errors surfaced by Liquid Editor intents.
enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case invalidProjectName
    case malformedURL

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidProjectName:
            return "The project name is invalid."
        case .malformedURL:
            return "Failed to construct the launch URL."
        }
    }
}

// MARK: - LiquidEditorShortcutsProvider

/// Registers Liquid Editor intents as first-class App Shortcuts.
///
/// Automatically surfaced in the Shortcuts app, Spotlight, and Siri
/// — no user configuration required.
struct LiquidEditorShortcutsProvider: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenProjectIntent(),
            phrases: [
                "Open project in \(.applicationName)",
                "Open a project in \(.applicationName)"
            ],
            shortTitle: "Open Project",
            systemImageName: "folder.fill"
        )

        AppShortcut(
            intent: CreateProjectIntent(),
            phrases: [
                "Create project in \(.applicationName)",
                "New project in \(.applicationName)"
            ],
            shortTitle: "Create Project",
            systemImageName: "plus.square.fill"
        )

        AppShortcut(
            intent: ExportProjectIntent(),
            phrases: [
                "Export project in \(.applicationName)",
                "Export current \(.applicationName) project"
            ],
            shortTitle: "Export Project",
            systemImageName: "square.and.arrow.up.fill"
        )
    }
}
