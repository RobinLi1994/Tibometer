import Foundation
import TibometerCore

final class CodexClientTests {
    private var temporaryDirectories: [URL] = []

    func cleanup() throws {
        for directory in temporaryDirectories { try FileManager.default.removeItem(at: directory) }
    }

    private func fixture(mode: String) throws -> CodexConfiguration {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tibometer-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let file = directory.appendingPathComponent("fake-codex")
        let script = """
        #!/usr/bin/python3
        import sys, json, time
        from pathlib import Path
        mode = '\(mode)'
        for line in sys.stdin:
            r = json.loads(line)
            with Path(__file__).with_name('requests.jsonl').open('a') as trace:
                trace.write(json.dumps(r)+'\\n')
            if 'id' not in r: continue
            if mode == 'hang':
                time.sleep(30)
                continue
            if mode == 'exit': sys.exit(1)
            method = r['method']
            if method == 'initialize':
                result = {'userAgent':'fixture'}
            elif method == 'account/read':
                assert r['params']['refreshToken'] is False
                result = {'account': None if mode == 'logged-out' else {'type':'apiKey' if mode == 'api-key' else 'chatgpt','email':'fixture@example.invalid','planType':'pro'}}
            elif method == 'thread/list':
                assert r['params']['useStateDbOnly'] is True
                result = {'data':[{'id':'fixture-thread','model':'fixture-model','updatedAt':1800000000,'preview':'private task text'}]}
            elif method == 'account/usage/read':
                assert r['params']['threadId'] == 'fixture-thread'
                usage = {'threadId':'wrong-thread' if mode == 'wrong-thread' else 'fixture-thread', 'estimatedUsageCreditsMicros':1250000, 'estimatedUsageUsdMicros':None,
                    'groups':[{'model':'fixture-model','reasoningEffort':'high','speed':'standard','inputTokens':120,'cachedInputTokens':20,'netNewInputTokens':100,'outputTokens':30,'totalTokens':150,'estimatedUsageCreditsMicros':1250000}]}
                result = {'summary':{'lifetimeTokens':999999999},'threadUsage':None if mode == 'usage-missing' else usage}
            else:
                assert method == 'account/rateLimits/read'
                if mode == 'rpc-error':
                    print(json.dumps({'id':r['id'],'error':{'code':-32000,'message':'private upstream error'}}),flush=True)
                    continue
                print(json.dumps({'method':'account/rateLimits/updated','params':{}}),flush=True)
                result = {'accountId':'fixture-account','rateLimits':{'limitId':'codex','primary':{'usedPercent':32,'windowDurationMins':300,'resetsAt':1800000000},'secondary':{'usedPercent':12,'windowDurationMins':10080,'resetsAt':1800500000},'credits':{'hasCredits':True,'unlimited':False,'balance':'12.5'}}}
            print(json.dumps({'id':r['id'],'result':result}),flush=True)
        """
        try Data(script.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return CodexConfiguration(executablePath: file.path, homePath: directory.path, timeout: mode == "hang" ? 1 : 5)
    }

    func testStdioHandshakeAccountAndUsageRead() async throws {
        let snapshot = try await CodexClient().fetch(configuration: fixture(mode: "normal"))
        expectEqual(snapshot.buckets.first?.window(.fiveHour)?.remainingPercent, 68)
        expectEqual(snapshot.buckets.first?.window(.weekly)?.remainingPercent, 88)
        expectEqual(snapshot.accountFingerprint.count, 64)
        expectFalse(snapshot.accountFingerprint.contains("fixture-account"))
        expectEqual(snapshot.codexBucket?.credits?.balanceValue, Decimal(string: "12.5"))
    }

    func testExecutableShimFindsItsAdjacentRuntime() async throws {
        let configuration = try fixture(mode: "normal")
        let executable = URL(fileURLWithPath: configuration.executablePath)
        let runtime = executable.deletingLastPathComponent().appendingPathComponent("node")
        try FileManager.default.moveItem(at: executable, to: runtime)
        try Data("#!/bin/sh\nexec node \"$@\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let snapshot = try await CodexClient().fetch(configuration: configuration)
        expectEqual(snapshot.codexBucket?.window(.weekly)?.remainingPercent, 88)
    }

    func testThreadUsageUsesReadOnlyRequestsAndPreservesFields() async throws {
        let configuration = try fixture(mode: "usage")
        let client = CodexClient()
        let threads = try await client.recentThreads(configuration: configuration)
        expectEqual(threads.first?.id, "fixture-thread")
        let encodedThreads = try JSONEncoder().encode(threads)
        expectFalse(String(decoding: encodedThreads, as: UTF8.self).contains("private task text"))
        let usage = try require(try await client.threadUsage(threadID: "fixture-thread", configuration: configuration))
        expectEqual(usage.threadId, "fixture-thread")
        expectEqual(usage.estimatedUsageCreditsMicros, 1_250_000)
        expectNil(usage.estimatedUsageUsdMicros)
        expectEqual(usage.groups.first?.totalTokens, 150)
        expectEqual(usage.groups.first?.cachedInputTokens, 20)
        expectEqual(usage.groups.first?.netNewInputTokens, 100)
        let trace = try String(contentsOf: URL(fileURLWithPath: configuration.homePath).appendingPathComponent("requests.jsonl"), encoding: .utf8)
        let methods = try trace.split(separator: "\n").map { line in
            let request = try require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return request["method"] as? String ?? ""
        }
        expectEqual(Set(methods), ["initialize", "initialized", "account/read", "thread/list", "account/usage/read"])
    }

    func testUnavailableUsageDoesNotFallBackToAccountTotals() async throws {
        let usage = try await CodexClient().threadUsage(threadID: "fixture-thread", configuration: fixture(mode: "usage-missing"))
        expectNil(usage)
        do {
            _ = try await CodexClient().threadUsage(threadID: "fixture-thread", configuration: fixture(mode: "wrong-thread"))
            Checks.fail("Expected mismatched thread rejection")
        } catch { expectEqual(error as? TibometerError, .invalidResponse) }
        do {
            _ = try await CodexClient().threadUsage(threadID: " \n", configuration: .init(executablePath: "/not-a-codex"))
            Checks.fail("Expected empty ID rejection before starting Codex")
        } catch { expectEqual(error as? TibometerError, .invalidThreadID) }
    }

    func testReadOnlyPolicyRejectsMutationsAndImplicitRepairs() {
        for method in ["account/login/start", "account/logout", "account/rateLimitResetCredit/consume", "account/sendAddCreditsNudgeEmail",
                       "thread/start", "thread/resume", "thread/fork", "thread/archive", "turn/start", "config/value/write", "command/exec", "fs/writeFile", "unknown/read"] {
            expectFalse(CodexReadOnlyPolicy.permits(method: method), method)
        }
        expectFalse(CodexReadOnlyPolicy.permits(method: "account/read", params: ["refreshToken": true]))
        expectFalse(CodexReadOnlyPolicy.permits(method: "account/read"))
        expectFalse(CodexReadOnlyPolicy.permits(method: "thread/list"))
        expectFalse(CodexReadOnlyPolicy.permits(method: "thread/list", params: ["useStateDbOnly": false]))
        expect(CodexReadOnlyPolicy.permits(method: "account/read", params: ["refreshToken": false]))
        expect(CodexReadOnlyPolicy.permits(method: "thread/list", params: ["useStateDbOnly": true]))
        expect(CodexReadOnlyPolicy.permits(method: "account/rateLimits/read"))
        expect(CodexReadOnlyPolicy.permits(method: "account/usage/read", params: ["threadId": "fixture-thread"]))
    }

    func testLoggedOutAndAPIKeyGiveActionableErrors() async throws {
        for (mode, expected) in [("logged-out", TibometerError.notSignedIn), ("api-key", TibometerError.unsupportedAccount)] {
            do { _ = try await CodexClient().fetch(configuration: fixture(mode: mode)); Checks.fail("Expected auth failure") }
            catch { expectEqual(error as? TibometerError, expected) }
        }
    }

    func testTimeoutIsBoundedAndServerExitDoesNotHang() async throws {
        for (mode, expected) in [("hang", TibometerError.timeout), ("exit", TibometerError.serverExited)] {
            let start = Date()
            do { _ = try await CodexClient().fetch(configuration: fixture(mode: mode)); Checks.fail("Expected transport failure") }
            catch { expectEqual(error as? TibometerError, expected) }
            expectLess(Date().timeIntervalSince(start), 4)
        }
    }

    func testRPCErrorDoesNotExposeRawServerText() async throws {
        do { _ = try await CodexClient().fetch(configuration: fixture(mode: "rpc-error")); Checks.fail("Expected RPC error") }
        catch {
            expectEqual(error as? TibometerError, .rpc("account/rateLimits/read", -32000))
            expectFalse(error.localizedDescription.contains("private upstream"))
        }
    }
}
