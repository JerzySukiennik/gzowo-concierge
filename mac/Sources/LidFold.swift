// Gzowo Concierge for macOS - lid fold: reads the hinge angle sensor and folds a frosted snapshot of the built-in screen as the lid closes and opens.
import AppKit
import CoreImage
import IOKit.hid
import QuartzCore
import ScreenCaptureKit

final class LidAngleSensor {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?

    init?() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x05ac, kIOHIDProductIDKey: 0x8104, kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 0x8A] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let d = set.first,
              IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
        device = d
    }

    func angle() -> Double? {
        guard let device else { return nil }
        var buf = [UInt8](repeating: 0, count: 8)
        var len = CFIndex(8)
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &buf, &len) == kIOReturnSuccess, len >= 3 else { return nil }
        return Double(Int(buf[2]) << 8 | Int(buf[1]))
    }
}

private let foldCI = CIContext(options: [.useSoftwareRenderer: false])

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

@MainActor
final class FoldOverlay {
    private let window: NSWindow
    private let card = CALayer()
    private let sharp = CALayer()
    private let soft = CALayer()
    private let heavy = CALayer()
    private let frost = CALayer()
    private let shade = CAGradientLayer()
    private let sheen = CAGradientLayer()
    private let size: CGSize

    init(screen: NSScreen, image: CGImage?) {
        size = screen.frame.size
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)
        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        window.contentView = view
        guard let host = view.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.backgroundColor = NSColor.black.cgColor
        card.anchorPoint = .zero
        card.bounds = CGRect(origin: .zero, size: size)
        card.position = .zero
        card.backgroundColor = NSColor.black.cgColor
        host.addSublayer(card)

        for l in [sharp, soft, heavy] {
            l.frame = card.bounds
            l.contentsGravity = .resize
            l.minificationFilter = .linear
            l.magnificationFilter = .linear
            card.addSublayer(l)
        }
        sharp.contents = image
        soft.opacity = 0
        heavy.opacity = 0

        frost.frame = card.bounds
        frost.backgroundColor = NSColor(white: 0.92, alpha: 1).cgColor
        frost.opacity = 0
        card.addSublayer(frost)

        sheen.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.5)
        sheen.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 0.35).cgColor, NSColor(white: 1, alpha: 0).cgColor]
        sheen.startPoint = CGPoint(x: 0.5, y: 0)
        sheen.endPoint = CGPoint(x: 0.5, y: 1)
        sheen.opacity = 0
        card.addSublayer(sheen)

        shade.frame = card.bounds
        shade.colors = [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.cgColor]
        shade.startPoint = CGPoint(x: 0.5, y: 0)
        shade.endPoint = CGPoint(x: 0.5, y: 1)
        shade.opacity = 0
        card.addSublayer(shade)
        CATransaction.commit()
    }

    func setBlurred(soft s: CGImage?, heavy h: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        soft.contents = s
        heavy.contents = h
        CATransaction.commit()
    }

    func show() { window.orderFrontRegardless() }

    /// Projects the picture so it stays fixed in space while the panel turns about the hinge by `delta` radians.
    /// A point (x, y) of the picture lands on the panel at (u, v) = ((K x + Ex sin d y) / w, (Ez y) / w) with
    /// K = Ez cos d - Ey sin d and w = sin d (y - Ey) + Ez cos d, seen from an eye at (Ex, Ey, Ez) in front of the screen.
    private func homography(_ delta: CGFloat) -> CATransform3D {
        let ex = size.width / 2, ey = size.height * 0.6, ez = size.height * 3.0
        let sd = sin(delta), cd = cos(delta)
        let k = ez * cd - ey * sd
        var t = CATransform3DIdentity
        t.m11 = k; t.m21 = ex * sd; t.m41 = 0
        t.m12 = 0; t.m22 = ez; t.m42 = 0
        t.m14 = 0; t.m24 = sd; t.m44 = k
        t.m33 = 1
        return t
    }

    func update(progress p: Double, delta: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let tilt = 38 * (1 - (1 - p) * (1 - p))
        card.transform = homography(CGFloat(min(tilt, max(delta, 0)) * .pi / 180))
        let so = smoothstep(0.05, 0.45, p), ho = smoothstep(0.4, 0.85, p)
        soft.opacity = Float(so)
        heavy.opacity = Float(ho)
        sharp.isHidden = so > 0.995 && soft.contents != nil
        soft.isHidden = ho > 0.995 && heavy.contents != nil
        frost.opacity = Float(0.2 * smoothstep(0.15, 0.8, p))
        sheen.opacity = Float(sin(.pi * min(p * 1.1, 1)) * 0.6)
        sheen.position = CGPoint(x: size.width / 2, y: size.height * (1.15 - 1.2 * CGFloat(p)))
        shade.opacity = Float(smoothstep(0.3, 0.95, p))
        card.opacity = Float(1 - smoothstep(0.88, 1, p))
        CATransaction.commit()
    }

    func dismiss() {
        let w = window
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            w.animator().alphaValue = 0
        }, completionHandler: { w.orderOut(nil) })
    }
}

