// DragDropReceiver.swift
// LiquidEditor
//
// IP16-2 (per 2026-04-18 premium UI redesign spec §16 — iPad platform):
// System drag-drop receiver. Accepts files dragged in from Files,
// Photos, Safari, Mail, and other apps — both on iPad (primary target)
// and on iPhone (where iOS 26 surfaces drop from Split-View-adjacent
// apps and from Stage Manager windows).
//
// Supported UTIs: `.movie`, `.image`, `.audio`, `.url`. Each dropped
// provider is loaded via NSItemProvider and handed off to
// MediaImportService when available — the actual import path is
// stubbed here with a TODO so M15-style import wiring can plug in
// later without changing the drop handshake.

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import os

// MARK: - DragDropReceiver

/// Receives file drops from other apps and hands them off to the
/// media import pipeline.
///
/// Thread safety: @MainActor because SwiftUI's `.onDrop` delegate runs
/// on the main actor and the receiver may update `@State`/@Observable
/// UI state to surface drop-target indicators.
@MainActor
@Observable
final class DragDropReceiver {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "DragDropReceiver"
    )

    // MARK: - State

    /// Whether a drop is currently being processed. Callers can use this
    /// for progress UI.
    private(set) var isProcessing: Bool = false

    /// Number of successfully loaded providers in the most recent drop.
    private(set) var lastDropCount: Int = 0

    /// Last drop error, if any — surfaced for UI banners.
    private(set) var lastError: Error?

    // MARK: - Dependencies

    /// Optional MediaImportService. When nil, drops are logged but not
    /// imported — useful for unit tests and for wiring the receiver
    /// before the import pipeline is ready.
    private let mediaImportService: MediaImportService?

    /// Accepted content types for drops.
    static let acceptedContentTypes: [UTType] = [.movie, .image, .audio, .url]

    // MARK: - Init

    init(mediaImportService: MediaImportService? = nil) {
        self.mediaImportService = mediaImportService
    }

    // MARK: - Public API

    /// Handle a batch of dropped providers. Called from SwiftUI's
    /// `.onDrop(perform:)` closure.
    ///
    /// - Parameter providers: The `NSItemProvider`s delivered by the drop.
    /// - Returns: `true` if at least one provider was accepted and loaded.
    @discardableResult
    func handleDrop(providers: [NSItemProvider]) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }

        var accepted = 0
        for provider in providers {
            if await loadProvider(provider) {
                accepted += 1
            }
        }

        lastDropCount = accepted
        Self.logger.info("Drop finished: \(accepted)/\(providers.count, privacy: .public) providers accepted")
        return accepted > 0
    }

    // MARK: - Private

    /// Attempt to load a single provider. Tries each accepted UTI in
    /// priority order (movie > image > audio > url) and returns after
    /// the first successful load.
    private func loadProvider(_ provider: NSItemProvider) async -> Bool {
        for type in Self.acceptedContentTypes {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else {
                continue
            }
            do {
                let url = try await loadFileURL(from: provider, type: type)
                await forwardToImport(url: url, type: type)
                return true
            } catch {
                Self.logger.error("Failed to load provider as \(type.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                lastError = error
                continue
            }
        }
        return false
    }

    /// Load a single provider as a file URL.
    ///
    /// Uses `loadFileRepresentation` for file-backed items and falls
    /// back to `loadDataRepresentation` (writing to a temp file) when
    /// the provider is data-only.
    private func loadFileURL(from provider: NSItemProvider, type: UTType) async throws -> URL {
        // Prefer file representation when available (avoids double copy).
        if provider.hasRepresentationConforming(toTypeIdentifier: type.identifier, fileOptions: []) {
            return try await withCheckedThrowingContinuation { cont in
                _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    guard let url else {
                        cont.resume(throwing: DragDropError.noURL)
                        return
                    }
                    // Copy to a temp file because the system-provided URL
                    // is only valid for the duration of this callback.
                    do {
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(url.pathExtension)
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        cont.resume(returning: tempURL)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }

        // Fall back to data representation.
        return try await withCheckedThrowingContinuation { cont in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let data else {
                    cont.resume(throwing: DragDropError.noData)
                    return
                }
                do {
                    let ext = type.preferredFilenameExtension ?? "bin"
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    try data.write(to: tempURL)
                    cont.resume(returning: tempURL)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Forward a loaded file URL to the media import pipeline.
    ///
    /// STUB: the actual import wiring is deferred until the
    /// drag-drop UX is fully designed (multi-file batching, progress
    /// HUD, conflict resolution). For now we log and keep the temp
    /// file around long enough for downstream code to pick it up.
    private func forwardToImport(url: URL, type: UTType) async {
        Self.logger.info("Drop forwarded: \(url.lastPathComponent, privacy: .public) (\(type.identifier, privacy: .public))")

        // TODO(IP16-2 follow-up): call MediaImportService once a
        // non-picker-based entry-point exists. The picker-based API
        // takes a UIViewController; a direct file-URL API is queued
        // for a separate ticket.
        _ = mediaImportService
    }
}

// MARK: - Errors

enum DragDropError: Error, Sendable {
    case noURL
    case noData
    case unsupportedType
}

// MARK: - View extension

extension View {
    /// Attach the system drag-drop receiver to this view.
    ///
    /// Accepts `.movie`, `.image`, `.audio`, and `.url` item providers.
    /// Updates `isTargeted` for target-state visuals (e.g. outline).
    func dragDropReceiver(
        _ receiver: DragDropReceiver,
        isTargeted: Binding<Bool>? = nil
    ) -> some View {
        self.onDrop(
            of: DragDropReceiver.acceptedContentTypes,
            isTargeted: isTargeted
        ) { providers in
            Task { @MainActor in
                await receiver.handleDrop(providers: providers)
            }
            return true
        }
    }
}
