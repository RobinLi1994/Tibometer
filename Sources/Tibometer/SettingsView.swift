import AppKit
import SwiftUI
import TibometerCore

struct SettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general, notifications, webhooks, source, about

        var id: Self { self }

        var title: String {
            switch self {
            case .general: L10n.text("settings.general")
            case .notifications: L10n.text("settings.notifications")
            case .webhooks: "Webhook"
            case .source: L10n.text("settings.source")
            case .about: L10n.text("settings.about")
            }
        }
    }

    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var notifier: LocalNotifier
    @State private var selectedPage: Page = .general
    @State private var webhook = WebhookConfiguration()
    @State private var webhookEnabled = false
    @State private var codexPath = ""
    @State private var codexHome = ""
    @State private var useCCSwitch = false
    @State private var ccSwitchProviderID = ""
    @State private var ccSwitchProviders: [CCSwitchOfficialProvider] = []
    @State private var ccSwitchError: LocalizedMessage?

    private func binding<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(get: { monitor.settings[keyPath: keyPath] }, set: { value in
            var updated = monitor.settings; updated[keyPath: keyPath] = value; monitor.updateSettings(updated)
        })
    }

    var body: some View {
        VStack(spacing: 12) {
            PagePicker(selection: $selectedPage, titles: Page.allCases.map(\.title),
                       accessibilityLabel: L10n.text("app.settings_title"))

            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16).frame(width: 560, height: 570)
        .background(TibometerStyle.background)
        .modifier(TibometerTheme())
        .environment(\.locale, L10n.locale)
        .onAppear {
            webhook = monitor.loadWebhook()
            webhookEnabled = monitor.settings.webhookEnabled
            codexPath = monitor.settings.codexPath
            codexHome = monitor.settings.codexHome
            useCCSwitch = monitor.settings.ccSwitchProviderID != nil
            ccSwitchProviderID = monitor.settings.ccSwitchProviderID ?? ""
            reloadCCSwitchProviders()
            Task { await notifier.refreshPermission() }
        }
    }

    private struct PagePicker: NSViewRepresentable {
        @Binding var selection: Page
        let titles: [String]
        let accessibilityLabel: String

        func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

        func makeNSView(context: Context) -> NSSegmentedControl {
            let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne,
                                             target: context.coordinator, action: #selector(Coordinator.selectPage(_:)))
            control.segmentDistribution = .fillEqually
            control.controlSize = .regular
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return control
        }

        func updateNSView(_ control: NSSegmentedControl, context: Context) {
            context.coordinator.selection = $selection
            for (index, title) in titles.enumerated() where control.label(forSegment: index) != title {
                control.setLabel(title, forSegment: index)
            }
            let index = Page.allCases.firstIndex(of: selection) ?? 0
            if control.selectedSegment != index { control.selectedSegment = index }
            control.setAccessibilityLabel(accessibilityLabel)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
            let size = nsView.intrinsicContentSize
            return CGSize(width: proposal.width ?? size.width, height: size.height)
        }

        final class Coordinator: NSObject {
            var selection: Binding<Page>

            init(selection: Binding<Page>) { self.selection = selection }

            @objc func selectPage(_ control: NSSegmentedControl) {
                guard Page.allCases.indices.contains(control.selectedSegment) else { return }
                selection.wrappedValue = Page.allCases[control.selectedSegment]
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .general: general
        case .notifications: notifications
        case .webhooks: webhooks
        case .source: source
        case .about: AboutView().id(L10n.language)
        }
    }

    private var general: some View {
        Form {
            Section {
                Picker(L10n.text("language.title"), selection: Binding(get: { monitor.language }, set: monitor.setLanguage)) {
                    ForEach(AppLanguage.allCases) { language in Text(language.displayName).tag(language) }
                }
                .id(L10n.language)
            }
            Section {
                Picker(L10n.text("menu_scope.title"), selection: Binding(get: { monitor.menuBarScope }, set: monitor.setMenuBarScope)) {
                    ForEach(MenuBarScope.allCases) { scope in Text(scope.title).tag(scope) }
                }
                .id("scope.\(L10n.language.rawValue)")
                Picker(L10n.text("menu_style.title"), selection: Binding(get: { monitor.menuBarStyle }, set: monitor.setMenuBarStyle)) {
                    ForEach(MenuBarStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .id("style.\(L10n.language.rawValue)")
                LabeledContent(L10n.text("menu_style.preview")) {
                    MenuBarStylePreview(style: monitor.menuBarStyle, scope: monitor.menuBarScope)
                }
                Toggle(L10n.text("settings.start_login"), isOn: Binding(get: { monitor.loginItemEnabled }, set: monitor.setLaunchAtLogin))
                if let feedback = monitor.loginItemFeedback { Text(feedback.localized).font(.caption).foregroundStyle(.secondary) }
                Text(L10n.text("settings.position_help"))
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L10n.text("settings.menu_bar")) }
            Section {
                Picker(L10n.text("settings.interval"), selection: binding(\.refreshInterval)) {
                    Text(L10n.text("settings.interval_15")).tag(15.0)
                    Text(L10n.text("settings.interval_30")).tag(30.0)
                    Text(L10n.text("settings.interval_60")).tag(60.0)
                    Text(L10n.text("settings.interval_120")).tag(120.0)
                    Text(L10n.text("settings.interval_300")).tag(300.0)
                }
            } header: { Text(L10n.text("settings.monitoring")) }
        }.formStyle(.grouped)
    }

    private var notifications: some View {
        Form {
            Section {
                Toggle(L10n.text("notification.toggle"), isOn: binding(\.notificationsEnabled))
                Toggle(L10n.text("notification.sound"), isOn: binding(\.notificationSound)).disabled(!monitor.settings.notificationsEnabled)
            } header: { Text(L10n.text("notification.reset_section")) }
            Section {
                HStack {
                    Text(notifier.statusText)
                    Spacer()
                    if notifier.authorization == .notDetermined {
                        Button(L10n.text("notification.allow")) { Task { await notifier.requestPermission() } }
                    } else if notifier.authorization == .denied {
                        Button(L10n.text("notification.open_settings")) { notifier.openSystemSettings() }
                    }
                    Button(L10n.text("notification.test")) { Task { await monitor.testNotification() } }
                }
                if let feedback = monitor.notificationFeedback { Text(feedback.localized).font(.caption).foregroundStyle(.secondary) }
            } header: { Text(L10n.text("notification.permission_section")) }
            Section {
                if monitor.records.isEmpty {
                    Text(L10n.text("notification.no_history"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(monitor.records.prefix(20)) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.event.title).font(.system(size: 12, weight: .medium))
                        Text(L10n.date(record.event.observedAt, timeStyle: .medium)).font(.caption2).foregroundStyle(.tertiary)
                        Text("\(record.localStatus.localized) · \(record.webhookStatus.localized)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text(L10n.text("notification.history")) }
        }.formStyle(.grouped)
    }

    private var webhooks: some View {
        Form {
            Section {
                Toggle(L10n.text("webhook.toggle"), isOn: $webhookEnabled)
                Picker(L10n.text("webhook.format"), selection: $webhook.format) {
                    ForEach(WebhookFormat.allCases) { format in Text(format.title).tag(format) }
                }
                .id(L10n.language)
                TextField("Webhook URL", text: $webhook.url, prompt: Text("https://…"))
                    .autocorrectionDisabled()
                if webhook.format == .json {
                    SecureField(L10n.text("webhook.token"), text: $webhook.bearerToken)
                    SecureField(L10n.text("webhook.secret"), text: $webhook.signingSecret)
                } else if webhook.format == .feishu {
                    SecureField(L10n.text("webhook.bot_secret"), text: $webhook.signingSecret)
                }
            } header: { Text(L10n.text("webhook.receiver")) }
            Section {
                if let feedback = monitor.webhookFeedback {
                    Text(feedback.localized).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(monitor.isTestingWebhook ? L10n.text("webhook.sending") : L10n.text("webhook.test")) { Task { await monitor.testWebhook(cleanedWebhook) } }
                        .disabled(webhook.url.isEmpty || monitor.isTestingWebhook || monitor.demo)
                    Spacer()
                    Button { _ = monitor.saveWebhook(cleanedWebhook, enabled: webhookEnabled) } label: {
                        Text(L10n.text("webhook.save"))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }.formStyle(.grouped)
    }

    private var cleanedWebhook: WebhookConfiguration {
        var value = webhook
        value.url = value.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.format != .json { value.bearerToken = "" }
        if value.format != .json && value.format != .feishu { value.signingSecret = "" }
        return value
    }

    private var source: some View {
        Form {
            Section {
                Picker(L10n.text("source.mode"), selection: $useCCSwitch) {
                    Text(L10n.text("source.local_codex")).tag(false)
                    Text(L10n.text("source.ccswitch")).tag(true)
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField(L10n.text("source.executable"), text: $codexPath, prompt: Text(L10n.text("source.automatic")))
                    Button(L10n.text("source.choose"), action: chooseCodex)
                }
                if useCCSwitch {
                    HStack {
                        Picker(L10n.text("source.official_account"), selection: $ccSwitchProviderID) {
                            ForEach(ccSwitchProviders) { provider in Text(provider.name).tag(provider.id) }
                        }
                        Button(action: reloadCCSwitchProviders) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help(L10n.text("source.reload_accounts"))
                    }
                    HStack {
                        Text(OfficialCodexHome.defaultURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Spacer()
                        Button(L10n.text("source.copy_login"), action: copyOfficialLoginCommand)
                            .disabled(ccSwitchProviderID.isEmpty)
                    }
                    Text(L10n.text("source.ccswitch_help")).font(.caption).foregroundStyle(.secondary)
                    if let ccSwitchError { Text(ccSwitchError.localized).font(.caption).foregroundStyle(.secondary) }
                } else {
                    TextField(L10n.text("source.home"), text: $codexHome, prompt: Text(L10n.text("source.default_home")))
                    if let executable = try? CodexLocator.executable(custom: codexPath) {
                        LabeledContent(L10n.text("source.current")) { Text(executable).font(.caption).textSelection(.enabled).lineLimit(3) }
                    }
                }
                if let feedback = monitor.sourceConnection.message {
                    Text(feedback.localized).font(.caption).foregroundStyle(.secondary)
                }
                Button(L10n.text("source.save")) {
                    monitor.saveAndConnect(executablePath: codexPath, homePath: codexHome,
                                           ccSwitchProviderID: useCCSwitch ? ccSwitchProviderID : nil)
                }
                .disabled(useCCSwitch && ccSwitchProviderID.isEmpty)
            } header: { Text(L10n.text("source.custom_section")) }
        }.formStyle(.grouped)
    }

    private func reloadCCSwitchProviders() {
        do {
            ccSwitchProviders = try CCSwitchOfficialSource().providers()
            ccSwitchError = ccSwitchProviders.isEmpty ? TibometerError.officialProviderMissing.userMessage : nil
            if !ccSwitchProviders.contains(where: { $0.id == ccSwitchProviderID }) {
                ccSwitchProviderID = ccSwitchProviders.first?.id ?? ""
            }
        } catch {
            ccSwitchProviders = []
            ccSwitchProviderID = ""
            ccSwitchError = .from(error)
        }
    }

    private func copyOfficialLoginCommand() {
        do {
            try OfficialCodexHome.prepare()
            let executable = try CodexLocator.executable(custom: codexPath)
            let command = OfficialCodexHome.loginCommand(executable: executable)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            ccSwitchError = "source.login_copied"
        } catch { ccSwitchError = .from(error) }
    }

    private func chooseCodex() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("source.choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            codexPath = url.path
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}

private struct MenuBarStylePreview: View {
    let style: MenuBarStyle
    let scope: MenuBarScope
    private static let sample = RateBucket(
        primary: RateWindow(usedPercent: 24, windowDurationMins: 300, resetsAt: nil),
        secondary: RateWindow(usedPercent: 39, windowDurationMins: 10080, resetsAt: nil))

    var body: some View {
        Group {
            if let image = MenuBarRenderer(style: style, bucket: Self.sample, scope: scope).image() {
                Image(nsImage: image).renderingMode(.template)
            } else {
                Image(nsImage: BrandAssets.menuBarIcon).renderingMode(.original)
            }
        }
        .foregroundStyle(.primary)
        .frame(height: 24)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MenuBarPresentation.title(bucket: Self.sample, scope: scope))
    }
}
