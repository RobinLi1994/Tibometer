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

struct StateStore {
    let directory: URL
    var url: URL { directory.appendingPathComponent("state.json") }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tibometer", isDirectory: true)
    }

    func load() throws -> MonitorState {
        guard FileManager.default.fileExists(atPath: url.path) else { return MonitorState() }
        return try JSONDecoder().decode(MonitorState.self, from: Data(contentsOf: url))
    }

    func save(_ state: MonitorState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