@MainActor
final class LidFoldController {
    private let sensor = LidAngleSensor()
    private var timer: Timer?
    private var fast = false
    private var smoothed: Double = 110
    private var lastRaw: Double = 110
    private var rest: Double = 110
    private var stillSince = Date()
    private var overlay: FoldOverlay?
    private var snapshot: CGImage?
    private var blurred: (CGImage?, CGImage?)?
    private var capturing = false
    private var demo: [Double] = []
    private let key = "lidFoldEnabled"
    private static let end: Double = 16

    var available: Bool { sensor != nil }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key); newValue ? start() : stop() }
    }

    func start() {
        guard enabled, sensor != nil, timer == nil else { return }
        if let a = sensor?.angle() { smoothed = a; lastRaw = a; rest = max(70, a) }
        schedule(fast: false)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stillSince = Date(); self?.schedule(fast: true) }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.lid-demo"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.playDemo() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        overlay?.dismiss()
        overlay = nil
        snapshot = nil
        blurred = nil
    }

    func playDemo() {
        guard overlay == nil else { return }
        let top = max(rest, 100)
        var seq: [Double] = []
        let n = 90
        for i in 0...n { let t = Double(i) / Double(n); seq.append(top - (top - 8) * (0.5 - 0.5 * cos(.pi * t))) }
        seq += Array(repeating: 8, count: 30)
        for i in 0...n { let t = Double(i) / Double(n); seq.append(8 + (top - 8) * (0.5 - 0.5 * cos(.pi * t))) }
        seq += Array(repeating: top, count: 40)
        demo = seq
        rest = top
        smoothed = top
        lastRaw = top
        stillSince = Date()
        schedule(fast: true)
    }

    private func schedule(fast f: Bool) {
        if timer != nil && fast == f { return }
        fast = f
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: f ? 1.0 / 60 : 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private static var builtinScreen: NSScreen? {
        NSScreen.screens.first { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(n.uint32Value) != 0
        }
    }

    private func tick() {
        let demoMode = !demo.isEmpty
        guard let raw = demoMode ? demo.removeFirst() : sensor?.angle() else { return }
        let now = Date()
        if abs(raw - lastRaw) > 0.9 { stillSince = now }
        lastRaw = raw
        smoothed += (raw - smoothed) * (fast ? 0.5 : 1)
        let a = smoothed
        if overlay == nil && now.timeIntervalSince(stillSince) > 1.2 && a > 60 { rest = a }

        let start = rest - 7
        let p = min(max((start - a) / (start - Self.end), 0), 1)

        if snapshot == nil && !capturing && a < rest - 2.5 { capture() }

        if p > 0.002 {
            schedule(fast: true)
            if overlay == nil, let screen = Self.builtinScreen, snapshot != nil || !CGPreflightScreenCaptureAccess() {
                let o = FoldOverlay(screen: screen, image: snapshot)
                if let b = blurred { o.setBlurred(soft: b.0, heavy: b.1) }
                o.show()
                overlay = o
            }
            overlay?.update(progress: p, delta: rest - a)
            if !demoMode && now.timeIntervalSince(stillSince) > 1.5 && p < 0.7 {
                overlay?.dismiss()
                overlay = nil
                snapshot = nil
                blurred = nil
                rest = max(60, a)
            }
        } else {
            if let o = overlay { o.update(progress: 0, delta: 0); o.dismiss(); overlay = nil }
            if a >= rest - 1.5 && !capturing { snapshot = nil; blurred = nil }
            let settle = !demoMode && overlay == nil && a >= rest - 2.5 && now.timeIntervalSince(stillSince) > 0.6
            if settle { schedule(fast: false) }
        }
    }

    private func capture() {
        guard let screen = Self.builtinScreen, CGPreflightScreenCaptureAccess(),
              let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        capturing = true
        let id = num.uint32Value
        let scale = screen.backingScaleFactor
        Task {
            defer { Task { @MainActor in self.capturing = false } }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let display = content.displays.first(where: { $0.displayID == id }) else { return }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(CGFloat(display.width) * scale)
            cfg.height = Int(CGFloat(display.height) * scale)
            cfg.showsCursor = false
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg) else { return }
            await MainActor.run { self.snapshot = img }
            let blurs = await Task.detached(priority: .userInitiated) { () -> (CGImage?, CGImage?) in
                (Self.blur(img, sigma: 9), Self.blur(img, sigma: 26))
            }.value
            await MainActor.run {
                self.blurred = blurs
                self.overlay?.setBlurred(soft: blurs.0, heavy: blurs.1)
            }
        }
    }

    nonisolated private static func blur(_ img: CGImage, sigma: Double) -> CGImage? {
        let small = CIImage(cgImage: img).transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let ext = small.extent
        let out = small.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: ext)
        return foldCI.createCGImage(out, from: ext)
    }
}
