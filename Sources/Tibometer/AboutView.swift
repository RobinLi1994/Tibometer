import SwiftUI
import TibometerCore

struct AboutView: View {
    @State private var showingLicense = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var websiteURL: URL {
        URL(string: "https://tibometer.app" + L10n.language.websitePath)!
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BrandLogo(size: 80)
                VStack(spacing: 8) {
                    Text("Tibometer").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(L10n.text("app.tagline")).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(L10n.text("about.version", version))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    Link(destination: websiteURL) {
                        Label(L10n.text("about.website"), systemImage: "globe")
                    }
                    Link(destination: URL(string: "https://github.com/nangcr/Tibometer")!) {
                        Label { Text("GitHub") } icon: { GitHubIcon() }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Divider()

                VStack(spacing: 12) {
                    LabeledContent(L10n.text("about.author")) {
                        Link(destination: URL(string: "https://github.com/nangcr")!) {
                            Label { Text("nangcr") } icon: { GitHubIcon() }
                        }
                    }
                    LabeledContent(L10n.text("about.license")) {
                        Button("MIT") { showingLicense = true }
                            .buttonStyle(.link)
                    }
                }
                .font(.callout)

                Link(destination: TiboThanks.composeURL) {
                    Label(L10n.text("thanks.button"), systemImage: "hand.thumbsup")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help(L10n.text("thanks.help"))
            }
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.vertical, 24)
        }
        .sheet(isPresented: $showingLicense) { LicenseView() }
    }
}

private struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss

    private var text: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return L10n.text("about.license_unavailable")
        }
        return contents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MIT License").font(.headline)
            ScrollView {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button(L10n.text("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 460)
        .onExitCommand { dismiss() }
    }
}
