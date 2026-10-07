// Gzowo Concierge for macOS - cheap static glass: translucent material, luminous edge and top sheen (system glassEffect pegs the GPU on this Mac).
import SwiftUI

struct GlassPanel: ViewModifier {
    var radius: CGFloat = 28
    var strength: Material = .thinMaterial
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let light = scheme == .light
        content
            .background(shape.fill(strength))
            .background(shape.fill(light ? Color.white.opacity(0.28) : Color.white.opacity(0.04)))
            .background(
                shape.fill(LinearGradient(colors: [Color.white.opacity(light ? 0.34 : 0.07), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.22)))
            )
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(light ? 0.95 : 0.30), Color.white.opacity(light ? 0.25 : 0.05), Color.white.opacity(light ? 0.55 : 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.9)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(light ? 0.07 : 0.28), radius: 14, y: 5)
    }
}

extension View {
    func glassPanel(radius: CGFloat = 28, strength: Material = .thinMaterial) -> some View {
        modifier(GlassPanel(radius: radius, strength: strength))
    }
}
