// DeepLinkRouter.swift
// LiquidEditor
//
// OS17-3: Custom URL scheme + Universal Links router per spec §10.10.2.
//
// Scheme: liquideditor://
//
// Supported paths:
// - liquideditor://open?project=<id>     -> open an existing project
// - liquideditor://import?url=<url>      -> URL import (§9.7) pre-filled
// - liquideditor://new?template=<id>     -> new project from template
//
// Universal Links resolve the same query string via HTTPS when a web
// domain is registered.
//
// Per spec: incoming URLs surface an amber confirmation pill BEFORE
// acting. Destructive operations are never auto-executed. The caller
// (typically the app root) inspects `pendingRequest` and decides
// whether to present the confirmation UI.

import Foundation
import Observation

// MARK: - DeepLinkRequest

/// Parsed representation of an incoming deep-link URL.
enum DeepLinkRequest: Sendable, Equatable {
    case openProject(id: String)
    case importURL(source: URL)
    case newFromTemplate(id: String)
    case unknown(original: URL)
}

// MARK: - DeepLinkRouter

/// Observable router. Attach at app root; the scene's `.onOpenURL`
/// handler calls `handle(_:)`, which populates `pendingRequest` for
/// the UI to inspect.
@Observable
@MainActor
final class DeepLinkRouter {

    /// The URL scheme this router matches. Keep in sync with Info.plist
    /// CFBundleURLSchemes.
    static let scheme = "liquideditor"

    /// Last-received request awaiting user confirmation. `nil` when idle.
    var pendingRequest: DeepLinkRequest?

    // MARK: - Public API

    /// Parse + stash a URL. Safe to call on any URL — the router
    /// silently drops unrelated ones.
    func handle(_ url: URL) {
        guard let parsed = parse(url) else { return }
        pendingRequest = parsed
    }

    /// Clear the pending request after the UI has confirmed or dismissed.
    func clear() {
        pendingRequest = nil
    }

    // MARK: - Parsing

    /// Parse a URL into a `DeepLinkRequest` if it matches our scheme,
    /// otherwise returns nil.
    func parse(_ url: URL) -> DeepLinkRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme else {
            return nil
        }

        // URLComponents treats `liquideditor://open?...` as having host = "open"
        // and no path; both open?... and /open?... parse the same way here.
        let action = (components.host ?? components.path.trimmingCharacters(in: .init(charactersIn: "/")))
        let params = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )

        switch action {
        case "open":
            guard let id = params["project"] else { return .unknown(original: url) }
            return .openProject(id: id)

        case "import":
            guard let raw = params["url"], let src = URL(string: raw) else {
                return .unknown(original: url)
            }
            return .importURL(source: src)

        case "new":
            guard let templateID = params["template"] else { return .unknown(original: url) }
            return .newFromTemplate(id: templateID)

        default:
            return .unknown(original: url)
        }
    }
}
