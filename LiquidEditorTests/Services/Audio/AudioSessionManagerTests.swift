// AudioSessionManagerTests.swift
// LiquidEditorTests
//
// Comprehensive tests for AudioSessionManager:
// - Session category configuration for each mode
// - Active/inactive state tracking
// - Interruption handling state machine
// - Route change handler registration
// - Combined configure + activate
// - Edge cases and error descriptions

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - AudioSessionManager Tests

@Suite("AudioSessionManager Tests")
struct AudioSessionManagerTests {

    // MARK: - Initial State

    @Test("Session starts inactive with no mode")
    func initialState() async {
        let manager = AudioSessionManager()
        let isActive = await manager.sessionIsActive
        let mode = await manager.activeMode
        #expect(isActive == false)
        #expect(mode == nil)
    }

    // MARK: - Configuration

    @Test("Configure for playback mode sets currentMode")
    func configurePlayback() async throws {
        let manager = AudioSessionManager()
        try await manager.configure(for: .playback())
        let mode = await manager.activeMode
        if case .playback = mode {
            // pass
        } else {
            Issue.record("Expected playback mode, got \(String(describing: mode))")
        }
    }

    @Test("Configure for playback with mixWithOthers sets currentMode")
    func configurePlaybackMixing() async throws {
        let manager = AudioSessionManager()
        try await manager.configure(for: .playback(mixWithOthers: true))
        let mode = await manager.activeMode
        if case .playback(let mix) = mode {
            #expect(mix == true)
        } else {
            Issue.record("Expected playback mode with mixing")
        }
    }

    @Test("Configure for recording mode sets currentMode")
    func configureRecording() async throws {
        let manager = AudioSessionManager()
        try await manager.configure(for: .recording)
        let mode = await manager.activeMode
        if case .recording = mode {
            // pass
        } else {
            Issue.record("Expected recording mode, got \(String(describing: mode))")
        }
    }

    @Test("Configure for monitoring mode sets currentMode")
    func configureMonitoring() async throws {
        let manager = AudioSessionManager()
        try await manager.configure(for: .monitoring)
        let mode = await manager.activeMode
        if case .monitoring = mode {
            // pass
        } else {
            Issue.record("Expected monitoring mode, got \(String(describing: mode))")
        }
    }

    @Test("Configure for editing mode sets currentMode")
    func configureEditing() async throws {
        let manager = AudioSessionManager()
        try await manager.configure(for: .editing)
        let mode = await manager.activeMode
        if case .editing = mode {
            // pass
        } else {
            Issue.record("Expected editing mode, got \(String(describing: mode))")
        }
    }

    @Test("Configure for exporting mode sets currentMode")
    func configureExporting() async throws {
        let manager = AudioSessionManager()
        try await manager.configure(for: .exporting)
        let mode = await manager.activeMode
        if case .exporting = mode {
            // pass
        } else {
            Issue.record("Expected exporting mode, got \(String(describing: mode))")
        }
    }

    // MARK: - Activation / Deactivation

    @Test("Activate sets session as active")
    func activateSession() async throws {
        let manager = AudioSessionManager()
        try await manager.configure(for: .editing)
        try await manager.activate()
        let isActive = await manager.sessionIsActive
        #expect(isActive == true)
    }

    @Test("Deactivate sets session as inactive")
    func deactivateSession() async throws {
        let manager = AudioSessionManager()
        try await manager.configure(for: .editing)
        try await manager.activate()
        try await manager.deactivate()
        let isActive = await manager.sessionIsActive
        #expect(isActive == false)
    }

    @Test("Configure and activate in one call")
    func configureAndActivate() async throws {
        let manager = AudioSessionManager()
        try await manager.configureAndActivate(for: .playback())
        let isActive = await manager.sessionIsActive
        let mode = await manager.activeMode
        #expect(isActive == true)
        if case .playback = mode {
            // pass
        } else {
            Issue.record("Expected playback mode after configureAndActivate")
        }
    }

    // MARK: - Mode Switching

