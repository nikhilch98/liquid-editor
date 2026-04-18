// CrashReporter.swift
// LiquidEditor
//
// Stub crash reporting facade. Provides a unified interface for
// recording non-fatal errors, identifying users, and leaving breadcrumbs
// during a session. The current implementation logs to `os.log` only —
// real third-party SDK wiring (Sentry / Bugsnag / Firebase Crashlytics)
// is intentionally deferred to a later milestone.
//
// The public API is shaped so that swapping the implementation for a
// real SDK later requires only re-implementing the method bodies; no
// call sites need to change.

import Foundation
import os

// MARK: - CrashReporter

/// App-wide crash reporting facade.
///
/// Thread Safety:
/// - `@MainActor` because start()/setUser() are typically called from
///   lifecycle events that originate on the main actor. The underlying
///   `Logger` is itself thread-safe, so individual log calls are cheap.
/// - Internal breadcrumb storage is guarded by the main actor.
///
/// Usage:
/// ```swift
/// // At app launch:
/// CrashReporter.shared.start()
///
/// // On user login:
/// CrashReporter.shared.setUser(id: userID)
///
/// // Anywhere an interesting event occurs:
/// CrashReporter.shared.leaveBreadcrumb("Opened editor for project \(id)")
///
/// // Non-fatal error:
/// CrashReporter.shared.recordError(err, userInfo: ["op": "export"])
/// ```
@MainActor
final class CrashReporter {

    // MARK: - Singleton

    /// Shared instance — call `start()` once at launch before use.
    static let shared = CrashReporter()

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "CrashReporter"
    )

    // MARK: - Constants

    /// Maximum breadcrumb buffer size. Older entries are discarded to
    /// bound memory usage in long-running sessions.
    private static let maxBreadcrumbs = 100

    // MARK: - State

    private var started = false
    private var currentUserID: String?
    private var breadcrumbs: [Breadcrumb] = []

    private init() {}

    // MARK: - Lifecycle

    /// Initialise the crash reporter. Idempotent — safe to call multiple
    /// times from tests or previews.
    ///
    /// Future work: this is where the real SDK would be configured
    /// (e.g., `SentrySDK.start { ... }`). For now, logs a start marker.
    func start() {
        guard !started else { return }
        started = true
        Self.logger.info("CrashReporter started (stub implementation)")
    }

    // MARK: - User Identification

    /// Attach an anonymised user identifier to subsequent reports.
    ///
    /// - Parameter id: An opaque, stable identifier. Pass `nil` to clear.
    func setUser(id: String?) {
        currentUserID = id
        if let id {
            Self.logger.info("CrashReporter setUser id=\(id, privacy: .private(mask: .hash))")
        } else {
            Self.logger.info("CrashReporter cleared user")
        }
    }

    // MARK: - Breadcrumbs

    /// Record a short free-form breadcrumb describing a user action or
    /// app event. Breadcrumbs are attached to subsequent error reports.
    ///
    /// - Parameter message: Human-readable event description.
    func leaveBreadcrumb(_ message: String) {
        let crumb = Breadcrumb(timestamp: Date(), message: message)
        breadcrumbs.append(crumb)
        if breadcrumbs.count > Self.maxBreadcrumbs {
            breadcrumbs.removeFirst(breadcrumbs.count - Self.maxBreadcrumbs)
        }
        Self.logger.debug("Breadcrumb: \(message, privacy: .public)")
    }

    // MARK: - Error Recording

    /// Record a non-fatal error with optional context.
    ///
    /// - Parameters:
    ///   - error: The error to record.
    ///   - userInfo: Contextual keys (e.g., `["op": "export", "code": 42]`).
    func recordError(_ error: Error, userInfo: [String: Any] = [:]) {
        let description = String(describing: error)
        let contextDescription = userInfo.isEmpty
            ? "none"
            : userInfo.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        Self.logger.error(
            "Non-fatal error: \(description, privacy: .public) context=[\(contextDescription, privacy: .public)] user=\(self.currentUserID ?? "anonymous", privacy: .private(mask: .hash))"
        )
    }

    // MARK: - Diagnostics

    /// Read-only snapshot of currently stored breadcrumbs.
    /// Exposed mainly for tests and debug UI.
    var currentBreadcrumbs: [Breadcrumb] {
        breadcrumbs
    }
}

// MARK: - Breadcrumb

/// A single timestamped log entry attached to future crash reports.
struct Breadcrumb: Sendable, Equatable {
    let timestamp: Date
    let message: String
}
