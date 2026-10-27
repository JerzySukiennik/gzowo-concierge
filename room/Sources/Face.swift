// Concierge Pokój - the Concierge avatar always on screen: asleep and dimmed between conversations, awake with eyes that follow the person in front of the camera.
import AppKit
import AVFoundation
import IOKit.graphics
import IOKit.pwr_mgt
import QuartzCore
import SwiftUI
import Vision

enum FacePhase { case sleeping, listening, thinking, speaking, ringing }

final class FaceModel: ObservableObject {
    @Published var phase: FacePhase = .sleeping
    @Published var look = CGSize.zero
    @Published var level: CGFloat = 0
    @Published var caption = ""
    @Published var blink = false
    @Published var shape = "circle"
}

struct FaceBody: Shape {
    var kind: String
    func path(in r: CGRect) -> Path {
        switch kind {
        case "squircle": return Path(roundedRect: r, cornerRadius: r.width * 0.32, style: .continuous)
        case "capsule": return Path(roundedRect: CGRect(x: r.minX, y: r.minY + r.height * 0.2, width: r.width, height: r.height * 0.6), cornerRadius: r.height * 0.3, style: .continuous)
        default: return Path(ellipseIn: r)
        }
    }
}

struct FaceView: View {
    @ObservedObject var model: FaceModel

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.46
            let asleep = model.phase == .sleeping
            let eyeW = size * (asleep ? 0.13 : 0.11)
            let base: CGFloat = {
                switch model.phase {
                case .sleeping: return 0.028
                case .listening: return 0.3
                case .thinking: return 0.12
                case .speaking: return 0.2 + model.level * 0.14
                case .ringing: return 0.36
                }
            }()
            let eyeH = size * base * (model.blink && !asleep ? 0.1 : 1)
            let look = model.phase == .thinking ? CGSize(width: 0.5, height: -0.7) : (asleep ? CGSize(width: 0, height: 0.45) : model.look)
            ZStack {
                Color.black
                VStack(spacing: size * 0.16) {
                    ZStack {
                        FaceBody(kind: model.shape).fill(Color(white: asleep ? 0.34 : 1))
                        HStack(spacing: size * 0.17) {
                            Capsule().fill(Color.black).frame(width: eyeW, height: max(eyeH, 3))
                            Capsule().fill(Color.black).frame(width: eyeW, height: max(eyeH, 3))
                        }
                        .offset(x: look.width * size * 0.13, y: look.height * size * 0.09)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: look)
                        .animation(.easeOut(duration: model.blink ? 0.06 : (asleep ? 0.5 : 0.18)), value: eyeH)
                    }
                    .frame(width: size, height: size)
                    .animation(.easeInOut(duration: 0.6), value: asleep)
                    .scaleEffect(model.phase == .thinking ? 0.97 : 1)
                    .animation(model.phase == .thinking ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: model.phase)
                    Text(model.caption)
                        .font(.system(size: size * 0.11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(white: 0.75))
                        .frame(height: size * 0.16)
                        .opacity(model.caption.isEmpty ? 0 : 1)
                }
                .offset(y: size * 0.08)
            }
        }
        .ignoresSafeArea()
    }
}

final class FaceWindow: NSWindow {
    var onUserInput: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onUserInput() }
    override func mouseDown(with event: NSEvent) { onUserInput() }
}

final class FaceScreen {
    let model = FaceModel()
    var onUserInput: () -> Void = {}
    private var window: FaceWindow?
    private var host: NSView?
    private var overlay: NSView?
    private var zLayers: [CATextLayer] = []
    private let tracker = FaceTracker()
    private var blinkTimer: Timer?
    private var brightnessTimer: Timer?
    private var activity: IOPMAssertionID = 0
    private var asideUntil = Date.distantPast
    private let headless = ProcessInfo.processInfo.environment["ROOM_HEADLESS"] != nil

    init() {
        tracker.onLook = { [weak self] look in self?.model.look = look }
    }

    var asleep: Bool { model.phase == .sleeping }

