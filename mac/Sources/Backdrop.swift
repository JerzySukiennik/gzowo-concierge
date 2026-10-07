// Gzowo Concierge for macOS - static neutral in-window backdrop that the glass panels refract (no desktop transparency: that pegs the GPU on this Mac).
import SwiftUI

struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let light = scheme == .light
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
            colors: light
                ? [Color(white: 0.955), Color(white: 0.925), Color(white: 0.945),
                   Color(white: 0.935), Color(white: 0.965), Color(white: 0.915),
                   Color(white: 0.925), Color(white: 0.945), Color(white: 0.905)]
                : [Color(white: 0.105), Color(white: 0.085), Color(white: 0.115),
                   Color(white: 0.095), Color(white: 0.125), Color(white: 0.080),
                   Color(white: 0.090), Color(white: 0.105), Color(white: 0.070)]
        )
        .ignoresSafeArea()
    }
}
