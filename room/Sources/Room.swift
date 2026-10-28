// Concierge Pokój - the room assistant: wake word, one spoken exchange per wake (longer only after a question), host or offline mode, ringing alarms.
import AppKit
import Foundation

final class Room: LiveEvents {
    enum Phase { case asleep, connecting, listening, thinking, speaking }

    private let config: RoomConfig
    private let audio = AudioIO()
    private let face = FaceScreen()
    private let tools: RoomTools
    private var wake: WakeWord?
    private let audioQ = DispatchQueue(label: "room.audio")
    private let streamLock = NSLock()
    private var streamTarget: LiveLink?
    private var ring: [Data] = []
    private var utteranceChunks = 0
    private var testFeeding = false
    private var recording = Data()
    private var recordLeft = 0
    private var recordPath = ""

    private var phase: Phase = .asleep
    private var link: LiveLink?
    private var sessionAudio: [Data] = []
    private var turnDone = false
    private var assistantText = ""
    private var userText = ""
    private var userAt = Date.distantPast
    private var heardUser = false
    private var toolsInFlight = 0
    private var answered = false
    private var hostWorking = false
    private var sessionStart = Date()
    private var lastHeard = Date()
    private var firstAudioLogged = false
    private var silenceTimer: Timer?
    private var ringing: RoomAlarm?
    private var ringStop: Timer?
    private var hostBase: String?
    private var lastPrompt: String?
    private var promptFetched = Date.distantPast
    private var offlineTurns: [[String: String]] = []
    private let promptFile = RoomConfig.dir.appendingPathComponent("prompt.txt")
    private let turnsFile = RoomConfig.dir.appendingPathComponent("offline-turns.json")

