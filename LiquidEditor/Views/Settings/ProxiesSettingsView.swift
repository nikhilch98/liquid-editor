// ProxiesSettingsView.swift
// LiquidEditor
//
// S2-24: App Settings › Proxies section.
//
// Dedicated settings panel for proxy-generation preferences with
// UserDefaults-backed storage. Bound to the local stub `ProxySettings`
// (scoped to this file so we don't intrude on ProxyService's domain
// types until a unified settings model lands).

import SwiftUI
import os

// MARK: - ProxySettingsResolution

/// Resolution tier used for proxy generation.
///
/// Values correspond to relative scale factors applied to the source
/// material rather than absolute pixel dimensions; this avoids coupling
/// Settings to the `ProxyResolution` AVFoundation preset enum.
enum ProxySettingsResolution: String, CaseIterable, Identifiable, Sendable, Codable {
    case quarter
    case half
    case full

    var id: String { rawValue }

    /// User-facing label.
    var label: String {
        switch self {
        case .quarter: return "Quarter"
        case .half:    return "Half"
        case .full:    return "Full"
        }
    }

    /// Description shown under the picker.
    var summary: String {
        switch self {
        case .quarter: return "1/4 resolution — smallest proxies, fastest editing."
        case .half:    return "1/2 resolution — balanced quality and size."
        case .full:    return "Full resolution — no downscaling; rarely needed."
        }
    }
}

// MARK: - ProxySettings

/// UserDefaults-backed settings for proxy generation.
///
/// Stored under a single key prefix so wiping is easy during QA:
/// `com.liquideditor.settings.proxy.*`.
@MainActor
@Observable
final class ProxySettings {

    // MARK: - Keys

    private enum Key {
        static let autoGenerate     = "com.liquideditor.settings.proxy.autoGenerate"
        static let resolution       = "com.liquideditor.settings.proxy.resolution"
        static let storageLimitGB   = "com.liquideditor.settings.proxy.storageLimitGB"
    }

    // MARK: - Logger

    nonisolated(unsafe) private static let logger = Logger(
        subsystem: "LiquidEditor",
        category: "ProxySettings"
    )

    // MARK: - Defaults

    static let defaultStorageLimitGB: Int = 20
    static let storageLimitRange: ClosedRange<Int> = 1...500
    static let defaultResolution: ProxySettingsResolution = .half

    // MARK: - Storage

    private let defaults: UserDefaults

    // MARK: - Observable State

    /// Automatically generate proxies for 4K+ source material.
    var autoGenerateFor4KPlus: Bool {
        didSet { defaults.set(autoGenerateFor4KPlus, forKey: Key.autoGenerate) }
    }

    /// Target proxy resolution tier.
    var resolution: ProxySettingsResolution {
        didSet { defaults.set(resolution.rawValue, forKey: Key.resolution) }
    }

    /// Maximum disk budget for proxy cache, in gigabytes.
    var storageLimitGB: Int {
        didSet {
            let clamped = storageLimitGB.clamped(to: Self.storageLimitRange)
            if clamped != storageLimitGB {
                storageLimitGB = clamped
                return
            }
            defaults.set(storageLimitGB, forKey: Key.storageLimitGB)
        }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Auto-generate: default ON (matches Flutter predecessor).
        if defaults.object(forKey: Key.autoGenerate) == nil {
            self.autoGenerateFor4KPlus = true
        } else {
            self.autoGenerateFor4KPlus = defaults.bool(forKey: Key.autoGenerate)
        }

        // Resolution: default half.
        if let raw = defaults.string(forKey: Key.resolution),
           let parsed = ProxySettingsResolution(rawValue: raw) {
            self.resolution = parsed
        } else {
            self.resolution = Self.defaultResolution
        }

        // Storage limit: default 20 GB.
        let rawLimit = defaults.integer(forKey: Key.storageLimitGB)
        self.storageLimitGB = rawLimit > 0
            ? rawLimit.clamped(to: Self.storageLimitRange)
            : Self.defaultStorageLimitGB
    }

    // MARK: - Actions

    /// Clear all generated proxy files.
    ///
    /// Removes everything under the proxy cache directory. Safe to call
    /// if the directory is missing. Runs on a background task so the
    /// main actor remains responsive.
    func clearAllProxies() async {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)
                .first ?? fm.temporaryDirectory
            let proxyDir = caches.appendingPathComponent("Proxies", isDirectory: true)

            guard fm.fileExists(atPath: proxyDir.path) else {
                Self.logger.info("clearAllProxies: nothing to remove at \(proxyDir.path, privacy: .public)")
                return
            }

            do {
                try fm.removeItem(at: proxyDir)
                Self.logger.info("clearAllProxies: removed \(proxyDir.path, privacy: .public)")
            } catch {
                Self.logger.error("clearAllProxies failed: \(error.localizedDescription)")
            }
        }.value
    }
}

// MARK: - Int clamping helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - ProxiesSettingsView

/// Settings panel for proxy-generation preferences.
///
/// Designed for presentation inside the app's existing settings navigation
/// stack (e.g. pushed from `SettingsView`).
@MainActor
struct ProxiesSettingsView: View {

    // MARK: - Inputs

    @State private var settings: ProxySettings

    // MARK: - Local State

    @State private var showingClearConfirmation = false
    @State private var isClearing = false

    // MARK: - Init

    init(settings: ProxySettings = ProxySettings()) {
        _settings = State(initialValue: settings)
    }

    // MARK: - Body

    var body: some View {
        Form {
            autoGenerateSection
            resolutionSection
            storageSection
            dangerSection
        }
        .navigationTitle("Proxies")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear all proxies?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task { await clearProxies() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all generated proxy files. Editing performance may drop until proxies regenerate.")
        }
    }

    // MARK: - Sections

    private var autoGenerateSection: some View {
        Section {
            Toggle(isOn: $settings.autoGenerateFor4KPlus) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-generate proxies for 4K+")
                    Text("Improves scrubbing and playback for high-resolution clips.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Automatic Generation")
        }
    }

    private var resolutionSection: some View {
        Section {
            Picker("Proxy resolution", selection: $settings.resolution) {
                ForEach(ProxySettingsResolution.allCases) { res in
                    Text(res.label).tag(res)
                }
            }
            .pickerStyle(.segmented)

            Text(settings.resolution.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Proxy Resolution")
        }
    }

    private var storageSection: some View {
        Section {
            Stepper(value: $settings.storageLimitGB,
                    in: ProxySettings.storageLimitRange) {
                HStack {
                    Text("Storage limit")
                    Spacer()
                    Text("\(settings.storageLimitGB) GB")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("When the proxy cache exceeds this size, the oldest proxies are deleted first.")
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingClearConfirmation = true
            } label: {
                HStack {
                    if isClearing {
                        ProgressView()
                            .padding(.trailing, 6)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text(isClearing ? "Clearing…" : "Clear all proxies")
                }
            }
            .disabled(isClearing)
        }
    }

    // MARK: - Actions

    private func clearProxies() async {
        isClearing = true
        await settings.clearAllProxies()
        isClearing = false
    }
}

// MARK: - Preview

#Preview("Proxy Settings") {
    NavigationStack {
        ProxiesSettingsView()
    }
}
