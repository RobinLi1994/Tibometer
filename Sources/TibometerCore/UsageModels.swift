import Foundation
import CryptoKit

public enum QuotaWindow: Int, Codable, CaseIterable, Identifiable, Sendable {
    case fiveHour = 300
    case weekly = 10080

    public var id: Int { rawValue }
    public var title: String { L10n.text(self == .fiveHour ? "quota.five_hour" : "quota.weekly") }
    public var shortTitle: String { self == .fiveHour ? "5H" : "7D" }
    public var apiName: String { self == .fiveHour ? "five_hour" : "weekly" }
}

public struct RateWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double?
    public var windowDurationMins: Int?
    public var resetsAt: Double?

    public init(usedPercent: Double?, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public var validUsedPercent: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, usedPercent))
    }
    public var remainingPercent: Double? { validUsedPercent.map { 100 - $0 } }
    public var resetDate: Date? {
        guard let resetsAt, resetsAt.isFinite, resetsAt > 0 else { return nil }
        return Date(timeIntervalSince1970: resetsAt)
    }
    public var percentageText: String {
        guard let remainingPercent else { return "—" }
        // Round down so only an unused window displays 100%.
        if remainingPercent > 0 && remainingPercent < 1 { return "<1%" }
        return "\(Int(remainingPercent.rounded(.down)))%"
    }
}

public struct RateBucket: Codable, Equatable, Identifiable, Sendable {
    public var limitId: String?
    public var limitName: String?
    public var primary: RateWindow?
    public var secondary: RateWindow?
    public var planType: String?
    public var credits: CreditsSnapshot?

    public init(limitId: String? = "codex", limitName: String? = nil, primary: RateWindow?, secondary: RateWindow?, planType: String? = nil, credits: CreditsSnapshot? = nil) {
        self.limitId = limitId
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.credits = credits
    }

    public var id: String { limitId ?? "codex" }
    public var title: String {
        if id == "codex" { return "Codex" }
        return limitName ?? id
    }
    public func window(_ kind: QuotaWindow) -> RateWindow? {
        [primary, secondary].compactMap { $0 }.first { $0.windowDurationMins == kind.rawValue }
    }
}

public struct RateLimitsResponse: Codable, Sendable {
    public var rateLimits: RateBucket?
    public var rateLimitsByLimitId: [String: RateBucket]?
    public var accountId: String?

    public init(rateLimits: RateBucket?, rateLimitsByLimitId: [String: RateBucket]? = nil, accountId: String? = nil) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
        self.accountId = accountId
    }

    public var buckets: [RateBucket] {
        if let map = rateLimitsByLimitId, !map.isEmpty {
            guard var bucket = map["codex"] else { return [] }
            bucket.limitId = "codex"
            return [bucket]
        }
        guard let rateLimits, rateLimits.id == "codex" else { return [] }
        return [rateLimits]
    }
}

public struct UsageSnapshot: Codable, Sendable {
    public var observedAt: Date
    public var accountFingerprint: String
    public var buckets: [RateBucket]

    public init(observedAt: Date, accountFingerprint: String, buckets: [RateBucket]) {
        self.observedAt = observedAt
        self.accountFingerprint = accountFingerprint
        self.buckets = buckets
    }

    public var codexBucket: RateBucket? { buckets.first { $0.id == "codex" } }

    public var codexOnly: UsageSnapshot {
        var value = self
        value.buckets = codexBucket.map { [$0] } ?? []
        return value
    }

    public static func fingerprint(_ identity: String) -> String {
        SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum ResetReason: String, Codable, Sendable {
    case newWindow = "new_window"
    case restoredToFull = "restored_to_full"
}

public struct ResetEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var observedAt: Date
    public var bucketId: String
    public var bucketName: String
    public var window: QuotaWindow
    public var previousUsedPercent: Double
    public var remainingPercent: Double
    public var previousResetAt: Date?
    public var nextResetAt: Date?
    public var reason: ResetReason

    public var title: String { L10n.text("reset.title", bucketName, window.title) }
    public var notificationTitle: String { L10n.text("reset.headline") }
    public var message: String { L10n.text("reset.full") }

    public static func testEvent(now: Date = Date()) -> ResetEvent {
        ResetEvent(id: UUID().uuidString, observedAt: now, bucketId: "codex", bucketName: "Codex", window: .fiveHour,
                   previousUsedPercent: 85, remainingPercent: 100, previousResetAt: now,
                   nextResetAt: now.addingTimeInterval(18000), reason: .restoredToFull)
    }
}
