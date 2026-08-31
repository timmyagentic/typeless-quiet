import Foundation
import XCTest
@testable import TypelessQuietApp
@testable import TypelessQuietCore

private final class MigrationDirectoryStore: AccountDirectoryStoring, @unchecked Sendable {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("accounts.json")
    var stored: AccountDirectory
    var saveCallCount = 0
    var failingSaveCalls = Set<Int>()

    init(stored: AccountDirectory) { self.stored = stored }
    func load() throws -> AccountDirectory { stored }
    func save(_ directory: AccountDirectory) throws {
        saveCallCount += 1
        if failingSaveCalls.contains(saveCallCount) { throw MigrationTestError.injected }
        stored = directory
    }
}

private final class MigrationGuardStore: QuotaGuardStoring, @unchecked Sendable {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("quota-guard.json")
    var stored: QuotaGuardDocument
    var saveCallCount = 0
    var failingSaveCalls = Set<Int>()

    init(stored: QuotaGuardDocument) { self.stored = stored }
    func load() throws -> QuotaGuardDocument { stored }
    func save(_ document: QuotaGuardDocument) throws {
        saveCallCount += 1
        if failingSaveCalls.contains(saveCallCount) { throw MigrationTestError.injected }
        stored = document
    }
}

private final class MigrationSecretStore: AccountSecretStoring, @unchecked Sendable {
    var values: [UUID: String] = [:]
    func containsSecret(accountID: UUID) throws -> Bool { values[accountID] != nil }
    func readSecret(accountID: UUID) throws -> String? { values[accountID] }
    func saveSecret(_ secret: String, accountID: UUID) throws { values[accountID] = secret }
    func deleteSecret(accountID: UUID) throws { values.removeValue(forKey: accountID) }
}

private final class MigrationReader: TypelessCurrentStateReading {
    var result: TypelessStateReadResult
    init(result: TypelessStateReadResult) { self.result = result }
    func read() throws -> TypelessStateReadResult { result }
}

@MainActor
private final class MigrationLoginOpener: OfficialTypelessLoginOpening {
    let loginURL = OfficialTypelessLoginOpener.defaultLoginURL
    var openCount = 0
    func openLogin() -> Bool { openCount += 1; return true }
}

private final class MigrationAuditStore: SwitchAuditStoring, @unchecked Sendable {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audit.json")
    var log = SwitchAuditLog()
    func load() throws -> SwitchAuditLog { log }
    func append(_ event: SwitchAuditEvent) throws -> SwitchAuditLog {
        log.events.append(event)
        return log
    }
}

private enum MigrationTestError: Error {
    case injected
}

@MainActor
final class BackupControllerTests: XCTestCase {
    private let migrationDate = Date(timeIntervalSince1970: 70_000)

    func testExportFileIsPrivateAndContainsNoLocalSecretState() throws {
        let fixture = try makeFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("backup.json")

        try fixture.controller.export(to: fileURL, exportedAt: migrationDate)

        let data = try Data(contentsOf: fileURL)
        let backup = try PortableBackupCodec.decode(data)
        let serialized = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(backup.accounts.count, 1)
        XCTAssertFalse(backup.security.secretsIncluded)
        XCTAssertFalse(backup.security.deviceIdentityIncluded)
        XCTAssertTrue(backup.security.requiresOfficialReauthentication)
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
        XCTAssertFalse(serialized.contains("hasSecret"))
        XCTAssertFalse(serialized.contains("usedCharacters"))
        XCTAssertFalse(serialized.contains("consecutiveFailures"))
        XCTAssertFalse(serialized.lowercased().contains("secret-value"))
    }

    func testImportMergesAndForcesGuardDisabledWithoutTouchingKeychain() throws {
        let fixture = try makeFixture()
        let backup = try makeBackup(
            existingSourceID: UUID(),
            includeNewAccount: true
        )

        let preview = try fixture.controller.importData(
            try PortableBackupCodec.encode(backup),
            now: migrationDate
        )

        XCTAssertEqual(preview.accountCount, 2)
        XCTAssertEqual(preview.addedCount, 1)
        XCTAssertEqual(preview.updatedCount, 1)
        let existing = try XCTUnwrap(
            fixture.manager.directory.account(matchingEmail: "existing@example.test")
        )
        let imported = try XCTUnwrap(
            fixture.manager.directory.account(matchingEmail: "new@example.test")
        )
        XCTAssertEqual(existing.id, fixture.existing.id)
        XCTAssertTrue(existing.hasSecret)
        XCTAssertEqual(fixture.secretStore.values[existing.id], "secret-value")
        XCTAssertEqual(imported.status, .unknown)
        XCTAssertNil(imported.quota)
        XCTAssertFalse(imported.hasSecret)
        XCTAssertFalse(fixture.guardController.configuration.isEnabled)
        XCTAssertEqual(fixture.guardController.runtime, QuotaGuardRuntime())
    }

