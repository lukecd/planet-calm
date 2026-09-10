import XCTest

@MainActor
final class PlanetCalmUITests: XCTestCase {
    func testAutomaticBirdVisitWithoutDevelopmentTrigger() throws {
        try automaticBirdVisit(long: false)
    }

    func testFiftyFiveMinuteAutomaticBirdVisit() throws {
        try automaticBirdVisit(long: true)
    }

    private func automaticBirdVisit(long: Bool) throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--autumn-encounter-review", "--autumn-fresh"]
        if long { app.launchArguments.append("--encounter-long") }
        app.launch()
        let countdown = app.buttons["sessionCountdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Hide"].exists)
        let initial = countdown.value as? String
        for index in 0..<4 {
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)], timeout: 8)
            let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            picture.name = "automatic-bird-\(index)"
            picture.lifetime = .keepAlways
            add(picture)
        }
        XCTAssertNotEqual(countdown.value as? String, initial)
        app.buttons["developerControls"].tap()
        app.buttons["Autumn Tree tuning"].tap()
        app.buttons["Autumn Tree monitor"].tap()
        let summary = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Automatic birds:")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(summary.label.hasPrefix("Automatic birds: 0"))
    }

    func testDeerRestingLandscapeAndControls() throws {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--deer-study","--autumn-fresh","--deer-pose=31"]
        app.launch()
        XCTAssertTrue(app.buttons["sessionCountdown"].waitForExistence(timeout:10))
        XCUIDevice.shared.orientation = .landscapeLeft
        _ = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in false },object:nil)],timeout:2)
        let window=app.windows.firstMatch
        let display=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        if app.frame.width < app.frame.height {
            let controls=display.buttons["window-controls:com.planetcalm.app"]
            if controls.exists {
                controls.tap()
                let full=display.buttons["Zoom-button"]
                if full.exists { full.tap() }
            }
        }
        let wide = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in app.frame.width > app.frame.height },object:nil)
        let widthResult=XCTWaiter.wait(for:[wide],timeout:8)
        // Accessibility bounds update before the system rotation animation ends.
        _ = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in false },object:nil)],timeout:2)
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        image.name="deer-rest-ipad-landscape";image.lifetime = .keepAlways;add(image)
        XCTAssertEqual(widthResult,.completed)
        app.buttons["developerControls"].tap()
        XCTAssertTrue(app.buttons["autumnDeerPlay"].waitForExistence(timeout:5))
        app.buttons["autumnDeerRest"].tap()
        app.buttons["Hide"].tap()
        XCTAssertTrue(app.buttons["sessionCountdown"].isHittable)
        XCUIDevice.shared.orientation = .portrait
        _ = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in false },object:nil)],timeout:2)
        window.coordinate(withNormalizedOffset:CGVector(dx:0.99,dy:0.99))
            .press(forDuration:0.25,thenDragTo:display.coordinate(withNormalizedOffset:CGVector(dx:0.99,dy:0.99)))
    }

    func testDeerEndingNativeStudy() throws {
        let app=XCUIApplication()
        app.launchArguments=["--deer-study","--autumn-fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["sessionCountdown"].waitForExistence(timeout:10))
        let start=Date()
        for time in [2.0,5,8,12,16,18,20,22,24,26,28,31,39] {
            let wait=max(0.01,time-Date().timeIntervalSince(start))
            _ = XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in false },object:nil)],timeout:wait)
            let picture=XCTAttachment(screenshot:app.screenshot())
            picture.name="deer-study-\(Int(time))"
            picture.lifetime = .keepAlways
            add(picture)
        }
        XCTAssertEqual(app.buttons["sessionCountdown"].value as? String,"Complete")
    }

    private func pauseAutumnUsingControls(_ app: XCUIApplication) {
        app.buttons["developerControls"].tap()
        if !app.buttons["performancePauseResume"].exists { app.buttons["Autumn Tree runner"].tap() }
        let pause = app.buttons["performancePauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        XCTAssertEqual(pause.label, "Resume")
        app.buttons["Hide"].tap()
    }

    func testOrigamiFlightStudyPortrait() throws { try origamiFlightStudy(wide: false) }
    func testOrigamiFlightStudyWide() throws { try origamiFlightStudy(wide: true) }

    private func origamiFlightStudy(wide: Bool) throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--autumn-checkpoint", "--autumn-fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["autumnBirdFly"].waitForExistence(timeout: 8))
        if wide && app.frame.height > app.frame.width {
            app.buttons["Hide"].tap()
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
                .press(forDuration: 0.25, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.48)))
            let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 8), .completed)
            app.buttons["developerControls"].tap()
        }
        let controls = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        controls.name = "origami-study-controls"
        controls.lifetime = .keepAlways
        add(controls)
        app.buttons["autumnBirdFly"].tap()
        app.buttons["Hide"].tap()
        XCTAssertTrue(app.buttons["sessionCountdown"].exists)
        let start = Date()
        for target in [2.0, 3, 4, 5, 6, 7, 8, 9, 12, 16, 20, 24, 28] {
            let wait = max(0.01, target - Date().timeIntervalSince(start))
            let interval = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
            _ = XCTWaiter.wait(for: [interval], timeout: wait)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "origami-live-\(wide ? "wide" : "portrait")-\(Int(target))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        pauseAutumnUsingControls(app)
        if wide {
            let window = app.windows.firstMatch
            let display = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
                .press(forDuration: 0.25, thenDragTo: display.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99)))
        }
    }
    func testAutumnIPadWideWindow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--autumn-light-audit"]
        app.launch()
        XCTAssertTrue(app.buttons["Hide"].waitForExistence(timeout: 8))
        app.buttons["Hide"].tap()
        // iPadOS 26 can keep a window's aspect ratio when the device rotates.
        // Exercise an actual wide app window through the system resize handle.
        if app.frame.height > app.frame.width {
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
                .press(forDuration: 0.25, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.48)))
        }
        let wide = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        let result = XCTWaiter.wait(for: [wide], timeout: 8)
        print("RESIZED IPAD APP: \(app.frame)")
        let proof = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        proof.name = "ipad-wide-window-proof"
        proof.lifetime = .keepAlways
        add(proof)
        XCTAssertEqual(result, .completed)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
        _ = XCTWaiter.wait(for: [settled], timeout: 1)
        let next = app.buttons["autumnAuditNext"]
        for step in 0...20 {
            XCTAssertEqual(next.value as? String, String(format: "%.2f", Double(step) * 0.05))
            // XCTest misreports the window origin on this iPadOS version; capture
            // the display so the lower half is not cropped from the evidence.
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = String(format: "autumn-ipad-wide-window-%03d", step*5)
            attachment.lifetime = .keepAlways
            add(attachment)
            if step < 20 { next.tap() }
        }
        app.terminate()
        app.launchArguments = ["--autumn-checkpoint", "--autumn-fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["Hide"].waitForExistence(timeout: 8))
        app.buttons["Autumn Tree tuning"].tap()
        app.buttons["Autumn Tree runner"].tap()
        let run = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Run Autumn")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        app.buttons["Hide"].tap()
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertTrue(app.buttons["sessionCountdown"].exists)
        for index in 0..<17 {
            let interval = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
            _ = XCTWaiter.wait(for: [interval], timeout: 4)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "autumn-ipad-wide-motion-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        pauseAutumnUsingControls(app)
        // Restore a tall window so this check does not contaminate portrait tests.
        let window = app.windows.firstMatch
        let display = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
            .press(forDuration: 0.25, thenDragTo: display.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99)))
        let tall = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.firstMatch.frame.height > app.windows.firstMatch.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [tall], timeout: 8), .completed)
        let restored = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        restored.name = "autumn-ipad-restored-tall"
        restored.lifetime = .keepAlways
        add(restored)
    }

    func testAutumnCompleteStoryPortrait() throws { try completeAutumnStory(wide: false) }
    func testAutumnCompleteStoryWideWindow() throws { try completeAutumnStory(wide: true) }

    private func completeAutumnStory(wide: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--autumn-checkpoint", "--autumn-fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["Hide"].waitForExistence(timeout: 8))
        // Another test or user can leave iPadOS in a wide window. Normalize the
        // actual window, not just the requested device orientation.
        if app.frame.width > app.frame.height {
            let window = app.windows.firstMatch
            let display = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
                .press(forDuration: 0.25, thenDragTo: display.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99)))
        }
        app.buttons["Autumn Tree tuning"].tap()
        app.buttons["Autumn Tree runner"].tap()
        app.buttons["storyRunnerLength"].tap()
        app.buttons["1 min"].tap()
        let run = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Run Autumn")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        app.buttons["Hide"].tap()
        if wide {
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
                .press(forDuration: 0.25, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.48)))
        }
        for index in 0..<13 {
            let pause = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
            _ = XCTWaiter.wait(for: [pause], timeout: 5)
            XCTAssertEqual(app.frame.width > app.frame.height, wide)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "autumn-complete-\(wide ? "wide" : "portrait")-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(app.buttons["sessionCountdown"].value as? String, "Complete")
        if wide {
            let window = app.windows.firstMatch
            let display = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
                .press(forDuration: 0.25, thenDragTo: display.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99)))
        }
    }

    func testAutumnCleanupChooserUsesCurrentScene() throws {
        let app = XCUIApplication()
        // Obsolete lab flags must no longer divert launch away from the app.
        app.launchArguments = ["--autumn-fresh", "--story-chooser-review", "--gate5", "--autumn-cast-review"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Choose a story"].waitForExistence(timeout: 8))
        if app.buttons["Hide"].exists { app.buttons["Hide"].tap() }
        let thumbnail = app.buttons["story-choice-autumnTree"]
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        let chooser = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        chooser.name = "autumn-cleanup-current-tree-thumbnail"
        chooser.lifetime = .keepAlways
        add(chooser)
        thumbnail.tap()
        XCTAssertTrue(app.otherElements["Autumn Tree focus story"].waitForExistence(timeout: 8))
        let scene = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        scene.name = "autumn-cleanup-current-scene-from-chooser"
        scene.lifetime = .keepAlways
        add(scene)
    }

    func testAutumnCheckpointLightPortrait() throws { try autumnLightAudit(landscape: false) }
    func testAutumnCheckpointLightLandscape() throws { try autumnLightAudit(landscape: true) }

    private func autumnLightAudit(landscape: Bool) throws {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--autumn-light-audit"] + (landscape ? ["--autumn-landscape"] : [])
        app.launch()
        XCTAssertTrue(app.otherElements["Autumn Tree focus story"].waitForExistence(timeout: 8))
        if app.buttons["Hide"].exists { app.buttons["Hide"].tap() }
        let next = app.buttons["autumnAuditNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        if landscape {
            XCUIDevice.shared.orientation = .portrait
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
            XCTAssertGreaterThan(app.frame.width, app.frame.height)
        }
        else { XCTAssertGreaterThan(app.frame.height, app.frame.width) }
        for step in 0...20 {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = String(format: "autumn-%@-%03d", landscape ? "landscape" : "portrait", step * 5)
            attachment.lifetime = .keepAlways
            add(attachment)
            if step < 20 { next.tap() }
        }
    }

    func testAutumnCheckpointLiveMotion() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--autumn-checkpoint", "--autumn-fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["Hide"].waitForExistence(timeout: 8))
        app.buttons["Autumn Tree tuning"].tap()
        app.buttons["Autumn Tree runner"].tap()
        let run = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Run Autumn")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        app.buttons["Hide"].tap()
        // Cover all three spatially distinct gusts and the resulting leaf carpet.
        for index in 0..<27 {
            let pause = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
            _ = XCTWaiter.wait(for: [pause], timeout: 4)
            XCTAssertGreaterThan(app.windows.firstMatch.frame.height, app.windows.firstMatch.frame.width,
                "Portrait motion review was interrupted by a device/window rotation.")
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "autumn-motion-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        pauseAutumnUsingControls(app)
        let frozen = app.screenshot().pngRepresentation
        let pause = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
        _ = XCTWaiter.wait(for: [pause], timeout: 2)
        // Exact image assertion is inappropriate with a live status-bar clock; physics
        // equality is covered by the model test.
        XCTAssertFalse(frozen.isEmpty)
        XCTAssertFalse(app.buttons["Resume"].exists)
    }

    func testAutumnCheckpointPlaybackControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--autumn-light-audit"]
        app.launch()
        XCTAssertTrue(app.buttons["Hide"].waitForExistence(timeout: 8))
        app.buttons["Hide"].tap()
        let play = app.buttons["sessionBegin"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.buttons["sessionCountdown"].exists)
        pauseAutumnUsingControls(app)
        app.buttons["developerControls"].tap()
        XCTAssertTrue(app.buttons["Autumn Tree runner"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "autumn-paused-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSessionCancelBackgroundAndNoRestoration() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--session-ui-review", "--autumn-fresh"]
        app.launch()
        let begin = app.buttons["sessionBegin"]
        let exit = app.buttons["sessionCountdown"]
        let timer = app.buttons["sessionCountdown"]
        XCTAssertTrue(begin.waitForExistence(timeout: 8))
        XCTAssertEqual(begin.value as? String, "5 minutes")
        begin.tap()
        XCTAssertTrue(exit.exists)
        XCTAssertFalse(app.buttons["Pause"].exists)
        XCTAssertFalse(app.buttons["Stories"].exists)
        XCTAssertFalse(begin.exists)
        exit.tap()
        XCTAssertTrue(app.alerts["End this session?"].waitForExistence(timeout: 3))
        app.buttons["Keep focusing"].tap()
        func seconds(_ value: String) -> Int {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
        }
        let before = seconds(timer.value as? String ?? "")
        XCUIDevice.shared.press(.home)
        let interval = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
        _ = XCTWaiter.wait(for: [interval], timeout: 3)
        app.activate()
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        XCTAssertLessThan(seconds(timer.value as? String ?? ""), before)
        let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picture.name = "focus-session-phone-running"
        picture.lifetime = .keepAlways
        add(picture)
        exit.tap()
        app.alerts["End this session?"].buttons["End session"].tap()
        XCTAssertTrue(app.staticTexts["Choose a story"].waitForExistence(timeout: 5))
        app.buttons["story-choice-autumnTree"].tap()
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        XCTAssertEqual(begin.value as? String, "5 minutes")
        begin.tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 8))
        XCTAssertFalse(timer.exists)
        XCTAssertFalse(exit.exists)
    }

    func testSessionCompletionHoldsEnding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--session-ending-review", "--autumn-fresh"]
        app.launch()
        let done = app.buttons["sessionCountdown"]
        let completion = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            done.exists && done.value as? String == "Complete"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completion], timeout: 10), .completed)
        XCTAssertEqual(done.value as? String, "Complete")
        XCTAssertFalse(app.buttons["Again"].exists)
        XCTAssertFalse(app.buttons["sessionBegin"].exists)
        let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picture.name = "focus-session-complete"
        picture.lifetime = .keepAlways
        add(picture)
        done.tap()
        XCTAssertTrue(app.staticTexts["Choose a story"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["End this session?"].exists)
    }

    func testSceneSettingsAndHandwrittenStart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--session-ui-review", "--autumn-fresh"]
        app.launch()
        let begin = app.buttons["sessionBegin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 8))
        XCTAssertEqual(begin.value as? String, "5 minutes")
        XCTAssertFalse(app.staticTexts["sessionDuration"].exists)
        XCTAssertFalse(app.otherElements["sessionDurationSlider"].exists)
        let settings = app.buttons["sceneSettings"]
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        let label = app.staticTexts["sessionDuration"]
        XCTAssertTrue(label.waitForExistence(timeout: 8))
        let slider = app.descendants(matching: .any).matching(identifier: "sessionDurationSlider").firstMatch
        XCTAssertTrue(slider.exists)
        XCTAssertTrue(slider.isEnabled)
        for (x, expected) in [(0.99, "55 minutes"), (0.01, "5 minutes"), (0.5, "30 minutes")] {
            slider.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.35)).tap()
            XCTAssertEqual(label.value as? String, expected)
        }
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.35)))
        XCTAssertEqual(label.value as? String, "55 minutes")
        label.tap()
        XCTAssertFalse(app.alerts["How many minutes?"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Change time"].exists)
        // Exercise the wider five-minute landing zones and deliberate neighboring values.
        for (raw, expected) in [(14.4, 15), (15.6, 15), (14.0, 14), (16.0, 16), (23.0, 23), (17.0, 17)] {
            let x = (16 + (raw - 5) / 50 * (slider.frame.width - 32)) / slider.frame.width
            slider.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.35)).tap()
            XCTAssertEqual(label.value as? String, "\(expected) minutes")
        }
        XCTAssertEqual(label.value as? String, "17 minutes")
        let volume = app.sliders["sceneVolume"]
        volume.adjust(toNormalizedSliderPosition: 0.3)
        let savedVolume = volume.value as? String
        XCTAssertNotEqual(savedVolume, "65 percent")
        app.scrollViews.firstMatch.swipeUp()
        let mute = app.switches["sceneMute"]
        XCTAssertTrue(mute.isHittable)
        mute.tap()
        XCTAssertEqual(mute.value as? String, "1")
        let panel = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        panel.name = "scene-settings-phone"
        panel.lifetime = .keepAlways
        add(panel)
        app.buttons["sceneSettingsDone"].tap()
        XCTAssertEqual(begin.value as? String, "17 minutes")
        let setup = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        setup.name = "handwritten-start-phone"
        setup.lifetime = .keepAlways
        add(setup)
        app.buttons["sessionBegin"].tap()
        let timer = app.buttons["sessionCountdown"]
        XCTAssertTrue(timer.waitForExistence(timeout: 3))
        XCTAssertTrue((timer.value as? String ?? "").hasPrefix("16:") || timer.value as? String == "17:00")
        XCTAssertFalse(label.exists)
        XCTAssertFalse(slider.exists)
        XCTAssertFalse(app.buttons["sessionBegin"].exists)
        XCTAssertFalse(app.buttons["sessionBack"].exists)
        settings.tap()
        XCTAssertTrue(slider.exists)
        XCTAssertFalse(slider.isEnabled)
        XCTAssertEqual(label.value as? String, "17 minutes")
        XCTAssertTrue(app.staticTexts["Duration is fixed for this session."].exists)
        let frozenChoice = label.value as? String
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.35)).tap()
        XCTAssertEqual(label.value as? String, frozenChoice)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertEqual(volume.value as? String, savedVolume)
        mute.tap()
        XCTAssertEqual(mute.value as? String, "0")
        XCTAssertTrue(volume.isEnabled)
        app.buttons["sceneSettingsDone"].tap()
        let running = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        running.name = "paper-countdown-phone"
        running.lifetime = .keepAlways
        add(running)
        timer.tap()
        XCTAssertTrue(app.alerts["End this session?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep focusing"].tap()
        XCTAssertTrue(timer.exists)
    }

    func testSessionIPadTallAndWideHeader() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--session-ui-review", "--autumn-fresh"]
        app.launch()
        XCTAssertTrue(app.buttons["sessionBegin"].waitForExistence(timeout: 8))
        let window = app.windows.firstMatch
        let display = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if app.frame.width > app.frame.height {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
                .press(forDuration: 0.25, thenDragTo: display.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99)))
        }
        for wide in [false, true] {
            if wide {
                app.buttons["sessionCountdown"].tap()
                app.alerts.buttons["End session"].tap()
                app.buttons["story-choice-autumnTree"].tap()
                XCUIDevice.shared.orientation = .landscapeLeft
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
                    .press(forDuration: 0.25, thenDragTo: display.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99)))
                // iPadOS windowing can preserve portrait dimensions after rotation.
                // Exercise the landscape layout through its actual window bounds.
                if app.frame.width < app.frame.height {
                    window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
                        .press(forDuration: 0.25, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.48)))
                }
                let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    app.frame.width > app.frame.height
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 8), .completed)
            }
            let setup = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            setup.name = "paper-duration-ipad-\(wide ? "wide" : "tall")"
            setup.lifetime = .keepAlways
            add(setup)
            XCTAssertTrue(app.buttons["sessionBegin"].isHittable)
            let beginFrame = app.buttons["sessionBegin"].frame
            if wide {
                XCTAssertLessThan(beginFrame.maxX, window.frame.midX)
            } else {
                XCTAssertEqual(beginFrame.midX, window.frame.midX, accuracy: 2)
            }
            XCTAssertFalse(beginFrame.intersects(app.buttons["sessionBack"].frame))
            XCTAssertFalse(app.buttons["sessionBegin"].frame.intersects(app.staticTexts["Autumn"].frame))
            app.buttons["sceneSettings"].tap()
            XCTAssertTrue(app.buttons["sceneSettingsDone"].isHittable)
            XCTAssertTrue(app.sliders["sceneVolume"].isHittable)
            let settings = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            settings.name = "scene-settings-ipad-\(wide ? "wide" : "tall")"
            settings.lifetime = .keepAlways
            add(settings)
            app.buttons["sceneSettingsDone"].tap()
            app.buttons["sessionBegin"].tap()
            let timer = app.buttons["sessionCountdown"]
            let controls = app.buttons["sceneSettings"]
            XCTAssertEqual(app.frame.width > app.frame.height, wide)
            XCTAssertTrue(timer.isHittable)
            XCTAssertEqual(timer.frame.midX, beginFrame.midX, accuracy: 2)
            XCTAssertFalse(controls.frame.intersects(timer.frame))
            controls.tap()
            let previousTime = timer.value as? String
            let keepsRunning = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                timer.value as? String != previousTime
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [keepsRunning], timeout: 4), .completed)
            app.buttons["sceneSettingsDone"].tap()
            let picture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            picture.name = "focus-session-ipad-\(wide ? "wide" : "tall")"
            picture.lifetime = .keepAlways
            add(picture)
        }
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
            .press(forDuration: 0.25, thenDragTo: display.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99)))
    }

    func testSplashMusicRunnerDoesNotRestorePausedRun() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--performance-runner-review"]
        app.launchEnvironment["SPLASH_AUDIO_DISABLED"] = "1"
        app.launch()
        let pause = app.buttons["performancePauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertTrue(app.staticTexts["Paused Splash"].waitForExistence(timeout: 3))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["developerControls"].waitForExistence(timeout: 10))
        app.buttons["developerControls"].tap()
        let runner = app.buttons["Splash runner"]
        XCTAssertTrue(runner.waitForExistence(timeout: 10))
        runner.tap()
        XCTAssertTrue(app.buttons["Run Splash"].waitForExistence(timeout: 3))
        XCTAssertFalse(pause.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "splash-no-session-restoration"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSplashMusicRunnerControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--performance-runner-review"]
        app.launchEnvironment["SPLASH_AUDIO_DISABLED"] = "1"
        app.launch()
        let pause = app.buttons["performancePauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertTrue(app.staticTexts["Paused Splash"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "splash-runner-paused"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        pause.tap()
        XCTAssertTrue(app.staticTexts["Running Splash"].waitForExistence(timeout: 3))
        app.buttons["Hide"].tap()
        XCTAssertTrue(app.buttons["developerControls"].waitForExistence(timeout: 3))
        app.buttons["developerControls"].tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        app.buttons["End run"].tap()
        XCTAssertTrue(app.buttons["Run Splash"].waitForExistence(timeout: 3))
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
        let wantsLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
        app.launchArguments = ["--sunrise-audit"]
        if wantsLandscape { app.launchArguments.append("--sunrise-audit-landscape") }
        app.launch()
        XCUIDevice.shared.orientation = orientation
        let geometryExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                wantsLandscape ? app.frame.width > app.frame.height : app.frame.height > app.frame.width
            }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [geometryExpectation], timeout: 8), .completed)
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

    func testStartOpensSessionSetupAndStoriesOpensChooser() throws {
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
        XCTAssertTrue(app.buttons["sessionBegin"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Choose a story"].exists)
        app.buttons["sessionBack"].tap()
        app.buttons["Back"].tap()
        // Returning restarts the authored 2.0s delay + 1.2s navigation reveal.
        // XCTest cannot query hittability while its activation point is hidden.
        let revealedAt = Date().addingTimeInterval(3.3)
        let reveal = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Date() >= revealedAt
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reveal], timeout: 5), .completed)
        XCTAssertTrue(waitUntilHittable(stories, timeout: 6))
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

        let returnToStories = app.buttons["sessionBack"]
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

}
