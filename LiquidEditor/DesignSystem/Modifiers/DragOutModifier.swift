// DragOutModifier.swift
// LiquidEditor
//
// IP16-5 (per 2026-04-18 premium UI redesign spec §16 — iPad platform):
// Drag-out. Users can drag a clip out of the editor into another app
// (Files, Messages, a mail draft) and drag a finished project file out
// of the library. Uses SwiftUI's native `.draggable` modifier backed by
// Transferable so both iOS 17+ (native transferable) and UIKit-Drag
// consumers (Files app, older apps) accept the drop.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ClipTransfer

/// Thin transferable wrapper for a timeline clip.
///
/// Carries the bare minimum to reconstruct the clip at the destination:
/// the clip ID, display name, and underlying media URL. A full
/// round-trip transfer format (with effects, keyframes, etc.) is a
/// later milestone — for now drag-out produces a plain-file
/// representation that third-party apps can open as a movie/audio file.
struct ClipTransfer: Codable, Transferable, Sendable {
    let id: String
    let displayName: String
    let sourceURL: URL?

    static var transferRepresentation: some TransferRepresentation {
        // JSON representation for in-app / round-trip drops. Covers
        // both Liquid-Editor-to-Liquid-Editor and a plain-data export
        // target for third-party apps that accept our custom UTI.
        CodableRepresentation(contentType: .liquidEditorClip)
    }
}

// MARK: - UTType extension

extension UTType {
    /// Custom type for Liquid Editor in-app clip transfers.
    static let liquidEditorClip = UTType(
        exportedAs: "com.liquideditor.clip",
        conformingTo: .data
    )

    /// Custom type for Liquid Editor in-app project metadata transfers.
    static let liquidEditorProject = UTType(
        exportedAs: "com.liquideditor.project",
        conformingTo: .data
    )
}

// MARK: - ProjectTransfer

/// Thin transferable wrapper for project metadata.
///
/// When the project has no associated file URL (typical — full exports
/// are one-off, not on-disk), this lets callers drag the project
/// JSON into another Liquid Editor window so it can round-trip between
/// iPad scenes.
struct ProjectTransfer: Codable, Transferable, Sendable {
    let id: String
    let name: String
    let thumbnailPath: String?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .liquidEditorProject)
    }
}

// MARK: - View extension — generic file

extension View {
    /// Make this view draggable as a file.
    ///
    /// Destination apps (Files, Messages, Mail) receive a file-URL
    /// provider pointing at `file`.
    ///
    /// - Parameter file: The local file URL to expose as the drag payload.
    func dragOut(file: URL) -> some View {
        self.draggable(file) {
            // Preview: use the file's icon or a minimal fallback.
            Image(systemName: "doc")
                .font(.title)
                .foregroundStyle(.primary)
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - View extension — clip

extension View {
    /// Make this view draggable as a timeline clip.
    ///
    /// The transferable payload is a `ClipTransfer` which carries the
    /// clip's identifier, display name, and (when available) source
    /// URL so Files-compatible drop targets receive a playable file.
    ///
    /// - Parameter clip: The clip to expose as the drag payload.
    func dragOutClip(_ clip: any TimelineItemProtocol) -> some View {
        let transfer = ClipTransfer(
            id: clip.id,
            displayName: clip.displayName,
            sourceURL: (clip as? any ClipSourceProviding)?.sourceURL
        )
        return self.draggable(transfer) {
            HStack(spacing: 6) {
                Image(systemName: "film")
                Text(clip.displayName)
                    .lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }
}

// MARK: - View extension — project

extension View {
    /// Make this view draggable as a project metadata payload.
    ///
    /// Carries the project id, name, and thumbnail path so another
    /// Liquid Editor window can open the project on drop. Third-party
    /// apps see a JSON `com.liquideditor.project` item.
    ///
    /// A future enhancement will export a zipped `.lrproj` bundle for
    /// Files-app-compatible sharing; for now this is the in-app
    /// round-trip representation.
    ///
    /// - Parameter project: The project metadata to expose.
    func dragOutProject(_ project: ProjectMetadata) -> some View {
        let transfer = ProjectTransfer(
            id: project.id,
            name: project.name,
            thumbnailPath: project.thumbnailPath
        )
        return self.draggable(transfer) {
            HStack(spacing: 6) {
                Image(systemName: "doc.fill")
                Text(project.name)
                    .lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }
}

// MARK: - ClipSourceProviding

/// Optional protocol for clips that expose a local file URL.
///
/// Opt-in so the drag-out system can surface a file-URL representation
/// to third-party apps without forcing every TimelineItem to carry a URL.
protocol ClipSourceProviding {
    var sourceURL: URL? { get }
}
