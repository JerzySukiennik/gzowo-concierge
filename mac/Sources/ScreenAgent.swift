// Gzowo Concierge for macOS - screen agent: sends screenshots to the host, executes the clicks, typing and keys it returns, shows a pet cursor and live steps in the island.
import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI

struct AgentState: Equatable {
    var active = false
    var step = 0
    var total = 0
    var narration = ""
    var ask: String?
    var finished = false
    var ok = true
    var summary = ""
    var visible: Bool { active || finished }
}

@MainActor
final class PetOverlay {
    private let panel: NSPanel
    private let host: NSHostingView<PetView>
    private let state = PetState()
    var windowNumber: Int { panel.windowNumber }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 40), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        host = NSHostingView(rootView: PetView(state: state))
        host.sizingOptions = []
        panel.contentView = host
    }

    func show(at point: CGPoint, label: String) {
        state.label = label
        move(to: point)
        panel.orderFrontRegardless()
    }

    func move(to p: CGPoint) {
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        panel.setFrameOrigin(NSPoint(x: p.x + 14, y: screenH - p.y - 44))
    }

    func set(label: String) { state.label = label }
    func hide() { panel.orderOut(nil) }
}

@MainActor
final class PetState: ObservableObject {
    @Published var label = ""
}

struct PetView: View {
    @ObservedObject var state: PetState

    var body: some View {
        HStack(spacing: 7) {
            NotchBot(kind: "circle", color: "white", size: 20, busy: false, alert: false, look: .zero, blink: false)
            if !state.label.isEmpty {
                Text(state.label).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.black.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        .fixedSize()
        .frame(width: 240, height: 40, alignment: .topLeading)
    }
}

@MainActor
final class ScreenAgentController {
    private let hud: NotchModel
    private let pet = PetOverlay()
    private var socket: URLSessionWebSocketTask?
    private var keyMonitors: [Any] = []
    private var running = false
    private var injecting = false
    private var resetTask: Task<Void, Never>?
    private var cursor = CGPoint.zero
    var hiddenWindowNumbers: () -> [Int] = { [] }

    private var displayID = CGMainDisplayID()
    private var origin = CGPoint.zero
    private var screenSize = CGSize(width: 1440, height: 900)

    private func pickScreen() {
        let mouse = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return }
        let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? primary
        displayID = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        origin = CGPoint(x: s.frame.minX, y: primary.frame.height - s.frame.maxY)
        screenSize = s.frame.size
    }

    init(hud: NotchModel) { self.hud = hud }

    private static var socketURL: URL {
        var s = Config.base.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
        if s.hasSuffix("/") { s.removeLast() }
        return URL(string: s + "/agent")!
    }

    func run(task: String) {
        guard !running else { return }
        resetTask?.cancel()
        guard AXIsProcessTrusted() else {
            hud.agent = AgentState(finished: true, ok: false, summary: "Włącz Dostępność dla Concierge")
            scheduleReset(5)
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            hud.agent = AgentState(finished: true, ok: false, summary: "Włącz Nagrywanie ekranu dla Concierge i uruchom ponownie")
            scheduleReset(6)
            return
        }
        running = true
        pickScreen()
        hud.beginAgentRun(task)
        hud.agent = AgentState(active: true, narration: "Patrzę na ekran")
        installKeyGuard()
        Task { await loop(task) }
    }

    func stop() {
        guard running else { return }
        socket?.send(.string("{\"type\":\"stop\"}")) { _ in }
        finish(ok: false, summary: "Zatrzymano")
    }

    func answer(_ yes: Bool) {
        hud.agent.ask = nil
        socket?.send(.string("{\"type\":\"answer\",\"yes\":\(yes)}")) { _ in }
    }

    private func loop(_ task: String) async {
        let ws = URLSession.shared.webSocketTask(with: Self.socketURL)
        ws.maximumMessageSize = 16 << 20
        socket = ws
        ws.resume()
        do {
            let first = try await capture()
            try await send(["type": "start", "task": task, "image": first])
            while running {
                let message = try await ws.receive()
                guard case .string(let text) = message, let d = text.data(using: .utf8),
                      let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let type = j["type"] as? String else { continue }
                switch type {
                case "status": hud.agent.narration = j["text"] as? String ?? ""
                case "plan": hud.agent.total = (j["steps"] as? [Any])?.count ?? 0
                case "ask":
                    hud.agent.step = j["step"] as? Int ?? hud.agent.step
                    hud.agent.ask = j["question"] as? String ?? "Kontynuować?"
                case "urlcheck": try await send(["type": "url", "url": Self.activeBrowserURL() ?? ""])
                case "action": await execute(j)
                case "done": finish(ok: j["ok"] as? Bool ?? true, summary: j["summary"] as? String ?? ""); return
                default: break
                }
            }
        } catch {
            if running { finish(ok: false, summary: "Brak połączenia z hostem") }
        }
    }

    private func send(_ obj: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: obj)
        try await socket?.send(.string(String(data: data, encoding: .utf8) ?? "{}"))
    }

