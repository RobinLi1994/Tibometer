import Foundation
import TibometerCore

final class QuotaTests {
    private func sample(_ used: Double?, at: Double = 1000, reset: Double? = 2000, account: String = "A", kind: QuotaWindow = .fiveHour) -> UsageSnapshot {
        UsageSnapshot(observedAt: Date(timeIntervalSince1970: at), accountFingerprint: account,
            buckets: [RateBucket(primary: RateWindow(usedPercent: used, windowDurationMins: kind.rawValue, resetsAt: reset), secondary: nil)])
    }

    func testWeeklyInPrimaryIsNeverAssumedToBeFiveHours() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1800000000},"secondary":null}}"#.utf8)
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        expectNil(response.buckets.first?.window(.fiveHour))
        expectEqual(response.buckets.first?.window(.weekly)?.remainingPercent, 93)
    }

    func testMultiBucketMapIsAuthoritativeAndDoesNotMixSparkWithCodex() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":7,"windowDurationMins":10080}},"spark":{"limitName":"Spark","primary":{"usedPercent":0,"windowDurationMins":300}}}}"#.utf8)
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        expectEqual(response.buckets.map(\.id), ["codex"])
        expectNil(response.buckets[0].window(.fiveHour))
        expectEqual(response.buckets[0].window(.weekly)?.remainingPercent, 93)
    }

    func testOtherBucketsNeverBecomeACodexFallback() throws {
        let other = RateBucket(limitId: "codex_bengalfox", limitName: "GPT-5.3-Codex-Spark",
            primary: RateWindow(usedPercent: 0, windowDurationMins: 300, resetsAt: 2000), secondary: nil)
        expect(RateLimitsResponse(rateLimits: other).buckets.isEmpty)
        expect(RateLimitsResponse(rateLimits: sample(25).codexBucket, rateLimitsByLimitId: [other.id: other]).buckets.isEmpty)
        var old = sample(95)
        old.buckets.append(other)
        let restored = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(old)).codexOnly
        expectEqual(restored.buckets.map(\.id), ["codex"])
        expectEqual(MenuBarPresentation.title(bucket: other), L10n.text("quota.empty"))
        expect(MenuBarPresentation.visibleWindows(in: other).isEmpty)
    }

    func testOtherBucketsDoNotNotifyOrChangePolling() {
        var before = sample(75)
        let other = RateBucket(limitId: "codex_bengalfox", primary: RateWindow(usedPercent: 95, windowDurationMins: 300, resetsAt: 1101), secondary: nil)
        before.buckets.append(other)
        var detector = ResetDetector()
        _ = detector.observe(before)
        var after = before
        after.observedAt = Date(timeIntervalSince1970: 1100)
        after.buckets[1].primary?.usedPercent = 0
        expect(detector.observe(after).isEmpty)
        expectEqual(RefreshSchedule.delay(snapshot: after, now: after.observedAt, interval: 30), 30)
    }

    func testEmptyMapFallsBackToLegacy() {
        let bucket = sample(20).buckets[0]
        expectEqual(RateLimitsResponse(rateLimits: bucket, rateLimitsByLimitId: [:]).buckets.count, 1)
    }

    func testUnknownAndOutOfRangeValues() {
        expectNil(RateWindow(usedPercent: nil, windowDurationMins: 300, resetsAt: nil).remainingPercent)
        expectNil(RateWindow(usedPercent: .nan, windowDurationMins: 300, resetsAt: nil).remainingPercent)
        expectEqual(RateWindow(usedPercent: 120, windowDurationMins: 300, resetsAt: nil).remainingPercent, 0)
        expectEqual(RateWindow(usedPercent: -10, windowDurationMins: 300, resetsAt: nil).remainingPercent, 100)
        expectEqual(RateWindow(usedPercent: 0.1, windowDurationMins: 300, resetsAt: nil).percentageText, "99%")
        expectEqual(RateWindow(usedPercent: 99.9, windowDurationMins: 300, resetsAt: nil).percentageText, "<1%")
    }

    func testInitialSampleNeverNotifies() {
        var detector = ResetDetector()
        expect(detector.observe(sample(0)).isEmpty)
    }

    func testConsumptionAndPartialRecoveryDoNotNotify() {
        var detector = ResetDetector()
        _ = detector.observe(sample(70))
        expect(detector.observe(sample(80, at: 1100)).isEmpty)
        expect(detector.observe(sample(20, at: 1200)).isEmpty)
    }

    func testFullRestoreEmitsOnceAcrossRestart() throws {
        var detector = ResetDetector()
        _ = detector.observe(sample(95))
        let events = detector.observe(sample(0, at: 1100))
        expectEqual(events.count, 1)
        expectEqual(events.first?.reason, .restoredToFull)
        expectEqual(events.first?.remainingPercent, 100)
        detector = try JSONDecoder().decode(ResetDetector.self, from: JSONEncoder().encode(detector))
        expect(detector.observe(sample(0, at: 1200)).isEmpty)
    }

    func testPersistedBaselineDetectsResetWhileAppWasClosed() throws {
        var detector = ResetDetector()
        _ = detector.observe(sample(80))
        detector = try JSONDecoder().decode(ResetDetector.self, from: JSONEncoder().encode(detector))
        expectEqual(detector.observe(sample(0, at: 2100, reset: 20000)).count, 1)
    }

    func testNewWindowIsDetectedEvenWhenAlreadyPartlyConsumed() {
        var detector = ResetDetector()
        _ = detector.observe(sample(90))
        let events = detector.observe(sample(4, at: 2100, reset: 20000))
        expectEqual(events.first?.reason, .newWindow)
        expectEqual(events.first?.remainingPercent, 96)
        expect(events.first?.message.contains("100%") ?? false)
    }

    func testDeadlineAloneIsNotProofOfResetAndDelayedConfirmationWorks() {
        var detector = ResetDetector()
        _ = detector.observe(sample(90))
        expect(detector.observe(sample(90, at: 2010)).isEmpty)
        expect(detector.observe(sample(90, at: 2020)).isEmpty)
        expectEqual(detector.observe(sample(5, at: 2030, reset: 20000)).count, 1)
    }

    func testChangingFutureDeadlineWithoutResetDoesNotNotify() {
        var detector = ResetDetector()
        _ = detector.observe(sample(0))
        expect(detector.observe(sample(0, at: 1010, reset: 2010)).isEmpty)
        expect(detector.observe(sample(0, at: 1050, reset: 4000)).isEmpty)
    }

    func testMissingDataDoesNotCreateARefillOrDestroyBaseline() {
        var detector = ResetDetector()
        _ = detector.observe(sample(95))
        expect(detector.observe(sample(nil, at: 1100)).isEmpty)
        expectEqual(detector.observe(sample(0, at: 1200)).count, 1)
    }

    func testAccountSwitchNeverLooksLikeAReset() {
        var detector = ResetDetector()
        _ = detector.observe(sample(95))
        expect(detector.observe(sample(0, at: 1100, account: "B")).isEmpty)
    }

    func testOlderAndDuplicateSamplesDoNotReplaceBaseline() {
        var detector = ResetDetector()
        _ = detector.observe(sample(95))
        expect(detector.observe(sample(0, at: 900)).isEmpty)
        expect(detector.observe(sample(0, at: 1000)).isEmpty)
        expectEqual(detector.observe(sample(0, at: 1100)).count, 1)
    }

    func testBothWindowsResetIndependently() {
        var detector = ResetDetector()
        var before = sample(95)
        before.buckets[0].secondary = RateWindow(usedPercent: 80, windowDurationMins: 10080, resetsAt: 3000)
        _ = detector.observe(before)
        var after = sample(0, at: 1100)
        after.buckets[0].secondary = RateWindow(usedPercent: 0, windowDurationMins: 10080, resetsAt: 3000)
        expectEqual(Set(detector.observe(after).map(\.window)), [.fiveHour, .weekly])
    }

    func testRefreshAtResetAndBackoff() {
        let now = Date(timeIntervalSince1970: 1995)
        expectEqual(RefreshSchedule.delay(snapshot: sample(80), now: now, interval: 30), 7)
        expectEqual(RefreshSchedule.delay(snapshot: sample(80), now: Date(timeIntervalSince1970: 2010), interval: 30), 10)
        expectEqual(RefreshSchedule.delay(snapshot: sample(80), now: now, interval: 30, failures: 5), 300)
    }
}
