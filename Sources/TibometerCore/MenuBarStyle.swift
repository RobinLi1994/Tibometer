import Foundation

public enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case percentage
    case bars
    case barsPercentage = "bars_percentage"
    case rings
    case ringsPercentage = "rings_percentage"

    public var id: String { rawValue }
    public var title: String { L10n.text("menu_style.\(rawValue)") }
    public var usesBars: Bool { self == .bars || self == .barsPercentage }
    public var usesRings: Bool { self == .rings || self == .ringsPercentage }
    public var showsPercentage: Bool { self == .percentage || self == .barsPercentage || self == .ringsPercentage }

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        let stored = defaults.string(forKey: "appearance.menuBarStyle") ?? ""
        if stored == "text" || stored == "stacked" { return .percentage }
        return Self(rawValue: stored) ?? .percentage
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "appearance.menuBarStyle")
    }
}
