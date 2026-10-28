// Concierge Pokój - Gemini Live links: through the Concierge host on the home network (all of its tools and history) or straight to Gemini when the main Mac is off.
import Foundation

protocol LiveEvents: AnyObject {
    func liveReady()
    func liveAudio(_ pcm24: Data)
    func liveTranscript(user: Bool, text: String)
    func liveTurnComplete()
    func liveInterrupted()
    func liveTool(id: String, name: String, args: [String: Any])
    func liveThinking()
    func liveSpeaking()
    func liveFailed(_ message: String, beforeReady: Bool)
}

protocol LiveLink: AnyObject {
    var viaHost: Bool { get }
    func sendAudio(_ pcm16: Data)
    func sendToolResult(id: String, name: String, response: [String: Any])
    func close()
}

private func jsonString(_ o: Any) -> String? {
    guard let d = try? JSONSerialization.data(withJSONObject: o) else { return nil }
    return String(data: d, encoding: .utf8)
}

final class HostLink: LiveLink {
    let viaHost = true
    private weak var events: LiveEvents?
    private let task: URLSessionWebSocketTask
    private var ready = false
    private var closed = false

    init?(base: String, token: String, tools: [[String: Any]], rules: String, events: LiveEvents) {
        var comps = URLComponents(string: base.replacingOccurrences(of: "http", with: "ws", options: .anchored))
        comps?.path = "/live"
        comps?.queryItems = [URLQueryItem(name: "client", value: "room"), URLQueryItem(name: "t", value: token)]
        guard let url = comps?.url else { return nil }
        self.events = events
        task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 8 << 20
        task.resume()
        if let hello = jsonString(["type": "hello", "tools": tools, "rules": rules]) { task.send(.string(hello)) { _ in } }
        receive()
    }

    private func receive() {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, !self.closed else { return }
                switch result {
                case .failure(let e):
                    self.fail("Host: \(e.localizedDescription)")
                case .success(.data(let d)):
                    self.events?.liveAudio(d)
                    self.receive()
                case .success(.string(let s)):
                    self.handle(s)
                    self.receive()
                @unknown default:
                    self.receive()
                }
            }
        }
    }

    private func handle(_ s: String) {
        guard let m = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any], let type = m["type"] as? String else { return }
        switch type {
        case "ready": ready = true; events?.liveReady()
        case "transcript": if let t = m["text"] as? String { events?.liveTranscript(user: (m["role"] as? String) == "user", text: t) }
        case "turn-complete": events?.liveTurnComplete()
        case "interrupted": events?.liveInterrupted()
        case "room-tool":
            if let id = m["id"] as? String, let name = m["name"] as? String { events?.liveTool(id: id, name: name, args: m["args"] as? [String: Any] ?? [:]) }
        case "state":
            if (m["state"] as? String) == "thinking" { events?.liveThinking() }
            if (m["state"] as? String) == "speaking" { events?.liveSpeaking() }
        case "tool", "approval":
            if (m["status"] as? String ?? "running") == "running" { events?.liveThinking() }
        case "error": fail(m["message"] as? String ?? "Błąd hosta")
        default: break
        }
    }

    private func fail(_ message: String) {
        guard !closed else { return }
        closed = true
        task.cancel(with: .goingAway, reason: nil)
        events?.liveFailed(message, beforeReady: !ready)
    }

    func sendAudio(_ pcm16: Data) {
        guard !closed else { return }
        task.send(.data(pcm16)) { _ in }
    }

    func sendToolResult(id: String, name: String, response: [String: Any]) {
        guard !closed, let s = jsonString(["type": "tool-result", "id": id, "response": response]) else { return }
        task.send(.string(s)) { _ in }
    }

    func close() {
        guard !closed else { return }
        closed = true
        if let s = jsonString(["type": "end"]) { task.send(.string(s)) { _ in } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [task] in task.cancel(with: .normalClosure, reason: nil) }
    }
}

final class DirectLink: LiveLink {
    let viaHost = false
    private weak var events: LiveEvents?
    private var task: URLSessionWebSocketTask?
    private let keys: [String]
    private var keyIndex = 0
    private let setup: [String: Any]
    private var ready = false
    private var closed = false
    private var pending: [Data] = []
    private var userText = ""
    private var modelText = ""

