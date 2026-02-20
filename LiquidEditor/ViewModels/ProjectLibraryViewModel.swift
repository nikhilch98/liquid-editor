// ProjectLibraryViewModel.swift
// LiquidEditor
//
// ViewModel for the Project Library home screen.
// Manages project listing, sorting, filtering, and CRUD operations.
//
// Uses @Observable macro (iOS 17+) with @MainActor isolation
// for safe UI-bound state management. Dependencies are injected
// via protocol references for testability.

import AVFoundation
import Foundation
import Observation
import PhotosUI
import SwiftUI

// MARK: - LibraryTab

/// Tabs available in the Project Library.
enum LibraryTab: String, CaseIterable, Sendable, Identifiable {
    case projects = "Projects"
    case media = "Media"
    case people = "People"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .projects: return "film.stack"
        case .media: return "photo.on.rectangle"
        case .people: return "person.2"
        }
    }
}

// MARK: - SortCriteria

/// Sorting options for the project library.
enum SortCriteria: String, CaseIterable, Sendable, Identifiable {
    case dateModifiedDesc = "Date Modified (Newest)"
    case dateModifiedAsc = "Date Modified (Oldest)"
    case dateCreatedDesc = "Date Created (Newest)"
    case dateCreatedAsc = "Date Created (Oldest)"
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"

    var id: String { rawValue }

    var label: String { rawValue }

    var systemImage: String {
        switch self {
        case .dateModifiedDesc, .dateCreatedDesc:
            return "arrow.down"
        case .dateModifiedAsc, .dateCreatedAsc:
            return "arrow.up"
        case .nameAsc:
            return "textformat.abc"
        case .nameDesc:
            return "textformat.abc"
        }
    }
}

// MARK: - MediaFilterType

/// Filter options for the media browser.
enum MediaFilterType: String, CaseIterable, Sendable, Identifiable {
    case all = "All"
    case video = "Video"
    case image = "Image"
    case audio = "Audio"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .video: return "video"
        case .image: return "photo"
        case .audio: return "waveform"
        }
    }
}

// MARK: - StorageBreakdown

/// Lightweight storage breakdown calculated from project metadata.
///
/// Provides approximate storage usage by media category, derived from
/// the `fileSizeBytes` on each `ProjectMetadata` entry. Since individual
/// project metadata does not distinguish between media types, this uses
/// a heuristic based on clip counts and known file-type distributions
/// typical for video editing projects.
struct StorageBreakdown: Sendable, Equatable {

    /// Estimated video storage in bytes.
    var videoBytes: Int64 = 0

    /// Estimated photo storage in bytes.
    var photoBytes: Int64 = 0

    /// Estimated audio storage in bytes.
    var audioBytes: Int64 = 0

    /// Other storage (thumbnails, project files, etc.) in bytes.
    var otherBytes: Int64 = 0

    /// Total storage across all categories.
    var totalBytes: Int64 { videoBytes + photoBytes + audioBytes + otherBytes }

    /// Formatted total size for display (e.g., "1.2 GB").
    var formattedTotal: String { Self.formatBytes64(totalBytes) }

    /// Formatted video size for display.
    var formattedVideo: String { Self.formatBytes64(videoBytes) }

    /// Formatted photo size for display.
    var formattedPhoto: String { Self.formatBytes64(photoBytes) }

    /// Formatted audio size for display.
    var formattedAudio: String { Self.formatBytes64(audioBytes) }

    /// Formatted other size for display.
    var formattedOther: String { Self.formatBytes64(otherBytes) }

    /// Fractional proportion of video storage (0.0 - 1.0).
    var videoFraction: Double {
        totalBytes > 0 ? Double(videoBytes) / Double(totalBytes) : 0
    }

    /// Fractional proportion of photo storage (0.0 - 1.0).
    var photoFraction: Double {
        totalBytes > 0 ? Double(photoBytes) / Double(totalBytes) : 0
    }

    /// Fractional proportion of audio storage (0.0 - 1.0).
    var audioFraction: Double {
        totalBytes > 0 ? Double(audioBytes) / Double(totalBytes) : 0
    }

    /// Fractional proportion of other storage (0.0 - 1.0).
    var otherFraction: Double {
        totalBytes > 0 ? Double(otherBytes) / Double(totalBytes) : 0
    }

    /// Format Int64 byte count into a human-readable string.
    private static func formatBytes64(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        if bytes < 1_073_741_824 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        }
        return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
    }
}

// MARK: - ProjectLibraryViewModel

/// ViewModel for the Project Library home screen.
///
/// Manages project metadata listing, sorting, searching, and
/// CRUD operations. Uses protocol-based dependency injection
/// for the project and media asset repositories.
@Observable
@MainActor
final class ProjectLibraryViewModel {

