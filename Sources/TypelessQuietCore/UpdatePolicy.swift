import Foundation

public enum UpdateChannel: String, Codable, CaseIterable, Sendable {
    case stable
    case beta

    public var allowedChannels: Set<String> { self == .beta ? ["beta"] : [] }
    public var title: String { self == .beta ? "Beta 与正式版" : "仅正式版" }

    public static func resolve(saved: String?, bundled: String?) -> Self {
        saved.flatMap(Self.init(rawValue:)) ?? bundled.flatMap(Self.init(rawValue:)) ?? .stable
    }
}

public enum UpdatePolicy {
    public static func shouldCheck(
        automatic: Bool, canCheck: Bool, lastCheck: Date?, now: Date
    ) -> Bool {
        automatic && canCheck && (lastCheck.map { now.timeIntervalSince($0) > 21600 } ?? true)
    }
}

public struct AvailableUpdate: Codable, Equatable, Sendable {
    public let version: String
    public let build: String
    public let channel: UpdateChannel

    public init(version: String, build: String, channel: UpdateChannel) {
        self.version = version
        self.build = build
        self.channel = channel
    }

    public func isNewer(than currentBuild: String, channel selectedChannel: UpdateChannel) -> Bool {
        guard let candidate = UInt64(build), let current = UInt64(currentBuild),
              selectedChannel == .beta || channel == .stable else { return false }
        return candidate > current
    }
}

public struct UpdateCheckIntent {
    private var directInstall = false
    public init() {}
    public mutating func requestDirectInstall() { directInstall = true }
    public mutating func reset() { directInstall = false }
    public mutating func consumeDirectInstall() -> Bool {
        defer { reset() }
        return directInstall
    }
}
