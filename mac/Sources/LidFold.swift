// Gzowo Concierge for macOS - lid fold: as the lid closes, the screen image stays where it stood, seen through the lid as through glass that frosts and darkens; driven by the hinge angle sensor.
import AppKit
import CoreImage
import IOKit.hid
import QuartzCore
import ScreenCaptureKit

final class LidAngleSensor: @unchecked Sendable {
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

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetWindowBackgroundBlurRadius") private func CGSSetWindowBackgroundBlurRadius(_ cid: Int32, _ wid: UInt32, _ radius: Int32) -> Int32

private typealias WindowGrab = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
private let windowGrab: WindowGrab? = {
    guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
          let f = dlsym(h, "CGWindowListCreateImage") else { return nil }
    return unsafeBitCast(f, to: WindowGrab.self)
}()

private let foldCI = CIContext(options: [.useSoftwareRenderer: false])

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

private func easeOut(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return 1 - (1 - t) * (1 - t)
}

private enum Fold {
    static let eyeDistance = 2.6
    static let eyeHeight = 0.6
    static let hinge = 0.0
    static let vanish = atan2(eyeDistance, eyeHeight)
    static let span = vanish - 6 * Double.pi / 180
    static let maxBlur = 64.0

    static func plate(_ delta: Double, height: Double) -> CATransform3D? {
        let s = sin(delta), c = cos(delta)
        let k = eyeDistance * c - eyeHeight * s
        guard k > 0.01 else { return nil }
        var t = CATransform3DIdentity
        t.m22 = CGFloat(eyeDistance / k)
        t.m24 = CGFloat(s / (k * height))
        return t
    }
}

@MainActor
final class FoldOverlay {
    let screenFrame: CGRect
    private let imageWindow: NSWindow
    private let glassWindow: NSWindow
    private let plate = CALayer()
    private let sharp = CALayer()
    private let vivid = CALayer()
    private let dim = CAGradientLayer()
    private let crease = CAGradientLayer()
    private let cid = CGSMainConnectionID()
    private var radius: Int32 = -1

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let size = screen.frame.size
        imageWindow = Self.window(screen.frame, opaque: true, level: .screenSaver)
        glassWindow = Self.window(screen.frame, opaque: false, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let host = imageWindow.contentView?.layer {
            host.backgroundColor = NSColor.black.cgColor
            plate.bounds = CGRect(origin: .zero, size: size)
            plate.anchorPoint = CGPoint(x: 0.5, y: -Fold.hinge)
            plate.position = CGPoint(x: size.width / 2, y: -Fold.hinge * size.height)
            plate.allowsEdgeAntialiasing = true
            for l in [sharp, vivid] {
                l.frame = plate.bounds
                l.contentsGravity = .resize
                l.minificationFilter = .trilinear
                l.allowsEdgeAntialiasing = true
                plate.addSublayer(l)
            }
            vivid.opacity = 0
            host.addSublayer(plate)
        }
        if let host = glassWindow.contentView?.layer {
            dim.frame = host.bounds
            dim.colors = [NSColor.black.cgColor, NSColor.black.withAlphaComponent(0.8).cgColor]
            dim.startPoint = CGPoint(x: 0.5, y: 0)
            dim.endPoint = CGPoint(x: 0.5, y: 1)
            dim.opacity = 0
            host.addSublayer(dim)
            crease.frame = host.bounds
            crease.colors = [NSColor.black.cgColor, NSColor.black.withAlphaComponent(0.45).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
            crease.locations = [0, 0.09, 0.22]
            crease.startPoint = CGPoint(x: 0.5, y: 0)
            crease.endPoint = CGPoint(x: 0.5, y: 1)
            crease.opacity = 0
            host.addSublayer(crease)
        }
        CATransaction.commit()
    }

    private static func window(_ frame: CGRect, opaque: Bool, level: NSWindow.Level) -> NSWindow {
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = opaque
        w.backgroundColor = opaque ? .black : NSColor.black.withAlphaComponent(0.002)
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none
        w.level = level
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.setFrame(frame, display: false)
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        w.contentView = view
        return w
    }

    var glassID: UInt32 { UInt32(glassWindow.windowNumber) }
    var hasImage: Bool { sharp.contents != nil }

    func showGlass() {
        setBlur(0)
        glassWindow.orderFrontRegardless()
    }

    func setImage(_ img: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sharp.contents = img
        vivid.contents = nil
        plate.transform = CATransform3DIdentity
        plate.isHidden = false
        CATransaction.commit()
        imageWindow.orderFrontRegardless()
    }

    func setVivid(_ img: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        vivid.contents = img
        CATransaction.commit()
    }

    func update(frost p: Double, geometry delta: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if hasImage {
            if let t = Fold.plate(delta, height: screenFrame.height) {
                plate.transform = t
                plate.isHidden = false
            } else {
                plate.isHidden = true
            }
        }
        vivid.opacity = Float(easeOut(p / 0.7))
        dim.opacity = Float(0.5 * easeOut(p / 0.7) + 0.5 * smoothstep(0.7, 1, p))
        crease.opacity = Float(0.5 * easeOut(p / 0.6))
        CATransaction.commit()
        setBlur(Int32((Fold.maxBlur * easeOut(p / 0.55)).rounded()))
    }

    func hide() {
        imageWindow.orderOut(nil)
        glassWindow.orderOut(nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sharp.contents = nil
        vivid.contents = nil
        dim.opacity = 0
        crease.opacity = 0
        CATransaction.commit()
        setBlur(0)
    }

    private func setBlur(_ r: Int32) {
        guard r != radius else { return }
        radius = r
        _ = CGSSetWindowBackgroundBlurRadius(cid, glassID, r)
    }
}

@MainActor
final class LidFoldController {
    private let sensor = LidAngleSensor()
    private let pollQueue = DispatchQueue(label: "fun.gzowo.concierge.lid.poll", qos: .userInteractive)
    private let grabQueue = DispatchQueue(label: "fun.gzowo.concierge.lid.grab", qos: .userInteractive)
    private var source: DispatchSourceTimer?
    private var fast = false
    private var observing = false
    private var smoothed: Double = 110
    private var lastRaw: Double = 110
    private var rest: Double = 110
    private var stillSince = Date()
    private var overlay: FoldOverlay?
    private var active = false
    private var frost: Double = 0
    private var geometry: Double = 0
    private var cycle = 0
    private var demo: [Double] = []
    private var demoImage: CGImage?
    private let key = "lidFoldEnabled"

    var available: Bool { sensor != nil }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key); newValue ? start() : stop() }
    }

