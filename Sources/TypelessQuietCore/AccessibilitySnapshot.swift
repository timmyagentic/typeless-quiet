import Foundation

public struct AXFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public struct AXNodePath: Hashable, Sendable {
    public let components: [Int]

    public init(_ components: [Int] = []) {
        self.components = components
    }

    public func appending(_ component: Int) -> AXNodePath {
        AXNodePath(components + [component])
    }
}

public struct AXNodeSnapshot: Equatable, Sendable {
    public let role: String?
    public let subrole: String?
    public let title: String?
    public let value: String?
    public let elementDescription: String?
    public let help: String?
    public let identifier: String?
    public let domIdentifier: String?
    public let domClassList: Set<String>
    public let frame: AXFrame?
    public let actions: Set<String>
    public let children: [AXNodeSnapshot]

    public init(
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        elementDescription: String? = nil,
        help: String? = nil,
        identifier: String? = nil,
        domIdentifier: String? = nil,
        domClassList: Set<String> = [],
        frame: AXFrame? = nil,
        actions: Set<String> = [],
        children: [AXNodeSnapshot] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.elementDescription = elementDescription
        self.help = help
        self.identifier = identifier
        self.domIdentifier = domIdentifier
        self.domClassList = domClassList
        self.frame = frame
        self.actions = actions
        self.children = children
    }
}

public enum UnsafeMatchReason: String, Equatable, Sendable {
    case multipleTargetCards
    case missingCardFrame
    case noEligibleCloseButton
    case multipleEligibleCloseButtons
}

public enum MatchDecision: Equatable, Sendable {
    case noTarget
    case unsafe(UnsafeMatchReason)
    case dismiss(cardIndex: Int, buttonPath: AXNodePath)
}
