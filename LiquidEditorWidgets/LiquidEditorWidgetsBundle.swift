// LiquidEditorWidgetsBundle.swift
// LiquidEditorWidgets
//
// OS17-5: Widget extension bundle entry point. Registers every widget
// surfaced on Home Screen, Lock Screen, and StandBy per spec §10.10.4.

import SwiftUI
import WidgetKit

@main
struct LiquidEditorWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecentProjectsWidget()
        QuickActionWidget()
    }
}
