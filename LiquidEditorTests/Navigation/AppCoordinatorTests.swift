import Testing
import SwiftUI
@testable import LiquidEditor

// MARK: - ActiveSheet Tests

@Suite("ActiveSheet Tests")
struct ActiveSheetTests {

    @Test("All sheet cases have unique ids")
    func allSheetCasesHaveUniqueIds() {
        let allSheets: [ActiveSheet] = [
            .export, .colorGrading, .videoEffects, .transitions,
            .audio, .textEditor, .stickerPicker, .trackManagement,
            .speedControl, .volumeControl, .crop, .personSelection,
        ]
        let ids = allSheets.map(\.id)
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == allSheets.count)
    }

    @Test("Sheet ids match expected strings")
    func sheetIdsMatchExpected() {
        #expect(ActiveSheet.export.id == "export")
        #expect(ActiveSheet.colorGrading.id == "colorGrading")
        #expect(ActiveSheet.videoEffects.id == "videoEffects")
        #expect(ActiveSheet.transitions.id == "transitions")
        #expect(ActiveSheet.audio.id == "audio")
        #expect(ActiveSheet.textEditor.id == "textEditor")
        #expect(ActiveSheet.stickerPicker.id == "stickerPicker")
        #expect(ActiveSheet.trackManagement.id == "trackManagement")
        #expect(ActiveSheet.speedControl.id == "speedControl")
        #expect(ActiveSheet.volumeControl.id == "volumeControl")
        #expect(ActiveSheet.crop.id == "crop")
        #expect(ActiveSheet.personSelection.id == "personSelection")
    }

    @Test("Total number of sheet cases is 12")
    func totalSheetCases() {
        let allSheets: [ActiveSheet] = [
            .export, .colorGrading, .videoEffects, .transitions,
            .audio, .textEditor, .stickerPicker, .trackManagement,
            .speedControl, .volumeControl, .crop, .personSelection,
        ]
        #expect(allSheets.count == 12)
    }

    @Test("Equatable conformance works")
    func equatableConformance() {
        #expect(ActiveSheet.export == ActiveSheet.export)
        #expect(ActiveSheet.export != ActiveSheet.colorGrading)
        #expect(ActiveSheet.crop == ActiveSheet.crop)
        #expect(ActiveSheet.crop != ActiveSheet.audio)
    }
}

// MARK: - AppCoordinator Tests

@Suite("AppCoordinator Tests")
@MainActor
struct AppCoordinatorTests {

    // MARK: - Initial State

    @Test("Initial state has empty navigation path")
    func initialStateEmptyPath() {
        let coordinator = AppCoordinator()
        #expect(coordinator.path.isEmpty)
    }

    @Test("Initial state has no active sheet")
    func initialStateNoSheet() {
        let coordinator = AppCoordinator()
        #expect(coordinator.activeSheet == nil)
    }

    // MARK: - Push Navigation

    @Test("navigateToEditor adds route to path")
    func navigateToEditorAddsRoute() {
        let coordinator = AppCoordinator()
        coordinator.navigateToEditor(projectId: "proj-1")
        #expect(coordinator.path.count == 1)
    }

    @Test("navigateToSettings adds route to path")
    func navigateToSettingsAddsRoute() {
        let coordinator = AppCoordinator()
        coordinator.navigateToSettings()
        #expect(coordinator.path.count == 1)
    }

    @Test("navigateToOnboarding adds route to path")
    func navigateToOnboardingAddsRoute() {
        let coordinator = AppCoordinator()
        coordinator.navigateToOnboarding()
        #expect(coordinator.path.count == 1)
    }

    @Test("navigateToFullscreenPreview adds route to path")
    func navigateToFullscreenPreviewAddsRoute() {
        let coordinator = AppCoordinator()
        coordinator.navigateToFullscreenPreview()
        #expect(coordinator.path.count == 1)
    }

    @Test("navigateToMediaBrowser adds route to path")
    func navigateToMediaBrowserAddsRoute() {
        let coordinator = AppCoordinator()
        coordinator.navigateToMediaBrowser()
        #expect(coordinator.path.count == 1)
    }

    @Test("push adds arbitrary route to path")
    func pushAddsRoute() {
        let coordinator = AppCoordinator()
        coordinator.push(.settings)
        #expect(coordinator.path.count == 1)
    }

    @Test("Multiple pushes accumulate in path")
    func multiplePushesAccumulate() {
        let coordinator = AppCoordinator()
        coordinator.navigateToSettings()
        coordinator.navigateToEditor(projectId: "p1")
        coordinator.navigateToMediaBrowser()
        #expect(coordinator.path.count == 3)
    }

    // MARK: - Pop Navigation

    @Test("pop removes last route from path")
    func popRemovesLastRoute() {
        let coordinator = AppCoordinator()
        coordinator.navigateToSettings()
        coordinator.navigateToEditor(projectId: "p1")
        #expect(coordinator.path.count == 2)

        coordinator.pop()
        #expect(coordinator.path.count == 1)
    }

    @Test("pop on empty path does nothing")
    func popOnEmptyPathDoesNothing() {
        let coordinator = AppCoordinator()
        coordinator.pop()
        #expect(coordinator.path.isEmpty)
    }

    @Test("popToRoot clears navigation path")
    func popToRootClearsPath() {
        let coordinator = AppCoordinator()
        coordinator.navigateToSettings()
        coordinator.navigateToEditor(projectId: "p1")
        coordinator.navigateToMediaBrowser()
        #expect(coordinator.path.count == 3)

        coordinator.popToRoot()
        #expect(coordinator.path.isEmpty)
    }

