import Testing
import Foundation
@testable import LiquidEditor

// MARK: - AspectRatioMode Tests

@Suite("AspectRatioMode Tests")
struct AspectRatioModeTests {

    @Test("All cases exist")
    func allCases() {
        let cases = AspectRatioMode.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.letterbox))
        #expect(cases.contains(.zoomToFill))
        #expect(cases.contains(.stretch))
    }

    @Test("Display names are correct")
    func displayNames() {
        #expect(AspectRatioMode.letterbox.displayName == "Fit (Letterbox)")
        #expect(AspectRatioMode.zoomToFill.displayName == "Fill (Crop)")
        #expect(AspectRatioMode.stretch.displayName == "Stretch")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for mode in AspectRatioMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(AspectRatioMode.self, from: data)
            #expect(decoded == mode)
        }
    }
}

// MARK: - AspectRatioSetting Tests

@Suite("AspectRatioSetting Tests")
struct AspectRatioSettingTests {

    @Test("Landscape 16:9 properties")
    func landscape16x9() {
        let ratio = AspectRatioSetting.landscape16x9
        #expect(ratio.widthRatio == 16)
        #expect(ratio.heightRatio == 9)
        #expect(ratio.label == "16:9")
        #expect(ratio.isLandscape == true)
        #expect(ratio.isPortrait == false)
        #expect(ratio.isSquare == false)
    }

    @Test("Portrait 9:16 properties")
    func portrait9x16() {
        let ratio = AspectRatioSetting.portrait9x16
        #expect(ratio.widthRatio == 9)
        #expect(ratio.heightRatio == 16)
        #expect(ratio.isLandscape == false)
        #expect(ratio.isPortrait == true)
        #expect(ratio.isSquare == false)
    }

    @Test("Square 1:1 properties")
    func square1x1() {
        let ratio = AspectRatioSetting.square1x1
        #expect(ratio.widthRatio == 1)
        #expect(ratio.heightRatio == 1)
        #expect(ratio.isLandscape == false)
        #expect(ratio.isPortrait == false)
        #expect(ratio.isSquare == true)
    }

    @Test("All presets correct count")
    func allPresets() {
        #expect(AspectRatioSetting.presets.count == 7)
    }

    @Test("Value computes decimal ratio")
    func valueComputation() {
        let ratio = AspectRatioSetting.landscape16x9
        let expected = 16.0 / 9.0
        #expect(abs(ratio.value - expected) < 0.0001)
    }

    @Test("Classic 4:3 value")
    func classic4x3Value() {
        let ratio = AspectRatioSetting.classic4x3
        let expected = 4.0 / 3.0
        #expect(abs(ratio.value - expected) < 0.0001)
    }

    @Test("Cinematic 2.35:1 properties")
    func cinematic() {
        let ratio = AspectRatioSetting.cinematic
        #expect(ratio.widthRatio == 47)
        #expect(ratio.heightRatio == 20)
        #expect(ratio.label == "2.35:1")
        #expect(ratio.isLandscape == true)
    }

    @Test("fromWidthHeight finds matching preset")
    func fromWidthHeightMatch() {
        // 1920x1080 matches 16:9
        let result = AspectRatioSetting.fromWidthHeight(width: 1920, height: 1080)
        #expect(result == AspectRatioSetting.landscape16x9)
    }

    @Test("fromWidthHeight finds square preset")
    func fromWidthHeightSquare() {
        let result = AspectRatioSetting.fromWidthHeight(width: 500, height: 500)
        #expect(result == AspectRatioSetting.square1x1)
    }

    @Test("fromWidthHeight returns nil for no match")
    func fromWidthHeightNoMatch() {
        let result = AspectRatioSetting.fromWidthHeight(width: 1000, height: 777)
        #expect(result == nil)
    }

    @Test("with() copy method")
    func withCopy() {
        let original = AspectRatioSetting.landscape16x9
        let modified = original.with(label: "Custom 16:9")
        #expect(modified.widthRatio == 16)
        #expect(modified.heightRatio == 9)
        #expect(modified.label == "Custom 16:9")
    }

    @Test("with() changes ratio")
    func withChangeRatio() {
        let original = AspectRatioSetting.landscape16x9
        let modified = original.with(widthRatio: 21, heightRatio: 9, label: "21:9")
        #expect(modified.widthRatio == 21)
        #expect(modified.heightRatio == 9)
    }

    @Test("Equatable ignores label")
    func equatableIgnoresLabel() {
        let a = AspectRatioSetting(widthRatio: 16, heightRatio: 9, label: "16:9")
        let b = AspectRatioSetting(widthRatio: 16, heightRatio: 9, label: "Different Label")
        #expect(a == b)
    }

