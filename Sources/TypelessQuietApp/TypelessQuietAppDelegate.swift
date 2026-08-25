import AppKit
import CoreServices
import TypelessQuietCore

@MainActor
enum MainWindowRequestRouter {
    static var handler: (() -> Void)?

    static func requestPresentation() {
        handler?()
    }
}

@MainActor
final class TypelessQuietAppDelegate: NSObject, NSApplicationDelegate {
    private let presentationPolicy = MainWindowPresentationPolicy()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAsLoginItem = event?
            .paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?
            .booleanValue ?? false

        guard presentationPolicy.shouldPresentMainWindow(
            launchedAsLoginItem: launchedAsLoginItem
        ) else { return }

        DispatchQueue.main.async {
            MainWindowRequestRouter.requestPresentation()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        if presentationPolicy.shouldPresentMainWindowForReopen(
            hasVisibleWindows: hasVisibleWindows
        ) {
            MainWindowRequestRouter.requestPresentation()
        }
        return false
    }
}
