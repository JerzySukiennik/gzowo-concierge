// Gzowo Concierge for macOS - standing link to the host (/mac): whole-screen screenshots on request, showing a thread or a link, and a once-a-minute sample of the app in use for the day summary.
import AppKit
import ScreenCaptureKit

@MainActor
final class MacLink {
    var onShow: (String, URL?) -> Void = { _, _ in }
    private var task: URLSessionWebSocketTask?
    private var sampler: Timer?
    private var retry: Timer?

    private static var socketURL: URL {
        let s = Config.base.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: s + "/mac")!
    }

    func start() {
        connect()
        sampler = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    private func connect() {
        retry?.invalidate()
        let t = URLSession.shared.webSocketTask(with: Self.socketURL)
        t.maximumMessageSize = 16 << 20
        task = t
        t.resume()
        receive(t)
    }

    private func reconnectLater() {
        task = nil
        retry?.invalidate()
        retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.connect() }
        }
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, t === self.task else { return }
                switch result {
                case .failure:
                    self.reconnectLater()
                case .success(.string(let s)):
                    self.handle(s)
                    self.receive(t)
                case .success:
                    self.receive(t)
                }
            }
        }
    }

    private func send(_ obj: [String: Any]) {
        guard let task, let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
        task.send(.string(s)) { _ in }
    }

    private func handle(_ s: String) {
        guard let m = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any], let type = m["type"] as? String, let id = m["id"] as? String else { return }
        switch type {
        case "screenshot":
            Task { @MainActor in
                let front = Self.frontWindow()
                do {
                    let data = try await Self.capture()
                    self.send(["id": id, "data": data, "app": front.app, "title": front.title])
                } catch {
                    self.send(["id": id, "error": "Nie udało się zrobić zrzutu ekranu: \(error.localizedDescription)"])
                }
            }
        case "show":
            let thread = m["thread"] as? String ?? "main"
            let url = (m["url"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            onShow(thread, url)
            send(["id": id, "ok": true])
        default:
            send(["id": id, "error": "unknown request"])
        }
    }

    private func sample() {
        let idle = CGEventType(rawValue: ~0).map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) } ?? 0
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        guard idle < 120, !locked else { return }
        let front = Self.frontWindow()
        guard !front.app.isEmpty else { return }
        send(["type": "activity", "app": front.app, "title": front.title])
    }

    private static func frontWindow() -> (app: String, title: String) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return ("", "") }
        let pid = app.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let title = list.first { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }?[kCGWindowName as String] as? String ?? ""
        return (app.localizedName ?? "", title)
    }

    private static func capture() async throws -> String {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let sid = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == sid }) ?? content.displays.first else { throw CocoaError(.fileNoSuchFile) }
        let mine = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        let scale = min(2, 1600 / CGFloat(display.width))
        cfg.width = Int(CGFloat(display.width) * scale)
        cfg.height = Int(CGFloat(display.height) * scale)
        cfg.showsCursor = true
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        guard let jpeg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else { throw CocoaError(.fileWriteUnknown) }
        return jpeg.base64EncodedString()
    }
}