    init() {
        config = RoomConfig.load()
        tools = RoomTools(config: config)
        lastPrompt = try? String(contentsOf: promptFile, encoding: .utf8)
        if let d = try? Data(contentsOf: turnsFile), let t = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] { offlineTurns = t }
    }

    func start() {
        tools.lastUserSpeech = { [weak self] in (self?.userText ?? "", self?.userAt ?? .distantPast) }
        tools.alarms.onFire = { [weak self] a in self?.ring(a) }
        face.onUserInput = { [weak self] in self?.userTapped() }
        face.start()
        if let res = Bundle.main.resourceURL {
            wake = WakeWord(modelPath: res.appendingPathComponent("model").path, wordsPath: res.appendingPathComponent("wake-words.txt").path)
        }
        wake?.onReject = { [weak self] _ in self?.saveClip("reject") }
        wake?.onWake = { [weak self] follows in
            guard let self else { return }
            self.saveClip("wake")
            if self.recordLeft > 0 { NSLog("room: wake heard during recording"); return }
            let n = min(self.utteranceChunks, 80)
            let utterance = follows ? Array(self.ring.suffix(n)) : []
            DispatchQueue.main.async { self.woke(commandFollows: follows, utterance: utterance) }
        }
        audio.onChunk = { [weak self] chunk, level in
            guard let self else { return }
            self.audioQ.async { if !self.testFeeding { self.feed(chunk) } }
            DispatchQueue.main.async { if self.phase == .listening { self.face.model.level = CGFloat(level) } }
        }
        audio.onSpeechIdle = { [weak self] in self?.speechFinished() }
        Task { _ = await tools.osa("set volume input volume 85") }
        do { try audio.start() } catch { NSLog("room: audio failed: \(error.localizedDescription)") }
        probeHost()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.probeHost() }
        let launched = Date()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let alarmSoon = self.tools.alarms.items.contains { $0.fire.timeIntervalSinceNow < 900 }
            guard c.hour == 3, (c.minute ?? 0) >= 30, Date().timeIntervalSince(launched) > 6 * 3600, self.phase == .asleep, self.ringing == nil, !alarmSoon else { return }
            NSLog("room: nightly restart")
            exit(0)
        }
        NSLog("room: ready, wake=\(wake != nil), hosts=\(config.hosts.count), keys=\(config.geminiKeys.count)")
    }

    private func feed(_ chunk: Data) {
        if recordLeft > 0 {
            recording.append(chunk)
            recordLeft -= 1
            if recordLeft == 0 { Self.writeWav(recording, to: recordPath); NSLog("room: recorded \(recordPath)"); recording = Data() }
        }
        ring.append(chunk)
        if ring.count > 80 { ring.removeFirst(ring.count - 80) }
        utteranceChunks += 1
        if wake?.accept(chunk) == true { utteranceChunks = 0 }
        streamLock.lock(); let target = streamTarget; streamLock.unlock()
        target?.sendAudio(chunk)
    }

    private func saveClip(_ kind: String) {
        let dir = RoomConfig.dir.appendingPathComponent("wakes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let pcm = ring.suffix(max(15, min(utteranceChunks + 3, 60))).reduce(Data(), +)
        Self.writeWav(pcm, to: dir.appendingPathComponent("\(f.string(from: Date()))-\(kind).wav").path)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for old in files.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(60) { try? FileManager.default.removeItem(at: old) }
    }

    private func setStreaming(_ on: Bool) {
        streamLock.lock(); streamTarget = on ? link : nil; streamLock.unlock()
    }

    private func woke(commandFollows: Bool, utterance: [Data]) {
        NSLog("room: wake (command follows: \(commandFollows), replay \(utterance.count) chunks)")
        let afterAlarm = ringing?.kind == "alarm"
        if ringing != nil { stopRinging() }
        switch phase {
        case .speaking:
            audio.stopSpeech()
            setPhase(.listening)
            setStreaming(true)
            armSilence(8)
            return
        case .asleep:
            break
        default:
            return
        }
        if !commandFollows { audio.effect("wake", volume: 0.6) }
        face.wake(.listening)
        beginSession(replay: utterance, afterAlarm: afterAlarm)
    }

    private func beginSession(replay: [Data], afterAlarm: Bool = false) {
        alarmContext = afterAlarm
        setPhase(.connecting)
        turnDone = false
        toolsInFlight = 0
        answered = false
        hostWorking = false
        firstAudioLogged = false
        sessionStart = Date()
        lastHeard = Date()
        assistantText = ""
        heardUser = !replay.isEmpty
        sessionAudio = replay
        if let base = hostBase, let l = HostLink(base: base, token: config.token, tools: tools.declarations(offline: false), rules: rulesNow(offline: false), events: self) {
            link = l
        } else {
            link = direct()
        }
        NSLog("room: session via \(link?.viaHost == true ? "host" : "gemini direct")")
        guard let link else { endSession(); return }
        for chunk in replay { link.sendAudio(chunk) }
        setStreaming(true)
        armSilence(heardUser ? 12 : 8)
    }

    private func direct() -> LiveLink? {
        guard !config.geminiKeys.isEmpty else { return nil }
        let base = lastPrompt ?? "Jesteś Concierge, osobisty asystent Jurka (14 lat, Warszawa). Mów po polsku, krótko i rzeczowo, jak kumpel-inżynier."
        return DirectLink(keys: config.geminiKeys, model: config.model, voice: config.voice, prompt: "\(base)\n\n\(rulesNow(offline: true))", tools: tools.declarations(offline: true), events: self)
    }

    private var alarmContext = false

    private func rulesNow(offline: Bool) -> String {
        let now = Date()
        let f = DateFormatter(); f.locale = Locale(identifier: "pl_PL"); f.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        return "\(RoomTools.rules)\n\(offline ? RoomTools.offlineRules + "\n" : "")\(alarmContext ? RoomTools.alarmRules + "\n" : "")Now: \(f.string(from: now)) (Europe/Warsaw); said aloud: \"\(Self.spokenTime(now))\". For a later time of day call room_timers_list or count from this."
    }

    static func spokenTime(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0
        let hours = ["zero", "pierwsza", "druga", "trzecia", "czwarta", "piąta", "szósta", "siódma", "ósma", "dziewiąta", "dziesiąta", "jedenasta", "dwunasta", "trzynasta", "czternasta", "piętnasta", "szesnasta", "siedemnasta", "osiemnasta", "dziewiętnasta", "dwudziesta", "dwudziesta pierwsza", "dwudziesta druga", "dwudziesta trzecia"]
        let ones = ["zero", "jeden", "dwa", "trzy", "cztery", "pięć", "sześć", "siedem", "osiem", "dziewięć", "dziesięć", "jedenaście", "dwanaście", "trzynaście", "czternaście", "piętnaście", "szesnaście", "siedemnaście", "osiemnaście", "dziewiętnaście"]
        let tens = ["", "", "dwadzieścia", "trzydzieści", "czterdzieści", "pięćdziesiąt"]
        let minutes: String
        if m == 0 { minutes = "" }
        else if m < 10 { minutes = " zero " + ones[m] }
        else if m < 20 { minutes = " " + ones[m] }
        else { minutes = " " + tens[m / 10] + (m % 10 == 0 ? "" : " " + ones[m % 10]) }
        return hours[h] + minutes
    }

    private func setPhase(_ p: Phase) {
        phase = p
        switch p {
        case .listening, .connecting: face.model.phase = .listening
        case .thinking: face.model.phase = .thinking
        case .speaking: face.model.phase = .speaking
        case .asleep: break
        }
    }

    private func armSilence(_ seconds: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.phase == .listening || self.phase == .connecting else { return }
            self.endSession()
        }
    }

    private func endSession() {
        NSLog("room: session end")
        silenceTimer?.invalidate()
        setStreaming(false)
        link?.close()
        link = nil
        audio.stopSpeech()
        phase = .asleep
        flushOffline()
        if ringing == nil { face.sleep() }
    }

    func liveReady() {
        NSLog("room: ready +%.1fs", Date().timeIntervalSince(sessionStart))
        if phase == .connecting { setPhase(.listening) }
    }

    func liveAudio(_ pcm24: Data) {
        guard phase != .asleep else { return }
        if phase != .speaking {
            setStreaming(false)
            silenceTimer?.invalidate()
            setPhase(.speaking)
        }
        if !hostWorking { answered = true }
        if !firstAudioLogged { firstAudioLogged = true; NSLog("room: first audio +%.1fs after last speech", Date().timeIntervalSince(lastHeard)) }
        audio.playSpeech(pcm24)
        face.model.level = min(1, CGFloat(pcm24.count) / 9600)
    }

    func liveTranscript(user: Bool, text: String) {
        if user {
            userText = text
            userAt = Date()
            lastHeard = Date()
            firstAudioLogged = false
            heardUser = true
            if phase == .listening { armSilence(10) }
        } else {
            assistantText = text
        }
    }

    func liveTurnComplete() {
        NSLog("room: turn - user: \(userText) | assistant: \(assistantText)")
        turnDone = true
        if link?.viaHost == false { recordOffline() }
        if !audio.speaking { speechFinished() }
    }

    func liveInterrupted() {
        audio.stopSpeech()
        if phase != .asleep { setPhase(.listening); setStreaming(true); armSilence(8) }
    }

    func liveThinking() {
        guard phase != .asleep else { return }
        NSLog("room: thinking +%.1fs", Date().timeIntervalSince(lastHeard))
        hostWorking = true
        answered = false
        firstAudioLogged = false
        guard phase != .speaking else { return }
        setPhase(.thinking)
        setStreaming(false)
        waitForAnswer(25)
    }

    func liveSpeaking() {
        hostWorking = false
    }

    private func waitForAnswer(_ seconds: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, !self.answered, self.phase != .asleep, self.phase != .speaking else { return }
            NSLog("room: no answer, closing")
            self.endSession()
        }
    }

    func liveTool(id: String, name: String, args: [String: Any]) {
        setPhase(.thinking)
        setStreaming(false)
        silenceTimer?.invalidate()
        toolsInFlight += 1
        answered = false
        Task { @MainActor in
            let result = await tools.handle(name, args)
            NSLog("room: tool \(name) \(args) -> \(result)")
            link?.sendToolResult(id: id, name: name, response: result)
            toolsInFlight = max(0, toolsInFlight - 1)
            waitForAnswer(15)
        }
    }

    func liveFailed(_ message: String, beforeReady: Bool) {
        NSLog("room: live failed: \(message)")
        if beforeReady, link?.viaHost == true {
            hostBase = nil
            link = direct()
            if let link { for chunk in sessionAudio { link.sendAudio(chunk) }; setStreaming(true); return }
        }
        endSession()
    }

    private func speechFinished() {
        guard turnDone, phase != .asleep, toolsInFlight == 0 else { return }
        turnDone = false
        if hostWorking || !answered {
            if phase != .thinking { setPhase(.thinking); setStreaming(false) }
            waitForAnswer(hostWorking ? 25 : 15)
            return
        }
        assistantText = ""
        answered = false
        setPhase(.listening)
        setStreaming(true)
        armSilence(9)
    }

    private func recordOffline() {
        let u = userText.trimmingCharacters(in: .whitespacesAndNewlines), a = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty { offlineTurns.append(["role": "user", "text": u]) }
        if !a.isEmpty { offlineTurns.append(["role": "model", "text": a]) }
        userText = ""
        saveOffline()
    }

    private func saveOffline() {
        if let d = try? JSONSerialization.data(withJSONObject: offlineTurns) { try? d.write(to: turnsFile) }
    }

    private func flushOffline() {
        guard !offlineTurns.isEmpty, let base = hostBase, let url = URL(string: base + "/api/room/turns") else { return }
        let batch = offlineTurns
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["turns": batch])
        URLSession.shared.dataTask(with: req) { [weak self] _, res, _ in
            guard (res as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.offlineTurns.removeFirst(min(batch.count, self.offlineTurns.count))
                self.saveOffline()
            }
        }.resume()
    }

    private func probeHost() {
        guard !config.token.isEmpty, !config.hosts.isEmpty else { hostBase = nil; return }
        let group = DispatchGroup()
        var found: String?
        let lock = NSLock()
        for base in config.hosts {
            guard let url = URL(string: base + "/api/health") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 2.5)
            req.setValue("Bearer \(config.token)", forHTTPHeaderField: "authorization")
            group.enter()
            URLSession.shared.dataTask(with: req) { _, res, _ in
                if (res as? HTTPURLResponse)?.statusCode == 200 { lock.lock(); if found == nil { found = base }; lock.unlock() }
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let wasOffline = self.hostBase == nil
            self.hostBase = found
            if found != nil && (wasOffline || self.lastPrompt == nil || Date().timeIntervalSince(self.promptFetched) > 3600) { self.fetchPrompt() }
            if found != nil && self.phase == .asleep { self.flushOffline() }
        }
    }

    private func fetchPrompt() {
        guard let base = hostBase, let url = URL(string: base + "/api/room/prompt") else { return }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "authorization")
        URLSession.shared.dataTask(with: req) { [weak self] data, res, _ in
            guard (res as? HTTPURLResponse)?.statusCode == 200, let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let p = j["prompt"] as? String else { return }
            DispatchQueue.main.async {
                self?.lastPrompt = p
                self?.promptFetched = Date()
                if let file = self?.promptFile { try? p.write(to: file, atomically: true, encoding: .utf8) }
            }
        }.resume()
    }

    private func ring(_ a: RoomAlarm) {
        if phase != .asleep { endSession() }
        ringing = a
        NSLog("room: ringing \(a.kind) \(a.label)")
        let label = a.label.isEmpty ? (a.kind == "alarm" ? "Pobudka" : "Timer") : a.label
        face.wake(.ringing)
        face.model.caption = label
        if a.kind == "alarm" {
            audio.effect("alarm", loops: -1)
            ringStop?.invalidate()
            ringStop = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in self?.stopRinging() }
        } else {
            audio.effect("timer", loops: 3)
            ringStop?.invalidate()
            ringStop = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in self?.stopRinging() }
        }
    }

    private func stopRinging() {
        ringStop?.invalidate()
        audio.stopEffect("alarm")
        audio.stopEffect("timer")
        ringing = nil
        if phase == .asleep { face.sleep() } else { face.model.caption = "" }
    }

    private func userTapped() {
        if ringing != nil { stopRinging() }
        else if phase != .asleep { endSession() }
        else { face.stepAside(minutes: 10) }
    }

    func snapshot(_ path: String) { face.snapshot(to: path) }

    func record(_ spec: String) {
        let parts = spec.split(separator: ":")
        guard let path = parts.first, let secs = parts.count > 1 ? Int(parts[1]) : 30 else { return }
        audioQ.async {
            self.recording = Data()
            self.recordPath = String(path)
            self.recordLeft = max(1, min(secs, 120)) * 10
        }
    }

    private static func writeWav(_ pcm: Data, to path: String) {
        var h = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 2)) }
        h.append(Data("RIFF".utf8)); u32(UInt32(36 + pcm.count)); h.append(Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        h.append(Data("data".utf8)); u32(UInt32(pcm.count))
        try? (h + pcm).write(to: URL(fileURLWithPath: path))
    }

    func playTest(_ path: String) {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)), let r = d.range(of: Data("data".utf8)), r.upperBound + 4 < d.count else { return }
        let pcm = d.subdata(in: (r.upperBound + 4)..<d.count) + Data(count: 3200 * 120)
        audioQ.async { self.testFeeding = true }
        DispatchQueue.global().async {
            defer { self.audioQ.async { self.testFeeding = false } }
            var i = 0
            while i < pcm.count {
                let chunk = pcm.subdata(in: i..<min(i + 3200, pcm.count))
                self.audioQ.async { self.feed(chunk) }
                i += 3200
                usleep(100_000)
            }
        }
    }
}
