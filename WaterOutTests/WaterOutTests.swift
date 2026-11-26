import CoreImage
import Foundation
import XCTest

final class WaterOutTests: XCTestCase {
    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testToneDurationSoftEnvelopeAndGainCap() {
        for mode in SoundMode.allCases {
            for seconds in SoundPreset.durations {
                let job = SoundJob.tone(SoundPreset(mode: mode, seconds: seconds))
                XCTAssertEqual(job.duration, Double(seconds))
                XCTAssertEqual(SoundSignal.stereo(job, elapsed: 0).0, 0)
                XCTAssertEqual(SoundSignal.stereo(job, elapsed: job.duration).1, 0)
                XCTAssertEqual(SoundSignal.stereo(job, elapsed: job.duration + 1).0, 0)
                for time in stride(from: 0.0, to: job.duration, by: 0.007) {
                    XCTAssertLessThanOrEqual(abs(SoundSignal.stereo(job, elapsed: time).0), SoundSignal.gainLimit)
                }
            }
        }
        XCTAssertEqual(SoundSignal.envelope(elapsed: -1, length: 15), 0)
        XCTAssertLessThan(SoundSignal.envelope(elapsed: 0.02, length: 15), 0.05)
        XCTAssertLessThan(SoundSignal.envelope(elapsed: 14.99, length: 15), 0.05)
        XCTAssertEqual(SoundSignal.envelope(elapsed: 1, length: 15), 1)
    }

    func testStereoAndLowLevelReceiver() {
        let stereo = SoundJob.check(.stereo, nil)
        XCTAssertEqual(stereo.channel(at: 0.53), .left)
        XCTAssertEqual(stereo.channel(at: 2.53), .right)
        XCTAssertEqual(SoundSignal.stereo(stereo, elapsed: 2).0, 0)
        XCTAssertEqual(SoundSignal.stereo(stereo, elapsed: 2).1, 0)
        let left = SoundSignal.stereo(stereo, elapsed: 0.531)
        let right = SoundSignal.stereo(stereo, elapsed: 2.531)
        XCTAssertNotEqual(left.0, 0)
        XCTAssertEqual(left.1, 0)
        XCTAssertEqual(right.0, 0)
        XCTAssertNotEqual(right.1, 0)
        let earpiece = SoundJob.check(.receiver, nil)
        for time in stride(from: 0.0, to: earpiece.duration, by: 0.009) {
            XCTAssertLessThanOrEqual(abs(SoundSignal.stereo(earpiece, elapsed: time).0), 0.035)
        }
        XCTAssertNil(SoundJob.check(.stereo, .left).countsAsCheck)
        XCTAssertNil(SoundJob.monoSample.countsAsCheck)
    }

    func testCancelInvalidatesLateRouteOrCompletionCallbacks() throws {
        var token = PlaybackToken()
        let first = try XCTUnwrap(token.begin())
        XCTAssertNil(token.begin())
        XCTAssertTrue(token.stop())
        XCTAssertFalse(token.stop())
        XCTAssertFalse(token.matches(first))
        let second = try XCTUnwrap(token.begin())
        XCTAssertFalse(token.matches(first))
        XCTAssertTrue(token.matches(second))
    }

    func testPresetRoundTripAndInvalidPayloads() {
        for mode in SoundMode.allCases {
            let preset = SoundPreset(mode: mode, seconds: 10)
            XCTAssertEqual(SoundPreset.decode("\n\(preset.code)\n"), preset)
        }
        let code = SoundPreset.standard.code
        XCTAssertNil(SoundPreset.decode(code.replacingOccurrences(of: "WT1:", with: "WT2:")))
        XCTAssertNil(SoundPreset.decode(code + "="))
        XCTAssertNil(SoundPreset.decode("WT1:" + String(repeating: "A", count: 257)))
        XCTAssertNil(SoundPreset.decode(SoundPreset(mode: .basic, seconds: 16).code))
        for invalid in [
            #"{"mode":"ultrasonic","seconds":15}"#,
            #"{"mode":"basic","seconds":15,"gain":1}"#,
            #"{"mode":"basic","seconds":true}"#
        ] {
            let token = Data(invalid.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
            XCTAssertNil(SoundPreset.decode("WT1:" + token))
        }
    }

    func testPresetFileReadsBoundedUTF8Code() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let preset = SoundPreset(mode: .sweep, seconds: 5)
        try Data(preset.code.utf8).write(to: url)
        XCTAssertEqual(SoundPreset.readFile(url).flatMap(SoundPreset.decode), preset)
        try Data(repeating: 65, count: SoundPreset.maxCodeBytes + 1).write(to: url)
        XCTAssertNil(SoundPreset.readFile(url))
        try Data([0xff]).write(to: url)
        XCTAssertNil(SoundPreset.readFile(url))
    }

    func testPaidDownloadIncludesAllFeatures() {
        XCTAssertTrue(Launch.freePeriod)
    }

    func testMatchingConditionsAndPrivacyOfCompletionMilestone() {
        let record = ListeningComparison.example
        XCTAssertTrue(record.sameConditions)
        let changed = CheckSession(check: .speaker, conditions: .init(output: .speaker, volume: -1), hearing: .clear)
        XCTAssertFalse(ListeningComparison(before: changed, after: changed).sameConditions)
        let other = CheckSession(check: .speaker, conditions: .init(output: .speaker, volume: 50), hearing: .clear)
        XCTAssertFalse(ListeningComparison(before: record.before, after: other).sameConditions)

        let day = Date(timeIntervalSince1970: 1_700_000_000)
        var milestone = Milestones()
        milestone.complete(.speaker, at: day)
        milestone.complete(.receiver, at: day)
        XCTAssertFalse(milestone.completedChecklist)
        XCTAssertFalse(milestone.claimRating(idle: true, shared: true))
        milestone.complete(.stereo, at: day.addingTimeInterval(86_400))
        XCTAssertTrue(milestone.markChecklistShown())
        XCTAssertFalse(milestone.markChecklistShown())
        XCTAssertFalse(milestone.claimRating(idle: false, shared: true))
        XCTAssertFalse(milestone.claimRating(idle: true, shared: false))
        XCTAssertTrue(milestone.claimRating(idle: true, shared: true))
        XCTAssertFalse(milestone.claimRating(idle: true, shared: true))
    }

    func testQRRoundTripUsingCIDetector() throws {
        XCTAssertNil(CardCode.storeURL(id: ""))
        XCTAssertNil(CardCode.storeURL(id: "invalid/id"))
        let store = try XCTUnwrap(CardCode.storeURL(id: "123456789"))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode,
                                               context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for url in [CardCode.supportURL, store] {
            let bitmap = try XCTUnwrap(CardCode.image(for: url))
            let result = detector.features(in: CIImage(cgImage: bitmap)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(result, [url.absoluteString])
        }
    }

    func testLocalizationsLoadInHostlessTestBundle() {
        XCTAssertNotEqual(L.t("tone.play"), "tone.play")
        XCTAssertTrue(L.f("preset.seconds", 15).contains("15"))
    }
}
