import XCTest
@testable import TypelessQuietCore

final class MainWindowPresentationPolicyTests: XCTestCase {
    private let policy = MainWindowPresentationPolicy()

    func testShowsMainWindowForNormalUserLaunch() {
        XCTAssertTrue(policy.shouldPresentMainWindow(launchedAsLoginItem: false))
    }

    func testKeepsLoginItemLaunchInBackground() {
        XCTAssertFalse(policy.shouldPresentMainWindow(launchedAsLoginItem: true))
    }

    func testExplicitReopenAlwaysPresentsOrRaisesMainWindow() {
        XCTAssertTrue(policy.shouldPresentMainWindowForReopen(hasVisibleWindows: false))
        XCTAssertTrue(policy.shouldPresentMainWindowForReopen(hasVisibleWindows: true))
    }
}
