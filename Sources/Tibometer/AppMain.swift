import AppKit
import SwiftUI
import Combine
import TibometerCore

@main
struct TibometerMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var dashboard: DashboardPanelController!
    private var settingsWindow: NSWindow?
    private var monitor: UsageMonitor!
    private var renderedMenuBar: MenuBarRenderer?
    private var renderedMultiMenuBar: MultiAccountMenuBarRenderer?
    private var menuLanguage: AppLanguage?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = CommandLine.arguments.contains("--demo")
        // Enforce one running instance for direct executable launches.
        if !demo, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
            NSApp.terminate(nil)
            return
        }
        monitor = UsageMonitor(demo: demo)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "Tibometer.QuotaStatus"
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
            button.image = nil
            button.imagePosition = .noImage
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel(L10n.text("app.accessibility"))
        }
        dashboard = DashboardPanelController(monitor: monitor, statusItem: statusItem, openSettings: { [weak self] in self?.showSettings() })
        monitor.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }.store(in: &cancellables)
        updateStatusItem()
        monitor.start()
        if CommandLine.arguments.contains("--show") { togglePopover() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    private func updateStatusItem() {
        if menuLanguage != L10n.language {
            menuLanguage = L10n.language
            NSApp.mainMenu = ApplicationMenu.make()
        }
        let title = monitor.menuBarTitle
        if monitor.accounts.count > 1, let button = statusItem.button {
            let renderer = MultiAccountMenuBarRenderer(values: monitor.accountSummaries.prefix(2).compactMap { summary in
                summary.remainingPercent.map { Int($0.rounded(.down)) }
            }, warning: MultiAccountPresentation.aggregate(monitor.accountSummaries).issueCount > 0)
            if renderer != renderedMultiMenuBar {
                button.title = ""
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleNone
                button.image = renderer.image() ?? BrandAssets.menuBarIcon
                renderedMultiMenuBar = renderer
            }
            renderedMenuBar = nil
        } else {
            let renderer = MenuBarRenderer(style: monitor.menuBarStyle, bucket: monitor.codexBucket,
                                           scope: monitor.menuBarScope,
                                           stale: monitor.lastError != nil || monitor.isStale)
            if renderer != renderedMenuBar, let button = statusItem.button {
                button.title = ""
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleNone
                if let image = renderer.image() {
                    button.image = image
                } else {
                    button.image = BrandAssets.menuBarIcon
                }
                renderedMenuBar = renderer
            }
            renderedMultiMenuBar = nil
        }
        statusItem.button?.toolTip = "\(title)\n\(monitor.statusText)\n\(monitor.menuBarHelp)"
        statusItem.button?.setAccessibilityLabel(L10n.text("app.accessibility"))
        statusItem.button?.setAccessibilityValue(monitor.menuBarTitle)
        settingsWindow?.title = L10n.text("app.settings_title")
        dashboard.updateLanguage()
    }

    @objc private func togglePopover() {
        if dashboard.isShown { dashboard.hide(); return }
        dashboard.show()
        Task { await monitor.notifier.refreshPermission() }
    }

    private func showSettings() {
        dashboard.hide()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 570),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L10n.text("app.settings_title")
            window.contentView = NSHostingView(rootView: SettingsView(monitor: monitor, notifier: monitor.notifier))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        window.contentView = nil
        settingsWindow = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            dashboard.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { dashboard?.stop(); monitor?.stop() }
}
