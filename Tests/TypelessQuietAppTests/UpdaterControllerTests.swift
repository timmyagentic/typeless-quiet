import Foundation
import Sparkle
import XCTest
@testable import TypelessQuietApp
import TypelessQuietCore

@MainActor
final class UpdaterControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var root: URL!
    private var suite: String!
    private var bundle: Bundle!

    override func setUpWithError() throws {
        suite = "TypelessUpdaterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        root = FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathExtension("app")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": suite!, "CFBundleVersion": "9",
                                   "CFBundleShortVersionString": "0.0.1", "TypelessUpdateChannel": "beta"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        bundle = Bundle(url: root)!
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: root)
    }

    private func controller() -> UpdaterController { UpdaterController(bundle: bundle, defaults: defaults, start: false) }
    private var update: AvailableUpdate { AvailableUpdate(version: "0.0.1 Beta 4", build: "10", channel: .beta) }

    func testBackgroundDiscoveryPersistsBadgeWithoutOpeningWindowAndEndsSession() {
        let updater = controller()
        var presentations = 0
        updater.onPresent = { presentations += 1 }
        var choices: [SPUUserUpdateChoice] = []
        updater.receiveDiscovery(update, userInitiated: false, recoveredInstallation: false) { choices.append($0) }
        XCTAssertEqual(presentations, 0)
        XCTAssertEqual(choices, [.dismiss])
        XCTAssertEqual(updater.phase, .available)
        XCTAssertEqual(controller().available, update)
    }

    func testManualDiscoveryShowsFeedbackAndDoesNotInstallUntilUserActs() {
        let updater = controller()
        var presentations = 0
        updater.onPresent = { presentations += 1 }
        var choice: SPUUserUpdateChoice?
        updater.receiveDiscovery(update, userInitiated: true, recoveredInstallation: false) { choice = $0 }
        XCTAssertEqual(presentations, 1)
        XCTAssertEqual(choice, .dismiss)
    }

    func testRecoveredInstallerDoesNotRelaunchFromBadgeAttention() {
        let updater = controller()
        var choices: [SPUUserUpdateChoice] = []
        updater.onPresent = {}
        updater.receiveDiscovery(update, userInitiated: true, recoveredInstallation: true) { choices.append($0) }
        XCTAssertEqual(updater.phase, .ready)
        XCTAssertTrue(choices.isEmpty)
        updater.installAvailableUpdate()
        XCTAssertTrue(choices.isEmpty)
        updater.installAndRelaunch()
        updater.installAndRelaunch()
        XCTAssertEqual(choices, [.install])
    }

    func testDownloadCancellationIsOneShotAndExpiresAtExtraction() {
        let updater = controller()
        var cancellations = 0
        updater.showDownloadInitiated { cancellations += 1 }
        updater.cancel()
        updater.cancel()
        XCTAssertEqual(cancellations, 1)
        updater.showDownloadInitiated { cancellations += 1 }
        updater.showDownloadDidStartExtractingUpdate()
        updater.cancel()
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(updater.canCancel)
        XCTAssertEqual(updater.phase, .extracting)
    }

    func testReadyRequiresExplicitRestartAndLaterIsOneShot() {
        let updater = controller()
        var presentations = 0
        var choices: [SPUUserUpdateChoice] = []
        updater.onPresent = { presentations += 1 }
        updater.showReady { choices.append($0) }
        XCTAssertEqual(updater.phase, .ready)
        XCTAssertEqual(presentations, 1)
        XCTAssertTrue(choices.isEmpty)
        updater.installLater()
        updater.installAndRelaunch()
        XCTAssertEqual(choices, [.dismiss])
    }

    func testNewerFeedMustBeRevalidatedAndOlderBuildIsNotOffered() {
        let updater = controller()
        var choices: [SPUUserUpdateChoice] = []
        updater.receiveDiscovery(AvailableUpdate(version: "0.1.5", build: "6", channel: .stable),
                                 userInitiated: false, recoveredInstallation: false) { choices.append($0) }
        XCTAssertEqual(choices, [.dismiss])
        XCTAssertNil(updater.available)
        XCTAssertEqual(updater.phase, .upToDate)
    }

    func testNoUpdateClearsPersistedBadgeWithoutBackgroundWindow() {
        let updater = controller()
        var presentations = 0
        updater.onPresent = { presentations += 1 }
        updater.receiveDiscovery(update, userInitiated: false, recoveredInstallation: false) { _ in }
        var acknowledged = false
        updater.showUpdateNotFoundWithError(NSError(domain: SUSparkleErrorDomain,
                code: Int(SUError.noUpdateError.rawValue))) { acknowledged = true }
        XCTAssertTrue(acknowledged)
        XCTAssertNil(controller().available)
        XCTAssertEqual(presentations, 0)
    }

    func testFailedDownloadRetainsBadgeButInvalidatesRestartReply() {
        let updater = controller()
        var choices: [SPUUserUpdateChoice] = []
        updater.onPresent = {}
        updater.receiveDiscovery(update, userInitiated: false, recoveredInstallation: true) { choices.append($0) }
        updater.showUpdaterError(NSError(domain: "test", code: 1)) {}
        updater.installAndRelaunch()
        XCTAssertTrue(choices.isEmpty)
        XCTAssertEqual(updater.phase, .failed)
        XCTAssertEqual(controller().available, update)
    }

    func testChannelPreferenceAndOldBadgesAreFilteredOnLaunch() {
        let updater = controller()
        updater.receiveDiscovery(update, userInitiated: false, recoveredInstallation: false) { _ in }
        defaults.set("stable", forKey: "TypelessPlusPlus.UpdateChannel")
        XCTAssertNil(controller().available)
        XCTAssertEqual(controller().channel, .stable)
    }

    func testQAFlagAloneCannotActivateIsolatedModeOnProductionIdentity() {
        XCTAssertFalse(UpdaterController.isIsolatedQA(bundle))
    }
}
