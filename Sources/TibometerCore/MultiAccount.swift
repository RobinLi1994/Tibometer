import Foundation

public enum AccountSource: Codable, Equatable, Sendable {
    case local(homePath: String)
    case ccSwitch(providerID: String, homePath: String)

    public var homePath: String {
        switch self {
        case let .local(homePath), let .ccSwitch(_, homePath): return homePath
        }
    }

    public var providerID: String? {
        if case let .ccSwitch(providerID, _) = self { return providerID }
        return nil
    }
}

public struct AccountConfiguration: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var executablePath: String
    public var source: AccountSource
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, executablePath: String, source: AccountSource, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.source = source
        self.enabled = enabled
    }
}

public struct LegacyAccountSettings: Codable, Equatable, Sendable {
    public var executablePath: String
    public var homePath: String
    public var ccSwitchProviderID: String?

    public init(executablePath: String, homePath: String, ccSwitchProviderID: String?) {
        self.executablePath = executablePath
        self.homePath = homePath
        self.ccSwitchProviderID = ccSwitchProviderID
    }
}

public enum AccountRegistryError: Error, Equatable, Sendable {
    case maximumReached
    case duplicateName
    case duplicateHome
    case duplicateID
    case invalidName
}

public struct AccountRegistry: Codable, Equatable, Sendable {
    public static let maximumAccountCount = 10
    public private(set) var accounts: [AccountConfiguration]

    public init(accounts: [AccountConfiguration] = []) {
        self.accounts = accounts
    }

    public static func migrated(from legacy: LegacyAccountSettings, id: UUID = UUID()) -> AccountRegistry {
        let source: AccountSource = if let providerID = legacy.ccSwitchProviderID {
            .ccSwitch(providerID: providerID, homePath: legacy.homePath)
        } else {
            .local(homePath: legacy.homePath)
        }
        return AccountRegistry(accounts: [AccountConfiguration(id: id, name: "Codex account",
                                                                executablePath: legacy.executablePath, source: source)])
    }

    public mutating func add(_ account: AccountConfiguration) throws {
        try validate(account, excluding: nil)
        accounts.append(account)
    }

    public mutating func update(_ account: AccountConfiguration) throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw AccountRegistryError.duplicateID
        }
        try validate(account, excluding: account.id)
        accounts[index] = account
    }

    public mutating func remove(id: UUID) {
        accounts.removeAll { $0.id == id }
    }

    private func validate(_ account: AccountConfiguration, excluding id: UUID?) throws {
        guard !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AccountRegistryError.invalidName
        }
        if id == nil && accounts.count >= Self.maximumAccountCount { throw AccountRegistryError.maximumReached }
        if accounts.contains(where: { $0.id != id && $0.id == account.id }) { throw AccountRegistryError.duplicateID }
        if accounts.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(account.name) == .orderedSame }) {
            throw AccountRegistryError.duplicateName
        }
        if accounts.contains(where: { $0.id != id && $0.source.homePath == account.source.homePath }) {
            throw AccountRegistryError.duplicateHome
        }
    }
}

public enum AccountConnectionStatus: String, Codable, Equatable, Sendable {
    case connected
    case refreshing
    case error
    case stale
    case paused
    case connecting
}

public struct AccountSummary: Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var snapshot: UsageSnapshot?
    public var status: AccountConnectionStatus

    public init(id: UUID, name: String, enabled: Bool, snapshot: UsageSnapshot?, status: AccountConnectionStatus) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.snapshot = snapshot
        self.status = status
    }

    public var remainingPercent: Double? {
        snapshot?.codexBucket.flatMap { bucket in
            QuotaWindow.allCases.compactMap { bucket.window($0)?.remainingPercent }.min()
        }
    }

    public func remainingPercent(for kind: QuotaWindow) -> Double? {
        snapshot?.codexBucket?.window(kind)?.remainingPercent
    }

    public var resetDate: Date? {
        guard let bucket = snapshot?.codexBucket else { return nil }
        return QuotaWindow.allCases
            .compactMap { bucket.window($0) }
            .filter { $0.remainingPercent != nil }
            .min { ($0.remainingPercent ?? .greatestFiniteMagnitude) < ($1.remainingPercent ?? .greatestFiniteMagnitude) }?
            .resetDate
    }
}

public struct MultiAccountAggregate: Equatable, Sendable {
    public var accountCount: Int
    public var issueCount: Int
    public var lowestRemainingPercent: Int?
    public var secondLowestRemainingPercent: Int?

    public init(accountCount: Int, issueCount: Int, lowestRemainingPercent: Int?, secondLowestRemainingPercent: Int? = nil) {
        self.accountCount = accountCount
        self.issueCount = issueCount
        self.lowestRemainingPercent = lowestRemainingPercent
        self.secondLowestRemainingPercent = secondLowestRemainingPercent
    }
}

public enum MultiAccountPresentation {
    public static func aggregate(_ accounts: [AccountSummary]) -> MultiAccountAggregate {
        let issues = accounts.filter { !$0.enabled || $0.status != .connected }.count
        let lowestValues = accounts.compactMap(\.remainingPercent).map { Int($0.rounded(.down)) }.sorted()
        return MultiAccountAggregate(accountCount: accounts.count, issueCount: issues,
                                     lowestRemainingPercent: lowestValues.first,
                                     secondLowestRemainingPercent: lowestValues.dropFirst().first)
    }
}

public enum RefreshScheduler {
    public static func nextBatch(accounts: [AccountConfiguration], running: Set<UUID>, limit: Int = 3) -> [UUID] {
        guard limit > 0 else { return [] }
        return accounts.filter { $0.enabled && !running.contains($0.id) }.prefix(limit).map(\.id)
    }
}
