// SettingsView.swift
// LiquidEditor
//
// App settings screen with grouped sections matching Flutter SettingsView:
// General, Editor, Gestures, Performance, Keyboard Shortcuts, and About.
//
// Matches Flutter layout:
// - General: Appearance picker, Font Size picker, Haptic Feedback toggle
// - Editor: Grid Overlay toggle, Grid Type picker, Snap to Guides toggle, Show Tutorial row
// - Gestures: Pinch Sensitivity slider, Swipe Threshold slider, Long Press Duration slider
// - Performance: Cache Size slider (no clear cache, no current usage)
// - Keyboard Shortcuts: informational display of key bindings
// - About: Version, Credits (dialog), Privacy Policy (dialog)
//
// Removed: Auto-Save, Default Frame Rate, Default Resolution, Clear Cache,
//          Current Usage, Reset to Defaults, Build number, "Made with love" text
//
// Pure SwiftUI with iOS 26 native styling. Uses List with
// grouped inset style for native settings appearance.

import SwiftUI

// MARK: - AppearanceMode

/// Appearance mode options for the app.
enum AppearanceMode: String, CaseIterable, Sendable, Identifiable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    var id: String { rawValue }
}

// MARK: - FontSizeOption

/// Font size scale options.
enum FontSizeOption: String, CaseIterable, Sendable, Identifiable {
    case small = "Small"
    case defaultSize = "Default"
    case large = "Large"

    var id: String { rawValue }

    var scale: Double {
        switch self {
        case .small: return 0.85
        case .defaultSize: return 1.0
        case .large: return 1.3
        }
    }
}

// MARK: - SettingsView

/// The app settings screen.
///
/// Displays user-configurable preferences organized into sections:
/// General, Editor, Gestures, Performance, Keyboard Shortcuts, and About.
struct SettingsView: View {

    // MARK: - State

    @State private var viewModel: SettingsViewModel

    /// Dismiss action for sheet presentation.
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local UI State

    /// Whether the credits alert is shown.
    @State private var showCreditsAlert: Bool = false

    /// Whether the privacy policy alert is shown.
    @State private var showPrivacyAlert: Bool = false

    /// Whether the onboarding view is shown.
    @State private var showOnboarding: Bool = false

    // MARK: - Initialization

