// PeopleGridView.swift
// LiquidEditor
//
// People tab content for the Project Library.
// Displays a grid of known persons with rectangular card layout,
// gradient overlays, image count badges, and quality star ratings.
//
// Matches Flutter _PersonCard layout:
// - Fixed 2-column grid with aspect ratio ~0.85
// - Rectangular card (rounded 16pt corners) instead of circular thumbnails
// - Gradient overlay on thumbnails
// - Image count badge overlay (top-right): photo icon + count
// - Quality star ratings overlay (bottom-left): 5 gold stars
// - Name text below the card thumbnail
// - No "Add Person" card in grid (FAB handles this)
//
// Pure SwiftUI with iOS 26 native styling. No Material Design.

import PhotosUI
import SwiftUI

// MARK: - PeopleGridView

/// Grid view of known people from the People library.
///
/// Each card displays a rectangular face thumbnail with gradient overlay,
/// image count badge, quality stars, and the person's name below.
struct PeopleGridView: View {

    @Bindable var viewModel: ProjectLibraryViewModel

    /// Callback when a person card's "View" action is triggered.
    var onView: ((Person) -> Void)?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.people.isEmpty {
                loadingView
            } else if viewModel.filteredPeople.isEmpty {
                emptyPeopleView
            } else {
                peopleGrid
            }
        }
        .alert(
            "Rename Person",
            isPresented: $viewModel.showRenameAlert,
            actions: {
                TextField("Name", text: $viewModel.renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    Task { await viewModel.commitRename() }
                }
            },
            message: {
                Text("Enter a new name for this person.")
            }
        )
    }

    // MARK: - Grid

    private var peopleGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: LiquidSpacing.lg),
                    GridItem(.flexible(), spacing: LiquidSpacing.lg),
                ],
                spacing: LiquidSpacing.lg
            ) {
                ForEach(viewModel.filteredPeople, id: \.id) { person in
                    personCard(for: person)
                }
            }
            .padding(.horizontal, LiquidSpacing.xl)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Person Card

    private func personCard(for person: Person) -> some View {
        PersonCardWrapper(person: person) {
            VStack(alignment: .leading, spacing: LiquidSpacing.sm + 2) {
                // Thumbnail with overlays
                personThumbnailCard(for: person)
                    .aspectRatio(0.85, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous)
                            .stroke(LiquidColors.glassBorder, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)

                // Name below card
                Text(person.name)
                    .font(LiquidTypography.footnoteSemibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, LiquidSpacing.xxs)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(person.name), \(person.imageCount) photos")
        .contextMenu {
            personContextMenu(for: person)
        }
    }

    private func personThumbnailCard(for person: Person) -> some View {
        ZStack {
            // Background
            Rectangle()
                .fill(LiquidColors.fillTertiary)

            // Thumbnail image
            if !person.thumbnailPath.isEmpty {
                let documentsURL = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                ).first
                let fullURL = documentsURL?.appendingPathComponent(person.thumbnailPath)

                if let url = fullURL, let uiImage = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    personPlaceholder
                }
            } else {
                personPlaceholder
            }

            // Gradient overlay for readability
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.4),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Image count badge (top-right)
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: LiquidSpacing.xs) {
                        Image(systemName: "photo")
                            .font(LiquidTypography.caption)
                            .foregroundStyle(.white)
                        Text("\(person.imageCount)")
                            .font(LiquidTypography.captionMedium)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, LiquidSpacing.sm)
                    .padding(.vertical, LiquidSpacing.xs)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .padding(LiquidSpacing.sm)
                }
                Spacer()
            }

            // Quality star ratings (bottom-left)
            VStack {
                Spacer()
                HStack {
                    qualityStarsOverlay(for: person)
                        .padding(LiquidSpacing.sm)
                    Spacer()
                }
            }
        }
    }

    private var personPlaceholder: some View {
        VStack {
            Image(systemName: "person.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Quality Stars Overlay

    private func qualityStarsOverlay(for person: Person) -> some View {
        let averageQuality: Double = {
            guard !person.images.isEmpty else { return 0 }
            let total = person.images.map(\.qualityScore).reduce(0, +)
            return total / Double(person.images.count)
        }()
        let bestQuality: Double = {
            guard !person.images.isEmpty else { return 0 }
            return person.images.map(\.qualityScore).max() ?? 0
        }()
        let starCount = max(1, min(5, Int((bestQuality * 5).rounded())))

        return HStack(spacing: LiquidSpacing.xs) {
            // Colored quality dot based on average quality across all images
            Circle()
                .fill(qualityDotColor(score: averageQuality))
                .frame(width: 6, height: 6)
                .accessibilityLabel(qualityDotLabel(score: averageQuality))

            // Star rating based on best image quality
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: index < starCount ? "star.fill" : "star")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(
                            index < starCount
                                ? Color(.systemYellow)
                                : Color(.systemGray)
                        )
                }
            }
        }
    }

    /// Color for the quality dot indicator.
    ///
    /// - Green: average quality >= 0.7 (good faces, suitable for recognition).
    /// - Yellow: average quality >= 0.4 (fair faces, may degrade tracking).
    /// - Red: average quality < 0.4 (poor faces, insufficient for reliable recognition).
    private func qualityDotColor(score: Double) -> Color {
        if score >= 0.7 { return Color(.systemGreen) }
        if score >= 0.4 { return Color(.systemYellow) }
        return Color(.systemRed)
    }

    /// Accessibility label for the quality dot.
    private func qualityDotLabel(score: Double) -> String {
        if score >= 0.7 { return "Good quality" }
        if score >= 0.4 { return "Fair quality" }
        return "Poor quality"
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func personContextMenu(for person: Person) -> some View {
        Button {
            onView?(person)
        } label: {
            Label("View", systemImage: "eye")
        }

        Button {
            viewModel.beginAddImageToPerson(id: person.id)
        } label: {
            Label("Add Photo", systemImage: "photo.on.rectangle")
        }

        Button {
            viewModel.beginRenamePerson(person)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            Task { await viewModel.deletePerson(id: person.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty / Loading States

    private var emptyPeopleView: some View {
        ContentUnavailableView {
            Label("No People", systemImage: "person.2")
        } description: {
            Text("Add reference photos for better tracking.\nPhotos from different angles help improve person recognition.")
        } actions: {
            Button {
                Task { await viewModel.addPerson() }
            } label: {
                Text("Add Person")
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading People...")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, LiquidSpacing.sm)
            Spacer()
        }
    }
}

// MARK: - PersonCardWrapper

/// Wraps person card content with a press scale animation matching Flutter's
/// `CupertinoContextMenu.builder` scale behavior.
private struct PersonCardWrapper<Content: View>: View {

    let person: Person
    let content: () -> Content

    @State private var isPressed: Bool = false

    init(person: Person, @ViewBuilder content: @escaping () -> Content) {
        self.person = person
        self.content = content
    }

    var body: some View {
        content()
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isPressed)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
    }
}
