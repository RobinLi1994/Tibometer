import AppKit
import Combine
import ServiceManagement
import TibometerCore

@MainActor
final class UsageMonitor: ObservableObject {
    @Published var settings: Settings
    @Published private(set) var menuBarStyle: MenuBarStyle
    @Published private(set) var menuBarScope: MenuBarScope
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var records: [EventRecord] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: LocalizedMessage?
    @Published private(set) var sourceConnection = SourceConnectionFeedback()
    @Published private(set) var persistenceWarning: LocalizedMessage?
    @Published private(set) var nextRefreshAt: Date?
    @Published private(set) var now = Date()
    @Published private(set) var isTestingWebhook = false
    @Published var webhookFeedback: LocalizedMessage?
    @Published var notificationFeedback: LocalizedMessage?
    @Published var loginItemFeedback: LocalizedMessage?
    @Published private(set) var loginItemEnabled = false
    let notifier = LocalNotifier()
    let demo: Bool
    private var state: MonitorState
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
        settings = demo ? Settings() : Settings.load()
        menuBarStyle = demo ? .percentage : MenuBarStyle.load()
        menuBarScope = demo ? .both : MenuBarScope.load()
        do { state = demo ? MonitorState() : try store.load() }
        catch { state = MonitorState(); persistenceWarning = "error.state_read" }
        state.snapshot = state.snapshot?.codexOnly
        state.records.removeAll { $0.event.bucketId != "codex" }
        state.detector.retainCodexOnly()
        snapshot = state.snapshot
        records = state.records
        if demo {
            snapshot = UsageSnapshot(observedAt: Date(), accountFingerprint: "demo", buckets: [
                RateBucket(primary: RateWindow(usedPercent: 24, windowDurationMins: 300, resetsAt: Date().addingTimeInterval(7680).timeIntervalSince1970),
                           secondary: RateWindow(usedPercent: 39, windowDurationMins: 10080, resetsAt: Date().addingTimeInterval(230400).timeIntervalSince1970), planType: "pro",
                           credits: .init(hasCredits: true, unlimited: false, balance: "128.5"))
            ])
        }
    }

    var codexBucket: RateBucket? { snapshot?.codexBucket }
    var credits: CreditsSnapshot? { codexBucket?.credits }
    var isStale: Bool {
        guard let snapshot else { return false }
        return lastError != nil || now.timeIntervalSince(snapshot.observedAt) > max(90, settings.refreshInterval * 2)
    }
    var menuBarTitle: String {
        MenuBarPresentation.title(bucket: codexBucket, stale: lastError != nil || isStale, scope: menuBarScope)
    }
    var menuBarHelp: String {
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
        if isRefreshing { return L10n.text("status.refreshing") }
        if lastError != nil { return L10n.text("status.error") }
        if isStale { return L10n.text("status.stale") }
        if snapshot == nil { return L10n.text("status.connecting") }
        return L10n.text("status.connected")
    }

    func start() {
        localeObservation = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        loginItemEnabled = SMAppService.mainApp.status == .enabled
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
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

    func refresh() async {
        guard !demo, !isRefreshing else { return }
        refreshTimer?.invalidate()
        isRefreshing = true
        let revision = settingsRevision
        do {
            let fresh = try await CodexClient().fetch(configuration: .init(executablePath: settings.codexPath, homePath: settings.codexHome))
            if revision == settingsRevision {
                let switchedAccount = state.snapshot.map { $0.accountFingerprint != fresh.accountFingerprint } ?? false
                if switchedAccount { state.records = [] }
                let events = state.detector.observe(fresh)
                state.snapshot = fresh
                snapshot = fresh
                for event in events where event.bucketId == "codex" {
                    let hook = settings.webhookEnabled && webhookConfiguration != nil
                    state.records.insert(EventRecord(event: event, localStatus: settings.notificationsEnabled ? "notification.waiting" : "notification.disabled",
                        webhookStatus: hook ? "webhook.waiting" : "webhook.disabled", webhookFingerprint: hook ? webhookConfiguration?.fingerprint : nil,
                        webhookPending: hook, localPending: settings.notificationsEnabled), at: 0)
                }
                state.records = Array(state.records.prefix(100))
                records = state.records
                lastError = nil
                sourceConnection.complete(revision: revision)
                failures = 0
                persist()
            }
        } catch {
            if revision == settingsRevision {
                failures += 1
                lastError = .from(error)
                sourceConnection.complete(revision: revision, error: .from(error))
            }
        }
        isRefreshing = false
        now = Date()
        if revision != settingsRevision {
            Task { await refresh() }
            return
        }
        scheduleNextRefresh()
        await deliverPending()
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
        settings = updated
        guard !demo else { return }
        settings.save()
        if changedSource {
            settingsRevision += 1
            state = MonitorState()
            snapshot = nil
            records = []
            lastError = nil
            persist()
            Task { await refresh() }
        } else {
            scheduleNextRefresh()
        }
        Task { await deliverPending() }
    }

    func saveAndConnect(executablePath: String, homePath: String) {
        guard !demo else { sourceConnection.reject("status.demo"); return }
        do {
            _ = try CodexLocator.executable(custom: executablePath)
            _ = try CodexLocator.home(custom: homePath)
            var updated = settings
            updated.codexPath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.codexHome = homePath.trimmingCharacters(in: .whitespacesAndNewlines)
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
            try await WebhookSender().send(event: .testEvent(), configuration: configuration, isTest: true)
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
        do { try store.save(state); stateSaved = true; persistenceWarning = nil }
        catch { stateSaved = false; persistenceWarning = "error.state_write" }
    }

    private func updateRecord(_ id: String, _ change: (inout EventRecord) -> Void) {
        guard let index = state.records.firstIndex(where: { $0.id == id }) else { return }
        change(&state.records[index])
        records = state.records
        persist()
    }

    private func deliverPending() async {
        guard !demo, !isDelivering else { return }
        if !stateSaved { persist() }
        guard stateSaved else { return }
        isDelivering = true
        defer { isDelivering = false }
        for record in state.records {
            guard record.event.bucketId == "codex" else { continue }
            guard state.records.contains(where: { $0.id == record.id }) else { continue }
            if record.localPending {
                // Persist before posting to prevent duplicate banners.
                updateRecord(record.id) { $0.localPending = false; $0.localStatus = settings.notificationsEnabled ? "notification.submitting" : "notification.disabled" }
                guard stateSaved else { return }
                if settings.notificationsEnabled {
                    do {
                        let status = try await notifier.send(record.event, sound: settings.notificationSound)
                        updateRecord(record.id) { $0.localStatus = status }
                    } catch { updateRecord(record.id) { $0.localStatus = "notification.failed" } }
                }
            }
            guard record.webhookPending, record.nextAttemptAt.map({ $0 <= Date() }) ?? true else { continue }
            guard state.records.contains(where: { $0.id == record.id }) else { continue }
            guard record.webhookAttempts < 3 else {
                updateRecord(record.id) { $0.webhookPending = false; $0.webhookStatus = "webhook.limit_reached" }
                continue
            }
            guard settings.webhookEnabled, let configuration = webhookConfiguration,
                  record.webhookFingerprint == configuration.fingerprint else {
                updateRecord(record.id) { $0.webhookPending = false; $0.webhookStatus = "webhook.cancelled" }
                continue
            }
            updateRecord(record.id) { $0.webhookAttempts += 1; $0.webhookStatus = "webhook.delivering" }
            guard stateSaved else { return }
            do {
                try await WebhookSender().send(event: record.event, configuration: configuration)
                updateRecord(record.id) { $0.webhookPending = false; $0.webhookStatus = "webhook.delivered" }
            } catch {
                let retryable = (error as? WebhookDeliveryError)?.retryable ?? false
                updateRecord(record.id) {
                    $0.webhookPending = retryable && $0.webhookAttempts < 3
                    $0.nextAttemptAt = $0.webhookPending ? Date().addingTimeInterval(Double($0.webhookAttempts) * 60) : nil
                    $0.webhookStatus = $0.webhookPending ? .init("webhook.retrying", String($0.webhookAttempts)) : .from(error)
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
