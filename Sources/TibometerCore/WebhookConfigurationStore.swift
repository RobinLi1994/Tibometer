import Foundation
import Darwin

public struct WebhookConfigurationStore: Sendable {
    public let directory: URL
    public var url: URL { directory.appendingPathComponent("webhook.json") }

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tibometer", isDirectory: true)
    }

    public func load() throws -> WebhookConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        do { return try JSONDecoder().decode(WebhookConfiguration.self, from: Data(contentsOf: url)) }
        catch { throw TibometerError.webhook(.init("error.config_read", String((error as NSError).code))) }
    }

    public func save(_ configuration: WebhookConfiguration) throws {
        let temporary = directory.appendingPathComponent(".webhook-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configuration)
            // The file is private from creation, including before the atomic replacement.
            guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard Darwin.rename(temporary.path, url.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            throw TibometerError.webhook(.init("error.config_write", String((error as NSError).code)))
        }
    }
}
