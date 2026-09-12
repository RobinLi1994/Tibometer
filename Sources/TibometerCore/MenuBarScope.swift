import Foundation

public enum MenuBarScope: String, CaseIterable, Identifiable, Sendable {
    case fiveHour = "5h"
    case weekly = "7d"
    case both

    public var id: String { rawValue }
    public var title: String { L10n.text("menu_scope.\(rawValue)") }

    public func includes(_ window: QuotaWindow) -> Bool {
        self == .both || (self == .fiveHour && window == .fiveHour) || (self == .weekly && window == .weekly)
    }

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: "appearance.menuBarScope") ?? "") ?? .both
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "appearance.menuBarScope")
    }
}
