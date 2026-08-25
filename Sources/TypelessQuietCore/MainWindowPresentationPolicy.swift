public struct MainWindowPresentationPolicy: Sendable {
    public init() {}

    public func shouldPresentMainWindow(launchedAsLoginItem: Bool) -> Bool {
        !launchedAsLoginItem
    }

    public func shouldPresentMainWindowForReopen(hasVisibleWindows _: Bool) -> Bool {
        true
    }
}
