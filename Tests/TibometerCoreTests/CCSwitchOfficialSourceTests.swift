import Foundation
import SQLite3
import TibometerCore

struct CCSwitchOfficialSourceTests {
    private func token(subject: String) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let payload = Data("{\"sub\":\"\(subject)\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return "\(header).\(payload).signature"
    }

    private func fixture(_ body: (CCSwitchOfficialSource, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tibometer-cc-switch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("cc-switch.db")
        let store = root.appendingPathComponent("codex_oauth_auth.json")
        let home = root.appendingPathComponent("official-home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        var connection: OpaquePointer?
        guard sqlite3_open(database.path, &connection) == SQLITE_OK, let connection else { throw MissingValue() }
        defer { sqlite3_close(connection) }
        guard sqlite3_exec(connection, "CREATE TABLE providers (id TEXT, app_type TEXT, name TEXT, category TEXT, meta TEXT, sort_index INTEGER)", nil, nil, nil) == SQLITE_OK else { throw MissingValue() }
        let meta = #"{"authBinding":{"source":"managed_account","authProvider":"codex_oauth","accountId":"local-a"}}"#
        let sql = "INSERT INTO providers VALUES ('official-a','codex','OpenAI Official','official','\(meta)',0)"
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw MissingValue() }
        guard sqlite3_exec(connection, "INSERT INTO providers VALUES ('proxy','codex','Proxy','third_party','{}',1)", nil, nil, nil) == SQLITE_OK else { throw MissingValue() }

        let managed: [String: Any] = ["accounts": ["local-a": ["chatgpt_account_id": "workspace-a", "id_token": token(subject: "user-a")]]]
        try JSONSerialization.data(withJSONObject: managed).write(to: store)
        let native: [String: Any] = ["auth_mode": "chatgpt", "tokens": ["account_id": "workspace-a", "id_token": token(subject: "user-a")]]
        try JSONSerialization.data(withJSONObject: native).write(to: home.appendingPathComponent("auth.json"))
        try body(CCSwitchOfficialSource(databaseURL: database, accountStoreURL: store), home, database)
    }

    func testFindsOnlyBoundOfficialProviderAndAcceptsMatchingLogin() throws {
        try fixture { source, home, _ in
            let providers = try source.providers()
            expectEqual(providers.map(\.id), ["official-a"])
            expectEqual(providers.first?.name, "OpenAI Official")
            let before = try Data(contentsOf: source.accountStoreURL)
            expectNoThrow(try source.validate(providerID: "official-a", codexHome: home))
            expectEqual(try Data(contentsOf: source.accountStoreURL), before)
        }
    }

    func testProviderRebindingInvalidatesPreviousLogin() throws {
        try fixture { source, home, database in
            var connection: OpaquePointer?
            guard sqlite3_open(database.path, &connection) == SQLITE_OK, let connection else { throw MissingValue() }
            defer { sqlite3_close(connection) }
            let meta = #"{"authBinding":{"source":"managed_account","authProvider":"codex_oauth","accountId":"local-b"}}"#
            guard sqlite3_exec(connection, "UPDATE providers SET meta='\(meta)' WHERE id='official-a'", nil, nil, nil) == SQLITE_OK else { throw MissingValue() }
            do { try source.validate(providerID: "official-a", codexHome: home); Checks.fail("Expected changed account binding to stop monitoring") }
            catch { expectEqual(error as? TibometerError, .officialProviderMissing) }
        }
    }

    func testRejectsWrongUserInSameWorkspace() throws {
        try fixture { source, home, _ in
            let native: [String: Any] = ["auth_mode": "chatgpt", "tokens": ["account_id": "workspace-a", "id_token": token(subject: "user-b")]]
            try JSONSerialization.data(withJSONObject: native).write(to: home.appendingPathComponent("auth.json"))
            do { try source.validate(providerID: "official-a", codexHome: home); Checks.fail("Expected account mismatch") }
            catch { expectEqual(error as? TibometerError, .accountMismatch) }
        }
    }

    func testRejectsMissingLoginAndMissingProvider() throws {
        try fixture { source, home, _ in
            try FileManager.default.removeItem(at: home.appendingPathComponent("auth.json"))
            do { try source.validate(providerID: "official-a", codexHome: home); Checks.fail("Expected login required") }
            catch { expectEqual(error as? TibometerError, .isolatedLoginRequired) }
            do { try source.validate(providerID: "proxy", codexHome: home); Checks.fail("Expected official provider required") }
            catch { expectEqual(error as? TibometerError, .officialProviderMissing) }
        }
    }

    func testIsolatedHomeDoesNotOverwriteExistingConfig() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tibometer-official-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try OfficialCodexHome.prepare(at: root)
        let config = root.appendingPathComponent("config.toml")
        expectEqual(try String(contentsOf: config, encoding: .utf8), "cli_auth_credentials_store = \"file\"\n")
        try Data("custom = true\n".utf8).write(to: config)
        try OfficialCodexHome.prepare(at: root)
        expectEqual(try String(contentsOf: config, encoding: .utf8), "custom = true\n")
        let command = OfficialCodexHome.loginCommand(executable: "/Applications/Codex CLI/codex", home: root)
        expect(command.contains("CODEX_HOME='\(root.path)'"))
        expect(command.contains("'/Applications/Codex CLI/codex' login"))
    }
}
