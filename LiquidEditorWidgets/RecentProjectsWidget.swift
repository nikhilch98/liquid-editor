// RecentProjectsWidget.swift
// LiquidEditorWidgets
//
// OS17-5: "Recent Projects" home-screen widget. Tap any row to open
// that project via `liquideditor://project/<id>` deep link.
//
// The provider currently returns a hardcoded sample set; a future task
// will wire it to a shared App Group store populated by the main app.

import SwiftUI
import WidgetKit

// MARK: - Sample model

struct RecentProjectSample: Hashable {
    let id: UUID
    let name: String
    let accentHex: UInt32

    var accent: Color {
        Color(
            red: Double((accentHex >> 16) & 0xFF) / 255.0,
            green: Double((accentHex >> 8) & 0xFF) / 255.0,
            blue: Double(accentHex & 0xFF) / 255.0
        )
    }

    static let samples: [RecentProjectSample] = [
        .init(id: UUID(), name: "Sunset Reel", accentHex: 0xFF6B35),
        .init(id: UUID(), name: "Road Trip", accentHex: 0x4A90E2),
        .init(id: UUID(), name: "Beach Day", accentHex: 0x50C878)
    ]
}

// MARK: - TimelineEntry

struct RecentProjectsEntry: TimelineEntry {
    let date: Date
    let projects: [RecentProjectSample]
}

// MARK: - Provider

struct RecentProjectsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentProjectsEntry {
        RecentProjectsEntry(date: Date(), projects: RecentProjectSample.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentProjectsEntry) -> Void) {
        completion(RecentProjectsEntry(date: Date(), projects: RecentProjectSample.samples))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentProjectsEntry>) -> Void) {
        let entry = RecentProjectsEntry(date: Date(), projects: RecentProjectSample.samples)
        // Refresh at most every 15 min per spec §10.10.4.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct RecentProjectsWidget: Widget {
    let kind: String = "RecentProjectsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentProjectsProvider()) { entry in
            RecentProjectsWidgetEntryView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("Recent Projects")
        .description("Jump back into your latest edits.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - View

struct RecentProjectsWidgetEntryView: View {
    let entry: RecentProjectsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            small
        default:
            medium
        }
    }

    private var small: some View {
        // Small widget renders the single most-recent project as the tap target.
        let project = entry.projects.first
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "film")
                    .foregroundStyle(.tint)
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Spacer()
            Text(project?.name ?? "No projects")
                .font(.headline)
                .lineLimit(2)
            if let project {
                Capsule()
                    .fill(project.accent)
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(project.map { URL(string: "liquideditor://project/\($0.id.uuidString)") ?? URL(string: "liquideditor://")! })
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "film")
                    .foregroundStyle(.tint)
                Text("Recent Projects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(entry.projects.prefix(3), id: \.id) { project in
                Link(destination: URL(string: "liquideditor://project/\(project.id.uuidString)")!) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(project.accent)
                            .frame(width: 28, height: 28)
                        Text(project.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
