// ExternalDisplayController.swift
// LiquidEditor
//
// IP16-6 (per 2026-04-18 premium UI redesign spec §16 — iPad platform):
// External display support. Observes UIScreen connect/disconnect
// notifications and exposes a list of external screens plus an
// `isExternalDisplayActive` flag for the EditorView.
//
// API `mirrorPreview(_ playerLayer:)` creates a dedicated UIWindow on
// the external screen that hosts the preview AVPlayerLayer.
// Full mirroring (stretching the layer to fill, letter-boxing,
// handling rotation) is deferred to a follow-up ticket; for now we
// create the window and attach the layer at the screen's bounds.

import AVFoundation
import Foundation
import SwiftUI
import UIKit
import os

// MARK: - ExternalDisplayController

/// Tracks external displays (AirPlay + wired) and hosts a mirror
/// window for the preview player.
@MainActor
@Observable
final class ExternalDisplayController {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "ExternalDisplayController"
    )

    // MARK: - Public state

    /// All currently-connected external screens.
    private(set) var externalScreens: [UIScreen] = []

    /// Convenience — true when at least one external screen is present.
    var isExternalDisplayActive: Bool {
        !externalScreens.isEmpty
    }

    // MARK: - Private state

    /// Active mirror window, if any. Retained so the system does not
    /// deallocate the backing UIWindow.
    private var mirrorWindow: UIWindow?

    /// Observers kept alive for the lifetime of the controller.
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    // MARK: - Init / Deinit

    init() {
        refreshScreens()
        registerNotifications()
    }

    deinit {
        // Observers are retained for the lifetime of the controller.
        // NotificationCenter automatically cleans up observer tokens
        // when their owner is deallocated (post-iOS 9), but we still
        // want to remove them explicitly if we ever migrate away from
        // block-based observers. Cross-actor removal is not possible
        // from a nonisolated deinit, so we rely on the default GC path.
        //
        // If this ever becomes a leak, spin up a dedicated
        // `@MainActor func stop()` and call it from the owner.
    }

    // MARK: - Public API

    /// Mirror the given player layer onto the first external screen.
    ///
    /// STUB — creates a UIWindow on the external screen with a plain
    /// black background and attaches the player layer at the screen's
    /// bounds. A follow-up ticket will add letter-boxing, rotation
    /// handling, and re-attachment on screen reconnect.
    ///
    /// - Parameter playerLayer: The AVPlayerLayer whose contents to mirror.
    /// - Returns: `true` if a mirror window was created; `false` if no
    ///   external screen is available.
    @discardableResult
    func mirrorPreview(_ playerLayer: AVPlayerLayer) -> Bool {
        guard let screen = externalScreens.first else {
            Self.logger.info("mirrorPreview called but no external screen is connected.")
            return false
        }

        // Tear down any existing mirror first.
        teardownMirror()

        // Create a window scene-less UIWindow on the external screen.
        // `UIScreen`-based window construction is deprecated on iOS 13+
        // in favor of scene-based windows; for a mirrored screen we
        // obtain the matching window scene if available.
        let window: UIWindow
        if let scene = windowScene(for: screen) {
            window = UIWindow(windowScene: scene)
        } else {
            // Fallback — the external screen has not yet produced a
            // dedicated scene. Return false; the caller can retry when
            // the scene appears.
            Self.logger.info("No UIWindowScene for external screen yet — deferring mirror.")
            return false
        }

        window.frame = screen.bounds
        window.backgroundColor = .black
        window.isHidden = false

        // Host a bare UIViewController with the player layer embedded.
        let hostVC = UIViewController()
        hostVC.view.backgroundColor = .black
        playerLayer.frame = hostVC.view.bounds
        playerLayer.videoGravity = .resizeAspect
        hostVC.view.layer.addSublayer(playerLayer)
        window.rootViewController = hostVC
        window.makeKeyAndVisible()

        mirrorWindow = window
        Self.logger.info("External mirror window created on screen: \(screen.description, privacy: .public)")
        return true
    }

    /// Tear down any active mirror window.
    func teardownMirror() {
        mirrorWindow?.isHidden = true
        mirrorWindow = nil
    }

    // MARK: - Private

    private func registerNotifications() {
        // iOS 16+ steers external-display detection through scene
        // notifications instead of `UIScreen.didConnectNotification`
        // (now deprecated in iOS 26). When a new scene connects or
        // disconnects we re-derive `externalScreens` from the scene
        // graph via `refreshScreens()`.
        connectObserver = NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreens()
            }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshScreens()
                // Drop the mirror window if its backing screen went away.
                if self.externalScreens.isEmpty {
                    self.teardownMirror()
                }
            }
        }
    }

    private func refreshScreens() {
        // iOS 16+: discover external screens through the scene graph
        // (UIScreen.screens / UIScreen.main are deprecated in iOS 26).
        // Each connected UIWindowScene reports its host screen, and
        // the key/primary scene is the one matching the active
        // foreground window scene.
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyScreen = windowScenes
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
        var seen: [ObjectIdentifier: Bool] = [:]
        var distinctScreens: [UIScreen] = []
        for scene in windowScenes {
            let screen = scene.screen
            let key = ObjectIdentifier(screen)
            if seen[key] == nil {
                seen[key] = true
                distinctScreens.append(screen)
            }
        }
        externalScreens = distinctScreens.filter { $0 !== keyScreen }
    }

    /// Find the UIWindowScene that hosts the given external screen.
    private func windowScene(for screen: UIScreen) -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.screen === screen }
    }
}
