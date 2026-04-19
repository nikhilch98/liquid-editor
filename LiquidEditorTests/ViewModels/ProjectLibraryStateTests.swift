// ProjectLibraryStateTests.swift
// LiquidEditor
//
// TT13-2 (Premium UI §11.6): Structural state tests for the Project
// Library + Export screens. Real snapshot testing requires an external
// library (SnapshotTesting); we verify VM/state-machine state at each
// scenario instead.
//
// Scope:
// - `ExportJobStateMachine` transitions: idle → exporting → success, plus
//   invalid-transition rejection, cancel, reset, and the convenience flags.
// - `ProjectLibraryViewModel` additions that aren't already covered by
//   `ProjectLibraryViewModelTests`:
//     - `loadCurrentTab()` dispatches to the tab-specific loader.
//     - `storageBreakdown` math from `ProjectMetadata.fileSizeBytes`.
//     - `clearError()` clears prior error state.
//
// NOTE (deferred): the original TT13-2 task called for "Drafts / Cloud"
// tab filters and a soft-delete trash flow. Neither the Drafts tab, Cloud
// tab, nor soft-delete/trash is implemented on `ProjectLibraryViewModel`
// today — only `LibraryTab` (.projects / .media / .people). Those
// assertions are intentionally omitted per the plan's "do not invent"
// rule.
//
// Reuses `MockProjectRepository`, `MockMediaAssetRepository`,
// `MockError`, and `ProjectMetadata.testInstance` from
// `ProjectLibraryViewModelTests.swift` — same test target.

import Foundation
import Testing
@testable import LiquidEditor

// MARK: - ExportJobStateMachine Transitions

@Suite("ExportJobStateMachine transitions")
@MainActor
struct ExportJobStateMachineStateTests {

    // MARK: - Initial State

    @Test("Initial state is idle")
    func initialStateIdle() {
        let machine = ExportJobStateMachine()
        #expect(machine.state == .idle)
    }

    @Test("Init with custom initial state is respected")
    func initialCustomState() {
        let machine = ExportJobStateMachine(initial: .exporting(progress: 0.25, eta: 10))
        #expect(machine.state.isRunning)
        #expect(machine.state.progressValue == 0.25)
    }

    // MARK: - Happy-Path Transition Chain

    @Test("idle → exporting → success is accepted")
    func idleToExportingToSuccess() throws {
        let machine = ExportJobStateMachine()

        // idle → exporting.
        #expect(machine.transition(to: .exporting(progress: 0.0, eta: 30)))
        #expect(machine.state.isRunning)
        #expect(!machine.state.isTerminal)

        // exporting → exporting (progress tick).
        #expect(machine.transition(to: .exporting(progress: 0.5, eta: 15)))
        #expect(machine.state.progressValue == 0.5)
        #expect(machine.state.etaSeconds == 15)

        // exporting → success.
        let outputURL = URL(fileURLWithPath: "/tmp/export.mov")
        #expect(machine.transition(to: .success(url: outputURL)))
        if case let .success(url) = machine.state {
            #expect(url == outputURL)
        } else {
            Issue.record("Expected .success after transition")
        }
        #expect(machine.state.isTerminal)
        #expect(!machine.state.isRunning)
    }

    // MARK: - Invalid Transitions

    @Test("success → exporting is rejected")
    func successToExportingRejected() {
        let machine = ExportJobStateMachine(initial: .success(url: URL(fileURLWithPath: "/tmp/out.mov")))
        let accepted = machine.transition(to: .exporting(progress: 0.1, eta: 5))
        #expect(accepted == false)

        // State must remain unchanged on rejection.
        if case .success = machine.state {
            // ok
        } else {
            Issue.record("Expected state to remain .success after rejected transition")
        }
    }

    @Test("idle → success directly is rejected")
    func idleToSuccessRejected() {
        let machine = ExportJobStateMachine()
        let accepted = machine.transition(to: .success(url: URL(fileURLWithPath: "/tmp/out.mov")))
        #expect(accepted == false)
        #expect(machine.state == .idle)
    }