    init(preferencesRepository: any PreferencesRepositoryProtocol) {
        _viewModel = State(
            initialValue: SettingsViewModel(preferencesRepository: preferencesRepository)
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                generalSection
                editorSection
                gesturesSection
                performanceSection
                keyboardShortcutsSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                viewModel.loadSettings()
            }
            .alert("Liquid Editor", isPresented: $showCreditsAlert) {
                Button("OK") {}
            } message: {
                Text("Built with Swift and native iOS technologies.\n\nPowered by AVFoundation, Vision framework, and the iOS 26 Liquid Glass design system.")
            }
            .alert("Privacy Policy", isPresented: $showPrivacyAlert) {
                Button("OK") {}
            } message: {
                Text("Liquid Editor processes all video data on-device. No video content is uploaded to external servers. Your projects and media remain private on your device.")
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    showOnboarding = false
                }
            }
        }
    }

    // MARK: - General Section

    /// Binding that converts between `AppearanceMode` enum and the ViewModel's `String` property.
    private var appearanceModeBinding: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: viewModel.appearanceMode) ?? .system },
            set: { viewModel.appearanceMode = $0.rawValue }
        )
    }

    /// Binding that converts between `FontSizeOption` enum and the ViewModel's `String` property.
    private var fontSizeOptionBinding: Binding<FontSizeOption> {
        Binding(
            get: { FontSizeOption(rawValue: viewModel.fontSizeOption) ?? .defaultSize },
            set: { viewModel.fontSizeOption = $0.rawValue }
        )
    }

    private var generalSection: some View {
        Section {
            // Appearance picker
            Picker(selection: appearanceModeBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            } label: {
                Label("Appearance", systemImage: "paintbrush")
            }

            // Font Size picker
            Picker(selection: fontSizeOptionBinding) {
                ForEach(FontSizeOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            } label: {
                Label("Font Size", systemImage: "textformat.size")
            }

            // Haptic feedback toggle
            Toggle(isOn: $viewModel.hapticFeedbackEnabled) {
                Label("Haptic Feedback", systemImage: "hand.tap")
            }
        } header: {
            Text("General")
        }
    }

    // MARK: - Editor Section

    private var editorSection: some View {
        Section {
            // Grid overlay toggle
            Toggle(isOn: $viewModel.gridVisible) {
                Label("Grid Overlay", systemImage: "grid")
            }

            // Grid Type picker
            Picker(selection: $viewModel.selectedGridType) {
                Text("Rule of Thirds").tag("Rule of Thirds")
                Text("Grid 3x3").tag("Grid 3x3")
                Text("Golden Ratio").tag("Golden Ratio")
                Text("Crosshair").tag("Crosshair")
            } label: {
                Label("Grid Type", systemImage: "squareshape.split.3x3")
            }

            // Snap to Guides (renamed from Snap to Grid)
            Toggle(isOn: $viewModel.snapToGridEnabled) {
                Label("Snap to Guides", systemImage: "rectangle.split.3x3")
            }

            // Show Tutorial
            Button {
                showOnboarding = true
            } label: {
                HStack {
                    Label("Show Tutorial", systemImage: "questionmark.circle")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        } header: {
            Text("Editor")
        }
    }

    // MARK: - Gestures Section

    private var gesturesSection: some View {
        Section {
            // Pinch Zoom Sensitivity
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Pinch Sensitivity", systemImage: "hand.pinch")
                    Spacer()
                    Text(sensitivityLabel(viewModel.pinchSensitivity))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $viewModel.pinchSensitivity,
                    in: 0.5...2.0,
                    step: 0.1
                )
            }
            .padding(.vertical, 4)

            // Swipe Threshold
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Swipe Threshold", systemImage: "hand.draw")
                    Spacer()
                    Text(sensitivityLabel(viewModel.swipeThreshold))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $viewModel.swipeThreshold,
                    in: 0.5...2.0,
                    step: 0.1
                )
            }
            .padding(.vertical, 4)

            // Long Press Duration
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Long Press Duration", systemImage: "hand.tap.fill")
                    Spacer()
                    Text("\(Int(viewModel.longPressDurationMs))ms")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $viewModel.longPressDurationMs,
                    in: 300...1000,
                    step: 100
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("Gestures")
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        Section {
            // Cache size slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Cache Size", systemImage: "internaldrive")
                    Spacer()
                    Text("\(viewModel.maxCacheSizeMB) MB")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.maxCacheSizeMB) },
                        set: { viewModel.maxCacheSizeMB = Int($0) }
                    ),
                    in: 100...500,
                    step: 50
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("Performance")
        }
    }

    // MARK: - Keyboard Shortcuts Section

    private var keyboardShortcutsSection: some View {
        Section {
            keyboardShortcutRow(label: "Play/Pause", keys: "Space")
            keyboardShortcutRow(label: "Undo", keys: "Cmd+Z")
            keyboardShortcutRow(label: "Redo", keys: "Cmd+Shift+Z")
            keyboardShortcutRow(label: "Split", keys: "Cmd+B")
            keyboardShortcutRow(label: "Delete", keys: "Delete")
            keyboardShortcutRow(label: "Select All", keys: "Cmd+A")
            keyboardShortcutRow(label: "Export", keys: "Cmd+E")
        } header: {
            Text("Keyboard Shortcuts")
        } footer: {
            Text("Available when using an external keyboard.")
        }
    }

    private func keyboardShortcutRow(label: String, keys: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(keys)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            // App version
            HStack {
                Label("Version", systemImage: "app.badge")
                Spacer()
                Text(viewModel.appVersion)
                    .foregroundStyle(.secondary)
            }

            // Credits
            Button {
                showCreditsAlert = true
            } label: {
                HStack {
                    Label("Credits", systemImage: "person.3")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Privacy Policy
            Button {
                showPrivacyAlert = true
            } label: {
                HStack {
                    Label("Privacy Policy", systemImage: "hand.raised")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private func sensitivityLabel(_ value: Double) -> String {
        if value < 0.8 { return "Low" }
        if value < 1.3 { return "Normal" }
        return "High"
    }
}
