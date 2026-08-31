import XCTest
@testable import TypelessQuietCore

final class AccountFoundationTests: XCTestCase {
    func testNormalizesAccountEmailAndDefaultsDisplayName() throws {
        let profile = try AccountProfile(
            displayName: "  ",
            email: "  User@Example.COM "
        )

        XCTAssertEqual(profile.email, "user@example.com")
        XCTAssertEqual(profile.displayName, "user@example.com")
        XCTAssertEqual(profile.status, .available)
        XCTAssertFalse(profile.hasSecret)
    }

    func testRejectsInvalidEmail() {
        XCTAssertThrowsError(try AccountProfile(displayName: "Invalid", email: "not-an-email")) {
            XCTAssertEqual($0 as? AccountDirectoryError, .invalidEmail)
        }
    }

    func testRejectsDuplicateEmailCaseInsensitively() throws {
        var directory = try AccountDirectory(accounts: [
            try AccountProfile(displayName: "One", email: "user@example.com"),
        ])

        XCTAssertThrowsError(
            try directory.add(try AccountProfile(displayName: "Two", email: "USER@EXAMPLE.COM"))
        ) {
            XCTAssertEqual($0 as? AccountDirectoryError, .duplicateEmail)
        }
    }

    func testDirectoryCanonicalizesDecodedOrMutatedProfiles() throws {
        var profile = try AccountProfile(displayName: "  Person  ", email: "person@example.com")
        profile.email = "  PERSON@EXAMPLE.COM  "
        profile.note = "  Primary  "

        let directory = try AccountDirectory(accounts: [profile])

        XCTAssertEqual(directory.accounts.first?.email, "person@example.com")
        XCTAssertEqual(directory.accounts.first?.displayName, "Person")
        XCTAssertEqual(directory.accounts.first?.note, "Primary")
    }

    func testDirectoryRejectsMutatedInvalidProfile() throws {
        var profile = try AccountProfile(displayName: "Person", email: "person@example.com")
        profile.email = "invalid"

        XCTAssertThrowsError(try AccountDirectory(accounts: [profile])) {
            XCTAssertEqual($0 as? AccountDirectoryError, .invalidEmail)
        }
    }

    func testUpdateRejectsDuplicateBeforeChangingDirectory() throws {
        let first = try AccountProfile(displayName: "One", email: "one@example.com")
        let second = try AccountProfile(displayName: "Two", email: "two@example.com")
        var directory = try AccountDirectory(accounts: [first, second])
        var duplicate = first
        duplicate.email = "TWO@EXAMPLE.COM"

        XCTAssertThrowsError(try directory.update(duplicate)) {
            XCTAssertEqual($0 as? AccountDirectoryError, .duplicateEmail)
        }
        XCTAssertEqual(directory.account(matchingEmail: "one@example.com")?.id, first.id)
    }

    func testStoreRejectsUnsupportedSchemaVersion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("accounts.json")
        try Data(#"{"accounts":[],"schemaVersion":2}"#.utf8).write(to: file)

        XCTAssertThrowsError(try AccountDirectoryStore(fileURL: file).load()) {
            XCTAssertEqual($0 as? AccountDirectoryError, .invalidSchema)
        }
    }

    func testAccountDirectoryStoreRoundTripsSchemaV1WithoutSecrets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = root.appendingPathComponent("accounts.json")
        let store = AccountDirectoryStore(fileURL: file)
        let profile = try AccountProfile(
            displayName: "Personal",
            email: "personal@example.com",
            note: "Primary",
            hasSecret: true
        )
        let directory = try AccountDirectory(accounts: [profile])

        try store.save(directory)
        let loaded = try store.load()
        let data = try Data(contentsOf: file)
        let serialized = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(loaded, directory)
        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertFalse(serialized.contains("password"))
        XCTAssertFalse(serialized.contains("access_token"))
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testQuotaFreshnessAndRemainingCharacters() {
        let observedAt = Date(timeIntervalSince1970: 1_000)
        let quota = QuotaSnapshot(
            usedCharacters: 3_444,
            limitCharacters: 8_000,
            observedAt: observedAt,
            source: .typelessAccessibility
        )

        XCTAssertEqual(quota.remainingCharacters, 4_556)
        XCTAssertTrue(quota.isFresh(at: observedAt.addingTimeInterval(299), maximumAge: 300))
        XCTAssertFalse(quota.isFresh(at: observedAt.addingTimeInterval(301), maximumAge: 300))
    }

