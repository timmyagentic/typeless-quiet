import Foundation
import XCTest
@testable import TypelessQuietApp
@testable import TypelessQuietCore

final class LiveTypelessStateSmokeTests: XCTestCase {
    func testReadsCurrentTypeless240IdentityWithoutPrintingValues() throws {
        try requireLiveQA()
        let result = try TypelessCurrentStateReader().read()

        XCTAssertEqual(result.appVersion, "2.4.0")
        XCTAssertTrue(result.appRunning)
        XCTAssertNotNil(result.state.email)
    }

    func testReadsFreshVisibleQuotaWhenCurrentInterfaceExposesIt() throws {
        try requireLiveQA()
        let result = try TypelessCurrentStateReader().read()
        guard let quota = result.state.quota else {
            throw XCTSkip("Current Typeless interface does not expose a readable quota")
        }

        XCTAssertEqual(quota.source, .typelessAccessibility)
        XCTAssertTrue(quota.isFresh())
    }

    func testReadsActivityWhenCurrentInterfaceExposesRecordingControl() throws {
        try requireLiveQA()
        let result = try TypelessCurrentStateReader().read()
        guard result.state.activity != .unknown else {
            throw XCTSkip("Current Typeless interface does not expose recognized activity controls")
        }

        XCTAssertTrue([
            TypelessActivityState.idle,
            .recording,
            .processing,
        ].contains(result.state.activity))
    }

    private func requireLiveQA() throws {
        guard ProcessInfo.processInfo.environment[
            "TYPELESS_PLUSPLUS_RUN_LIVE_READ_QA"
        ] == "true" else {
            throw XCTSkip("Set TYPELESS_PLUSPLUS_RUN_LIVE_READ_QA=true for local live QA")
        }
    }
}
