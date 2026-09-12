import AppKit
import SwiftUI
import TibometerCore

private final class QuotaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class PanelDimensions: ObservableObject {
    @Published var size = CGSize(width: 372, height: 540)
}

private struct DashboardHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct DashboardContainer: View {
    @ObservedObject var dimensions: PanelDimensions
    let monitor: UsageMonitor
    let openSettings: () -> Void
    let heightChanged: (CGFloat) -> Void

    var body: some View {
        ScrollView(.vertical) {
            DashboardView(monitor: monitor, notifier: monitor.notifier, openSettings: openSettings,
                          width: dimensions.size.width)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: DashboardHeight.self, value: geometry.size.height)
                })
        }
        .frame(width: dimensions.size.width, height: dimensions.size.height, alignment: .top)
        .background(TibometerStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.09)))
        .onPreferenceChange(DashboardHeight.self, perform: heightChanged)
    }
}

@MainActor
final class DashboardPanelController {
    private let panel = QuotaPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let dimensions = PanelDimensions()
    private let statusItem: NSStatusItem
    private var measuredHeight: CGFloat = 540
    private var globalMouseMonitor: Any?
    private var localEventMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?

    var isShown: Bool { panel.isVisible }

    init(monitor: UsageMonitor, statusItem: NSStatusItem, openSettings: @escaping () -> Void) {
        self.statusItem = statusItem
        panel.title = L10n.text("app.quota_title")
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        let host = NSHostingController(rootView: DashboardContainer(dimensions: dimensions, monitor: monitor,
            openSettings: openSettings, heightChanged: { [weak self] height in
                DispatchQueue.main.async { self?.contentHeightChanged(height) }
            }))
        // PanelPlacement owns sizing and anchoring.
        host.sizingOptions = []
        panel.contentViewController = host
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if self?.isShown == true { self?.position() } }
            }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.hide() } }
    }

    func updateLanguage() {
        panel.title = L10n.text("app.quota_title")
    }

    func show() {
        position()
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        installDismissalHandlers()
    }

    func hide() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        globalMouseMonitor = nil
        localEventMonitor = nil
    }

    private func position() {
        let anchor: CGRect? = statusItem.button.flatMap { button in
            button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) }
        }
        let screen = anchor.flatMap { rect in NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) } }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visibleAnchor = anchor.flatMap { screen.frame.intersects($0) && $0.width > 0 ? $0 : nil }
        let frame = PanelPlacement.frame(anchor: visibleAnchor, visibleFrame: screen.visibleFrame,
                                        contentSize: CGSize(width: 372, height: measuredHeight))
        if dimensions.size != frame.size { dimensions.size = frame.size }
        panel.setFrame(frame, display: true)
    }

    private func contentHeightChanged(_ height: CGFloat) {
        guard height.isFinite, height > 0, abs(height - measuredHeight) > 0.5 else { return }
        measuredHeight = ceil(height)
        if isShown { position() }
    }

    private func installDismissalHandlers() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.hide()
                return nil
            }
            // Picker windows stay interactive while the panel is open.
            if event.type != .keyDown, let window = event.window, window !== self.statusItem.button?.window,
               window.level < self.panel.level { self.hide() }
            return event
        }
    }

    func stop() {
        hide()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }
}
