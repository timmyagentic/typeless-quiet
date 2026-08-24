import Foundation

public struct TargetPromptMatcher: Sendable {
    public static let targetBundleIdentifier = "now.typeless.desktop"
    public static let targetCardRole = "AXUserInterfaceTooltip"
    public static let targetTitle = "Upgrade for enhanced accuracy"

    private let minimumButtonEdge = 14.0
    private let maximumButtonEdge = 20.0
    private let containmentTolerance = 1.0
    private let maximumTopInset = 32.0

    public init() {}

    public func decision(for cards: [AXNodeSnapshot]) -> MatchDecision {
        let targetCards = cards.enumerated().filter { _, card in
            card.role == Self.targetCardRole && containsTargetTitle(card)
        }

        guard !targetCards.isEmpty else {
            return .noTarget
        }
        guard targetCards.count == 1, let target = targetCards.first else {
            return .unsafe(.multipleTargetCards)
        }
        guard let cardFrame = target.element.frame else {
            return .unsafe(.missingCardFrame)
        }

        let eligibleButtons = descendants(of: target.element).filter { item in
            isEligibleCloseButton(item.node, inside: cardFrame)
        }

        switch eligibleButtons.count {
        case 0:
            return .unsafe(.noEligibleCloseButton)
        case 1:
            return .dismiss(
                cardIndex: target.offset,
                buttonPath: eligibleButtons[0].path
            )
        default:
            return .unsafe(.multipleEligibleCloseButtons)
        }
    }

    private func containsTargetTitle(_ node: AXNodeSnapshot) -> Bool {
        let values = [node.title, node.value, node.elementDescription, node.help]
        if values.contains(where: isExactTargetTitle) {
            return true
        }
        return node.children.contains(where: containsTargetTitle)
    }

    private func isExactTargetTitle(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) == Self.targetTitle
    }

    private func descendants(
        of node: AXNodeSnapshot,
        path: AXNodePath = AXNodePath()
    ) -> [(node: AXNodeSnapshot, path: AXNodePath)] {
        node.children.enumerated().flatMap { index, child in
            let childPath = path.appending(index)
            return [(child, childPath)] + descendants(of: child, path: childPath)
        }
    }

    private func isEligibleCloseButton(
        _ node: AXNodeSnapshot,
        inside card: AXFrame
    ) -> Bool {
        guard node.role == "AXButton",
              hasNoAccessibleName(node),
              node.actions.contains("AXPress"),
              let button = node.frame,
              (minimumButtonEdge ... maximumButtonEdge).contains(button.width),
              (minimumButtonEdge ... maximumButtonEdge).contains(button.height),
              isContained(button, in: card)
        else {
            return false
        }

        let rightInset = card.maxX - button.maxX
        let topInset = button.minY - card.minY
        let maximumRightInset = min(48.0, card.width * 0.20)
        let minimumRightRegionX = card.minX + (card.width * 0.70)

        return (-containmentTolerance ... maximumRightInset).contains(rightInset)
            && (-containmentTolerance ... maximumTopInset).contains(topInset)
            && button.minX >= minimumRightRegionX
    }

    private func hasNoAccessibleName(_ node: AXNodeSnapshot) -> Bool {
        [node.title, node.elementDescription, node.help].allSatisfy { value in
            guard let value else { return true }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func isContained(_ child: AXFrame, in parent: AXFrame) -> Bool {
        child.minX >= parent.minX - containmentTolerance
            && child.minY >= parent.minY - containmentTolerance
            && child.maxX <= parent.maxX + containmentTolerance
            && child.maxY <= parent.maxY + containmentTolerance
    }
}
