import Foundation

public struct TargetPromptMatcher: Sendable {
    public static let targetBundleIdentifier = "now.typeless.desktop"
    public static let targetCardRole = "AXUserInterfaceTooltip"
    public static let targetTitle = "Upgrade for enhanced accuracy"

    public static let targetCardRoles: Set<String> = [
        targetCardRole,
        "AXDialog",
        "AXPopover",
        "AXSheet",
    ]

    public static let targetCardSubroles: Set<String> = [
        "AXApplicationDialog",
        "AXDialog",
        "AXPopover",
        "AXSystemDialog",
    ]

    public static let targetTexts: Set<String> = [
        targetTitle,
        "Get unlimited words",
        "Get unlimited words, enhanced accuracy, and priority access during high demand.",
        "获取无限字数",
        "获取无限字数、增强的准确性，以及在高需求期间的优先访问权。",
        "獲取無限字數",
        "獲得無限制的字數、提升的準確性，以及在需求高峰期間的優先訪問權限。",
        "獲得無限字數、提升準確性，並在需求高峰時享有優先訪問權。",
    ]

    private let minimumButtonEdge = 14.0
    private let maximumLegacyButtonEdge = 20.0
    private let maximumSemanticButtonEdge = 44.0
    private let containmentTolerance = 1.0
    private let maximumTopInset = 32.0

    private let semanticCloseNames: Set<String> = [
        "cancel",
        "close",
        "dismiss",
        "关闭",
        "關閉",
    ]

    private let semanticCloseSubroles: Set<String> = [
        "AXCancelButton",
        "AXCloseButton",
    ]

    public init() {}

    public func decision(for cards: [AXNodeSnapshot]) -> MatchDecision {
        let targetCards = cards.enumerated().filter { _, card in
            guard Self.isTargetCardContainer(role: card.role, subrole: card.subrole) else {
                return false
            }
            return containsTargetText(card)
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

    public static func isTargetCardContainer(role: String?, subrole: String?) -> Bool {
        role.map(targetCardRoles.contains) == true
            || subrole.map(targetCardSubroles.contains) == true
    }

    private func containsTargetText(_ node: AXNodeSnapshot) -> Bool {
        let values = [node.title, node.value, node.elementDescription, node.help]
        if values.contains(where: isExactTargetText) {
            return true
        }
        return node.children.contains(where: containsTargetText)
    }

    private func isExactTargetText(_ value: String?) -> Bool {
        guard let value else { return false }
        return Self.targetTexts.contains(
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
              node.actions.contains("AXPress"),
              let button = node.frame,
              hasEligibleButtonSize(node, frame: button),
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

    private func hasEligibleButtonSize(_ node: AXNodeSnapshot, frame: AXFrame) -> Bool {
        let hasSemanticIdentity = hasSemanticCloseIdentity(node)
        let maximumEdge = hasNoAccessibleName(node) && !hasSemanticIdentity
            ? maximumLegacyButtonEdge
            : hasSemanticIdentity
                ? maximumSemanticButtonEdge
                : 0

        return maximumEdge > 0
            && (minimumButtonEdge ... maximumEdge).contains(frame.width)
            && (minimumButtonEdge ... maximumEdge).contains(frame.height)
    }

    private func hasSemanticCloseIdentity(_ node: AXNodeSnapshot) -> Bool {
        if node.subrole.map(semanticCloseSubroles.contains) == true {
            return true
        }

        let values = [
            node.title,
            node.elementDescription,
            node.help,
            node.identifier,
            node.domIdentifier,
        ] + node.domClassList.map(Optional.some)

        return values.contains { value in
            guard let value else { return false }
            return semanticTokens(in: value).contains { semanticCloseNames.contains($0) }
        }
    }

    private func semanticTokens(in value: String) -> Set<String> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var camelCaseSeparated = ""
        var previousWasLowercaseOrNumber = false
        for character in trimmed {
            if character.isUppercase && previousWasLowercaseOrNumber {
                camelCaseSeparated.append(" ")
            }
            camelCaseSeparated.append(character)
            previousWasLowercaseOrNumber = character.isLowercase || character.isNumber
        }

        let normalized = camelCaseSeparated.lowercased()
        if semanticCloseNames.contains(normalized) {
            return [normalized]
        }

        return Set(normalized.split { character in
            !character.isLetter && !character.isNumber
        }.map(String.init))
    }

    private func isContained(_ child: AXFrame, in parent: AXFrame) -> Bool {
        child.minX >= parent.minX - containmentTolerance
            && child.minY >= parent.minY - containmentTolerance
            && child.maxX <= parent.maxX + containmentTolerance
            && child.maxY <= parent.maxY + containmentTolerance
    }
}
