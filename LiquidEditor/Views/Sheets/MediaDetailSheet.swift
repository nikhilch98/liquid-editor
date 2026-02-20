// MediaDetailSheet.swift
// LiquidEditor
//
// Media file detail view showing comprehensive metadata.
//
// Presented as a bottom sheet with thumbnail preview, metadata fields
// (resolution, duration, codec, color space, etc.), action buttons
// (favorite, copy ID), and tags display.
//
// Pure iOS 26 SwiftUI with native Liquid Glass styling.

import SwiftUI

// MARK: - MediaDetailSheet

/// Displays detailed metadata for a media asset.
///
/// Shows:
/// - Thumbnail preview with filename, type, and file size
/// - Favorite toggle and copy-ID button
/// - Full metadata table (resolution, duration, codec, color, audio, etc.)
/// - Color and text tags
struct MediaDetailSheet: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    /// The media asset to display.
    let asset: MediaAsset

    /// Called when the favorite status is toggled.
    let onToggleFavorite: ((String) -> Void)?

    /// Called when the sheet appears (for refreshing metadata if needed).
    let onRefresh: ((String) -> Void)?

    // MARK: - Init

    init(
        asset: MediaAsset,
        onToggleFavorite: ((String) -> Void)? = nil,
        onRefresh: ((String) -> Void)? = nil
    ) {
        self.asset = asset
        self.onToggleFavorite = onToggleFavorite
        self.onRefresh = onRefresh
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LiquidSpacing.lg) {
                    thumbnailHeader

                    actionButtons

                    metadataSection

                    if !asset.colorTags.isEmpty || !asset.textTags.isEmpty {
                        tagsSection
                    }

                    Spacer(minLength: LiquidSpacing.xxxl)
                }
                .padding(LiquidSpacing.lg)
            }
            .background(LiquidColors.background)
            .navigationTitle("Media Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Request metadata refresh if callback provided.
            // Parent can update and re-present sheet with fresh data.
            onRefresh?(asset.id)
        }
    }

    // MARK: - Thumbnail Header

    private var thumbnailHeader: some View {
        HStack(alignment: .top, spacing: LiquidSpacing.lg) {
            // Thumbnail placeholder
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                .fill(LiquidColors.fillTertiary)
                .frame(width: 100, height: 100)
                .overlay {
                    Image(systemName: thumbnailIcon)
                        .font(.system(size: 32))
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                .accessibilityHidden(true)

            // Basic info
            VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
                Text(asset.originalFilename)
                    .font(LiquidTypography.bodySemibold)
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(2)

                Text("\(asset.type.rawValue.uppercased()) - \(MediaDetailSheet.formatDuration(asset.durationMicroseconds))")
                    .font(LiquidTypography.subheadline)
                    .foregroundStyle(LiquidColors.textSecondary)

                Text(MediaDetailSheet.formatFileSize(asset.fileSize))
                    .font(LiquidTypography.subheadline)
                    .foregroundStyle(LiquidColors.textSecondary)
            }
        }
    }

    private var thumbnailIcon: String {
        if asset.isAudio { return "waveform" }
        return "photo"
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: LiquidSpacing.lg) {
            Button {
                onToggleFavorite?(asset.id)
            } label: {
                Image(systemName: asset.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        asset.isFavorite ? LiquidColors.error : LiquidColors.textSecondary
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(asset.isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityHint("Toggles favorite status for this media asset")

            Button {
                UIPasteboard.general.string = asset.id
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 24))
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy asset ID")
            .accessibilityHint("Copies the asset identifier to the clipboard")
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Details")

            metadataRow("Resolution", "\(asset.width) x \(asset.height)")

            if asset.isVideo || asset.isAudio {
                metadataRow("Duration", MediaDetailSheet.formatDuration(asset.durationMicroseconds))
            }

            if let frameRate = asset.frameRate {
                metadataRow("Frame Rate", String(format: "%.2f fps", frameRate.value))
            }

            if let codec = asset.codec {
                metadataRow("Codec", codec)
            }

            if let colorSpace = asset.colorSpace {
                metadataRow("Color Space", colorSpace)
            }

            if let bitDepth = asset.bitDepth {
                metadataRow("Bit Depth", "\(bitDepth)-bit")
            }

            if asset.hasAudio {
                let channels = MediaDetailSheet.channelDescription(asset.audioChannels ?? 0)
                let sampleRate = MediaDetailSheet.formatSampleRate(asset.audioSampleRate ?? 0)
                metadataRow("Audio", "\(channels) @ \(sampleRate)")
            }

            metadataRow("File Size", MediaDetailSheet.formatFileSize(asset.fileSize))

            if let creationDate = asset.creationDate {
                metadataRow("Created", MediaDetailSheet.formatDate(creationDate))
            }

            metadataRow("Imported", MediaDetailSheet.formatDate(asset.importedAt))

            if let location = asset.locationISO6709 {
                metadataRow("Location", location)
            }

            if let importSource = asset.importSource {
                metadataRow("Source", MediaDetailSheet.formatSource(importSource))
            }

            metadataRow("Content Hash", String(asset.contentHash.prefix(12)) + "...")
            metadataRow("Asset ID", String(asset.id.prefix(8)) + "...")
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            sectionHeader("Tags")

            MediaTagFlowLayout(spacing: LiquidSpacing.sm) {
                ForEach(asset.colorTags, id: \.self) { tag in
                    Circle()
                        .fill(MediaDetailSheet.tagColorToSwiftUI(tag))
                        .frame(width: 20, height: 20)
                        .accessibilityLabel("\(tagColorName(tag)) tag")
                }

                ForEach(asset.textTags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(LiquidColors.textPrimary)
                        .padding(.horizontal, LiquidSpacing.sm)
                        .padding(.vertical, LiquidSpacing.xxs)
                        .background(LiquidColors.fillTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(LiquidTypography.footnoteSemibold)
            .foregroundStyle(LiquidColors.textSecondary)
            .textCase(.uppercase)
            .padding(.bottom, LiquidSpacing.sm)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textPrimary)
        }
        .padding(.vertical, LiquidSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Static Formatters

    /// Cached date formatter to avoid repeated allocation.
    /// Used for formatting creation and import dates.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy H:mm"
        return formatter
    }()

    /// Format microseconds duration as `H:MM:SS` or `M:SS`.
    static func formatDuration(_ microseconds: Int64) -> String {
        let totalSeconds = microseconds / 1_000_000
        if totalSeconds == 0 { return "--:--" }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// Format bytes as human-readable file size.
    static func formatFileSize(_ bytes: Int) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
        }
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        }
        if bytes >= 1024 {
            return "\(bytes / 1024) KB"
        }
        return "\(bytes) bytes"
    }

    /// Format date for display using cached formatter.
    static func formatDate(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }

    /// Channel count to description.
    static func channelDescription(_ channels: Int) -> String {
        switch channels {
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1 Surround"
        case 8: "7.1 Surround"
        default: "\(channels) ch"
        }
    }

    /// Format sample rate in Hz to kHz.
    static func formatSampleRate(_ rate: Int) -> String {
        if rate >= 1000 {
            let khz = Double(rate) / 1000.0
            return rate % 1000 == 0
                ? String(format: "%.0f kHz", khz)
                : String(format: "%.1f kHz", khz)
        }
        return "\(rate) Hz"
    }

    /// Format import source for display.
    static func formatSource(_ source: ImportSource) -> String {
        switch source {
        case .photoLibrary: "Photo Library"
        case .files: "Files"
        case .camera: "Camera"
        case .url: "URL"
        case .googleDrive: "Google Drive"
        case .dropbox: "Dropbox"
        }
    }

    /// Convert TagColor to SwiftUI Color.
    static func tagColorToSwiftUI(_ tag: TagColor) -> Color {
        switch tag {
        case .red: Color(.systemRed)
        case .orange: Color(.systemOrange)
        case .yellow: Color(.systemYellow)
        case .green: Color(.systemGreen)
        case .blue: Color(.systemBlue)
        case .purple: Color(.systemPurple)
        }
    }

    /// Get color name for accessibility label.
    private func tagColorName(_ tag: TagColor) -> String {
        switch tag {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        }
    }
}

// MARK: - MediaTagFlowLayout

/// Simple flow layout for tags in the media detail sheet (wrapping horizontal layout).
struct MediaTagFlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangementResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = max(totalHeight, currentY + rowHeight)
        }

        return ArrangementResult(
            size: CGSize(width: totalWidth, height: totalHeight),
            positions: positions
        )
    }
}

#Preview {
    MediaDetailSheet(
        asset: MediaAsset(
            id: "preview-asset-1",
            contentHash: "abc123def456",
            relativePath: "Media/video.mp4",
            originalFilename: "Beach_Sunset_4K.mp4",
            type: .video,
            durationMicroseconds: 125_000_000,
            frameRate: Rational(30, 1),
            width: 3840,
            height: 2160,
            codec: "hevc",
            audioSampleRate: 48000,
            audioChannels: 2,
            fileSize: 256_000_000,
            importedAt: Date(),
            colorTags: [.blue, .green],
            textTags: ["sunset", "beach"],
            colorSpace: "Rec. 2020 HLG",
            bitDepth: 10,
            importSource: .photoLibrary
        )
    )
}
