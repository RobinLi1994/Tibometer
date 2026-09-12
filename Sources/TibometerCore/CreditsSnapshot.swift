import Foundation

public struct CreditsSnapshot: Codable, Equatable, Sendable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    public var balanceValue: Decimal? {
        guard let text = balance?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { return nil }
        return value
    }

    public var shouldDisplay: Bool {
        unlimited || balanceValue != Decimal.zero
    }

    public var displayText: String {
        if unlimited { return L10n.text("credits.unlimited") }
        guard let value = balanceValue else {
            return L10n.text(hasCredits ? "credits.available" : "credits.none")
        }
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 38
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }
}
