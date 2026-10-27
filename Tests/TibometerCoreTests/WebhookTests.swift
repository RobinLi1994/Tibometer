import Foundation
import CryptoKit
import TibometerCore

final class WebhookTests {
    func testOnlyHTTPSOrLoopbackHTTPIsAccepted() throws {
        for url in ["https://example.com/hook", "http://127.0.0.1:8080/hook", "http://localhost:8080", "http://[::1]:8080"] {
            expectNoThrow(try WebhookConfiguration(url: url).validatedURL(), url)
        }
        for url in ["http://example.com", "file:///tmp/hook", "https://user:password@example.com", "https://example.com/#token", "not a URL"] {
            expectThrows(try WebhookConfiguration(url: url).validatedURL(), url)
        }
        expectThrows(try WebhookConfiguration(url: "https://example.com", bearerToken: "a\r\nb").validatedURL())
    }

    func testGenericPayloadHasNoAccountCredentialsAndStableEventID() throws {
        let event = ResetEvent.testEvent(now: Date(timeIntervalSince1970: 1700000000))
        let config = WebhookConfiguration(url: "https://example.com", bearerToken: "secret-token", signingSecret: "secret-sign")
        let request = try WebhookRequestBuilder.build(event: event, configuration: config)
        let data = try require(request.httpBody)
        let body = try require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        expectEqual(body["event"] as? String, "codex.limit.reset")
        expectEqual(body["window"] as? String, "five_hour")
        expectEqual(body["remaining_percent"] as? Double, 100)
        expectEqual(body["schema_version"] as? Int, 1)
        expectNil(body["account_id"])
        expectNil(body["account_fingerprint"])
        expectFalse(String(decoding: data, as: UTF8.self).contains("secret-token"))
        expectFalse(String(decoding: data, as: UTF8.self).contains("secret-sign"))
        expectEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), event.id)
        expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testGenericSignatureValidatesExactBodyAndTimestamp() throws {
        let now = Date(timeIntervalSince1970: 1700000000)
        let request = try WebhookRequestBuilder.build(event: .testEvent(now: now), configuration: .init(url: "https://example.com", signingSecret: "sample-secret"), now: now)
        let body = try require(request.httpBody)
        let signature = try require(request.value(forHTTPHeaderField: "X-Tibometer-Signature"))
        let timestamp = try require(request.value(forHTTPHeaderField: "X-Tibometer-Timestamp"))
        expectEqual(timestamp, "1700000000")
        let expected = HMAC<SHA256>.authenticationCode(for: Data("\(timestamp).".utf8) + body, using: SymmetricKey(data: Data("sample-secret".utf8)))
        expectEqual(signature, "sha256=" + expected.map { String(format: "%02x", $0) }.joined())
    }

    func testDingTalkSignedURLPreservesTokenAndEncodesSignature() throws {
        let now = Date(timeIntervalSince1970: 1700000000.123)
        let configuration = WebhookConfiguration(url: "https://oapi.dingtalk.com/robot/send?access_token=abc%2B123",
                                                 format: .dingtalk, signingSecret: "SECtest-secret0")
        let request = try WebhookRequestBuilder.build(event: .testEvent(now: now), configuration: configuration, isTest: true, now: now)
        let url = try require(request.url)
        let components = try require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        expectEqual(components.queryItems?.first(where: { $0.name == "access_token" })?.value, "abc+123")
        expectEqual(components.queryItems?.first(where: { $0.name == "timestamp" })?.value, "1700000000123")
        expectEqual(components.queryItems?.first(where: { $0.name == "sign" })?.value, "uV95GnVejFsy9+utjtLP+E1tAzu/UDhZ2r+hGc7YFFc=")
        expect(components.percentEncodedQuery?.contains("sign=uV95GnVejFsy9%2ButjtLP%2BE1tAzu%2FUDhZ2r%2BhGc7YFFc%3D") == true)
        expectFalse(url.absoluteString.contains("SECtest-secret0"))
        let body = try require(JSONSerialization.jsonObject(with: require(request.httpBody)) as? [String: Any])
        expectEqual(body["msgtype"] as? String, "text")
        expectEqual((body["text"] as? [String: String])?["content"], L10n.text("webhook.test_message"))
        expectNil(body["sign"])
    }

    func testDingTalkRequiresSigningSecret() {
        let configuration = WebhookConfiguration(url: "https://oapi.dingtalk.com/robot/send?access_token=abc", format: .dingtalk)
        expectThrows(try configuration.validatedURL())
    }

    func testTestEventAndChatFormats() throws {
        for format in WebhookFormat.allCases {
            let request = try WebhookRequestBuilder.build(event: .testEvent(), configuration: .init(url: "https://example.com", format: format,
                                                                                                  signingSecret: format == .dingtalk ? "SECtest-secret" : ""), isTest: true)
            let body = try require(JSONSerialization.jsonObject(with: require(request.httpBody)) as? [String: Any])
            switch format {
            case .json: expectEqual(body["event"] as? String, "codex.webhook.test")
            case .slack: expectEqual(body["text"] as? String, L10n.text("webhook.test_message"))
            case .discord:
                expectNotNil(body["content"])
                expectNotNil(body["allowed_mentions"])
            case .feishu: expectEqual(body["msg_type"] as? String, "text")
            case .wecom: expectEqual(body["msgtype"] as? String, "text")
            case .dingtalk: expectEqual(body["msgtype"] as? String, "text")
            }
        }
    }

    func testResetMessagesUseFullResetCopyAndPreserveQuotaData() throws {
        let previous = L10n.preference
        defer { L10n.preference = previous }
        for language in [AppLanguage.english, .chinese] {
            L10n.preference = language
            for window in QuotaWindow.allCases {
                for remaining in [100.0, 99.9, 24.9, 0.4, 0.0] {
                    var event = ResetEvent.testEvent()
                    event.window = window
                    event.remainingPercent = remaining
                    event.reason = remaining == 100 ? .restoredToFull : .newWindow
                    expectEqual(event.notificationTitle, language == .english ? "Tibo did it again." : "Tibo 又出手了。")
                    expectEqual(event.message, language == .english
                                ? "Your Codex usage has been reset to 100%."
                                : "你的 Codex 额度已重置为 100%。")
                    expect(event.title.contains(window.title))

                    let expected = "\(event.notificationTitle)\n\(event.message)\n\(window.title)"
                    for format in WebhookFormat.allCases {
                        let request = try WebhookRequestBuilder.build(event: event, configuration: .init(url: "https://example.com", format: format,
                                                                                                         signingSecret: format == .dingtalk ? "SECtest-secret" : ""))
                        let body = try require(JSONSerialization.jsonObject(with: require(request.httpBody)) as? [String: Any])
                        let text: String?
                        switch format {
                        case .json:
                            text = body["message"] as? String
                            expectEqual(body["window"] as? String, window.apiName)
                            expectEqual(body["remaining_percent"] as? Double, remaining)
                        case .slack: text = body["text"] as? String
                        case .discord: text = body["content"] as? String
                        case .feishu: text = (body["content"] as? [String: String])?["text"]
                        case .wecom: text = (body["text"] as? [String: String])?["content"]
                        case .dingtalk: text = (body["text"] as? [String: String])?["content"]
                        }
                        expectEqual(text, expected)
                    }
                }
            }
        }
    }
}
