// Gzowo Concierge for macOS - keyboard cleaning mode: every key, media key and the Touch Bar are ignored while you wipe them; a click or a quiet minute ends it.
import AppKit
import SwiftUI

private final class CleanWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private struct CleanView: View {
    @ObservedObject var model: KeyboardClean

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "keyboard").font(.system(size: 54, weight: .light)).foregroundStyle(.white)
                Text("Czyszczenie klawiatury").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                Text("Klawisze i Touch Bar nic teraz nie robią. Kliknij gdziekolwiek, żeby skończyć.").font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 4)
                    Circle().trim(from: 0, to: model.quietLeft / 60).stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: model.quietLeft)
                    Text("\(Int(model.quietLeft.rounded(.up)))").font(.system(size: 20, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                .padding(.top, 8)
                Text("Odblokuje się sama po minucie bez naciśnięć. Naciśnięte: \(model.presses)").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.stop() }
    }
}

@MainActor
final class KeyboardClean: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var quietLeft: Double = 60
    @Published private(set) var presses = 0
    fileprivate var tap: CFMachPort?
    private var windows: [NSWindow] = []
    private var ticker: Timer?
    private var lastPress = Date()
    var lockTouchBar: (Bool) -> Void = { _ in }

    func start() {
        guard !active else { return }
        guard AXIsProcessTrusted() else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            return
        }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: cleanTapCallback, userInfo: me) else { return }
        tap = port
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        active = true
        presses = 0
        lastPress = Date()
        quietLeft = 60
        for screen in NSScreen.screens {
            let w = CleanWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.contentView = NSHostingView(rootView: CleanView(model: self))
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        lockTouchBar(true)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.quietLeft = max(0, 60 - Date().timeIntervalSince(self.lastPress))
                if self.quietLeft <= 0 { self.stop() }
            }
        }
    }

    func stop() {
        guard active else { return }
        active = false
        ticker?.invalidate(); ticker = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
        lockTouchBar(false)
        let ws = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; ws.forEach { $0.animator().alphaValue = 0 } }, completionHandler: { ws.forEach { $0.orderOut(nil) } })
    }

    fileprivate func pressed() {
        lastPress = Date()
        presses += 1
    }

    var tapState: String { tap.map { CGEvent.tapIsEnabled(tap: $0) ? "on" : "off" } ?? "none" }

    fileprivate func reenable() { if let tap, active { CGEvent.tapEnable(tap: tap, enable: true) } }
}

private func cleanTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let me = Unmanaged<KeyboardClean>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { MainActor.assumeIsolated { me.reenable() }; return Unmanaged.passUnretained(event) }
    if type == .keyDown || type.rawValue == 14 { MainActor.assumeIsolated { me.pressed() } }
    return nil
}
