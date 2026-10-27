import Foundation
import Darwin
import CoreServices

public enum TibometerError: LocalizedError, Equatable {
    case executableMissing
    case invalidHome
    case notSignedIn
    case isolatedLoginRequired
    case ccSwitchUnavailable
    case officialProviderMissing
    case accountMismatch
    case unsupportedAccount
    case timeout
    case serverExited
    case invalidResponse
    case rpc(String, Int)
    case noLimits
    case readOnlyViolation
    case invalidThreadID
    case webhook(LocalizedMessage)

    public var errorDescription: String? { userMessage.localized }
    public var userMessage: LocalizedMessage {
        switch self {
        case .executableMissing: return "error.executable"
        case .invalidHome: return "error.home"
        case .notSignedIn: return "error.login"
        case .isolatedLoginRequired: return "error.isolated_login"
        case .ccSwitchUnavailable: return "error.ccswitch_unavailable"
        case .officialProviderMissing: return "error.official_provider"
        case .accountMismatch: return "error.account_mismatch"
        case .unsupportedAccount: return "error.auth_type"
        case .timeout: return "error.timeout"
        case .serverExited: return "error.server_exit"
        case .invalidResponse: return "error.response"
        case let .rpc(method, code): return .init("error.rpc", method, String(code))
        case .noLimits: return "error.no_limits"
        case .readOnlyViolation: return "error.read_only"
        case .invalidThreadID: return "error.thread_id"
        case let .webhook(message): return message
        }
    }
}

public struct CodexConfiguration: Sendable {
    public var executablePath: String
    public var homePath: String
    public var timeout: TimeInterval

    public init(executablePath: String = "", homePath: String = "", timeout: TimeInterval = 25) {
        self.executablePath = executablePath
        self.homePath = homePath
        self.timeout = timeout
    }
}

public enum CodexLocator {
    public static func executable(custom: String = "", applications: [URL]? = nil) throws -> String {
        func isExecutable(_ path: String) -> Bool {
            var isDirectory: ObjCBool = false
            return path.hasPrefix("/") && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
        }
        func bundledExecutables(in application: URL) -> [String] {
            ["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
             "Contents/Resources/codex"].map { application.appendingPathComponent($0).path }
        }
        let custom = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths: [String]
        if !custom.isEmpty {
            let path = (custom as NSString).expandingTildeInPath
            guard path.hasPrefix("/") else { throw TibometerError.executableMissing }
            let url = URL(fileURLWithPath: path)
            paths = url.pathExtension.lowercased() == "app" ? bundledExecutables(in: url) : [path]
        } else {
            let registered = applications
                ?? (LSCopyApplicationURLsForBundleIdentifier("com.openai.codex" as CFString, nil)?.takeRetainedValue() as? [URL] ?? [])
            paths = registered.flatMap { bundledExecutables(in: $0) }
        }
        guard let path = paths.first(where: isExecutable) else { throw TibometerError.executableMissing }
        return path
    }

