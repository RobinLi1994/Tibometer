import Foundation
import TibometerCore

final class MultiAccountTests {
    private let workID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let personalID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let researchID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    func testLegacySettingsMigrateToFirstAccountAndPreserveSource() throws {
        let legacy = LegacyAccountSettings(executablePath: "/Applications/Codex.app",
                                            homePath: "/tmp/codex-work",
                                            ccSwitchProviderID: nil)
        let registry = AccountRegistry.migrated(from: legacy, id: workID)

        expectEqual(registry.accounts.count, 1)
        let account = try require(registry.accounts.first)
        expectEqual(account.id, workID)
        expectEqual(account.name, "Codex account")
        expectEqual(account.source, .local(homePath: "/tmp/codex-work"))
        expectEqual(account.executablePath, "/Applications/Codex.app")
        expect(account.enabled)
    }

    func testRegistryRejectsDuplicateNamesAndHomesAndCapsAtTenAccounts() throws {
        var registry = AccountRegistry()
        try registry.add(AccountConfiguration(id: workID, name: "Work", executablePath: "codex", source: .local(homePath: "/tmp/work")))
        expectThrows(try registry.add(AccountConfiguration(id: personalID, name: "Work", executablePath: "codex", source: .local(homePath: "/tmp/personal"))))
        expectThrows(try registry.add(AccountConfiguration(id: researchID, name: "Research", executablePath: "codex", source: .local(homePath: "/tmp/work"))))
        for index in 0..<9 {
            let id = UUID()
            try registry.add(AccountConfiguration(id: id, name: "Account \(index)", executablePath: "codex", source: .local(homePath: "/tmp/account-\(index)")))
        }
        expectEqual(registry.accounts.count, 10)
        expectThrows(try registry.add(AccountConfiguration(name: "Eleventh", executablePath: "codex", source: .local(homePath: "/tmp/eleventh"))))
    }

    func testAggregateUsesLowestRemainingAndCountsIssues() {
        let summaries = [
            AccountSummary(id: workID, name: "Work", enabled: true, snapshot: snapshot(used: 22), status: .connected),
            AccountSummary(id: personalID, name: "Personal", enabled: true, snapshot: snapshot(used: 67), status: .connected),
            AccountSummary(id: researchID, name: "Research", enabled: true, snapshot: nil, status: .error)
        ]
        let aggregate = MultiAccountPresentation.aggregate(summaries)

        expectEqual(aggregate.accountCount, 3)
        expectEqual(aggregate.issueCount, 1)
        expectEqual(aggregate.lowestRemainingPercent, 33)
        expectEqual(aggregate.secondLowestRemainingPercent, 78)
    }

    func testRefreshBatchExcludesPausedAndLimitsConcurrency() {
        let accounts = (0..<5).map { index in
            AccountConfiguration(id: UUID(), name: "Account \(index)", executablePath: "codex",
                                 source: .local(homePath: "/tmp/account-\(index)"), enabled: index != 3)
        }
        let running = Set([accounts[0].id])
        let batch = RefreshScheduler.nextBatch(accounts: accounts, running: running, limit: 3)

        expectEqual(batch.count, 3)
        expectFalse(batch.contains(accounts[3].id))
        expectFalse(batch.contains(accounts[0].id))
    }

    func testRegistryRenamesAccountWithoutChangingItsIdentityOrHome() throws {
        var registry = AccountRegistry()
        let account = AccountConfiguration(id: workID, name: "Work", executablePath: "codex",
                                           source: .local(homePath: "/tmp/work"))
        try registry.add(account)
        var renamed = account
        renamed.name = "Personal"
        try registry.update(renamed)
        expectEqual(registry.accounts.first?.id, workID)
        expectEqual(registry.accounts.first?.name, "Personal")
        expectEqual(registry.accounts.first?.source.homePath, "/tmp/work")
    }

    func testSummaryUsesResetDateForLowestRemainingWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(observedAt: now, accountFingerprint: "work", buckets: [
            RateBucket(primary: RateWindow(usedPercent: 75, windowDurationMins: 300,
                                           resetsAt: now.addingTimeInterval(86_400).timeIntervalSince1970),
                       secondary: RateWindow(usedPercent: 30, windowDurationMins: 10080,
                                            resetsAt: now.addingTimeInterval(172_800).timeIntervalSince1970))
        ])
        let summary = AccountSummary(id: workID, name: "Work", enabled: true, snapshot: snapshot, status: .connected)
        expectEqual(summary.resetDate, now.addingTimeInterval(86_400))
    }

    private func snapshot(used: Double) -> UsageSnapshot {
        UsageSnapshot(observedAt: Date(timeIntervalSince1970: 1_800_000_000), accountFingerprint: UUID().uuidString,
                      buckets: [RateBucket(primary: RateWindow(usedPercent: used, windowDurationMins: 300, resetsAt: nil),
                                           secondary: RateWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: nil))])
    }
}
