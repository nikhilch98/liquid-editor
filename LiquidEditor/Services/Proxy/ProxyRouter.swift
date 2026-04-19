// ProxyRouter.swift
// LiquidEditor
//
// PP12-10: Central playback-vs-export URL router.
//
// During editing we want the *playback* engine to load low-resolution
// proxies when available so scrub/seek stays fluid. During export we want
// the encoder to always read the *original* full-quality master.
//
// `ProxyRouter` is the single decision point for that choice. Every code
// path that resolves a URL for AVFoundation should go through
// `playbackURL(for:originalURL:)` or `exportURL(for:originalURL:)` rather
// than reaching into `ProxyService` directly, so the contract stays
// consistent across the codebase.
//
// Dependency: `ProxyService.shared` actor.
// - Reads are `async` (actor-isolated).
// - The router itself is `@MainActor` because it is consumed from the
//   PlaybackEngine / export pipeline's UI-side glue code.

import Foundation

// MARK: - ProxyRouter

/// Resolves the correct media URL for playback vs export for a given clip.
///
/// ### Contract
/// - `playbackURL(for:originalURL:)` → proxy when registered, else original.
/// - `exportURL(for:originalURL:)` → ALWAYS the original, never a proxy.
///
/// ### Thread Safety
/// `@MainActor` isolated. Uses `ProxyService.shared` under the hood.
///
/// ### Usage
/// ```swift
/// let url = await ProxyRouter().playbackURL(
///     for: clip.id,
///     originalURL: clip.sourceURL
/// )
/// let exportURL = ProxyRouter().exportURL(
///     for: clip.id,
///     originalURL: clip.sourceURL
/// )
/// ```
@MainActor
struct ProxyRouter {

    // MARK: - Dependencies

    /// Proxy registry accessor. Defaulted to the shared singleton so the
    /// router is a zero-state value type; inject a different service from
    /// tests if needed.
    ///
    /// NOTE: This is a pure function dependency — the router does not
    /// observe the service, it only queries it per call. Upstream callers
    /// are responsible for invalidating cached URLs when proxies appear or
    /// disappear.
    private let service: ProxyService

    // MARK: - Init

    /// - Parameter service: Defaults to `ProxyService.shared`. Pass a
    ///   dedicated actor instance for tests.
    init(service: ProxyService = .shared) {
        self.service = service
    }

    // MARK: - Playback

    /// Returns the URL that the PlaybackEngine should use for the given
    /// clip during interactive editing.
    ///
    /// If a proxy has been registered and its file is still on disk the
    /// proxy URL is returned; otherwise the original URL is returned
    /// unchanged.
    ///
    /// - Parameters:
    ///   - clipID: Clip identifier. Currently unused in the lookup (the
    ///     `ProxyService` keys on source URL) but retained in the signature
    ///     so future implementations can migrate to a clip-keyed registry
    ///     without touching call sites.
    ///   - originalURL: The clip's original master source URL.
    /// - Returns: Proxy URL when available, else `originalURL`.
    func playbackURL(for clipID: UUID, originalURL: URL) async -> URL {
        _ = clipID // reserved for future clip-keyed registry
        return await service.getPlaybackPath(for: originalURL)
    }

    // MARK: - Export

    /// Returns the URL that the export pipeline should use for the given
    /// clip.
    ///
    /// **This always returns `originalURL`.** The export pipeline must never
    /// emit proxy footage — doing so would ship a low-resolution master to
    /// the user. This function exists (rather than just passing the
    /// original URL directly) to make the "export reads originals" decision
    /// explicit at every call site, and to keep a symmetric router API with
    /// `playbackURL(for:originalURL:)`.
    ///
    /// - Parameters:
    ///   - clipID: Clip identifier. Ignored in the current implementation.
    ///   - originalURL: The clip's original master source URL.
    /// - Returns: `originalURL` verbatim.
    func exportURL(for clipID: UUID, originalURL: URL) -> URL {
        _ = clipID // no-op — export ignores the clip registry entirely.
        return originalURL
    }
}
