import XCTest
@testable import TypelessQuietCore

final class InitialSetupPolicyTests: XCTestCase {
    private let policy = InitialSetupPolicy()

    func testFirstLaunchShowsOnboardingPromptsForAccessibilityAndRegistersLoginItem() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: false,
            accessibilityPromptedBuild: nil,
            currentBuild: "4",
            launchAtLoginInitialized: false,
            launchAtLoginStatus: .notRegistered
        ))

        XCTAssertEqual(plan, InitialSetupPlan(
            presentAccessibilityOnboarding: true,
            promptForAccessibility: true,
            recordAccessibilityPromptBuild: true,
            registerLaunchAtLogin: true,
            markLaunchAtLoginInitialized: false
        ))
    }

    func testMissingPermissionStillShowsOnboardingAfterCurrentBuildWasPrompted() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: false,
            accessibilityPromptedBuild: "4",
            currentBuild: "4",
            launchAtLoginInitialized: true,
            launchAtLoginStatus: .notRegistered
        ))

        XCTAssertTrue(plan.presentAccessibilityOnboarding)
        XCTAssertFalse(plan.promptForAccessibility)
        XCTAssertFalse(plan.recordAccessibilityPromptBuild)
    }

    func testNewBuildRetriesSystemPromptWhileKeepingOnboardingVisible() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: false,
            accessibilityPromptedBuild: "3",
            currentBuild: "4",
            launchAtLoginInitialized: true,
            launchAtLoginStatus: .notRegistered
        ))

        XCTAssertTrue(plan.presentAccessibilityOnboarding)
        XCTAssertTrue(plan.promptForAccessibility)
        XCTAssertTrue(plan.recordAccessibilityPromptBuild)
    }

    func testGrantedAccessibilityNeedsNeitherOnboardingNorPrompt() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptedBuild: nil,
            currentBuild: "4",
            launchAtLoginInitialized: true,
            launchAtLoginStatus: .enabled
        ))

        XCTAssertFalse(plan.presentAccessibilityOnboarding)
        XCTAssertFalse(plan.promptForAccessibility)
        XCTAssertFalse(plan.recordAccessibilityPromptBuild)
    }

    func testExistingEnabledLoginItemCompletesDefaultWithoutRegisteringAgain() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptedBuild: "4",
            currentBuild: "4",
            launchAtLoginInitialized: false,
            launchAtLoginStatus: .enabled
        ))

        XCTAssertFalse(plan.registerLaunchAtLogin)
        XCTAssertTrue(plan.markLaunchAtLoginInitialized)
    }

    func testRequiredSystemApprovalCompletesDefaultWithoutRegisteringAgain() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptedBuild: "4",
            currentBuild: "4",
            launchAtLoginInitialized: false,
            launchAtLoginStatus: .requiresApproval
        ))

        XCTAssertFalse(plan.registerLaunchAtLogin)
        XCTAssertTrue(plan.markLaunchAtLoginInitialized)
    }

    func testUserDisabledLoginItemIsNotAutomaticallyReenabled() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptedBuild: "4",
            currentBuild: "4",
            launchAtLoginInitialized: true,
            launchAtLoginStatus: .notRegistered
        ))

        XCTAssertFalse(plan.registerLaunchAtLogin)
        XCTAssertFalse(plan.markLaunchAtLoginInitialized)
    }

    func testUnavailableLoginItemRetriesOnAFutureLaunch() {
        let plan = policy.plan(for: InitialSetupState(
            accessibilityGranted: true,
            accessibilityPromptedBuild: "4",
            currentBuild: "4",
            launchAtLoginInitialized: false,
            launchAtLoginStatus: .unavailable
        ))

        XCTAssertFalse(plan.registerLaunchAtLogin)
        XCTAssertFalse(plan.markLaunchAtLoginInitialized)
    }
}