    // MARK: - Configuration Constants

    /// Default name for new projects.
    static let defaultProjectName = "Untitled Project"

    /// Default name for new people.
    static let defaultPersonName = "New Person"

    /// Suffix added to duplicated project names.
    static let duplicateProjectSuffix = " (Copy)"

    /// Shared ByteCountFormatter for file size display.
    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    // MARK: - State

    /// Loaded project metadata entries.
    private(set) var projects: [ProjectMetadata] = []

    /// Loaded media assets.
    private(set) var mediaAssets: [MediaAsset] = []

    /// Loaded people entries.
    private(set) var people: [Person] = []

    /// Currently selected tab.
    var selectedTab: LibraryTab = .projects

    /// Current sort criteria.
    var sortCriteria: SortCriteria = .dateModifiedDesc

    /// Current search text (bound to .searchable).
    var searchText: String = ""

    /// Current media filter type.
    var mediaFilter: MediaFilterType = .all

    /// Whether a loading operation is in progress.
    private(set) var isLoading: Bool = false

    /// Whether a video import is in progress.
    private(set) var isImporting: Bool = false

    /// Most recent error message, if any.
    private(set) var error: String?

    // MARK: - Dependencies

    private let projectRepository: any ProjectRepositoryProtocol
    private let mediaAssetRepository: any MediaAssetRepositoryProtocol
    private let personRepository: (any PersonRepositoryProtocol)?
    private let mediaImportService: MediaImportService?

    // MARK: - Init

    init(
        projectRepository: any ProjectRepositoryProtocol,
        mediaAssetRepository: any MediaAssetRepositoryProtocol,
        personRepository: (any PersonRepositoryProtocol)? = nil,
        mediaImportService: MediaImportService? = nil
    ) {
        self.projectRepository = projectRepository
        self.mediaAssetRepository = mediaAssetRepository
        self.personRepository = personRepository
        self.mediaImportService = mediaImportService
    }

    // MARK: - Computed Properties

    /// Projects filtered by search text and sorted by current criteria.
    var filteredProjects: [ProjectMetadata] {
        var result = projects

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { project in
                project.name.lowercased().contains(query) ||
                project.tags.contains { $0.lowercased().contains(query) }
            }
        }

        // Apply sort
        result.sort { lhs, rhs in
            switch sortCriteria {
            case .dateModifiedDesc:
                return lhs.modifiedAt > rhs.modifiedAt
            case .dateModifiedAsc:
                return lhs.modifiedAt < rhs.modifiedAt
            case .dateCreatedDesc:
                return lhs.createdAt > rhs.createdAt
            case .dateCreatedAsc:
                return lhs.createdAt < rhs.createdAt
            case .nameAsc:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .nameDesc:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            }
        }

