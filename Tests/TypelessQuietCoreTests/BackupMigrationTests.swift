import XCTest
@testable import TypelessQuietCore

final class BackupMigrationTests: XCTestCase {
    private let exportedAt = Date(timeIntervalSince1970: 60_000)

    func testExportUsesDedicatedSecretFreeSchema() throws {
        let fixture = try makeExportFixture()

        let backup = try PortableBackupCodec.makeBackup(
            directory: fixture.directory,
            quotaGuard: fixture.guardConfiguration,
            appVersion: "0.2.0",
            exportedAt: exportedAt
        )
        let data = try PortableBackupCodec.encode(backup)
        let serialized = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(backup.format, "typeless-plusplus-backup")
        XCTAssertEqual(backup.schemaVersion, 1)
        XCTAssertFalse(backup.security.secretsIncluded)
        XCTAssertFalse(backup.security.deviceIdentityIncluded)
        XCTAssertTrue(backup.security.requiresOfficialReauthentication)
        XCTAssertTrue(backup.quotaGuard.wasEnabled)
        XCTAssertFalse(serialized.contains("hasSecret"))
        XCTAssertFalse(serialized.contains("usedCharacters"))
        XCTAssertFalse(serialized.contains("limitCharacters"))
        XCTAssertFalse(serialized.contains("lastAttemptAt"))
        XCTAssertFalse(serialized.contains("activeTransactionID"))
        XCTAssertFalse(serialized.lowercased().contains("access_token"))
        XCTAssertFalse(serialized.lowercased().contains("refresh_token"))
        XCTAssertFalse(serialized.lowercased().contains("password"))
        XCTAssertFalse(serialized.lowercased().contains("cookie"))
        XCTAssertFalse(serialized.contains("deviceIdentifier"))
    }

    func testBackupRoundTripsWithISO8601Dates() throws {
        let fixture = try makeExportFixture()
        let backup = try PortableBackupCodec.makeBackup(
            directory: fixture.directory,
            quotaGuard: fixture.guardConfiguration,
            appVersion: "0.2.0",
            exportedAt: exportedAt
        )

        let encoded = try PortableBackupCodec.encode(backup)
        let decoded = try PortableBackupCodec.decode(encoded)
        let serialized = String(decoding: encoded, as: UTF8.self)

        XCTAssertEqual(decoded, backup)
        XCTAssertTrue(serialized.contains("1970-01-01T16:40:00Z"))
    }

    func testDecodeRejectsWrongFormatSchemaSecurityAndOversize() throws {
        var backup = try makePortableBackup()
        backup.format = "other-format"
        XCTAssertThrowsBackup(.invalidFormat, backup)

        backup = try makePortableBackup()
        backup.schemaVersion = 2
        XCTAssertThrowsBackup(.unsupportedSchema, backup)

        backup = try makePortableBackup()
        backup.security.secretsIncluded = true
        XCTAssertThrowsBackup(.unsafeSecurityManifest, backup)

        let oversized = Data(repeating: 0, count: PortableBackupCodec.maximumByteCount + 1)
        XCTAssertThrowsError(try PortableBackupCodec.decode(oversized)) {
            XCTAssertEqual($0 as? PortableBackupError, .fileTooLarge)
        }
    }

    func testDecodeRejectsDuplicateEmailIDAndDanglingPoolReference() throws {
        var backup = try makePortableBackup()
        backup.accounts.append(PortableAccount(
            sourceID: UUID(),
            displayName: "Duplicate",
            email: "USER@EXAMPLE.TEST",
            note: "",
            createdAt: exportedAt
        ))
        XCTAssertThrowsBackup(.duplicateEmail, backup)

        backup = try makePortableBackup()
        backup.accounts.append(PortableAccount(
            sourceID: backup.accounts[0].sourceID,
            displayName: "Other",
            email: "other@example.test",
            note: "",
            createdAt: exportedAt
        ))
        XCTAssertThrowsBackup(.duplicateAccountID, backup)

        backup = try makePortableBackup()
        backup.quotaGuard.accountPool.append(UUID())
        XCTAssertThrowsBackup(.invalidPoolReference, backup)
    }

