// EditorViewModel.swift
// LiquidEditor
//
// ViewModel for the main editor screen.
//
// Manages editor state including playback, selection, tool panels,
// and undo/redo. Uses @Observable for automatic SwiftUI integration
// and @MainActor for UI-thread safety.

import AVFoundation
import Foundation
import os
import UIKit

// MARK: - EditorTab

/// Bottom toolbar tab selection.
enum EditorTab: String, CaseIterable, Sendable {
    case edit
    case fx
    case overlay
    case audio
    case smart

    var displayName: String {
        switch self {
        case .edit: "Edit"
        case .fx: "FX"
        case .overlay: "Overlay"
        case .audio: "Audio"
        case .smart: "Smart"
        }
    }

    var iconName: String {
        switch self {
        case .edit: "slider.horizontal.3"
        case .fx: "sparkles"
        case .overlay: "square.on.square"
        case .audio: "speaker.wave.2"
        case .smart: "brain"
        }
    }

    var activeIconName: String {
        switch self {
        case .edit: "slider.horizontal.3"
        case .fx: "sparkles"
        case .overlay: "square.on.square.fill"
        case .audio: "speaker.wave.2.fill"
        case .smart: "brain.head.profile"
        }
    }
}

// MARK: - ActiveToolPanel

/// Which tool panel sheet is currently presented.
enum ActiveToolPanel: String, CaseIterable, Sendable {
    case none
    case colorGrading
    case videoEffects
    case crop
    case transition
    case audioEffects
    case textEditor
    case stickerPicker
    case volume
    case speed
    case trackManagement
    case keyframeEditor
    case autoReframe
    case personSelection

    /// Whether a panel sheet should be shown.
    var isPresented: Bool { self != .none }

    var displayName: String {
        switch self {
        case .none: ""
        case .colorGrading: "Color Grading"
        case .videoEffects: "Video Effects"
        case .crop: "Crop & Rotate"
        case .transition: "Transitions"
        case .audioEffects: "Audio Effects"
        case .textEditor: "Text Editor"
        case .stickerPicker: "Stickers"
        case .volume: "Volume"
        case .speed: "Speed"
        case .trackManagement: "Tracks"
        case .keyframeEditor: "Keyframes"
        case .autoReframe: "Auto Reframe"
        case .personSelection: "Person Selection"
        }
    }
}

// MARK: - EditorViewModel

