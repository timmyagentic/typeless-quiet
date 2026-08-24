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

    func testIgnoresExactTextWhenContainerRoleIsNotTooltip() {
        let card = targetCard(role: "AXGroup", buttons: [eligibleButton()])
        XCTAssertEqual(matcher.decision(for: [card]), .noTarget)
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

    func testRejectsNamedButton() {
        let button = AXNodeSnapshot(
            role: "AXButton",
            title: "Close",
            frame: AXFrame(x: 392, y: 208, width: 16, height: 16),
            actions: ["AXPress"]
        )
        XCTAssertEqual(
            matcher.decision(for: [targetCard(buttons: [button])]),
            .unsafe(.noEligibleCloseButton)
        )
    }

    func testRejectsButtonWithAccessibleHelpName() {
        let button = AXNodeSnapshot(
            role: "AXButton",
            help: "Dismiss",
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
        title: String = "Upgrade for enhanced accuracy",
        buttons: [AXNodeSnapshot]
    ) -> AXNodeSnapshot {
        AXNodeSnapshot(
            role: role,
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
}
