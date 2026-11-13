import XCTest

/// Smoke tests for the main flows, driven with mock sensors in the in-memory preview store
/// (`--debug-preview`, optionally `--scenario <name>`). They never touch real history.
/// Compile with `xcodebuild … build-for-testing`; running them drives the simulator UI and needs
/// the user's permission for a visual review.
@MainActor
final class FTPunkUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// `mockSpeed` slows the mock sensor stream down (the preview default is 12×), so a test that has to act on a phase
    /// is not racing the ramp to exhaustion.
    @discardableResult
    func launch(scenario: String? = nil, mockSpeed: Int? = nil) -> XCUIApplication {
        app.launchArguments = ["--debug-preview"] + (scenario.map { ["--scenario", $0] } ?? []) + (mockSpeed.map { ["--mock-speed", String($0)] } ?? [])
        app.launch()
        return app
    }

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @discardableResult
    func tap(_ id: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let target = element(id)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Missing \(id)", file: file, line: line)
        target.tap()
        return target
    }

    /// Scrolls Home (or any scroll view) until the element can be tapped.
    func scrollTo(_ target: XCUIElement, maxSwipes: Int = 12) {
        var swipes = 0
        while !(target.exists && target.isHittable) && swipes < maxSwipes { app.swipeUp(); swipes += 1 }
    }

    // MARK: FTP test

    /// Home → FTP test → pre-flight → start → skip warm-up (debug) → hold to finish → result.
    /// Mock results are debug recordings: they show the debug badge and offer no adoption.
    ///
    /// The mock stream runs at 4× here. At the preview default of 12× the ramp reached exhaustion (a 300 W target, after
    /// 40 steps of 12 s) while the test was still in the debug menu, so Hold to finish was already gone. At 4× the ramp
    /// lasts two minutes of wall time: far longer than this test needs, and still long enough for the 60-second window
    /// the estimate requires.
    func testFTPTestFromHomeToDebugResult() throws {
        launch(mockSpeed: 4)
        tap("ftp-test")
        XCTAssertTrue(element("primary-action").waitForExistence(timeout: 10), "Pre-flight shows Start")
        tap("primary-action")
        XCTAssertTrue(element("minimise-ride").waitForExistence(timeout: 20), "The cockpit fills the screen")
        // Debug-only: skip the warm-up from the options menu (the quick debug warm-up may already be over).
        tap("ride-options")
        if app.buttons["Debug controls…"].waitForExistence(timeout: 3) {
            app.buttons["Debug controls…"].tap()
            if app.buttons["Skip warm-up"].waitForExistence(timeout: 3) { app.buttons["Skip warm-up"].tap() }
            if app.buttons["Done"].waitForExistence(timeout: 3) { app.buttons["Done"].tap() }
        }
        // Right after the warm-up: Hold to finish is there, and stays there for about two minutes.
        let hold = element("hold-to-finish")
        XCTAssertTrue(hold.waitForExistence(timeout: 30), "The ramp offers Hold to finish")
        // A tap must not end the test; a deliberate hold does.
        hold.tap()
        XCTAssertTrue(hold.exists, "A short tap does not finish the ramp")
        Thread.sleep(forTimeInterval: 20) // about 80 s of mock ramp: a full minute for the estimate
        XCTAssertTrue(element("hold-to-finish").exists, "The ramp is still running, far from exhaustion")
        element("hold-to-finish").press(forDuration: 2.0)
        XCTAssertTrue(element("primary-action").waitForExistence(timeout: 30), "The result shows its action bar")
        XCTAssertFalse(app.buttons["keep-ftp"].exists, "Debug results cannot be adopted")
        tap("primary-action") // Done
        XCTAssertTrue(element("ftp-test").waitForExistence(timeout: 10), "Back on Home")
    }

    /// A real (seeded) result: adopt it, see the training hand-off, return Home with the new FTP.
    func testAdoptingAResultUpdatesHome() throws {
        launch(scenario: "result-new-ftp")
        XCTAssertTrue(element("primary-action").waitForExistence(timeout: 20))
        tap("primary-action") // Use … as Alex's FTP
        XCTAssertTrue(element("ftp-adopted").waitForExistence(timeout: 10), "Adoption is confirmed inline")
        let handoff = element("training-handoff")
        XCTAssertTrue(handoff.exists, "The training hand-off follows adoption")
        let adoptedWatts = handoff.label.components(separatedBy: " ").compactMap { Int($0) }.first(where: { $0 > 50 })
        tap("primary-action") // Back to Home
        XCTAssertTrue(element("ftp-test").waitForExistence(timeout: 10))
        // The library now resolves to the adopted FTP.
        let card = app.buttons["Sweet spot 3×10"]
        scrollTo(card)
        card.tap()
        if let adoptedWatts {
            XCTAssertTrue(app.staticTexts["Targets use your FTP of \(adoptedWatts) W."].waitForExistence(timeout: 5), "New targets use \(adoptedWatts) W")
        }
    }

    /// Stop & save from the live-ride bar is one tap, with no confirmation.
    func testMinimiseShowsTheLiveRideBarAndStopIsImmediate() throws {
        launch(scenario: "ride-ramp")
        tap("minimise-ride")
        XCTAssertTrue(element("return-to-ride").waitForExistence(timeout: 10))
        tap("live-bar-stop")
        XCTAssertFalse(element("return-to-ride").waitForExistence(timeout: 3), "Stopping removes the live-ride bar at once")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Stop has no confirmation dialog")
    }

    // MARK: Workouts and free rides

    /// Find the card by its accessibility button label and activate that element.
    /// This fails if a replacement accessibility element hides the button's press action.
    func testLibraryCardAccessibilityElementOpensDetails() throws {
        launch(scenario: "library")
        let card = app.buttons.matching(NSPredicate(format: "label == %@", "Sweet spot 3×10")).firstMatch
        scrollTo(card)
        XCTAssertTrue(card.exists, "The workout is exposed as a labelled accessibility button")
        XCTAssertTrue(card.isEnabled)
        card.tap()
        XCTAssertTrue(element("primary-action").waitForExistence(timeout: 10), "The workout detail sheet opens")
        XCTAssertTrue(app.staticTexts["Targets use your FTP of 250 W."].exists)
    }

    /// Library card → detail → pre-flight → start → pause → resume → stop.
    func testWorkoutFromTheLibraryPausesResumesAndStops() throws {
        launch(scenario: "library")
        let card = app.buttons["Sweet spot 3×10"]
        scrollTo(card)
        card.tap()
        tap("primary-action") // Start in the detail sheet opens the pre-flight
        XCTAssertTrue(element("intensity-stepper").waitForExistence(timeout: 10), "The workout pre-flight offers intensity")
        tap("primary-action") // Start workout
        XCTAssertTrue(element("pause-resume").waitForExistence(timeout: 20), "The workout cockpit opens")
        tap("pause-resume")
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 10), "Pausing offers Resume")
        tap("pause-resume")
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10), "Resuming offers Pause again")
        tap("stop-save")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Stop has no confirmation dialog")
        tap("primary-action") // Done
        XCTAssertTrue(element("ftp-test").waitForExistence(timeout: 10))
    }

    /// Free ERG: ±10 W, then stop.
    func testFreeERGAdjustsByTenWattsAndStops() throws {
        launch()
        tap("quick-erg")
        tap("primary-action")
        XCTAssertTrue(element("erg-plus").waitForExistence(timeout: 20))
        tap("erg-plus")
        tap("erg-minus")
        tap("stop-save")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        tap("primary-action") // Done
        XCTAssertTrue(element("ftp-test").waitForExistence(timeout: 10))
    }

    // MARK: Progress

    func activityRows() -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'activity-'"))
    }

    /// The identifiers of the activity rows, scrolling until `expected` are known. The rows sit below the trend chart in a
    /// lazily loaded list, so only the rows near the viewport are in the accessibility hierarchy at any time; counting the
    /// query once would see just the first row. Each row is identified by its own identifier instead.
    func activityIdentifiers(expected: Int, maxSwipes: Int = 8) -> Set<String> {
        var seen = Set<String>()
        for _ in 0...maxSwipes {
            seen.formUnion(activityRows().allElementsBoundByIndex.map(\.identifier))
            if seen.count >= expected { break }
            app.swipeUp()
        }
        return seen
    }
    func scrollToTop(maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes { app.swipeDown() }
    }

    /// Two riders: Progress follows the current rider, All riders shows both, and a swipe deletes after confirmation.
    func testProgressFiltersByRiderAndDeletesBySwipe() throws {
        launch(scenario: "progress-two-riders")
        XCTAssertTrue(activityRows().firstMatch.waitForExistence(timeout: 20))
        let alex = activityIdentifiers(expected: 2)
        XCTAssertEqual(alex.count, 2, "Alex is the current rider: two FTP tests")
        scrollToTop()
        tap("progress-filter")
        app.buttons["All riders"].tap()
        let everyone = activityIdentifiers(expected: 3)
        XCTAssertEqual(everyone.count, 3, "All riders shows three activities")
        XCTAssertTrue(alex.isSubset(of: everyone), "Alex's tests are among them")
        scrollToTop()
        activityRows().firstMatch.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "Deleting asks for confirmation")
        app.alerts.buttons["Delete"].tap()
        Thread.sleep(forTimeInterval: 2)
        scrollToTop()
        XCTAssertEqual(activityIdentifiers(expected: 3).count, 2, "One activity was removed")
    }

    // MARK: Chaindance

    /// The explicitly enabled visual preview shows Chaindance; the header menu switches it off and on again.
    func testPixelRideShowsInTheCockpitAndTheMenuTogglesIt() throws {
        launch(scenario: "visual-ramp-threshold")
        XCTAssertTrue(element("ride-visual").waitForExistence(timeout: 20), "The visual preview enables Chaindance")
        XCTAssertTrue(element("ride-visual").label.hasPrefix("Chaindance: threshold effort, level"), "It carries a summary label")
        tap("ride-visual-menu")
        app.buttons["Off"].tap()
        XCTAssertFalse(element("ride-visual").waitForExistence(timeout: 3), "Off: the cockpit shows the metrics only")
        XCTAssertTrue(element("hold-to-finish").exists && element("stop-save").exists, "Controls are unaffected")
        tap("ride-visual-menu")
        app.buttons["Strip"].tap()
        XCTAssertTrue(element("ride-visual").waitForExistence(timeout: 5), "Back on, in the same place")
    }

    /// Workouts show it too, and a paused workout says so.
    func testPixelRideAppearsInWorkoutsAndDescribesAPause() throws {
        launch(scenario: "visual-paused")
        XCTAssertTrue(element("pause-resume").waitForExistence(timeout: 20))
        XCTAssertEqual(element("ride-visual").label, "Chaindance: paused")
    }

    /// With the switch off, a ride starts without it.
    func testPixelRideCanBeOffForARide() throws {
        launch(scenario: "visual-off")
        XCTAssertTrue(element("hold-to-finish").waitForExistence(timeout: 20))
        XCTAssertFalse(element("ride-visual").exists, "Chaindance is off")
    }

    /// The switch lives in Settings → Ride display and in the pre-flight of tests and workouts.
    func testPixelRideSwitchIsInSettingsAndPreflight() throws {
        launch(scenario: "home-not-connected")
        tap("ftp-test")
        XCTAssertTrue(element("pixel-ride-toggle").waitForExistence(timeout: 10), "The test pre-flight offers it")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["Show Chaindance during rides"]
        scrollTo(toggle)
        XCTAssertTrue(toggle.exists, "Settings → Ride display offers it")
    }

    // MARK: Story removal

    /// The story is gone: three tabs, no Home card, no Settings switch. (Its data is still read and kept; the unit tests
    /// cover that.)
    func testThereIsNoStoryTabCardOrSwitch() throws {
        launch(scenario: "home-not-connected")
        XCTAssertFalse(app.tabBars.buttons["Story"].exists, "No Story tab")
        XCTAssertEqual(app.tabBars.buttons.count, 3, "Home, Progress and Settings")
        XCTAssertFalse(element("story-card").exists, "No Home story card")
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.switches["Lowline story"].exists, "No Settings switch")
    }

    /// A result has no story receipt any more.
    func testTheResultShowsNoStoryReceipt() throws {
        launch(scenario: "result-new-ftp")
        XCTAssertTrue(app.staticTexts["ESTIMATED FTP"].waitForExistence(timeout: 20))
        XCTAssertFalse(element("story-receipt").exists)
    }
}
