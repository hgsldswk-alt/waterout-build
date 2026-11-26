import XCTest

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!

    private enum Language: String {
        case en
        case simplified = "zh-Hans"
        case traditional = "zh-Hant"
        case japanese = "ja"
        var locale: String {
            switch self {
            case .en: return "en_US"
            case .simplified: return "zh_CN"
            case .traditional: return "zh_TW"
            case .japanese: return "ja_JP"
            }
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ language: Language = .en, _ flags: [String] = [], code: String? = nil, fileCode: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-reset", "-AppleLanguages", "(\(language.rawValue))",
                               "-AppleLocale", language.locale] + flags
        if let code { app.launchEnvironment["WATEROUT_PRESET"] = code }
        if let fileCode { app.launchEnvironment["WATEROUT_PRESET_FILE"] = fileCode }
        app.launch()
    }

    private func button(_ id: String, timeout: TimeInterval = 8) -> XCUIElement {
        let element = app.buttons[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), id)
        return element
    }

    private func element(_ id: String, timeout: TimeInterval = 8) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), id)
        return element
    }

    private func tap(_ id: String) {
        let element = button(id)
        if !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, id)
        element.tap()
    }

    private func back() {
        let first = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 6))
        first.tap()
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPlayStopAndReplayOnHome() {
        launch()
        tap("tone.play")
        _ = element("tone.countdown")
        tap("tone.stop")
        XCTAssertEqual(button("tone.play").label, "Replay")
        tap("tone.play")
        tap("tone.stop")
    }

    func testCycleFinishesAndShareContentIsRendered() {
        launch()
        tap("tone.play")
        XCTAssertTrue(button("home.card", timeout: 23).exists)
        tap("home.card")
        let share = button("card.share")
        expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: share)
        waitForExpectations(timeout: 8)
        tap("card.share")
        _ = element("share.requested")
    }

    func testRouteFailureNeverEntersPlayback() {
        launch(.en, ["-route-error"])
        tap("tone.play")
        _ = element("audio.problem")
        XCTAssertFalse(app.buttons["tone.stop"].exists)
        tap("home.check.speaker")
        _ = element("audio.problem")
        XCTAssertFalse(app.buttons["check.stop"].exists)
    }

    func testLeavingAppStopsAndNeverAutoplaysOnReturn() {
        launch()
        tap("tone.play")
        _ = button("tone.stop")
        XCUIDevice.shared.press(.home)
        app.activate()
        _ = button("tone.play")
        _ = element("audio.problem")
        XCTAssertFalse(app.buttons["tone.stop"].exists)
    }

    func testStereoUsesWrittenLabelsAndReplaysOneSide() {
        launch()
        tap("home.check.stereo")
        XCTAssertTrue(button("channel.left").label.contains("Left"))
        XCTAssertTrue(button("channel.right").label.contains("Right"))
        tap("hearing.both")
        tap("channel.right")
        tap("check.stop")
    }

    func testMonoAndReceiverFallbacks() {
        launch(.en, ["-mono", "-receiver-error"])
        tap("home.check.stereo")
        _ = element("audio.problem")
        tap("check.fallback")
        _ = button("hearing.clear")
        XCTAssertFalse(app.buttons["hearing.both"].exists)
        back()
        tap("home.check.receiver")
        _ = element("audio.problem")
        tap("check.fallback")
        _ = button("hearing.clear")
    }

    func testPlaybackChecksSavedPresetsAndHistoryExport() {
        launch(.en, ["-seed-history"])
        tap("tone.play")
        tap("tone.stop")
        tap("home.check.speaker")
        _ = button("hearing.clear")
        back()
        tap("home.history")
        tap("history.record")
        _ = element("history.conditions")
        tap("history.export")
        _ = element("share.requested")
        for _ in 0..<3 where !app.buttons["home.settings"].exists && app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
            _ = app.buttons["home.settings"].waitForExistence(timeout: 2)
        }
        tap("home.settings")
        tap("settings.presets")
        tap("preset.saved.0")
        XCTAssertTrue(app.staticTexts["Limited sweep"].exists)
        tap("tone.play")
        tap("tone.stop")
    }

    func testImportPreviewsBeforeApplyingAndDoesNotStartSound() {
        let json = Data(#"{"mode":"sweep","seconds":5}"#.utf8)
        let code = json.base64EncodedString().replacingOccurrences(of: "=", with: "")
        launch(code: "\nWT1:\(code)\n")
        tap("home.import")
        XCTAssertFalse(app.buttons["import.use"].exists)
        tap("import.paste")
        _ = element("import.result")
        tap("import.use")
        XCTAssertTrue(app.staticTexts["Limited sweep"].exists)
        XCTAssertFalse(app.buttons["tone.stop"].exists)
        tap("tone.play")
        tap("tone.stop")
    }

    func testHomePresetFilePreviewsBeforeApplying() {
        let data = Data(#"{"mode":"sweep","seconds":5}"#.utf8)
        let code = data.base64EncodedString().replacingOccurrences(of: "=", with: "")
        launch(fileCode: "WT1:\(code)")
        tap("home.importFile")
        _ = element("import.result")
        tap("import.use")
        XCTAssertTrue(app.staticTexts["Limited sweep"].exists)
        XCTAssertFalse(app.buttons["tone.stop"].exists)
    }

    func testComparisonRecordsTwoCompletedSamples() {
        launch()
        tap("home.settings")
        tap("settings.history")
        tap("history.new")
        tap("history.play.before")
        _ = element("history.note.before")
        tap("history.play.after")
        _ = element("history.note.after")
        tap("history.save")
        _ = element("history.conditions")
        tap("history.export")
        _ = element("share.requested")
    }

    func testAllThreeChecksRevealMilestone() {
        launch()
        tap("home.check.speaker")
        _ = button("check.card")
        back()
        tap("home.check.receiver")
        _ = button("check.card")
        back()
        tap("home.check.stereo")
        XCTAssertEqual(button("check.card").label, "Keep this checklist")
    }

    private func storeShots(_ language: Language) {
        launch(language, ["-seed-history", "-seed-milestone"])
        let prefix = "store-\(language.rawValue)-"
        _ = button("tone.play")
        attach(prefix + "01-home")
        tap("tone.play")
        _ = button("tone.stop")
        attach(prefix + "02-playing")
        tap("tone.stop")
        tap("home.check.stereo")
        _ = button("check.stop")
        attach(prefix + "03-stereo")
        back()
        tap("home.settings")
        tap("settings.history")
        tap("history.record")
        _ = element("history.conditions")
        attach(prefix + "04-comparison")
        tap("history.card")
        let share = button("card.share")
        expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: share)
        waitForExpectations(timeout: 8)
        attach(prefix + "05-card")
    }

    func testStoreEnglish() { storeShots(.en) }
    func testStoreSimplifiedChinese() { storeShots(.simplified) }
    func testStoreTraditionalChinese() { storeShots(.traditional) }
    func testStoreJapanese() { storeShots(.japanese) }
}