    init(keys: [String], model: String, voice: String, prompt: String, tools: [[String: Any]], events: LiveEvents) {
        self.keys = keys
        self.events = events
        setup = ["setup": [
            "model": model,
            "generationConfig": ["responseModalities": ["AUDIO"], "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]], "languageCode": "pl-PL"]],
            "systemInstruction": ["parts": [["text": prompt]]],
            "tools": [["functionDeclarations": tools]],
            "inputAudioTranscription": ["languageCodes": ["pl-PL"]],
            "outputAudioTranscription": [String: Any](),
        ] as [String: Any]]
        connect()
    }

    private func connect() {
        guard keyIndex < keys.count else { fail("Brak działającego klucza Gemini"); return }
        let url = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(keys[keyIndex])")!
        let t = URLSession.shared.webSocketTask(with: url)
        t.maximumMessageSize = 8 << 20
        task = t
        t.resume()
        if let s = jsonString(setup) { t.send(.string(s)) { _ in } }
        receive(t)
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, !self.closed, t === self.task else { return }
                switch result {
                case .failure(let e):
                    if !self.ready && self.keyIndex + 1 < self.keys.count {
                        self.keyIndex += 1
                        self.connect()
                    } else {
                        self.fail("Gemini: \(e.localizedDescription)")
                    }
                case .success(.data(let d)):
                    self.handle(d)
                    self.receive(t)
                case .success(.string(let s)):
                    self.handle(Data(s.utf8))
                    self.receive(t)
                @unknown default:
                    self.receive(t)
                }
            }
        }
    }

    private func handle(_ d: Data) {
        guard let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        if m["setupComplete"] != nil {
            ready = true
            events?.liveReady()
            for chunk in pending { sendAudio(chunk) }
            pending.removeAll()
            return
        }
        if let call = m["toolCall"] as? [String: Any], let calls = call["functionCalls"] as? [[String: Any]] {
            for c in calls {
                events?.liveTool(id: c["id"] as? String ?? UUID().uuidString, name: c["name"] as? String ?? "", args: c["args"] as? [String: Any] ?? [:])
            }
            return
        }
        guard let sc = m["serverContent"] as? [String: Any] else { return }
        if sc["interrupted"] as? Bool == true { events?.liveInterrupted() }
        if let turn = sc["modelTurn"] as? [String: Any], let parts = turn["parts"] as? [[String: Any]] {
            for p in parts {
                if let inline = p["inlineData"] as? [String: Any], let b64 = inline["data"] as? String, let audio = Data(base64Encoded: b64) { events?.liveAudio(audio) }
            }
        }
        if let it = sc["inputTranscription"] as? [String: Any], let t = it["text"] as? String { userText += t; events?.liveTranscript(user: true, text: userText) }
        if let ot = sc["outputTranscription"] as? [String: Any], let t = ot["text"] as? String { modelText += t; events?.liveTranscript(user: false, text: modelText) }
        if sc["turnComplete"] as? Bool == true {
            userText = ""
            modelText = ""
            events?.liveTurnComplete()
        }
    }

    private func fail(_ message: String) {
        guard !closed else { return }
        closed = true
        task?.cancel(with: .goingAway, reason: nil)
        events?.liveFailed(message, beforeReady: !ready)
    }

    func sendAudio(_ pcm16: Data) {
        guard !closed else { return }
        guard ready else { if pending.count < 100 { pending.append(pcm16) }; return }
        let msg: [String: Any] = ["realtimeInput": ["audio": ["mimeType": "audio/pcm;rate=16000", "data": pcm16.base64EncodedString()]]]
        if let s = jsonString(msg) { task?.send(.string(s)) { _ in } }
    }

    func sendText(_ text: String) {
        guard !closed, ready, let s = jsonString(["realtimeInput": ["text": text]]) else { return }
        task?.send(.string(s)) { _ in }
    }

    func sendToolResult(id: String, name: String, response: [String: Any]) {
        guard !closed else { return }
        let msg: [String: Any] = ["toolResponse": ["functionResponses": [["id": id, "name": name, "response": response]]]]
        if let s = jsonString(msg) { task?.send(.string(s)) { _ in } }
    }

    func close() {
        guard !closed else { return }
        closed = true
        task?.cancel(with: .normalClosure, reason: nil)
    }
}
