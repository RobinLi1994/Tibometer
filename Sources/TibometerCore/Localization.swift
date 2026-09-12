import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt-BR"
    case italian = "it"
    case dutch = "nl"
    case polish = "pl"
    case russian = "ru"
    case turkish = "tr"
    case indonesian = "id"
    case vietnamese = "vi"

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .system: return L10n.text("language.system")
        case .english: return "English"
        case .chinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .portuguese: return "Português (Brasil)"
        case .italian: return "Italiano"
        case .dutch: return "Nederlands"
        case .polish: return "Polski"
        case .russian: return "Русский"
        case .turkish: return "Türkçe"
        case .indonesian: return "Bahasa Indonesia"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    public var websitePath: String {
        switch resolved() {
        case .english: return "/"
        case .chinese: return "/zh/"
        case .traditionalChinese: return "/zh-Hant/"
        default: return "/\(resolved().rawValue)/"
        }
    }

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
            if parts.first == "zh" {
                if parts.contains("hant") { return .traditionalChinese }
                if parts.contains("hans") { return .chinese }
                return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? .traditionalChinese : .chinese
            }
            if parts.first == "pt" { return .portuguese }
            if let match = Self.allCases.first(where: { $0 != .system && $0.rawValue.lowercased() == parts.first.map(String.init) }) {
                return match
            }
        }
        return .english
    }
}

public enum L10n {
    public static var preference: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appearance.language") ?? "system") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "appearance.language") }
    }
    public static var language: AppLanguage { preference.resolved() }
    public static var locale: Locale { locale(for: language) }
    public static func locale(for language: AppLanguage) -> Locale {
        let resolved = language.resolved()
        switch resolved {
        case .english: return Locale(identifier: "en_US")
        case .chinese: return Locale(identifier: "zh_CN")
        case .traditionalChinese: return Locale(identifier: "zh_TW")
        default: return Locale(identifier: resolved.rawValue)
        }
    }

    public static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Tibometer_TibometerCore.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()
    private static let tables: [AppLanguage: [String: String]] = {
        var result: [AppLanguage: [String: String]] = [:]
        for language in AppLanguage.allCases where language != .system {
            if let path = resources.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language.rawValue),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
                result[language] = table
            }
        }
        return result
    }()
    private static let placeholders = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)

    public static func table(for language: AppLanguage) -> [String: String] { tables[language.resolved()] ?? [:] }

    public static func text(_ key: String, _ arguments: String..., language: AppLanguage? = nil) -> String {
        render(key, arguments: arguments, language: language)
    }

    public static func render(_ key: String, arguments: [String] = [], language: AppLanguage? = nil) -> String {
        let template = table(for: language ?? self.language)[key] ?? tables[.english]?[key] ?? key
        let result = NSMutableString(string: template)
        for match in placeholders.matches(in: template, range: NSRange(location: 0, length: result.length)).reversed() {
            let indexString = (template as NSString).substring(with: match.range(at: 1))
            if let index = Int(indexString), arguments.indices.contains(index) {
                result.replaceCharacters(in: match.range, with: arguments[index])
            }
        }
        return result as String
    }

    public static func date(_ date: Date, dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    public static func countdown(_ date: Date?, now: Date) -> String {
        guard let date else { return text("quota.reset_unknown") }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return text("quota.awaiting_reset") }
        let minutes = max(1, (seconds + 59) / 60)
        if minutes >= 1440 { return text("quota.reset_days", String(minutes / 1440), String(minutes % 1440 / 60)) }
        if minutes >= 60 { return text("quota.reset_hours", String(minutes / 60), String(minutes % 60)) }
        return text("quota.reset_minutes", String(minutes))
    }
}

public struct LocalizedMessage: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    public var key: String
    public var arguments: [String]
    public var localized: String { L10n.render(key, arguments: arguments) }

    public init(_ key: String, _ arguments: String...) { self.key = key; self.arguments = arguments }
    public init(stringLiteral value: String) { self.init(value) }
    private enum CodingKeys: String, CodingKey { case key, arguments }

    public init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            self = Self.migrate(legacy)
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        }
    }

    private static func migrate(_ legacy: String) -> LocalizedMessage {
        let text = legacy.hasPrefix("投递失败：") ? String(legacy.dropFirst("投递失败：".count)) : legacy
        for (key, template) in L10n.table(for: .chinese).sorted(by: { $0.key < $1.key }) {
            if template == text { return .init(key) }
            let parts = template.components(separatedBy: try! NSRegularExpression(pattern: #"\{\d+\}"#))
            guard parts.count > 1 else { continue }
            let pattern = "^" + parts.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "(.*?)") + "$"
            guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            var message = LocalizedMessage(key)
            message.arguments = (1..<match.numberOfRanges).map { (text as NSString).substring(with: match.range(at: $0)) }
            return message
        }
        return .init(legacy)
    }

    public static func from(_ error: Error) -> LocalizedMessage {
        if let error = error as? TibometerError { return error.userMessage }
        if let error = error as? WebhookDeliveryError { return error.message }
        return .init("error.system", String((error as NSError).code))
    }
}

private extension String {
    func components(separatedBy expression: NSRegularExpression) -> [String] {
        let string = self as NSString
        var start = 0
        var result: [String] = []
        for match in expression.matches(in: self, range: NSRange(location: 0, length: string.length)) {
            result.append(string.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = NSMaxRange(match.range)
        }
        result.append(string.substring(from: start))
        return result
    }
}
