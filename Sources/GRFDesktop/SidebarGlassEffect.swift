import SwiftUI

/// Use the native soft scroll-edge blur while preserving source-list clipping.
public struct SidebarGlassEffect: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}
