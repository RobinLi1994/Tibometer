import Foundation
import CryptoKit

public enum WebhookFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case json
    case slack
    case discord
    case feishu
    case wecom

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .json: return L10n.text("webhook.json")
        case .slack: return "Slack"
        case .discord: return "Discord"
        case .feishu: return L10n.text("webhook.feishu")
        case .wecom: return L10n.text("webhook.wecom")
        }
    }
}

public struct WebhookConfiguration: Codable, Equatable, Sendable {
    public var url: String
    public var format: WebhookFormat
    public var bearerToken: String
    public var signingSecret: String

    public init(url: String = "", format: WebhookFormat = .json, bearerToken: String = "", signingSecret: String = "") {
        self.url = url
        self.format = format
        self.bearerToken = bearerToken
        self.signingSecret = signingSecret
    }

    public var fingerprint: String { UsageSnapshot.fingerprint("\(format.rawValue):\(url)") }

    public func validatedURL() throws -> URL {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty, let target = components.url,
              components.user == nil, components.password == nil, components.fragment == nil else {
            throw TibometerError.webhook("error.url")
        }
        let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        guard components.scheme?.lowercased() == "https" || (components.scheme?.lowercased() == "http" && loopback) else {
            throw TibometerError.webhook("error.https")
        }
        guard bearerToken.rangeOfCharacter(from: .newlines) == nil else {
            throw TibometerError.webhook("error.token")
        }
        return target
    }
}

public struct WebhookPayload: Encodable {
    public let schemaVersion = 1
    public var event: String
    public var eventId: String
    public var observedAt: Date
    public var bucketId: String
    public var bucketName: String
    public var window: String
    public var windowDurationMins: Int
    public var previousUsedPercent: Double
    public var remainingPercent: Double
    public var previousResetAt: Date?
    public var nextResetAt: Date?
    public var reason: String
    public var message: String

    public init(reset: ResetEvent, isTest: Bool) {
        event = isTest ? "codex.webhook.test" : "codex.limit.reset"
        eventId = reset.id
        observedAt = reset.observedAt
        bucketId = reset.bucketId
        bucketName = reset.bucketName
        window = reset.window.apiName
        windowDurationMins = reset.window.rawValue
        previousUsedPercent = reset.previousUsedPercent
        remainingPercent = reset.remainingPercent
        previousResetAt = reset.previousResetAt
        nextResetAt = reset.nextResetAt
        reason = reset.reason.rawValue
        message = isTest ? L10n.text("webhook.test_message") : "\(reset.notificationTitle)\n\(reset.message)\n\(reset.window.title)"
    }
}

public struct WebhookDeliveryError: LocalizedError {
    public var message: LocalizedMessage
    public var retryable: Bool
    public var errorDescription: String? { message.localized }
}

public enum WebhookRequestBuilder {
    public static func build(event: ResetEvent, configuration: WebhookConfiguration, isTest: Bool = false, now: Date = Date()) throws -> URLRequest {
        let payload = WebhookPayload(reset: event, isTest: isTest)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let body: Data
        switch configuration.format {
        case .json:
            body = try encoder.encode(payload)
        case .slack:
            body = try JSONSerialization.data(withJSONObject: ["text": payload.message], options: [.sortedKeys])
        case .discord:
            body = try JSONSerialization.data(withJSONObject: ["content": payload.message, "allowed_mentions": ["parse": []]], options: [.sortedKeys])
        case .feishu:
            var object: [String: Any] = ["msg_type": "text", "content": ["text": payload.message]]
            if !configuration.signingSecret.isEmpty {
                let timestamp = String(Int(now.timeIntervalSince1970))
                let key = SymmetricKey(data: Data("\(timestamp)\n\(configuration.signingSecret)".utf8))
                object["timestamp"] = timestamp
                object["sign"] = Data(HMAC<SHA256>.authenticationCode(for: Data(), using: key)).base64EncodedString()
            }
            body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        case .wecom:
            body = try JSONSerialization.data(withJSONObject: ["msgtype": "text", "text": ["content": payload.message]], options: [.sortedKeys])
        }
        var request = URLRequest(url: try configuration.validatedURL())
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Tibometer/1.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue(event.id, forHTTPHeaderField: "Idempotency-Key")
        request.setValue(event.id, forHTTPHeaderField: "X-Tibometer-Event-ID")
        if !configuration.bearerToken.isEmpty {
            request.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if configuration.format == .json, !configuration.signingSecret.isEmpty {
            let timestamp = String(Int(now.timeIntervalSince1970))
            let key = SymmetricKey(data: Data(configuration.signingSecret.utf8))
            let signed = Data("\(timestamp).".utf8) + body
            let digest = HMAC<SHA256>.authenticationCode(for: signed, using: key).map { String(format: "%02x", $0) }.joined()
            request.setValue(timestamp, forHTTPHeaderField: "X-Tibometer-Timestamp")
            request.setValue("sha256=\(digest)", forHTTPHeaderField: "X-Tibometer-Signature")
        }
        return request
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Keep payloads and credentials on the configured destination.
        completionHandler(nil)
    }
}

public struct WebhookSender: Sendable {
    public init() {}

    public func send(event: ResetEvent, configuration: WebhookConfiguration, isTest: Bool = false) async throws {
        let request = try WebhookRequestBuilder.build(event: event, configuration: configuration, isTest: isTest)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 15
        sessionConfiguration.timeoutIntervalForResource = 20
        sessionConfiguration.httpShouldSetCookies = false
        let session = URLSession(configuration: sessionConfiguration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            throw WebhookDeliveryError(message: "error.webhook_network", retryable: true)
        }
        guard let http = response as? HTTPURLResponse else {
            throw WebhookDeliveryError(message: "error.webhook_response", retryable: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebhookDeliveryError(message: .init("error.webhook_http", String(http.statusCode)), retryable: http.statusCode == 429 || http.statusCode >= 500)
        }
        if configuration.format == .feishu || configuration.format == .wecom {
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let code = (object["code"] as? Int) ?? (object["errcode"] as? Int) ?? (object["StatusCode"] as? Int) else {
                throw WebhookDeliveryError(message: "error.bot_response", retryable: false)
            }
            guard code == 0 else {
                throw WebhookDeliveryError(message: .init("error.bot_rejected", String(code)), retryable: false)
            }
        }
    }
}
