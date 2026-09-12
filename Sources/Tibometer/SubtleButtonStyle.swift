import SwiftUI

struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    private struct Content: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        private var fillOpacity: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.09 }
            return isHovered ? 0.045 : 0
        }

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .background(.primary.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isEnabled && isFocused ? TibometerStyle.accent.opacity(0.65) : .clear, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .opacity(isEnabled ? 1 : 0.45)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: fillOpacity)
                .onHover { isHovered = $0 }
        }
    }
}

struct SubtleHover: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(.primary.opacity(isEnabled && isHovered ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 6))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