    func start() {
        guard enabled, let sensor, source == nil else { return }
        if let a = sensor.angle() { smoothed = a; lastRaw = a; rest = max(60, a) }
        let s = DispatchSource.makeTimerSource(queue: pollQueue)
        s.setEventHandler { [weak self] in
            let a = sensor.angle()
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reading(a) } }
        }
        s.schedule(deadline: .now(), repeating: 1.0 / 30, leeway: .milliseconds(2))
        s.resume()
        source = s
        fast = false
        warmUp()
        guard !observing else { return }
        observing = true
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stillSince = Date(); self?.warmUp() }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.lid-demo"), object: nil, queue: .main) { [weak self] note in
            let path = note.object as? String
            MainActor.assumeIsolated { self?.playDemo(imagePath: path) }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        demo = []
        finish()
    }

    func playDemo(imagePath: String? = nil) {
        guard source != nil, !active, demo.isEmpty else { return }
        if let path = imagePath, let ns = NSImage(contentsOfFile: path) {
            demoImage = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
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
        setRate(fast: true)
    }

    private func setRate(fast f: Bool) {
        guard f != fast, let source else { return }
        fast = f
        source.schedule(deadline: .now(), repeating: f ? 1.0 / 60 : 1.0 / 30, leeway: .milliseconds(2))
    }

    private static var builtinScreen: NSScreen? {
        NSScreen.screens.first { displayID($0).map { CGDisplayIsBuiltin($0) != 0 } ?? false }
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func reading(_ value: Double?) {
        let demoMode = !demo.isEmpty
        guard let raw = demoMode ? demo.removeFirst() : value else { return }
        if demo.isEmpty && demoMode { demoImage = nil }
        let now = Date()
        if abs(raw - lastRaw) > 0.9 { stillSince = now }
        lastRaw = raw
        smoothed += (raw - smoothed) * (active ? 0.55 : 1)
        let still = now.timeIntervalSince(stillSince)

        if !active {
            if still > 1 && raw > 45 { rest = raw }
            guard rest - raw >= 1 else { setRate(fast: demoMode); return }
            begin()
        }

        var goal = max(0, rest - smoothed) * .pi / 180
        if !demoMode && still > 0.6 && goal < Fold.span * 0.85 {
            rest = smoothed
            goal = 0
        }
        setRate(fast: demoMode || still < 1)
        frost += (goal - frost) * 0.6
        if overlay?.hasImage == true { geometry += (goal - geometry) * 0.3 }
        overlay?.update(frost: min(frost / Fold.span, 1), geometry: geometry)
        if goal < 0.004 && frost < 0.004 && geometry < 0.006 { finish() }
    }

    private func begin() {
        guard let screen = Self.builtinScreen else { return }
        if overlay?.screenFrame != screen.frame { overlay?.hide(); overlay = FoldOverlay(screen: screen) }
        guard let overlay else { return }
        active = true
        cycle += 1
        frost = 0
        geometry = 0
        setRate(fast: true)
        overlay.showGlass()
        if let img = demoImage { show(img, cycle: cycle) } else { grab(screen, below: overlay.glassID, cycle: cycle) }
    }

    private func finish() {
        guard active else { return }
        active = false
        cycle += 1
        frost = 0
        geometry = 0
        overlay?.hide()
    }

    private func show(_ img: CGImage, cycle c: Int) {
        overlay?.setImage(img)
        geometry = 0
        grabQueue.async { [weak self] in
            let v = Self.vivid(img)
            DispatchQueue.main.async { MainActor.assumeIsolated { if let self, self.cycle == c { self.overlay?.setVivid(v) } } }
        }
    }

    private func grab(_ screen: NSScreen, below wid: UInt32, cycle c: Int) {
        guard CGPreflightScreenCaptureAccess(), let id = Self.displayID(screen) else { return }
        let bounds = CGDisplayBounds(id)
        let scale = screen.backingScaleFactor
        grabQueue.async { [weak self] in
            let img = windowGrab?(bounds, 1 << 2, wid, 1 << 3)?.takeRetainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.cycle == c, self.active else { return }
                    if let img { self.show(img, cycle: c) } else { self.grabFallback(id, scale: scale, cycle: c) }
                }
            }
        }
    }

    private func grabFallback(_ id: CGDirectDisplayID, scale: CGFloat, cycle c: Int) {
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let display = content.displays.first(where: { $0.displayID == id }) else { return }
            let mine = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(CGFloat(display.width) * scale)
            cfg.height = Int(CGFloat(display.height) * scale)
            cfg.showsCursor = false
            let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
            guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg),
                  cycle == c, active else { return }
            show(img, cycle: c)
        }
    }

    private func warmUp() {
        guard CGPreflightScreenCaptureAccess() else { return }
        grabQueue.async {
            _ = windowGrab?(CGRect(x: 0, y: 0, width: 8, height: 8), 1, 0, 0)?.takeRetainedValue()
            let tiny = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
            _ = foldCI.createCGImage(tiny.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.8]), from: tiny.extent)
        }
    }

    nonisolated private static func vivid(_ img: CGImage) -> CGImage? {
        let src = CIImage(cgImage: img).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        let out = src.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.8])
        return foldCI.createCGImage(out, from: src.extent)
    }
}