    func testGuardStoreFailureRollsBackBothModels() throws {
        let fixture = try makeFixture()
        let originalDirectory = fixture.manager.directory
        let originalGuard = fixture.guardController.document
        fixture.guardStore.failingSaveCalls = [1]
        let backup = try makeBackup(existingSourceID: UUID(), includeNewAccount: true)

        XCTAssertThrowsError(try fixture.controller.importData(
            try PortableBackupCodec.encode(backup),
            now: migrationDate
        ))

        XCTAssertEqual(fixture.manager.directory, originalDirectory)
        XCTAssertEqual(fixture.directoryStore.stored, originalDirectory)
        XCTAssertEqual(fixture.guardController.document, originalGuard)
        XCTAssertEqual(fixture.guardStore.stored, originalGuard)
    }

    func testRollbackFailureIsSurfacedExplicitly() throws {
        let fixture = try makeFixture()
        fixture.directoryStore.failingSaveCalls = [2]
        fixture.guardStore.failingSaveCalls = [1, 2]
        let backup = try makeBackup(existingSourceID: UUID(), includeNewAccount: true)

        XCTAssertThrowsError(try fixture.controller.importData(
            try PortableBackupCodec.encode(backup),
            now: migrationDate
        )) {
            guard let controllerError = $0 as? BackupControllerError,
                  case .importAndRollbackFailed = controllerError
            else {
                return XCTFail("Expected explicit rollback failure, got \($0)")
            }
        }
    }

    func testPreviewDoesNotMutateLocalState() throws {
        let fixture = try makeFixture()
        let beforeDirectory = fixture.manager.directory
        let beforeGuard = fixture.guardController.document
        let backup = try makeBackup(existingSourceID: UUID(), includeNewAccount: true)

        let preview = try fixture.controller.previewImport(
            try PortableBackupCodec.encode(backup)
        )

        XCTAssertEqual(preview.addedCount, 1)
        XCTAssertEqual(fixture.manager.directory, beforeDirectory)
        XCTAssertEqual(fixture.guardController.document, beforeGuard)
        XCTAssertEqual(fixture.directoryStore.saveCallCount, 0)
        XCTAssertEqual(fixture.guardStore.saveCallCount, 0)
    }

    func testImportIsBlockedWhileSwitchIsInProgress() throws {
        let fixture = try makeFixture(includeTarget: true)
        let target = try XCTUnwrap(
            fixture.manager.accounts.first { $0.email == "target@example.test" }
        )
        fixture.switchCoordinator.startSwitch(to: target.id)
        XCTAssertTrue(fixture.switchCoordinator.isBusy)
        let backup = try makeBackup(existingSourceID: UUID(), includeNewAccount: true)

        XCTAssertThrowsError(try fixture.controller.importData(
            try PortableBackupCodec.encode(backup)
        )) {
            XCTAssertEqual($0 as? BackupControllerError, .switchInProgress)
        }
    }

    func testFreshOfficialLoginMarksImportedUnknownAccountAvailable() throws {
        let fixture = try makeFixture()
        let backup = try makeBackup(existingSourceID: UUID(), includeNewAccount: true)
        _ = try fixture.controller.importData(
            try PortableBackupCodec.encode(backup),
            now: Date()
        )
        let imported = try XCTUnwrap(
            fixture.manager.directory.account(matchingEmail: "new@example.test")
        )
        let observedAt = Date()
        fixture.reader.result = makeResult(
            email: imported.email,
            observedAt: observedAt,
            remaining: 5_000
        )

        fixture.controller.refreshReauthenticationStatus()

        XCTAssertEqual(
            fixture.manager.directory.account(matchingEmail: imported.email)?.status,
            .available
        )
        XCTAssertTrue(fixture.controller.accountsRequiringOfficialLogin.isEmpty)
    }

    func testOfficialLoginButtonUsesFixedP2Opener() throws {
        let fixture = try makeFixture()
        XCTAssertTrue(fixture.controller.openOfficialLogin())
        XCTAssertEqual(fixture.loginOpener.openCount, 1)
        XCTAssertEqual(
            fixture.controller.officialLoginURL,
            OfficialTypelessLoginOpener.defaultLoginURL
        )
    }

    func testBackupUIFixturesAreValidAndSecretFree() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = testsDirectory.appendingPathComponent("Fixtures/typeless-backup-qa")
        let backupData = try Data(contentsOf: root.appendingPathComponent("backup.json"))
        let backup = try PortableBackupCodec.decode(backupData)
        let accounts = try AccountDirectoryStore(
            fileURL: root.appendingPathComponent("accounts-after-import.json")
        ).load()
        let guardDocument = try QuotaGuardStore(
            fileURL: root.appendingPathComponent("quota-guard-after-import.json")
        ).load()
        let serialized = String(decoding: backupData, as: UTF8.self)

