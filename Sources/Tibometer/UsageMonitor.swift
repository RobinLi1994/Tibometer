import AppKit
import Combine
import ServiceManagement
import TibometerCore

private struct AccountRefreshResult: Sendable {
    var id: UUID
    var snapshot: UsageSnapshot?
    var error: LocalizedMessage?
}

@MainActor
final class DisplayClock: ObservableObject {
    @Published private(set) var now = Date()

    func update() { now = Date() }
}

@MainActor
final class UsageMonitor: ObservableObject {
    @Published var settings: Settings
    @Published private(set) var accounts: [AccountConfiguration]
    @Published private(set) var accountSummaries: [AccountSummary] = []
    @Published private(set) var menuBarStyle: MenuBarStyle
    @Published private(set) var menuBarScope: MenuBarScope
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var records: [EventRecord] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: LocalizedMessage?
    @Published private(set) var sourceConnection = SourceConnectionFeedback()
    @Published private(set) var persistenceWarning: LocalizedMessage?
    @Published private(set) var nextRefreshAt: Date?
    let clock = DisplayClock()
    var now: Date { clock.now }
    @Published private(set) var isTestingWebhook = false
    @Published var webhookFeedback: LocalizedMessage?
    @Published var notificationFeedback: LocalizedMessage?
    @Published var loginItemFeedback: LocalizedMessage?
    @Published private(set) var loginItemEnabled = false
    let notifier = LocalNotifier()
    let demo: Bool
    private var state: MonitorState
    private var accountStates: [UUID: MonitorState] = [:]
    private var accountErrors: [UUID: LocalizedMessage] = [:]
    private var accountFailures: [UUID: Int] = [:]
    private var accountRefreshing: Set<UUID> = []
    private var pausedAccounts: Set<UUID> = []
    private(set) var selectedAccountID: UUID?
    private let store = StateStore()
    private let webhookStore = WebhookConfigurationStore()
    private var failures = 0
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private var deliveryTimer: Timer?
    private var observations: [NSObjectProtocol] = []
    private var localeObservation: NSObjectProtocol?
    private var isDelivering = false
    private var webhookConfiguration: WebhookConfiguration?
    private var settingsRevision = 0
    private var stateSaved = true

    init(demo: Bool = false) {
        self.demo = demo
        let loadedSettings = demo ? Settings() : Settings.load()
        let configuredAccounts = demo ? Self.demoAccounts() : loadedSettings.configuredAccounts
        settings = loadedSettings
        accounts = configuredAccounts
        selectedAccountID = configuredAccounts.first?.id
        menuBarStyle = demo ? .percentage : MenuBarStyle.load()
        menuBarScope = demo ? .both : MenuBarScope.load()
        do { state = demo ? MonitorState() : try store.load() }
        catch { state = MonitorState(); persistenceWarning = "error.state_read" }
        if !demo {
            do {
                let multi = try store.loadMulti(firstAccountID: selectedAccountID)
                accountStates = multi.states
                for account in accounts where accountStates[account.id] == nil { accountStates[account.id] = MonitorState() }
                if settings.accounts.isEmpty, !accounts.isEmpty {
                    settings.accounts = accounts
                    settings.save()
                }
            } catch { persistenceWarning = "error.state_read" }
        }
        state = accountStates[selectedAccountID ?? UUID()] ?? state
        state.snapshot = state.snapshot?.codexOnly
        state.records.removeAll { $0.event.bucketId != "codex" }
        state.detector.retainCodexOnly()
        if let selectedAccountID { accountStates[selectedAccountID] = state }
        snapshot = state.snapshot
        records = state.records
        if demo {
            let demoSnapshot = UsageSnapshot(observedAt: Date(), accountFingerprint: "demo", buckets: [
                RateBucket(primary: RateWindow(usedPercent: 24, windowDurationMins: 300, resetsAt: Date().addingTimeInterval(7680).timeIntervalSince1970),
                           secondary: RateWindow(usedPercent: 39, windowDurationMins: 10080, resetsAt: Date().addingTimeInterval(230400).timeIntervalSince1970), planType: "pro",
                           credits: .init(hasCredits: true, unlimited: false, balance: "128.5"))
            ])
            let personalSnapshot = UsageSnapshot(observedAt: Date(), accountFingerprint: "demo-personal", buckets: [
                RateBucket(primary: RateWindow(usedPercent: 67, windowDurationMins: 300, resetsAt: Date().addingTimeInterval(4080).timeIntervalSince1970),
                           secondary: RateWindow(usedPercent: 63, windowDurationMins: 10080, resetsAt: Date().addingTimeInterval(230400).timeIntervalSince1970), planType: "plus")
            ])
            if accounts.indices.contains(0) { accountStates[accounts[0].id] = MonitorState(snapshot: demoSnapshot) }
            if accounts.indices.contains(1) { accountStates[accounts[1].id] = MonitorState(snapshot: personalSnapshot) }
            if accounts.indices.contains(2) { accountErrors[accounts[2].id] = "error.login" }
            snapshot = demoSnapshot
            state = accountStates[accounts[0].id] ?? state
        }
        refreshSummaries()
    }

