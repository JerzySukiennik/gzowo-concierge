// Gzowo Concierge for macOS - state and actions of the notch dock: hover state, quick chat with streamed reply, approvals, next event.
import AppKit
import SwiftUI

@MainActor
final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var closedSize = CGSize(width: 190, height: 24)
    @Published var openSize = CGSize(width: 580, height: 196)
    @Published var text = ""
    @Published var reply = ""
    @Published var steps: [String] = []
    @Published var streaming = false
    @Published var errorText = ""
    @Published var nextEvent = ""
    @Published var online = false
    @Published var busy = false
    @Published var pending: [PendingItem] = []
    @Published var avatarShape = "circle"
    @Published var avatarColor = "auto"
    @Published var look = CGSize.zero
    @Published var blink = false
    @Published var dictation: DictationPhase = .idle
    @Published var level: Float = 0
    var wantsFocus = false
    var replyThread = ""

    var activeThread: () -> String = { "main" }
    var onFinished: (String) -> Void = { _ in }
    var openApp: () -> Void = {}
    var openLive: () -> Void = {}
    var openSettings: () -> Void = {}
    var quitApp: () -> Void = {}
    var requestPoll: () -> Void = {}
    var expandRequest: () -> Void = {}
    private var streamTask: Task<Void, Never>?
    private var lastToday: Date = .distantPast

    static let maxHeight: CGFloat = 660
    static let replyMax: CGFloat = 440

    var replyShown: String { errorText.isEmpty ? (reply.isEmpty ? "…" : reply) : errorText }

    var replyHeight: CGFloat {
        let w = openSize.width - 52
        let text = errorText.isEmpty ? NotchText.plain(replyShown) : errorText
        let font = NSFont.systemFont(ofSize: errorText.isEmpty ? 13 : 12.5)
        let r = (text as NSString).boundingRect(with: CGSize(width: w, height: 6000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let lines = max(1, Int((r.height / (font.ascender - font.descender + font.leading)).rounded()))
        return min(ceil(r.height) + CGFloat(lines) * 2 + 10, Self.replyMax)
    }

    var openHeight: CGFloat {
        var h: CGFloat = 156
        if !pending.isEmpty { h += CGFloat(min(pending.count, 2)) * 74 }
        if !reply.isEmpty || streaming || !errorText.isEmpty { h = 134 + replyHeight + (steps.isEmpty ? 0 : 28) + CGFloat(min(pending.count, 2)) * 74 }
        else if !nextEvent.isEmpty { h += 24 }
        return min(h, Self.maxHeight)
    }

    var pillExtra: CGFloat {
        switch dictation {
        case .idle: return 0
        case .listening, .thinking, .done: return 80
        case .failed: return 170
        }
    }

    var sticky: Bool { !text.isEmpty || streaming || !pending.isEmpty }

    var status: String {
        if !online { return "Host nie odpowiada" }
        if !pending.isEmpty { return "Czeka na Twoją zgodę" }
        if streaming || busy { return "Pracuję…" }
        return "Gotowy"
    }

    func apply(_ s: HostState) {
        online = s.online; busy = s.busy
        if pending != s.pendingItems { pending = s.pendingItems }
        if avatarShape != s.avatarShape { avatarShape = s.avatarShape }
        if avatarColor != s.avatarColor { avatarColor = s.avatarColor }
    }

    func clearReply() { reply = ""; steps = []; errorText = "" }

    func send() {
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !streaming else { return }
        text = ""
        reply = ""; steps = []; errorText = ""
        streaming = true
        let thread = activeThread()
        replyThread = thread
        streamTask = Task { [weak self] in
            await self?.stream(msg, thread: thread)
        }
    }

    private func stream(_ msg: String, thread: String) async {
        defer { Task { @MainActor in self.streaming = false; self.requestPoll(); self.onFinished(thread) } }
        guard let url = URL(string: Config.base + "/api/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": msg, "thread": thread])
        req.timeoutInterval = 120
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            for try await line in bytes.lines {
                guard let data = line.data(using: .utf8), let e = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                switch e["type"] as? String {
                case "text":
                    let t = e["text"] as? String ?? ""
                    reply = reply.isEmpty ? t : reply + "\n" + t
                case "tool":
                    let s = e["summary"] as? String ?? ""
                    if e["status"] as? String == "running" { if !steps.contains(s) { steps.append(s) } }
                    else if e["status"] as? String == "failed" { errorText = (e["error"] as? String) ?? "Narzędzie nie zadziałało." }
                case "error":
                    errorText = e["message"] as? String ?? "Błąd."
                case "approval":
                    requestPoll()
                default: break
                }
            }
        } catch {
            errorText = "Brak połączenia z hostem."
        }
    }

    func approve(_ item: PendingItem, _ yes: Bool) {
        pending.removeAll { $0.id == item.id }
        Task {
            _ = await Api.post("/api/approvals/\(item.id)", ["approve": yes])
            requestPoll()
        }
    }

    func refreshToday(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastToday) > 120 else { return }
        lastToday = Date()
        Task {
            guard let j = await Api.send("GET", "/api/today"), let cal = j["calendar"] as? [[String: Any]] else { return }
            let now = Date()
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            let upcoming = cal.compactMap { e -> (String, Date, Bool)? in
                guard let t = e["title"] as? String, let s = e["start"] as? String, let d = iso.date(from: s) else { return nil }
                let end = (e["end"] as? String).flatMap { iso.date(from: $0) } ?? d
                return end > now ? (t, d, e["allDay"] as? Bool ?? false) : nil
            }.sorted { $0.1 < $1.1 }
            if let n = upcoming.first {
                let f = DateFormatter(); f.locale = Locale(identifier: "pl_PL")
                f.dateFormat = Calendar.current.isDateInToday(n.1) ? "HH:mm" : "EEE HH:mm"
                nextEvent = n.2 ? "\(n.0), cały dzień" : "\(n.0), \(f.string(from: n.1))"
            } else { nextEvent = "" }
        }
    }
}