    @Test("Equatable distinguishes different ratios")
    func equatableDifferentRatios() {
        #expect(AspectRatioSetting.landscape16x9 != AspectRatioSetting.portrait9x16)
    }

    @Test("Hashable uses ratio components")
    func hashable() {
        let a = AspectRatioSetting(widthRatio: 16, heightRatio: 9, label: "A")
        let b = AspectRatioSetting(widthRatio: 16, heightRatio: 9, label: "B")
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = AspectRatioSetting.landscape16x9
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AspectRatioSetting.self, from: data)
        #expect(decoded == original)
        #expect(decoded.label == original.label)
    }

    @Test("Portrait 4:5 preset")
    func portrait4x5() {
        let ratio = AspectRatioSetting.portrait4x5
        #expect(ratio.widthRatio == 4)
        #expect(ratio.heightRatio == 5)
        #expect(ratio.isPortrait == true)
    }
}

// MARK: - ProjectMetadata Tests

@Suite("ProjectMetadata Tests")
struct ProjectMetadataTests {

    func makeMetadata(
        id: String = "test-id",
        name: String = "Test Project",
        timelineDurationMs: Int = 90000
    ) -> ProjectMetadata {
        ProjectMetadata(
            id: id,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            modifiedAt: Date(timeIntervalSince1970: 1700000000),
            timelineDurationMs: timelineDurationMs,
            clipCount: 5
        )
    }

    @Test("Creation with defaults")
    func creation() {
        let meta = makeMetadata()
        #expect(meta.id == "test-id")
        #expect(meta.name == "Test Project")
        #expect(meta.clipCount == 5)
        #expect(meta.timelineDurationMs == 90000)
        #expect(meta.version == 2)
        #expect(meta.tags == [])
        #expect(meta.isFavorite == false)
        #expect(meta.thumbnailPath == nil)
        #expect(meta.description == nil)
        #expect(meta.colorLabel == nil)
    }

    @Test("Formatted duration - minutes and seconds")
    func formattedDuration() {
        let meta = makeMetadata(timelineDurationMs: 90000)
        #expect(meta.formattedDuration == "1:30")
    }

    @Test("Formatted duration - hours")
    func formattedDurationHours() {
        let meta = makeMetadata(timelineDurationMs: 3661000) // 1h 1m 1s
        #expect(meta.formattedDuration == "1:01:01")
    }

    @Test("Formatted duration - zero")
    func formattedDurationZero() {
        let meta = makeMetadata(timelineDurationMs: 0)
        #expect(meta.formattedDuration == "0:00")
    }

    @Test("Equatable by id only")
    func equatable() {
        let a = makeMetadata(id: "same-id", name: "Name A")
        let b = makeMetadata(id: "same-id", name: "Name B")
        #expect(a == b)
    }

    @Test("Equatable different ids")
    func equatableDifferent() {
        let a = makeMetadata(id: "id-1")
        let b = makeMetadata(id: "id-2")
        #expect(a != b)
    }

    @Test("with() copy method")
    func withCopy() {
        let original = makeMetadata()
        let modified = original.with(name: "Updated", isFavorite: true)
        #expect(modified.name == "Updated")
        #expect(modified.isFavorite == true)
        #expect(modified.id == original.id)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = ProjectMetadata(
            id: "proj-1",
            name: "My Project",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            modifiedAt: Date(timeIntervalSince1970: 1700001000),
            thumbnailPath: "thumb.jpg",
            timelineDurationMs: 5000,
            clipCount: 3,
            version: 2,
            description: "A test project",
            tags: ["tag1", "tag2"],
            isFavorite: true,
            colorLabel: .blue
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectMetadata.self, from: data)
        #expect(decoded == original)
        #expect(decoded.name == "My Project")
        #expect(decoded.thumbnailPath == "thumb.jpg")
        #expect(decoded.tags == ["tag1", "tag2"])
        #expect(decoded.isFavorite == true)
        #expect(decoded.colorLabel == .blue)
    }
}

// MARK: - ProjectColor Tests

@Suite("ProjectColor Tests")
struct ProjectColorTests {

    @Test("All cases exist")
    func allCases() {
        #expect(ProjectColor.allCases.count == 7)
    }

