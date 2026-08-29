import XCTest

enum UITestSupport {
    /// Must match `TaskStripsApp.uiTestingArgument`.
    static let launchArgument = "-TaskStripsUITesting"
    /// Must match `TaskStripsApp.uiTestingStrips`, in board order.
    static let strips = ["Alpha strip", "Bravo strip", "Charlie strip"]
    static let timeout: TimeInterval = 15
}

extension XCUIApplication {
    // MARK: - Menus

    func openMenu(_ title: String) {
        let item = menuBars.menuBarItems[title]
        XCTAssertTrue(
            item.waitForExistence(timeout: UITestSupport.timeout),
            "there is no \"\(title)\" menu in the menu bar"
        )
        item.click()
    }

    func closeMenu() {
        typeKey(.escape, modifierFlags: [])
    }

    func menuItem(_ title: String) -> XCUIElement {
        menuBars.menuItems[title]
    }

    // MARK: - The board

    /// Rows show their title uppercased — see TaskRowView.
    func stripRow(titled title: String) -> XCUIElement {
        let element = staticTexts[title.uppercased()]
        XCTAssertTrue(
            element.waitForExistence(timeout: UITestSupport.timeout),
            "no row on the board titled \"\(title)\""
        )
        return element
    }

    func selectStrip(atRowTitled title: String) {
        stripRow(titled: title).click()
    }

    /// The seeded strips currently on the board, top to bottom.
    func boardTitles() -> [String] {
        let known = Set(UITestSupport.strips.map { $0.uppercased() })
        return staticTexts.allElementsBoundByIndex
            .filter { known.contains($0.label) }
            .sorted { $0.frame.minY < $1.frame.minY }
            .map(\.label)
    }

    /// Polls rather than asserting once: a reorder repaints a frame or two after the click.
    @discardableResult
    func waitForBoard(_ expected: [String], timeout: TimeInterval = UITestSupport.timeout) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if boardTitles() == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }
}
