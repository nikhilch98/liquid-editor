// ProjectChipDropdown.swift
// LiquidEditor
//
// S2-19: compact project-switcher chip for the editor chrome.
//
// Sits in the editor's top-chrome next to the close button. Displays the
// active project name with a chevron-down and, on tap, reveals a SwiftUI
// `Menu` containing:
//
//   - Up to 5 most-recent projects (excluding the currently active one).
//   - "New Project" action.
//   - "Back to Library" action.
//
// The chip itself is styled in the Liquid Glass design system using
// `LiquidColors`, `LiquidSpacing`, and `LiquidTypography` tokens so that
// it matches the adjacent chrome affordances (close, more, export).

import SwiftUI

// MARK: - ProjectChipItem

/// Lightweight row used to populate the recent-projects section of the
/// chip's dropdown menu. This avoids importing `ProjectMetadata` directly
/// into the view and keeps the chip reusable in previews and tests.
struct ProjectChipItem: Identifiable, Equatable, Sendable {

    /// Stable identifier — typically the project's UUID.
    let id: String

    /// Display name.
    let name: String

    /// Optional SF Symbol shown alongside the name (e.g. "film.stack").
    let systemImage: String?

    init(id: String, name: String, systemImage: String? = nil) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
    }
}

// MARK: - ProjectChipDropdown

/// Compact "active project" chip with a dropdown.
///
/// - Parameters:
///   - currentProjectName: name of the project currently open in the editor.
///   - recentProjects: recent projects list (any length — the view takes
///     the first five that aren't the current project).
///   - onSelectProject: called when the user chooses a recent project.
///   - onNewProject: called when the user taps "New Project".
///   - onBackToLibrary: called when the user taps "Back to Library".
@MainActor
struct ProjectChipDropdown: View {

    // MARK: - Inputs

    let currentProjectName: String
    let recentProjects: [ProjectChipItem]
    var onSelectProject: (ProjectChipItem) -> Void
    var onNewProject: () -> Void
    var onBackToLibrary: () -> Void

    /// Maximum number of recent projects shown in the dropdown. The spec
    /// calls for 5; centralised here so tests can assert the cap.
    static let maxRecentProjects: Int = 5

    // MARK: - Derived

    /// Recent projects with the active one removed, truncated to the cap.
    private var visibleRecents: [ProjectChipItem] {
        recentProjects
            .filter { $0.name != currentProjectName }
            .prefix(Self.maxRecentProjects)
            .map { $0 }
    }

    // MARK: - Body

    var body: some View {
        Menu {
            // Recent projects section — only shown when we have at least one.
            if !visibleRecents.isEmpty {
                Section("Recent Projects") {
                    ForEach(visibleRecents) { item in
                        Button {
                            onSelectProject(item)
                        } label: {
                            if let systemImage = item.systemImage {
                                Label(item.name, systemImage: systemImage)
                            } else {
                                Text(item.name)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    onNewProject()
                } label: {
                    Label("New Project", systemImage: "plus")
                }

                Button {
                    onBackToLibrary()
                } label: {
                    Label("Back to Library", systemImage: "square.grid.2x2")
                }
            }
        } label: {
            chipLabel
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(
            "Project: \(currentProjectName). Double-tap to switch projects."
        )
    }

    // MARK: - Subviews

    /// The chip itself: rounded-rect pill with project name + chevron.
    private var chipLabel: some View {
        HStack(spacing: LiquidSpacing.xs) {
            Text(currentProjectName)
                .font(LiquidTypography.subheadlineSemibold)
                .foregroundStyle(LiquidColors.Text.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LiquidColors.Text.secondary)
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.vertical, LiquidSpacing.xs + 2)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(LiquidStroke.hairlineColor, lineWidth: LiquidStroke.hairlineWidth)
        )
        .contentShape(Capsule(style: .continuous))
    }
}
