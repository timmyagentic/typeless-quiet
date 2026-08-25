import XCTest
@testable import TypelessQuietCore

final class AXWatcherTimingPolicyTests: XCTestCase {
    private let policy = AXWatcherTimingPolicy()

    func testUsesLowFrequencyWatchdogWhenAnyObserverNotificationIsRegistered() {
        XCTAssertEqual(
            policy.timing(observerRegistrationCount: 1),
            AXWatcherTiming(
                periodicScanInterval: 8.0,
                periodicScanTolerance: 1.6,
                observerDebounceDelay: 0.08
            )
        )
    }

    func testUsesReliableFallbackWhenObserverHasNoSupportedNotifications() {
        XCTAssertEqual(
            policy.timing(observerRegistrationCount: 0),
            AXWatcherTiming(
                periodicScanInterval: 1.0,
                periodicScanTolerance: 0.1,
                observerDebounceDelay: 0.08
            )
        )
    }

    func testAdditionalObserverRegistrationsDoNotIncreaseWatchdogFrequency() {
        XCTAssertEqual(
            policy.timing(observerRegistrationCount: 12),
            policy.timing(observerRegistrationCount: 1)
        )
    }
}
