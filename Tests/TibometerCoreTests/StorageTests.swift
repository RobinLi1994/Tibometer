import Foundation
import TibometerCore

final class StorageTests {
    private func withStore(_ body: (WebhookConfigurationStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tibometer-storage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(WebhookConfigurationStore(directory: directory))
    }

    func testMissingConfigurationStartsEmpty() throws {
        try withStore { store in
            expectEqual(try store.load(), WebhookConfiguration())
            expectFalse(FileManager.default.fileExists(atPath: store.url.path))
        }
    }

    func testPrivateFileSurvivesReopenAndOverwrite() throws {
        try withStore { store in
            let original = WebhookConfiguration(url: "http://127.0.0.1/hook", format: .json, bearerToken: "fixture-token", signingSecret: "fixture-secret")
            try store.save(original)
            expectEqual(try WebhookConfigurationStore(directory: store.directory).load(), original)
            let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
            expectEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            let directoryAttributes = try FileManager.default.attributesOfItem(atPath: store.directory.path)
            expectEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
            let updated = WebhookConfiguration(url: "http://localhost/updated", format: .feishu, signingSecret: "updated-fixture")
            try store.save(updated)
            expectEqual(try store.load(), updated)
            let newAttributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
            expectEqual((newAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            expectEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path), ["webhook.json"])
        }
    }

    func testDamagedFileReportsErrorWithoutOverwritingIt() throws {
        try withStore { store in
            try store.save(.init())
            let invalid = Data("invalid JSON fixture".utf8)
            try invalid.write(to: store.url)
            do { _ = try store.load(); Checks.fail("Expected unreadable configuration") }
            catch { expectEqual(LocalizedMessage.from(error).key, "error.config_read") }
            expectEqual(try Data(contentsOf: store.url), invalid)
        }
    }

    func testFailedWriteKeepsExistingDestinationAndRemovesTemporaryFiles() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: true)
            do { try store.save(.init()); Checks.fail("Expected destination conflict") }
            catch { expectEqual(LocalizedMessage.from(error).key, "error.config_write") }
            var directory: ObjCBool = false
            expect(FileManager.default.fileExists(atPath: store.url.path, isDirectory: &directory))
            expect(directory.boolValue)
            expectEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path), ["webhook.json"])
        }
    }
}
