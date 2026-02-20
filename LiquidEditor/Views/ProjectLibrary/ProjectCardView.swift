// ProjectCardView.swift
// LiquidEditor
//
// Individual project card for the Project Library grid.
// Displays thumbnail with gradient overlay, name, and compact metadata
// with a press scale animation and context menu actions.
//
// Matches Flutter _PremiumProjectCard layout:
// - Expanded thumbnail with gradient overlay and duration badge
// - Name (1 line) + compact "2h . 12 MB" line below
// - Context menu: Open, Duplicate, Rename, Delete
// - Press scale animation
//
// Pure SwiftUI with iOS 26 native styling. No Material Design.

import SwiftUI

// MARK: - ProjectCardView

/// A card representing a single project in the library grid.
///
/// Shows a thumbnail (or placeholder) with gradient overlay,
/// project name (1 line), and a compact metadata line with
/// relative date and file size. Supports context menu with
/// Open, Duplicate, Rename, and Delete actions.
struct ProjectCardView: View {

    let project: ProjectMetadata
    var onOpen: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    /// Track press state for scale animation.
    @State private var isPressed: Bool = false

    /// Async-loaded thumbnail image (nil while loading or if unavailable).
    @State private var thumbnailImage: UIImage? = nil

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm + 2) {
            thumbnailSection
            metadataSection
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .contextMenu {
            contextMenuItems
        }
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .task(id: project.thumbnailPath) {
            await loadThumbnail()
        }
    }

    // MARK: - Async Thumbnail Loading

    /// Load the thumbnail image asynchronously from disk.
    ///
    /// Dispatches the file I/O to a detached background task so the main
    /// actor is never blocked waiting on disk access.
    private func loadThumbnail() async {
        guard let path = project.thumbnailPath, !path.isEmpty else {
            thumbnailImage = nil
            return
        }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
            guard let fullURL = documentsURL?.appendingPathComponent(path) else { return nil }
            return UIImage(contentsOfFile: fullURL.path)
        }.value
        thumbnailImage = image
    }

    // MARK: - Thumbnail

    private var thumbnailSection: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(LiquidColors.fillTertiary)

            // Thumbnail (async-loaded) or placeholder
            if let img = thumbnailImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderImage
            }

            // Gradient overlay for text readability
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.4),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Favorite heart indicator (top-left)
            if project.isFavorite {
                VStack {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.5), in: Circle())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(LiquidSpacing.sm)
            }

            // Quality stars overlay (bottom-left) -- shown when quality score is available
            if let starCount = project.qualityStarCount {
                VStack {
                    Spacer()
                    HStack {
                        qualityStarsView(starCount: starCount)
                            .padding(LiquidSpacing.sm)
                        Spacer()
                    }
                }
            }

            // Duration badge (bottom-right)
            if project.timelineDurationMs > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(project.formattedDuration)
                            .font(LiquidTypography.caption2Semibold)
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(.black.opacity(0.6))
                            )
                    }
                }
                .padding(LiquidSpacing.sm)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous)
                .stroke(LiquidColors.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
    }

    /// Renders 5 quality stars with filled/empty states.
    ///
    /// - Parameter starCount: Number of filled stars (1-5).
    private func qualityStarsView(starCount: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= starCount ? "star.fill" : "star")
                    .font(.system(size: 8))
                    .foregroundStyle(index <= starCount ? Color.orange : Color(.systemGray))
            }
        }
    }

    private var placeholderImage: some View {
        VStack(spacing: LiquidSpacing.sm) {
            Image(systemName: "film")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
            HStack(spacing: LiquidSpacing.xs) {
                if let colorLabel = project.colorLabel {
                    Circle()
                        .fill(colorForLabel(colorLabel))
                        .frame(width: LiquidSpacing.sm, height: LiquidSpacing.sm)
                        .accessibilityHidden(true)
                }

                Text(project.name)
                    .font(LiquidTypography.footnoteSemibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(compactMetadataLine)
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, LiquidSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(compactMetadataLine)")
    }

    /// Map ProjectColor enum values to SwiftUI Color.
    private func colorForLabel(_ label: ProjectColor) -> Color {
        switch label {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        }
    }

    /// Compact metadata line combining relative date and file size.
    /// Format: "2h · 12 MB" (compact, no trailing "ago") or just relative date if no file size.
    private var compactMetadataLine: String {
        let fileSize = project.formattedFileSize
        if !fileSize.isEmpty {
            return "\(project.formattedModifiedCompact) \u{00B7} \(fileSize)"
        }
        return project.formattedModifiedCompact
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            onOpen?()
        } label: {
            Label("Open", systemImage: "play.fill")
        }

        Button {
            onDuplicate?()
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            onRename?()
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            onDelete?()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
