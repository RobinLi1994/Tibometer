import Foundation
import TibometerCore

@main
struct Probe {
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            func option(_ name: String) -> String {
                guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return "" }
                return arguments[index + 1]
            }
            if arguments.contains("--webhook-test") {
                let config = WebhookConfiguration(url: option("--webhook-test"), format: WebhookFormat(rawValue: option("--format")) ?? .json,
                    bearerToken: ProcessInfo.processInfo.environment["TIBOMETER_WEBHOOK_TOKEN"] ?? "",
                    signingSecret: ProcessInfo.processInfo.environment["TIBOMETER_WEBHOOK_SECRET"] ?? "")
                try await WebhookSender().send(event: .testEvent(), configuration: config, isTest: true)
                print("Webhook test delivered")
                return
            }
            let configuration = CodexConfiguration(executablePath: option("--codex"), homePath: option("--codex-home"))
            if arguments.contains("--recent-threads") {
                try printJSON(await CodexClient().recentThreads(configuration: configuration))
                return
            }
            if arguments.contains("--thread-usage") {
                let id = option("--thread-usage")
                let usage = try await CodexClient().threadUsage(threadID: id, configuration: configuration)
                struct Output: Encodable { var requestedThreadId: String; var available: Bool; var threadUsage: ThreadUsage? }
                try printJSON(Output(requestedThreadId: id, available: usage != nil, threadUsage: usage))
                return
            }
            let snapshot = try await CodexClient().fetch(configuration: configuration)
            struct Output: Encodable { var observedAt: Date; var buckets: [RateBucket] }
            try printJSON(Output(observedAt: snapshot.observedAt, buckets: snapshot.buckets))
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}
