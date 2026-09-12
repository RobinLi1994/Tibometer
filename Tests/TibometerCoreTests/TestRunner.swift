import Foundation

enum Checks {
    static var failures: [String] = []
    static var count = 0
    static func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        failures.append("\(file):\(line): \(message)")
    }
    static func run(_ name: String, _ body: () throws -> Void) {
        let previous = failures.count
        do { try body() } catch { fail("\(name): \(error)") }
        count += 1
        print("\(failures.count == previous ? "PASS" : "FAIL") \(name)")
    }
    static func runAsync(_ name: String, _ body: () async throws -> Void) async {
        let previous = failures.count
        do { try await body() } catch { fail("\(name): \(error)") }
        count += 1
        print("\(failures.count == previous ? "PASS" : "FAIL") \(name)")
    }
}

func expect(_ value: @autoclosure () -> Bool, _ message: String = "Expected true", file: StaticString = #filePath, line: UInt = #line) {
    if !value() { Checks.fail(message, file: file, line: line) }
}
func expectFalse(_ value: @autoclosure () -> Bool, _ message: String = "Expected false", file: StaticString = #filePath, line: UInt = #line) {
    if value() { Checks.fail(message, file: file, line: line) }
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { Checks.fail("Expected \(expected), got \(actual)", file: file, line: line) }
}
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { Checks.fail("Expected nil", file: file, line: line) }
}
func expectNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value == nil { Checks.fail("Expected non-nil", file: file, line: line) }
}
func expectLess<T: Comparable>(_ actual: T, _ bound: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual >= bound { Checks.fail("Expected \(actual) < \(bound)", file: file, line: line) }
}
func expectNoThrow<T>(_ value: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value() } catch { Checks.fail("Unexpected error \(error): \(message)", file: file, line: line) }
}
func expectThrows<T>(_ value: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); Checks.fail("Expected error: \(message)", file: file, line: line) } catch {}
}
struct MissingValue: Error {}
func require<T>(_ value: T?) throws -> T {
    guard let value else { throw MissingValue() }
    return value
}

