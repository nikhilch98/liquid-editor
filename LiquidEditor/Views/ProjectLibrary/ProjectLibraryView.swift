// ProjectLibraryView.swift
// LiquidEditor
//
// Home screen for the Project Library.
// Displays projects and people as two tab pages with a bottom tab bar,
// a floating action button, and inline search toggle.
//
// Matches Flutter layout:
// - 2-tab bottom tab bar (Projects/People) instead of 3-tab segmented picker
// - FAB at bottom-right for add actions
// - Settings gear icon in navigation bar trailing
// - Toggle search button that reveals inline TextField
// - Simple PhotosPicker for adding media (no import source sheet)
//
// Pure SwiftUI with iOS 26 native styling. No Material Design.

import PhotosUI
import SwiftUI

// MARK: - ProjectLibraryView

/// The main Project Library home screen.
///
/// Contains a bottom tab bar for switching between Projects and People tabs.
/// Each tab displays a grid of cards with contextual actions.
/// Supports search (via toggle button), sort, and pull-to-refresh.
struct ProjectLibraryView: View {

    @State private var viewModel: ProjectLibraryViewModel
    @Environment(AppCoordinator.self) private var coordinator

    /// Currently selected tab index (0 = Projects, 1 = People).
    @State private var currentTabIndex: Int = 0

    /// Whether inline search is visible (Projects tab).
    @State private var isSearchActive: Bool = false

    /// PhotosPicker selection for importing media.
    @State private var selectedPhotoItem: PhotosPickerItem?

    /// Whether the rename project alert is shown.
    @State private var showRenameProjectAlert: Bool = false

    /// Project being renamed.
    @State private var renameProjectId: String?

    /// Text for project rename.
    @State private var renameProjectText: String = ""

    /// Whether the projects grid is in selection/edit mode.
    @State private var isEditMode: Bool = false

    /// Set of selected project IDs in edit mode.
    @State private var selectedProjectIds: Set<String> = []

    /// Whether the batch delete confirmation dialog is showing.
    @State private var showBatchDeleteConfirmation: Bool = false

    /// IP16-2: system drag-drop receiver for incoming files.
    @State private var dragDropReceiver = DragDropReceiver()

    /// IP16-2: drop target state (outline/highlight while hovering).
    @State private var isDropTargeted: Bool = false

