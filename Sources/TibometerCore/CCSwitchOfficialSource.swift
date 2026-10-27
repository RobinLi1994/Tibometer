import Foundation
import SQLite3

public struct CCSwitchOfficialProvider: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
}

public struct CCSwitchOfficialSource: Sendable {
    public let databaseURL: URL
    public let accountStoreURL: URL

    public init(databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-switch/cc-switch.db"),
                accountStoreURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-switch/codex_oauth_auth.json")) {
        self.databaseURL = databaseURL
        self.accountStoreURL = accountStoreURL
    }

    public func providers() throws -> [CCSwitchOfficialProvider] {
        try bindings().map { CCSwitchOfficialProvider(id: $0.providerID, name: $0.name) }
    }

    public func validate(providerID: String, codexHome: URL) throws {
        guard let binding = try bindings().first(where: { $0.providerID == providerID }) else {
            throw TibometerError.officialProviderMissing
        }
        guard let storeData = try? Data(contentsOf: accountStoreURL),
              let store = try? JSONSerialization.jsonObject(with: storeData) as? [String: Any] else {
            throw TibometerError.officialProviderMissing
        }
        let accounts = store["accounts"] as? [String: [String: Any]]
        guard let managed = accounts?[binding.accountID],
              let workspace = managed["chatgpt_account_id"] as? String,
              let managedToken = managed["id_token"] as? String,
              let managedSubject = Self.subject(in: managedToken) else {
            throw TibometerError.officialProviderMissing
        }
        let authURL = codexHome.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              auth["auth_mode"] as? String == "chatgpt",
              let tokens = auth["tokens"] as? [String: Any],
              let nativeWorkspace = tokens["account_id"] as? String,
              let nativeToken = tokens["id_token"] as? String,
              let nativeSubject = Self.subject(in: nativeToken) else {
            throw TibometerError.isolatedLoginRequired
        }
        guard workspace == nativeWorkspace && managedSubject == nativeSubject else {
            throw TibometerError.accountMismatch
        }
    }

    private struct Binding {
        let providerID: String
        let name: String
        let accountID: String
    }

    private func bindings() throws -> [Binding] {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let connection else {
            if connection != nil { sqlite3_close(connection) }
            throw TibometerError.ccSwitchUnavailable
        }
        defer { sqlite3_close(connection) }
        let sql = "SELECT id, name, meta FROM providers WHERE app_type = 'codex' AND category = 'official' ORDER BY sort_index, name"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TibometerError.ccSwitchUnavailable
        }
        defer { sqlite3_finalize(statement) }
        var result: [Binding] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idValue = sqlite3_column_text(statement, 0),
                  let nameValue = sqlite3_column_text(statement, 1),
                  let metaValue = sqlite3_column_text(statement, 2),
                  let meta = try? JSONSerialization.jsonObject(with: Data(String(cString: metaValue).utf8)) as? [String: Any],
                  let auth = meta["authBinding"] as? [String: Any],
                  auth["source"] as? String == "managed_account",
                  auth["authProvider"] as? String == "codex_oauth",
                  let accountID = auth["accountId"] as? String, !accountID.isEmpty else { continue }
            result.append(Binding(providerID: String(cString: idValue), name: String(cString: nameValue), accountID: accountID))
        }
        guard sqlite3_errcode(connection) == SQLITE_OK || sqlite3_errcode(connection) == SQLITE_DONE else {
            throw TibometerError.ccSwitchUnavailable
        }
        return result
    }

    private static func subject(in token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = claims["sub"] as? String, !subject.isEmpty else { return nil }
        return subject
    }
}

public enum OfficialCodexHome {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tibometer/OfficialCodex", isDirectory: true)
    }

    public static func prepare(at url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let config = url.appendingPathComponent("config.toml")
        if !FileManager.default.fileExists(atPath: config.path) {
            try Data("cli_auth_credentials_store = \"file\"\n".utf8).write(to: config, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        }
    }

    public static func loginCommand(executable: String, home: URL = defaultURL) -> String {
        func quote(_ value: String) -> String { "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'" }
        return "CODEX_HOME=\(quote(home.path)) \(quote(executable)) login"
    }
}
