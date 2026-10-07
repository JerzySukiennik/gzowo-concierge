// Gzowo Concierge for macOS - static in-window backdrop that the glass panels refract (no desktop transparency: that pegs the GPU on this Mac).
import SwiftUI

struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let light = scheme == .light
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
            colors: light
                ? [Color(red: 0.93, green: 0.94, blue: 1.00), Color(red: 0.86, green: 0.91, blue: 1.00), Color(red: 0.95, green: 0.92, blue: 1.00),
                   Color(red: 0.90, green: 0.96, blue: 1.00), Color(red: 0.97, green: 0.95, blue: 1.00), Color(red: 0.88, green: 0.93, blue: 0.99),
                   Color(red: 1.00, green: 0.94, blue: 0.96), Color(red: 0.91, green: 0.94, blue: 1.00), Color(red: 0.89, green: 0.95, blue: 1.00)]
                : [Color(red: 0.08, green: 0.09, blue: 0.16), Color(red: 0.07, green: 0.11, blue: 0.22), Color(red: 0.12, green: 0.09, blue: 0.20),
                   Color(red: 0.06, green: 0.12, blue: 0.20), Color(red: 0.10, green: 0.11, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.18),
                   Color(red: 0.14, green: 0.09, blue: 0.16), Color(red: 0.07, green: 0.10, blue: 0.19), Color(red: 0.06, green: 0.11, blue: 0.18)]
        )
        .ignoresSafeArea()
    }
}
