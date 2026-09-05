import Foundation
import XCTest
@testable import TypelessQuietCore

final class UpdatePolicyTests: XCTestCase {
    func testLifecycleChecksRespectPreferenceBusyStateAndSixHourBoundary() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(UpdatePolicy.shouldCheck(automatic: true, canCheck: true, lastCheck: nil, now: now))
        XCTAssertFalse(UpdatePolicy.shouldCheck(automatic: false, canCheck: true, lastCheck: nil, now: now))
        XCTAssertFalse(UpdatePolicy.shouldCheck(automatic: true, canCheck: false, lastCheck: nil, now: now))
        XCTAssertFalse(UpdatePolicy.shouldCheck(automatic: true, canCheck: true, lastCheck: now.addingTimeInterval(-21600), now: now))
        XCTAssertTrue(UpdatePolicy.shouldCheck(automatic: true, canCheck: true, lastCheck: now.addingTimeInterval(-21601), now: now))
        XCTAssertFalse(UpdatePolicy.shouldCheck(automatic: true, canCheck: true, lastCheck: now.addingTimeInterval(10), now: now))
    }

    func testStableExcludesBetaAndBetaIncludesStable() {
        XCTAssertEqual(UpdateChannel.stable.allowedChannels, [])
        XCTAssertEqual(UpdateChannel.beta.allowedChannels, ["beta"])
        XCTAssertEqual(UpdateChannel.resolve(saved: nil, bundled: "beta"), .beta)
        XCTAssertEqual(UpdateChannel.resolve(saved: "stable", bundled: "beta"), .stable)
        XCTAssertEqual(UpdateChannel.resolve(saved: "invalid", bundled: "invalid"), .stable)
    }

    func testAvailabilityUsesBuildNotMarketingVersionAndClearsAfterUpgrade() {
        let beta = AvailableUpdate(version: "0.0.1 Beta 3", build: "9", channel: .beta)
        XCTAssertTrue(beta.isNewer(than: "8", channel: .beta))
        XCTAssertFalse(beta.isNewer(than: "9", channel: .beta))
        XCTAssertFalse(beta.isNewer(than: "10", channel: .beta))
        XCTAssertFalse(beta.isNewer(than: "8", channel: .stable))
        let oldQuiet = AvailableUpdate(version: "0.1.5", build: "6", channel: .stable)
        XCTAssertFalse(oldQuiet.isNewer(than: "8", channel: .beta))
        XCTAssertFalse(AvailableUpdate(version: "9", build: "bad", channel: .stable).isNewer(than: "8", channel: .stable))
    }

    func testDirectInstallIntentIsConsumedOnceAndCancelResetsIt() {
        var intent = UpdateCheckIntent()
        XCTAssertFalse(intent.consumeDirectInstall())
        intent.requestDirectInstall()
        XCTAssertTrue(intent.consumeDirectInstall())
        XCTAssertFalse(intent.consumeDirectInstall())
        intent.requestDirectInstall()
        intent.reset()
        XCTAssertFalse(intent.consumeDirectInstall())
    }
}