@main
struct TestRunner {
    static func main() async {
        let quota = QuotaTests()
        Checks.run("weekly duration mapping", quota.testWeeklyInPrimaryIsNeverAssumedToBeFiveHours)
        Checks.run("authoritative multi-bucket data", quota.testMultiBucketMapIsAuthoritativeAndDoesNotMixSparkWithCodex)
        Checks.run("removed buckets never become a fallback", quota.testOtherBucketsNeverBecomeACodexFallback)
        Checks.run("removed buckets do not notify or affect polling", quota.testOtherBucketsDoNotNotifyOrChangePolling)
        Checks.run("legacy fallback", quota.testEmptyMapFallsBackToLegacy)
        Checks.run("unknown values and percentage display", quota.testUnknownAndOutOfRangeValues)
        Checks.run("first observation is silent", quota.testInitialSampleNeverNotifies)
        Checks.run("consumption and partial recovery", quota.testConsumptionAndPartialRecoveryDoNotNotify)
        Checks.run("full reset deduplication after restart", quota.testFullRestoreEmitsOnceAcrossRestart)
        Checks.run("reset during downtime", quota.testPersistedBaselineDetectsResetWhileAppWasClosed)
        Checks.run("partly consumed new window", quota.testNewWindowIsDetectedEvenWhenAlreadyPartlyConsumed)
        Checks.run("delayed server confirmation", quota.testDeadlineAloneIsNotProofOfResetAndDelayedConfirmationWorks)
        Checks.run("future timestamp drift", quota.testChangingFutureDeadlineWithoutResetDoesNotNotify)
        Checks.run("missing sample preserves baseline", quota.testMissingDataDoesNotCreateARefillOrDestroyBaseline)
        Checks.run("account switch is silent", quota.testAccountSwitchNeverLooksLikeAReset)
        Checks.run("older sample ignored", quota.testOlderAndDuplicateSamplesDoNotReplaceBaseline)
        Checks.run("independent reset windows", quota.testBothWindowsResetIndependently)
        Checks.run("reset scheduling and backoff", quota.testRefreshAtResetAndBackoff)
        let source = SourceConnectionTests()
        Checks.run("saved source waits for matching connection", source.testSavingWaitsForTheCurrentSource)
        Checks.run("source switch, failure and recovery feedback", source.testSourceSwitchAndRecoveryNeverUseOldResults)
        Checks.run("invalid path feedback survives in-flight results", source.testInvalidPathFeedbackSurvivesAnInFlightRequest)
        let placement = PanelPlacementTests()
        Checks.run("panel top stays anchored during content changes", placement.testPanelStaysBelowMenuBarWhenContentHeightChanges)
        Checks.run("oversized panel fits visible screen", placement.testOversizedContentIsLimitedToScreen)
        Checks.run("secondary display placement", placement.testSecondaryDisplayUsesItsOwnOriginAndEdges)
        Checks.run("hidden item fallback placement", placement.testHiddenStatusItemCanStillOpenAtSafeScreenCorner)
        let presentation = PresentationTests()
        Checks.run("all 16 languages persist and localize runtime messages", presentation.testAllLanguagesPersistAndUpdateRuntimeMessages)
        Checks.run("X thank-you draft target, language and privacy", presentation.testThanksLinkContainsOnlyTheEnglishDraft)
        Checks.run("only available quota windows appear", presentation.testMissingWindowsAreHiddenEverywhere)
        Checks.run("unknown values hidden, exhausted values visible", presentation.testUnknownIsHiddenButExhaustedIsVisible)
        Checks.run("system language and manual override", presentation.testSystemDetectionAndManualOverride)
        Checks.run("menu style persistence and existing preferences", presentation.testStylePreferenceSurvivesReloadAndPreservesExistingSettings)
        Checks.run("graphic remaining values and unavailable windows", presentation.testGraphicItemsUseRemainingValuesAndHideUnavailableWindows)
        Checks.run("selected menu limits and missing data", presentation.testMenuBarScopeShowsOnlySelectedAvailableWindows)
        Checks.run("menu limit selection persistence", presentation.testScopePreferenceSurvivesReloadAndPreservesStyle)
        Checks.run("one quota keeps size and centers", presentation.testOneAvailableWindowKeepsSizeAndCenters)
        Checks.run("rings align horizontally and center", presentation.testProgressRingsAlignHorizontallyAndStayCentered)
        Checks.run("complete matching translation catalogs", presentation.testCatalogsCoverTheSameKeysAndPlaceholders)
        Checks.run("live language and stable menu labels", presentation.testLiveLanguageChangesErrorsNotificationsDatesAndMenu)
        Checks.run("legacy delivery history migration", presentation.testLegacyDeliveryHistoryStillDecodesAndLocalizes)
        let credits = CreditsTests()
        Checks.run("credits without quota windows and legacy compatibility", credits.testCreditsDecodeWithoutQuotaWindowsAndOldSnapshotsStillWork)
        Checks.run("credit balance precision and zero", credits.testBalanceKeepsZeroAndDecimalPrecision)
        Checks.run("missing and unlimited credit display", credits.testMissingAndUnlimitedCreditsAreNotInventedNumbers)
        let storage = StorageTests()
        Checks.run("missing webhook file starts empty", storage.testMissingConfigurationStartsEmpty)
        Checks.run("private webhook file persistence and atomic replacement", storage.testPrivateFileSurvivesReopenAndOverwrite)
        Checks.run("damaged webhook file is preserved", storage.testDamagedFileReportsErrorWithoutOverwritingIt)
        Checks.run("failed webhook save preserves destination", storage.testFailedWriteKeepsExistingDestinationAndRemovesTemporaryFiles)
        let hooks = WebhookTests()
        Checks.run("webhook URL validation", hooks.testOnlyHTTPSOrLoopbackHTTPIsAccepted)
        Checks.run("payload privacy and event ID", hooks.testGenericPayloadHasNoAccountCredentialsAndStableEventID)
        Checks.run("HMAC signature", hooks.testGenericSignatureValidatesExactBodyAndTimestamp)
        Checks.run("webhook message formats", hooks.testTestEventAndChatFormats)
        Checks.run("fixed reset copy, window scope and original quota data", hooks.testResetMessagesUseFullResetCopyAndPreserveQuotaData)
        let locator = CodexLocatorTests()
        Checks.run("renamed and relocated Codex application", locator.testRegisteredApplicationDoesNotDependOnItsNameOrLocation)
        Checks.run("missing application requires manual selection", locator.testMissingRegistrationRequiresManualSelection)
        Checks.run("manual application selection resolves bundled executable", locator.testManuallySelectedApplicationResolvesItsBundledExecutable)
        Checks.run("custom executable priority and validation", locator.testCustomPathIsAuthoritativeAndDirectoriesAreRejected)
        let client = CodexClientTests()
        await Checks.runAsync("real stdio transport against fixture", client.testStdioHandshakeAccountAndUsageRead)
        await Checks.runAsync("executable shim finds adjacent runtime", client.testExecutableShimFindsItsAdjacentRuntime)
        await Checks.runAsync("account authentication errors", client.testLoggedOutAndAPIKeyGiveActionableErrors)
        await Checks.runAsync("bounded timeout and process exit", client.testTimeoutIsBoundedAndServerExitDoesNotHang)
        await Checks.runAsync("RPC error privacy", client.testRPCErrorDoesNotExposeRawServerText)
        await Checks.runAsync("read-only task usage transport", client.testThreadUsageUsesReadOnlyRequestsAndPreservesFields)
        await Checks.runAsync("unavailable and mismatched task usage", client.testUnavailableUsageDoesNotFallBackToAccountTotals)
        Checks.run("write and implicit repair requests rejected", client.testReadOnlyPolicyRejectsMutationsAndImplicitRepairs)
        Checks.run("fixture cleanup", client.cleanup)
        for failure in Checks.failures { FileHandle.standardError.write(Data((failure + "\n").utf8)) }
        print("\(Checks.count) checks, \(Checks.failures.count) failures")
        exit(Checks.failures.isEmpty ? 0 : 1)
    }
}
