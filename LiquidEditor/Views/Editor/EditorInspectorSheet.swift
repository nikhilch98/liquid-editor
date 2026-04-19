// EditorInspectorSheet.swift
// LiquidEditor
//
// Minimal viewer for the premium-redesign Inspector panel, driven by
// `InspectorViewModel.sectionIDs`. This is the ship-today wiring: it
// presents the right-rail/sheet chrome, the correct ordered list of
// sections per spec §10.2, and a placeholder body for each section.
//
// Follow-ups (intentionally not done in this pass):
//   - Replace each placeholder `sectionContent(for:)` case with the live
//     InspectorXxxSection view bound to the selected clip's @Binding
//     fields on EditorViewModel.
//   - Add a persistent right-rail layout on iPad instead of the sheet.

import SwiftUI

@MainActor
struct EditorInspectorSheet: View {

    let editorViewModel: EditorViewModel
    @Bindable var inspectorViewModel: InspectorViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InspectorPanel(
                sections: sections,
                emptyState: nil
            )
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .background(LiquidColors.Canvas.base.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Refresh selection on present so stale sectionIDs don't ship.
            inspectorViewModel.selection = computeSelection(
                from: editorViewModel
            )
        }
    }

    // MARK: - Section builder

    private var sections: [InspectorSection] {
        inspectorViewModel.sectionIDs.map { id in
            InspectorSection(
                id: id.rawValue,
                title: sectionTitle(for: id),
                isCollapsed: inspectorViewModel.collapsedByDefault.contains(id)
            ) {
                sectionContent(for: id)
            }
        }
    }

    private func sectionTitle(for id: InspectorSectionID) -> String {
        switch id {
        case .clipHeader:        return "Clip"
        case .projectMeta:       return "Project"
        case .playhead:          return "Playhead"
        case .linkGroup:         return "Link Group"
        case .clipMarkers:       return "Markers"
        case .clipProperties:    return "Properties"
        case .proxy:             return "Proxy"
        case .transform:         return "Transform"
        case .transformOps:      return "Flip / Rotate / Crop"
        case .opacity:           return "Opacity"
        case .blendMode:         return "Blend Mode"
        case .animation:         return "Animation"
        case .speed:             return "Speed"
        case .volume:            return "Volume"
        case .audioPan:          return "Pan"
        case .audioEffectsStack: return "Audio Effects"
        case .audioNormalize:    return "Normalize"
        case .textContent:       return "Text"
        case .captionStyle:      return "Caption Style"
        case .colorGrade:        return "Color Grade"
        }
    }

    @ViewBuilder
    private func sectionContent(for id: InspectorSectionID) -> some View {
        // Ship-today placeholder body so the panel renders without crashing
        // on missing bindings. Replace per section as live data wiring lands.
        HStack {
            Image(systemName: "ellipsis.rectangle")
                .font(.footnote)
                .foregroundStyle(LiquidColors.Text.tertiary)
            Text("Coming soon")
                .font(.footnote)
                .foregroundStyle(LiquidColors.Text.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    // MARK: - Selection mapping

    /// Very-minimal mapping from EditorViewModel's selectedClipId to the
    /// InspectorSelectionType. When multi-selection / text / audio /
    /// caption types land on the view model, extend this switch.
    private func computeSelection(
        from editor: EditorViewModel
    ) -> InspectorSelectionType {
        guard editor.selectedClipId != nil else {
            return .none
        }
        // Default to videoClip(hasAudio: true) for the common case; a
        // follow-up can inspect the actual clip type once EditorViewModel
        // exposes a `selectedClipKind` field.
        return .videoClip(hasAudio: true)
    }
}