    private func execute(_ j: [String: Any]) async {
        guard let name = j["name"] as? String else { return }
        let args = j["args"] as? [String: Any] ?? [:]
        hud.agent.step = j["step"] as? Int ?? hud.agent.step
        hud.agent.total = j["steps"] as? Int ?? hud.agent.total
        let narration = j["narration"] as? String ?? ""
        hud.agent.narration = narration
        var ok = true
        var error: String?
        switch name {
        case "click", "double_click", "triple_click", "right_click":
            await moveCursor(toGrid: args, label: narration)
            click(name == "right_click" ? .right : .left, count: name == "triple_click" ? 3 : (name == "double_click" ? 2 : 1))
        case "type_text":
            pet.set(label: narration)
            let ok2 = await TextInserter.paste(args["text"] as? String ?? "")
            if !ok2 { ok = false; error = "Nie udało się wpisać tekstu." }
            if args["press_enter"] as? Bool == true { await pressKeys("Enter") }
        case "type_secret":
            pet.set(label: narration)
            Self.typeUnicode(args["value"] as? String ?? "")
        case "press_key":
            pet.set(label: narration)
            if !(await pressKeys(args["keys"] as? String ?? "")) { ok = false; error = "Nieznany klawisz." }
        case "scroll":
            await moveCursor(toGrid: args, label: narration)
            scroll(args["direction"] as? String ?? "down", amount: args["amount"] as? Int ?? 5)
        case "open_app":
            pet.set(label: narration)
            ok = openApp(args["name"] as? String ?? "")
            if !ok { error = "Nie znalazłem tej aplikacji." }
            try? await Task.sleep(for: .milliseconds(900))
        case "wait":
            try? await Task.sleep(for: .seconds(min(5, max(1, args["seconds"] as? Int ?? 2))))
        default:
            ok = false
            error = "Nieznana akcja."
        }
        try? await Task.sleep(for: .milliseconds(name == "open_app" ? 700 : 650))
        guard running else { return }
        do {
            let image = try await capture()
            var reply: [String: Any] = ["type": "observation", "ok": ok, "image": image]
            if let error { reply["error"] = error }
            try await send(reply)
        } catch {
            finish(ok: false, summary: "Nie udało się zrobić zrzutu ekranu")
        }
    }

    private func finish(ok: Bool, summary: String) {
        guard running else { return }
        running = false
        removeKeyGuard()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        pet.hide()
        hud.endAgentRun(ok: ok, summary: summary)
        hud.agent = AgentState(finished: true, ok: ok, summary: summary)
        NSSound(named: ok ? "Pop" : "Basso")?.play()
        scheduleReset(ok ? 7 : 6)
    }

