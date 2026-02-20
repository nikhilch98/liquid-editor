// AddPersonSheet.swift
// LiquidEditor
//
// Flow for adding a new person to the People library.
//
// Multi-step sheet: image picking -> face detection -> duplicate check
// -> name entry -> save. Uses PHPickerViewController for photo
// selection and Vision framework for face detection via PeopleService.
//
// Matches Flutter AddPersonSheet layout:
// - After detecting a face, checks for duplicates against existing people
// - If duplicate found, shows alert with Cancel / Add to Existing / Create New
// - Before saving, validates name uniqueness among existing people
//
// Pure iOS 26 SwiftUI with native Liquid Glass styling.

import PhotosUI
import SwiftUI

// MARK: - AddPersonState

/// State machine for the add-person flow.
enum AddPersonState: String, CaseIterable, Sendable {
    case initial
    case pickingImage
    case detecting
    case selectingPerson
    case enteringName
    case checkingDuplicate
    case saving
    case error
}

// MARK: - DuplicateAction

/// Actions available when a duplicate person is detected.
private enum DuplicateAction {
    case cancel
    case addToExisting
    case createNew
}

// MARK: - AddPersonSheet

/// Sheet for adding a new person with face detection.
///
/// Guides the user through:
/// 1. Pick a photo from the library
/// 2. Detect faces in the image
/// 3. Select a person (if multiple detected)
/// 4. Check for duplicates against existing people
/// 5. Enter a name and save
struct AddPersonSheet: View {

    // MARK: - State

    @State private var flowState: AddPersonState = .initial
    @State private var errorMessage: String?
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var detectionResult: PersonDetectionResult?
    @State private var selectedPerson: DetectedPerson?
    @State private var personName = ""
    @State private var showPhotoPicker = false

    /// Duplicate detection alert state.
    @State private var showDuplicateAlert = false
    @State private var duplicateResult: DuplicateCheckResult?

    /// Name uniqueness alert state.
    @State private var showNameExistsAlert = false

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldFocused: Bool

    /// Existing people for duplicate and name checks.
    let existingPeople: [Person]

    /// Called when a person is successfully created.
    let onPersonAdded: ((Person) -> Void)?

    /// Called when an image should be added to an existing person.
    let onAddToExisting: ((String, DetectedPerson) -> Void)?

    // MARK: - Init

