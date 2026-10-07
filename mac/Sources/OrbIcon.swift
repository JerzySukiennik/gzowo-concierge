// Gzowo Concierge for macOS - draws the menu bar orb for each assistant state.
import AppKit

enum OrbIcon {
    static func image(for state: HostState, phase: CGFloat) -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            let alive = state.online
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let ring = NSBezierPath()
            ring.appendArc(withCenter: c, radius: 7.4, startAngle: 0, endAngle: 360)
            ring.lineWidth = 1.5
            if !alive { ring.setLineDash([2.0, 2.4], count: 2, phase: 0) }
            NSGraphicsContext.current?.saveGraphicsState()
            if state.busy || state.live == "thinking" || !alive { NSColor.black.withAlphaComponent(alive ? 0.32 : 0.55).setStroke() }
            ring.stroke()
            NSGraphicsContext.current?.restoreGraphicsState()

            if state.busy || state.live == "thinking" {
                let arc = NSBezierPath()
                let start = phase * 360
                arc.appendArc(withCenter: c, radius: 7.4, startAngle: start, endAngle: start + 105)
                arc.lineWidth = 1.9
                arc.lineCapStyle = .round
                arc.stroke()
            }

            var core: CGFloat = 3.6
            if state.live == "speaking" { core = 3.6 + 1.1 * (0.5 + 0.5 * sin(phase * .pi * 8)) }
            else if state.live == "listening" { core = 3.9 }
            if alive { NSBezierPath(ovalIn: NSRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2)).fill() }

            if state.pending > 0 {
                let r: CGFloat = 3.1
                let badge = NSRect(x: rect.maxX - r * 2 - 0.5, y: rect.maxY - r * 2 - 0.5, width: r * 2, height: r * 2)
                NSGraphicsContext.current?.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: badge.insetBy(dx: -1.4, dy: -1.4)).fill()
                NSGraphicsContext.current?.restoreGraphicsState()
                NSBezierPath(ovalIn: badge).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
