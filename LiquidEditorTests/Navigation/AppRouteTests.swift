import Testing
import Foundation
@testable import LiquidEditor

@Suite("AppRoute Tests")
struct AppRouteTests {

    // MARK: - Route Creation

    @Test("All route cases can be created")
    func allRouteCasesCanBeCreated() {
        let projectLibrary = AppRoute.projectLibrary
        let editor = AppRoute.editor(projectId: "proj-123")
        let settings = AppRoute.settings
        let onboarding = AppRoute.onboarding
        let fullscreenPreview = AppRoute.fullscreenPreview
        let mediaBrowser = AppRoute.mediaBrowser

        // Verify each case exists (would fail to compile if missing)
        #expect(projectLibrary == .projectLibrary)
        #expect(editor == .editor(projectId: "proj-123"))
        #expect(settings == .settings)
        #expect(onboarding == .onboarding)
        #expect(fullscreenPreview == .fullscreenPreview)
        #expect(mediaBrowser == .mediaBrowser)
    }

    // MARK: - Hashable Conformance

    @Test("Same route equals same route")
    func sameRouteEquals() {
        #expect(AppRoute.projectLibrary == AppRoute.projectLibrary)
        #expect(AppRoute.settings == AppRoute.settings)
        #expect(AppRoute.onboarding == AppRoute.onboarding)
        #expect(AppRoute.fullscreenPreview == AppRoute.fullscreenPreview)
        #expect(AppRoute.mediaBrowser == AppRoute.mediaBrowser)
    }

    @Test("Editor routes with same projectId are equal")
    func editorRoutesWithSameIdAreEqual() {
        let a = AppRoute.editor(projectId: "abc")
        let b = AppRoute.editor(projectId: "abc")
        #expect(a == b)
    }

    @Test("Different routes are not equal")
    func differentRoutesAreNotEqual() {
        #expect(AppRoute.projectLibrary != AppRoute.settings)
        #expect(AppRoute.settings != AppRoute.onboarding)
        #expect(AppRoute.onboarding != AppRoute.fullscreenPreview)
        #expect(AppRoute.fullscreenPreview != AppRoute.mediaBrowser)
        #expect(AppRoute.mediaBrowser != AppRoute.projectLibrary)
    }

    @Test("Editor routes with different projectId are not equal")
    func editorRoutesWithDifferentIdAreNotEqual() {
        let a = AppRoute.editor(projectId: "proj-1")
        let b = AppRoute.editor(projectId: "proj-2")
        #expect(a != b)
    }

    @Test("Editor route is not equal to other route types")
    func editorRouteIsNotEqualToOtherTypes() {
        let editor = AppRoute.editor(projectId: "proj-1")
        #expect(editor != AppRoute.projectLibrary)
        #expect(editor != AppRoute.settings)
    }

    // MARK: - Hashable (Set / Dictionary usage)

    @Test("Routes can be used in a Set")
    func routesCanBeUsedInSet() {
        var routeSet: Set<AppRoute> = []
        routeSet.insert(.projectLibrary)
        routeSet.insert(.settings)
        routeSet.insert(.editor(projectId: "proj-1"))
        routeSet.insert(.editor(projectId: "proj-1")) // duplicate

        #expect(routeSet.count == 3)
        #expect(routeSet.contains(.projectLibrary))
        #expect(routeSet.contains(.settings))
        #expect(routeSet.contains(.editor(projectId: "proj-1")))
    }

    @Test("Same routes produce same hash value")
    func sameRoutesProduceSameHash() {
        let a = AppRoute.editor(projectId: "xyz")
        let b = AppRoute.editor(projectId: "xyz")
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - Associated Values

    @Test("Editor route stores projectId")
    func editorRouteStoresProjectId() {
        let route = AppRoute.editor(projectId: "my-project-42")
        if case .editor(let projectId) = route {
            #expect(projectId == "my-project-42")
        } else {
            Issue.record("Expected editor route with projectId")
        }
    }

    @Test("Editor route with empty projectId works")
    func editorRouteWithEmptyProjectId() {
        let route = AppRoute.editor(projectId: "")
        if case .editor(let projectId) = route {
            #expect(projectId == "")
        } else {
            Issue.record("Expected editor route with empty projectId")
        }
    }

    @Test("Editor route with special characters in projectId")
    func editorRouteWithSpecialCharacters() {
        let specialId = "proj-ABC_123-!@#"
        let route = AppRoute.editor(projectId: specialId)
        if case .editor(let projectId) = route {
            #expect(projectId == specialId)
        } else {
            Issue.record("Expected editor route with special characters projectId")
        }
    }
}