        return result
    }

    /// Media assets filtered by type and search text.
    var filteredMediaAssets: [MediaAsset] {
        var result = mediaAssets

        // Apply type filter
        switch mediaFilter {
        case .all:
            break
        case .video:
            result = result.filter { $0.type == .video }
        case .image:
            result = result.filter { $0.type == .image }
        case .audio:
            result = result.filter { $0.type == .audio }
        }

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { asset in
                asset.originalFilename.lowercased().contains(query)
            }
        }

        return result
    }

    /// People filtered by search text.
    var filteredPeople: [Person] {
        guard !searchText.isEmpty else { return people }
        let query = searchText.lowercased()
        return people.filter { $0.name.lowercased().contains(query) }
    }

    /// Storage breakdown calculated from project metadata.
    ///
    /// Since `ProjectMetadata.fileSizeBytes` represents the total project
    /// size without a per-media-type split, we use a heuristic:
    /// - 85% of total size is attributed to video (dominant media type)
    /// - 5% to photos (thumbnails, stills)
    /// - 5% to audio (extracted audio, music tracks)
    /// - 5% to other (project files, caches)
    var storageBreakdown: StorageBreakdown {
        let totalBytes = projects.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
        guard totalBytes > 0 else { return StorageBreakdown() }

        let videoBytes = Int64(Double(totalBytes) * 0.85)
        let photoBytes = Int64(Double(totalBytes) * 0.05)
        let audioBytes = Int64(Double(totalBytes) * 0.05)
        let otherBytes = totalBytes - videoBytes - photoBytes - audioBytes

        return StorageBreakdown(
            videoBytes: videoBytes,
            photoBytes: photoBytes,
            audioBytes: audioBytes,
            otherBytes: otherBytes
        )
    }

    // MARK: - Data Loading

    /// Load all projects from the repository.
    func loadProjects() async {
        isLoading = true
        error = nil

        do {
            projects = try await projectRepository.listMetadata()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Load all media assets from the repository.
    func loadMediaAssets() async {
        isLoading = true
        error = nil

        do {
            mediaAssets = try await mediaAssetRepository.listAll()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Load all people from the person repository.
    func loadPeople() async {
        guard let personRepository else {
            // No person repository injected; nothing to load.
            return
        }

        isLoading = true
        error = nil

        do {
            people = try await personRepository.listAll()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Load data for the current tab.
    func loadCurrentTab() async {
        switch selectedTab {
        case .projects:
            await loadProjects()
        case .media:
            await loadMediaAssets()
        case .people:
            await loadPeople()
        }
    }

    // MARK: - Project CRUD

    /// Create a new empty project.
    ///
    /// - Parameter name: Display name for the new project (defaults to "Untitled Project").
    /// - Returns: The ID of the newly created project, or nil if creation failed.
    func createProject(name: String = ProjectLibraryViewModel.defaultProjectName) async -> String? {
        let now = Date()
        let project = Project(
            name: name,
            sourceVideoPath: "",
            createdAt: now,
            modifiedAt: now
        )

        do {
            try await projectRepository.save(project)
            await loadProjects()
            return project.id
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Create a new project from a selected PhotosPickerItem.
    ///
    /// Loads the video data, validates it is a playable video file using
    /// AVURLAsset, then creates and saves a project with the source video path.
    ///
    /// - Parameter item: The PhotosPickerItem selected by the user.
    /// - Returns: The ID of the newly created project, or nil if import failed.
    func createProjectFromVideo(item: PhotosPickerItem) async -> String? {
        isImporting = true
        defer { isImporting = false }

        do {
            // Load video as a transferable Movie (URL-backed).
            guard let videoData = try await item.loadTransferable(type: Data.self) else {
                error = "Could not load video from photo library."
                return nil
            }

            // Write to a temporary file to validate with AVURLAsset.
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try videoData.write(to: tempURL)

            // Validate the file is a playable video.
            let asset = AVURLAsset(url: tempURL)
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)

            guard !videoTracks.isEmpty else {
                // Clean up temp file.
                try? FileManager.default.removeItem(at: tempURL)
                error = "Selected file does not contain a video track."
                return nil
            }

            let durationMicros = Int64(CMTimeGetSeconds(duration) * 1_000_000)

            // Copy to project storage directory.
            let documentsDir = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!
            let videosDir = documentsDir.appendingPathComponent("Videos")
            try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)

            let projectId = UUID().uuidString.lowercased()
            let filename = "\(projectId).\(tempURL.pathExtension)"
            let destURL = videosDir.appendingPathComponent(filename)
            try FileManager.default.moveItem(at: tempURL, to: destURL)

            let relativePath = "Videos/\(filename)"

            // Generate and save a thumbnail for the project card (best-effort).
            var thumbnailRelativePath: String?
            if let importService = mediaImportService,
               let thumbData = try? await importService.generateThumbnail(
                   path: destURL.path, maxSize: 320
               ) {
                let thumbnailsDir = documentsDir.appendingPathComponent("Thumbnails")
                try? FileManager.default.createDirectory(
                    at: thumbnailsDir, withIntermediateDirectories: true
                )
                let thumbURL = thumbnailsDir.appendingPathComponent("\(projectId).jpg")
                if (try? thumbData.write(to: thumbURL)) != nil {
                    thumbnailRelativePath = "Thumbnails/\(projectId).jpg"
                }
            }

            let now = Date()
            let project = Project(
                id: projectId,
                name: "Untitled Project",
                sourceVideoPath: relativePath,
                durationMicros: durationMicros,
                createdAt: now,
                modifiedAt: now,
                thumbnailPath: thumbnailRelativePath
            )

            try await projectRepository.save(project)
            await loadProjects()
            return project.id
        } catch {
            self.error = "Failed to import video: \(error.localizedDescription)"
            return nil
        }
    }

    /// Delete a project by ID.
    ///
    /// - Parameter id: The project's unique identifier.
    func deleteProject(id: String) async {
        do {
            try await projectRepository.delete(id: id)
            projects.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Delete multiple projects by their IDs.
    ///
    /// Deletes each project from the repository, ignoring individual failures,
    /// then refreshes the project list from the repository.
    ///
    /// - Parameter ids: Set of project unique identifiers to delete.
    func deleteProjects(ids: Set<String>) async {
        for id in ids {
            do {
                try await projectRepository.delete(id: id)
            } catch {
                // Continue deleting remaining projects even if one fails.
                self.error = error.localizedDescription
            }
        }
        await loadProjects()
    }

    /// Duplicate a project.
    ///
    /// - Parameter id: The source project's unique identifier.
    func duplicateProject(id: String) async {
        guard let source = projects.first(where: { $0.id == id }) else {
            error = "Project not found"
            return
        }

        let newId = UUID().uuidString
        let newName = "\(source.name)\(Self.duplicateProjectSuffix)"

        do {
            _ = try await projectRepository.duplicate(id: id, newId: newId, newName: newName)
            await loadProjects()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Delete a media asset by ID.
    ///
    /// - Parameter id: The asset's unique identifier.
    func deleteMediaAsset(id: String) async {
        do {
            try await mediaAssetRepository.delete(id: id)
            mediaAssets.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Toggle favorite status for a media asset.
    ///
    /// - Parameter id: The asset's unique identifier.
    func toggleMediaFavorite(id: String) async {
        guard let index = mediaAssets.firstIndex(where: { $0.id == id }) else { return }
        let asset = mediaAssets[index]
        let updated = asset.with(isFavorite: !asset.isFavorite)

        do {
            try await mediaAssetRepository.save(updated)
            mediaAssets[index] = updated
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - People Management

    /// Whether the add-person photo picker is showing.
    var showAddPersonPicker: Bool = false

    /// Whether the add-image-to-person photo picker is showing.
    var showAddImagePicker: Bool = false

    /// ID of person currently being targeted for adding an image.
    var addImageTargetPersonId: String?

    /// Whether the rename alert is showing.
    var showRenameAlert: Bool = false

    /// Person ID being renamed.
    var renameTargetPersonId: String?

    /// Text field value for renaming.
    var renameText: String = ""

    /// Whether the import source sheet is showing.
    var showImportSourceSheet: Bool = false

    /// Media asset selected for info detail display.
    var selectedMediaAssetForDetail: MediaAsset?

    /// Add a new person from a detected face image.
    ///
    /// Creates a person entry with a default name. The caller is expected
    /// to present a photo picker and call this with the resulting image path.
    /// Persists the new person to the repository if available.
    ///
    /// - Parameters:
    ///   - name: Display name for the new person (defaults to "New Person").
    ///   - imagePath: Relative path to the saved face image.
    ///   - embedding: Face embedding vector (empty if not yet extracted).
    ///   - qualityScore: Image quality score.
    func addPerson(
        name: String = ProjectLibraryViewModel.defaultPersonName,
        imagePath: String = "",
        embedding: [Double] = [],
        qualityScore: Double = 0.5
    ) async {
        let now = Date()
        let personImage = PersonImage(
            id: UUID().uuidString,
            imagePath: imagePath,
            embedding: embedding,
            qualityScore: qualityScore,
            addedAt: now
        )
        let person = Person(
            id: UUID().uuidString,
            name: name,
            createdAt: now,
            modifiedAt: now,
            images: imagePath.isEmpty ? [] : [personImage]
        )

        if let personRepository {
            do {
                try await personRepository.save(person)
            } catch {
                self.error = error.localizedDescription
                return
            }
        }

        people.append(person)
    }

    /// Rename a person.
    ///
    /// Persists the updated person to the repository if available.
    ///
    /// - Parameters:
    ///   - id: The person's unique identifier.
    ///   - newName: The new display name.
    func renamePerson(id: String, newName: String) async {
        guard let index = people.firstIndex(where: { $0.id == id }) else { return }
        let updated = people[index].with(name: newName, modifiedAt: Date())

        if let personRepository {
            do {
                try await personRepository.save(updated)
            } catch {
                self.error = error.localizedDescription
                return
            }
        }

        people[index] = updated
    }

    /// Initiate adding an image to a person (shows photo picker).
    ///
    /// - Parameter id: The person's unique identifier.
    func beginAddImageToPerson(id: String) {
        addImageTargetPersonId = id
        showAddImagePicker = true
    }

    /// Delete a person from the people library.
    ///
    /// Removes from repository if available, then updates local state.
    ///
    /// - Parameter id: The person's unique identifier.
    func deletePerson(id: String) async {
        if let personRepository {
            do {
                try await personRepository.delete(id: id)
            } catch {
                self.error = error.localizedDescription
                return
            }
        }

        people.removeAll { $0.id == id }
    }

    /// Present the rename alert for a person.
    ///
    /// - Parameter person: The person to rename.
    func beginRenamePerson(_ person: Person) {
        renameTargetPersonId = person.id
        renameText = person.name
        showRenameAlert = true
    }

    /// Commit the rename from the alert.
    func commitRename() async {
        guard let id = renameTargetPersonId, !renameText.isEmpty else { return }
        await renamePerson(id: id, newName: renameText)
        renameTargetPersonId = nil
        renameText = ""
    }

    // MARK: - Import

    /// Show the import source selection sheet.
    func showImportMedia() {
        showImportSourceSheet = true
    }

    // MARK: - Error

    /// Clear the current error.
    func clearError() {
        error = nil
    }
}
