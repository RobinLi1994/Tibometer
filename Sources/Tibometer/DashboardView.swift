import SwiftUI
import TibometerCore

private enum DashboardLayout {
    static let iconWidth: CGFloat = 20
    static let rowSpacing: CGFloat = 10
    static let controlWidth: CGFloat = 44
    static let controlHeight: CGFloat = 32
    static let rowPadding: CGFloat = 12
    static let detailSpacing: CGFloat = 3
    static let textInset = iconWidth + rowSpacing
}

private enum DashboardTypography {
    static let brand = Font.system(size: 18, weight: .semibold)
    static let title = Font.system(size: 13, weight: .semibold)
    static let value = Font.system(size: 28, weight: .semibold)
    static let body = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11)
    static let action = Font.system(size: 12)
}

struct DashboardView: View {
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var notifier: LocalNotifier
    var openSettings: () -> Void
    var width: CGFloat = 372

    private var visibleCredits: CreditsSnapshot? {
        guard let credits = monitor.credits, credits.shouldDisplay else { return nil }
        return credits
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 16)
            quotaSection
            VStack(alignment: .leading, spacing: 0) {
                if let credits = visibleCredits {
                    CreditsRow(credits: credits, stale: monitor.isStale)
                        .id(L10n.language)
                        .padding(.vertical, DashboardLayout.rowPadding)
                    Divider()
                }
                notifications.padding(.vertical, DashboardLayout.rowPadding)
                Divider()
                connectionStatus.padding(.vertical, DashboardLayout.rowPadding)
                Divider()
                footer.padding(.top, 8)
            }
        }
        .padding(20).frame(width: width)
        .background(TibometerStyle.background)
        .modifier(TibometerTheme())
        .environment(\.locale, L10n.locale)
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandLogo(size: 40)
            VStack(alignment: .leading, spacing: DashboardLayout.detailSpacing) {
                Text("Tibometer").font(DashboardTypography.brand)
                Text(L10n.text("dashboard.subtitle"))
                    .font(DashboardTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let plan = monitor.codexBucket?.planType {
                let isPro = plan.lowercased() == "pro"
                Text(isPro ? "Pro" : plan.uppercased()).font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isPro ? Color(white: 0.15) : TibometerStyle.foreground)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background {
                        if isPro { Capsule().fill(TibometerStyle.proBadgeGradient) }
                        else { Capsule().fill(TibometerStyle.subtleSurface) }
                    }
            }
        }
    }

    @ViewBuilder private var quotaSection: some View {
        if !monitor.visibleWindows.isEmpty || visibleCredits == nil {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(monitor.visibleWindows) { kind in
                    if let window = monitor.codexBucket?.window(kind) {
                        QuotaCard(kind: kind, window: window, now: monitor.now, stale: monitor.isStale)
                    }
                }
                if monitor.visibleWindows.isEmpty && visibleCredits == nil {
                    Label(L10n.text(monitor.snapshot == nil && monitor.lastError == nil ? "quota.loading" : "quota.empty"),
                          systemImage: "chart.bar")
                    .font(DashboardTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 14).modifier(DashboardCardSurface())
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: DashboardLayout.rowSpacing) {
                Group {
                    if monitor.lastError != nil || monitor.isStale {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10)).foregroundStyle(TibometerStyle.warning)
                    } else {
                        Circle().fill(monitor.snapshot == nil ? Color.secondary : TibometerStyle.success)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: DashboardLayout.iconWidth).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DashboardLayout.detailSpacing) {
                    Text(monitor.statusText).font(DashboardTypography.body)
                    if monitor.snapshot != nil {
                        lastUpdated
                            .font(DashboardTypography.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                refreshButton.frame(width: DashboardLayout.controlWidth)
            }
            if let error = monitor.lastError { statusWarning(error.localized) }
            if let warning = monitor.persistenceWarning { statusWarning(warning.localized) }
        }
    }

    @ViewBuilder private var lastUpdated: some View {
        if let snapshot = monitor.snapshot {
            Text(L10n.text("dashboard.updated", L10n.date(snapshot.observedAt, dateStyle: .none, timeStyle: .medium)))
                .help(L10n.text("quota.last_updated", L10n.date(snapshot.observedAt, timeStyle: .medium)))
        }
    }

    private func statusWarning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DashboardLayout.rowSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .frame(width: DashboardLayout.iconWidth).foregroundStyle(TibometerStyle.warning)
                .accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true)
        }
        .font(DashboardTypography.caption)
    }

    private var notificationBinding: Binding<Bool> {
        Binding(get: { monitor.settings.notificationsEnabled }, set: { enabled in
            var updated = monitor.settings
            updated.notificationsEnabled = enabled
            monitor.updateSettings(updated)
            if enabled && !monitor.demo && notifier.authorization == .notDetermined {
                Task { await notifier.requestPermission() }
            }
        })
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: DashboardLayout.rowSpacing) {
                Image(systemName: monitor.settings.notificationsEnabled ? "bell" : "bell.slash")
                    .font(.system(size: 14)).frame(width: DashboardLayout.iconWidth)
                    .foregroundStyle(.primary).accessibilityHidden(true)
                Text(L10n.text("notification.reset_section")).font(DashboardTypography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle(L10n.text("notification.toggle"), isOn: notificationBinding)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .frame(width: DashboardLayout.controlWidth, height: DashboardLayout.controlHeight)
                    .modifier(SubtleHover())
            }
            if monitor.settings.notificationsEnabled && !monitor.demo &&
                (notifier.authorization == .notDetermined || notifier.authorization == .denied) {
                HStack(spacing: 8) {
                    Text(notifier.statusText).font(DashboardTypography.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button(L10n.text(notifier.authorization == .denied ? "notification.open_settings" : "notification.allow")) {
                        if notifier.authorization == .denied { notifier.openSystemSettings() }
                        else { Task { await notifier.requestPermission() } }
                    }.controlSize(.small)
                }
                .padding(.leading, DashboardLayout.textInset)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: openSettings) {
                HStack(spacing: DashboardLayout.rowSpacing) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13)).frame(width: DashboardLayout.iconWidth)
                    Text(L10n.text("common.settings"))
                        .font(DashboardTypography.action)
                }
                .padding(.trailing, 8)
                .frame(height: DashboardLayout.controlHeight)
            }
            .keyboardShortcut(",", modifiers: .command)
            Spacer(minLength: 4)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 13))
                    .frame(width: DashboardLayout.controlHeight, height: DashboardLayout.controlHeight)
            }
            .frame(width: DashboardLayout.controlWidth)
            .help(L10n.text("common.quit")).accessibilityLabel(L10n.text("common.quit"))
        }
        .buttonStyle(SubtleButtonStyle())
    }

    private var refreshButton: some View {
        Button { Task { await monitor.refresh() } } label: {
            Group {
                if monitor.isRefreshing { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.clockwise").font(.system(size: 13)) }
            }
            .frame(width: DashboardLayout.controlHeight, height: DashboardLayout.controlHeight)
        }
        .buttonStyle(SubtleButtonStyle())
        .disabled(monitor.isRefreshing || monitor.demo)
        .help(L10n.text("common.refresh")).accessibilityLabel(L10n.text("common.refresh"))
    }
}

