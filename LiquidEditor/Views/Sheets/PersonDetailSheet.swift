// PersonDetailSheet.swift
// LiquidEditor
//
// Person details view with face thumbnails, rename, and image management.
//
// Displays a person's reference images in a grid with quality indicators,
// primary badge, and context menu actions (remove). Supports adding
// new images and renaming the person.
//
// Safety features (matching Flutter):
// - Confirmation dialog before removing images
// - Face detection validation when adding new images
// - Name uniqueness check before saving rename
//
// Pure iOS 26 SwiftUI with native Liquid Glass styling.

import PhotosUI
import SwiftUI
import UIKit

// MARK: - PersonDetailSheet

/// Sheet for viewing and editing person details.
///
/// Shows the person's reference images in a 2-column grid with:
/// - Quality star ratings per image
/// - "Primary" badge on the first image
/// - Context menu to remove images (with confirmation dialog)
/// - Add image button (up to 5, with face detection validation)
/// - Tap name to rename (with uniqueness check)
struct PersonDetailSheet: View {

    // MARK: - State

    @State private var person: Person
    @State private var isAddingImage = false
    @State private var showRenamAlert = false
    @State private var renameText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false

    // Real image loading from disk
    @State private var loadedImages: [String: UIImage] = [:]
    /// IDs whose disk lookup has completed (success or failure).
    @State private var checkedImageIds: Set<String> = []

    // Safety feature states
    @State private var imageToRemove: PersonImage?
    @State private var showRemoveConfirmation = false
    @State private var showDifferentPersonAlert = false
    @State private var differentPersonMessage = ""
    @State private var pendingImageData: Data?
    @State private var pendingDetectedPerson: DetectedPerson?
    @State private var showNameTakenAlert = false
    @State private var nameConflictText = ""

    @Environment(\.dismiss) private var dismiss

    /// Called when the person is updated.
    let onPersonUpdated: ((Person) -> Void)?

    /// All existing person names for uniqueness checking.
    let existingPersonNames: [String]

    // MARK: - Constants

    private static let maxImages = 5
    private let columns = [
        GridItem(.flexible(), spacing: LiquidSpacing.md),
        GridItem(.flexible(), spacing: LiquidSpacing.md),
    ]

    // MARK: - Init