    private static func demoAccounts() -> [AccountConfiguration] {
        [
            AccountConfiguration(name: "Work · Pro", executablePath: "codex", source: .local(homePath: "demo-work")),
            AccountConfiguration(name: "Personal", executablePath: "codex", source: .local(homePath: "demo-personal")),
            AccountConfiguration(name: "Research lab", executablePath: "codex", source: .local(homePath: "demo-research"))
        ]
    }

    var selectedAccount: AccountConfiguration? { accounts.first { $0.id == selectedAccountID } }
    var codexBucket: RateBucket? { snapshot?.codexBucket }
    var credits: CreditsSnapshot? { codexBucket?.credits }
    var isStale: Bool {
        guard let snapshot else { return false }
        return lastError != nil || now.timeIntervalSince(snapshot.observedAt) > max(90, settings.refreshInterval * 2)
    }
    var menuBarTitle: String {
        if accounts.count > 1 {
            let aggregate = MultiAccountPresentation.aggregate(accountSummaries)
            guard let lowest = aggregate.lowestRemainingPercent else { return L10n.text("quota.empty") }
            let second = aggregate.secondLowestRemainingPercent.map { " · \($0)%" } ?? ""
            let additional = aggregate.accountCount > 2 ? " · +\(aggregate.accountCount - 2)" : ""
            let warning = aggregate.issueCount > 0 ? " · ⚠\(aggregate.issueCount)" : ""
            return "\(lowest)%\(second)\(additional)\(warning)"
        }
        return MenuBarPresentation.title(bucket: codexBucket, stale: lastError != nil || isStale, scope: menuBarScope)
    }
    var menuBarHelp: String {
        if accounts.count > 1 {
            let aggregate = MultiAccountPresentation.aggregate(accountSummaries)
            var lines = [L10n.text("multi.accounts_summary", String(aggregate.accountCount))]
            if let lowest = aggregate.lowestRemainingPercent {
                lines.append(L10n.text("multi.lowest_remaining", String(lowest)))
            }
            if let second = aggregate.secondLowestRemainingPercent {
                lines.append(L10n.text("multi.second_lowest", String(second)))
            }
            if aggregate.issueCount > 0 {
                lines.append(L10n.text("multi.issue_count", String(aggregate.issueCount)))
            }
            return lines.joined(separator: "\n")
        }
        let empty = snapshot != nil && MenuBarPresentation.items(in: codexBucket, scope: menuBarScope).isEmpty
        return L10n.text(empty ? "menu_scope.unavailable" : "app.tooltip")
    }
    var visibleWindows: [QuotaWindow] { MenuBarPresentation.visibleWindows(in: codexBucket) }
    var language: AppLanguage { L10n.preference }

    func setLanguage(_ language: AppLanguage) {
        objectWillChange.send()
        L10n.preference = language
    }

    func setMenuBarStyle(_ style: MenuBarStyle) {
        guard menuBarStyle != style else { return }
        menuBarStyle = style
        if !demo { style.save() }
    }

    func setMenuBarScope(_ scope: MenuBarScope) {
        guard menuBarScope != scope else { return }
        menuBarScope = scope
        if !demo { scope.save() }
    }

    var statusText: String {
        if demo { return L10n.text("status.demo") }
        if accounts.isEmpty { return L10n.text("status.no_accounts") }
        if accounts.count > 1 {
            let aggregate = MultiAccountPresentation.aggregate(accountSummaries)
            if aggregate.lowestRemainingPercent == nil { return L10n.text("status.no_accounts_available") }
            if aggregate.issueCount > 0 { return L10n.text("status.multi_issue", String(aggregate.issueCount)) }
            return L10n.text("status.connected")
        }
        if isRefreshing { return L10n.text("status.refreshing") }
        if lastError != nil { return L10n.text("status.error") }
        if isStale { return L10n.text("status.stale") }
        if snapshot == nil { return L10n.text("status.connecting") }
        return L10n.text("status.connected")
    }

