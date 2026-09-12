import SwiftUI

enum TibometerStyle {
    static let accent = Color(nsColor: .systemBlue)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let foreground = gray(light: 0.12, dark: 0.94)
    static let background = gray(light: 0.965, dark: 0.105)
    static let surface = gray(light: 1, dark: 0.145)
    static let subtleSurface = gray(light: 0.93, dark: 0.205)
    static let border = gray(light: 0.855, dark: 0.29)
    static let progressTrack = gray(light: 0.83, dark: 0.31)
    static let proBadgeGradient = LinearGradient(
        colors: [Color(red: 0.98, green: 0.92, blue: 0.93), Color(red: 0.82, green: 0.95, blue: 0.97)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func progressColor(_ remaining: Double) -> NSColor {
        if remaining < 25 { return .systemRed }
        if remaining < 50 { return .systemYellow }
        return .systemGreen
    }

    private static func gray(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let level = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
        })
    }
}

struct TibometerTheme: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(TibometerStyle.accent)
            .accentColor(TibometerStyle.accent)
            .symbolRenderingMode(.monochrome)
            .buttonStyle(.automatic)
    }
}
