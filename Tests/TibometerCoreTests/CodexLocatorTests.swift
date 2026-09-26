import Foundation
import TibometerCore

struct CodexLocatorTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tibometer locator \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func executable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func testRegisteredApplicationDoesNotDependOnItsNameOrLocation() throws {
        try withDirectory { directory in
            let missing = directory.appendingPathComponent("Codex.app")
            let renamed = directory.appendingPathComponent("Other Apps/ChatGPT Preview.app")
            let binary = renamed.appendingPathComponent("Contents/Resources/codex")
            try executable(at: binary)
            expectEqual(try CodexLocator.executable(applications: [missing, renamed]), binary.path)
        }
    }

    func testMissingRegistrationRequiresManualSelection() throws {
        try withDirectory { directory in
            let binary = directory.appendingPathComponent("bin/codex")
            try executable(at: binary)
            do {
                _ = try CodexLocator.executable(applications: [])
                Checks.fail("Expected manual selection when no application is registered")
            } catch { expectEqual(error as? TibometerError, .executableMissing) }
            expectEqual(try CodexLocator.executable(custom: binary.path, applications: []), binary.path)
        }
    }

    func testNestedCLIBundleSupportsAutomaticAndManualDiscovery() throws {
        try withDirectory { directory in
            let app = directory.appendingPathComponent("ChatGPT.app")
            let binary = app.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
            try executable(at: binary)
            expectEqual(try CodexLocator.executable(applications: [app]), binary.path)
            expectEqual(try CodexLocator.executable(custom: app.path, applications: []), binary.path)
        }
    }

    func testManuallySelectedApplicationResolvesItsBundledExecutable() throws {
        try withDirectory { directory in
            let app = directory.appendingPathComponent("Other Apps/ChatGPT Preview.app")
            let binary = app.appendingPathComponent("Contents/Resources/codex")
            try executable(at: binary)
            expectEqual(try CodexLocator.executable(custom: app.path, applications: []), binary.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: binary.path)
            expectThrows(try CodexLocator.executable(custom: app.path, applications: []))
        }
    }

    func testCustomPathIsAuthoritativeAndDirectoriesAreRejected() throws {
        try withDirectory { directory in
            let app = directory.appendingPathComponent("Codex.app")
            let bundled = app.appendingPathComponent("Contents/Resources/codex")
            let custom = directory.appendingPathComponent("custom-codex")
            try executable(at: bundled)
            try executable(at: custom)
            expectEqual(try CodexLocator.executable(custom: "  \(custom.path)\n", applications: [app]), custom.path)
            for invalid in [directory.appendingPathComponent("missing.app").path, directory.path, "relative/codex"] {
                do {
                    _ = try CodexLocator.executable(custom: invalid, applications: [app])
                    Checks.fail("Expected invalid custom path to be rejected")
                } catch { expectEqual(error as? TibometerError, .executableMissing) }
            }
            try FileManager.default.removeItem(at: custom)
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("codex"), withIntermediateDirectories: true)
            expectThrows(try CodexLocator.executable(custom: directory.appendingPathComponent("codex").path, applications: []))
        }
    }
}