    /// Initialize with injected repository dependencies.
    init(
        projectRepository: any ProjectRepositoryProtocol,
        mediaAssetRepository: any MediaAssetRepositoryProtocol,
        mediaImportService: MediaImportService? = nil
    ) {
        _viewModel = State(
            initialValue: ProjectLibraryViewModel(
                projectRepository: projectRepository,
                mediaAssetRepository: mediaAssetRepository,
                mediaImportService: mediaImportService
            )
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(white: 0.12),
                    Color.black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Native TabView with iOS 26 Liquid Glass tab bar
            TabView(selection: $currentTabIndex) {
                Tab("Projects", systemImage: "square.grid.2x2", value: 0) {
                    projectsTab
                }

                Tab("People", systemImage: "person.2", value: 1) {
                    peopleTab
                }
            }

            // Floating action button (above tab bar)
            floatingActionButton
                .padding(.trailing, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.tabBarHeight + LiquidSpacing.xxxl)
        }
        // IP16-3: multitasking layout — publishes \.layoutMode to children.
        .observeMultitaskingLayout()
        // IP16-2: accept drag-drop from external apps at the library root.
        .dragDropReceiver(dragDropReceiver, isTargeted: $isDropTargeted)
        .alert(
            "Error",
            isPresented: .init(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.clearError() } }
            ),
            actions: {
                Button("OK") {
                    viewModel.clearError()
                }
            },
            message: {
                if let error = viewModel.error {
                    Text(error)
                }
            }
        )
        .alert(
            "Rename Project",
            isPresented: $showRenameProjectAlert,
            actions: {
                TextField("Name", text: $renameProjectText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    guard let projectId = renameProjectId else { return }
                    // Rename would be handled by ViewModel in production
                    _ = projectId
                    renameProjectId = nil
                    renameProjectText = ""
                }
            },
            message: {
                Text("Enter a new name for this project.")
            }
        )
        .task {
            await viewModel.loadProjects()
            await viewModel.loadPeople()
        }
        .onChange(of: currentTabIndex) { _, _ in
            isSearchActive = false
            viewModel.searchText = ""
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            selectedPhotoItem = nil
            Task {
                // Load and validate the video before creating the project.
                if let projectId = await viewModel.createProjectFromVideo(item: newItem) {
                    coordinator.navigateToEditor(projectId: projectId)
                }
            }
        }
        .overlay {
            if viewModel.isImporting {
                importingOverlay
            }
        }
    }

    // MARK: - Projects Tab

    private var projectsTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Inline search bar (visible when toggled)
                if isSearchActive {
                    inlineSearchBar(prompt: "Search projects...")
                }

                // Content
                projectsContent
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                projectsToolbar
            }
            .refreshable {
                await viewModel.loadProjects()
            }
        }
    }

    // MARK: - People Tab

    private var peopleTab: some View {
        NavigationStack {
            PeopleGridView(viewModel: viewModel)
                .navigationTitle("People")
                .navigationBarTitleDisplayMode(.large)
                .refreshable {
                    await viewModel.loadPeople()
                }
        }
    }

    // MARK: - Floating Action Button

    @ViewBuilder
    private var floatingActionButton: some View {
        if currentTabIndex == 0 {
            // Projects tab: open PhotosPicker for importing video
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .videos
            ) {
                fabIcon
            }
            .buttonStyle(.plain)
        } else {
            // People tab: add person
            Button {
                Task { await viewModel.addPerson() }
            } label: {
                fabIcon
            }
            .buttonStyle(.plain)
        }
    }

    /// Shared FAB icon with Liquid Glass styling.
    private var fabIcon: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 56, height: 56)
            .glassEffect(style: .thin, cornerRadius: 28)
    }

    // MARK: - Inline Search Bar

    private func inlineSearchBar(prompt: String) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $viewModel.searchText)
                .textFieldStyle(.plain)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(LiquidSpacing.sm)
        .background(LiquidColors.fillTertiary)
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall + 2, style: .continuous))
        .padding(.horizontal, LiquidSpacing.xl)
        .padding(.vertical, LiquidSpacing.sm)
    }

    // MARK: - Projects Content

    @ViewBuilder
    private var projectsContent: some View {
        if viewModel.isLoading && viewModel.projects.isEmpty {
            loadingView
        } else if viewModel.projects.isEmpty {
            emptyProjectsView
        } else if viewModel.filteredProjects.isEmpty {
            noMatchingProjectsView
        } else {
            projectsGrid
        }
    }

    private var projectsGrid: some View {
        ScrollView {
            VStack(spacing: LiquidSpacing.lg) {
                // Storage usage summary bar
                if viewModel.storageBreakdown.totalBytes > 0 {
                    StorageUsageSummaryView(breakdown: viewModel.storageBreakdown)
                        .padding(.horizontal, LiquidSpacing.xl)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: LiquidSpacing.lg),
                        GridItem(.flexible(), spacing: LiquidSpacing.lg),
                    ],
                    spacing: LiquidSpacing.lg
                ) {
                    ForEach(viewModel.filteredProjects, id: \.id) { project in
                        projectCardCell(project)
                    }
                }
                .padding(.horizontal, LiquidSpacing.xl)
            }
            .padding(.top, 0)
            .padding(.bottom, 120)
        }
        .overlay(alignment: .bottom) {
            if isEditMode && !selectedProjectIds.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        showBatchDeleteConfirmation = true
                    } label: {
                        Label(
                            "Delete \(selectedProjectIds.count) Project\(selectedProjectIds.count == 1 ? "" : "s")",
                            systemImage: "trash"
                        )
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: selectedProjectIds.isEmpty)
            }
        }
        .confirmationDialog(
            "Delete \(selectedProjectIds.count) project\(selectedProjectIds.count == 1 ? "" : "s")?",
            isPresented: $showBatchDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteProjects(ids: selectedProjectIds)
                    withAnimation {
                        selectedProjectIds.removeAll()
                        isEditMode = false
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    /// Renders a single project card cell with selection overlay in edit mode.
    private func projectCardCell(_ project: ProjectMetadata) -> some View {
        ProjectCardView(
            project: project,
            onOpen: {
                coordinator.navigateToEditor(projectId: project.id)
            },
            onDuplicate: {
                Task { await viewModel.duplicateProject(id: project.id) }
            },
            onRename: {
                renameProjectId = project.id
                renameProjectText = project.name
                showRenameProjectAlert = true
            },
            onDelete: {
                Task { await viewModel.deleteProject(id: project.id) }
            }
        )
        .aspectRatio(0.8, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            if isEditMode {
                Image(systemName: selectedProjectIds.contains(project.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selectedProjectIds.contains(project.id) ? .white : Color.primary.opacity(0.6))
                    .background(
                        Circle()
                            .fill(selectedProjectIds.contains(project.id) ? Color.accentColor : Color.clear)
                            .padding(2)
                    )
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode {
                withAnimation(.spring(response: 0.2)) {
                    if selectedProjectIds.contains(project.id) {
                        selectedProjectIds.remove(project.id)
                    } else {
                        selectedProjectIds.insert(project.id)
                    }
                }
            } else {
                coordinator.navigateToEditor(projectId: project.id)
            }
        }
    }

    // MARK: - Empty States

    private var noMatchingProjectsView: some View {
        VStack {
            Spacer()
                .frame(height: 60)
            Text("No matching projects")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyProjectsView: some View {
        ContentUnavailableView {
            Label("No Projects", systemImage: "film.stack")
        } description: {
            Text("Import a video to get started")
        } actions: {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .videos
            ) {
                Text("New Project")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading Library...")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, LiquidSpacing.sm)
            Spacer()
        }
    }

    /// Full-screen overlay shown while a video is being imported and validated.
    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            VStack(spacing: LiquidSpacing.lg) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Importing Video...")
                    .font(LiquidTypography.headline)
                    .foregroundStyle(.white)
                Text("Validating and preparing your video")
                    .font(LiquidTypography.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(LiquidSpacing.xxxl)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerXLarge, style: .continuous))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var projectsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 4) {
                // Select / Done toggle for edit mode
                Button(isEditMode ? "Done" : "Select") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isEditMode.toggle()
                        if !isEditMode {
                            selectedProjectIds.removeAll()
                        }
                    }
                }
                .fontWeight(isEditMode ? .semibold : .regular)

                if !isEditMode {
                    // Search toggle (hidden in edit mode to reduce clutter)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearchActive.toggle()
                            if !isSearchActive {
                                viewModel.searchText = ""
                            }
                        }
                    } label: {
                        Image(systemName: isSearchActive ? "xmark.circle.fill" : "magnifyingglass")
                    }

                    // Sort
                    sortMenu

                    // Settings
                    Button {
                        coordinator.navigateToSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortCriteria.allCases) { criteria in
                Button {
                    viewModel.sortCriteria = criteria
                } label: {
                    HStack {
                        Text(criteria.label)
                        if viewModel.sortCriteria == criteria {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
}

// MARK: - StorageUsageSummaryView

/// Displays a segmented storage usage bar with per-category breakdown.
///
/// Shows the total storage used across all projects as a horizontal
/// segmented bar colored by media type, with text labels beneath.
/// Uses Liquid Glass styling consistent with the iOS 26 design system.
private struct StorageUsageSummaryView: View {

    /// Storage breakdown data from the ViewModel.
    let breakdown: StorageBreakdown

    /// Bar segment height.
    private let barHeight: CGFloat = 8

    /// Minimum visible segment width fraction to avoid invisible slivers.
    private let minimumVisibleFraction: Double = 0.02

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            // Header: total storage label
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(breakdown.formattedTotal) used")
                    .font(LiquidTypography.subheadlineMedium)
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Segmented color bar
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    segmentCapsule(
                        fraction: breakdown.videoFraction,
                        color: .blue,
                        totalWidth: geometry.size.width
                    )
                    segmentCapsule(
                        fraction: breakdown.photoFraction,
                        color: .green,
                        totalWidth: geometry.size.width
                    )
                    segmentCapsule(
                        fraction: breakdown.audioFraction,
                        color: .orange,
                        totalWidth: geometry.size.width
                    )
                    segmentCapsule(
                        fraction: breakdown.otherFraction,
                        color: .gray,
                        totalWidth: geometry.size.width
                    )
                }
            }
            .frame(height: barHeight)
            .clipShape(Capsule())

            // Category labels
            HStack(spacing: LiquidSpacing.lg) {
                categoryLabel(color: .blue, title: "Video", size: breakdown.formattedVideo)
                categoryLabel(color: .green, title: "Photo", size: breakdown.formattedPhoto)
                categoryLabel(color: .orange, title: "Audio", size: breakdown.formattedAudio)
                Spacer()
            }
        }
        .padding(LiquidSpacing.md)
        .glassEffect(style: .thin, cornerRadius: LiquidSpacing.cornerMedium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Storage usage: \(breakdown.formattedTotal) total. Video \(breakdown.formattedVideo), Photo \(breakdown.formattedPhoto), Audio \(breakdown.formattedAudio)")
    }

    // MARK: - Segment Capsule

    /// A single colored bar segment proportional to its fraction.
    @ViewBuilder
    private func segmentCapsule(
        fraction: Double,
        color: Color,
        totalWidth: CGFloat
    ) -> some View {
        let effectiveFraction = fraction > 0 ? max(fraction, minimumVisibleFraction) : 0
        let segmentWidth = max(0, effectiveFraction * (totalWidth - 6)) // 6 = 3 * 2pt spacing

        if segmentWidth > 0 {
            RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                .fill(color)
                .frame(width: segmentWidth, height: barHeight)
        }
    }

    // MARK: - Category Label

    /// A colored dot with a label and size text.
    private func categoryLabel(color: Color, title: String, size: String) -> some View {
        HStack(spacing: LiquidSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(title): \(size)")
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#if DEBUG

private struct PreviewProjectRepository: ProjectRepositoryProtocol {
    func save(_ project: Project) async throws {}
    func load(id: String) async throws -> Project { throw RepositoryError.notFound(id) }
    func loadMetadata(id: String) async throws -> ProjectMetadata { throw RepositoryError.notFound(id) }
    func listMetadata() async throws -> [ProjectMetadata] {
        [
            ProjectMetadata(
                id: "1", name: "Beach Sunset", createdAt: .now.addingTimeInterval(-3600),
                modifiedAt: .now.addingTimeInterval(-1800), thumbnailPath: nil,
                timelineDurationMs: 45_000, clipCount: 3, fileSizeBytes: 52_428_800,
                version: 1, description: nil, tags: [], isFavorite: true, colorLabel: .blue
            ),
            ProjectMetadata(
                id: "2", name: "City Timelapse", createdAt: .now.addingTimeInterval(-86400),
                modifiedAt: .now.addingTimeInterval(-7200), thumbnailPath: nil,
                timelineDurationMs: 120_000, clipCount: 8, fileSizeBytes: 157_286_400,
                version: 1, description: nil, tags: [], isFavorite: false, colorLabel: nil
            ),
            ProjectMetadata(
                id: "3", name: "Wedding Highlight", createdAt: .now.addingTimeInterval(-172800),
                modifiedAt: .now.addingTimeInterval(-86400), thumbnailPath: nil,
                timelineDurationMs: 300_000, clipCount: 15, fileSizeBytes: 524_288_000,
                version: 1, description: nil, tags: [], isFavorite: false, colorLabel: .purple
            ),
        ]
    }
    func delete(id: String) async throws {}
    func exists(id: String) async -> Bool { false }
    func rename(id: String, newName: String) async throws {}
    func duplicate(id: String, newId: String, newName: String) async throws -> Project {
        throw RepositoryError.notFound(id)
    }
}

private struct PreviewMediaAssetRepository: MediaAssetRepositoryProtocol {
    func save(_ asset: MediaAsset) async throws {}
    func load(id: String) async throws -> MediaAsset { throw RepositoryError.notFound(id) }
    func loadByContentHash(_ hash: String) async throws -> [MediaAsset] { [] }
    func listAll() async throws -> [MediaAsset] { [] }
    func listForProject(projectId: String) async throws -> [MediaAsset] { [] }
    func delete(id: String) async throws {}
    func exists(id: String) async -> Bool { false }
    func updateLinkStatus(assetId: String, newRelativePath: String, isLinked: Bool) async throws {}
    func findUnlinkedAssets() async throws -> [MediaAsset] { [] }
}

#Preview("Project Library") {
    ProjectLibraryView(
        projectRepository: PreviewProjectRepository(),
        mediaAssetRepository: PreviewMediaAssetRepository()
    )
    .environment(AppCoordinator())
    .preferredColorScheme(.dark)
}

#endif
