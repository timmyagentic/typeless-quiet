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

private struct ObservedNotification {
    let element: AXUIElement
    let notification: String
}

private enum ScanTrigger: String {
    case initial
    case observer
    case watchdog
    case fallback
}

private let typelessObserverCallback: AXObserverCallback = {
    _, _, notification, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<TypelessProcessWatcher>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    watcher.accessibilityNotificationReceived(notification: notification as String)
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
    private let timingPolicy = AXWatcherTimingPolicy()
    private let onEvent: (TypelessWatcherEvent) -> Void

    private var observer: AXObserver?
    private var observedNotifications: [ObservedNotification] = []
    private var pollTimer: Timer?
    private var isStarted = false
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
        guard !isStarted else { return }
        isStarted = true
        installObserver()

        let timing = timingPolicy.timing(
            observerRegistrationCount: observedNotifications.count
        )
        let periodicTrigger: ScanTrigger = observedNotifications.isEmpty
            ? .fallback
            : .watchdog
        let timer = Timer(timeInterval: timing.periodicScanInterval, repeats: true) {
            [weak self] _ in
            self?.scheduleScan(trigger: periodicTrigger)
        }
        timer.tolerance = timing.periodicScanTolerance
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        logger.info(
            "AX observer registrations: \(self.observedNotifications.count, privacy: .public); periodic scan interval: \(timing.periodicScanInterval, privacy: .public)s"
        )
        scheduleScan(trigger: .initial)
    }

    func stop() {
        isStarted = false
        pollTimer?.invalidate()
        pollTimer = nil

        if let observer {
            for registration in observedNotifications {
                AXObserverRemoveNotification(
                    observer,
                    registration.element,
                    registration.notification as CFString
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

    fileprivate func accessibilityNotificationReceived(notification: String) {
        logger.debug("Received AX notification: \(notification, privacy: .public)")
        if notification == "AXWindowCreated" || notification == "AXUIElementDestroyed" {
            refreshObservedWindows()
        }
        let timing = timingPolicy.timing(
            observerRegistrationCount: observedNotifications.count
        )
        scheduleScan(trigger: .observer, after: timing.observerDebounceDelay)
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

        observer = newObserver
        registerNotifications(
            [
                "AXCreated",
                "AXLayoutChanged",
                "AXWindowCreated",
                "AXFocusedWindowChanged",
                "AXApplicationActivated",
                "AXApplicationShown",
            ],
            on: applicationElement,
            observer: newObserver
        )
        refreshObservedWindows()
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
    }

    private func refreshObservedWindows() {
        guard let observer else { return }
        let notifications = [
            "AXCreated",
            "AXLayoutChanged",
            "AXValueChanged",
            "AXUIElementDestroyed",
        ]
        for window in reader.windowElements(in: applicationElement) {
            registerNotifications(notifications, on: window, observer: observer)
        }
    }

    private func registerNotifications(
        _ notifications: [String],
        on element: AXUIElement,
        observer: AXObserver
    ) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in notifications {
            guard !isObserving(element: element, notification: notification) else {
                continue
            }
            let result = AXObserverAddNotification(
                observer,
                element,
                notification as CFString,
                refcon
            )
            if result == .success || result == .notificationAlreadyRegistered {
                observedNotifications.append(ObservedNotification(
                    element: element,
                    notification: notification
                ))
            }
        }
    }

    private func isObserving(element: AXUIElement, notification: String) -> Bool {
        observedNotifications.contains { registration in
            registration.notification == notification
                && CFEqual(registration.element, element)
        }
    }

    private func scheduleScan(trigger: ScanTrigger, after delay: TimeInterval = 0) {
        guard !scanScheduled else { return }
        scanScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.scanScheduled = false
            guard self.isStarted else { return }
            self.scan(trigger: trigger)
        }
    }

    private func scan(trigger: ScanTrigger) {
        guard !isScanning else { return }
        isScanning = true
        let startedAt = ProcessInfo.processInfo.systemUptime
        defer {
            isScanning = false
            let durationMilliseconds = Int(
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
            logger.debug(
                "AX scan trigger=\(trigger.rawValue, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public)"
            )
        }

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
        (decision: MatchDecision, captures: [CapturedCard]),
        DecisionCaptureFailure
    > {
        let cards: [AXUIElement]
        switch reader.targetCardElements(in: applicationElement) {
        case let .success(elements):
            cards = elements
        case let .failure(failure):
            return .failure(DecisionCaptureFailure(message: String(describing: failure)))
        }

        var captures: [CapturedCard] = []
        captures.reserveCapacity(cards.count)
        for card in cards {
            switch reader.capture(card) {
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
