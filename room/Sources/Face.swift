// Concierge Pokój - full-screen face on a black screen: the Concierge avatar whose eyes follow the person in front of the camera.
import AppKit
import AVFoundation
import IOKit.pwr_mgt
import SwiftUI
import Vision

enum FacePhase { case listening, thinking, speaking, ringing, idle }

final class FaceModel: ObservableObject {
    @Published var phase: FacePhase = .idle
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
            let eyeW = size * 0.11
            let base: CGFloat = {
                switch model.phase {
                case .listening: return 0.3
                case .thinking: return 0.12
                case .speaking: return 0.2 + model.level * 0.14
                case .ringing: return 0.36
                case .idle: return 0.24
                }
            }()
            let eyeH = size * base * (model.blink ? 0.1 : 1)
            let look = model.phase == .thinking ? CGSize(width: 0.5, height: -0.7) : model.look
            ZStack {
                Color.black
                VStack(spacing: size * 0.16) {
                    ZStack {
                        FaceBody(kind: model.shape).fill(Color.white)
                        HStack(spacing: size * 0.17) {
                            Capsule().fill(Color.black).frame(width: eyeW, height: max(eyeH, 3))
                            Capsule().fill(Color.black).frame(width: eyeW, height: max(eyeH, 3))
                        }
                        .offset(x: look.width * size * 0.13, y: look.height * size * 0.09)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: look)
                        .animation(.easeOut(duration: model.blink ? 0.06 : 0.12), value: eyeH)
                    }
                    .frame(width: size, height: size)
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
    private var window: FaceWindow?
    private let tracker = FaceTracker()
    private var blinkTimer: Timer?
    private var activity: IOPMAssertionID = 0
    var onUserInput: () -> Void = {}

    init() {
        tracker.onLook = { [weak self] look in self?.model.look = look }
    }

    var visible: Bool { window?.isVisible == true && (window?.alphaValue ?? 0) > 0.5 }

    private let headless = ProcessInfo.processInfo.environment["ROOM_HEADLESS"] != nil

    func show(_ phase: FacePhase) {
        model.phase = phase
        guard !headless else { return }
        IOPMAssertionDeclareUserActivity("Concierge Pokoj" as CFString, kIOPMUserActiveLocal, &activity)
        guard let screen = NSScreen.main else { return }
        let w = window ?? makeWindow(screen)
        window = w
        w.setFrame(screen.frame, display: true)
        if !w.isVisible || w.alphaValue < 1 {
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            w.makeKey()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; w.animator().alphaValue = 1 }
        }
        tracker.start()
        startBlinking()
    }

    func hide(sleepDisplay: Bool) {
        guard !headless else { model.caption = ""; return }
        tracker.stop()
        blinkTimer?.invalidate()
        blinkTimer = nil
        model.caption = ""
        guard let w = window, w.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.6; w.animator().alphaValue = 0 }, completionHandler: {
            w.orderOut(nil)
            let idle = CGEventType(rawValue: ~0).map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) } ?? 999
            guard sleepDisplay, idle > 90 else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["displaysleepnow"]
            try? p.run()
        })
    }

    private func makeWindow(_ screen: NSScreen) -> FaceWindow {
        let w = FaceWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = true
        w.backgroundColor = .black
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: FaceView(model: model))
        w.onUserInput = { [weak self] in self?.onUserInput() }
        NSCursor.setHiddenUntilMouseMoves(true)
        return w
    }

    private func startBlinking() {
        guard blinkTimer == nil else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, Int.random(in: 0..<4) == 0 else { return }
            self.model.blink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.model.blink = false }
        }
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
