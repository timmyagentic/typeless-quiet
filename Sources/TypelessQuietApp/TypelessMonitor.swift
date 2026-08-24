import AppKit
import TypelessQuietCore

enum TypelessMonitorEvent {
    case runningChanged(Bool)
    case dismissed(Date)
    case unsafe(String)
    case error(String)
}

@MainActor
final class TypelessMonitor: NSObject {
    private let onEvent: (TypelessMonitorEvent) -> Void
    private var watcher: TypelessProcessWatcher?
    private var watchingAllowed = false
    private var lastRunningState: Bool?

    init(onEvent: @escaping (TypelessMonitorEvent) -> Void) {
        self.onEvent = onEvent
        super.init()
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationsChanged),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationsChanged),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        reconcile()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detachWatcher()
    }

    func setWatchingAllowed(_ allowed: Bool) {
        guard watchingAllowed != allowed else { return }
        watchingAllowed = allowed
        reconcile()
    }

    @objc private func workspaceApplicationsChanged(_ notification: Notification) {
        reconcile()
    }

    private func reconcile() {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: TargetPromptMatcher.targetBundleIdentifier
        )
        let isRunning = !applications.isEmpty
        if lastRunningState != isRunning {
            lastRunningState = isRunning
            onEvent(.runningChanged(isRunning))
        }

        guard watchingAllowed else {
            detachWatcher()
            return
        }

        guard applications.count == 1, let application = applications.first else {
            detachWatcher()
            if applications.count > 1 {
                onEvent(.unsafe("multiple Typeless application processes"))
            }
            return
        }

        if watcher?.watchedProcessIdentifier == application.processIdentifier {
            return
        }

        detachWatcher()
        let newWatcher = TypelessProcessWatcher(
            processIdentifier: application.processIdentifier
        ) { [weak self] event in
            switch event {
            case let .dismissed(date):
                self?.onEvent(.dismissed(date))
            case let .unsafe(message):
                self?.onEvent(.unsafe(message))
            case let .error(message):
                self?.onEvent(.error(message))
            }
        }
        watcher = newWatcher
        newWatcher.start()
    }

    private func detachWatcher() {
        watcher?.stop()
        watcher = nil
    }
}
