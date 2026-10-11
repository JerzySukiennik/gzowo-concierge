// Gzowo Concierge for macOS - system-wide dictation: hold Control+Option, speak, release; audio streams to the host (Gemini Live), clean text is inserted where you were typing.
import AppKit
import ApplicationServices
import AVFoundation
import Accelerate

enum DictationPhase: Equatable {
    case idle, listening, thinking, done
    case failed(String)
}

@MainActor
final class DictationController {
    private let hud: NotchModel
    private var flagsMonitors: [Any] = []
    private var keyMonitors: [Any] = []
    private var engagedAt: Date?
    private var armed = false
    private var armingTask: Task<Void, Never>?
    private var session: DictationSession?
    private var resetTask: Task<Void, Never>?

    private static let required: NSEvent.ModifierFlags = [.control, .option]
    private static let agentFlags: NSEvent.ModifierFlags = [.control, .option, .shift]
    private var agentMode = false
    private var sessionAgent = false
    var onAgentTask: (String) -> Void = { _ in }
    private static let tracked: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    private static let armingDelay: TimeInterval = 0.18
    private static let minimumHold: TimeInterval = 0.4

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "dictationEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dictationEnabled"); if newValue { askAccessibility() } else { cancel() } }
    }

    init(hud: NotchModel) { self.hud = hud }

    func start() {
        let observe: @Sendable (NSEvent) -> Void = { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.flagsChanged(flags) }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged], handler: observe) { flagsMonitors.append(g) }
        let local: @Sendable (NSEvent) -> NSEvent? = { event in observe(event); return event }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged], handler: local) { flagsMonitors.append(l) }
        if enabled { askAccessibility() }
    }

    func askAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard enabled else { return }
        let current = flags.intersection(Self.tracked)
        if engagedAt == nil {
            if current == Self.required { agentMode = false; engage() }
            else if current == Self.agentFlags { agentMode = true; engage() }
            return
        }
        let need = agentMode ? Self.agentFlags : Self.required
        if current == need { return }
        if !agentMode && !armed && current == Self.agentFlags { agentMode = true; return }
        finish(cancelled: current.isSuperset(of: need))
    }

    private func engage() {
        engagedAt = Date()
        armed = false
        installKeyGuard()
        armingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.armingDelay))
            guard !Task.isCancelled else { return }
            self?.arm()
        }
    }

    private func arm() {
        guard engagedAt != nil, !armed else { return }
        armed = true
        sessionAgent = agentMode
        begin()
    }

    private func finish(cancelled: Bool) {
        guard let engagedAt else { return }
        let held = Date().timeIntervalSince(engagedAt)
        let wasArmed = armed
        self.engagedAt = nil
        armed = false
        armingTask?.cancel()
        armingTask = nil
        removeKeyGuard()
        guard wasArmed else { return }
        if cancelled || held < Self.minimumHold { cancel() } else { release() }
    }

    private func installKeyGuard() {
        let cancel: @Sendable (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.finish(cancelled: true) } }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: cancel) { keyMonitors.append(g) }
        let local: @Sendable (NSEvent) -> NSEvent? = { event in cancel(event); return event }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: local) { keyMonitors.append(l) }
    }

    private func removeKeyGuard() {
        for m in keyMonitors { NSEvent.removeMonitor(m) }
        keyMonitors = []
    }

    private func set(_ phase: DictationPhase) {
        resetTask?.cancel()
        hud.dictation = phase
        if case .done = phase { schedule(after: 1.0) }
        if case .failed = phase { schedule(after: 3.2) }
    }

    private func schedule(after s: Double) {
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(s))
            guard !Task.isCancelled else { return }
            self?.hud.dictation = .idle
        }
    }

    private func begin() {
        guard session == nil else { return }
        guard AXIsProcessTrusted() else {
            set(.failed("Włącz Dostępność dla Concierge"))
            askAccessibility()
            NSSound(named: "Basso")?.play()
            return
        }
        let s = DictationSession(
            onLevel: { [weak self] level in Task { @MainActor in self?.hud.level = level } },
            onResult: { [weak self] result in Task { @MainActor in self?.handle(result) } }
        )
        session = s
        set(.listening)
        NSSound(named: "Tink")?.play()
        Task {
            do { try await s.start() }
            catch {
                await MainActor.run {
                    if self.session === s { self.session = nil }
                    self.set(.failed(error.localizedDescription))
                    NSSound(named: "Basso")?.play()
                }
            }
        }
    }

    private func release() {
        guard let s = session else { return }
        set(.thinking)
        s.end()
    }

    private func cancel() {
        guard let s = session else { return }
        session = nil
        s.cancel()
        hud.dictation = .idle
    }

    private func handle(_ result: DictationSession.Result) {
        session = nil
        switch result {
        case .text(let text):
            guard !text.isEmpty else { set(.failed("Nic nie usłyszałem")); return }
            if sessionAgent {
                hud.dictation = .idle
                onAgentTask(text)
                return
            }
            Task {
                let ok = await TextInserter.insert(text)
                set(ok ? .done : .failed("Nie udało się wstawić tekstu"))
                NSSound(named: ok ? "Pop" : "Basso")?.play()
            }
        case .failure(let message):
            set(.failed(message))
            NSSound(named: "Basso")?.play()
        }
    }
}