    func testDecodedQuotaClampsCorruptNegativeCounts() throws {
        let json = #"{"limitCharacters":-20,"observedAt":0,"source":"typelessLocalStorage","usedCharacters":-10}"#

        let quota = try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(quota.usedCharacters, 0)
        XCTAssertEqual(quota.limitCharacters, 0)
        XCTAssertEqual(quota.remainingCharacters, 0)
    }

    func testParsesWhitelistedTypelessIdentityWithoutLeakingTokens() throws {
        let json = """
        {
          "userData": {
            "email": "person@example.com",
            "name": "Person",
            "subscription_plan_name": "Free",
            "access_token": "TOP-SECRET",
            "refresh_token": "ALSO-SECRET"
          },
          "session": {"cookie": "SECRET-COOKIE"}
        }
        """
        let observedAt = Date(timeIntervalSince1970: 2_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_900)

        let state = try TypelessLocalStateParser.parse(
            data: Data(json.utf8),
            observedAt: observedAt,
            fileModifiedAt: modifiedAt
        )
        let encoded = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)

        XCTAssertEqual(state.email, "person@example.com")
        XCTAssertEqual(state.displayName, "Person")
        XCTAssertEqual(state.planName, "Free")
        XCTAssertEqual(state.sourceModifiedAt, modifiedAt)
        XCTAssertNil(state.quota)
        XCTAssertFalse(encoded.contains("TOP-SECRET"))
        XCTAssertFalse(encoded.contains("ALSO-SECRET"))
        XCTAssertFalse(encoded.contains("SECRET-COOKIE"))
    }

    func testLocalQuotaUsesFileModificationTimeForFreshness() throws {
        let json = #"{"quotaUsage":{"used":500,"limit":8000}}"#
        let readAt = Date(timeIntervalSince1970: 10_000)
        let modifiedAt = Date(timeIntervalSince1970: 9_000)

        let state = try TypelessLocalStateParser.parse(
            data: Data(json.utf8),
            observedAt: readAt,
            fileModifiedAt: modifiedAt
        )

        XCTAssertEqual(state.quota?.observedAt, modifiedAt)
        XCTAssertFalse(state.quota?.isFresh(at: readAt, maximumAge: 300) ?? true)
    }

    func testParsesVisibleLocalizedQuota() {
        let observedAt = Date(timeIntervalSince1970: 3_000)

        XCTAssertEqual(
            VisibleQuotaParser.parse(["获取无限字数", "3,444 / 8,000 字"], observedAt: observedAt),
            QuotaSnapshot(
                usedCharacters: 3_444,
                limitCharacters: 8_000,
                observedAt: observedAt,
                source: .typelessAccessibility
            )
        )
        XCTAssertEqual(
            VisibleQuotaParser.parse(["3,444 / 8,000 words"], observedAt: observedAt)?.remainingCharacters,
            4_556
        )
        XCTAssertNil(VisibleQuotaParser.parse(["August 31 / 2026"], observedAt: observedAt))
    }

    func testMergesVisibleQuotaIntoLocalIdentity() throws {
        let state = CurrentTypelessState(
            email: "person@example.com",
            displayName: "Person",
            planName: "Free",
            quota: nil,
            observedAt: Date(timeIntervalSince1970: 4_000),
            sourceModifiedAt: nil
        )
        let quota = QuotaSnapshot(
            usedCharacters: 100,
            limitCharacters: 8_000,
            observedAt: Date(timeIntervalSince1970: 4_001),
            source: .typelessAccessibility
        )

        XCTAssertEqual(state.merging(quota: quota).quota, quota)
    }
}
