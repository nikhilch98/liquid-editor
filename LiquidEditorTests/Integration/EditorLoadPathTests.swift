// EditorLoadPathTests.swift
// LiquidEditorTests
//
// Regression test for the editor open flow. Constructs an EditorViewModel
// for a project whose sourceVideoPath resolves to a real file on disk,
// invokes loadProject, and verifies the timeline and player get populated.
//
// Historically (pre-2026-04-18), EditorViewModel accepted a Project but
// never consumed project.sourceVideoPath or project.clips — the editor
// opened with a blank preview and empty timeline regardless of the
// project's contents. This suite prevents that regression.

import AVFoundation
import Foundation
import Testing
@testable import LiquidEditor

@Suite("Editor Load Path")
@MainActor
struct EditorLoadPathTests {

    // MARK: - Helpers

    /// Copy the generated sample video into Documents/Videos/ under a
    /// deterministic name and return the project that references it.
    private func makeProjectWithFixtureVideo() async throws -> Project {
        let fixtureURL = try await FixtureFactory.sampleVideoURL()
        let fixtureAsset = AVURLAsset(url: fixtureURL)
        let duration = try await fixtureAsset.load(.duration)
        let durationMicros = Int64(CMTimeGetSeconds(duration) * 1_000_000)

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videosDir = documentsDir.appendingPathComponent("Videos")
        try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)

        let projectId = "editorloadtest-\(UUID().uuidString.lowercased())"
        let filename = "\(projectId).mp4"
        let destURL = videosDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: fixtureURL, to: destURL)

        return Project(
            id: projectId,
            name: "Editor Load Test",
            sourceVideoPath: "Videos/\(filename)",
            durationMicros: durationMicros
        )
    }

    // MARK: - Tests

    @Test("loadProject populates timeline and wires AVPlayer for a legacy source-video project")
    func loadProjectPopulatesTimelineAndPlayer() async throws {
        let project = try await makeProjectWithFixtureVideo()
        let viewModel = EditorViewModel(project: project)

        #expect(viewModel.timeline.toList().isEmpty)
        #expect(viewModel.player == nil)

        await viewModel.loadProject()

        let items = viewModel.timeline.toList()
        #expect(items.count == 1)
        #expect(items.first is VideoClip)
        #expect(viewModel.totalDuration > 0)
        #expect(viewModel.player != nil,
                "AVPlayer must be non-nil after loadProject; if nil the preview will stay blank")
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("loadProject with empty project leaves empty state and no error")
    func loadProjectEmptyProjectStaysEmpty() async throws {
        let project = Project(
            id: "empty-\(UUID().uuidString.lowercased())",
            name: "Empty",
            sourceVideoPath: ""
        )
        let viewModel = EditorViewModel(project: project)

        await viewModel.loadProject()

        #expect(viewModel.timeline.toList().isEmpty,
                "Empty project should leave the VM's timeline empty")
        #expect(viewModel.errorMessage == nil,
                "Empty project should be a valid empty-state, not an error")
        #expect(viewModel.isLoading == false)
        // viewModel.player may be non-nil here because it is sourced from
        // ServiceContainer.shared.compositionManager, which is a long-lived
        // singleton that other tests in the run may have populated. The VM's
        // own state (timeline + error) is the honest check for an empty
        // load.
    }
}