    @Test("exporting → idle directly is rejected")
    func exportingToIdleRejected() {
        let machine = ExportJobStateMachine(initial: .exporting(progress: 0.5, eta: 10))
        let accepted = machine.transition(to: .idle)
        #expect(accepted == false)
        #expect(machine.state.isRunning)
    }

    // MARK: - Error / Cancel / Reset

    @Test("exporting → error is accepted and terminal")
    func exportingToError() {
        let machine = ExportJobStateMachine(initial: .exporting(progress: 0.4, eta: 8))
        #expect(machine.transition(to: .error(message: "boom")))
        #expect(machine.state.isTerminal)
        #expect(!machine.state.isRunning)
    }

    @Test("cancel() from exporting flips state to cancelled")
    func cancelFromExporting() {
        let machine = ExportJobStateMachine(initial: .exporting(progress: 0.3, eta: 12))
        machine.cancel()
        #expect(machine.state == .cancelled)
        #expect(machine.state.isTerminal)
    }

    @Test("cancel() from terminal state is a no-op")
    func cancelTerminalNoOp() {
        let url = URL(fileURLWithPath: "/tmp/out.mov")
        let machine = ExportJobStateMachine(initial: .success(url: url))
        machine.cancel()
        // Still success — cancel is ignored.
        if case let .success(storedURL) = machine.state {
            #expect(storedURL == url)
        } else {
            Issue.record("Expected cancel() on terminal to leave state unchanged")
        }
    }

    @Test("reset() returns the machine to idle from any state")
    func resetFromTerminal() {
        let machine = ExportJobStateMachine(initial: .error(message: "fail"))
        machine.reset()
        #expect(machine.state == .idle)
    }

    // MARK: - Convenience Flags

    @Test("isRunning / isTerminal reflect the state correctly")
    func flagsAreConsistent() {
        #expect(ExportJobState.idle.isRunning == false)
        #expect(ExportJobState.idle.isTerminal == false)

        let running = ExportJobState.exporting(progress: 0.1, eta: 5)
        #expect(running.isRunning == true)
        #expect(running.isTerminal == false)

        let done = ExportJobState.success(url: URL(fileURLWithPath: "/tmp/x.mov"))
        #expect(done.isRunning == false)
        #expect(done.isTerminal == true)

        let failed = ExportJobState.error(message: "x")
        #expect(failed.isTerminal)

        #expect(ExportJobState.cancelled.isTerminal)
    }

    @Test("displayLabel is non-empty for every case")
    func displayLabels() {
        #expect(ExportJobState.idle.displayLabel == "Idle")
        #expect(ExportJobState.exporting(progress: 0, eta: 0).displayLabel == "Exporting")
        #expect(ExportJobState.success(url: URL(fileURLWithPath: "/tmp/x.mov")).displayLabel == "Done")
        #expect(ExportJobState.error(message: "bad").displayLabel == "Failed")
        #expect(ExportJobState.cancelled.displayLabel == "Cancelled")
    }

    @Test("isValid table enforces the documented reachability rules")
    func isValidTable() {
        // A small sample of the documented table (see ExportJobState.swift).
        #expect(ExportJobStateMachine.isValid(from: .idle, to: .exporting(progress: 0, eta: 0)))
        #expect(ExportJobStateMachine.isValid(from: .exporting(progress: 0.1, eta: 1),
                                              to: .exporting(progress: 0.2, eta: 1)))
        #expect(ExportJobStateMachine.isValid(from: .success(url: URL(fileURLWithPath: "/x")), to: .idle))
        #expect(ExportJobStateMachine.isValid(from: .error(message: "e"), to: .idle))

        // Should NOT be valid.
        #expect(ExportJobStateMachine.isValid(
            from: .success(url: URL(fileURLWithPath: "/x")),
            to: .exporting(progress: 0, eta: 0)
        ) == false)
        #expect(ExportJobStateMachine.isValid(
            from: .cancelled,
            to: .exporting(progress: 0, eta: 0)
        ) == false)
    }
}

// MARK: - ProjectLibraryViewModel: Additional State Coverage

