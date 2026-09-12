import Foundation

public enum MenuBarPresentation {
    public struct Item: Equatable, Sendable {
        public var window: QuotaWindow
        public var remainingPercent: Double
        public var percentageText: String
        public var text: String { "\(window.shortTitle) \(percentageText)" }
    }

    public static func items(in bucket: RateBucket?, scope: MenuBarScope = .both) -> [Item] {
        guard bucket?.id == "codex" else { return [] }
        return QuotaWindow.allCases.compactMap { kind in
            guard scope.includes(kind), let window = bucket?.window(kind), let remaining = window.remainingPercent else { return nil }
            return Item(window: kind, remainingPercent: remaining, percentageText: window.percentageText)
        }
    }

    public static func visibleWindows(in bucket: RateBucket?) -> [QuotaWindow] {
        items(in: bucket).map(\.window)
    }

    public static func title(bucket: RateBucket?, stale: Bool = false, scope: MenuBarScope = .both) -> String {
        let parts = items(in: bucket, scope: scope).map(\.text)
        guard !parts.isEmpty else { return L10n.text("quota.empty") }
        return (stale ? "! " : "") + parts.joined(separator: " · ")
    }
}
