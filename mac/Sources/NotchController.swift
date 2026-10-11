// Gzowo Concierge for macOS - owns the notch panel: placement above the menu bar, hover and click behaviour, tight panel sizing, show/hide setting.
import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NotchController {
    let model = NotchModel()
    private var panel: NotchPanel!
    private var hosting: NSHostingView<NotchView>!
    private var cancellables = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var blinkTimer: Timer?
    private let margin: CGFloat = 36
    private let key = "notchEnabled"

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key); apply() }
    }

    func start() {
        let p = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        hosting = NSHostingView(rootView: NotchView(m: model))
        hosting.sizingOptions = []
        p.contentView = hosting
        panel = p

        model.expandRequest = { [weak self] in self?.expand() }
        model.openApp = { [weak self] in self?.collapse(); self?.onOpenApp() }
        model.openLive = { [weak self] in self?.collapse(); self?.onOpenLive() }

        model.$pending.removeDuplicates().sink { [weak self] list in
            guard let self else { return }
            if !list.isEmpty && !self.model.expanded { self.expand(focus: false) }
            self.resizePanel()
        }.store(in: &cancellables)
        Publishers.CombineLatest3(model.$reply, model.$streaming, model.$errorText).sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizePanel() }
        }.store(in: &cancellables)
        model.$nextEvent.sink { [weak self] _ in DispatchQueue.main.async { self?.resizePanel() } }.store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.layoutForScreen(); self?.resizePanel() }
        }
        installMonitors()
        layoutForScreen()
        apply()
    }

    var onOpenApp: () -> Void = {}
    var onOpenLive: () -> Void = {}

    private var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main ?? NSScreen.screens[0] }

    private func layoutForScreen() {
        let s = screen
        var size = CGSize(width: 190, height: 24)
        if s.safeAreaInsets.top > 0 {
            let l = s.auxiliaryTopLeftArea?.width ?? 0, r = s.auxiliaryTopRightArea?.width ?? 0
            size = CGSize(width: max(150, s.frame.width - l - r + 6), height: s.safeAreaInsets.top)
        }
        model.closedSize = size
    }

    private var shapeSize: CGSize {
        model.expanded ? CGSize(width: model.openSize.width, height: model.openHeight) : model.closedSize
    }

    private var panelFrame: NSRect {
        let s = screen.frame
        let w = model.openSize.width + margin * 2, h = NotchModel.maxHeight + margin
        return NSRect(x: s.midX - w / 2, y: s.maxY - h, width: w, height: h)
    }

    private var shapeRect: NSRect {
        let s = screen.frame, size = shapeSize
        return NSRect(x: s.midX - size.width / 2, y: s.maxY - size.height, width: size.width, height: size.height)
    }

    private func resizePanel() {
        guard enabled, let panel, panel.frame != panelFrame else { return }
        panel.setFrame(panelFrame, display: false)
    }

    private func apply() {
        guard let panel else { return }
        if enabled {
            panel.setFrame(panelFrame, display: true)
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
        } else {
            collapse()
            panel.orderOut(nil)
        }
    }

    func expand(focus: Bool = true) {
        collapseWork?.cancel(); expandWork?.cancel()
        guard enabled, !model.expanded else { return }
        if !model.streaming && !model.reply.isEmpty && model.replyThread != model.activeThread() { model.clearReply() }
        model.wantsFocus = focus
        model.expanded = true
        model.refreshToday()
        if focus { panel.makeKey() }
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 4.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.model.blink = true
                try? await Task.sleep(nanoseconds: 130_000_000)
                self?.model.blink = false
            }
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    func collapse() {
        collapseWork?.cancel(); expandWork?.cancel()
        guard model.expanded else { return }
        blinkTimer?.invalidate(); blinkTimer = nil
        model.expanded = false
        panel.resignKey()
    }

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in Task { @MainActor in self?.mouseMoved() } }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] e in Task { @MainActor in self?.mouseMoved() }; return e }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.model.expanded { if self.pillHit.contains(NSEvent.mouseLocation) { self.onOpenApp() }; return }
                if !self.shapeRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) { self.model.pending.isEmpty ? self.collapse() : () }
            }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] e in
            Task { @MainActor in
                guard let self, self.model.expanded, self.model.pending.isEmpty else { return }
                if !self.shapeRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) { self.collapse() }
            }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] e in
            if e.keyCode == 53, let self, self.model.expanded, self.panel.isKeyWindow { Task { @MainActor in self.collapse() }; return nil }
            return e
        }) { monitors.append(m) }
    }

    private var pillHit: NSRect {
        let s = screen.frame, c = model.closedSize
        return NSRect(x: s.midX - c.width / 2 - 10, y: s.maxY - c.height - 4, width: c.width + 20, height: c.height + 4)
    }

    private func mouseMoved() {
        guard enabled else { return }
        let p = NSEvent.mouseLocation
        let over = model.expanded ? shapeRect.insetBy(dx: -4, dy: -4).contains(p) : pillHit.contains(p)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        if !model.expanded {
            if pillHit.contains(p) {
                if expandWork == nil {
                    let w = DispatchWorkItem { [weak self] in self?.expandWork = nil; self?.expand(focus: false) }
                    expandWork = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: w)
                }
            } else { expandWork?.cancel(); expandWork = nil }
        } else {
            let r = shapeRect
            model.look = CGSize(width: max(-1, min(1, (p.x - (r.minX + 44)) / 300)), height: max(-1, min(1, ((r.maxY - 32) - p.y) / 200)))
            if r.insetBy(dx: -16, dy: -16).contains(p) { collapseWork?.cancel(); collapseWork = nil }
            else if !model.sticky, collapseWork == nil {
                let w = DispatchWorkItem { [weak self] in self?.collapseWork = nil; self?.collapse() }
                collapseWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
            }
        }
    }
}
