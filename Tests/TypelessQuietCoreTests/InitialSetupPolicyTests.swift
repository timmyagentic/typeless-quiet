import XCTest
@testable import TypelessQuietCore

final class InitialSetupPolicyTests: XCTestCase {
    private let policy = InitialSetupPolicy()

    func testFirstLaunchPromptsForMissingAccessibilityAndRegistersLoginItem() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: false,
            accessibilityPromptHandled: false,
            launchAtLoginInitialized: false,
            launchAtLoginStatus: .notRegistered
        ))

        XCTAssertEqual(plan, InitialSetupPlan(
            promptForAccessibility: true,
            markAccessibilityPromptHandled: true,
            registerLaunchAtLogin: true,
            markLaunchAtLoginInitialized: false
        ))
    }

    func testDoesNotRepeatAccessibilityPromptAfterFirstHandling() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: false,
            accessibilityPromptHandled: true,
            launchAtLoginInitialized: true,
            launchAtLoginStatus: .notRegistered
        ))

        XCTAssertFalse(plan.promptForAccessibility)
        XCTAssertFalse(plan.markAccessibilityPromptHandled)
    }

    func testAlreadyGrantedAccessibilityCompletesPromptSetupWithoutPrompting() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptHandled: false,
            launchAtLoginInitialized: true,
            launchAtLoginStatus: .enabled
        ))

        XCTAssertFalse(plan.promptForAccessibility)
        XCTAssertTrue(plan.markAccessibilityPromptHandled)
    }

    func testExistingEnabledLoginItemCompletesDefaultWithoutRegisteringAgain() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptHandled: true,
            launchAtLoginInitialized: false,
            launchAtLoginStatus: .enabled
        ))

        XCTAssertFalse(plan.registerLaunchAtLogin)
        XCTAssertTrue(plan.markLaunchAtLoginInitialized)
    }

    func testRequiredSystemApprovalCompletesDefaultWithoutRegisteringAgain() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptHandled: true,
            launchAtLoginInitialized: false,
            launchAtLoginStatus: .requiresApproval
        ))

        XCTAssertFalse(plan.registerLaunchAtLogin)
        XCTAssertTrue(plan.markLaunchAtLoginInitialized)
    }

    func testUserDisabledLoginItemIsNotAutomaticallyReenabled() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptHandled: true,
            launchAtLoginInitialized: true,
            launchAtLoginStatus: .notRegistered
        ))

        XCTAssertFalse(plan.registerLaunchAtLogin)
        XCTAssertFalse(plan.markLaunchAtLoginInitialized)
    }

    func testUnavailableLoginItemRetriesOnAFutureLaunch() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptHandled: true,
            launchAtLoginInitialized: false,
            launchAtLoginStatus: .unavailable
        ))

        XCTAssertFalse(plan.registerLaunchAtLogin)
        XCTAssertFalse(plan.markLaunchAtLoginInitialized)
    }
}
