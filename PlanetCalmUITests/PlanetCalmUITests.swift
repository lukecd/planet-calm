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

    func testSunriseAuditPortrait() throws {
        captureSunriseAudit(orientation: .portrait, name: "portrait")
    }

    func testSunriseAuditLandscape() throws {
        captureSunriseAudit(orientation: .landscapeLeft, name: "landscape")
    }

    private func captureSunriseAudit(orientation: UIDeviceOrientation, name: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--sunrise-audit"]
        app.launch()
        XCUIDevice.shared.orientation = orientation
        let advance = app.buttons["sunriseAuditNext"]
        XCTAssertTrue(advance.waitForExistence(timeout: 8))
        for index in 0...20 {
            XCTAssertEqual(advance.value as? String, String(index))
            // Rendering settles while the canonical review state is frozen.
            Thread.sleep(forTimeInterval: 0.8)
            let screenshot = XCUIScreen.main.screenshot()
            if index == 20 {
                // Detect the ink fallback: passing timing tests alone does not prove
                // that Metal compiled, loaded its grain, and rendered daylight.
                let pixels = 64
                var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
                let context = CGContext(data: &bytes, width: pixels, height: pixels,
                    bitsPerComponent: 8, bytesPerRow: pixels * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(screenshot.image.cgImage!, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
                let goldPixels = stride(from: 0, to: bytes.count, by: 4).filter {
                    bytes[$0] > 180 && bytes[$0 + 1] > 130 && bytes[$0 + 2] < 180
                }.count
                XCTAssertGreaterThan(Double(goldPixels) / Double(pixels * pixels), 0.35)
            }
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = String(format: "sunrise-%@-%03d", name, index * 5)
            attachment.lifetime = .keepAlways
            add(attachment)
            if index < 20 { advance.tap() }
        }
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

        let start = app.buttons["Start"]
        let stories = app.buttons["Stories"]
        let stats = app.buttons["Stats"]
        let settings = app.buttons["Settings"]

        XCTAssertTrue(waitUntilHittable(stories, timeout: 6))

        stats.tap()
        settings.tap()
        start.tap()

        XCTAssertFalse(app.staticTexts["Choose a story"].exists)

        stories.tap()
        XCTAssertFalse(app.staticTexts["Choose a story"].waitForExistence(timeout: 0.30))
        XCTAssertTrue(app.staticTexts["Choose a story"].waitForExistence(timeout: 3))
    }

    func testStoryChooserLaunchesBothScenes() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let stories = app.buttons["Stories"]
        XCTAssertTrue(waitUntilHittable(stories, timeout: 6))
        stories.tap()
        XCTAssertTrue(app.staticTexts["Choose a story"].waitForExistence(timeout: 3))

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

    private func waitUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return element.isHittable && element.isEnabled
            },
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
        Thread.sleep(forTimeInterval: 4.7)

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
