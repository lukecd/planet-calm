import XCTest

@MainActor
final class PlanetCalmUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAutumnCastReviewPortrait() throws {
        captureAutumnCastReview(orientation: .portrait, name: "actual-ipad-portrait-flock-t10")
    }

    func testAutumnCastReviewLandscape() throws {
        captureAutumnCastReview(orientation: .landscapeLeft, name: "actual-ipad-landscape-flock-t10")
    }

    func testContemporaryLotusReviewLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--contemporary-lotus-review"]
        app.launch()

        XCUIDevice.shared.orientation = .landscapeLeft
        let geometryExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let app = object as? XCUIApplication else { return false }
                return app.frame.width > app.frame.height
            },
            object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [geometryExpectation], timeout: 5), .completed)

        let stage = app.otherElements[
            "Contemporary Lotus focus story, still pond with one lotus pad"
        ]
        XCTAssertTrue(stage.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "contemporary-lotus-ipad-a16-landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSplashPortrait() throws {
        captureSplash(orientation: .portrait, name: "planet-focus-splash-portrait")
    }

    func testSplashLandscape() throws {
        captureSplash(orientation: .landscapeLeft, name: "planet-focus-splash-landscape")
    }

    func testOnlyStoriesMenuItemNavigates() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.88))
        let stories = app.coordinate(withNormalizedOffset: CGVector(dx: 0.37, dy: 0.88))
        let stats = app.coordinate(withNormalizedOffset: CGVector(dx: 0.59, dy: 0.88))
        let settings = app.coordinate(withNormalizedOffset: CGVector(dx: 0.81, dy: 0.88))

        stats.tap()
        settings.tap()
        start.tap()

        XCTAssertFalse(app.staticTexts["Choose a story"].exists)

        stories.tap()
        XCTAssertTrue(app.staticTexts["Choose a story"].waitForExistence(timeout: 5))
    }

    func testStoryChooserLaunchesBothScenes() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.37, dy: 0.88)).tap()
        XCTAssertTrue(app.staticTexts["Choose a story"].waitForExistence(timeout: 5))

        let autumn = app.buttons["story-choice-autumnTree"]
        XCTAssertTrue(autumn.waitForExistence(timeout: 5))
        autumn.tap()
        XCTAssertTrue(app.otherElements["Autumn Tree focus story"].waitForExistence(timeout: 5))

        let returnToStories = app.buttons["Stories"]
        XCTAssertTrue(returnToStories.waitForExistence(timeout: 5))
        returnToStories.tap()

        let lotus = app.buttons["story-choice-contemporaryLotus"]
        XCTAssertTrue(lotus.waitForExistence(timeout: 5))
        lotus.tap()
        XCTAssertTrue(
            app.otherElements[
                "Contemporary Lotus focus story, still pond with one lotus pad"
            ]
            .waitForExistence(timeout: 5)
        )
    }

    private func captureSplash(orientation: UIDeviceOrientation, name: String) {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = orientation

        let expectsLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let geometryExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let app = object as? XCUIApplication else { return false }
                return expectsLandscape
                    ? app.frame.width > app.frame.height
                    : app.frame.height > app.frame.width
            },
            object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [geometryExpectation], timeout: 5), .completed)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureAutumnCastReview(orientation: UIDeviceOrientation, name: String) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--autumn-cast-review",
            "--autumn-cast-mode=combined",
            "--autumn-cast-time=10",
            "--autumn-cast-paused",
            "--autumn-cast-seed=230003",
            "--autumn-cast-count=24",
            "--autumn-cast-size=14"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Autumn cast · native integration"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = orientation

        let expectsLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let geometryExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let app = object as? XCUIApplication else { return false }
                return expectsLandscape
                    ? app.frame.width > app.frame.height
                    : app.frame.height > app.frame.width
            },
            object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [geometryExpectation], timeout: 5), .completed)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
