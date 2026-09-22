import XCTest

enum UITestSupport {
    /// Must match `TaskStripsApp.uiTestingArgument`.
    static let launchArgument = "-TaskStripsUITesting"
    /// Must match `TaskStripsApp.uiTestingStrips`, in board order.
    static let strips = ["Alpha strip", "Bravo strip", "Charlie strip"]
    /// Must match `TaskStripsApp.uiTestingLibraryFile`.
    static let libraryFile = "Seeded receipt.pdf"
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

    /// Scoped to one menu on purpose: several titles (Delete, most obviously) appear in more than
    /// one menu, and an app-wide lookup fails outright with "multiple matching elements".
    func menuItem(_ title: String, in menu: String) -> XCUIElement {
        menuBars.menuBarItems[menu].menus.menuItems[title]
    }

    /// macOS mirrors alert buttons onto the Touch Bar, and an unscoped lookup will happily hand
    /// back that copy — which then refuses to be clicked: "cannot be called with Touch Bar
    /// elements". Scoped to whatever is actually presenting the dialog.
    func confirmationButton(_ title: String) -> XCUIElement {
        let inSheet = sheets.buttons[title].firstMatch
        if inSheet.exists { return inSheet }
        let inDialog = dialogs.buttons[title].firstMatch
        if inDialog.exists { return inDialog }
        return windows.buttons[title].firstMatch
    }

    /// Scoped for the same reason `confirmationButton` is: macOS mirrors buttons onto the Touch
    /// Bar, so an app-wide lookup can match the same button twice and fail with "multiple
    /// matching elements" before it ever gets as far as clicking.
    func windowButton(_ title: String) -> XCUIElement {
        let inSheet = sheets.buttons[title].firstMatch
        if inSheet.exists { return inSheet }
        return windows.buttons[title].firstMatch
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
    ///
    /// Looks each title up by name rather than enumerating `staticTexts` — the enumeration came
    /// back empty on CI even with the rows plainly on screen and clickable, while the by-name
    /// lookup `stripRow(titled:)` uses resolved them fine.
    func boardTitles() -> [String] {
        UITestSupport.strips
            .map { $0.uppercased() }
            .compactMap { title -> (title: String, top: CGFloat)? in
                let element = staticTexts[title]
                guard element.exists else { return nil }
                return (title, element.frame.minY)
            }
            .sorted { $0.top < $1.top }
            .map(\.title)
    }

    /// Polls rather than asserting once: a reorder repaints a frame or two after the click.
    @discardableResult
    func waitForBoard(_ expected: [String], timeout: TimeInterval = UITestSupport.timeout) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if boardTitles() == expected { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }
}
