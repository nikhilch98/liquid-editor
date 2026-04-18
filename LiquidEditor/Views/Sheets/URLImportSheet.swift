// URLImportSheet.swift
// LiquidEditor
//
// Sheet for importing a remote media file by URL. Validates the URL
// format on input, downloads to the temporary directory with a progress
// indicator, and hands the resulting local file to
// `MediaImportService`-compatible consumers via `onDownloaded`.

import SwiftUI
import UniformTypeIdentifiers
import os

// MARK: - URLImportSheet

/// Sheet with a single URL field and a Download CTA.
///
/// Thread Safety:
/// - View state is main-actor bound.
/// - Download work uses `URLSession.download(from:)` which runs on a
///   background queue; progress is observed via a KVO-wrapped
///   `URLSessionTask` forwarding fractional completion to the main
///   actor.
struct URLImportSheet: View {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "URLImportSheet"
    )

    // MARK: - Inputs

    /// Called with the imported media after the download completes and
    /// the file is moved to a temp location.
    let onDownloaded: (ImportedMedia) -> Void

    /// Optional cancel callback.
    var onCancel: (() -> Void)?

    /// Optional import service handle (reserved for future metadata
    /// extraction hand-off). Currently unused to keep the sheet
    /// self-contained.
    var mediaImportService: MediaImportService?

    // MARK: - State

    @State private var rawURL: String = ""
    @State private var downloader = URLDownloader()
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Derived

    private var validatedURL: URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard url.host?.isEmpty == false else { return nil }
        return url
    }

    private var isValid: Bool { validatedURL != nil }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: LiquidSpacing.xl) {
                header
                urlField
                if downloader.isDownloading {
                    progressView
                } else {
                    validationHint
                }
                Spacer(minLength: 0)
                downloadButton
            }
            .padding(LiquidSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiquidColors.background.ignoresSafeArea())
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        downloader.cancel()
                        onCancel?()
                        dismiss()
                    }
                }
            }
            .alert("Download failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var header: some View {
        VStack(spacing: LiquidSpacing.sm) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Paste a direct link to a video, image, or audio file.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var urlField: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
            Text("URL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("https://example.com/clip.mp4", text: $rawURL, axis: .vertical)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .lineLimit(3)
                .padding(LiquidSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(fieldBorderColor, lineWidth: 1)
                )
                .disabled(downloader.isDownloading)
                .accessibilityLabel("URL field")
        }
    }

    private var fieldBorderColor: Color {
        if rawURL.isEmpty { return .secondary.opacity(0.3) }
        return isValid ? Color.accentColor.opacity(0.7) : .red.opacity(0.7)
    }

    @ViewBuilder
    private var validationHint: some View {
        if !rawURL.isEmpty && !isValid {
            Label("Enter a valid http(s) URL.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Reserve space to avoid layout jump.
            Text(" ").font(.footnote).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            ProgressView(value: downloader.progress, total: 1.0) {
                Text("Downloading…")
                    .font(.subheadline)
            } currentValueLabel: {
                Text("\(Int(downloader.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .tint(Color.accentColor)
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        Button {
            startDownload()
        } label: {
            if downloader.isDownloading {
                HStack(spacing: LiquidSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Downloading…")
                }
                .frame(maxWidth: .infinity)
            } else {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isValid || downloader.isDownloading)
    }

    // MARK: - Actions

    private func startDownload() {
        guard let url = validatedURL, !downloader.isDownloading else { return }
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        Task { @MainActor in
            do {
                let localURL = try await downloader.download(from: url)
                let type = MediaType.from(url: localURL)
                Self.logger.info("URLImportSheet downloaded \(url.absoluteString, privacy: .public) -> \(localURL.lastPathComponent, privacy: .public)")
                let media = ImportedMedia(
                    url: localURL,
                    type: type,
                    assetIdentifier: nil,
                    originalFilename: url.lastPathComponent
                )
                // Stub hook: real impl would forward to
                // `mediaImportService.extractMetadata(path:)` and
                // `generateThumbnail(path:)`. Kept as future work.
                _ = mediaImportService
                onDownloaded(media)
                dismiss()
            } catch is CancellationError {
                // Intentional cancel — no alert.
            } catch {
                Self.logger.error("URLImportSheet failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - URLDownloader

/// Small @Observable helper that wraps a `URLSessionDownloadTask`.
///
/// Kept private-ish (internal) so the sheet can own one as `@State`.
@MainActor
@Observable
final class URLDownloader {

    /// Fractional download progress in `[0, 1]`.
    var progress: Double = 0

    /// `true` while a download is in flight.
    var isDownloading: Bool = false

    @ObservationIgnored
    private var task: URLSessionDownloadTask?

    @ObservationIgnored
    private var progressObservation: NSKeyValueObservation?

    /// Cancel the in-flight download, if any.
    func cancel() {
        task?.cancel()
        task = nil
        progressObservation?.invalidate()
        progressObservation = nil
        isDownloading = false
        progress = 0
    }

    /// Download `url` to a unique location inside the temporary directory.
    /// - Returns: The local file URL of the downloaded payload.
    func download(from url: URL) async throws -> URL {
        cancel()
        isDownloading = true
        progress = 0
        defer {
            isDownloading = false
            progressObservation?.invalidate()
            progressObservation = nil
            task = nil
        }

        let (tempURL, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
            let downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] location, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let location, let response else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                    return
                }

                // Move file out of URLSession's ephemeral location before
                // the completion handler returns (system will delete the
                // source otherwise).
                let destDir = FileManager.default.temporaryDirectory
                let ext = url.pathExtension.isEmpty ? (response.suggestedFilename as NSString?)?.pathExtension ?? "dat" : url.pathExtension
                let destURL = destDir
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                do {
                    try FileManager.default.moveItem(at: location, to: destURL)
                    continuation.resume(returning: (destURL, response))
                } catch {
                    continuation.resume(throwing: error)
                }
                _ = self  // capture
            }

            // Observe fractional progress and forward to main actor.
            self.progressObservation = downloadTask.progress.observe(
                \.fractionCompleted,
                options: [.new]
            ) { [weak self] progress, _ in
                let value = progress.fractionCompleted
                Task { @MainActor [weak self] in
                    self?.progress = value
                }
            }

            self.task = downloadTask
            downloadTask.resume()
        }

        return tempURL
    }
}

// MARK: - MediaType + URL

private extension MediaType {
    static func from(url: URL) -> MediaType {
        let uti = UTType(filenameExtension: url.pathExtension)
        if uti?.conforms(to: .movie) == true || uti?.conforms(to: .video) == true {
            return .video
        } else if uti?.conforms(to: .audio) == true {
            return .audio
        } else if uti?.conforms(to: .image) == true {
            return .image
        }
        return .video
    }
}