@Suite("Project library extra state coverage")
@MainActor
struct ProjectLibraryExtraStateTests {

    // MARK: - Helpers

    /// Distinct helper name to avoid colliding with `makeVM()` in
    /// `ProjectLibraryViewModelTests`.
    private func makeLibraryVM() -> (
        ProjectLibraryViewModel,
        MockProjectRepository,
        MockMediaAssetRepository
    ) {
        let projectRepo = MockProjectRepository()
        let mediaRepo = MockMediaAssetRepository()
        let vm = ProjectLibraryViewModel(
            projectRepository: projectRepo,
            mediaAssetRepository: mediaRepo
        )
        return (vm, projectRepo, mediaRepo)
    }

    // MARK: - loadCurrentTab Dispatch

    @Test("loadCurrentTab dispatches to loadProjects when on .projects tab")
    func loadCurrentTabProjects() async {
        let (vm, repo, _) = makeLibraryVM()
        repo.metadata = [
            .testInstance(id: "p1", name: "Alpha"),
            .testInstance(id: "p2", name: "Beta"),
        ]
        vm.selectedTab = .projects

        await vm.loadCurrentTab()

        #expect(vm.projects.count == 2)
        #expect(vm.mediaAssets.isEmpty)
    }

    @Test("loadCurrentTab dispatches to loadMediaAssets when on .media tab")
    func loadCurrentTabMedia() async {
        let (vm, _, mediaRepo) = makeLibraryVM()
        mediaRepo.assets = [
            .testInstance(id: "m1", filename: "a.mp4", type: .video),
            .testInstance(id: "m2", filename: "b.jpg", type: .image),
        ]
        vm.selectedTab = .media

        await vm.loadCurrentTab()

        #expect(vm.mediaAssets.count == 2)
        #expect(vm.projects.isEmpty)
    }

    // MARK: - storageBreakdown Math

    @Test("storageBreakdown is zero when there are no projects")
    func storageBreakdownEmpty() {
        let (vm, _, _) = makeLibraryVM()
        let breakdown = vm.storageBreakdown
        #expect(breakdown.totalBytes == 0)
        #expect(breakdown.videoFraction == 0)
        #expect(breakdown.photoFraction == 0)
        #expect(breakdown.audioFraction == 0)
        #expect(breakdown.otherFraction == 0)
    }

    @Test("storageBreakdown sums project sizes and splits per VM heuristic")
    func storageBreakdownMath() async {
        let (vm, repo, _) = makeLibraryVM()
        let p1 = ProjectMetadata(
            id: "p1", name: "One",
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 1),
            fileSizeBytes: 1_000
        )
        let p2 = ProjectMetadata(
            id: "p2", name: "Two",
            createdAt: Date(timeIntervalSince1970: 2),
            modifiedAt: Date(timeIntervalSince1970: 2),
            fileSizeBytes: 3_000
        )
        repo.metadata = [p1, p2]
        await vm.loadProjects()

        let breakdown = vm.storageBreakdown
        // Total is the sum of both.
        #expect(breakdown.totalBytes == 4_000)
        // Video gets 85% rounded down; photo 5%; audio 5%; other = remainder.
        #expect(breakdown.videoBytes == 3_400)
        #expect(breakdown.photoBytes == 200)
        #expect(breakdown.audioBytes == 200)
        #expect(breakdown.otherBytes == 4_000 - 3_400 - 200 - 200)

        // Fractions are consistent with the byte split.
        let totalDouble = Double(breakdown.totalBytes)
        #expect(abs(breakdown.videoFraction - Double(breakdown.videoBytes) / totalDouble) < 1e-9)
        #expect(abs(breakdown.photoFraction - Double(breakdown.photoBytes) / totalDouble) < 1e-9)
    }

    // MARK: - clearError Behaviour

    @Test("clearError() nils the error set by a failed load")
    func clearErrorAfterLoadFailure() async {
        let (vm, repo, _) = makeLibraryVM()
        repo.shouldThrow = true
        await vm.loadProjects()
        #expect(vm.error != nil)

        vm.clearError()
        #expect(vm.error == nil)
    }
}