    @Test("Display names")
    func displayNames() {
        #expect(ProjectColor.red.displayName == "Red")
        #expect(ProjectColor.purple.displayName == "Purple")
        #expect(ProjectColor.pink.displayName == "Pink")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for color in ProjectColor.allCases {
            let data = try JSONEncoder().encode(color)
            let decoded = try JSONDecoder().decode(ProjectColor.self, from: data)
            #expect(decoded == color)
        }
    }
}

// MARK: - ProjectSettings Tests

@Suite("ProjectSettings Tests")
struct ProjectSettingsTests {

    @Test("Default settings")
    func defaults() {
        let settings = ProjectSettings()
        #expect(settings.resolution == .fullHD1080p)
        #expect(settings.frameRate == .auto)
        #expect(settings.aspectRatio == nil)
        #expect(settings.aspectRatioMode == .letterbox)
        #expect(settings.backgroundColor == 0xFF000000)
    }

    @Test("Static default settings matches init defaults")
    func staticDefault() {
        let settings = ProjectSettings.defaultSettings
        #expect(settings.resolution == .fullHD1080p)
        #expect(settings.frameRate == .auto)
    }

    @Test("Custom creation")
    func customCreation() {
        let settings = ProjectSettings(
            resolution: .uhd4k,
            frameRate: .fixed60,
            aspectRatio: .landscape16x9,
            aspectRatioMode: .zoomToFill,
            backgroundColor: 0xFFFFFFFF
        )
        #expect(settings.resolution == .uhd4k)
        #expect(settings.frameRate == .fixed60)
        #expect(settings.aspectRatio == .landscape16x9)
        #expect(settings.aspectRatioMode == .zoomToFill)
        #expect(settings.backgroundColor == 0xFFFFFFFF)
    }

    @Test("with() copy method")
    func withCopy() {
        let original = ProjectSettings()
        let modified = original.with(resolution: .hd720p)
        #expect(modified.resolution == .hd720p)
        #expect(modified.frameRate == .auto) // unchanged
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = ProjectSettings(
            resolution: .qhd1440p,
            frameRate: .fixed30,
            aspectRatio: .cinematic,
            aspectRatioMode: .stretch,
            backgroundColor: 0xFFFF0000
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectSettings.self, from: data)
        #expect(decoded.resolution == original.resolution)
        #expect(decoded.frameRate == original.frameRate)
        #expect(decoded.aspectRatio == original.aspectRatio)
        #expect(decoded.aspectRatioMode == original.aspectRatioMode)
        #expect(decoded.backgroundColor == original.backgroundColor)
    }
}

// MARK: - FrameRate Tests

@Suite("FrameRate Tests")
struct FrameRateTests {

    @Test("All frame rate values")
    func allValues() {
        #expect(FrameRate.fps24.value == 24)
        #expect(FrameRate.fps30.value == 30)
        #expect(FrameRate.fps60.value == 60)
    }

    @Test("Display names")
    func displayNames() {
        #expect(FrameRate.fps24.displayName == "24 FPS")
        #expect(FrameRate.fps30.displayName == "30 FPS")
        #expect(FrameRate.fps60.displayName == "60 FPS")
    }

    @Test("fromFps detection")
    func fromFps() {
        #expect(FrameRate.fromFps(23.976) == .fps24)
        #expect(FrameRate.fromFps(24.0) == .fps24)
        #expect(FrameRate.fromFps(29.97) == .fps30)
        #expect(FrameRate.fromFps(30.0) == .fps30)
        #expect(FrameRate.fromFps(59.94) == .fps60)
        #expect(FrameRate.fromFps(60.0) == .fps60)
    }
}

// MARK: - FrameRateOption Tests

@Suite("FrameRateOption Tests")
struct FrameRateOptionTests {

    @Test("Display names")
    func displayNames() {
        #expect(FrameRateOption.auto.displayName == "Auto (from source)")
        #expect(FrameRateOption.fixed24.displayName == "24 FPS")
        #expect(FrameRateOption.fixed30.displayName == "30 FPS")
        #expect(FrameRateOption.fixed60.displayName == "60 FPS")
    }

    @Test("Fixed rate returns correct FrameRate")
    func fixedRate() {
        #expect(FrameRateOption.auto.fixedRate == nil)
        #expect(FrameRateOption.fixed24.fixedRate == .fps24)
        #expect(FrameRateOption.fixed30.fixedRate == .fps30)
        #expect(FrameRateOption.fixed60.fixedRate == .fps60)
    }

    @Test("All cases")
    func allCases() {
        #expect(FrameRateOption.allCases.count == 4)
    }
}

// MARK: - Resolution Tests

@Suite("Resolution Tests")
struct ResolutionTests {

