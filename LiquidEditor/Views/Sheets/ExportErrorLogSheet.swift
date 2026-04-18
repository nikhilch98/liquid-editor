// ExportErrorLogSheet.swift
// LiquidEditor
//
// S2-15: Export error log + Copy log action.
//
// Full-screen sheet rendering detailed export log entries (timestamp +
// severity + message) with level filter chips and a Copy Log action that
// writes a formatted plain-text rendering to `UIPasteboard.general`.
//
// Intended for use from ExportQueueSheet via a "View Log" affordance.

import SwiftUI
import UIKit

// MARK: - ExportLogLevel

/// Severity levels for export log entries.
///
/// Levels are ordered `info < warning < error < critical` for visual
/// emphasis and filter sorting.
enum ExportLogLevel: String, CaseIterable, Sendable, Codable {
    case info
    case warning
    case error
    case critical

    /// Human-readable label.
    var label: String {
        switch self {
        case .info:     return "Info"
        case .warning:  return "Warning"
        case .error:    return "Error"
        case .critical: return "Critical"
        }
    }

    /// SF Symbol for the chip / row icon.
    var sfSymbolName: String {
        switch self {
        case .info:     return "info.circle"
        case .warning:  return "exclamationmark.triangle"
        case .error:    return "xmark.octagon"
        case .critical: return "flame"
        }
    }

    /// Tint colour for the chip / row icon.
    var tintColor: Color {
        switch self {
        case .info:     return .secondary
        case .warning:  return .orange
        case .error:    return .red
        case .critical: return .pink
        }
    }
}

// MARK: - ExportLogEntry

/// A single entry in the export log.
struct ExportLogEntry: Sendable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let level: ExportLogLevel
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: ExportLogLevel,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

// MARK: - ExportErrorLogSheet

/// Sheet presenting a filterable list of export log entries with a
/// "Copy Log" action.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showLog) {
///     ExportErrorLogSheet(entries: viewModel.logEntries)
/// }
/// ```
@MainActor
struct ExportErrorLogSheet: View {

    // MARK: - Inputs

    /// All entries to display. The sheet maintains its own filter state.
    let entries: [ExportLogEntry]

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Local State

    /// Currently active level filters. Empty set == "show all".
    @State private var activeFilters: Set<ExportLogLevel> = []

    /// Copy action confirmation toast trigger.
    @State private var didCopy: Bool = false

    // MARK: - Computed

    private var visibleEntries: [ExportLogEntry] {
        guard !activeFilters.isEmpty else { return entries }
        return entries.filter { activeFilters.contains($0.level) }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let fullTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChips
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                Divider()

                if visibleEntries.isEmpty {
                    emptyState
                } else {
                    logList
                }
            }
            .background(.ultraThinMaterial)
            .navigationTitle("Export Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyLog()
                    } label: {
                        Label("Copy Log", systemImage: "doc.on.doc")
                    }
                    .disabled(entries.isEmpty)
                }
            }
            .overlay(alignment: .top) {
                if didCopy {
                    copiedToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: didCopy)
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExportLogLevel.allCases, id: \.self) { level in
                    chip(for: level)
                }
            }
        }
    }

    private func chip(for level: ExportLogLevel) -> some View {
        let isActive = activeFilters.contains(level)
        let count = entries.filter { $0.level == level }.count
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            if isActive {
                activeFilters.remove(level)
            } else {
                activeFilters.insert(level)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: level.sfSymbolName)
                    .font(.caption)
                Text(level.label)
                    .font(.caption.weight(.medium))
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isActive
                        ? level.tintColor.opacity(0.22)
                        : Color.secondary.opacity(0.12)
                )
            )
            .overlay(
                Capsule().stroke(
                    isActive ? level.tintColor : .clear,
                    lineWidth: 1
                )
            )
            .foregroundStyle(isActive ? level.tintColor : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.label) filter, \(count) entries")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - List

    private var logList: some View {
        List {
            ForEach(visibleEntries) { entry in
                row(for: entry)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(for entry: ExportLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.level.sfSymbolName)
                .foregroundStyle(entry.level.tintColor)
                .font(.body)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Text(Self.timestampFormatter.string(from: entry.timestamp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No log entries")
                .font(.headline)
            Text("No messages match the current filter.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Copy

    private func copyLog() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let text = Self.renderPlainText(entries: visibleEntries)
        UIPasteboard.general.string = text
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            didCopy = false
        }
    }

    private var copiedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text("Copied to clipboard")
                .font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(Capsule())
        .padding(.top, 8)
    }

    // MARK: - Rendering

    /// Format log entries for copy/paste.
    static func renderPlainText(entries: [ExportLogEntry]) -> String {
        entries.map { entry in
            let ts = fullTimestampFormatter.string(from: entry.timestamp)
            let level = entry.level.rawValue.uppercased()
            return "[\(ts)] [\(level)] \(entry.message)"
        }
        .joined(separator: "\n")
    }
}

// MARK: - Preview

#Preview("Export Log") {
    ExportErrorLogSheet(entries: [
        ExportLogEntry(level: .info, message: "Export started."),
        ExportLogEntry(level: .info, message: "Composition built in 120ms."),
        ExportLogEntry(level: .warning, message: "Thermal state elevated."),
        ExportLogEntry(level: .error, message: "Encode stall at frame 4281."),
        ExportLogEntry(level: .critical, message: "Insufficient disk space."),
    ])
}