    init(
        existingPeople: [Person] = [],
        onPersonAdded: ((Person) -> Void)? = nil,
        onAddToExisting: ((String, DetectedPerson) -> Void)? = nil
    ) {
        self.existingPeople = existingPeople
        self.onPersonAdded = onPersonAdded
        self.onAddToExisting = onAddToExisting
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Custom header row
            headerRow
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()
                .padding(.horizontal)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiquidColors.background)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedImageItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedImageItem) { _, newItem in
            handleImageSelection(newItem)
        }
        .onAppear {
            showPhotoPicker = true
            flowState = .pickingImage
        }
        .alert("Person Already Exists", isPresented: $showDuplicateAlert) {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            Button("Add to Existing") {
                handleAddToExisting()
            }
            Button("Create New") {
                flowState = .enteringName
                nameFieldFocused = true
            }
        } message: {
            if let result = duplicateResult, let matchName = result.matchedPersonName {
                Text("This looks like \"\(matchName)\"\nSimilarity: \(Int(result.similarity * 100))%")
            } else {
                Text("A similar person was found.")
            }
        }
        .alert("Name Already Exists", isPresented: $showNameExistsAlert) {
            Button("OK") {
                flowState = .enteringName
                nameFieldFocused = true
            }
        } message: {
            Text("A person with this name already exists. Please choose a different name.")
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Add Person")
                .font(LiquidTypography.headline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityHint("Dismisses the add person sheet")
        }
    }

    // MARK: - Content Router

    @ViewBuilder
    private var content: some View {
        switch flowState {
        case .initial, .pickingImage:
            loadingState(message: "Opening photo library...")

        case .detecting:
            loadingState(message: "Detecting people...")

        case .selectingPerson:
            personSelector

        case .checkingDuplicate:
            loadingState(message: "Checking for duplicates...")

        case .enteringName:
            nameInputView

        case .saving:
            loadingState(message: "Saving...")

        case .error:
            errorView
        }
    }

    // MARK: - Loading State

    private func loadingState(message: String) -> some View {
        VStack(spacing: LiquidSpacing.lg) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(LiquidTypography.footnote)
                .foregroundStyle(LiquidColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error State

    private var errorView: some View {
        VStack(spacing: LiquidSpacing.lg) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(LiquidColors.error.opacity(0.7))
                .accessibilityHidden(true)

            Text(errorMessage ?? "An error occurred")
                .font(LiquidTypography.body)
                .foregroundStyle(LiquidColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiquidSpacing.xxxl)

            Button("Try Again") {
                retryFromStart()
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Restarts the add person flow")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Person Selector

    private var personSelector: some View {
        VStack(spacing: LiquidSpacing.sm) {
            if let result = detectionResult {
                Text("\(result.personCount) people detected")
                    .font(LiquidTypography.body)
                    .foregroundStyle(LiquidColors.textPrimary)

                Text("Tap to select the person you want to add")
                    .font(LiquidTypography.footnote)
                    .foregroundStyle(LiquidColors.textSecondary)
            }

            // Image with bounding boxes
            if let imageData = selectedImageData,
               let uiImage = UIImage(data: imageData) {
                GeometryReader { geometry in
                    let imageSize = uiImage.size
                    let scale = min(
                        geometry.size.width / imageSize.width,
                        geometry.size.height / imageSize.height
                    )
                    let displaySize = CGSize(
                        width: imageSize.width * scale,
                        height: imageSize.height * scale
                    )

                    ZStack {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium))

                        // Bounding boxes for detected people
                        if let result = detectionResult {
                            ForEach(result.people, id: \.id) { person in
                                let box = person.boundingBox
                                let rect = CGRect(
                                    x: (box.origin.x / imageSize.width) * displaySize.width,
                                    y: (box.origin.y / imageSize.height) * displaySize.height,
                                    width: (box.width / imageSize.width) * displaySize.width,
                                    height: (box.height / imageSize.height) * displaySize.height
                                )

                                Rectangle()
                                    .stroke(Color.accentColor, lineWidth: 2)
                                    .fill(Color.accentColor.opacity(0.2))
                                    .frame(width: rect.width, height: rect.height)
                                    .position(
                                        x: rect.midX,
                                        y: rect.midY
                                    )
                                    .accessibilityLabel("Person \(person.id)")
                                    .accessibilityHint("Tap to select this person")
                                    .accessibilityAddTraits(.isButton)
                                    .onTapGesture {
                                        selectPerson(person)
                                    }
                            }
                        }
                    }
                    .frame(width: displaySize.width, height: displaySize.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(LiquidSpacing.lg)
            }
        }
    }

    // MARK: - Name Input View

    private var nameInputView: some View {
        VStack(spacing: 0) {
            // Preview image
            if let imageData = selectedImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                    .padding(.top, LiquidSpacing.xxl)
            }

            // Quality indicator
            if let person = selectedPerson {
                qualityStars(score: person.qualityScore)
                    .padding(.top, LiquidSpacing.lg)
            }

            // Name input
            TextField("Enter name", text: $personName)
                .font(LiquidTypography.title3)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFieldFocused)
                .onSubmit { savePerson() }
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.xxl)
                .accessibilityLabel("Person name")
                .accessibilityHint("Enter a name for this person")

            Text("Photos from different angles help improve tracking")
                .font(LiquidTypography.caption)
                .foregroundStyle(LiquidColors.textTertiary)
                .padding(.top, LiquidSpacing.sm)

            Spacer()

            // Save button
            Button {
                savePerson()
            } label: {
                Text("Save")
                    .font(LiquidTypography.bodyMedium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(personName.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.bottom, LiquidSpacing.xxl)
            .accessibilityLabel("Save person")
            .accessibilityHint("Saves the person with the entered name")
        }
        .onAppear {
            nameFieldFocused = true
        }
    }

    // MARK: - Quality Stars

    private func qualityStars(score: Double) -> some View {
        let starCount = max(1, min(5, Int((score * 5).rounded())))

        return HStack(spacing: LiquidSpacing.xxs) {
            Text("Quality: ")
                .font(LiquidTypography.footnote)
                .foregroundStyle(LiquidColors.textSecondary)

            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < starCount ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        index < starCount
                            ? Color(.systemYellow)
                            : LiquidColors.textSecondary
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quality \(starCount) out of 5 stars")
    }

    // MARK: - Actions

    private func handleImageSelection(_ item: PhotosPickerItem?) {
        guard let item else {
            dismiss()
            return
        }

        flowState = .detecting

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                showError("Failed to load image data")
                return
            }

            selectedImageData = data

            // Write image to a temporary file for Vision framework processing.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")

            do {
                try data.write(to: tempURL)
            } catch {
                showError("Failed to prepare image for detection")
                return
            }

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            // Detect faces via PeopleService.
            let peopleService = PeopleService()
            let result = await peopleService.detectPeople(imagePath: tempURL.path)

            if result.success {
                await MainActor.run {
                    detectionResult = result
                }

                if result.personCount > 1 {
                    // Multiple faces: let the user pick which person to add.
                    await MainActor.run {
                        flowState = .selectingPerson
                    }
                } else if let firstPerson = result.people.first {
                    // Single face: auto-select and check for duplicates.
                    await MainActor.run {
                        selectedPerson = firstPerson
                    }
                    await checkForDuplicates(person: firstPerson, service: peopleService)
                } else {
                    // Success but no people array (shouldn't happen).
                    await MainActor.run {
                        flowState = .enteringName
                    }
                }
            } else {
                // No faces detected or quality issue.
                await MainActor.run {
                    showError(result.errorMessage ?? "No face detected. Please try another photo with a clear face.")
                }
            }
        }
    }

    private func selectPerson(_ person: DetectedPerson) {
        selectedPerson = person

        // Check for duplicates after selection.
        Task {
            let peopleService = PeopleService()
            await checkForDuplicates(person: person, service: peopleService)
        }
    }

    /// Check if the detected person matches any existing person.
    private func checkForDuplicates(
        person: DetectedPerson,
        service: PeopleService
    ) async {
        guard !existingPeople.isEmpty, !person.embedding.isEmpty else {
            // No existing people or no embedding: skip duplicate check.
            await MainActor.run {
                flowState = .enteringName
                nameFieldFocused = true
            }
            return
        }

        await MainActor.run {
            flowState = .checkingDuplicate
        }

        // Build embedding data from existing people.
        let peopleData = existingPeople.map { p in
            PersonEmbedding(
                id: p.id,
                name: p.name,
                embeddings: p.images.map { img in
                    EmbeddingEntry(
                        imageId: img.id,
                        embedding: img.embedding,
                        qualityScore: img.qualityScore
                    )
                }
            )
        }

        let result = await service.findDuplicates(
            newEmbedding: person.embedding,
            peopleData: peopleData
        )

        await MainActor.run {
            if result.isDuplicate, result.matchedPersonName != nil {
                // Show duplicate alert with 3 options.
                duplicateResult = result
                showDuplicateAlert = true
            } else {
                // No duplicate found: proceed to name entry.
                flowState = .enteringName
                nameFieldFocused = true
            }
        }
    }

    /// Handle adding the detected image to an existing matched person.
    private func handleAddToExisting() {
        guard let result = duplicateResult,
              let matchedId = result.matchedPersonId,
              let person = selectedPerson else {
            dismiss()
            return
        }

        flowState = .saving
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        onAddToExisting?(matchedId, person)
        dismiss()
    }

    /// Check if a name is already used by an existing person.
    private func isNameUsed(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return existingPeople.contains { $0.name.lowercased() == lowered }
    }

    private func savePerson() {
        let name = personName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            showError("Please enter a name")
            return
        }

        // Check name uniqueness.
        if isNameUsed(name) {
            showNameExistsAlert = true
            return
        }

        flowState = .saving

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Create the Person (in production, this delegates to PeopleService).
        let person = Person(
            id: UUID().uuidString,
            name: name,
            createdAt: Date(),
            modifiedAt: Date(),
            images: []
        )

        onPersonAdded?(person)
        dismiss()
    }

    private func showError(_ message: String) {
        errorMessage = message
        flowState = .error
    }

    private func retryFromStart() {
        flowState = .initial
        errorMessage = nil
        selectedImageData = nil
        detectionResult = nil
        selectedPerson = nil
        personName = ""
        duplicateResult = nil
        showPhotoPicker = true
        flowState = .pickingImage
    }
}