    @Test("Width and height for all resolutions")
    func widthHeight() {
        #expect(Resolution.sd480p.width == 854)
        #expect(Resolution.sd480p.height == 480)
        #expect(Resolution.hd720p.width == 1280)
        #expect(Resolution.hd720p.height == 720)
        #expect(Resolution.fullHD1080p.width == 1920)
        #expect(Resolution.fullHD1080p.height == 1080)
        #expect(Resolution.qhd1440p.width == 2560)
        #expect(Resolution.qhd1440p.height == 1440)
        #expect(Resolution.uhd4k.width == 3840)
        #expect(Resolution.uhd4k.height == 2160)
    }

    @Test("Display names")
    func displayNames() {
        #expect(Resolution.sd480p.displayName == "480p")
        #expect(Resolution.fullHD1080p.displayName == "1080p")
        #expect(Resolution.uhd4k.displayName == "4K")
    }
}

// MARK: - ProjectTemplate Tests

@Suite("ProjectTemplate Tests")
struct ProjectTemplateTests {

    @Test("Built-in templates count")
    func builtInsCount() {
        #expect(ProjectTemplate.builtIns.count == 7)
    }

    @Test("Blank template properties")
    func blankTemplate() {
        let blank = ProjectTemplate.blank
        #expect(blank.id == "builtin-blank")
        #expect(blank.name == "Blank")
        #expect(blank.category == .standard)
        #expect(blank.isBuiltIn == true)
        #expect(blank.aspectRatio == nil)
        #expect(blank.frameRate == .auto)
        #expect(blank.resolution == nil)
    }

    @Test("TikTok template properties")
    func tiktokTemplate() {
        let tt = ProjectTemplate.tiktokReels
        #expect(tt.id == "builtin-tiktok")
        #expect(tt.aspectRatio == .portrait9x16)
        #expect(tt.frameRate == .fixed30)
        #expect(tt.resolution == .fullHD1080p)
        #expect(tt.category == .social)
    }

    @Test("YouTube template properties")
    func youtubeTemplate() {
        let yt = ProjectTemplate.youtube
        #expect(yt.aspectRatio == .landscape16x9)
        #expect(yt.frameRate == .fixed30)
        #expect(yt.resolution == .fullHD1080p)
        #expect(yt.category == .standard)
    }

    @Test("Cinematic template")
    func cinematicTemplate() {
        let cin = ProjectTemplate.cinematicFilm
        #expect(cin.aspectRatio == .cinematic)
        #expect(cin.frameRate == .fixed24)
        #expect(cin.category == .cinematic)
    }

    @Test("toProjectSettings conversion")
    func toProjectSettings() {
        let settings = ProjectTemplate.tiktokReels.toProjectSettings()
        #expect(settings.resolution == .fullHD1080p)
        #expect(settings.frameRate == .fixed30)
        #expect(settings.aspectRatio == .portrait9x16)
        #expect(settings.aspectRatioMode == .zoomToFill)
    }

    @Test("Blank template toProjectSettings uses defaults")
    func blankToProjectSettings() {
        let settings = ProjectTemplate.blank.toProjectSettings()
        #expect(settings.resolution == .fullHD1080p)
        #expect(settings.frameRate == .auto)
        #expect(settings.aspectRatio == nil)
    }

    @Test("Equatable by id only")
    func equatable() {
        let a = ProjectTemplate.tiktokReels
        let b = a.with(name: "Different Name")
        #expect(a == b) // same id
    }

    @Test("with() copy method")
    func withCopy() {
        let original = ProjectTemplate.blank
        let modified = original.with(name: "Custom Blank", category: .custom)
        #expect(modified.name == "Custom Blank")
        #expect(modified.category == .custom)
        #expect(modified.id == "builtin-blank")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = ProjectTemplate.tiktokReels
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectTemplate.self, from: data)
        #expect(decoded == original)
        #expect(decoded.name == original.name)
        #expect(decoded.aspectRatio == original.aspectRatio)
    }
}

// MARK: - TemplateCategory Tests

@Suite("TemplateCategory Tests")
struct TemplateCategoryTests {

    @Test("All cases")
    func allCases() {
        #expect(TemplateCategory.allCases.count == 4)
    }

    @Test("Display names")
    func displayNames() {
        #expect(TemplateCategory.social.displayName == "Social")
        #expect(TemplateCategory.cinematic.displayName == "Cinematic")
        #expect(TemplateCategory.standard.displayName == "Standard")
        #expect(TemplateCategory.custom.displayName == "My Templates")
    }
}

