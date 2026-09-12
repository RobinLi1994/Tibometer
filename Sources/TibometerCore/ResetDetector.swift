import Foundation

public struct ResetDetector: Codable, Sendable {
    private struct Observation: Codable, Sendable {
        var window: RateWindow
        var observedAt: Date
    }
    private var accountFingerprint: String?
    private var observations: [String: Observation] = [:]
    private var lastObservedAt: Date?

    public init() {}

    public mutating func retainCodexOnly() {
        observations = observations.filter { $0.key.hasPrefix("codex:") }
    }

    public mutating func observe(_ snapshot: UsageSnapshot) -> [ResetEvent] {
        retainCodexOnly()
        if snapshot.accountFingerprint != accountFingerprint {
            accountFingerprint = snapshot.accountFingerprint
            observations = [:]
            lastObservedAt = nil
        }
        guard lastObservedAt.map({ snapshot.observedAt > $0 }) ?? true else { return [] }
        lastObservedAt = snapshot.observedAt
        var events: [ResetEvent] = []
        for bucket in snapshot.buckets where bucket.id == "codex" {
            for kind in QuotaWindow.allCases {
                let key = "\(bucket.id):\(kind.rawValue)"
                guard let current = bucket.window(kind), let currentUsed = current.validUsedPercent else {
                    // Preserve the last valid baseline while this window is unavailable.
                    continue
                }
                defer { observations[key] = Observation(window: current, observedAt: snapshot.observedAt) }
                guard let old = observations[key], let oldUsed = old.window.validUsedPercent else { continue }
                let restored = oldUsed > 0 && currentUsed == 0
                let advanced: Bool
                if let oldReset = old.window.resetDate, let nextReset = current.resetDate {
                    advanced = snapshot.observedAt >= oldReset && nextReset > snapshot.observedAt
                        && nextReset.timeIntervalSince(oldReset) > 60
                } else {
                    advanced = false
                }
                guard restored || advanced else { continue }
                events.append(ResetEvent(
                    id: UUID().uuidString, observedAt: snapshot.observedAt, bucketId: bucket.id, bucketName: bucket.title,
                    window: kind, previousUsedPercent: oldUsed, remainingPercent: 100 - currentUsed,
                    previousResetAt: old.window.resetDate, nextResetAt: current.resetDate,
                    reason: restored ? .restoredToFull : .newWindow
                ))
            }
        }
        return events
    }
}

public enum RefreshSchedule {
    public static func delay(snapshot: UsageSnapshot?, now: Date, interval: TimeInterval, failures: Int = 0) -> TimeInterval {
        let base = min(300, max(15, interval))
        if failures > 0 { return min(300, base * pow(2, Double(min(4, failures - 1)))) }
        let resets = snapshot?.codexOnly.buckets.flatMap { bucket in
            QuotaWindow.allCases.compactMap { bucket.window($0)?.resetDate }
        } ?? []
        let candidates = resets.compactMap { date -> TimeInterval? in
            let seconds = date.timeIntervalSince(now)
            if seconds > 0 { return max(2, seconds + 2) }
            if seconds > -120 { return 10 }
            return nil
        }
        return min(base, candidates.min() ?? base)
    }
}
