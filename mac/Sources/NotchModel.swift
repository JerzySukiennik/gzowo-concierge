// Gzowo Concierge for macOS - state of the island: live activities (levels, media, timers, next event, agent, dictation) with priorities and sizes, quick chat with streamed reply, approvals.
import AppKit
import SwiftUI

struct AgentRun: Identifiable, Equatable {
    enum State { case running, ok, failed }
    let id = UUID()
    var task: String
    var state: State = .running
    var summary = ""
}

struct UpcomingEvent: Equatable {
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
}

enum Activity: Hashable {
    case idle, dictation, agent, hud, alarm, peek, timer, event, media
}

@MainActor
final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var hovering = false
    @Published var closedSize = CGSize(width: 190, height: 24)
    @Published var openSize = CGSize(width: 600, height: 196)
    @Published var expandedHeight: CGFloat = 214
    @Published var text = ""
    @Published var reply = ""
    @Published var steps: [String] = []
    @Published var streaming = false
    @Published var errorText = ""
    @Published var upcoming: [UpcomingEvent] = []
    @Published var online = false
    @Published var busy = false
    @Published var pending: [PendingItem] = []
    @Published var avatarShape = "circle"
    @Published var avatarColor = "auto"
    @Published var look = CGSize.zero
    @Published var blink = false
    @Published var dictation: DictationPhase = .idle
    @Published var level: Float = 0
    @Published var agent = AgentState()
    @Published var agentMode = false
    @Published var agentHistory: [AgentRun] = []
    @Published var hud: LevelEvent?
    @Published var media = NowPlaying()
    @Published var mediaArt: NSImage?
    @Published var mediaIcon: NSImage?
    @Published var peek = false
    @Published var timers: [TimerInfo] = []
    @Published var alarm: TimerInfo?
    @Published var clock = Date()

    var startAgent: (String) -> Void = { _ in }
    var stopAgent: () -> Void = {}
    var answerAgent: (Bool) -> Void = { _ in }
    var collapseRequest: () -> Void = {}
    var expandRequest: () -> Void = {}
    var focusRequest: () -> Void = {}
    var mediaCommand: (String) -> Void = { _ in }
    var mediaSeek: (Double) -> Void = { _ in }
    var wantsFocus = false
    var replyThread = ""

    var activeThread: () -> String = { "main" }
    var onFinished: (String) -> Void = { _ in }
    var openApp: () -> Void = {}
    var openLive: () -> Void = {}
    var openSettings: () -> Void = {}
    var quitApp: () -> Void = {}
    var requestPoll: () -> Void = {}
    private var streamTask: Task<Void, Never>?
    private var lastToday: Date = .distantPast
    private var hudWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var alarmWork: DispatchWorkItem?
    private var timerWork: DispatchWorkItem?
    private var ticker: Timer?
    private var rung = Set<String>()
    private var sound: NSSound?
    private var started = Date()

    static let maxHeight: CGFloat = 680
    static let replyMax: CGFloat = 420

    var replyShown: String { errorText.isEmpty ? (reply.isEmpty ? "…" : reply) : errorText }

    var replyHeight: CGFloat {
        let w = openSize.width - 60
        let text = errorText.isEmpty ? NotchText.plain(replyShown) : errorText
        let font = NSFont.systemFont(ofSize: errorText.isEmpty ? 13 : 12.5)
        let r = (text as NSString).boundingRect(with: CGSize(width: w, height: 6000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let lines = max(1, Int((r.height / (font.ascender - font.descender + font.leading)).rounded()))
        return min(ceil(r.height) + CGFloat(lines) * 2 + 10, Self.replyMax)
    }

    var hasReply: Bool { !reply.isEmpty || streaming || !errorText.isEmpty }

    // MARK: activities

    var activeTimer: TimerInfo? {
        timers.filter { $0.done == nil && $0.ends > clock }.min { $0.ends < $1.ends }
    }

    var soonEvent: UpcomingEvent? {
        upcoming.first { !$0.allDay && $0.start > clock.addingTimeInterval(-120) && $0.start.timeIntervalSince(clock) <= 30 * 60 }
    }

    var nextEvent: UpcomingEvent? { upcoming.first { $0.end > clock } }

    var nextEventLine: String {
        guard let n = nextEvent else { return "" }
        if n.allDay { return "\(n.title), cały dzień" }
        let f = DateFormatter(); f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = Calendar.current.isDateInToday(n.start) ? "HH:mm" : "EEE HH:mm"
        return n.start <= clock ? "\(n.title), teraz" : "\(n.title), \(f.string(from: n.start))"
    }

    var attention: Bool { !pending.isEmpty || busy || streaming || !online }

    var activities: [Activity] {
        var a: [Activity] = []
        if hud != nil { a.append(.hud) }
        if dictation != .idle { a.append(.dictation) }
        if agent.visible { a.append(.agent) }
        if alarm != nil { a.append(.alarm) }
        if peek && !media.isEmpty { a.append(.peek) }
        if attention { a.append(.idle) }
        if activeTimer != nil { a.append(.timer) }
        if soonEvent != nil { a.append(.event) }
        if !media.isEmpty && media.playing { a.append(.media) }
        a.append(.idle)
        return a
    }

    var primary: Activity { activities.first ?? .idle }

    var secondary: Activity? {
        let p = primary
        guard ![.peek, .alarm].contains(p) else { return nil }
        return activities.dropFirst().first { [.timer, .event, .media].contains($0) && $0 != p }
    }

    var agentSize: CGSize { CGSize(width: agent.ask != nil ? 380 : 330, height: agent.ask != nil ? 84 : (agent.finished ? 34 : 38)) }

    var pillExtra: CGFloat {
        switch dictation {
        case .idle: return 0
        case .listening, .thinking, .done: return 80
        case .failed: return 170
        }
    }

    func compactSize(_ a: Activity) -> CGSize {
        let w = closedSize.width, h = closedSize.height
        let grow: CGFloat = hovering ? 1 : 0
        switch a {
        case .idle: return CGSize(width: w + 18 * grow, height: h + 5 * grow)
        case .dictation: return CGSize(width: w + pillExtra, height: h)
        case .agent: return agentSize
        case .hud: return CGSize(width: max(w + 130, 320), height: h + 12)
        case .alarm: return CGSize(width: max(w + 200, 390), height: h + 34)
        case .peek: return CGSize(width: max(w + 200, 390), height: h + 34)
        case .timer, .media: return CGSize(width: w + 70 + 14 * grow, height: h + 4 * grow)
        case .event: return CGSize(width: max(w + 150, 340) + 14 * grow, height: h + 4 * grow)
        }
    }

    var bubbleSize: CGSize { CGSize(width: closedSize.height + 14, height: closedSize.height) }

    var shapeSize: CGSize {
        expanded ? CGSize(width: openSize.width, height: min(expandedHeight, Self.maxHeight)) : compactSize(primary)
    }

    var radii: (top: CGFloat, bottom: CGFloat) {
        if expanded { return (12, 30) }
        switch primary {
        case .hud: return (8, 18)
        case .alarm, .peek: return (10, 24)
        case .agent: return (8, agent.ask != nil ? 22 : 16)
        default: return (6, hovering ? 12 : 9)
        }
    }

    var transient: Bool { hud != nil || alarm != nil || agent.ask != nil }

    // MARK: live inputs

    func showLevel(_ e: LevelEvent) {
        hud = e
        hudWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: w)
    }

    func setMedia(_ n: NowPlaying, art: NSImage?, icon: NSImage?) {
        if media != n { media = n }
        if mediaArt !== art { mediaArt = art }
        if mediaIcon !== icon { mediaIcon = icon }
        if n.isEmpty { peek = false }
    }

    func peekMedia(for seconds: Double = 2.6) {
        guard !media.isEmpty, !expanded, Date().timeIntervalSince(started) > 3 else { return }
        peek = true
        peekWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.peek = false }
        peekWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    func setTimers(_ list: [TimerInfo]) {
        if timers != list { timers = list }
        let now = Date()
        for t in list where !rung.contains(t.id) {
            let end = t.done ?? t.ends
            if end <= now {
                rung.insert(t.id)
                if now.timeIntervalSince(end) < 20 && now.timeIntervalSince(started) > 2 { ring(t) }
            }
        }
        if let a = alarm, !list.contains(where: { $0.id == a.id }) { stopAlarm() }
        scheduleTimerCheck()
        retick()
    }

    private func scheduleTimerCheck() {
        timerWork?.cancel()
        guard let next = timers.filter({ $0.done == nil && !rung.contains($0.id) }).map(\.ends).min() else { return }
        let w = DispatchWorkItem { [weak self] in guard let self else { return }; self.clock = Date(); self.setTimers(self.timers) }
        timerWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, next.timeIntervalSinceNow), execute: w)
    }

    private func ring(_ t: TimerInfo) {
        alarm = t
        sound?.stop()
        sound = ProcessInfo.processInfo.environment["CONCIERGE_TB_TEST"] == nil ? NSSound(named: "Glass") : nil
        chime(t.id, left: 4)
        alarmWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.stopAlarm() }
        alarmWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 14, execute: w)
    }

    private func chime(_ id: String, left: Int) {
        guard alarm?.id == id, left > 0 else { return }
        sound?.stop(); sound?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in self?.chime(id, left: left - 1) }
    }

    func stopAlarm() {
        guard let a = alarm else { return }
        alarm = nil
        sound?.stop()
        Task { _ = await Api.post("/api/timers/\(a.id)/dismiss"); requestPoll() }
    }

    func timerAction(_ t: TimerInfo, _ action: String, seconds: Int = 60) {
        if action == "add", alarm?.id == t.id { alarm = nil; sound?.stop(); Task { _ = await Api.post("/api/timers", ["seconds": seconds, "label": t.label]); requestPoll() }; return }
        if action == "cancel" { timers.removeAll { $0.id == t.id } }
        Task { _ = await Api.post("/api/timers/\(t.id)/\(action)", ["seconds": seconds]); requestPoll() }
    }

    private var tickEvery: TimeInterval = 0

    private var wantedTick: TimeInterval {
        if activeTimer != nil || upcoming.contains(where: { !$0.allDay && abs($0.start.timeIntervalSince(clock)) < 150 }) { return 1 }
        if upcoming.contains(where: { !$0.allDay && $0.start.timeIntervalSince(clock) > -120 && $0.start.timeIntervalSince(clock) < 31 * 60 }) { return 10 }
        return 30
    }

    func retick() {
        clock = Date()
        let want = wantedTick
        guard want != tickEvery || ticker == nil else { return }
        tickEvery = want
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: want, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.clock = Date()
                if self.wantedTick != self.tickEvery { self.retick() }
            }
        }
    }

    func beginAgentRun(_ task: String) { agentHistory.insert(AgentRun(task: task), at: 0) }

    func endAgentRun(ok: Bool, summary: String) {
        guard let i = agentHistory.firstIndex(where: { $0.state == .running }) else { return }
        agentHistory[i].state = ok ? .ok : .failed
        agentHistory[i].summary = summary
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
        if s.online { setTimers(s.timers) }
    }

    func clearReply() { reply = ""; steps = []; errorText = "" }

    func send() {
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !streaming else { return }
        if agentMode {
            text = ""
            agentMode = false
            collapseRequest()
            startAgent(msg)
            return
        }
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
                    if s.hasPrefix("Ustawiam timer") || s.hasPrefix("Wyłączam timer") { requestPoll() }
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
            let list = cal.compactMap { e -> UpcomingEvent? in
                guard let t = e["title"] as? String, let s = e["start"] as? String, let d = iso.date(from: s) else { return nil }
                let end = (e["end"] as? String).flatMap { iso.date(from: $0) } ?? d
                return end > now ? UpcomingEvent(title: t, start: d, end: end, allDay: e["allDay"] as? Bool ?? false) : nil
            }.sorted { $0.start < $1.start }
            if list != upcoming { upcoming = list }
            retick()
        }
    }
}