// MARK: - DraftMetadata Tests

@Suite("DraftMetadata Tests")
struct DraftMetadataTests {

    @Test("Empty factory")
    func emptyFactory() {
        let meta = DraftMetadata.empty(projectId: "proj-1")
        #expect(meta.projectId == "proj-1")
        #expect(meta.currentIndex == 0)
        #expect(meta.drafts.isEmpty)
        #expect(meta.cleanShutdown == true)
    }

    @Test("Next index wraps around")
    func nextIndex() {
        let meta = DraftMetadata(projectId: "p", currentIndex: 4, drafts: [], cleanShutdown: true)
        #expect(meta.nextIndex == 0) // wraps at maxDrafts=5
    }

    @Test("Next index increments")
    func nextIndexIncrement() {
        let meta = DraftMetadata(projectId: "p", currentIndex: 2, drafts: [], cleanShutdown: true)
        #expect(meta.nextIndex == 3)
    }

    @Test("Latest draft finds most recent")
    func latestDraft() {
        let earlier = DraftEntry(
            index: 0,
            savedAt: Date(timeIntervalSince1970: 1000),
            clipCount: 1,
            timelineDurationMicros: 1_000_000,
            triggerReason: .autoSave
        )
        let later = DraftEntry(
            index: 1,
            savedAt: Date(timeIntervalSince1970: 2000),
            clipCount: 2,
            timelineDurationMicros: 2_000_000,
            triggerReason: .manualSave
        )
        let meta = DraftMetadata(projectId: "p", currentIndex: 1, drafts: [earlier, later], cleanShutdown: true)
        #expect(meta.latestDraft?.index == 1)
    }

    @Test("withNewDraft adds draft")
    func withNewDraft() {
        let meta = DraftMetadata.empty(projectId: "p")
        let draft = DraftEntry(
            index: 0,
            savedAt: Date(),
            clipCount: 3,
            timelineDurationMicros: 5_000_000,
            triggerReason: .significantEdit
        )
        let updated = meta.withNewDraft(draft)
        #expect(updated.drafts.count == 1)
        #expect(updated.currentIndex == 0)
        #expect(updated.cleanShutdown == false)
    }

    @Test("withNewDraft replaces existing slot")
    func withNewDraftReplace() {
        let draft0 = DraftEntry(
            index: 0,
            savedAt: Date(timeIntervalSince1970: 1000),
            clipCount: 1,
            timelineDurationMicros: 1_000_000,
            triggerReason: .autoSave
        )
        let meta = DraftMetadata(projectId: "p", currentIndex: 0, drafts: [draft0], cleanShutdown: true)
        let newDraft0 = DraftEntry(
            index: 0,
            savedAt: Date(timeIntervalSince1970: 2000),
            clipCount: 5,
            timelineDurationMicros: 5_000_000,
            triggerReason: .manualSave
        )
        let updated = meta.withNewDraft(newDraft0)
        #expect(updated.drafts.count == 1)
        #expect(updated.drafts[0].clipCount == 5)
    }

    @Test("markCleanShutdown")
    func markCleanShutdown() {
        let meta = DraftMetadata(projectId: "p", currentIndex: 0, drafts: [], cleanShutdown: false)
        let clean = meta.markCleanShutdown()
        #expect(clean.cleanShutdown == true)
    }

    @Test("markSessionStarted")
    func markSessionStarted() {
        let meta = DraftMetadata(projectId: "p", currentIndex: 0, drafts: [], cleanShutdown: true)
        let started = meta.markSessionStarted()
        #expect(started.cleanShutdown == false)
    }

    @Test("Equatable by projectId")
    func equatable() {
        let a = DraftMetadata(projectId: "same", currentIndex: 0, drafts: [], cleanShutdown: true)
        let b = DraftMetadata(projectId: "same", currentIndex: 3, drafts: [], cleanShutdown: false)
        #expect(a == b)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let draft = DraftEntry(
            index: 0,
            savedAt: Date(timeIntervalSince1970: 1700000000),
            clipCount: 2,
            timelineDurationMicros: 3_000_000,
            triggerReason: .autoSave
        )
        let original = DraftMetadata(projectId: "proj-1", currentIndex: 0, drafts: [draft], cleanShutdown: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DraftMetadata.self, from: data)
        #expect(decoded == original)
        #expect(decoded.drafts.count == 1)
        #expect(decoded.cleanShutdown == true)
    }
}

// MARK: - DraftEntry Tests

@Suite("DraftEntry Tests")
struct DraftEntryTests {

