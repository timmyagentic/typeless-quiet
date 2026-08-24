import AppKit
import ApplicationServices
import OSLog
import TypelessQuietCore

enum TypelessWatcherEvent {
    case dismissed(Date)
    case unsafe(String)
    case error(String)
}

private struct DecisionCaptureFailure: Error {
    let message: String
}

private let typelessObserverCallback: AXObserverCallback = {
    _, _, notification, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<TypelessProcessWatcher>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    watcher.accessibilityNotificationReceived(notification as String)
}

final class TypelessProcessWatcher {
    private let logger = Logger(
        subsystem: "io.github.timmyagentic.TypelessQuiet",
        category: "TypelessWatcher"
    )
    private let processIdentifier: pid_t
    private let applicationElement: AXUIElement
    private let reader = AccessibilityElementReader()
    private let matcher = TargetPromptMatcher()
    private let onEvent: (TypelessWatcherEvent) -> Void

    private var observer: AXObserver?
    private var observedNotifications: [String] = []
    private var pollTimer: Timer?
    private var scanScheduled = false
    private var isScanning = false
    private var lastDismissalUptime = -Double.infinity
    private var lastUnsafeMessage: String?

    var watchedProcessIdentifier: pid_t { processIdentifier }

    init(processIdentifier: pid_t, onEvent: @escaping (TypelessWatcherEvent) -> Void) {
        self.processIdentifier = processIdentifier
        self.applicationElement = AXUIElementCreateApplication(processIdentifier)
        self.onEvent = onEvent
    }

    func start() {
        installObserver()

        let timer = Timer(timeInterval: 0.40, repeats: true) { [weak self] _ in
            self?.scheduleScan()
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        scheduleScan()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil

        if let observer {
            for notification in observedNotifications {
                AXObserverRemoveNotification(
                    observer,
                    applicationElement,
                    notification as CFString
                )
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }

        observedNotifications.removeAll()
        observer = nil
        scanScheduled = false
        isScanning = false
    }

    fileprivate func accessibilityNotificationReceived(_ notification: String) {
        logger.debug("Received AX notification: \(notification, privacy: .public)")
        scheduleScan()
    }

    private func installObserver() {
        var newObserver: AXObserver?
        let result = AXObserverCreate(
            processIdentifier,
            typelessObserverCallback,
            &newObserver
        )
        guard result == .success, let newObserver else {
            logger.info("AX observer unavailable; bounded polling remains active")
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = ["AXCreated", "AXLayoutChanged", "AXWindowCreated"]
        for notification in notifications {
            let addResult = AXObserverAddNotification(
                newObserver,
                applicationElement,
                notification as CFString,
                refcon
            )
            if addResult == .success {
                observedNotifications.append(notification)
            }
        }

        observer = newObserver
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
    }

    private func scheduleScan() {
        guard !scanScheduled else { return }
        scanScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scanScheduled = false
            self.scan()
        }
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDismissalUptime >= 1.0 else { return }

        switch captureDecision() {
        case let .failure(failure):
            reportUnsafe(failure.message)
        case let .success(initial):
            switch initial.decision {
            case .noTarget:
                lastUnsafeMessage = nil
            case let .unsafe(reason):
                reportUnsafe(reason.rawValue)
            case .dismiss:
                revalidateAndDismiss(expected: initial.decision)
            }
        }
    }

    private func revalidateAndDismiss(expected: MatchDecision) {
        switch captureDecision() {
        case let .failure(failure):
            reportUnsafe("revalidation: \(failure.message)")
        case let .success(revalidated):
            guard revalidated.decision == expected else {
                reportUnsafe("target changed during revalidation")
                return
            }
            guard case let .dismiss(cardIndex, buttonPath) = revalidated.decision,
                  revalidated.captures.indices.contains(cardIndex),
                  let button = revalidated.captures[cardIndex].elementsByPath[buttonPath]
            else {
                reportUnsafe("validated button could not be resolved")
                return
            }

            let actionResult = AXUIElementPerformAction(button, "AXPress" as CFString)
            guard actionResult == .success else {
                let message = "AXPress failed with code \(actionResult.rawValue)"
                logger.error("\(message, privacy: .public)")
                onEvent(.error(message))
                return
            }

            lastDismissalUptime = ProcessInfo.processInfo.systemUptime
            lastUnsafeMessage = nil
            let date = Date()
            logger.notice("Dismissed the exact Typeless accuracy-upgrade card")
            onEvent(.dismissed(date))
        }
    }

    private func captureDecision() -> Result<
        (decision: MatchDecision, captures: [CapturedTooltip]),
        DecisionCaptureFailure
    > {
        let tooltips: [AXUIElement]
        switch reader.tooltipElements(in: applicationElement) {
        case let .success(elements):
            tooltips = elements
        case let .failure(failure):
            return .failure(DecisionCaptureFailure(message: String(describing: failure)))
        }

        var captures: [CapturedTooltip] = []
        captures.reserveCapacity(tooltips.count)
        for tooltip in tooltips {
            switch reader.capture(tooltip) {
            case let .success(capture):
                captures.append(capture)
            case let .failure(failure):
                return .failure(DecisionCaptureFailure(message: String(describing: failure)))
            }
        }

        return .success((
            decision: matcher.decision(for: captures.map(\.snapshot)),
            captures: captures
        ))
    }

    private func reportUnsafe(_ message: String) {
        guard lastUnsafeMessage != message else { return }
        lastUnsafeMessage = message
        logger.warning("Failing closed: \(message, privacy: .public)")
        onEvent(.unsafe(message))
    }
}
