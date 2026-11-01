import SwiftUI

/// A shared hover treatment for the workspace's text actions and menu labels.
struct ControlHoverEffect: ViewModifier {
    var pressed = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .foregroundColor(isEnabled && (hovering || pressed) ? .blue : nil)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(isEnabled ? (pressed ? 0.14 : hovering ? 0.08 : 0) : 0))
            }
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering && isEnabled)
    }
}

struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(ControlHoverEffect(pressed: configuration.isPressed))
    }
}

/// Color sidebar text and symbols together without changing row geometry.
struct NavigationHoverEffect: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .foregroundColor(hovering && isEnabled ? .blue : nil)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
