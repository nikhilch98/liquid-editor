// QuickActionWidget.swift
// LiquidEditorWidgets
//
// OS17-5: "New Project" quick-action widget. Tapping launches the app
// into the new-project flow via the `liquideditor://new` deep link.

import SwiftUI
import WidgetKit

// MARK: - Provider

struct QuickActionEntry: TimelineEntry {
    let date: Date
}

struct QuickActionProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionEntry {
        QuickActionEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionEntry) -> Void) {
        completion(QuickActionEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionEntry>) -> Void) {
        completion(Timeline(entries: [QuickActionEntry(date: Date())], policy: .never))
    }
}

// MARK: - Widget

struct QuickActionWidget: Widget {
    let kind: String = "QuickActionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionProvider()) { _ in
            QuickActionWidgetEntryView()
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("New Project")
        .description("Start a new Liquid Editor project.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - View

struct QuickActionWidgetEntryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.orange)
            }
            Text("New Project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "liquideditor://new")!)
    }
}