    private func scheduleReset(_ seconds: Double) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hud.agent = AgentState()
        }
    }

    private func installKeyGuard() {
        let handler: @Sendable (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { if self?.injecting == false { self?.stop() } }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: handler) { keyMonitors.append(g) }
        let local: @Sendable (NSEvent) -> NSEvent? = { event in handler(event); return event }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: local) { keyMonitors.append(l) }
    }

    private func removeKeyGuard() {
        for m in keyMonitors { NSEvent.removeMonitor(m) }
        keyMonitors = []
    }

    private func capture() async throws -> String {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { throw CocoaError(.fileNoSuchFile) }
        let ids = Set(hiddenWindowNumbers() + [pet.windowNumber])
        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { ids.contains(Int($0.windowID)) })
        let cfg = SCStreamConfiguration()
        let scale = min(1, 1440 / CGFloat(display.width))
        cfg.width = Int(CGFloat(display.width) * scale)
        cfg.height = Int(CGFloat(display.height) * scale)
        cfg.showsCursor = true
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { throw CocoaError(.fileWriteUnknown) }
        return jpeg.base64EncodedString()
    }

    private func point(fromGrid args: [String: Any]) -> CGPoint {
        let x = (args["x"] as? Double) ?? Double(args["x"] as? Int ?? 500)
        let y = (args["y"] as? Double) ?? Double(args["y"] as? Int ?? 500)
        return CGPoint(x: origin.x + min(max(x, 0), 1000) / 1000 * screenSize.width, y: origin.y + min(max(y, 0), 1000) / 1000 * screenSize.height)
    }

    private func moveCursor(toGrid args: [String: Any], label: String) async {
        let target = point(fromGrid: args)
        let start = CGEvent(source: nil)?.location ?? target
        if pet.windowNumber > 0 { pet.show(at: start, label: label) }
        let steps = 26
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let p = CGPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            pet.move(to: p)
            try? await Task.sleep(for: .milliseconds(14))
        }
        cursor = target
    }

    private func click(_ button: CGMouseButton, count: Int) {
        let down: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let up: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        for n in 1...count {
            guard let d = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: cursor, mouseButton: button),
                  let u = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: cursor, mouseButton: button) else { continue }
            d.setIntegerValueField(.mouseEventClickState, value: Int64(n))
            u.setIntegerValueField(.mouseEventClickState, value: Int64(n))
            d.post(tap: .cghidEventTap)
            usleep(30_000)
            u.post(tap: .cghidEventTap)
            usleep(60_000)
        }
    }

    private func scroll(_ direction: String, amount: Int) {
        let n = Int32(min(max(amount, 1), 20))
        var dy: Int32 = 0, dx: Int32 = 0
        switch direction {
        case "up": dy = n
        case "down": dy = -n
        case "left": dx = n
        default: dx = -n
        }
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy * 3, wheel2: dx * 3, wheel3: 0)?.post(tap: .cghidEventTap)
    }

    static func typeUnicode(_ text: String) {
        for ch in text {
            var u = Array(String(ch).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
                e.post(tap: .cghidEventTap)
                usleep(6_000)
            }
        }
    }

    static func activeBrowserURL() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return nil }
        let script: String
        switch id {
        case "com.apple.Safari": script = "tell application \"Safari\" to return URL of current tab of front window"
        case "com.google.Chrome": script = "tell application \"Google Chrome\" to return URL of active tab of front window"
        case "com.brave.Browser": script = "tell application \"Brave Browser\" to return URL of active tab of front window"
        case "com.microsoft.edgemac": script = "tell application \"Microsoft Edge\" to return URL of active tab of front window"
        case "company.thebrowser.Browser": script = "tell application \"Arc\" to return URL of active tab of front window"
        default: return nil
        }
        var err: NSDictionary?
        return NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue
    }

    private func openApp(_ name: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", name]
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, ";": 41, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "enter": 36, "return": 36, "tab": 48, "space": 49, "backspace": 51, "delete": 51, "escape": 53, "esc": 53,
        "left": 123, "arrowleft": 123, "right": 124, "arrowright": 124, "down": 125, "arrowdown": 125, "up": 126, "arrowup": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    ]

    private func pressKeys(_ combo: String) async -> Bool {
        let parts = combo.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, let code = Self.keyCodes[keyName] else { return false }
        var flags: CGEventFlags = []
        for m in parts.dropLast() {
            switch m {
            case "cmd", "command", "meta", "super": flags.insert(.maskCommand)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: return false
            }
        }
        injecting = true
        defer { Task { try? await Task.sleep(for: .milliseconds(300)); injecting = false } }
        guard let src = CGEventSource(stateID: .privateState),
              let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
              let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) else { return false }
        d.flags = flags
        u.flags = flags
        d.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(20))
        u.post(tap: .cghidEventTap)
        return true
    }
}