    func selectAccount(_ id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        selectedAccountID = id
        state = accountStates[id] ?? MonitorState()
        snapshot = state.snapshot
        records = state.records
        lastError = accountErrors[id]
        clock.update()
        objectWillChange.send()
    }

    func setAccountEnabled(_ id: UUID, enabled: Bool) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].enabled = enabled
        if enabled { pausedAccounts.remove(id) } else { pausedAccounts.insert(id) }
        settings.accounts = accounts
        if !demo { settings.save() }
        refreshSummaries()
        if enabled { Task { await refresh(accountIDs: [id]) } }
    }

    func refreshSummaries() {
        let summaries = accounts.map { account in
            let current = accountStates[account.id]
            let status: AccountConnectionStatus
            if !account.enabled || pausedAccounts.contains(account.id) { status = .paused }
            else if accountRefreshing.contains(account.id) { status = .refreshing }
            else if accountErrors[account.id] != nil { status = .error }
            else if let observedAt = current?.snapshot?.observedAt,
                    Date().timeIntervalSince(observedAt) > max(90, settings.refreshInterval * 2) { status = .stale }
            else if current?.snapshot != nil { status = .connected }
            else { status = .connecting }
            return AccountSummary(id: account.id, name: account.name, enabled: account.enabled,
                                  snapshot: current?.snapshot, status: status)
        }
        accountSummaries = summaries.sorted {
            switch ($0.remainingPercent, $1.remainingPercent) {
            case let (lhs?, rhs?): return lhs == rhs ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    func start() {
        localeObservation = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        loginItemEnabled = SMAppService.mainApp.status == .enabled
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let wasStale = self.isStale
                self.clock.update()
                if self.isStale != wasStale { self.objectWillChange.send() }
            }
        }
        Task { await notifier.refreshPermission() }
        guard !demo else { return }
        if settings.webhookEnabled {
            do {
                let config = try webhookStore.load()
                guard !config.url.isEmpty else { throw TibometerError.webhook("error.webhook_missing") }
                _ = try config.validatedURL()
                webhookConfiguration = config
            }
            catch { webhookFeedback = .from(error) }
        }
        let wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        observations.append(wake)
        deliveryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.deliverPending() }
        }
        Task {
            await refresh()
            if notifier.authorization == .notDetermined && settings.notificationsEnabled { await notifier.requestPermission() }
        }
    }

    func refresh() async { await refresh(accountIDs: accounts.map(\.id)) }

    func refresh(accountIDs requestedIDs: [UUID]) async {
        guard !demo, !isRefreshing else { return }
        refreshTimer?.invalidate()
        isRefreshing = true
        let revision = settingsRevision
        let targets = accounts.filter { requestedIDs.contains($0.id) && $0.enabled && !pausedAccounts.contains($0.id) }
        var pending = targets
        while !pending.isEmpty, revision == settingsRevision {
            let batch = Array(pending.prefix(3))
            pending.removeFirst(min(3, pending.count))
            accountRefreshing.formUnion(batch.map(\.id))
            refreshSummaries()
            let configurations = batch.map { account in
                (account.id, account.executablePath, account.source)
            }
            await withTaskGroup(of: AccountRefreshResult.self) { group in
                for (id, executablePath, source) in configurations {
                    group.addTask {
                        do {
                            if let providerID = source.providerID {
                                try CCSwitchOfficialSource().validate(providerID: providerID,
                                                                       codexHome: URL(fileURLWithPath: source.homePath))
                            }
                            let fresh = try await CodexClient().fetch(configuration: .init(executablePath: executablePath,
                                                                                             homePath: source.homePath))
                            if let providerID = source.providerID {
                                try CCSwitchOfficialSource().validate(providerID: providerID,
                                                                       codexHome: URL(fileURLWithPath: source.homePath))
                            }
                            return AccountRefreshResult(id: id, snapshot: fresh, error: nil)
                        } catch {
                            return AccountRefreshResult(id: id, snapshot: nil, error: .from(error))
                        }
                    }
                }
                for await result in group { apply(result, revision: revision) }
            }
            accountRefreshing.subtract(batch.map(\.id))
            refreshSummaries()
        }
        isRefreshing = false
        clock.update()
        refreshSummaries()
        if revision != settingsRevision {
            Task { await refresh() }
            return
        }
        scheduleNextRefresh()
        await deliverPending()
    }

    private func apply(_ result: AccountRefreshResult, revision: Int) {
        guard revision == settingsRevision else { return }
        var accountState = accountStates[result.id] ?? MonitorState()
        if let fresh = result.snapshot {
            let events = accountState.detector.observe(fresh)
            accountState.snapshot = fresh
            for event in events where event.bucketId == "codex" {
                var accountEvent = event
                accountEvent.id = "\(result.id.uuidString)-\(event.id)"
                let hook = settings.webhookEnabled && webhookConfiguration != nil
                let accountName = accounts.first(where: { $0.id == result.id })?.name
                accountState.records.insert(EventRecord(event: accountEvent, accountName: accountName,
                    localStatus: settings.notificationsEnabled ? "notification.waiting" : "notification.disabled",
                    webhookStatus: hook ? "webhook.waiting" : "webhook.disabled", webhookFingerprint: hook ? webhookConfiguration?.fingerprint : nil,
                    webhookPending: hook, localPending: settings.notificationsEnabled), at: 0)
            }
            accountState.records = Array(accountState.records.prefix(100))
            accountStates[result.id] = accountState
            accountErrors[result.id] = nil
            accountFailures[result.id] = 0
            if result.id == selectedAccountID {
                state = accountState
                snapshot = accountState.snapshot
                records = accountState.records
                lastError = nil
                sourceConnection.complete(revision: revision)
            }
        } else if let error = result.error {
            accountFailures[result.id, default: 0] += 1
            accountErrors[result.id] = error
            if result.id == selectedAccountID {
                lastError = error
                sourceConnection.complete(revision: revision, error: error)
            }
        }
        persist()
    }

    private func scheduleNextRefresh() {
        refreshTimer?.invalidate()
        let delay = RefreshSchedule.delay(snapshot: snapshot, now: Date(), interval: settings.refreshInterval, failures: failures)
        nextRefreshAt = Date().addingTimeInterval(delay)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func updateSettings(_ updated: Settings) {
        let changedSource = updated.codexPath != settings.codexPath || updated.codexHome != settings.codexHome
            || updated.ccSwitchProviderID != settings.ccSwitchProviderID
        let changedAccounts = updated.accounts != settings.accounts
        settings = updated
        accounts = settings.configuredAccounts
        for account in accounts where accountStates[account.id] == nil { accountStates[account.id] = MonitorState() }
        if selectedAccountID == nil || !accounts.contains(where: { $0.id == selectedAccountID }) { selectedAccountID = accounts.first?.id }
        if let selectedAccountID { state = accountStates[selectedAccountID] ?? MonitorState() }
        guard !demo else { return }
        settings.save()
        if changedSource || changedAccounts {
            settingsRevision += 1
            if changedSource {
                for account in accounts {
                    accountStates[account.id] = MonitorState()
                    accountErrors[account.id] = nil
                    accountFailures[account.id] = 0
                }
                state = MonitorState()
                snapshot = nil
                records = []
                lastError = nil
            }
            refreshSummaries()
            persist()
            Task { await refresh() }
        } else {
            scheduleNextRefresh()
        }
        Task { await deliverPending() }
    }

    @discardableResult
    func addAccount(name: String, executablePath: String, homePath: String, ccSwitchProviderID: String? = nil) -> Bool {
        guard accounts.count < AccountRegistry.maximumAccountCount else { sourceConnection.reject("error.account_limit"); return false }
        do {
            _ = try CodexLocator.executable(custom: executablePath)
            var registry = AccountRegistry(accounts: accounts)
            let accountID = UUID()
            let source: AccountSource
            if let ccSwitchProviderID {
                guard try CCSwitchOfficialSource().providers().contains(where: { $0.id == ccSwitchProviderID }) else {
                    throw TibometerError.officialProviderMissing
                }
                let url = OfficialCodexHome.accountURL(for: accountID)
                try OfficialCodexHome.prepare(at: url)
                source = .ccSwitch(providerID: ccSwitchProviderID, homePath: url.path)
            } else {
                source = .local(homePath: try CodexLocator.home(custom: homePath))
            }
            try registry.add(AccountConfiguration(id: accountID, name: name, executablePath: executablePath, source: source))
            var updated = settings
            updated.accounts = registry.accounts
            updateSettings(updated)
            selectAccount(accountID)
            return true
        } catch { sourceConnection.reject(.from(error)); return false }
    }

    func removeAccount(_ id: UUID) {
        guard accounts.count > 1 else { return }
        accounts.removeAll { $0.id == id }
        accountStates.removeValue(forKey: id)
        accountErrors.removeValue(forKey: id)
        accountFailures.removeValue(forKey: id)
        if selectedAccountID == id { selectedAccountID = accounts.first?.id }
        var updated = settings
        updated.accounts = accounts
        settings = updated
        if !demo { settings.save(); persist() }
        if let selectedAccountID { state = accountStates[selectedAccountID] ?? MonitorState() }
        snapshot = state.snapshot
        records = state.records
        lastError = accountErrors[selectedAccountID ?? UUID()]
        refreshSummaries()
    }

    @discardableResult
    func renameAccount(_ id: UUID, name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = accounts.first(where: { $0.id == id }) else { return false }
        var registry = AccountRegistry(accounts: accounts)
        var updatedAccount = account
        updatedAccount.name = trimmedName
        do {
            try registry.update(updatedAccount)
            accounts = registry.accounts
            settings.accounts = accounts
            if !demo { settings.save(); persist() }
            refreshSummaries()
            return true
        } catch let error as AccountRegistryError {
            let message: LocalizedMessage = switch error {
            case .duplicateName: "error.duplicate_account_name"
            case .invalidName: "error.account_name_empty"
            default: "error.account_name_invalid"
            }
            sourceConnection.reject(message)
            return false
        } catch {
            sourceConnection.reject("error.account_name_invalid")
            return false
        }
    }

    func saveAndConnect(executablePath: String, homePath: String, ccSwitchProviderID: String? = nil) {
        guard !demo else { sourceConnection.reject("status.demo"); return }
        do {
            _ = try CodexLocator.executable(custom: executablePath)
            if let ccSwitchProviderID {
                guard try CCSwitchOfficialSource().providers().contains(where: { $0.id == ccSwitchProviderID }) else {
                    throw TibometerError.officialProviderMissing
                }
                try OfficialCodexHome.prepare()
            } else {
                _ = try CodexLocator.home(custom: homePath)
            }
            var updated = settings
            updated.codexPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.codexHome = ccSwitchProviderID == nil
                ? homePath.trimmingCharacters(in: .whitespacesAndNewlines)
                : OfficialCodexHome.defaultURL.path
            updated.ccSwitchProviderID = ccSwitchProviderID
            let source: AccountSource = if let ccSwitchProviderID {
                .ccSwitch(providerID: ccSwitchProviderID, homePath: OfficialCodexHome.defaultURL.path)
            } else {
                .local(homePath: updated.codexHome)
            }
            let first = accounts.first
            let account = AccountConfiguration(id: first?.id ?? UUID(), name: first?.name ?? "Codex account",
                                                executablePath: updated.codexPath, source: source,
                                                enabled: first?.enabled ?? true)
            updated.accounts = [account] + accounts.dropFirst()
            updateSettings(updated)
            sourceConnection.begin(revision: settingsRevision)
            Task { await refresh() }
        } catch {
            sourceConnection.reject(.from(error))
        }
    }

    func loadWebhook() -> WebhookConfiguration {
        if demo { return .init() }
        if let webhookConfiguration { return webhookConfiguration }
        do {
            let config = try webhookStore.load()
            if !config.url.isEmpty { webhookConfiguration = config }
            return config
        } catch { webhookFeedback = .from(error); return .init() }
    }

    func saveWebhook(_ configuration: WebhookConfiguration, enabled: Bool) -> Bool {
        do {
            if enabled || !configuration.url.isEmpty { _ = try configuration.validatedURL() }
            guard !demo else { webhookFeedback = "webhook.demo"; return true }
            try webhookStore.save(configuration)
            webhookConfiguration = configuration
            var updated = settings
            updated.webhookEnabled = enabled
            updateSettings(updated)
            webhookFeedback = enabled ? "webhook.saved_on" : "webhook.saved_off"
            return true
        } catch { webhookFeedback = .from(error); return false }
    }

    func testWebhook(_ configuration: WebhookConfiguration) async {
        guard !demo, !isTestingWebhook else { return }
        isTestingWebhook = true
        webhookFeedback = nil
        defer { isTestingWebhook = false }
        do {
            let accountName = selectedAccount?.name
            let accountFingerprint = selectedAccountID.flatMap { accountStates[$0]?.snapshot?.accountFingerprint }
            try await WebhookSender().send(event: .testEvent(), configuration: configuration, isTest: true,
                                           accountName: accountName, accountFingerprint: accountFingerprint)
            webhookFeedback = "webhook.test_success"
        } catch { webhookFeedback = .from(error) }
    }

    func testNotification() async {
        guard !demo else { return }
        if notifier.authorization == .notDetermined { await notifier.requestPermission() }
        do { notificationFeedback = try await notifier.send(.testEvent(), sound: settings.notificationSound, isTest: true) }
        catch { notificationFeedback = "notification.failed" }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !demo else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemEnabled = SMAppService.mainApp.status == .enabled
            loginItemFeedback = SMAppService.mainApp.status == .requiresApproval ? "login.approval" : nil
        } catch { loginItemFeedback = "login.failed" }
    }

    private func persist() {
        guard !demo else { return }
        do { try store.saveMulti(MultiMonitorState(states: accountStates)); stateSaved = true; persistenceWarning = nil }
        catch { stateSaved = false; persistenceWarning = "error.state_write" }
    }

    private func updateRecord(_ accountID: UUID, _ id: String, _ change: (inout EventRecord) -> Void) {
        guard var accountState = accountStates[accountID], let index = accountState.records.firstIndex(where: { $0.id == id }) else { return }
        change(&accountState.records[index])
        accountStates[accountID] = accountState
        if accountID == selectedAccountID {
            state = accountState
            records = accountState.records
        }
        persist()
    }

    private func deliverPending() async {
        guard !demo, !isDelivering else { return }
        if !stateSaved { persist() }
        guard stateSaved else { return }
        isDelivering = true
        defer { isDelivering = false }
        for accountID in accounts.map(\.id) {
            guard let accountState = accountStates[accountID] else { continue }
            for record in accountState.records {
                guard record.event.bucketId == "codex" else { continue }
                guard accountStates[accountID]?.records.contains(where: { $0.id == record.id }) == true else { continue }
                if record.localPending {
                // Persist before posting to prevent duplicate banners.
                updateRecord(accountID, record.id) { $0.localPending = false; $0.localStatus = settings.notificationsEnabled ? "notification.submitting" : "notification.disabled" }
                guard stateSaved else { return }
                if settings.notificationsEnabled {
                    do {
                        let status = try await notifier.send(record.event, sound: settings.notificationSound, accountName: record.accountName)
                        updateRecord(accountID, record.id) { $0.localStatus = status }
                    } catch { updateRecord(accountID, record.id) { $0.localStatus = "notification.failed" } }
                }
                }
                guard record.webhookPending, record.nextAttemptAt.map({ $0 <= Date() }) ?? true else { continue }
                guard accountStates[accountID]?.records.contains(where: { $0.id == record.id }) == true else { continue }
                guard record.webhookAttempts < 3 else {
                    updateRecord(accountID, record.id) { $0.webhookPending = false; $0.webhookStatus = "webhook.limit_reached" }
                    continue
                }
                guard settings.webhookEnabled, let configuration = webhookConfiguration,
                      record.webhookFingerprint == configuration.fingerprint else {
                    updateRecord(accountID, record.id) { $0.webhookPending = false; $0.webhookStatus = "webhook.cancelled" }
                    continue
                }
                updateRecord(accountID, record.id) { $0.webhookAttempts += 1; $0.webhookStatus = "webhook.delivering" }
                guard stateSaved else { return }
                do {
                    let fingerprint = accountStates[accountID]?.snapshot?.accountFingerprint
                    try await WebhookSender().send(event: record.event, configuration: configuration,
                                                   accountName: record.accountName, accountFingerprint: fingerprint)
                    updateRecord(accountID, record.id) { $0.webhookPending = false; $0.webhookStatus = "webhook.delivered" }
                } catch {
                    let retryable = (error as? WebhookDeliveryError)?.retryable ?? false
                    updateRecord(accountID, record.id) {
                        $0.webhookPending = retryable && $0.webhookAttempts < 3
                        $0.nextAttemptAt = $0.webhookPending ? Date().addingTimeInterval(Double($0.webhookAttempts) * 60) : nil
                        $0.webhookStatus = $0.webhookPending ? .init("webhook.retrying", String($0.webhookAttempts)) : .from(error)
                    }
                }
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        clockTimer?.invalidate()
        deliveryTimer?.invalidate()
        for observer in observations { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let localeObservation { NotificationCenter.default.removeObserver(localeObservation) }
    }
}