    func testDecodeRejectsForbiddenLocalStateFieldsEvenWhenDecoderWouldIgnoreThem() throws {
        let backup = try makePortableBackup()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(backup)) as? [String: Any]
        )
        object["password"] = "should-never-be-imported"
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try PortableBackupCodec.decode(data)) {
            XCTAssertEqual($0 as? PortableBackupError, .forbiddenField)
        }
    }

    func testDecodeRejectsTooManyAccountsAndOversizedStrings() throws {
        var backup = try makePortableBackup()
        let template = backup.accounts[0]
        backup.accounts = (0 ... PortableBackupCodec.maximumAccountCount).map { index in
            PortableAccount(
                sourceID: UUID(),
                displayName: "User \(index)",
                email: "user\(index)@example.test",
                note: "",
                createdAt: template.createdAt
            )
        }
        XCTAssertThrowsBackup(.tooManyAccounts, backup)

        backup = try makePortableBackup()
        backup.accounts[0].note = String(repeating: "x", count: 4_097)
        XCTAssertThrowsBackup(.invalidAccount, backup)
    }

    func testMergePreservesLocalIdentitySecretQuotaAndStatusForMatchingEmail() throws {
        let sourceID = UUID()
        let quota = QuotaSnapshot(
            usedCharacters: 100,
            limitCharacters: 8_000,
            observedAt: exportedAt,
            source: .typelessAccessibility
        )
        let existing = try AccountProfile(
            displayName: "Local Name",
            email: "user@example.test",
            note: "Local note",
            status: .available,
            autoSwitchEligible: true,
            quota: quota,
            hasSecret: true,
            createdAt: exportedAt.addingTimeInterval(-500),
            updatedAt: exportedAt.addingTimeInterval(-100)
        )
        let backup = PortableBackup(
            exportedAt: exportedAt,
            appVersion: "0.2.0",
            accounts: [PortableAccount(
                sourceID: sourceID,
                displayName: "Imported Name",
                email: "USER@example.test",
                note: "Imported note",
                createdAt: exportedAt.addingTimeInterval(-1_000)
            )],
            quotaGuard: PortableQuotaGuard(
                wasEnabled: true,
                thresholdCharacters: 600,
                accountPool: [sourceID],
                cooldownMinutes: 45
            )
        )

        let plan = try BackupMigrationPlanner.plan(
            backup: backup,
            existing: try AccountDirectory(accounts: [existing]),
            now: exportedAt.addingTimeInterval(10),
            generateID: UUID.init
        )
        let merged = try XCTUnwrap(plan.directory.account(matchingEmail: existing.email))

        XCTAssertEqual(merged.id, existing.id)
        XCTAssertEqual(merged.displayName, "Imported Name")
        XCTAssertEqual(merged.note, "Imported note")
        XCTAssertEqual(merged.status, .available)
        XCTAssertTrue(merged.autoSwitchEligible)
        XCTAssertEqual(merged.quota, quota)
        XCTAssertTrue(merged.hasSecret)
        XCTAssertEqual(merged.createdAt, existing.createdAt)
        XCTAssertEqual(plan.addedCount, 0)
        XCTAssertEqual(plan.updatedCount, 1)
        XCTAssertTrue(plan.requiresOfficialReauthentication.isEmpty)
        XCTAssertEqual(plan.quotaGuard.configuration.accountPool, [existing.id])
        XCTAssertFalse(plan.quotaGuard.configuration.isEnabled)
        XCTAssertEqual(plan.quotaGuard.runtime, QuotaGuardRuntime())
    }

    func testNewAccountsRequireOfficialReauthenticationAndGuardIsDisabled() throws {
        let backup = try makePortableBackup()

        let plan = try BackupMigrationPlanner.plan(
            backup: backup,
            existing: try AccountDirectory(),
            now: exportedAt,
            generateID: UUID.init
        )
        let imported = try XCTUnwrap(plan.directory.accounts.first)

        XCTAssertEqual(imported.id, backup.accounts[0].sourceID)
        XCTAssertEqual(imported.status, .unknown)
        XCTAssertNil(imported.quota)
        XCTAssertFalse(imported.hasSecret)
        XCTAssertFalse(imported.autoSwitchEligible)
        XCTAssertEqual(plan.requiresOfficialReauthentication, [imported.id])
        XCTAssertEqual(plan.addedCount, 1)
        XCTAssertEqual(plan.remappedIDCount, 0)
        XCTAssertFalse(plan.quotaGuard.configuration.isEnabled)
        XCTAssertEqual(plan.quotaGuard.configuration.thresholdCharacters, 500)
        XCTAssertEqual(plan.quotaGuard.configuration.accountPool, [imported.id])
    }

    func testSourceUUIDCollisionIsRemappedAndGuardPoolFollowsMapping() throws {
        let backup = try makePortableBackup()
        let collision = try AccountProfile(
            id: backup.accounts[0].sourceID,
            displayName: "Existing Other",
            email: "other@example.test"
        )
        let replacementID = UUID()

        let plan = try BackupMigrationPlanner.plan(
            backup: backup,
            existing: try AccountDirectory(accounts: [collision]),
            now: exportedAt,
            generateID: { replacementID }
        )
        let imported = try XCTUnwrap(plan.directory.account(matchingEmail: "user@example.test"))

        XCTAssertEqual(imported.id, replacementID)
        XCTAssertEqual(plan.remappedIDCount, 1)
        XCTAssertEqual(plan.quotaGuard.configuration.accountPool, [replacementID])
    }

    private func makeExportFixture() throws -> (
        directory: AccountDirectory,
        guardConfiguration: QuotaGuardConfiguration
    ) {
        var account = try AccountProfile(
            displayName: "Person",
            email: "person@example.test",
            note: "Primary",
            status: .available,
            autoSwitchEligible: true,
            quota: QuotaSnapshot(
                usedCharacters: 1_000,
                limitCharacters: 8_000,
                observedAt: exportedAt,
                source: .typelessAccessibility
            ),
            hasSecret: true,
            createdAt: exportedAt.addingTimeInterval(-100)
        )
        account.updatedAt = exportedAt
        return (
            try AccountDirectory(accounts: [account]),
            QuotaGuardConfiguration(
                isEnabled: true,
                thresholdCharacters: 700,
                accountPool: [account.id],
                cooldownMinutes: 45
            )
        )
    }

    private func makePortableBackup() throws -> PortableBackup {
        let accountID = UUID()
        return PortableBackup(
            exportedAt: exportedAt,
            appVersion: "0.2.0",
            accounts: [PortableAccount(
                sourceID: accountID,
                displayName: "User",
                email: "user@example.test",
                note: "Primary",
                createdAt: exportedAt.addingTimeInterval(-100)
            )],
            quotaGuard: PortableQuotaGuard(
                wasEnabled: true,
                thresholdCharacters: 500,
                accountPool: [accountID],
                cooldownMinutes: 30
            )
        )
    }

    private func XCTAssertThrowsBackup(
        _ expected: PortableBackupError,
        _ backup: PortableBackup,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try PortableBackupCodec.decode(
            try encoder.encode(backup)
        ), file: file, line: line) {
            XCTAssertEqual($0 as? PortableBackupError, expected, file: file, line: line)
        }
    }
}