    @Test("Formatted duration")
    func formattedDuration() {
        let entry = DraftEntry(
            index: 0,
            savedAt: Date(),
            clipCount: 1,
            timelineDurationMicros: 125_000_000, // 2m 5s
            triggerReason: .autoSave
        )
        #expect(entry.formattedDuration == "2:05")
    }

    @Test("Trigger reason display names")
    func triggerReasonDisplayNames() {
        #expect(DraftTriggerReason.autoSave.displayName == "Auto-save")
        #expect(DraftTriggerReason.manualSave.displayName == "Manual save")
        #expect(DraftTriggerReason.significantEdit.displayName == "After edit")
        #expect(DraftTriggerReason.appBackground.displayName == "Background save")
    }

    @Test("with() copy method")
    func withCopy() {
        let original = DraftEntry(
            index: 0,
            savedAt: Date(),
            clipCount: 1,
            timelineDurationMicros: 1_000_000,
            triggerReason: .autoSave
        )
        let modified = original.with(clipCount: 10)
        #expect(modified.clipCount == 10)
        #expect(modified.index == 0)
    }
}

// MARK: - Project Tests

@Suite("Project Tests")
struct ProjectTests {

    func makeProject(
        id: String = "proj-1",
        name: String = "Test Project"
    ) -> Project {
        Project(
            id: id,
            name: name,
            sourceVideoPath: "Videos/test.mov",
            durationMicros: 10_000_000
        )
    }

    @Test("Creation with defaults")
    func creation() {
        let project = makeProject()
        #expect(project.id == "proj-1")
        #expect(project.name == "Test Project")
        #expect(project.sourceVideoPath == "Videos/test.mov")
        #expect(project.frameRate == .auto)
        #expect(project.durationMicros == 10_000_000)
        #expect(project.clips.isEmpty)
        #expect(project.inPointMicros == 0)
        #expect(project.outPointMicros == nil)
        #expect(project.version == 2)
        #expect(project.cropAspectRatio == 0.0)
        #expect(project.cropRotation90 == 0)
        #expect(project.cropFlipHorizontal == false)
        #expect(project.cropFlipVertical == false)
        #expect(project.noiseReductionIntensity == 0.5)
        #expect(project.noiseReductionEnabled == false)
        #expect(project.playbackSpeed == 1.0)
        #expect(project.textOverlays.isEmpty)
        #expect(project.stickerOverlays.isEmpty)
    }

    @Test("Computed durationSeconds")
    func durationSeconds() {
        let project = makeProject()
        #expect(project.durationSeconds == 10.0)
    }

    @Test("Computed clipCount")
    func clipCount() {
        let project = makeProject()
        #expect(project.clipCount == 0)
    }

    @Test("Formatted duration")
    func formattedDuration() {
        let project = Project(
            name: "Test",
            sourceVideoPath: "v.mov",
            durationMicros: 90_000_000 // 1m 30s
        )
        #expect(project.formattedDuration == "1:30")
    }

    @Test("Formatted duration with hours")
    func formattedDurationHours() {
        let project = Project(
            name: "Test",
            sourceVideoPath: "v.mov",
            durationMicros: 3661_000_000 // 1h 1m 1s
        )
        #expect(project.formattedDuration == "1:01:01")
    }

    @Test("with() copy preserves fields")
    func withCopy() {
        let original = makeProject()
        let modified = original.with(name: "Updated Name", playbackSpeed: 2.0)
        #expect(modified.name == "Updated Name")
        #expect(modified.playbackSpeed == 2.0)
        #expect(modified.id == "proj-1")
        #expect(modified.sourceVideoPath == "Videos/test.mov")
    }

    @Test("with() clear flags")
    func withClearFlags() {
        let project = Project(
            name: "Test",
            sourceVideoPath: "v.mov",
            outPointMicros: 5_000_000,
            thumbnailPath: "thumb.jpg"
        )
        let cleared = project.with(clearOutPointMicros: true, clearThumbnailPath: true)
        #expect(cleared.outPointMicros == nil)
        #expect(cleared.thumbnailPath == nil)
    }

    @Test("Equatable by id only")
    func equatable() {
        let a = makeProject(id: "same-id", name: "Name A")
        let b = makeProject(id: "same-id", name: "Name B")
        #expect(a == b)
    }

