public enum LaunchAtLoginSetupStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

public struct InitialSetupState: Equatable, Sendable {
    public let accessibilityGranted: Bool
    public let accessibilityPromptHandled: Bool
    public let launchAtLoginInitialized: Bool
    public let launchAtLoginStatus: LaunchAtLoginSetupStatus

    public init(
        accessibilityGranted: Bool,
        accessibilityPromptHandled: Bool,
        launchAtLoginInitialized: Bool,
        launchAtLoginStatus: LaunchAtLoginSetupStatus
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.accessibilityPromptHandled = accessibilityPromptHandled
        self.launchAtLoginInitialized = launchAtLoginInitialized
        self.launchAtLoginStatus = launchAtLoginStatus
    }
}

public struct InitialSetupPlan: Equatable, Sendable {
    public let promptForAccessibility: Bool
    public let markAccessibilityPromptHandled: Bool
    public let registerLaunchAtLogin: Bool
    public let markLaunchAtLoginInitialized: Bool

    public init(
        promptForAccessibility: Bool,
        markAccessibilityPromptHandled: Bool,
        registerLaunchAtLogin: Bool,
        markLaunchAtLoginInitialized: Bool
    ) {
        self.promptForAccessibility = promptForAccessibility
        self.markAccessibilityPromptHandled = markAccessibilityPromptHandled
        self.registerLaunchAtLogin = registerLaunchAtLogin
        self.markLaunchAtLoginInitialized = markLaunchAtLoginInitialized
    }
}

public struct InitialSetupPolicy: Sendable {
    public init() {}

    public func plan(for state: InitialSetupState) -> InitialSetupPlan {
        let shouldHandleAccessibility = !state.accessibilityPromptHandled
        let shouldPromptForAccessibility = shouldHandleAccessibility
            && !state.accessibilityGranted

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
            promptForAccessibility: shouldPromptForAccessibility,
            markAccessibilityPromptHandled: shouldHandleAccessibility,
            registerLaunchAtLogin: shouldRegisterLaunchAtLogin,
            markLaunchAtLoginInitialized: shouldMarkLaunchAtLoginInitialized
        )
    }
}