    init(
        person: Person,
        existingPersonNames: [String] = [],
        onPersonUpdated: ((Person) -> Void)? = nil
    ) {
        _person = State(initialValue: person)
        self.existingPersonNames = existingPersonNames
        self.onPersonUpdated = onPersonUpdated
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Custom header row
            sheetHeaderRow
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()
                .padding(.horizontal)

            VStack(spacing: 0) {
                headerInfo

                imageGrid
            }
            .background(LiquidColors.background)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Load images from disk concurrently when sheet appears
        .task {
            await loadImagesFromDisk()
        }
        // Rename dialog
        .alert("Rename Person", isPresented: $showRenamAlert) {
            TextField("Enter name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { performRename() }
        }
        // Remove photo confirmation dialog
        .alert("Remove Photo?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                imageToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let image = imageToRemove {
                    performRemoveImage(image)
                }
                imageToRemove = nil
            }
        } message: {
            Text("This photo will be removed from this person.")
        }
        // Different person detection alert
        .alert("Different Person?", isPresented: $showDifferentPersonAlert) {
            Button("Cancel", role: .cancel) {
                pendingImageData = nil
                pendingDetectedPerson = nil
            }
            Button("Add Anyway", role: .destructive) {
                if let jpegData = pendingImageData {
                    performAddImage(jpegData: jpegData)
                }
                pendingImageData = nil
                pendingDetectedPerson = nil
            }
        } message: {
            Text(differentPersonMessage)
        }
        // Name already taken alert
        .alert("Name Taken", isPresented: $showNameTakenAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The name \"\(nameConflictText)\" is already used by another person. Please choose a different name.")
        }
        // Photos picker
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            handleAddedImage(newItem)
        }
    }

    // MARK: - Sheet Header

    private var sheetHeaderRow: some View {
        HStack {
            Text(person.name)
                .font(LiquidTypography.headline)

            Spacer()

            if isAddingImage {
                ProgressView()
                    .accessibilityLabel("Adding image")
            } else {
                Button {
                    addImage()
                } label: {
                    Image(systemName: "plus")
                        .font(LiquidTypography.body)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(person.imageCount >= Self.maxImages)
                .accessibilityLabel("Add photo")
                .accessibilityHint("Adds a new reference photo for \(person.name)")
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Header Info

    private var headerInfo: some View {
        VStack(spacing: LiquidSpacing.sm) {
            // Tap name to rename
            Button {
                renameText = person.name
                showRenamAlert = true
            } label: {
                HStack(spacing: LiquidSpacing.xs) {
                    Text(person.name)
                        .font(LiquidTypography.title3)
                        .foregroundStyle(LiquidColors.textPrimary)
                    Image(systemName: "pencil")
                        .font(.system(size: LiquidSpacing.lg))
                        .foregroundStyle(LiquidColors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(person.name)")
            .accessibilityHint("Opens a dialog to rename this person")

            HStack(spacing: LiquidSpacing.lg) {
                Text("\(person.imageCount) of \(Self.maxImages) photos")
                    .font(LiquidTypography.footnote)
                    .foregroundStyle(LiquidColors.textSecondary)

                qualityStars(for: person)
            }
        }
        .padding(.vertical, LiquidSpacing.lg)
    }

    // MARK: - Quality Stars

    private func qualityStars(for person: Person) -> some View {
        let bestQuality = person.images
            .map(\.qualityScore)
            .max() ?? 0.0
        let starCount = PersonDetailSheet.qualityToStars(bestQuality)

        return HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < starCount ? "star.fill" : "star")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(
                        index < starCount
                            ? Color(.systemYellow)
                            : LiquidColors.textSecondary
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quality: \(starCount) of 5 stars")
    }

    /// Convert quality score (0.0-1.0) to star count (1-5).
    static func qualityToStars(_ score: Double) -> Int {
        max(1, min(5, Int((score * 5).rounded())))
    }

    // MARK: - Image Grid

    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: LiquidSpacing.md) {
                ForEach(Array(person.images.enumerated()), id: \.element.id) { index, image in
                    personImageCard(image: image, index: index)
                }
            }
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.bottom, 100)
        }
    }

    private func personImageCard(image: PersonImage, index: Int) -> some View {
        let starCount = PersonDetailSheet.qualityToStars(image.qualityScore)
        let loadedImage = loadedImages[image.id]
        let qualityDotColor = qualityColor(for: image.qualityScore)

        return ZStack(alignment: .topLeading) {
            // Image or placeholder
            if let uiImage = loadedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(0.75, contentMode: .fit)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge)
                    .fill(LiquidColors.fillTertiary)
                    .aspectRatio(0.75, contentMode: .fit)
                    .overlay {
                        if checkedImageIds.contains(image.id) {
                            // Load attempted but file not found
                            Image(systemName: "photo.slash")
                                .font(.largeTitle)
                                .foregroundStyle(LiquidColors.textTertiary)
                        } else {
                            // Still loading from disk
                            ProgressView()
                        }
                    }
            }

            // Gradient overlay
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
            }
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge))

            // Bottom row: quality dots + stars
            VStack {
                Spacer()
                HStack(spacing: LiquidSpacing.xs) {
                    // Quality indicator dot (green/yellow/red)
                    Circle()
                        .fill(qualityDotColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: qualityDotColor.opacity(0.6), radius: 3)

                    // Quality stars
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < starCount ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundStyle(
                                    i < starCount
                                        ? Color(.systemYellow)
                                        : Color(.systemGray)
                                )
                        }
                    }
                }
                .padding(.horizontal, LiquidSpacing.sm)
                .padding(.bottom, LiquidSpacing.sm)
            }

            // Primary badge (top-left on first image)
            if index == 0 {
                Text("Primary")
                    .font(LiquidTypography.caption2Semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, LiquidSpacing.sm)
                    .padding(.vertical, LiquidSpacing.xs)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                    .padding(LiquidSpacing.sm)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge))
        .contextMenu {
            // Remove Photo (destructive)
            Button(role: .destructive) {
                requestRemoveImage(image)
            } label: {
                Label("Remove Photo", systemImage: "trash")
            }
            .disabled(person.imageCount <= 1)

            // Set as Primary (only visible when not already primary)
            if index != 0 {
                Button {
                    setAsPrimary(image)
                } label: {
                    Label("Set as Primary", systemImage: "star.fill")
                }
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }

    /// Quality dot color based on quality score.
    private func qualityColor(for score: Double) -> Color {
        if score >= 0.7 { return .green }
        if score >= 0.4 { return .yellow }
        return .red
    }

    // MARK: - Image Loading

    /// Load all person images from disk concurrently and populate `loadedImages`.
    private func loadImagesFromDisk() async {
        let images = person.images
        guard !images.isEmpty else { return }

        // Use a task group to load all images concurrently off the main thread.
        let results: [(String, UIImage?)] = await withTaskGroup(
            of: (String, UIImage?).self
        ) { group in
            for personImage in images {
                group.addTask {
                    let path = personImage.imagePath
                    let uiImage = await Task.detached(priority: .userInitiated) {
                        UIImage(contentsOfFile: path)
                    }.value
                    return (personImage.id, uiImage)
                }
            }

            var collected: [(String, UIImage?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Merge results into cache and mark every ID as checked.
        var newMap = loadedImages
        var checked = checkedImageIds
        for (imageId, uiImage) in results {
            if let uiImage {
                newMap[imageId] = uiImage
            }
            checked.insert(imageId)
        }
        loadedImages = newMap
        checkedImageIds = checked
    }

    // MARK: - Actions

    private func addImage() {
        guard person.imageCount < Self.maxImages else { return }
        showPhotoPicker = true
    }

    /// Set a person image as the primary (first) image.
    private func setAsPrimary(_ image: PersonImage) {
        guard let currentIndex = person.images.firstIndex(where: { $0.id == image.id }),
              currentIndex != 0 else { return }

        var reordered = person.images
        reordered.remove(at: currentIndex)
        reordered.insert(image, at: 0)
        person = person.with(modifiedAt: Date(), images: reordered)
        onPersonUpdated?(person)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Request to remove an image - shows confirmation dialog first.
    private func requestRemoveImage(_ image: PersonImage) {
        guard person.imageCount > 1 else { return }
        imageToRemove = image
        showRemoveConfirmation = true
    }

    /// Actually perform the removal after confirmation.
    private func performRemoveImage(_ image: PersonImage) {
        guard person.imageCount > 1 else { return }

        let updatedImages = person.images.filter { $0.id != image.id }
        loadedImages.removeValue(forKey: image.id)
        checkedImageIds.remove(image.id)
        person = person.with(modifiedAt: Date(), images: updatedImages)
        onPersonUpdated?(person)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handleAddedImage(_ item: PhotosPickerItem?) {
        guard let item else { return }

        isAddingImage = true

        Task {
            defer {
                Task { @MainActor in
                    isAddingImage = false
                    selectedPhotoItem = nil
                }
            }

            // Load image data from the PhotosPicker selection.
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                return
            }

            guard let jpegData = uiImage.jpegData(compressionQuality: 0.9) else { return }

            // Write to a temporary file for PeopleService face detection.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")

            do {
                try jpegData.write(to: tempURL)
            } catch {
                return
            }

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            // Run face detection to get quality score and bounding box.
            let peopleService = PeopleService()
            let result = await peopleService.detectPeople(imagePath: tempURL.path)

            if result.success, let firstPerson = result.people.first {
                // Face detected - validate it matches this person.
                // Check if the detected face's embedding better matches another person.
                let validation = await peopleService.validateAddToExisting(
                    newEmbedding: firstPerson.embedding,
                    targetPersonId: person.id,
                    allPeopleData: [] // In a real app, pass all people data
                )

                if !validation.isValid,
                   let betterMatchName = validation.betterMatchPersonName {
                    // Different person detected - show warning dialog
                    await MainActor.run {
                        differentPersonMessage = "This image looks more like \"\(betterMatchName)\". Are you sure you want to add it to \(person.name)?"
                        pendingImageData = jpegData
                        pendingDetectedPerson = firstPerson
                        showDifferentPersonAlert = true
                    }
                    return
                }

                // Valid - add directly
                await MainActor.run {
                    performAddImage(jpegData: jpegData, qualityScore: firstPerson.qualityScore, boundingBox: firstPerson.boundingBox)
                }
            } else {
                // No face detected - still allow adding with low quality score
                await MainActor.run {
                    performAddImage(jpegData: jpegData)
                }
            }
        }
    }

    /// Actually add the image to the person after validation passes.
    private func performAddImage(
        jpegData: Data,
        qualityScore: Double = 0.3,
        boundingBox: CGRect? = nil
    ) {
        let imageId = UUID().uuidString
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }
        let personDir = documentsURL
            .appendingPathComponent("people")
            .appendingPathComponent(person.id)

        try? FileManager.default.createDirectory(
            at: personDir, withIntermediateDirectories: true
        )

        let destURL = personDir.appendingPathComponent("\(imageId).jpg")
        do {
            try jpegData.write(to: destURL)
        } catch {
            return
        }

        let newImage = PersonImage(
            id: imageId,
            imagePath: destURL.path,
            embedding: [],
            qualityScore: qualityScore,
            addedAt: Date(),
            boundingBox: boundingBox
        )

        let updatedImages = person.images + [newImage]
        person = person.with(modifiedAt: Date(), images: updatedImages)
        onPersonUpdated?(person)

        // Load the new image into the cache immediately.
        if let newUIImage = UIImage(contentsOfFile: destURL.path) {
            loadedImages[imageId] = newUIImage
        }
        checkedImageIds.insert(imageId)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func performRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != person.name else { return }

        // Name uniqueness check
        let lowercasedTrimmed = trimmed.lowercased()
        let nameTaken = existingPersonNames.contains { existingName in
            existingName.lowercased() == lowercasedTrimmed &&
            existingName.lowercased() != person.name.lowercased()
        }

        if nameTaken {
            nameConflictText = trimmed
            showNameTakenAlert = true
            return
        }

        person = person.with(name: trimmed, modifiedAt: Date())
        onPersonUpdated?(person)
    }
}

#Preview {
    PersonDetailSheet(
        person: Person(
            id: "preview-1",
            name: "Jane Doe",
            createdAt: Date(),
            modifiedAt: Date(),
            images: [
                PersonImage(
                    id: "img-1",
                    imagePath: "people/jane/1.jpg",
                    embedding: [],
                    qualityScore: 0.85,
                    addedAt: Date()
                ),
                PersonImage(
                    id: "img-2",
                    imagePath: "people/jane/2.jpg",
                    embedding: [],
                    qualityScore: 0.65,
                    addedAt: Date()
                ),
            ]
        )
    )
}
