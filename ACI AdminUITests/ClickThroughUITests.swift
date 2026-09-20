//
//  ClickThroughUITests.swift
//  ACI AdminUITests
//
//  Drives the click-through prototype across every screen and captures
//  a screenshot of each along the way.
//

import XCTest

final class ClickThroughUITests: XCTestCase {

    @MainActor
    func testClickThroughAllScreens() throws {
        let app = XCUIApplication()
        // Runs against in-memory fixtures with the data already loaded, so the walk
        // is hermetic and never waits on a spinner.
        app.launchArguments = ["-ui-testing"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        // ── Sign in ──
        let signIn = app.buttons["Sign in with Apple"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 8))
        snap(app, "01-sign-in")
        signIn.tap()

        // ── PIN lock ──
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 5))
        snap(app, "02-pin")
        for key in ["1", "2", "3", "4"] { app.buttons[key].tap() }

        // ── Home ──
        XCTAssertTrue(app.buttons["All notices"].waitForExistence(timeout: 5))
        snap(app, "03-home")

        // ── Notices + compose ──
        tab(app, "notices")
        let newNotification = app.buttons["New notification"]
        XCTAssertTrue(newNotification.waitForExistence(timeout: 5))
        snap(app, "04-notices")
        newNotification.tap()
        XCTAssertTrue(app.buttons["Save draft"].waitForExistence(timeout: 5))
        snap(app, "05-compose-notice")
        back(app)

        // ── Recurring: composer, schedule, skip sheet ──
        tab(app, "recurring")
        let newRule = app.buttons["New recurring notice"]
        XCTAssertTrue(newRule.waitForExistence(timeout: 5))
        snap(app, "06-recurring")
        newRule.tap()
        XCTAssertTrue(app.buttons["Save paused"].waitForExistence(timeout: 5))
        snap(app, "07-rule-composer")
        back(app)

        let schedule = app.buttons["Schedule"].firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        let skip = app.buttons["Skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        snap(app, "08-schedule")
        skip.tap()
        let keep = app.buttons["Keep it scheduled"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        snap(app, "09-skip-sheet")
        keep.tap()
        sleep(1)
        back(app)

        // ── Events + editor ──
        tab(app, "events")
        let event = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Night of Worship")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        snap(app, "10-events")
        event.tap()
        XCTAssertTrue(app.buttons["Unpublish event"].waitForExistence(timeout: 5))
        snap(app, "11-event-editor")
        back(app)

        // ── Review queue + item ──
        tab(app, "review")
        // The queue is keyed by day, not by devotional title: the status endpoint
        // reports dates and review states, and the title only arrives when a day
        // is opened.
        // Match the card's own eyebrow, not its day: "Today" also labels a tab,
        // and the tab bar wins firstMatch.
        let item = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "daily devotion")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        snap(app, "12-review-queue")
        item.tap()
        let approve = app.buttons["Approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        snap(app, "13-review-item")

        // A devotional is several recordings, not one: the narration, the
        // declarations and one file per prayer, each pickable on its own.
        let narration = app.buttons["Narration"]
        XCTAssertTrue(narration.waitForExistence(timeout: 5))
        scrollTo(app, narration)
        for track in ["Narration", "Declarations", "Prayer 1", "Prayer 5", "Music bed"] {
            XCTAssertTrue(app.buttons[track].exists, "missing audio track: \(track)")
        }
        snap(app, "13b-review-audio")
        // The review item is a long screen; the actions sit below the fold and
        // XCUITest never scrolls on its own.
        scrollTo(app, approve)
        approve.tap()
        XCTAssertTrue(
            app.staticTexts["Approved — published to readers"].waitForExistence(timeout: 5))
        snap(app, "14-review-approved-toast")
    }

    // MARK: - Helpers

    /// Swipes until the element is genuinely on screen. `tap()` on an element that
    /// is in the hierarchy but below the fold silently does nothing — and
    /// `isHittable` alone reports true for such elements, so check the frame as well.
    @MainActor
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement, tries: Int = 8) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<tries {
            guard element.exists else { return }
            let frame = element.frame
            let onScreen = window.contains(CGPoint(x: frame.midX, y: frame.midY))
            if onScreen && element.isHittable { return }
            app.swipeUp()
        }
    }

    @MainActor
    private func tab(_ app: XCUIApplication, _ id: String) {
        let button = app.buttons["tab-\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "tab \(id)")
        button.tap()
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let button = app.buttons["Back"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
