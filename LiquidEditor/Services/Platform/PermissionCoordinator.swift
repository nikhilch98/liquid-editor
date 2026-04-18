// PermissionCoordinator.swift
// LiquidEditor
//
// Coordinates system permission requests for the photo library, camera,
// and microphone. For each permission, the coordinator:
//   1. Checks the current authorisation status.
//   2. If `.notDetermined`, presents a `PermissionPrimerSheet` before
//      triggering the OS-level request.
//   3. If previously `.denied`, presents a settings deep-link sheet so
//      the user can enable the permission in Settings.
//
// Designed to be injected into views/view-models that need permission
// gating.

import AVFoundation
import Observation
import Photos
import SwiftUI
import UIKit
import os

// MARK: - PermissionKind → system status mapping helpers

@MainActor
private enum PermissionStatusHelper {

    static func photoLibraryStatus() -> PermissionStatus {
        let raw = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch raw {
        case .notDetermined: return .notDetermined
        case .authorized, .limited: return .authorized
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    static func cameraStatus() -> PermissionStatus {
        let raw = AVCaptureDevice.authorizationStatus(for: .video)
        switch raw {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    static func microphoneStatus() -> PermissionStatus {
        let raw = AVAudioApplication.shared.recordPermission
        switch raw {
        case .undetermined: return .notDetermined
        case .granted: return .authorized
        case .denied: return .denied
        @unknown default: return .denied
        }
    }
}

// MARK: - PermissionStatus

/// Normalised permission state shared across all kinds.
enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

// MARK: - PermissionSheetRequest

/// State describing a sheet the coordinator wants to show.
///
/// Views observe this via `coordinator.activeSheet` and render the
/// matching sheet binding.
struct PermissionSheetRequest: Identifiable, Sendable {
    enum Mode: Sendable {
        case primer
        case settingsDeepLink
    }

    let id = UUID()
    let kind: PermissionKind
    let mode: Mode
}

// MARK: - PermissionCoordinator

/// Orchestrates permission flows for photo library, camera, and microphone.
///
/// Thread Safety:
/// - `@MainActor` — all system permission APIs must be called on the
///   main actor and UI sheet state is main-bound anyway.
/// - `@Observable` so views can bind `activeSheet` directly.
///
/// Presentation contract:
/// - Views attach `.permissionCoordinatorSheets(coordinator)` (defined
///   below) which renders the primer/settings sheets when `activeSheet`
///   is set. This lets view-models call the async API without owning any
///   UI.
@MainActor
@Observable
final class PermissionCoordinator {

    // MARK: - Logger

    @ObservationIgnored
    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "PermissionCoordinator"
    )

    // MARK: - Observable UI State

    /// Sheet the coordinator wants presented. `nil` when no sheet is needed.
    var activeSheet: PermissionSheetRequest?

    // MARK: - Continuation State (non-observed)

    @ObservationIgnored
    private var primerContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Request access to the user's photo library.
    ///
    /// - Returns: `true` if the user is (now) authorised; `false` if denied.
    func requestPhotoLibraryAccess() async -> Bool {
        let status = PermissionStatusHelper.photoLibraryStatus()
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            guard await showPrimer(for: .photoLibrary) else { return false }
            let granted = await systemRequestPhotoLibrary()
            Self.logger.info("Photo library request result: \(granted, privacy: .public)")
            return granted
        case .denied:
            showSettingsDeepLink(for: .photoLibrary)
            return false
        }
    }

    /// Request access to the camera.
    func requestCameraAccess() async -> Bool {
        let status = PermissionStatusHelper.cameraStatus()
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            guard await showPrimer(for: .camera) else { return false }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            Self.logger.info("Camera request result: \(granted, privacy: .public)")
            return granted
        case .denied:
            showSettingsDeepLink(for: .camera)
            return false
        }
    }

    /// Request access to the microphone.
    func requestMicrophoneAccess() async -> Bool {
        let status = PermissionStatusHelper.microphoneStatus()
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            guard await showPrimer(for: .microphone) else { return false }
            let granted = await AVAudioApplication.requestRecordPermission()
            Self.logger.info("Microphone request result: \(granted, privacy: .public)")
            return granted
        case .denied:
            showSettingsDeepLink(for: .microphone)
            return false
        }
    }

    // MARK: - Primer Resolution (called by view)

    /// Called by the view hosting the primer sheet when the user taps
    /// Continue or Cancel. Resolves the pending async `request*` call.
    func resolvePrimer(requestID: UUID, didContinue: Bool) {
        guard let continuation = primerContinuations.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(returning: didContinue)
    }

    // MARK: - Private

    /// Present the primer sheet and suspend until the user chooses
    /// Continue (`true`) or Cancel (`false`).
    private func showPrimer(for kind: PermissionKind) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = PermissionSheetRequest(kind: kind, mode: .primer)
            primerContinuations[request.id] = continuation
            activeSheet = request
        }
    }

    private func showSettingsDeepLink(for kind: PermissionKind) {
        activeSheet = PermissionSheetRequest(kind: kind, mode: .settingsDeepLink)
    }

    /// Wrap the delegate-based PHPhotoLibrary request in async/await.
    private func systemRequestPhotoLibrary() async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                let granted = status == .authorized || status == .limited
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - View Integration

extension View {

    /// Attach the coordinator's sheets to any view that wants to gate on
    /// permissions. Typically applied high in the view hierarchy.
    func permissionCoordinatorSheets(_ coordinator: PermissionCoordinator) -> some View {
        modifier(PermissionCoordinatorSheetModifier(coordinator: coordinator))
    }
}

private struct PermissionCoordinatorSheetModifier: ViewModifier {
    @Bindable var coordinator: PermissionCoordinator

    func body(content: Content) -> some View {
        content.sheet(item: $coordinator.activeSheet) { request in
            switch request.mode {
            case .primer:
                PermissionPrimerSheet(
                    systemImage: request.kind.sfSymbol,
                    title: request.kind.title,
                    rationale: request.kind.subtitle,
                    onGrant: { coordinator.resolvePrimer(requestID: request.id, didContinue: true) },
                    onNotNow: { coordinator.resolvePrimer(requestID: request.id, didContinue: false) }
                )
            case .settingsDeepLink:
                SettingsDeepLinkSheet(kind: request.kind)
            }
        }
    }
}

// MARK: - SettingsDeepLinkSheet

/// Sheet shown when the user has previously denied a permission.
/// Offers a button that opens the app's Settings page.
private struct SettingsDeepLinkSheet: View {

    let kind: PermissionKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: LiquidSpacing.xl) {
                Image(systemName: kind.sfSymbol)
                    .font(.system(size: 56, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("\(kind.title) in Settings")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Access was previously declined. Open Settings to grant it so Liquid Editor can continue.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LiquidSpacing.md)

                Spacer(minLength: 0)

                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not Now") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(LiquidSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiquidColors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func openSettings() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        dismiss()
    }
}
