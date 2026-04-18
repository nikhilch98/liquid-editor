// SampleProjectSeeder.swift
// LiquidEditor
//
// First-launch seeder that ensures the user has at least one project in the
// Library to explore the app. Idempotent: guarded by a `UserDefaults` flag.
//
// Introduced for S2-26 (premium UI redesign: sample project seeded on
// first-launch).

import Foundation

// MARK: - SampleProjectSeeder

/// Seeds a single demo project into the Library on first launch.
///
/// Usage:
/// ```swift
/// SampleProjectSeeder.shared.seedIfNeeded(using: repositoryContainer.projectRepository)
/// ```
///
/// The seeder writes through `ProjectRepositoryProtocol` when one is supplied;
/// when no repository is available (unit-test / preview contexts) it records a
/// TODO and no-ops the persistence step so the flag still flips forward.
///
/// Isolation: `@MainActor` because the canonical call site is app launch in
/// the SwiftUI entry point; persistence work is offloaded via `Task` if
/// needed by the caller.
@MainActor
final class SampleProjectSeeder {

    /// Shared singleton instance.
    static let shared = SampleProjectSeeder()

    /// UserDefaults key guarding seed execution.
    private static let seededFlagKey = "sampleProjectSeeded"

    /// Injectable defaults (defaults to `.standard`) for testability.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Whether the seeder has already run (for diagnostics / tests).
    var hasSeeded: Bool {
        defaults.bool(forKey: Self.seededFlagKey)
    }

    /// Seed the sample project once if it has not already been seeded.
    ///
    /// - Parameter repository: Optional `ProjectRepositoryProtocol` used to
    ///   persist the seeded project. When `nil` the seed is skipped with a
    ///   TODO log; the flag is intentionally left `false` so a later launch
    ///   with a live repository can retry.
    func seedIfNeeded(using repository: ProjectRepositoryProtocol? = nil) {
        guard !hasSeeded else { return }

        guard let repository else {
            // TODO: Wire `ProjectRepositoryProtocol` from ServiceContainer at
            // call site so the sample project can actually be persisted.
            // Leaving the flag unset so a future launch can retry.
            return
        }

        let project = Self.makeSampleProject()
        Task { [weak self] in
            do {
                try await repository.save(project)
                await MainActor.run {
                    self?.markSeeded()
                }
            } catch {
                // Persistence failure should not flip the flag -- retry on
                // next launch. Callers can surface telemetry if desired.
            }
        }
    }

    /// Flip the "sample seeded" flag forward.
    private func markSeeded() {
        defaults.set(true, forKey: Self.seededFlagKey)
    }

    /// Reset the seeded flag (test / QA helper).
    func resetForTesting() {
        defaults.removeObject(forKey: Self.seededFlagKey)
    }

    // MARK: - Sample Project Factory

    /// Build the sample `Project` with 2-3 placeholder clips.
    ///
    /// The placeholder clips are encoded as lightweight `AnyCodableValue`
    /// dictionaries matching the existing `Project.clips` envelope; the
    /// editor layer interprets `kind == "placeholder"` items as "awaiting
    /// media" stubs so the user sees something in the timeline on first open.
    static func makeSampleProject() -> Project {
        let now = Date()
        let placeholders: [[String: AnyCodableValue]] = [
            [
                "id": .string("sample-clip-1"),
                "kind": .string("placeholder"),
                "label": .string("Welcome"),
                "durationMicros": .int(3_000_000),
            ],
            [
                "id": .string("sample-clip-2"),
                "kind": .string("placeholder"),
                "label": .string("Add your media"),
                "durationMicros": .int(5_000_000),
            ],
            [
                "id": .string("sample-clip-3"),
                "kind": .string("placeholder"),
                "label": .string("Share"),
                "durationMicros": .int(2_000_000),
            ],
        ]

        return Project(
            id: "sample-project-001",
            name: "Welcome to Liquid Editor",
            sourceVideoPath: "",
            frameRate: .fixed30,
            durationMicros: 10_000_000,
            clips: placeholders,
            createdAt: now,
            modifiedAt: now,
            version: 2
        )
    }
}
