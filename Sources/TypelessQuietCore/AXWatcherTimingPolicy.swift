public struct AXWatcherTiming: Equatable, Sendable {
    public let periodicScanInterval: Double
    public let periodicScanTolerance: Double
    public let observerDebounceDelay: Double

    public init(
        periodicScanInterval: Double,
        periodicScanTolerance: Double,
        observerDebounceDelay: Double
    ) {
        self.periodicScanInterval = periodicScanInterval
        self.periodicScanTolerance = periodicScanTolerance
        self.observerDebounceDelay = observerDebounceDelay
    }
}

public struct AXWatcherTimingPolicy: Sendable {
    public init() {}

    public func timing(observerRegistrationCount: Int) -> AXWatcherTiming {
        if observerRegistrationCount > 0 {
            return AXWatcherTiming(
                periodicScanInterval: 8.0,
                periodicScanTolerance: 1.6,
                observerDebounceDelay: 0.08
            )
        }

        return AXWatcherTiming(
            periodicScanInterval: 1.0,
            periodicScanTolerance: 0.1,
            observerDebounceDelay: 0.08
        )
    }
}
