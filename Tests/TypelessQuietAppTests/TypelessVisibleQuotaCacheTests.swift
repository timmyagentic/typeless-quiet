import Foundation
import XCTest
@testable import TypelessQuietApp
@testable import TypelessQuietCore

final class TypelessVisibleQuotaCacheTests: XCTestCase {
    private let email = "person@example.com"
    private let processIdentifier: pid_t = 42
    private let observedAt = Date(timeIntervalSince1970: 10_000)

    func testReusesFreshOfficialSnapshotWhenHubIsTemporarilyHidden() throws {
        let cache = TypelessVisibleQuotaCache(maximumAge: 300)

        let observed = cache.resolve(
            email: email,
            processIdentifier: processIdentifier,
            texts: ["855 / 8,000 字"],
            observedAt: observedAt
        )
        let hidden = cache.resolve(
            email: email,
            processIdentifier: processIdentifier,
            texts: ["更新说明"],
            observedAt: observedAt.addingTimeInterval(60)
        )

        XCTAssertEqual(observed.provenance, .visibleAccessibility)
        XCTAssertEqual(hidden.provenance, .cachedAccessibility)
        XCTAssertEqual(try XCTUnwrap(hidden.quota).remainingCharacters, 7_145)
        XCTAssertEqual(hidden.quota?.observedAt, observedAt)
    }

    func testCacheExpiresAndNeverCrossesEmailOrProcess() {
        let cache = TypelessVisibleQuotaCache(maximumAge: 300)
        _ = cache.resolve(
            email: email,
            processIdentifier: processIdentifier,
            texts: ["855 / 8,000 字"],
            observedAt: observedAt
        )

        XCTAssertEqual(
            cache.resolve(
                email: "other@example.com",
                processIdentifier: processIdentifier,
                texts: [],
                observedAt: observedAt.addingTimeInterval(1)
            ).provenance,
            .unavailable
        )
        _ = cache.resolve(
            email: email,
            processIdentifier: processIdentifier,
            texts: ["855 / 8,000 字"],
            observedAt: observedAt
        )
        XCTAssertEqual(
            cache.resolve(
                email: email,
                processIdentifier: processIdentifier + 1,
                texts: [],
                observedAt: observedAt.addingTimeInterval(1)
            ).provenance,
            .unavailable
        )
        _ = cache.resolve(
            email: email,
            processIdentifier: processIdentifier,
            texts: ["855 / 8,000 字"],
            observedAt: observedAt
        )
        XCTAssertEqual(
            cache.resolve(
                email: email,
                processIdentifier: processIdentifier,
                texts: [],
                observedAt: observedAt.addingTimeInterval(301)
            ).provenance,
            .unavailable
        )
    }

    func testExplicitWeeklyLimitReachedRefreshesOnlyAKnownLimit() throws {
        let cache = TypelessVisibleQuotaCache(maximumAge: 300)

        XCTAssertEqual(
            cache.resolve(
                email: email,
                processIdentifier: processIdentifier,
                texts: ["已达到每周限制"],
                observedAt: observedAt
            ).provenance,
            .unavailable
        )

        _ = cache.resolve(
            email: email,
            processIdentifier: processIdentifier,
            texts: ["7,999 / 8,000 字"],
            observedAt: observedAt
        )
        let reached = cache.resolve(
            email: email,
            processIdentifier: processIdentifier,
            texts: ["已达到每周限制"],
            observedAt: observedAt.addingTimeInterval(5)
        )

        XCTAssertEqual(reached.provenance, .visibleWeeklyLimitReached)
        XCTAssertEqual(try XCTUnwrap(reached.quota).usedCharacters, 8_000)
        XCTAssertEqual(reached.quota?.limitCharacters, 8_000)
        XCTAssertEqual(reached.quota?.observedAt, observedAt.addingTimeInterval(5))
    }
}
