import Foundation
import TibometerCore

struct Settings: Codable, Equatable {
    var refreshInterval: Double = 30
    var notificationsEnabled = true
    var notificationSound = true
    var webhookEnabled = false
    var codexPath = ""
    var codexHome = ""
    var ccSwitchProviderID: String?
    var accounts: [AccountConfiguration] = []

    private enum CodingKeys: String, CodingKey {
        case refreshInterval, notificationsEnabled, notificationSound, webhookEnabled
        case codexPath, codexHome, ccSwitchProviderID, accounts
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refreshInterval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 30
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        notificationSound = try container.decodeIfPresent(Bool.self, forKey: .notificationSound) ?? true
        webhookEnabled = try container.decodeIfPresent(Bool.self, forKey: .webhookEnabled) ?? false
        codexPath = try container.decodeIfPresent(String.self, forKey: .codexPath) ?? ""
        codexHome = try container.decodeIfPresent(String.self, forKey: .codexHome) ?? ""
        ccSwitchProviderID = try container.decodeIfPresent(String.self, forKey: .ccSwitchProviderID)
        accounts = try container.decodeIfPresent([AccountConfiguration].self, forKey: .accounts) ?? []
    }

    var configuredAccounts: [AccountConfiguration] {
        if !accounts.isEmpty { return accounts }
        guard !codexHome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ccSwitchProviderID != nil else { return [] }
        let homePath = ccSwitchProviderID == nil ? codexHome : OfficialCodexHome.defaultURL.path
        return AccountRegistry.migrated(from: LegacyAccountSettings(executablePath: codexPath, homePath: homePath,
                                                                     ccSwitchProviderID: ccSwitchProviderID)).accounts
    }

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: "settings"),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "settings") }
    }
}

struct EventRecord: Codable, Identifiable {
    var event: ResetEvent
    var accountName: String?
    var localStatus: LocalizedMessage
    var webhookStatus: LocalizedMessage
    var webhookFingerprint: String?
    var webhookAttempts = 0
    var nextAttemptAt: Date?
    var webhookPending: Bool
    var localPending: Bool
    var id: String { event.id }
}

struct MonitorState: Codable {
    var detector = ResetDetector()
    var snapshot: UsageSnapshot?
    var records: [EventRecord] = []
}

struct MultiMonitorState: Codable {
    var states: [UUID: MonitorState] = [:]
}

struct StateStore {
    let directory: URL
    var url: URL { directory.appendingPathComponent("state.json") }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tibometer", isDirectory: true)
    }

    func load() throws -> MonitorState {
        guard FileManager.default.fileExists(atPath: url.path) else { return MonitorState() }
        let data = try Data(contentsOf: url)
        if let multi = try? JSONDecoder().decode(MultiMonitorState.self, from: data) {
            return multi.states.values.first ?? MonitorState()
        }
        return try JSONDecoder().decode(MonitorState.self, from: data)
    }

    func loadMulti(firstAccountID: UUID?) throws -> MultiMonitorState {
        guard FileManager.default.fileExists(atPath: url.path) else { return MultiMonitorState() }
        let data = try Data(contentsOf: url)
        if let multi = try? JSONDecoder().decode(MultiMonitorState.self, from: data) { return multi }
        let legacy = try JSONDecoder().decode(MonitorState.self, from: data)
        guard let firstAccountID else { return MultiMonitorState() }
        return MultiMonitorState(states: [firstAccountID: legacy])
    }

    func save(_ state: MonitorState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func saveMulti(_ state: MultiMonitorState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
