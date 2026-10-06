import SwiftUI

public enum LiquidGlassStyle: Sendable {
    case regular
    case clear
    case tinted(Color)
    case interactive
    case interactiveTinted(Color)
}

public struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let style: LiquidGlassStyle
    let shape: S

    public init(style: LiquidGlassStyle = .regular, shape: S) {
        self.style = style
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            modernGlassBody(content: content)
        } else {
            legacyMaterialBody(content: content)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func modernGlassBody(content: Content) -> some View {
        switch style {
        case .regular:
            content
                .glassEffect(.regular, in: shape)
        case .clear:
            content
                .glassEffect(.clear, in: shape)
        case .tinted(let color):
            content
                .glassEffect(.regular.tint(color), in: shape)
        case .interactive:
            content
                .glassEffect(.regular.interactive(), in: shape)
        case .interactiveTinted(let color):
            content
                .glassEffect(.regular.tint(color).interactive(), in: shape)
        }
    }

    @ViewBuilder
    private func legacyMaterialBody(content: Content) -> some View {
        switch style {
        case .regular, .interactive:
            content
                .background(.ultraThinMaterial, in: shape)
        case .clear:
            content
                .background(.thinMaterial, in: shape)
        case .tinted(let color), .interactiveTinted(let color):
            content
                .background(color.opacity(0.15), in: shape)
                .background(.ultraThinMaterial, in: shape)
        }
    }
}

public extension View {
    func liquidGlass<S: Shape>(
        _ style: LiquidGlassStyle = .regular,
        in shape: S
    ) -> some View {
        self.modifier(LiquidGlassModifier(style: style, shape: shape))
    }
}