private struct DashboardCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(TibometerStyle.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(TibometerStyle.border, lineWidth: 0.5))
    }
}

private struct CreditsRow: View {
    let credits: CreditsSnapshot
    let stale: Bool

    var body: some View {
        HStack(spacing: DashboardLayout.rowSpacing) {
            Image(systemName: "circle.grid.2x2").font(.system(size: 13))
                .frame(width: DashboardLayout.iconWidth).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: DashboardLayout.detailSpacing) {
                Text(L10n.text("credits.title")).font(DashboardTypography.body)
                if stale { Text(L10n.text("quota.stale")).font(DashboardTypography.caption).foregroundStyle(TibometerStyle.foreground) }
            }
            Spacer(minLength: 12)
            Text(credits.displayText)
                .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                .foregroundStyle(TibometerStyle.foreground)
                .lineLimit(1).minimumScaleFactor(0.5).help(credits.displayText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuotaCard: View {
    let kind: QuotaWindow
    let window: RateWindow
    let now: Date
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Text(kind.title).font(DashboardTypography.title)
                    if stale {
                        Text(L10n.text("quota.stale"))
                            .font(DashboardTypography.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let remaining = window.remainingPercent, remaining < 50 {
                        Image(systemName: remaining < 25 ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .help(L10n.text(remaining < 25 ? "quota.critical" : "quota.low"))
                            .accessibilityLabel(L10n.text(remaining < 25 ? "quota.critical" : "quota.low"))
                    }
                    Text(window.percentageText)
                        .font(DashboardTypography.value).monospacedDigit()
                }
                .foregroundStyle(TibometerStyle.foreground)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(TibometerStyle.progressTrack)
                    if let remaining = window.remainingPercent {
                        Capsule().fill(Color(nsColor: TibometerStyle.progressColor(remaining)))
                            .frame(width: max(0, geometry.size.width * remaining / 100))
                    }
                }
            }.frame(height: 6).accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    .accessibilityHidden(true)
                Text(L10n.countdown(window.resetDate, now: now))
                    .font(DashboardTypography.caption).fontWeight(.medium)
                Spacer(minLength: 6)
                if let date = window.resetDate {
                    Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(L10n.locale)))
                        .font(DashboardTypography.caption)
                        .accessibilityLabel(L10n.date(date, dateStyle: .full))
                }
            }
            .lineLimit(1).minimumScaleFactor(0.9)
            .foregroundStyle(.secondary)
            .help(window.resetDate.map { L10n.date($0, dateStyle: .full, timeStyle: .medium) } ?? L10n.text("quota.reset_unknown"))
        }
        .padding(.horizontal, 16).padding(.vertical, 14).modifier(DashboardCardSurface())
        .accessibilityElement(children: .combine)
    }
}