    func start() {
        guard !headless else { return }
        present()
        sleep()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.window?.isVisible == false && Date() >= self.asideUntil { self.present() }
            if self.asleep { self.setBrightness(Self.sleepBrightness(), over: 3) }
        }
    }

    func wake(_ phase: FacePhase) {
        model.phase = phase
        guard !headless else { return }
        IOPMAssertionDeclareUserActivity("Concierge Pokoj" as CFString, kIOPMUserActiveLocal, &activity)
        asideUntil = .distantPast
        present()
        stopSleepAnimations()
        setBrightness(0.8, over: 0.4)
        tracker.start()
        startBlinking()
    }

    func sleep() {
        model.phase = .sleeping
        model.caption = ""
        model.look = .zero
        guard !headless else { return }
        tracker.stop()
        blinkTimer?.invalidate()
        blinkTimer = nil
        startSleepAnimations()
        setBrightness(Self.sleepBrightness(), over: 2.5)
    }

    func stepAside(minutes: Double) {
        guard !headless, let w = window else { return }
        asideUntil = Date().addingTimeInterval(minutes * 60)
        setBrightness(0.7, over: 0.3)
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.3; w.animator().alphaValue = 0 }, completionHandler: { w.orderOut(nil) })
    }

    func snapshot(to path: String) {
        typealias Grab = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let w = window, let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let f = dlsym(h, "CGWindowListCreateImage"),
              let img = unsafeBitCast(f, to: Grab.self)(.null, 1 << 3, UInt32(w.windowNumber), 1 << 3)?.takeRetainedValue(),
              let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static func sleepBrightness() -> Float {
        let h = Calendar.current.component(.hour, from: Date())
        return (h >= 22 || h < 7) ? 0.02 : 0.12
    }

    private func present() {
        guard let screen = NSScreen.main else { return }
        let w = window ?? makeWindow(screen)
        window = w
        w.setFrame(screen.frame, display: true)
        if !w.isVisible || w.alphaValue < 1 {
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            w.makeKey()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.4; w.animator().alphaValue = 1 }
        }
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private func makeWindow(_ screen: NSScreen) -> FaceWindow {
        let w = FaceWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = true
        w.backgroundColor = .black
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        let hosting = NSHostingView(rootView: FaceView(model: model))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        container.addSubview(hosting)
        let over = NSView(frame: container.bounds)
        over.layer = CALayer()
        over.wantsLayer = true
        over.autoresizingMask = [.width, .height]
        container.addSubview(over)
        w.contentView = container
        host = hosting
        overlay = over
        w.onUserInput = { [weak self] in self?.onUserInput() }
        return w
    }

    private func startSleepAnimations() {
        guard let layer = host?.layer, let root = overlay?.layer else { return }
        let b = root.bounds
        let c = CGPoint(x: b.midX, y: b.midY - min(b.width, b.height) * 0.04)
        var t = CATransform3DMakeTranslation(c.x, c.y, 0)
        t = CATransform3DScale(t, 0.975, 0.975, 1)
        t = CATransform3DTranslate(t, -c.x, -c.y, 0)
        let breathe = CABasicAnimation(keyPath: "transform")
        breathe.fromValue = CATransform3DIdentity
        breathe.toValue = t
        breathe.duration = 2.6
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(breathe, forKey: "breathe")

        guard zLayers.isEmpty else { return }
        let size = min(b.width, b.height) * 0.46
        let start = CGPoint(x: b.midX + size * 0.42, y: b.midY + size * 0.32)
        for i in 0..<3 {
            let z = CATextLayer()
            z.string = "z"
            z.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            z.fontSize = size * (0.09 + CGFloat(i) * 0.03)
            z.foregroundColor = NSColor(white: 0.4, alpha: 1).cgColor
            z.contentsScale = window?.backingScaleFactor ?? 2
            z.alignmentMode = .center
            z.bounds = CGRect(x: 0, y: 0, width: size * 0.3, height: size * 0.3)
            z.position = start
            z.opacity = 0
            root.addSublayer(z)
            let rise = CABasicAnimation(keyPath: "position")
            rise.fromValue = NSValue(point: start)
            rise.toValue = NSValue(point: CGPoint(x: start.x + size * 0.22, y: start.y + size * 0.42))
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.2, 0.7, 1]
            let group = CAAnimationGroup()
            rise.duration = 3.6
            fade.duration = 3.6
            group.animations = [rise, fade]
            group.duration = 3.6
            group.repeatCount = .infinity
            group.beginTime = CACurrentMediaTime() + Double(i) * 1.2
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            z.add(group, forKey: "float")
            zLayers.append(z)
        }
    }

    private func stopSleepAnimations() {
        host?.layer?.removeAnimation(forKey: "breathe")
        zLayers.forEach { $0.removeFromSuperlayer() }
        zLayers.removeAll()
    }

    private func startBlinking() {
        guard blinkTimer == nil else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.asleep, Int.random(in: 0..<4) == 0 else { return }
            self.model.blink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.model.blink = false }
        }
    }

    private func setBrightness(_ target: Float, over seconds: Double) {
        brightnessTimer?.invalidate()
        guard let from = Self.brightness() else { return }
        let steps = max(1, Int(seconds * 20))
        var i = 0
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: seconds / Double(steps), repeats: true) { [weak self] t in
            i += 1
            Self.setBrightness(from + (target - from) * Float(i) / Float(steps))
            if i >= steps { t.invalidate(); self?.brightnessTimer = nil }
        }
    }

    private static func displays(_ body: (io_service_t) -> Void) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &it) == KERN_SUCCESS else { return }
        var s = IOIteratorNext(it)
        while s != 0 { body(s); IOObjectRelease(s); s = IOIteratorNext(it) }
        IOObjectRelease(it)
    }

    private static func brightness() -> Float? {
        var value: Float?
        displays { s in
            var v: Float = 0
            if value == nil, IODisplayGetFloatParameter(s, 0, kIODisplayBrightnessKey as CFString, &v) == kIOReturnSuccess { value = v }
        }
        return value
    }

    private static func setBrightness(_ v: Float) {
        displays { s in IODisplaySetFloatParameter(s, 0, kIODisplayBrightnessKey as CFString, max(0, min(1, v))) }
    }
}

final class FaceTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onLook: (CGSize) -> Void = { _ in }
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "room.camera")
    private var configured = false
    private var frame = 0
    private var lastSeen = Date.distantPast

    func start() {
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else { return }
        if !configured {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            session.sessionPreset = .vga640x480
            if session.canAddInput(input) { session.addInput(input) }
            let out = AVCaptureVideoDataOutput()
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(out) { session.addOutput(out) }
            session.commitConfiguration()
            configured = true
        }
        queue.async { [session] in if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
        DispatchQueue.main.async { self.onLook(.zero) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frame += 1
        guard frame % 4 == 0, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let req = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([req])
        let faces = (req.results as? [VNFaceObservation]) ?? []
        if let f = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            lastSeen = Date()
            let x = -(f.boundingBox.midX - 0.5) * 2.2
            let y = -(f.boundingBox.midY - 0.55) * 2.2
            let look = CGSize(width: max(-1, min(1, x)), height: max(-1, min(1, y)))
            DispatchQueue.main.async { self.onLook(look) }
        } else if Date().timeIntervalSince(lastSeen) > 1.5 {
            DispatchQueue.main.async { self.onLook(.zero) }
        }
    }
}
