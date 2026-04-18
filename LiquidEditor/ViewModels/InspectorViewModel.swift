// InspectorViewModel.swift
// LiquidEditor
//
// IM9-1: @Observable @MainActor projection over EditorViewModel.selection
// per spec §10.2 + §11.4.
//
// Translates the editor's current selection (no selection / single clip /
// multi-select / playhead-only) into an ordered list of `InspectorSection`
// IDs that the InspectorPanel renders. The actual section CONTENT is
// produced by the section providers in IM9-2..21; this VM is purely a
// section-IDs router.
//
// Section visibility per spec §10.2 matrix:
//
//   selection -> sections
//   ---------------------
//   no selection    -> projectMeta, playhead
//   playhead only   -> playhead, projectMeta(collapsed)
//   video clip      -> clipHeader, transform, speed, volume, opacity,
//                      colorGrade, animation, blendMode, transformOps,
//                      audioPan(if has audio), proxy, properties
//   text clip       -> clipHeader, transform, opacity, textContent,
//                      animation
//   audio clip      -> clipHeader, speed, volume, audioPan,
//                      audioEffectsStack, audioNormalize
//   caption clip    -> clipHeader, opacity, captionStyle, animation
//   multi-select    -> clipHeader, transform(collapsed), speed(collapsed),
//                      volume(collapsed), opacity(collapsed),
//                      colorGrade(collapsed), animation(collapsed) + Mixed
//                      label per IM9-13
//
// Plus link-group + clip-markers sections shown when applicable.

import Foundation
import Observation

// MARK: - InspectorSelectionType

/// The selection categories the inspector projects against. Decoupled
/// from EditorViewModel's specific Clip subtypes so this VM can evolve
/// independently.
enum InspectorSelectionType: Equatable, Sendable {
    case none
    case playheadOnly
    case videoClip(hasAudio: Bool)
    case textClip
    case audioClip
    case captionClip
    case multiSelect(count: Int)
}

// MARK: - InspectorSectionID

/// Stable section identifiers used both as InspectorSection.id and for
/// stable diffing across selection changes.
enum InspectorSectionID: String, CaseIterable, Sendable {
    // Common
    case clipHeader
    case projectMeta
    case playhead
    case linkGroup
    case clipMarkers
    case clipProperties
    case proxy

    // Transform / motion
    case transform
    case transformOps         // flip / quick rotate / crop
    case opacity
    case blendMode
    case animation

    // Speed + audio
    case speed
    case volume
    case audioPan
    case audioEffectsStack
    case audioNormalize

    // Style
    case textContent
    case captionStyle
    case colorGrade
}

// MARK: - InspectorViewModel

/// @Observable projection that maps the current selection to the ordered
/// list of sections to render. The InspectorPanel reads `sectionIDs`
/// and asks its section-provider registry to materialize each one.
@Observable
@MainActor
final class InspectorViewModel {

    // MARK: - Inputs

    /// The current selection. Caller updates this on every selection change.
    var selection: InspectorSelectionType {
        didSet { recomputeSections() }
    }

    // MARK: - Outputs

    /// Ordered section IDs to render. Empty when selection == .none and
    /// the empty-state should be shown instead.
    private(set) var sectionIDs: [InspectorSectionID] = []

    /// Sections that should default-render collapsed (per spec §10.2 “○”).
    private(set) var collapsedByDefault: Set<InspectorSectionID> = []

    /// True when more than one clip is selected; consumers render “Mixed”
    /// labels for inconsistent values per IM9-13.
    var isMultiSelection: Bool {
        if case .multiSelect = selection { return true } else { return false }
    }

    // MARK: - Init

    init(selection: InspectorSelectionType = .none) {
        self.selection = selection
        recomputeSections()
    }

    // MARK: - Section computation

    private func recomputeSections() {
        switch selection {
        case .none:
            sectionIDs = [.projectMeta, .playhead]
            collapsedByDefault = []

        case .playheadOnly:
            sectionIDs = [.playhead, .projectMeta]
            collapsedByDefault = [.projectMeta]

        case .videoClip(let hasAudio):
            var ids: [InspectorSectionID] = [
                .clipHeader, .transform, .transformOps, .speed,
            ]
            if hasAudio { ids.append(.volume); ids.append(.audioPan) }
            ids.append(contentsOf: [
                .opacity, .blendMode, .colorGrade, .animation,
                .clipMarkers, .linkGroup, .proxy, .clipProperties,
            ])
            sectionIDs = ids
            collapsedByDefault = []

        case .textClip:
            sectionIDs = [
                .clipHeader, .textContent, .transform, .opacity,
                .animation, .clipMarkers, .clipProperties,
            ]
            collapsedByDefault = []

        case .audioClip:
            sectionIDs = [
                .clipHeader, .speed, .volume, .audioPan,
                .audioEffectsStack, .audioNormalize,
                .clipMarkers, .linkGroup, .clipProperties,
            ]
            collapsedByDefault = []

        case .captionClip:
            sectionIDs = [
                .clipHeader, .captionStyle, .opacity, .animation,
            ]
            collapsedByDefault = []

        case .multiSelect:
            sectionIDs = [
                .clipHeader, .transform, .speed, .volume,
                .opacity, .colorGrade, .animation,
            ]
            collapsedByDefault = [
                .transform, .speed, .volume, .opacity,
                .colorGrade, .animation,
            ]
        }
    }
}
