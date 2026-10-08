// Gzowo Concierge for macOS - the flat black and white avatar drawn natively for the notch (8 shapes, eyes that follow the pointer).
import SwiftUI

struct BotBody: Shape {
    var kind: String

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        switch kind {
        case "squircle":
            return Path(roundedRect: r, cornerRadius: w * 0.32, style: .continuous)
        case "capsule":
            return Path(roundedRect: CGRect(x: r.minX, y: r.minY + h * 0.2, width: w, height: h * 0.6), cornerRadius: h * 0.3, style: .continuous)
        case "pebble":
            var p = Path()
            p.move(to: CGPoint(x: r.minX + w * 0.12, y: r.minY + h * 0.55))
            p.addCurve(to: CGPoint(x: r.minX + w * 0.55, y: r.minY + h * 0.1), control1: CGPoint(x: r.minX + w * 0.04, y: r.minY + h * 0.25), control2: CGPoint(x: r.minX + w * 0.3, y: r.minY + h * 0.08))
            p.addCurve(to: CGPoint(x: r.minX + w * 0.96, y: r.minY + h * 0.58), control1: CGPoint(x: r.minX + w * 0.85, y: r.minY + h * 0.12), control2: CGPoint(x: r.minX + w * 1.0, y: r.minY + h * 0.38))
            p.addCurve(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h * 0.94), control1: CGPoint(x: r.minX + w * 0.92, y: r.minY + h * 0.84), control2: CGPoint(x: r.minX + w * 0.72, y: r.minY + h * 0.96))
            p.addCurve(to: CGPoint(x: r.minX + w * 0.12, y: r.minY + h * 0.55), control1: CGPoint(x: r.minX + w * 0.26, y: r.minY + h * 0.92), control2: CGPoint(x: r.minX + w * 0.14, y: r.minY + h * 0.78))
            return p
        case "triangle":
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY + h * 0.06))
            p.addLine(to: CGPoint(x: r.maxX - w * 0.02, y: r.maxY - h * 0.08))
            p.addLine(to: CGPoint(x: r.minX + w * 0.02, y: r.maxY - h * 0.08))
            p.closeSubpath()
            return p.strokedPath(StrokeStyle(lineWidth: w * 0.18, lineJoin: .round)).union(p)
        case "hexagon":
            var p = Path()
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 - .pi / 2 + .pi / 6
                let pt = CGPoint(x: r.midX + cos(a) * w * 0.42, y: r.midY + sin(a) * h * 0.42)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
            return p.strokedPath(StrokeStyle(lineWidth: w * 0.14, lineJoin: .round)).union(p)
        case "cloud":
            var p = Path()
            for (cx, cy, rad) in [(0.3, 0.55, 0.25), (0.52, 0.38, 0.28), (0.72, 0.55, 0.24), (0.5, 0.64, 0.3)] {
                p.addEllipse(in: CGRect(x: r.minX + w * (cx - rad), y: r.minY + h * (cy - rad), width: w * rad * 2, height: h * rad * 2))
            }
            return p
        case "droplet":
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY + h * 0.04))
            p.addCurve(to: CGPoint(x: r.maxX - w * 0.1, y: r.minY + h * 0.64), control1: CGPoint(x: r.midX + w * 0.12, y: r.minY + h * 0.28), control2: CGPoint(x: r.maxX - w * 0.1, y: r.minY + h * 0.42))
            p.addArc(center: CGPoint(x: r.midX, y: r.minY + h * 0.64), radius: w * 0.4, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addCurve(to: CGPoint(x: r.midX, y: r.minY + h * 0.04), control1: CGPoint(x: r.minX + w * 0.1, y: r.minY + h * 0.42), control2: CGPoint(x: r.midX - w * 0.12, y: r.minY + h * 0.28))
            return p
        default:
            return Path(ellipseIn: r)
        }
    }
}

struct NotchBot: View {
    var kind: String
    var color: String
    var size: CGFloat
    var busy: Bool
    var alert: Bool
    var look: CGSize
    var blink: Bool

    var body: some View {
        let white = color != "black"
        let body = white ? Color.white : Color(white: 0.16)
        let eye = white ? Color.black : Color.white
        let eyeH = size * (alert ? 0.34 : 0.27) * (blink ? 0.12 : 1)
        ZStack {
            BotBody(kind: kind).fill(body)
            if !white { BotBody(kind: kind).stroke(Color.white.opacity(0.35), lineWidth: 1) }
            HStack(spacing: size * 0.17) {
                Capsule().fill(eye).frame(width: size * 0.11, height: eyeH)
                Capsule().fill(eye).frame(width: size * 0.11, height: eyeH)
            }
            .offset(x: look.width * size * 0.1, y: look.height * size * 0.06 - size * 0.02)
        }
        .frame(width: size, height: size)
    }
}