    @Test("Equatable different ids")
    func equatableDifferent() {
        let a = makeProject(id: "id-1")
        let b = makeProject(id: "id-2")
        #expect(a != b)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = Project(
            id: "proj-1",
            name: "My Video",
            sourceVideoPath: "Videos/test.mov",
            frameRate: .fixed30,
            durationMicros: 5_000_000,
            version: 2,
            cropRotation90: 1,
            cropFlipHorizontal: true,
            playbackSpeed: 0.5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        #expect(decoded == original)
        #expect(decoded.name == "My Video")
        #expect(decoded.frameRate == .fixed30)
        #expect(decoded.cropRotation90 == 1)
        #expect(decoded.cropFlipHorizontal == true)
        #expect(decoded.playbackSpeed == 0.5)
    }

    @Test("Identifiable id property")
    func identifiable() {
        let project = makeProject(id: "unique-id")
        #expect(project.id == "unique-id")
    }
}

// MARK: - BackupManifest Tests

@Suite("BackupManifest Tests")
struct BackupManifestTests {

    func makeManifest() -> BackupManifest {
        BackupManifest(
            version: 1,
            appVersion: "1.2.3",
            appBuildNumber: 42,
            backupDate: Date(timeIntervalSince1970: 1700000000),
            deviceModel: "iPhone 15 Pro",
            iosVersion: "18.0",
            projectId: "proj-1",
            projectName: "My Project",
            projectVersion: 2,
            mediaFiles: [],
            totalSize: 1_048_576,
            includesMedia: true
        )
    }

    @Test("Creation")
    func creation() {
        let manifest = makeManifest()
        #expect(manifest.version == 1)
        #expect(manifest.appVersion == "1.2.3")
        #expect(manifest.projectId == "proj-1")
        #expect(manifest.projectName == "My Project")
        #expect(manifest.includesMedia == true)
    }

    @Test("Formatted total size")
    func formattedTotalSize() {
        let manifest = makeManifest()
        #expect(manifest.formattedTotalSize == "1.0 MB")
    }

    @Test("Media file count")
    func mediaFileCount() {
        let manifest = makeManifest()
        #expect(manifest.mediaFileCount == 0)
    }

    @Test("isNewerVersion detects newer app")
    func isNewerVersion() {
        let manifest = makeManifest()
        #expect(manifest.isNewerVersion(currentAppVersion: "1.2.2") == true)
        #expect(manifest.isNewerVersion(currentAppVersion: "1.2.3") == false)
        #expect(manifest.isNewerVersion(currentAppVersion: "1.2.4") == false)
        #expect(manifest.isNewerVersion(currentAppVersion: "1.1.0") == true)
        #expect(manifest.isNewerVersion(currentAppVersion: "2.0.0") == false)
    }

    @Test("BackupMediaEntry formatBytes")
    func formatBytes() {
        #expect(BackupMediaEntry.formatBytes(500) == "500 B")
        #expect(BackupMediaEntry.formatBytes(1536) == "1.5 KB")
        #expect(BackupMediaEntry.formatBytes(1_572_864) == "1.5 MB")
        #expect(BackupMediaEntry.formatBytes(1_610_612_736) == "1.5 GB")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let entry = BackupMediaEntry(
            originalPath: "Videos/clip.mov",
            archivePath: "media/clip.mov",
            contentHash: "abc123",
            fileSize: 1024,
            mediaType: "video"
        )
        let original = BackupManifest(
            version: 1,
            appVersion: "1.0.0",
            appBuildNumber: 1,
            backupDate: Date(timeIntervalSince1970: 1700000000),
            deviceModel: "iPhone 15",
            iosVersion: "18.0",
            projectId: "p-1",
            projectName: "Project",
            projectVersion: 2,
            mediaFiles: [entry],
            totalSize: 2048,
            includesMedia: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackupManifest.self, from: data)
        #expect(decoded == original)
        #expect(decoded.mediaFiles.count == 1)
    }
}

// MARK: - BackupValidationResult Tests

@Suite("BackupValidationResult Tests")
struct BackupValidationResultTests {

    @Test("Valid result")
    func valid() {
        let manifest = BackupManifest(
            version: 1, appVersion: "1.0", appBuildNumber: 1,
            backupDate: Date(), deviceModel: "iPhone", iosVersion: "18",
            projectId: "p", projectName: "P", projectVersion: 2,
            mediaFiles: [], totalSize: 0, includesMedia: false
        )
        let result = BackupValidationResult.valid(manifest)
        #expect(result.isValid == true)
        #expect(result.manifest != nil)
        #expect(result.warning == nil)
        #expect(result.error == nil)
    }

