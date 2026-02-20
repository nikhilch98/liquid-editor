import Testing
@testable import LiquidEditor

// MARK: - EditorViewModel Tracking Tests

@Suite("EditorViewModel Tracking Tests")
@MainActor
struct EditorViewModelTrackingTests {

    // MARK: - Helpers

    private func makeVM() -> EditorViewModel {
        let project = Project(name: "Tracking Test", sourceVideoPath: "/test/video.mp4")
        return EditorViewModel(project: project)
    }

    // MARK: - Initial State

    @Test("Initial tracking boxes are empty")
    func initialTrackingBoxes() {
        let vm = makeVM()
        #expect(vm.currentTrackingBoxes.isEmpty)
    }

    @Test("Initial tracking session ID is nil")
    func initialSessionId() {
        let vm = makeVM()
        #expect(vm.activeTrackingSessionId == nil)
    }

    @Test("isTrackingActive defaults to false")
    func trackingActiveDefault() {
        let vm = makeVM()
        #expect(vm.isTrackingActive == false)
    }

    @Test("isTrackDebugActive defaults to false")
    func trackDebugDefault() {
        let vm = makeVM()
        #expect(vm.isTrackDebugActive == false)
    }

    // MARK: - updateTrackingBoxes Early Returns

    @Test("updateTrackingBoxes clears boxes when no session active")
    func updateWithNoSession() async {
        let vm = makeVM()
        vm.activeTrackingSessionId = nil
        vm.isTrackingActive = true
        // Manually set some boxes to verify they get cleared
        vm.currentTrackingBoxes = [
            TrackedBoundingBox(
                id: "test-box",
                normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3),
                confidence: 0.9,
                label: "Person",
                personIndex: 0,
                skeletonJoints: nil
            ),
        ]
        #expect(!vm.currentTrackingBoxes.isEmpty)

        await vm.updateTrackingBoxes(for: 1000)
        #expect(vm.currentTrackingBoxes.isEmpty)
    }

    @Test("updateTrackingBoxes clears boxes when tracking inactive")
    func updateWithTrackingInactive() async {
        let vm = makeVM()
        vm.activeTrackingSessionId = "test-session"
        vm.isTrackingActive = false
        // Manually set some boxes to verify they get cleared
        vm.currentTrackingBoxes = [
            TrackedBoundingBox(
                id: "test-box",
                normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3),
                confidence: 0.9,
                label: "Person",
                personIndex: 0,
                skeletonJoints: nil
            ),
        ]
        #expect(!vm.currentTrackingBoxes.isEmpty)

        await vm.updateTrackingBoxes(for: 1000)
        #expect(vm.currentTrackingBoxes.isEmpty)
    }

    @Test("updateTrackingBoxes does nothing when boxes already empty and no session")
    func updateAlreadyEmptyNoSession() async {
        let vm = makeVM()
        vm.activeTrackingSessionId = nil
        vm.isTrackingActive = false
        #expect(vm.currentTrackingBoxes.isEmpty)

        await vm.updateTrackingBoxes(for: 500)
        #expect(vm.currentTrackingBoxes.isEmpty)
    }

    @Test("updateTrackingBoxes clears when both session nil and tracking inactive")
    func updateBothNilAndInactive() async {
        let vm = makeVM()
        vm.activeTrackingSessionId = nil
        vm.isTrackingActive = false
        vm.currentTrackingBoxes = [
            TrackedBoundingBox(
                id: "stale-box",
                normalizedRect: CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1),
                confidence: 0.5,
                label: nil,
                personIndex: nil,
                skeletonJoints: nil
            ),
        ]

        await vm.updateTrackingBoxes(for: 0)
        #expect(vm.currentTrackingBoxes.isEmpty)
    }

    // MARK: - toggleTrackDebug

    @Test("toggleTrackDebug flips isTrackDebugActive from false to true")
    func toggleTrackDebugOn() {
        let vm = makeVM()
        #expect(vm.isTrackDebugActive == false)
        vm.toggleTrackDebug()
        #expect(vm.isTrackDebugActive == true)
    }

    @Test("toggleTrackDebug flips isTrackDebugActive from true to false")
    func toggleTrackDebugOff() {
        let vm = makeVM()
        vm.toggleTrackDebug() // false -> true
        vm.toggleTrackDebug() // true -> false
        #expect(vm.isTrackDebugActive == false)
    }

    @Test("toggleTrackDebug can be called multiple times")
    func toggleTrackDebugMultiple() {
        let vm = makeVM()
        for i in 0..<6 {
            vm.toggleTrackDebug()
            let expected = (i % 2) == 0 // 0->true, 1->false, 2->true, ...
            #expect(vm.isTrackDebugActive == expected)
        }
    }

    // MARK: - Property Mutation

    @Test("isTrackingActive can be set directly")
    func setTrackingActive() {
        let vm = makeVM()
        vm.isTrackingActive = true
        #expect(vm.isTrackingActive == true)
        vm.isTrackingActive = false
        #expect(vm.isTrackingActive == false)
    }

    @Test("activeTrackingSessionId can be set and cleared")
    func setAndClearSessionId() {
        let vm = makeVM()
        vm.activeTrackingSessionId = "session-123"
        #expect(vm.activeTrackingSessionId == "session-123")
        vm.activeTrackingSessionId = nil
        #expect(vm.activeTrackingSessionId == nil)
    }

    @Test("currentTrackingBoxes can be set manually")
    func setTrackingBoxes() {
        let vm = makeVM()
        let boxes = [
            TrackedBoundingBox(
                id: "box-1",
                normalizedRect: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5),
                confidence: 0.95,
                label: "Person 1",
                personIndex: 0,
                skeletonJoints: nil
            ),
            TrackedBoundingBox(
                id: "box-2",
                normalizedRect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.6),
                confidence: 0.80,
                label: "Person 2",
                personIndex: 1,
                skeletonJoints: nil
            ),
        ]
        vm.currentTrackingBoxes = boxes
        #expect(vm.currentTrackingBoxes.count == 2)
        #expect(vm.currentTrackingBoxes[0].id == "box-1")
        #expect(vm.currentTrackingBoxes[1].id == "box-2")
    }

    @Test("Clearing tracking boxes results in empty array")
    func clearTrackingBoxes() {
        let vm = makeVM()
        vm.currentTrackingBoxes = [
            TrackedBoundingBox(
                id: "temp",
                normalizedRect: .zero,
                confidence: 1.0,
                label: nil,
                personIndex: nil,
                skeletonJoints: nil
            ),
        ]
        #expect(vm.currentTrackingBoxes.count == 1)
        vm.currentTrackingBoxes = []
        #expect(vm.currentTrackingBoxes.isEmpty)
    }
}