        XCTAssertEqual(backup.accounts.count, 1)
        XCTAssertEqual(accounts.accounts.first?.status, .unknown)
        XCTAssertFalse(guardDocument.configuration.isEnabled)
        XCTAssertFalse(serialized.contains("hasSecret"))
        XCTAssertFalse(serialized.contains("usedCharacters"))
        XCTAssertFalse(serialized.contains("consecutiveFailures"))
    }

    private func makeFixture(includeTarget: Bool = false) throws -> Fixture {
        let currentDate = Date()
        var existing = try AccountProfile(
            displayName: "Existing",
            email: "existing@example.test",
            status: .available,
            quota: QuotaSnapshot(
                usedCharacters: 100,
                limitCharacters: 8_000,
                observedAt: currentDate,
                source: .typelessAccessibility
            ),
            hasSecret: true
        )
        existing.updatedAt = currentDate
        var accounts = [existing]
        if includeTarget {
            accounts.append(try AccountProfile(
                displayName: "Target",
                email: "target@example.test",
                status: .available
            ))
        }
        let directory = try AccountDirectory(accounts: accounts)
        let directoryStore = MigrationDirectoryStore(stored: directory)
        let secretStore = MigrationSecretStore()
        secretStore.values[existing.id] = "secret-value"
        let reader = MigrationReader(result: makeResult(
            email: existing.email,
            observedAt: currentDate,
            remaining: 7_900
        ))
        let manager = AccountManager(
            directoryStore: directoryStore,
            secretStore: secretStore,
            stateReader: reader
        )
        let loginOpener = MigrationLoginOpener()
        let switchCoordinator = SwitchCoordinator(
            accountManager: manager,
            loginOpener: loginOpener,
            auditStore: MigrationAuditStore(),
            backgroundVerificationEnabled: false
        )
        let guardDocument = QuotaGuardDocument(
            configuration: QuotaGuardConfiguration(
                isEnabled: true,
                thresholdCharacters: 600,
                accountPool: accounts.map(\.id),
                cooldownMinutes: 45
            ),
            runtime: QuotaGuardRuntime(consecutiveFailures: 2)
        )
        let guardStore = MigrationGuardStore(stored: guardDocument)
        let guardController = QuotaGuardController(
            accountManager: manager,
            switchCoordinator: switchCoordinator,
            store: guardStore,
            timerEnabled: false
        )
        let controller = BackupController(
            accountManager: manager,
            quotaGuardController: guardController,
            switchCoordinator: switchCoordinator,
            loginOpener: loginOpener,
            appVersion: { "0.2.0" }
        )
        directoryStore.saveCallCount = 0
        guardStore.saveCallCount = 0
        return Fixture(
            existing: existing,
            directoryStore: directoryStore,
            secretStore: secretStore,
            reader: reader,
            manager: manager,
            loginOpener: loginOpener,
            switchCoordinator: switchCoordinator,
            guardStore: guardStore,
            guardController: guardController,
            controller: controller
        )
    }

    private func makeBackup(
        existingSourceID: UUID,
        includeNewAccount: Bool
    ) throws -> PortableBackup {
        var accounts = [PortableAccount(
            sourceID: existingSourceID,
            displayName: "Imported Existing",
            email: "existing@example.test",
            note: "Imported",
            createdAt: migrationDate
        )]
        if includeNewAccount {
            accounts.append(PortableAccount(
                sourceID: UUID(),
                displayName: "New",
                email: "new@example.test",
                note: "",
                createdAt: migrationDate
            ))
        }
        return PortableBackup(
            exportedAt: migrationDate,
            appVersion: "0.2.0",
            accounts: accounts,
            quotaGuard: PortableQuotaGuard(
                wasEnabled: true,
                thresholdCharacters: 700,
                accountPool: accounts.map(\.sourceID),
                cooldownMinutes: 60
            )
        )
    }

    private func makeResult(
        email: String,
        observedAt: Date,
        remaining: Int
    ) -> TypelessStateReadResult {
        TypelessStateReadResult(
            state: CurrentTypelessState(
                email: email,
                displayName: email,
                planName: "Free",
                quota: QuotaSnapshot(
                    usedCharacters: 8_000 - remaining,
                    limitCharacters: 8_000,
                    observedAt: observedAt,
                    source: .typelessAccessibility
                ),
                observedAt: observedAt,
                sourceModifiedAt: observedAt,
                activity: .idle
            ),
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("app-storage.json"),
            appVersion: "2.4.0",
            appRunning: true
        )
    }

    private struct Fixture {
        let existing: AccountProfile
        let directoryStore: MigrationDirectoryStore
        let secretStore: MigrationSecretStore
        let reader: MigrationReader
        let manager: AccountManager
        let loginOpener: MigrationLoginOpener
        let switchCoordinator: SwitchCoordinator
        let guardStore: MigrationGuardStore
        let guardController: QuotaGuardController
        let controller: BackupController
    }
}
