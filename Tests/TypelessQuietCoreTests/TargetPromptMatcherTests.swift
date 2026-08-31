import XCTest
@testable import TypelessQuietCore

final class TargetPromptMatcherTests: XCTestCase {
    private let matcher = TargetPromptMatcher()
    private let cardFrame = AXFrame(x: 100, y: 200, width: 320, height: 120)

    func testDismissesOnlyUniqueUnnamedPressableButtonAtTargetCardTopRight() {
        let card = targetCard(buttons: [eligibleButton()])

        XCTAssertEqual(
            matcher.decision(for: [card]),
            .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 0]))
        )
    }

    func testFindsExactTitleInDescendantStaticText() {
        let card = AXNodeSnapshot(
            role: "AXUserInterfaceTooltip",
            frame: cardFrame,
            children: [
                AXNodeSnapshot(
                    role: "AXGroup",
                    children: [
                        AXNodeSnapshot(
                            role: "AXStaticText",
                            value: "  Upgrade for enhanced accuracy  "
                        ),
                    ]
                ),
                eligibleButton(),
            ]
        )

        XCTAssertEqual(
            matcher.decision(for: [card]),
            .dismiss(cardIndex: 0, buttonPath: AXNodePath([1]))
        )
    }

    func testDismissesTypeless240EnglishTooltipUsingSemanticCloseButton() {
        let card = targetCard(
            title: "Get unlimited words",
            buttons: [semanticCloseButton(title: "Close")]
        )

        XCTAssertEqual(
            matcher.decision(for: [card]),
            .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 0]))
        )
    }

    func testDismissesTypeless240ChineseTooltipUsingSemanticCloseButton() {
        let card = targetCard(
            title: "获取无限字数",
            buttons: [semanticCloseButton(description: "关闭")]
        )

        XCTAssertEqual(
            matcher.decision(for: [card]),
            .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 0]))
        )
    }

    func testDismissesTypeless240DialogUsingExactDescription() {
        let card = targetCard(
            role: "AXDialog",
            title: "Get unlimited words, enhanced accuracy, and priority access during high demand.",
            buttons: [semanticCloseButton(help: "Dismiss")]
        )

        XCTAssertEqual(
            matcher.decision(for: [card]),
            .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 0]))
        )
    }

    func testDismissesTypeless240ApplicationDialogUsingDOMDismissIdentifier() {
        let card = targetCard(
            role: "AXGroup",
            subrole: "AXApplicationDialog",
            title: "获取无限字数",
            buttons: [semanticCloseButton(domIdentifier: "dismiss-subscription-prompt")]
        )

        XCTAssertEqual(
            matcher.decision(for: [card]),
            .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 0]))
        )
    }

    func testDismissesTypeless240UsingCamelCaseCloseIdentifier() {
        let card = targetCard(
            title: "Get unlimited words",
            buttons: [semanticCloseButton(domIdentifier: "subscriptionCloseButton")]
        )

        XCTAssertEqual(
            matcher.decision(for: [card]),
            .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 0]))
        )
    }

    func testDismissesTypeless240NativeCloseSubroleAtModernButtonSize() {
        let card = targetCard(
            title: "Get unlimited words",
            buttons: [semanticCloseButton(subrole: "AXCloseButton")]
        )

        XCTAssertEqual(
            matcher.decision(for: [card]),
            .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 0]))
        )
    }

    func testRecognizesEveryVersionedTargetText() {
        for targetText in TargetPromptMatcher.targetTexts.sorted() {
            XCTAssertEqual(
                matcher.decision(for: [
                    targetCard(title: targetText, buttons: [eligibleButton()]),
                ]),
                .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 0])),
                "Expected exact target text to match: \(targetText)"
            )
        }
    }

    func testRecognizesEverySupportedTransientContainerRole() {
        for role in TargetPromptMatcher.targetCardRoles.sorted() {
            XCTAssertEqual(
                matcher.decision(for: [
                    targetCard(role: role, buttons: [eligibleButton()]),
                ]),
                .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 0])),
                "Expected transient container role to match: \(role)"
            )
        }
    }

    func testIgnoresDifferentTooltipTitle() {
        let card = targetCard(title: "A new version is available", buttons: [eligibleButton()])
        XCTAssertEqual(matcher.decision(for: [card]), .noTarget)
    }

    func testRejectsTitleThatOnlyContainsTargetAsSubstring() {
        let card = targetCard(
            title: "Upgrade for enhanced accuracy today",
            buttons: [eligibleButton()]
        )
        XCTAssertEqual(matcher.decision(for: [card]), .noTarget)
    }

    func testRejectsTypeless240TitleThatOnlyContainsTargetAsSubstring() {
        let card = targetCard(
            title: "Get unlimited words today",
            buttons: [semanticCloseButton(title: "Close")]
        )
        XCTAssertEqual(matcher.decision(for: [card]), .noTarget)
    }

    func testIgnoresTypeless240PersistentSubscriptionCard() {
        let upgradeButton = AXNodeSnapshot(
            role: "AXButton",
            title: "升级",
            frame: AXFrame(x: 124, y: 276, width: 160, height: 40),
            actions: ["AXPress"]
        )
        let card = targetCard(
            role: "AXGroup",
            title: "获取无限字数",
            buttons: [upgradeButton]
        )
        XCTAssertEqual(matcher.decision(for: [card]), .noTarget)
    }

    func testRejectsTypeless240TooltipWithOnlyUpgradeButton() {
        let upgradeButton = AXNodeSnapshot(
            role: "AXButton",
            title: "Upgrade",
            frame: AXFrame(x: 280, y: 268, width: 120, height: 40),
            actions: ["AXPress"]
        )

        XCTAssertEqual(
            matcher.decision(for: [
                targetCard(title: "Get unlimited words", buttons: [upgradeButton]),
            ]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testRejectsTypeless240UpgradeDOMIdentifierAsCloseIdentity() {
        XCTAssertEqual(
            matcher.decision(for: [
                targetCard(
                    title: "Get unlimited words",
                    buttons: [semanticCloseButton(domIdentifier: "upgrade-subscription")]
                ),
            ]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testRejectsOversizedSemanticCloseButton() {
        XCTAssertEqual(
            matcher.decision(for: [
                targetCard(
                    title: "获取无限字数",
                    buttons: [semanticCloseButton(title: "关闭", edge: 48)]
                ),
            ]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testAllowsUnrelatedTooltipBesideUniqueTarget() {
        let update = targetCard(title: "A new version is available", buttons: [eligibleButton()])
        let target = targetCard(buttons: [eligibleButton()])

        XCTAssertEqual(
            matcher.decision(for: [update, target]),
            .dismiss(cardIndex: 1, buttonPath: AXNodePath([1, 0]))
        )
    }

    func testFailsClosedForMultipleTargetCards() {
        XCTAssertEqual(
            matcher.decision(for: [
                targetCard(buttons: [eligibleButton()]),
                targetCard(buttons: [eligibleButton()]),
            ]),
            .unsafe(.multipleTargetCards)
        )
    }

    func testFailsClosedWhenCardFrameIsMissing() {
        let card = AXNodeSnapshot(
            role: "AXUserInterfaceTooltip",
            children: [targetText(), eligibleButton()]
        )
        XCTAssertEqual(matcher.decision(for: [card]), .unsafe(.missingCardFrame))
    }

    func testRejectsNonDismissNamedButton() {
        let button = AXNodeSnapshot(
            role: "AXButton",
            title: "Learn more",
            frame: AXFrame(x: 392, y: 208, width: 16, height: 16),
            actions: ["AXPress"]
        )
        XCTAssertEqual(
            matcher.decision(for: [targetCard(buttons: [button])]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testRejectsButtonWithNonDismissHelpName() {
        let button = AXNodeSnapshot(
            role: "AXButton",
            help: "Open pricing",
            frame: AXFrame(x: 392, y: 208, width: 16, height: 16),
            actions: ["AXPress"]
        )
        XCTAssertEqual(
            matcher.decision(for: [targetCard(buttons: [button])]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testRejectsWrongButtonSize() {
        let button = AXNodeSnapshot(
            role: "AXButton",
            frame: AXFrame(x: 384, y: 208, width: 24, height: 24),
            actions: ["AXPress"]
        )
        XCTAssertEqual(
            matcher.decision(for: [targetCard(buttons: [button])]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testRejectsButtonOutsideTopRightRegion() {
        let button = AXNodeSnapshot(
            role: "AXButton",
            frame: AXFrame(x: 112, y: 286, width: 16, height: 16),
            actions: ["AXPress"]
        )
        XCTAssertEqual(
            matcher.decision(for: [targetCard(buttons: [button])]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testRejectsTopRightButtonThatExtendsOutsideCard() {
        let button = AXNodeSnapshot(
            role: "AXButton",
            frame: AXFrame(x: 410, y: 198, width: 16, height: 16),
            actions: ["AXPress"]
        )
        XCTAssertEqual(
            matcher.decision(for: [targetCard(buttons: [button])]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testRejectsButtonWithoutPressAction() {
        let button = AXNodeSnapshot(
            role: "AXButton",
            frame: AXFrame(x: 392, y: 208, width: 16, height: 16)
        )
        XCTAssertEqual(
            matcher.decision(for: [targetCard(buttons: [button])]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testFailsClosedForMultipleEligibleButtons() {
        let first = eligibleButton(x: 392)
        let second = eligibleButton(x: 368)

        XCTAssertEqual(
            matcher.decision(for: [targetCard(buttons: [first, second])]),
            .unsafe(.multipleEligibleCloseButtons)
        )
    }

    func testIgnoresUnrelatedButtonsWhenExactlyOneCandidateIsEligible() {
        let namedButton = AXNodeSnapshot(
            role: "AXButton",
            title: "Learn more",
            frame: AXFrame(x: 280, y: 280, width: 100, height: 24),
            actions: ["AXPress"]
        )

        XCTAssertEqual(
            matcher.decision(for: [targetCard(buttons: [namedButton, eligibleButton()])]),
            .dismiss(cardIndex: 0, buttonPath: AXNodePath([1, 1]))
        )
    }

    private func targetCard(
        role: String = "AXUserInterfaceTooltip",
        subrole: String? = nil,
        title: String = "Upgrade for enhanced accuracy",
        buttons: [AXNodeSnapshot]
    ) -> AXNodeSnapshot {
        AXNodeSnapshot(
            role: role,
            subrole: subrole,
            frame: cardFrame,
            children: [targetText(title), AXNodeSnapshot(role: "AXGroup", children: buttons)]
        )
    }

    private func targetText(_ value: String = "Upgrade for enhanced accuracy") -> AXNodeSnapshot {
        AXNodeSnapshot(role: "AXStaticText", value: value)
    }

    private func eligibleButton(x: Double = 392) -> AXNodeSnapshot {
        AXNodeSnapshot(
            role: "AXButton",
            frame: AXFrame(x: x, y: 208, width: 16, height: 16),
            actions: ["AXPress"]
        )
    }

    private func semanticCloseButton(
        subrole: String? = nil,
        title: String? = nil,
        description: String? = nil,
        help: String? = nil,
        domIdentifier: String? = nil,
        edge: Double = 32
    ) -> AXNodeSnapshot {
        AXNodeSnapshot(
            role: "AXButton",
            subrole: subrole,
            title: title,
            elementDescription: description,
            help: help,
            domIdentifier: domIdentifier,
            frame: AXFrame(x: 380, y: 204, width: edge, height: edge),
            actions: ["AXPress"]
        )
    }
}
