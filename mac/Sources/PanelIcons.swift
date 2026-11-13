// Gzowo Concierge for macOS - animated icons for the panel tiles: a laptop whose lid folds shut, a screen that switches off like an old CRT, a keyboard swept by a wave of light.
import SwiftUI

struct LaptopIcon: View {
    var closed: Bool
    var hover: Bool
    var color: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                RoundedRectangle(cornerRadius: 2.6, style: .continuous).strokeBorder(color, lineWidth: 1.7)
                RoundedRectangle(cornerRadius: 1.2, style: .continuous).fill(color.opacity(closed ? 0 : (hover ? 0.42 : 0.22))).padding(3.2)
            }
            .frame(width: 20, height: 14)
            .rotation3DEffect(.degrees(closed ? 76 : (hover ? -14 : 0)), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.55)
            .offset(y: -3)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(color).frame(width: 27, height: 3.2)
            if closed {
                PowerLED(color: color).offset(x: 9.5, y: -4.6)
                    .transition(.scale(scale: 0.2).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.25)))
            }
        }
        .frame(width: 30, height: 24)
        .animation(.spring(response: 0.5, dampingFraction: 0.62), value: closed)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: hover)
    }
}

private struct PowerLED: View {
    var color: Color
    @State private var glow = false

    var body: some View {
        Circle().fill(color).frame(width: 3, height: 3)
            .opacity(glow ? 1 : 0.3)
            .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true } }
    }
}

private struct CRT: Equatable {
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var light: Double = 1
}

struct DisplayIcon: View {
    var hover: Bool
    var trigger: Int
    var color: Color

    var body: some View {
        let base = hover ? 0.5 : 0.28
        VStack(spacing: 1.4) {
            ZStack {
                RoundedRectangle(cornerRadius: 2.6, style: .continuous).strokeBorder(color, lineWidth: 1.7)
                KeyframeAnimator(initialValue: CRT(), trigger: trigger) { v in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(color.opacity(min(1, base * v.light)))
                        .scaleEffect(x: v.sx, y: v.sy)
                        .padding(3.4)
                } keyframes: { _ in
                    KeyframeTrack(\.light) {
                        LinearKeyframe(3.2, duration: 0.06)
                        LinearKeyframe(3.2, duration: 0.2)
                        LinearKeyframe(0, duration: 0.1)
                        LinearKeyframe(0, duration: 0.5)
                        LinearKeyframe(1, duration: 0.01)
                    }
                    KeyframeTrack(\.sy) {
                        CubicKeyframe(0.07, duration: 0.14)
                        LinearKeyframe(0.07, duration: 0.72)
                        LinearKeyframe(1, duration: 0.01)
                    }
                    KeyframeTrack(\.sx) {
                        LinearKeyframe(1, duration: 0.14)
                        CubicKeyframe(0.02, duration: 0.14)
                        LinearKeyframe(0.02, duration: 0.58)
                        LinearKeyframe(1, duration: 0.01)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: hover)
            }
            .frame(width: 24, height: 16)
            Capsule().fill(color).frame(width: 10, height: 1.8)
        }
        .frame(width: 30, height: 24)
        .scaleEffect(hover ? 1.06 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hover)
    }
}

struct KeyboardIcon: View {
    var hover: Bool
    var color: Color
    private let rows: [[CGFloat]] = [[1, 1, 1, 1, 1, 1], [1, 1, 1, 1, 1, 1], [1.4, 3.6, 1.4]]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 40, paused: !hover)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(color, lineWidth: 1.6)
                VStack(spacing: 1.3) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 1.3) {
                            ForEach(rows[r].indices, id: \.self) { k in
                                let x = (CGFloat(rows[r][..<k].reduce(0, +)) + rows[r][k] / 2) / CGFloat(rows[r].reduce(0, +))
                                RoundedRectangle(cornerRadius: 0.6, style: .continuous)
                                    .fill(color.opacity(level(x: x, row: r, t: t)))
                                    .frame(width: 2.6 * rows[r][k] + 1.3 * (rows[r][k] - 1), height: 2.4)
                            }
                        }
                    }
                }
            }
            .frame(width: 28, height: 17)
        }
        .frame(width: 30, height: 24)
        .scaleEffect(hover ? 1.05 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hover)
    }

    private func level(x: CGFloat, row: Int, t: Double) -> Double {
        guard hover else { return 0.55 }
        let phase = (t * 1.25).truncatingRemainder(dividingBy: 1) * 1.6 - 0.3
        let d = abs(Double(x) - phase - Double(row) * 0.06)
        return 0.4 + 0.6 * max(0, 1 - d * 5)
    }
}
