// ClipPropertiesView.swift
// LiquidEditor
//
// T7-19 (Premium UI §10.3): Read-only metadata inspector for a
// selected clip. Typically presented as a sheet from the timeline
// long-press menu (Properties action).
//
// Contents per spec:
// - Codec / resolution / fps / color space / bit depth
// - Duration (formatted hh:mm:ss.ms)
// - File path (relative path surfaced; absolute hidden unless asked for)
// - Imported / creation dates (when available)
// - Linked / unlinked status
//
// Pure SwiftUI, iOS 26 native styling with Liquid Glass. No UIKit
// wrappers. Data is fed in via a simple `ClipPropertiesInput` value
// (the caller resolves the MediaAsset asynchronously before showing
// the sheet).

import SwiftUI

// MARK: - ClipPropertiesInput

/// Lightweight projection of the data a properties sheet needs.
///
/// This wrapper lets the sheet show properties for ANY clip type, not
/// only those backed by a `MediaAsset` — for example a `TextClip` where
/// only duration / name are relevant.
struct ClipPropertiesInput: Equatable, Sendable {
    let clipDisplayName: String
    let clipDurationMicros: TimeMicros
    let clipItemType: TimelineItemType

    /// Populated when the clip is backed by a video, image, or audio asset.
    let asset: MediaAsset?

    init(
        clipDisplayName: String,
        clipDurationMicros: TimeMicros,
        clipItemType: TimelineItemType,
        asset: MediaAsset? = nil
    ) {
        self.clipDisplayName = clipDisplayName
        self.clipDurationMicros = clipDurationMicros
        self.clipItemType = clipItemType
        self.asset = asset
    }
}

// MARK: - ClipPropertiesView

/// Read-only clip metadata sheet.
struct ClipPropertiesView: View {

    // MARK: - Inputs

    let input: ClipPropertiesInput

    /// Dismiss callback — caller flips `isPresented` back to `false`.
    let onDismiss: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    row("Name", value: input.clipDisplayName)
                    row("Type", value: input.clipItemType.rawValue.capitalized)
                    row("Duration", value: input.clipDurationMicros.simpleTimeString)
                }

                if let asset = input.asset {
                    Section("Source") {
                        row("Original filename", value: asset.originalFilename)
                        row("Relative path", value: asset.relativePath)
                    }

                    Section("Video") {
                        if asset.hasVideo {
                            row("Resolution", value: "\(asset.width) × \(asset.height)")
                            if let fr = asset.frameRate {
                                row(
                                    "Frame rate",
                                    value: String(format: "%.2f fps", fr.value)
                                )
                            }
                            if let codec = asset.codec {
                                row("Codec", value: codec.uppercased())
                            }
                            if let colorSpace = asset.colorSpace {
                                row("Color space", value: colorSpace)
                            }
                            if let bitDepth = asset.bitDepth {
                                row("Bit depth", value: "\(bitDepth)-bit")
                            }
                        } else {
                            row("Video", value: "—")
                        }
                    }

                    Section("Audio") {
                        if asset.hasAudio {
                            if let rate = asset.audioSampleRate {
                                row("Sample rate", value: "\(rate) Hz")
                            }
                            if let ch = asset.audioChannels {
                                row("Channels", value: "\(ch)")
                            }
                        } else {
                            row("Audio", value: "—")
                        }
                    }

                    Section("File") {
                        row(
                            "File size",
                            value: ByteCountFormatter.string(
                                fromByteCount: Int64(asset.fileSize),
                                countStyle: .file
                            )
                        )
                        row(
                            "Linked",
                            value: asset.isLinked ? "Yes" : "No (relink required)"
                        )
                        if let creation = asset.creationDate {
                            row("Created", value: creation.formatted(date: .abbreviated, time: .shortened))
                        }
                        row(
                            "Imported",
                            value: asset.importedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle("Clip Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Row helper

    @ViewBuilder
    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: LiquidSpacing.md)
            Text(value)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 14))
        .accessibilityElement(children: .combine)
    }
}
