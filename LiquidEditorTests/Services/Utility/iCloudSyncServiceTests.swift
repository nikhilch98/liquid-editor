import Testing
import Foundation
@testable import LiquidEditor

@Suite("iCloudSyncService Tests")
struct ICloudSyncServiceTests {

    // MARK: - ICloudSyncStatus

    @Suite("ICloudSyncStatus")
    struct ICloudSyncStatusTests {

        @Test("allCases contains 8 statuses")
        func allCasesCount() {
            #expect(ICloudSyncStatus.allCases.count == 8)
        }

        @Test("Each status has a unique rawValue")
        func uniqueRawValues() {
            let rawValues = Set(ICloudSyncStatus.allCases.map(\.rawValue))
            #expect(rawValues.count == ICloudSyncStatus.allCases.count)
        }

        @Test("Codable roundtrip preserves value")
        func codableRoundtrip() throws {
            for status in ICloudSyncStatus.allCases {
                let data = try JSONEncoder().encode(status)
                let decoded = try JSONDecoder().decode(ICloudSyncStatus.self, from: data)
                #expect(decoded == status)
            }
        }
    }

    // MARK: - ConflictResolution

    @Suite("ConflictResolution")
    struct ConflictResolutionTests {

        @Test("allCases contains 4 strategies")
        func allCasesCount() {
            #expect(ConflictResolution.allCases.count == 4)
        }

        @Test("Contains expected strategies")
        func expectedStrategies() {
            let cases = ConflictResolution.allCases
            #expect(cases.contains(.keepLocal))
            #expect(cases.contains(.keepRemote))
            #expect(cases.contains(.keepBoth))
            #expect(cases.contains(.merge))
        }

        @Test("Codable roundtrip preserves value")
        func codableRoundtrip() throws {
            for resolution in ConflictResolution.allCases {
                let data = try JSONEncoder().encode(resolution)
                let decoded = try JSONDecoder().decode(ConflictResolution.self, from: data)
                #expect(decoded == resolution)
            }
        }
    }

    // MARK: - SyncConflict

    @Suite("SyncConflict")
    struct ConflictTests {

        @Test("Properties are stored correctly")
        func properties() {
            let localDate = Date(timeIntervalSince1970: 1000)
            let remoteDate = Date(timeIntervalSince1970: 2000)
            let conflict = SyncConflict(
                projectId: "proj-1",
                projectName: "My Project",
                localModifiedAt: localDate,
                remoteModifiedAt: remoteDate,
                localSize: 5000,
                remoteSize: 6000
            )
            #expect(conflict.projectId == "proj-1")
            #expect(conflict.projectName == "My Project")
            #expect(conflict.localModifiedAt == localDate)
            #expect(conflict.remoteModifiedAt == remoteDate)
            #expect(conflict.localSize == 5000)
            #expect(conflict.remoteSize == 6000)
        }

        @Test("Equatable works correctly")
        func equality() {
            let date = Date()
            let a = SyncConflict(
                projectId: "p1",
                projectName: "P1",
                localModifiedAt: date,
                remoteModifiedAt: date,
                localSize: 100,
                remoteSize: 200
            )
            let b = SyncConflict(
                projectId: "p1",
                projectName: "P1",
                localModifiedAt: date,
                remoteModifiedAt: date,
                localSize: 100,
                remoteSize: 200
            )
            #expect(a == b)
        }
    }

    // MARK: - SyncResult

    @Suite("SyncResult")
    struct ResultTests {

        @Test("success factory creates successful result")
        func successFactory() {
            let result = SyncResult.success(syncedCount: 3, conflictCount: 1)
            #expect(result.success == true)
            #expect(result.error == nil)
            #expect(result.syncedCount == 3)
            #expect(result.conflictCount == 1)
        }

        @Test("failure factory creates failed result")
        func failureFactory() {
            let result = SyncResult.failure("Test error")
            #expect(result.success == false)
            #expect(result.error == "Test error")
            #expect(result.syncedCount == 0)
            #expect(result.conflictCount == 0)
        }

        @Test("unavailable result is a failure with descriptive error")
        func unavailableResult() {
            let result = SyncResult.unavailable
            #expect(result.success == false)
            #expect(result.error != nil)
            #expect(result.error!.contains("iCloud"))
        }
    }

    // MARK: - ICloudSyncServiceStub

    @Suite("Stub Implementation")
    struct StubTests {

        @Test("isAvailable returns false")
        func isAvailable() async {
            let stub = ICloudSyncServiceStub.shared
            let available = await stub.isAvailable()
            #expect(available == false)
        }

        @Test("getSyncStatus returns unavailable")
        func syncStatus() async {
            let stub = ICloudSyncServiceStub.shared
            let status = await stub.getSyncStatus(projectId: "any")
            #expect(status == .unavailable)
        }

        @Test("getAllSyncStatuses returns empty dictionary")
        func allStatuses() async {
            let stub = ICloudSyncServiceStub.shared
            let statuses = await stub.getAllSyncStatuses()
            #expect(statuses.isEmpty)
        }

        @Test("syncProject returns unavailable")
        func syncProject() async {
            let stub = ICloudSyncServiceStub.shared
            let result = await stub.syncProject(projectId: "any")
            #expect(result == .unavailable)
        }

        @Test("syncAll returns unavailable")
        func syncAll() async {
            let stub = ICloudSyncServiceStub.shared
            let result = await stub.syncAll()
            #expect(result == .unavailable)
        }

        @Test("downloadProject returns unavailable")
        func downloadProject() async {
            let stub = ICloudSyncServiceStub.shared
            let result = await stub.downloadProject(projectId: "any")
            #expect(result == .unavailable)
        }

        @Test("resolveConflict returns unavailable")
        func resolveConflict() async {
            let stub = ICloudSyncServiceStub.shared
            let result = await stub.resolveConflict(projectId: "any", resolution: .keepLocal)
            #expect(result == .unavailable)
        }

        @Test("getConflicts returns empty array")
        func getConflicts() async {
            let stub = ICloudSyncServiceStub.shared
            let conflicts = await stub.getConflicts()
            #expect(conflicts.isEmpty)
        }

        @Test("isAutoSyncEnabled returns false")
        func autoSync() async {
            let stub = ICloudSyncServiceStub.shared
            let enabled = await stub.isAutoSyncEnabled()
            #expect(enabled == false)
        }

        @Test("setAutoSyncEnabled does not throw")
        func setAutoSync() async {
            let stub = ICloudSyncServiceStub.shared
            await stub.setAutoSyncEnabled(true)
            // Should not crash
            let enabled = await stub.isAutoSyncEnabled()
            #expect(enabled == false) // Still false, stub ignores it
        }

        @Test("lastSyncTime returns nil")
        func lastSyncTime() async {
            let stub = ICloudSyncServiceStub.shared
            let time = await stub.lastSyncTime()
            #expect(time == nil)
        }

        @Test("forceFullSync returns unavailable")
        func forceFullSync() async {
            let stub = ICloudSyncServiceStub.shared
            let result = await stub.forceFullSync()
            #expect(result == .unavailable)
        }

        @Test("removeFromCloud returns unavailable")
        func removeFromCloud() async {
            let stub = ICloudSyncServiceStub.shared
            let result = await stub.removeFromCloud(projectId: "any")
            #expect(result == .unavailable)
        }

        @Test("Shared singleton is consistent")
        func singleton() {
            let a = ICloudSyncServiceStub.shared
            let b = ICloudSyncServiceStub.shared
            #expect(a === b)
        }
    }
}