/// Main view model for the editor screen.
///
/// Manages all editor state: playback, selection, tool panels, undo/redo.
/// Coordinates with `PlaybackEngine` (actor-isolated) for playback operations.
@Observable
@MainActor
final class EditorViewModel {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "EditorViewModel"
    )

    // MARK: - Project State

    /// The project being edited.
    var project: Project

    /// The persistent timeline data structure.
    var timeline: PersistentTimeline

    /// Multi-track compositing state.
    var multiTrackState: MultiTrackState?

    // MARK: - Playback State

    /// Current playhead position in microseconds.
    var currentTime: TimeMicros = 0

    /// Whether the timeline is currently playing.
    var isPlaying: Bool = false

    // MARK: - Selection State

    /// ID of the currently selected clip, if any.
    var selectedClipId: String?

    // MARK: - UI State

    /// Active bottom toolbar tab.
    var activeTab: EditorTab = .edit

    /// Currently presented tool panel (sheet).
    var activePanel: ActiveToolPanel = .none

    /// Whether the export sheet is visible.
    var showExportSheet: Bool = false

    /// Whether the settings sheet is visible.
    var showSettings: Bool = false

    /// Whether the editor is still loading the video.
    var isLoading: Bool = false

    /// Error message if video loading failed (nil when no error).
    var errorMessage: String?

    /// Whether a keyframe exists at the current playhead time.
    var hasKeyframeAtCurrentTime: Bool = false

    /// Whether the project settings dropdown is shown.
    var showProjectSettingsDropdown: Bool = false

    /// Whether comparison mode is active on the video preview.
    var isComparisonMode: Bool = false

    /// Whether trim mode is active (shows trim handles on selected clip).
    var isTrimMode: Bool = false

    /// Whether object tracking is actively running.
    var isTrackingActive: Bool = false

    /// Bounding boxes for the current playhead frame, populated when tracking is active.
    var currentTrackingBoxes: [TrackedBoundingBox] = []

    /// The active tracking session ID, set when a tracking session is started.
    var activeTrackingSessionId: String?

    /// Whether a voiceover recording is currently in progress.
    var isRecording: Bool = false

    /// Whether the track debug overlay is active.
    var isTrackDebugActive: Bool = false

    /// Whether fullscreen preview is presented.
    var showFullscreenPreview: Bool = false

    /// Timeline zoom scale factor.
    var zoomScale: Double = 1.0

    // MARK: - Undo/Redo

    /// Stack of previous timeline states for undo.
    private var undoStack: [PersistentTimeline] = []

    /// Stack of undone timeline states for redo.
    private var redoStack: [PersistentTimeline] = []

    // MARK: - Configuration Constants

    /// Maximum undo history depth.
    private let maxUndoDepth: Int

    /// Minimum clip duration for split operations (100ms).
    private let minClipDurationMicros: TimeMicros

    // MARK: - Dependencies

    /// Playback engine reference (actor-isolated, interacted with via async).
    private var playbackEngine: PlaybackEngine?

    /// Composition manager reference for AVPlayer access.
    /// The player is created by the composition manager during hot-swap.
    private let compositionManager: CompositionManager?

    /// Voiceover recorder — created fresh per recording session.
    private var voiceoverRecorder: VoiceoverRecorder?

    /// Most recently completed recording info.
    private(set) var lastRecordingInfo: RecordingInfo?

    // MARK: - Initialization

    /// Creates an editor view model for the given project.
    ///
    /// - Parameters:
    ///   - project: The project to edit.
    ///   - timeline: Initial timeline state (defaults to empty).
    ///   - playbackEngine: Optional playback engine for media playback.
    ///   - compositionManager: Optional composition manager for AVPlayer access.
    ///   - maxUndoDepth: Maximum undo stack depth (defaults to 50).
    ///   - minClipDurationMicros: Minimum clip duration for splits (defaults to 100ms).
    init(
        project: Project,
        timeline: PersistentTimeline = .empty,
        playbackEngine: PlaybackEngine? = nil,
        compositionManager: CompositionManager? = nil,
        maxUndoDepth: Int = 50,
        minClipDurationMicros: TimeMicros = 100_000
    ) {
        self.project = project
        self.timeline = timeline
        self.playbackEngine = playbackEngine
        self.compositionManager = compositionManager
        self.maxUndoDepth = maxUndoDepth
        self.minClipDurationMicros = minClipDurationMicros
    }

    // MARK: - Computed Properties

    /// Whether undo is available.
    var canUndo: Bool { !undoStack.isEmpty }

    /// Whether redo is available.
    var canRedo: Bool { !redoStack.isEmpty }

    /// Total duration of the timeline in microseconds.
    var totalDuration: TimeMicros { timeline.totalDurationMicros }

    /// Formatted current playhead time (MM:SS.ms).
    var formattedCurrentTime: String { currentTime.simpleTimeString }

    /// Formatted total duration (MM:SS.ms).
    var formattedTotalDuration: String { totalDuration.simpleTimeString }

    /// The AVPlayer for video preview display.
    ///
    /// Returns the player from the composition manager, or nil if no
    /// composition has been loaded yet.
    var player: AVPlayer? { compositionManager?.player }

    /// Whether media has been loaded and the player is ready for display.
    var hasMedia: Bool { compositionManager?.player != nil }

    // MARK: - Playback Control

    /// Start playback.
    func play() {
        isPlaying = true
        Task {
            guard let engine = playbackEngine else {
                Self.logger.warning("Play failed: playback engine is nil")
                isPlaying = false
                return
            }
            await engine.play()
            Self.logger.debug("Play started")
        }
    }

    /// Pause playback.
    func pause() {
        isPlaying = false
        Task {
            guard let engine = playbackEngine else {
                Self.logger.warning("Pause failed: playback engine is nil")
                return
            }
            await engine.pause()
            Self.logger.debug("Pause completed")
        }
    }

    /// Toggle between play and pause.
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Seek to a specific time.
    ///
    /// - Parameter time: Target time in microseconds.
    func seek(to time: TimeMicros) {
        let clamped = max(0, min(time, totalDuration))
        if clamped != time {
            Self.logger.debug("Seek clamped: requested=\(time), clamped=\(clamped)")
        }
        currentTime = clamped
        Task {
            do {
                guard let engine = playbackEngine else {
                    Self.logger.warning("Seek failed: playback engine is nil")
                    return
                }
                await engine.seek(clamped)
            }
        }
    }

    // MARK: - Editing Operations

    /// Split the selected clip at the current playhead position.
    func splitAtPlayhead() {
        guard let clipId = selectedClipId else {
            Self.logger.info("Split: no clip selected")
            return
        }

        guard let item = timeline.getById(clipId) else {
            Self.logger.warning("Split: clip not found: \(clipId)")
            return
        }

        guard let clipStart = timeline.startTimeOf(clipId) else {
            Self.logger.warning("Split: could not find start time for clip: \(clipId)")
            return
        }

        let offsetInClip = currentTime - clipStart

        guard offsetInClip > 0, offsetInClip < item.durationMicroseconds else {
            Self.logger.info("Split: playhead not within clip bounds")
            return
        }

        pushUndo()

        // Delegate split to the concrete clip type's splitAt() method.
        // Each clip type (VideoClip, AudioClip, GapClip, ImageClip, TextClip,
        // StickerClip, ColorClip) has its own splitAt() that returns (left, right).
        // We use a helper to erase the concrete split tuple to existential types.
        let splitResult: (left: any TimelineItemProtocol, right: any TimelineItemProtocol)?

        if let videoClip = item as? VideoClip {
            if let result = videoClip.splitAt(offsetInClip) {
                splitResult = (left: result.left, right: result.right)
            } else { splitResult = nil }
        } else if let audioClip = item as? AudioClip {
            if let result = audioClip.splitAt(offsetInClip) {
                splitResult = (left: result.left, right: result.right)
            } else { splitResult = nil }
        } else if let gapClip = item as? GapClip {
            if let result = gapClip.splitAt(offsetInClip) {
                splitResult = (left: result.left, right: result.right)
            } else { splitResult = nil }
        } else if let textClip = item as? TextClip {
            if let result = textClip.splitAt(offsetInClip) {
                splitResult = (left: result.left, right: result.right)
            } else { splitResult = nil }
        } else if let stickerClip = item as? StickerClip {
            if let result = stickerClip.splitAt(offsetInClip) {
                splitResult = (left: result.left, right: result.right)
            } else { splitResult = nil }
        } else if let colorClip = item as? ColorClip {
            if let result = colorClip.splitAt(offsetInClip) {
                splitResult = (left: result.left, right: result.right)
            } else { splitResult = nil }
        } else if let imageClip = item as? ImageClip {
            // ImageClip has no source in/out to split -- split into two
            // image clips with proportional durations.
            let minDuration: TimeMicros = 100_000
            if offsetInClip >= minDuration,
               offsetInClip <= imageClip.durationMicroseconds - minDuration {
                let leftClip = imageClip.with(
                    id: UUID().uuidString,
                    durationMicroseconds: offsetInClip
                )
                let rightClip = imageClip.with(
                    id: UUID().uuidString,
                    durationMicroseconds: imageClip.durationMicroseconds - offsetInClip
                )
                splitResult = (left: leftClip, right: rightClip)
            } else {
                splitResult = nil
            }
        } else {
            Self.logger.warning("Split: unsupported clip type for \(clipId)")
            return
        }

        guard let (leftClip, rightClip) = splitResult else {
            Self.logger.info("Split: offset invalid for clip split operation")
            return
        }

        // Remove original and insert left + right at the same position
        var updated = timeline.remove(clipId)
        updated = updated.insertAt(clipStart, leftClip)
        updated = updated.insertAt(clipStart + leftClip.durationMicroseconds, rightClip)
        timeline = updated

        // Select the right (second) clip after split
        selectedClipId = rightClip.id

        Self.logger.info("Split clip \(clipId) at offset \(offsetInClip)")
    }

    /// Delete the currently selected clip.
    func deleteSelected() {
        guard let clipId = selectedClipId else {
            Self.logger.info("Delete: no clip selected")
            return
        }

        pushUndo()
        timeline = timeline.remove(clipId)
        selectedClipId = nil
        Self.logger.info("Deleted clip: \(clipId)")
    }

    /// Duplicate the currently selected clip.
    func duplicateSelected() {
        guard let clipId = selectedClipId else {
            Self.logger.info("Duplicate: no clip selected")
            return
        }

        guard timeline.containsId(clipId) else {
            Self.logger.warning("Duplicate: clip not found: \(clipId)")
            return
        }

        guard let item = timeline.getById(clipId) else {
            Self.logger.warning("Duplicate: clip data not found: \(clipId)")
            return
        }

        guard let clipEnd = timeline.startTimeOf(clipId).map({ $0 + item.durationMicroseconds }) else {
            Self.logger.warning("Duplicate: could not find start time for clip: \(clipId)")
            return
        }

        pushUndo()

        // Clone the clip with a new ID using each type's duplicate() method.
        // Each concrete type's duplicate() returns its own type; we assign
        // directly to an existential variable to erase the type.
        let duplicated: any TimelineItemProtocol

        if let videoClip = item as? VideoClip {
            let dup = videoClip.duplicate()
            duplicated = dup
        } else if let audioClip = item as? AudioClip {
            let dup = audioClip.duplicate()
            duplicated = dup
        } else if let gapClip = item as? GapClip {
            let dup = gapClip.duplicate()
            duplicated = dup
        } else if let textClip = item as? TextClip {
            let dup = textClip.duplicate()
            duplicated = dup
        } else if let stickerClip = item as? StickerClip {
            let dup = stickerClip.duplicate()
            duplicated = dup
        } else if let colorClip = item as? ColorClip {
            let dup = colorClip.duplicate()
            duplicated = dup
        } else if let imageClip = item as? ImageClip {
            let dup = imageClip.duplicate()
            duplicated = dup
        } else {
            Self.logger.warning("Duplicate: unsupported clip type for \(clipId)")
            return
        }

        // Insert the duplicate immediately after the original clip
        timeline = timeline.insertAt(clipEnd, duplicated)
        selectedClipId = duplicated.id

        Self.logger.info("Duplicated clip: \(clipId) -> \(duplicated.id)")
    }

    // MARK: - Trim Mode

    /// Toggle trim mode for the selected clip.
    func toggleTrimMode() {
        isTrimMode.toggle()
        Self.logger.debug("Trim mode: \(self.isTrimMode)")
    }

    // MARK: - Undo/Redo

    /// Undo the last timeline operation.
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(timeline)
        timeline = previous
        Self.logger.debug("Undo (stack: \(self.undoStack.count))")
    }

    /// Redo the last undone timeline operation.
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(timeline)
        timeline = next
        Self.logger.debug("Redo (stack: \(self.redoStack.count))")
    }

    /// Push the current timeline state onto the undo stack.
    private func pushUndo() {
        undoStack.append(timeline)
        redoStack.removeAll()

        // Trim undo stack if it exceeds the limit
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst(undoStack.count - maxUndoDepth)
        }
    }

    // MARK: - Panel Management

    /// Set the active tool panel.
    ///
    /// - Parameter panel: The panel to present.
    func setActivePanel(_ panel: ActiveToolPanel) {
        activePanel = panel
        Self.logger.debug("Panel: \(panel.rawValue)")
    }

    /// Dismiss the current tool panel.
    func dismissPanel() {
        activePanel = .none
    }

    // MARK: - Keyframe Management

    /// Add a keyframe at the current playhead time.
    func addKeyframeManually() {
        hasKeyframeAtCurrentTime = true
        Self.logger.debug("Added keyframe at \(self.currentTime)")
    }

    /// Delete the keyframe at the current playhead time.
    func deleteKeyframeAtCurrentTime() {
        hasKeyframeAtCurrentTime = false
        Self.logger.debug("Removed keyframe at \(self.currentTime)")
    }

    /// Toggle keyframe at current time (add if absent, remove if present).
    func toggleKeyframeAtCurrentTime() {
        if hasKeyframeAtCurrentTime {
            deleteKeyframeAtCurrentTime()
        } else {
            addKeyframeManually()
        }
    }

    // MARK: - Voiceover Recording

    /// Toggle voiceover recording on/off.
    ///
    /// Checks microphone permission before starting. If permission is denied,
    /// sets `errorMessage` so the UI can present guidance.
    func toggleVoiceoverRecording() {
        if isRecording {
            stopVoiceoverRecording()
        } else {
            startVoiceoverRecording()
        }
    }

    private func startVoiceoverRecording() {
        // Check/request microphone permission.
        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .granted:
            beginRecording()
        case .denied:
            errorMessage = "Microphone access is denied. Please enable it in Settings."
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.beginRecording()
                    } else {
                        self.errorMessage = "Microphone access is required to record voiceover."
                    }
                }
            }
        @unknown default:
            errorMessage = "Unknown microphone permission state."
        }
    }

    private func beginRecording() {
        let recorder = VoiceoverRecorder()
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceover_\(UUID().uuidString).m4a")
            .path

        do {
            // Configure audio session for record + playback.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            try recorder.prepare(outputPath: outputPath)
            try recorder.start()

            voiceoverRecorder = recorder
            isRecording = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Self.logger.info("Voiceover recording started: \(outputPath)")
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            Self.logger.error("Voiceover start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopVoiceoverRecording() {
        guard let recorder = voiceoverRecorder else { return }
        let info = recorder.stop()
        lastRecordingInfo = info
        voiceoverRecorder = nil
        isRecording = false

        // Deactivate recording session.
        try? AVAudioSession.sharedInstance().setActive(false)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Self.logger.info(
            "Voiceover recording stopped: \(info.filePath), duration: \(info.durationMicros)µs"
        )
    }

    // MARK: - Track Debug

    /// Toggle the track debug overlay.
    func toggleTrackDebug() {
        isTrackDebugActive.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        Self.logger.debug("Track debug: \(self.isTrackDebugActive)")
    }

    // MARK: - Tracking Boxes

    /// Update `currentTrackingBoxes` to reflect the nearest tracked frame at the given timestamp.
    ///
    /// - Parameter timestampMs: Current playhead position in milliseconds.
    func updateTrackingBoxes(for timestampMs: Int) async {
        guard let sessionId = activeTrackingSessionId, isTrackingActive else {
            if !currentTrackingBoxes.isEmpty {
                currentTrackingBoxes = []
            }
            return
        }
        guard let allResults = await ServiceContainer.shared.trackingService.getAllResults(sessionId: sessionId),
              !allResults.isEmpty else { return }
        let closest = allResults.min(by: {
            abs($0.timestampMs - timestampMs) < abs($1.timestampMs - timestampMs)
        })
        currentTrackingBoxes = closest?.people.compactMap { person -> TrackedBoundingBox? in
            guard let bbox = person.boundingBox else { return nil }
            // NormalizedBoundingBox uses center-origin; convert to top-left for CGRect.
            let rect = CGRect(
                x: bbox.x - bbox.width / 2,
                y: bbox.y - bbox.height / 2,
                width: bbox.width,
                height: bbox.height
            )
            return TrackedBoundingBox(
                id: "\(sessionId)-\(person.personIndex)",
                normalizedRect: rect,
                confidence: Float(person.confidence),
                label: person.displayName,
                personIndex: person.personIndex,
                skeletonJoints: nil
            )
        } ?? []
    }

    // MARK: - Video Loading

    /// Reload the video source.
    func loadVideo() {
        isLoading = true
        errorMessage = nil
        Self.logger.debug("Loading video...")
        // Simulate async load — actual implementation delegates to PlaybackEngine
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoading = false
        }
    }
}
