public enum LaunchAtLoginSetupStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

public struct InitialSetupState: Equatable, Sendable {
    public let accessibilityGranted: Bool
    public let accessibilityPromptedBuild: String?
    public let currentBuild: String
    public let launchAtLoginInitialized: Bool
    public let launchAtLoginStatus: LaunchAtLoginSetupStatus

    public init(
        accessibilityGranted: Bool,
        accessibilityPromptedBuild: String?,
        currentBuild: String,
        launchAtLoginInitialized: Bool,
        launchAtLoginStatus: LaunchAtLoginSetupStatus
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.accessibilityPromptedBuild = accessibilityPromptedBuild
        self.currentBuild = currentBuild
        self.launchAtLoginInitialized = launchAtLoginInitialized
        self.launchAtLoginStatus = launchAtLoginStatus
    }
}

public struct InitialSetupPlan: Equatable, Sendable {
    public let presentAccessibilityOnboarding: Bool
    public let promptForAccessibility: Bool
    public let recordAccessibilityPromptBuild: Bool
    public let registerLaunchAtLogin: Bool
    public let markLaunchAtLoginInitialized: Bool

    public init(
        presentAccessibilityOnboarding: Bool,
        promptForAccessibility: Bool,
        recordAccessibilityPromptBuild: Bool,
        registerLaunchAtLogin: Bool,
        markLaunchAtLoginInitialized: Bool
    ) {
        self.presentAccessibilityOnboarding = presentAccessibilityOnboarding
        self.promptForAccessibility = promptForAccessibility
        self.recordAccessibilityPromptBuild = recordAccessibilityPromptBuild
        self.registerLaunchAtLogin = registerLaunchAtLogin
        self.markLaunchAtLoginInitialized = markLaunchAtLoginInitialized
    }
}

public struct InitialSetupPolicy: Sendable {
    public init() {}

    public func plan(for state: InitialSetupState) -> InitialSetupPlan {
        let shouldPresentAccessibilityOnboarding = !state.accessibilityGranted
        let shouldPromptForAccessibility = !state.accessibilityGranted
            && state.accessibilityPromptedBuild != state.currentBuild

        let shouldRegisterLaunchAtLogin: Bool
        let shouldMarkLaunchAtLoginInitialized: Bool
        if state.launchAtLoginInitialized {
            shouldRegisterLaunchAtLogin = false
            shouldMarkLaunchAtLoginInitialized = false
        } else {
            switch state.launchAtLoginStatus {
            case .notRegistered:
                shouldRegisterLaunchAtLogin = true
                shouldMarkLaunchAtLoginInitialized = false
            case .enabled, .requiresApproval:
                shouldRegisterLaunchAtLogin = false
                shouldMarkLaunchAtLoginInitialized = true
            case .unavailable:
                shouldRegisterLaunchAtLogin = false
                shouldMarkLaunchAtLoginInitialized = false
            }
        }

        return InitialSetupPlan(
            presentAccessibilityOnboarding: shouldPresentAccessibilityOnboarding,
            promptForAccessibility: shouldPromptForAccessibility,
            recordAccessibilityPromptBuild: shouldPromptForAccessibility,
            registerLaunchAtLogin: shouldRegisterLaunchAtLogin,
            markLaunchAtLoginInitialized: shouldMarkLaunchAtLoginInitialized
        )
    }
}