    @Test("popToRoot on empty path is safe")
    func popToRootOnEmptyPath() {
        let coordinator = AppCoordinator()
        coordinator.popToRoot()
        #expect(coordinator.path.isEmpty)
    }

    // MARK: - Sheet Presentation

    @Test("presentSheet sets active sheet")
    func presentSheetSetsActiveSheet() {
        let coordinator = AppCoordinator()
        coordinator.presentSheet(.export)
        #expect(coordinator.activeSheet == .export)
    }

    @Test("presentSheet with various sheet types")
    func presentSheetVariousTypes() {
        let coordinator = AppCoordinator()

        let sheets: [ActiveSheet] = [
            .export, .colorGrading, .videoEffects, .transitions,
            .audio, .textEditor, .stickerPicker, .trackManagement,
            .speedControl, .volumeControl, .crop, .personSelection,
        ]

        for sheet in sheets {
            coordinator.presentSheet(sheet)
            #expect(coordinator.activeSheet == sheet)
        }
    }

    @Test("dismissSheet clears active sheet")
    func dismissSheetClearsActiveSheet() {
        let coordinator = AppCoordinator()
        coordinator.presentSheet(.export)
        #expect(coordinator.activeSheet == .export)

        coordinator.dismissSheet()
        #expect(coordinator.activeSheet == nil)
    }

    @Test("dismissSheet when no sheet is showing is safe")
    func dismissSheetWhenNoSheet() {
        let coordinator = AppCoordinator()
        coordinator.dismissSheet()
        #expect(coordinator.activeSheet == nil)
    }

    @Test("Presenting a new sheet replaces the active sheet")
    func presentNewSheetReplacesActive() {
        let coordinator = AppCoordinator()
        coordinator.presentSheet(.export)
        #expect(coordinator.activeSheet == .export)

        coordinator.presentSheet(.colorGrading)
        #expect(coordinator.activeSheet == .colorGrading)
    }

    // MARK: - Sheet Convenience Methods

    @Test("presentExport sets export sheet")
    func presentExport() {
        let coordinator = AppCoordinator()
        coordinator.presentExport()
        #expect(coordinator.activeSheet == .export)
    }

    @Test("presentColorGrading sets colorGrading sheet")
    func presentColorGrading() {
        let coordinator = AppCoordinator()
        coordinator.presentColorGrading()
        #expect(coordinator.activeSheet == .colorGrading)
    }

    @Test("presentVideoEffects sets videoEffects sheet")
    func presentVideoEffects() {
        let coordinator = AppCoordinator()
        coordinator.presentVideoEffects()
        #expect(coordinator.activeSheet == .videoEffects)
    }

    @Test("presentTransitions sets transitions sheet")
    func presentTransitions() {
        let coordinator = AppCoordinator()
        coordinator.presentTransitions()
        #expect(coordinator.activeSheet == .transitions)
    }

    @Test("presentAudio sets audio sheet")
    func presentAudio() {
        let coordinator = AppCoordinator()
        coordinator.presentAudio()
        #expect(coordinator.activeSheet == .audio)
    }

    @Test("presentTextEditor sets textEditor sheet")
    func presentTextEditor() {
        let coordinator = AppCoordinator()
        coordinator.presentTextEditor()
        #expect(coordinator.activeSheet == .textEditor)
    }

    @Test("presentStickerPicker sets stickerPicker sheet")
    func presentStickerPicker() {
        let coordinator = AppCoordinator()
        coordinator.presentStickerPicker()
        #expect(coordinator.activeSheet == .stickerPicker)
    }

    @Test("presentTrackManagement sets trackManagement sheet")
    func presentTrackManagement() {
        let coordinator = AppCoordinator()
        coordinator.presentTrackManagement()
        #expect(coordinator.activeSheet == .trackManagement)
    }

    @Test("presentSpeedControl sets speedControl sheet")
    func presentSpeedControl() {
        let coordinator = AppCoordinator()
        coordinator.presentSpeedControl()
        #expect(coordinator.activeSheet == .speedControl)
    }

    @Test("presentVolumeControl sets volumeControl sheet")
    func presentVolumeControl() {
        let coordinator = AppCoordinator()
        coordinator.presentVolumeControl()
        #expect(coordinator.activeSheet == .volumeControl)
    }

    @Test("presentCrop sets crop sheet")
    func presentCrop() {
        let coordinator = AppCoordinator()
        coordinator.presentCrop()
        #expect(coordinator.activeSheet == .crop)
    }

    @Test("presentPersonSelection sets personSelection sheet")
    func presentPersonSelection() {
        let coordinator = AppCoordinator()
        coordinator.presentPersonSelection()
        #expect(coordinator.activeSheet == .personSelection)
    }

    // MARK: - Combined Navigation and Sheet State

    @Test("Navigation and sheet state are independent")
    func navigationAndSheetIndependent() {
        let coordinator = AppCoordinator()
        coordinator.navigateToEditor(projectId: "proj-1")
        coordinator.presentSheet(.export)

        #expect(coordinator.path.count == 1)
        #expect(coordinator.activeSheet == .export)

        coordinator.dismissSheet()
        #expect(coordinator.path.count == 1)
        #expect(coordinator.activeSheet == nil)

        coordinator.popToRoot()
        #expect(coordinator.path.isEmpty)
        #expect(coordinator.activeSheet == nil)
    }

    @Test("popToRoot does not affect active sheet")
    func popToRootDoesNotAffectSheet() {
        let coordinator = AppCoordinator()
        coordinator.navigateToSettings()
        coordinator.presentSheet(.crop)

        coordinator.popToRoot()
        #expect(coordinator.path.isEmpty)
        #expect(coordinator.activeSheet == .crop)
    }
}