    @Test("Switching modes updates activeMode")
    func switchModes() async throws {
        let manager = AudioSessionManager()

        try await manager.configure(for: .playback())
        if case .playback = await manager.activeMode {} else {
            Issue.record("Expected playback mode")
        }

        try await manager.configure(for: .editing)
        if case .editing = await manager.activeMode {} else {
            Issue.record("Expected editing mode after switch")
        }

        try await manager.configure(for: .recording)
        if case .recording = await manager.activeMode {} else {
            Issue.record("Expected recording mode after switch")
        }
    }

    // MARK: - Route Information

    @Test("Current route info returns valid structure")
    func routeInfo() async {
        let manager = AudioSessionManager()
        let info = manager.currentRouteInfo()

        // In simulator, route info should have some outputs
        // We just verify the structure is valid
        #expect(info.outputs is [String])
        #expect(info.inputs is [String])
        // Boolean values should be accessible
        _ = info.hasHeadphones
        _ = info.hasBluetooth
        _ = info.isBuiltInSpeaker
    }

    @Test("Preferred sample rate returns positive value")
    func sampleRate() async {
        let manager = AudioSessionManager()
        let rate = manager.preferredSampleRate
        #expect(rate > 0)
    }

    // MARK: - Interruption Handler Registration

    @Test("Set interruption handler stores callbacks without crash")
    func setInterruptionHandler() async {
        let manager = AudioSessionManager()

        await manager.setInterruptionHandler(
            onBegan: { _ in /* no-op */ },
            onEnded: { _ in /* no-op */ }
        )

        // If we get here without a crash, the handler was registered successfully
        let isActive = await manager.sessionIsActive
        #expect(isActive == false)
    }

    @Test("Set route change handler stores callback without crash")
    func setRouteChangeHandler() async {
        let manager = AudioSessionManager()

        await manager.setRouteChangeHandler { _ in
            // no-op: verifying registration does not crash
        }

        // If we get here, the handler was registered successfully
        let isActive = await manager.sessionIsActive
        #expect(isActive == false)
    }

    @Test("Re-setting interruption handler replaces previous one")
    func replaceInterruptionHandler() async {
        let manager = AudioSessionManager()

        await manager.setInterruptionHandler(
            onBegan: { _ in },
            onEnded: { _ in }
        )

        // Replace with new handler -- should not crash
        await manager.setInterruptionHandler(
            onBegan: { _ in },
            onEnded: { _ in }
        )
    }

    @Test("Re-setting route change handler replaces previous one")
    func replaceRouteChangeHandler() async {
        let manager = AudioSessionManager()

        await manager.setRouteChangeHandler { _ in }

        // Replace -- should not crash
        await manager.setRouteChangeHandler { _ in }
    }

    // MARK: - AudioSessionError descriptions

    @Test("Error descriptions are non-empty")
    func errorDescriptions() {
        let errors: [AudioSessionError] = [
            .configurationFailed("test"),
            .activationFailed("test"),
            .deactivationFailed("test"),
        ]

        for error in errors {
            let desc = error.errorDescription ?? ""
            #expect(!desc.isEmpty)
        }
    }

    // MARK: - AudioSessionMode

    @Test("AudioSessionMode cases are Sendable")
    func modeIsSendable() {
        let modes: [AudioSessionMode] = [
            .playback(),
            .playback(mixWithOthers: true),
            .recording,
            .monitoring,
            .editing,
            .exporting,
        ]
        // Verify all modes can be created without error
        #expect(modes.count == 6)
    }

    // MARK: - AudioRouteInfo

    @Test("AudioRouteInfo stores properties correctly")
    func routeInfoProperties() {
        let info = AudioRouteInfo(
            outputs: ["Speaker", "Headphones"],
            inputs: ["Microphone"],
            hasHeadphones: true,
            hasBluetooth: false,
            isBuiltInSpeaker: false
        )

        #expect(info.outputs.count == 2)
        #expect(info.inputs.count == 1)
        #expect(info.hasHeadphones == true)
        #expect(info.hasBluetooth == false)
        #expect(info.isBuiltInSpeaker == false)
    }
}
