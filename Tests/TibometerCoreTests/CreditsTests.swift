import Foundation
import TibometerCore

final class CreditsTests {
    func testCreditsDecodeWithoutQuotaWindowsAndOldSnapshotsStillWork() throws {
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: Data(#"{"rateLimits":{"credits":{"hasCredits":true,"unlimited":false,"balance":"1250.5"}}}"#.utf8))
        expectEqual(response.buckets.count, 1)
        expectEqual(response.buckets.first?.credits?.balanceValue, Decimal(string: "1250.5"))
        expectNil(response.buckets.first?.window(.fiveHour))
        let old = try JSONDecoder().decode(RateBucket.self, from: Data(#"{"primary":{"usedPercent":25,"windowDurationMins":10080}}"#.utf8))
        expectNil(old.credits)
        expectEqual(old.window(.weekly)?.remainingPercent, 75)
    }

    func testBalanceKeepsZeroAndDecimalPrecision() {
        let previous = UserDefaults.standard.object(forKey: "appearance.language")
        defer { UserDefaults.standard.set(previous, forKey: "appearance.language") }
        L10n.preference = .english
        expectEqual(CreditsSnapshot(hasCredits: false, unlimited: false, balance: "0").displayText, "0")
        expectEqual(CreditsSnapshot(hasCredits: true, unlimited: false, balance: "1234.56789").displayText, "1,234.56789")
        expectEqual(CreditsSnapshot(hasCredits: true, unlimited: false, balance: "0.0000000001").displayText, "0.0000000001")
        for balance in ["0", "0.00", " 000.000 "] {
            for hasCredits in [false, true] {
                let credits = CreditsSnapshot(hasCredits: hasCredits, unlimited: false, balance: balance)
                expectEqual(credits.balanceValue, Decimal.zero)
                expectFalse(credits.shouldDisplay)
            }
        }
        expect(CreditsSnapshot(hasCredits: true, unlimited: false, balance: "0.0000000001").shouldDisplay)
        expect(CreditsSnapshot(hasCredits: false, unlimited: false, balance: "12.5").shouldDisplay)
    }

    func testMissingAndUnlimitedCreditsAreNotInventedNumbers() {
        let previous = UserDefaults.standard.object(forKey: "appearance.language")
        defer { UserDefaults.standard.set(previous, forKey: "appearance.language") }
        L10n.preference = .english
        for balance in [String?.none, "", "NaN", "Infinity", "-1", "100 invalid"] {
            let available = CreditsSnapshot(hasCredits: true, unlimited: false, balance: balance)
            expectNil(available.balanceValue)
            expectEqual(available.displayText, "Available")
            expect(available.shouldDisplay)
            expectEqual(CreditsSnapshot(hasCredits: false, unlimited: false, balance: balance).displayText, "None available")
        }
        let unlimited = CreditsSnapshot(hasCredits: true, unlimited: true, balance: "0")
        expectEqual(unlimited.displayText, "Unlimited")
        expect(unlimited.shouldDisplay)
        L10n.preference = .chinese
        expectEqual(unlimited.displayText, "不限量")
        expectEqual(CreditsSnapshot(hasCredits: true, unlimited: false, balance: nil).displayText, "有可用点数")
    }
}
