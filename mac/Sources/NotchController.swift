// Gzowo Concierge for macOS - owns the island panel: placement above the menu bar, hover (grow, then open), click, fullscreen hiding with transient activities on top, show/hide setting.
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
    private var todayTimer: Timer?
    private let margin: CGFloat = 40
    private let dwell: Double = 0.25
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
        model.focusRequest = { [weak self] in self?.expand(focus: true) }
        model.collapseRequest = { [weak self] in self?.collapse() }
        model.openApp = { [weak self] in self?.collapse(); self?.onOpenApp() }
        model.openLive = { [weak self] in self?.collapse(); self?.onOpenLive() }

        model.$pending.removeDuplicates().sink { [weak self] list in
            guard let self else { return }
            if !list.isEmpty && !self.model.expanded { self.expand(focus: false) }
        }.store(in: &cancellables)
        Publishers.CombineLatest3(model.$hud, model.$alarm, model.$agent).sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshFullscreen() }
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.layoutForScreen(); self?.resizePanel() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.refreshToday(force: true) }
        }
        todayTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in self?.model.refreshToday(force: true) } }
        installMonitors()
        startFullscreenWatch()
        layoutForScreen()
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.model.refreshToday(force: true) }
        if ProcessInfo.processInfo.environment["CONCIERGE_TB_TEST"] != nil { installTestHooks() }
    }

    private func installTestHooks() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.island-test"), object: nil, queue: .main) { [weak self] n in
            let cmd = (n.object as? String) ?? ""
            Task { @MainActor in self?.runTest(cmd) }
        }
    }

    private func runTest(_ cmd: String) {
        let parts = cmd.split(separator: ":").map(String.init)
        let arg = parts.count > 1 ? Float(parts[1]) ?? 0.5 : 0.5
        switch parts.first ?? "" {
        case "expand": expand(focus: false)
        case "focus": expand(focus: true)
        case "collapse": collapse()
        case "hover": model.hovering = true
        case "unhover": model.hovering = false
        case "volume": model.showLevel(LevelEvent(kind: .volume, value: arg))
        case "mute": model.showLevel(LevelEvent(kind: .volume, value: arg, muted: true))
        case "airpods": model.showLevel(LevelEvent(kind: .volume, value: arg, device: "AirPods Jurka"))
        case "brightness": model.showLevel(LevelEvent(kind: .brightness, value: arg))
        case "keyboard": model.showLevel(LevelEvent(kind: .keyboard, value: arg))
        case "peek": model.peekMedia(for: 8)
        case "event": model.upcoming = [UpcomingEvent(title: "Fizyka", start: Date().addingTimeInterval(Double(arg) * 60), end: Date().addingTimeInterval(Double(arg) * 60 + 2700), allDay: false)]; model.retick()
        case "noevent": model.upcoming = []; model.retick()
        case "reply": model.reply = "Jutro w Warszawie **8°C**, rano mgła, po południu przejaśnienia. Wiatr słaby z zachodu, deszcz mało prawdopodobny. Weź lekką kurtkę na rano."
        case "noreply": model.clearReply()
        case "busy": model.streaming = arg > 0.5
        case "fakemedia":
            var n = NowPlaying(); n.title = "The Mentalist, Season 3"; n.app = "Prime Video"; n.playing = arg > 0.5; n.duration = 2549; n.elapsed = 1788; n.stamp = Date(); n.artId = "x"
            model.setMedia(n, art: NSImage(contentsOfFile: "/System/Library/Desktop Pictures/.thumbnails/Big Sur Coastline.heic") ?? NSImage(named: NSImage.applicationIconName), icon: nil)
        case "nomedia": model.setMedia(NowPlaying(), art: nil, icon: nil)
        default: break
        }
    }

    var onOpenApp: () -> Void = {}
    var onOpenLive: () -> Void = {}

    private var targetScreen: NSScreen?
    private var screen: NSScreen {
        if let t = targetScreen, NSScreen.screens.contains(t) { return t }
        return NSScreen.screens.first ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func follow(_ s: NSScreen) {
        targetScreen = s
        layoutForScreen()
        panel.ignoresMouseEvents = true
        panel.setFrame(panelFrame, display: true)
        refreshFullscreen(probe: true)
    }

    private func layoutForScreen() {
        let s = screen
        var size = CGSize(width: 190, height: max(22, NSStatusBar.system.thickness))
        if s.safeAreaInsets.top > 0 {
            let l = s.auxiliaryTopLeftArea?.width ?? 0, r = s.auxiliaryTopRightArea?.width ?? 0
            size = CGSize(width: max(150, s.frame.width - l - r + 6), height: s.safeAreaInsets.top)
        }
        if model.closedSize != size { model.closedSize = size }
    }

    private var panelFrame: NSRect {
        let s = screen.frame
        let w = model.openSize.width + margin * 2, h = NotchModel.maxHeight + margin
        return NSRect(x: s.midX - w / 2, y: s.maxY - h, width: w, height: h)
    }

    private var shapeRect: NSRect {
        let s = screen.frame, size = model.shapeSize
        return NSRect(x: s.midX - size.width / 2, y: s.maxY - size.height, width: size.width, height: size.height)
    }

    private var pillHit: NSRect {
        let s = screen.frame
        let c = model.compactSize(model.primary)
        var r = NSRect(x: s.midX - c.width / 2 - 8, y: s.maxY - c.height - 5, width: c.width + 16, height: c.height + 5)
        if model.secondary != nil { r.size.width += model.bubbleSize.width + 7 }
        return r
    }

    private func resizePanel() {
        guard enabled, let panel, panel.frame != panelFrame else { return }
        panel.setFrame(panelFrame, display: false)
    }

    private var hiddenForFullscreen = false

    private func screenIsFullscreen() -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let f = screen.frame
        let target = CGRect(x: f.minX, y: primary.frame.height - f.maxY, width: f.width, height: f.height)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0, let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
            let r = CGRect(x: b["X"] as? Double ?? -1, y: b["Y"] as? Double ?? -1, width: b["Width"] as? Double ?? 0, height: b["Height"] as? Double ?? 0)
            if abs(r.minX - target.minX) < 1.5 && abs(r.minY - target.minY) < 1.5 && abs(r.width - target.width) < 1.5 && abs(r.height - target.height) < 1.5 { return true }
        }
        return false
    }

    private var fullscreen = false

    func refreshFullscreen(probe: Bool = false) {
        guard enabled, let panel else { return }
        if probe || !fullscreen { fullscreen = screenIsFullscreen() }
        let hide = fullscreen && !model.transient
        guard hide != hiddenForFullscreen else { return }
        hiddenForFullscreen = hide
        if hide { collapse(); panel.orderOut(nil) } else { panel.setFrame(panelFrame, display: true); panel.orderFrontRegardless() }
    }

    private func startFullscreenWatch() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshFullscreen(probe: true); try? await Task.sleep(for: .milliseconds(700)); self?.refreshFullscreen(probe: true) }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshFullscreen(probe: true) } }
    }

    private func apply() {
        guard let panel else { return }
        if enabled {
            panel.setFrame(panelFrame, display: true)
            panel.ignoresMouseEvents = true
            if !hiddenForFullscreen { panel.orderFrontRegardless() }
        } else {
            collapse()
            panel.orderOut(nil)
        }
    }

    func expand(focus: Bool = false) {
        collapseWork?.cancel(); collapseWork = nil
        expandWork?.cancel(); expandWork = nil
        guard enabled, !hiddenForFullscreen else { return }
        if model.expanded {
            if focus && !panel.isKeyWindow { model.wantsFocus = true; panel.makeKey() }
            return
        }
        if !model.streaming && !model.reply.isEmpty && model.replyThread != model.activeThread() { model.clearReply() }
        if model.agent.finished && !model.agent.active { model.agent = AgentState() }
        if model.alarm != nil { model.stopAlarm() }
        model.wantsFocus = focus
        model.hovering = false
        model.peek = false
        model.expanded = true
        model.refreshToday()
        model.retick()
        panel.ignoresMouseEvents = false
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
        collapseWork?.cancel(); collapseWork = nil
        expandWork?.cancel(); expandWork = nil
        guard model.expanded else { return }
        blinkTimer?.invalidate(); blinkTimer = nil
        model.expanded = false
        model.hovering = false
        panel.resignKey()
    }

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in Task { @MainActor in self?.mouseMoved() } }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] e in Task { @MainActor in self?.mouseMoved() }; return e }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let p = NSEvent.mouseLocation
                if !self.model.expanded {
                    if !self.model.agent.active && self.pillHit.contains(p) { self.model.alarm != nil ? self.model.stopAlarm() : self.expand(focus: true) }
                    return
                }
                if !self.shapeRect.insetBy(dx: -6, dy: -6).contains(p), self.model.pending.isEmpty { self.collapse() }
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

    var windowNumber: Int { panel.windowNumber }

    private func mouseMoved() {
        guard enabled, !hiddenForFullscreen else { return }
        let p = NSEvent.mouseLocation
        if !model.expanded && !model.agent.visible && model.dictation == .idle && !model.transient,
           let s = NSScreen.screens.first(where: { $0.frame.contains(p) }), s != screen { follow(s) }
        let over = model.expanded ? shapeRect.insetBy(dx: -4, dy: -4).contains(p) : pillHit.contains(p)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        if !model.expanded {
            let canOpen = !model.agent.active && model.dictation == .idle && model.alarm == nil
            if over && canOpen {
                if !model.hovering { model.hovering = true }
                if expandWork == nil {
                    let w = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.expandWork = nil
                        if self.pillHit.contains(NSEvent.mouseLocation) { self.expand(focus: false) }
                    }
                    expandWork = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + dwell, execute: w)
                }
            } else {
                expandWork?.cancel(); expandWork = nil
                if model.hovering { model.hovering = false }
            }
        } else {
            let r = shapeRect
            model.look = CGSize(width: max(-1, min(1, (p.x - (r.minX + 50)) / 300)), height: max(-1, min(1, ((r.maxY - 30) - p.y) / 200)))
            if r.insetBy(dx: -16, dy: -16).contains(p) { collapseWork?.cancel(); collapseWork = nil }
            else if !model.sticky && !panel.isKeyWindow, collapseWork == nil {
                let w = DispatchWorkItem { [weak self] in self?.collapseWork = nil; self?.collapse() }
                collapseWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: w)
            }
        }
    }
}