    @Test("Valid with warning")
    func validWithWarning() {
        let manifest = BackupManifest(
            version: 1, appVersion: "1.0", appBuildNumber: 1,
            backupDate: Date(), deviceModel: "iPhone", iosVersion: "18",
            projectId: "p", projectName: "P", projectVersion: 2,
            mediaFiles: [], totalSize: 0, includesMedia: false
        )
        let result = BackupValidationResult.validWithWarning(manifest, warning: "Newer version")
        #expect(result.isValid == true)
        #expect(result.warning == "Newer version")
    }

    @Test("Invalid result")
    func invalid() {
        let result = BackupValidationResult.invalid("Corrupt archive")
        #expect(result.isValid == false)
        #expect(result.manifest == nil)
        #expect(result.error == "Corrupt archive")
    }
}

// MARK: - StorageUsage Tests

@Suite("StorageUsage Tests")
struct StorageUsageTests {

    @Test("Total bytes computed correctly")
    func totalBytes() {
        let usage = StorageUsage(
            projectFilesBytes: 100,
            videoFilesBytes: 200,
            peopleLibraryBytes: 50,
            thumbnailsBytes: 30,
            appCacheBytes: 20,
            otherBytes: 10,
            perProjectUsage: [],
            calculatedAt: Date()
        )
        #expect(usage.totalBytes == 410)
    }

    @Test("ProjectStorageUsage total bytes")
    func projectStorageTotal() {
        let psu = ProjectStorageUsage(
            projectId: "p",
            projectName: "Project",
            projectFileBytes: 100,
            mediaBytes: 500,
            thumbnailBytes: 50
        )
        #expect(psu.totalBytes == 650)
    }

    @Test("Sorted by size")
    func sortedBySize() {
        let small = ProjectStorageUsage(projectId: "s", projectName: "Small", projectFileBytes: 10, mediaBytes: 10, thumbnailBytes: 10)
        let large = ProjectStorageUsage(projectId: "l", projectName: "Large", projectFileBytes: 1000, mediaBytes: 1000, thumbnailBytes: 1000)
        let usage = StorageUsage(
            projectFilesBytes: 0, videoFilesBytes: 0, peopleLibraryBytes: 0,
            thumbnailsBytes: 0, appCacheBytes: 0, otherBytes: 0,
            perProjectUsage: [small, large],
            calculatedAt: Date()
        )
        let sorted = usage.sortedBySize
        #expect(sorted.first?.projectId == "l")
    }
}

// MARK: - SyncStatus Tests

@Suite("SyncStatus Tests")
struct SyncStatusTests {

    @Test("All cases")
    func allCases() {
        #expect(SyncStatus.allCases.count == 7)
    }

    @Test("Display names")
    func displayNames() {
        #expect(SyncStatus.local.displayName == "Local only")
        #expect(SyncStatus.synced.displayName == "Synced")
        #expect(SyncStatus.syncing.displayName == "Syncing...")
    }

    @Test("isActive for active states")
    func isActive() {
        #expect(SyncStatus.syncing.isActive == true)
        #expect(SyncStatus.pendingUpload.isActive == true)
        #expect(SyncStatus.pendingDownload.isActive == true)
        #expect(SyncStatus.synced.isActive == false)
        #expect(SyncStatus.local.isActive == false)
        #expect(SyncStatus.error.isActive == false)
    }
}

// MARK: - SyncOperation Tests

@Suite("SyncOperation Tests")
struct SyncOperationTests {

    @Test("Creation and defaults")
    func creation() {
        let op = SyncOperation(
            id: "op-1",
            type: .upload,
            projectId: "proj-1",
            queuedAt: Date()
        )
        #expect(op.retryCount == 0)
        #expect(op.error == nil)
        #expect(op.canRetry == true)
    }

    @Test("canRetry returns false at max retries")
    func canRetryMax() {
        let op = SyncOperation(
            id: "op-1",
            type: .upload,
            projectId: "proj-1",
            queuedAt: Date(),
            retryCount: 5
        )
        #expect(op.canRetry == false)
    }

    @Test("withRetry increments count")
    func withRetry() {
        let op = SyncOperation(id: "op-1", type: .download, projectId: "p", queuedAt: Date())
        let retried = op.withRetry(errorMessage: "Network error")
        #expect(retried.retryCount == 1)
        #expect(retried.error == "Network error")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = SyncOperation(
            id: "op-1",
            type: .delete,
            projectId: "proj-1",
            queuedAt: Date(timeIntervalSince1970: 1700000000),
            retryCount: 2,
            error: "Failed"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncOperation.self, from: data)
        #expect(decoded == original)
        #expect(decoded.retryCount == 2)
        #expect(decoded.error == "Failed")
    }
}