final class DictationSession: @unchecked Sendable {
    enum Result { case text(String), failure(String) }

    private let onLevel: @Sendable (Float) -> Void
    private let onResult: @Sendable (Result) -> Void
    private var engine: AVAudioEngine?
    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()
    private var finished = false
    private var tapBusy = 0.0
    private static let maxSeconds = 240.0
    private var sentFrames = 0

    init(onLevel: @escaping @Sendable (Float) -> Void, onResult: @escaping @Sendable (Result) -> Void) {
        self.onLevel = onLevel
        self.onResult = onResult
    }

    private static var socketURL: URL {
        var s = Config.base.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://")
        if s.hasSuffix("/") { s.removeLast() }
        return URL(string: s + "/dictate")!
    }

    func start() async throws {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .audio)
        default: granted = false
        }
        guard granted else { throw DictationError.message("Brak zgody na mikrofon (Ustawienia systemu, Prywatność)") }

        let t = URLSession.shared.webSocketTask(with: Self.socketURL)
        task = t
        t.resume()
        receive(t)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw DictationError.message("Mikrofon jest niedostępny")
        }
        converter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
        let ratio = 16000 / inFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(inFormat.sampleRate / 10), format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
            var consumed = false
            var err: NSError?
            let status = converter.convert(to: out, error: &err) { _, outStatus in
                if consumed { outStatus.pointee = .noDataNow; return nil }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, out.frameLength > 0, let ch = out.int16ChannelData?[0] else { return }
            let count = Int(out.frameLength)
            var level: Float = 0
            var f = [Float](repeating: 0, count: count)
            vDSP_vflt16(ch, 1, &f, 1, vDSP_Length(count))
            vDSP_rmsqv(f, 1, &level, vDSP_Length(count))
            self.onLevel(min(1, level / 32768 * 6))
            self.send(Data(bytes: ch, count: count * 2))
            self.lock.lock(); self.sentFrames += count; let over = Double(self.sentFrames) / 16000 > Self.maxSeconds; self.lock.unlock()
            if over { self.end() }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func send(_ data: Data) {
        lock.lock(); let t = task, done = finished; lock.unlock()
        guard !done else { return }
        t?.send(.data(data)) { _ in }
    }

    private func stopAudio() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    func end() {
        stopAudio()
        lock.lock(); let t = task; lock.unlock()
        t?.send(.string("{\"type\":\"end\"}")) { _ in }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) { [weak self] in self?.complete(.failure("Host nie odpowiedział na czas")) }
    }

    func cancel() {
        stopAudio()
        lock.lock(); let t = task; finished = true; lock.unlock()
        t?.send(.string("{\"type\":\"cancel\"}")) { _ in t?.cancel(with: .normalClosure, reason: nil) }
    }

    private func complete(_ r: Result) {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true
        let t = task
        lock.unlock()
        t?.cancel(with: .normalClosure, reason: nil)
        onResult(r)
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.complete(.failure("Brak połączenia z hostem"))
            case .success(let message):
                if case .string(let s) = message, let d = s.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], j["type"] as? String == "result" {
                    if let e = j["error"] as? String { self.complete(.failure(e)) } else { self.complete(.text((j["text"] as? String) ?? "")) }
                    return
                }
                self.receive(t)
            }
        }
    }
}

enum DictationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m } else { return nil } }
}

@MainActor
enum TextInserter {
    static func insert(_ text: String) async -> Bool {
        guard AXIsProcessTrusted(), !text.isEmpty else { return false }
        if insertViaAX(text) { return true }
        return await paste(text)
    }

    private static func insertViaAX(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let el = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.5)
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    static func paste(_ text: String) async -> Bool {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let x = item.data(forType: t) { d[t] = x } }
            return d
        }
        let count = pb.changeCount
        pb.clearContents()
        guard pb.setString(text, forType: .string) else { return false }
        guard let src = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(12))
        up.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(420))
        if pb.changeCount == count + 1 {
            pb.clearContents()
            if !saved.isEmpty {
                pb.writeObjects(saved.map { d in
                    let item = NSPasteboardItem()
                    for (t, x) in d { item.setData(x, forType: t) }
                    return item
                })
            }
        }
        return true
    }
}
