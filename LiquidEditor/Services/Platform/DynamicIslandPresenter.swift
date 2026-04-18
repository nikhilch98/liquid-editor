// DynamicIslandPresenter.swift
// LiquidEditor
//
// OS17-1: ActivityKit presenter for export progress Live Activity per
// spec §10.10.1.
//
// Start a Live Activity when export begins, push progress / ETA updates
// during the job, and end the activity on completion (success or failure).
//
// Attributes type (ExportLiveActivityAttributes) is declared in this file
// because ActivityKit requires the same type to be visible both to the
// host app (which calls `Activity.request` / `update`) and the widget
// extension (which renders the UI via `ActivityConfiguration(for:)`).
// Shipping it as part of the main app target + including the same
// source file in the widget extension target is the standard pattern.

import ActivityKit
import Foundation
import Observation

// MARK: - ExportLiveActivityAttributes

/// Attributes describing an active export Live Activity.
///
/// `ContentState` carries the values that change during the job
/// (progress, ETA). The top-level stored properties (projectName, jobId)
/// are fixed for the life of the activity.
public struct ExportLiveActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        /// 0.0 ... 1.0
        public let progress: Double
        /// Estimated remaining seconds; `nil` while we can't estimate yet.
        public let etaSeconds: Int?

        public init(progress: Double, etaSeconds: Int?) {
            self.progress = progress
            self.etaSeconds = etaSeconds
        }
    }

    public let projectName: String
    public let jobId: UUID

    public init(projectName: String, jobId: UUID) {
        self.projectName = projectName
        self.jobId = jobId
    }
}

// MARK: - DynamicIslandPresenter

/// @Observable presenter that owns the lifecycle of the export Live
/// Activity. Exactly one activity is tracked at a time; starting a new
/// one while another is running cleanly ends the previous.
@Observable
@MainActor
public final class DynamicIslandPresenter {

    // MARK: - State

    /// The currently-running activity, if any.
    private var activity: Activity<ExportLiveActivityAttributes>?

    /// Last progress value pushed. Exposed for the UI / tests.
    public private(set) var lastProgress: Double = 0

    /// Last ETA pushed (seconds remaining).
    public private(set) var lastEtaSeconds: Int?

    /// Project name of the current activity, if any.
    public private(set) var currentProjectName: String?

    /// Job ID of the current activity, if any.
    public private(set) var currentJobId: UUID?

    public init() {}

    // MARK: - Public API

    /// Start a Live Activity for an export job. If one is already
    /// running it is ended first.
    public func start(projectName: String, jobId: UUID) async {
        if activity != nil {
            await end(success: false)
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ExportLiveActivityAttributes(
            projectName: projectName,
            jobId: jobId
        )
        let initialState = ExportLiveActivityAttributes.ContentState(
            progress: 0,
            etaSeconds: nil
        )

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            let requested = try Activity<ExportLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            activity = requested
            currentProjectName = projectName
            currentJobId = jobId
            lastProgress = 0
            lastEtaSeconds = nil
        } catch {
            // ActivityKit can fail when the user has disabled Live Activities
            // or the system rate-limits requests. We silently no-op; callers
            // can observe `currentJobId == nil` to detect the failure.
            activity = nil
        }
    }

    /// Push a progress / ETA update to the running activity.
    public func update(progress: Double, etaSeconds: Int?) async {
        let clamped = min(max(progress, 0), 1)
        lastProgress = clamped
        lastEtaSeconds = etaSeconds

        guard let activityId = activity?.id else { return }
        let state = ExportLiveActivityAttributes.ContentState(
            progress: clamped,
            etaSeconds: etaSeconds
        )
        let content = ActivityContent(state: state, staleDate: nil)
        // Resolve the activity by ID from the global registry (Sendable
        // type); avoids capturing a main-actor-isolated stored property
        // into an async send.
        await Self.pushUpdate(activityId: activityId, content: content)
    }

    /// End the running activity. `success` is reflected in the final
    /// progress value (1.0 on success, last-known on failure).
    public func end(success: Bool) async {
        guard let activityId = activity?.id else {
            currentProjectName = nil
            currentJobId = nil
            return
        }

        let finalProgress = success ? 1.0 : lastProgress
        let finalState = ExportLiveActivityAttributes.ContentState(
            progress: finalProgress,
            etaSeconds: success ? 0 : lastEtaSeconds
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        await Self.pushEnd(activityId: activityId, content: content)

        self.activity = nil
        currentProjectName = nil
        currentJobId = nil
        lastProgress = finalProgress
    }

    // MARK: - Nonisolated helpers (Swift 6 Sendable sinks)

    nonisolated private static func pushUpdate(
        activityId: String,
        content: ActivityContent<ExportLiveActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<ExportLiveActivityAttributes>.activities
            .first(where: { $0.id == activityId }) else { return }
        await activity.update(content)
    }

    nonisolated private static func pushEnd(
        activityId: String,
        content: ActivityContent<ExportLiveActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<ExportLiveActivityAttributes>.activities
            .first(where: { $0.id == activityId }) else { return }
        await activity.end(content, dismissalPolicy: .default)
    }
}