    public static func home(custom: String = "") throws -> String {
        let input = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = input.isEmpty
            ? (ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex")
            : (input as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TibometerError.invalidHome
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

public struct CodexClient: Sendable {
    public init() {}

    public func fetch(configuration: CodexConfiguration = .init()) async throws -> UsageSnapshot {
        try await Self.withSession(configuration) { session, home, account in
            let result = try session.request("account/rateLimits/read")
            let response = try JSONDecoder().decode(RateLimitsResponse.self, from: JSONSerialization.data(withJSONObject: result))
            guard !response.buckets.isEmpty else { throw TibometerError.noLimits }
            // Persist only the account fingerprint.
            let identity = response.accountId ?? (account["email"] as? String) ?? UUID().uuidString
            return UsageSnapshot(observedAt: Date(), accountFingerprint: UsageSnapshot.fingerprint("\(home):\(identity)"), buckets: response.buckets)
        }
    }

    public func recentThreads(limit: Int = 5, configuration: CodexConfiguration = .init()) async throws -> [ThreadReference] {
        try await Self.withSession(configuration) { session, _, _ in
            let result = try session.request("thread/list", params: ["limit": min(20, max(1, limit)),
                "sortKey": "updated_at", "sortDirection": "desc", "useStateDbOnly": true])
            return try JSONDecoder().decode(ThreadListResponse.self, from: JSONSerialization.data(withJSONObject: result)).data
        }
    }

    public func threadUsage(threadID: String, configuration: CodexConfiguration = .init()) async throws -> ThreadUsage? {
        let id = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw TibometerError.invalidThreadID }
        return try await Self.withSession(configuration) { session, _, _ in
            let result = try session.request("account/usage/read", params: ["threadId": id])
            let response = try JSONDecoder().decode(AccountThreadUsageResponse.self, from: JSONSerialization.data(withJSONObject: result))
            if let usage = response.threadUsage, usage.threadId != id { throw TibometerError.invalidResponse }
            return response.threadUsage
        }
    }

    private static func withSession<T: Sendable>(_ configuration: CodexConfiguration,
        operation: @escaping @Sendable (RPCSession, String, [String: Any]) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let executable = try CodexLocator.executable(custom: configuration.executablePath)
                    let home = try CodexLocator.home(custom: configuration.homePath)
                    let session = try RPCSession(executable: executable, home: home, timeout: configuration.timeout)
                    defer { session.close() }
                    _ = try session.request("initialize", params: [
                        "clientInfo": ["name": "tibometer", "title": "Tibometer", "version": "1.0.2"]
                    ])
                    try session.send(["method": "initialized"])
                    let accountResult = try session.request("account/read", params: ["refreshToken": false])
                    guard let account = accountResult["account"] as? [String: Any] else { throw TibometerError.notSignedIn }
                    guard account["type"] as? String == "chatgpt" else { throw TibometerError.unsupportedAccount }
                    continuation.resume(returning: try operation(session, home, account))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

private final class RPCSession {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let finished = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var requestID = 0
    private let deadline: Date
    private var closed = false

    init(executable: String, home: String, timeout: TimeInterval) throws {
        deadline = Date().addingTimeInterval(max(1, timeout))
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "stdio://"]
        var environment = ProcessInfo.processInfo.environment
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = URL(fileURLWithPath: executable).deletingLastPathComponent().path + ":" + inheritedPath
        environment["CODEX_HOME"] = home
        environment["RUST_LOG"] = "error"
        process.environment = environment
        // Isolate Codex from project instructions and trust settings.
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let finished = finished
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
    }

    func send(_ object: [String: Any]) throws {
        if let method = object["method"] as? String,
           !CodexReadOnlyPolicy.permits(method: method, params: object["params"] as? [String: Any]) {
            throw TibometerError.readOnlyViolation
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0a)
        guard process.isRunning else { throw TibometerError.serverExited }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func request(_ method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        requestID += 1
        var message: [String: Any] = ["id": requestID, "method": method]
        if let params { message["params"] = params }
        try send(message)
        while true {
            let line = try nextLine()
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            if object["method"] != nil {
                if let id = object["id"] {
                    try send(["id": id, "error": ["code": -32601, "message": "This client only reads usage limits."]])
                }
                continue
            }
            guard object["id"] as? Int == requestID else { continue }
            if let error = object["error"] as? [String: Any] { throw TibometerError.rpc(method, error["code"] as? Int ?? -1) }
            guard let result = object["result"] as? [String: Any] else { throw TibometerError.invalidResponse }
            return result
        }
    }

    private func nextLine() throws -> Data {
        while true {
            if let index = buffer.firstIndex(of: 0x0a) {
                let line = buffer.subdata(in: 0..<index)
                buffer.removeSubrange(0...index)
                return line
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw TibometerError.timeout }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(1000, max(1, remaining * 1000))))
            if ready < 0 {
                if errno == EINTR { continue }
                throw TibometerError.serverExited
            }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else { throw TibometerError.serverExited }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 4 * 1024 * 1024 else { throw TibometerError.invalidResponse }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        if process.isRunning, finished.wait(timeout: .now() + 0.5) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        try? output.fileHandleForReading.close()
    }

    deinit { close() }
}
