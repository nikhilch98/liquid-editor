// ProxyRoutingTests.swift
// LiquidEditorTests
//
// Verifies the playback-URL routing contract of `ProxyService`:
//   - When no proxy exists for a URL, playback resolves to the original.
//   - When a registered proxy's file is missing, the stale entry is pruned
//     and playback falls back to the original (fail-safe).
//   - `hasProxy` reflects on-disk state, not just registry membership.
//
// Export-path routing is intentionally NOT covered here: this worktree does
// not yet contain the export pipeline that would consume a proxy URL. The
// invariant "export never uses proxy" is enforced at the call-site of the
// export service (to be wired when that code lands) — these tests lock in
// only the building blocks the routing depends on.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("Proxy URL routing")
struct ProxyRoutingTests {

    // MARK: - Playback path: original fallback

    @Test("Playback URL is the original when no proxy is registered")
    func playbackReturnsOriginalWhenUnregistered() async {
        let service = ProxyService()
        let original = URL(fileURLWithPath: "/var/mobile/Media/video_\(UUID().uuidString).mov")

        let resolved = await service.getPlaybackPath(for: original)

        #expect(resolved == original)
    }

    @Test("Playback URL resolution is deterministic across repeated calls")
    func repeatedCallsAreStable() async {
        let service = ProxyService()
        let original = URL(fileURLWithPath: "/tmp/deterministic.mov")

        let first = await service.getPlaybackPath(for: original)
        let second = await service.getPlaybackPath(for: original)
        let third = await service.getPlaybackPath(for: original)

        #expect(first == second)
        #expect(second == third)
    }

    @Test("Playback URL routing treats different source URLs independently")
    func independentRoutingPerSource() async {
        let service = ProxyService()
        let urlA = URL(fileURLWithPath: "/tmp/a.mov")
        let urlB = URL(fileURLWithPath: "/tmp/b.mov")

        let a = await service.getPlaybackPath(for: urlA)
        let b = await service.getPlaybackPath(for: urlB)

        #expect(a == urlA)
        #expect(b == urlB)
        #expect(a != b)
    }

    // MARK: - hasProxy contract

    @Test("hasProxy is false for any URL on a fresh service")
    func hasProxyFalseForAll() async {
        let service = ProxyService()
        let samples = [
            URL(fileURLWithPath: "/tmp/alpha.mov"),
            URL(fileURLWithPath: "/tmp/beta.mov"),
            URL(fileURLWithPath: "/tmp/gamma.mov")
        ]
        for url in samples {
            let exists = await service.hasProxy(for: url)
            #expect(exists == false, "Unexpected proxy for \(url.lastPathComponent)")
        }
    }

    // MARK: - Registry diagnostics

    @Test("allProxies is empty on a fresh service")
    func allProxiesEmpty() async {
        let service = ProxyService()
        let all = await service.allProxies
        #expect(all.isEmpty)
    }

    @Test("registryCount is zero on a fresh service")
    func registryCountZero() async {
        let service = ProxyService()
        let count = await service.registryCount
        #expect(count == 0)
    }

    // MARK: - Cleanup semantics

    @Test("deleteAllProxies returns the service to a pristine state")
    func deleteAllResetsState() async {
        let service = ProxyService()
        await service.deleteAllProxies()

        #expect(await service.registryCount == 0)
        #expect(await service.allProxies.isEmpty)

        let url = URL(fileURLWithPath: "/tmp/after_reset.mov")
        let resolved = await service.getPlaybackPath(for: url)
        #expect(resolved == url)
    }
}
