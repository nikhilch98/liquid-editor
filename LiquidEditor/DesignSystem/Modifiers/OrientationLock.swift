// OrientationLock.swift
// LiquidEditor
//
// F0-6: Per-screen orientation-lock infrastructure per spec §2.7.
//
// Spec policy:
// - iPhone: portrait primary; landscape supported on the Editor screen
//   only. Library + Export are portrait-locked.
// - iPad: landscape primary; portrait supported (media-browser collapses
//   to a drawer triggered by left-edge swipe).
//
// Mechanism:
// - SupportedOrientationsHost is a single source of truth (an
//   `@Observable @MainActor` class) that the AppDelegate (or
//   `UIApplication.shared.connectedScenes` query) reads to decide what
//   `supportedInterfaceOrientations` to return.
// - SwiftUI views call `.supportedOrientations(_:)` to push their
//   policy onto the host while presented; on disappear they restore
//   the previous policy via a stack.
//
// This file ships the SwiftUI surface only; AppDelegate wiring lives
// in LiquidEditorApp.swift later.

import SwiftUI
import Observation
import UIKit

// MARK: - SupportedOrientationsHost

/// Single source of truth for the currently-allowed orientations.
///
/// AppDelegate should read `current` from this host and return it from
/// `application(_:supportedInterfaceOrientationsFor:)`.
@Observable
@MainActor
final class SupportedOrientationsHost {

    /// The shared instance read by the AppDelegate.
    static let shared = SupportedOrientationsHost()

    /// Stack of pushed policies. Top of the stack is the active one.
    private(set) var stack: [UIInterfaceOrientationMask] = [.all]

    /// The currently-active policy.
    var current: UIInterfaceOrientationMask {
        stack.last ?? .all
    }

    /// Push a new policy onto the stack and ask the system to refresh
    /// the current scene's orientations.
    func push(_ mask: UIInterfaceOrientationMask) {
        stack.append(mask)
        requestUpdate()
    }

    /// Pop a policy off the stack (no-op if only the default remains).
    func pop() {
        guard stack.count > 1 else { return }
        stack.removeLast()
        requestUpdate()
    }

    /// Force-rotate the current scene to honor the new policy.
    private func requestUpdate() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: current)) { _ in }
    }
}

// MARK: - SupportedOrientationsModifier

/// Internal modifier that pushes/pops the host's policy based on the
/// view's appearance lifecycle.
private struct SupportedOrientationsModifier: ViewModifier {
    let mask: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear { SupportedOrientationsHost.shared.push(mask) }
            .onDisappear { SupportedOrientationsHost.shared.pop() }
    }
}

// MARK: - View extension

extension View {
    /// Restrict the orientations this view is allowed to be presented in.
    /// On disappear the previous policy is restored automatically.
    ///
    /// Spec mapping:
    /// - Library + Export should call `.supportedOrientations(.portrait)`
    /// - Editor on iPhone: `.supportedOrientations([.portrait, .landscape])`
    /// - Editor on iPad: `.supportedOrientations(.all)`
    func supportedOrientations(_ mask: UIInterfaceOrientationMask) -> some View {
        modifier(SupportedOrientationsModifier(mask: mask))
    }
}
