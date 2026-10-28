// Concierge Pokój - speaks announcements queued by the Concierge host (only when Jurek asked to be told in his room), in the same Gemini voice.
import Foundation

final class Announcer: LiveEvents {
    private let audio: AudioIO
    private var link: DirectLink?
    private var text = ""
    private var done: () -> Void = {}
    private var finishing = false
    private var watchdog: Timer?

    init(audio: AudioIO) { self.audio = audio }

    var busy: Bool { link != nil }

    func say(_ text: String, keys: [String], model: String, voice: String, done: @escaping () -> Void) {
        self.text = text
        self.done = done
        finishing = false
        let prompt = "Jesteś głosem asystenta Concierge w pokoju Jurka. Dostajesz treść komunikatu. Wypowiedz ją naturalnie po polsku, dokładnie tę treść, bez powitań i bez dodawania czegokolwiek."
        link = DirectLink(keys: keys, model: model, voice: voice, prompt: prompt, tools: [], events: self)
        watchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.finish() }
    }

    func stop() { finish() }

    private func finish() {
        guard link != nil else { return }
        watchdog?.invalidate()
        link?.close()
        link = nil
        let d = done
        done = {}
        d()
    }

    func liveReady() { link?.sendText("Komunikat: \(text)") }
    func liveAudio(_ pcm24: Data) { audio.playSpeech(pcm24) }
    func liveTranscript(user: Bool, text: String) {}
    func liveInterrupted() {}
    func liveTool(id: String, name: String, args: [String: Any]) {}
    func liveThinking() {}
    func liveSpeaking() {}
    func liveFailed(_ message: String, beforeReady: Bool) { NSLog("room: announcement failed: \(message)"); finish() }

    func liveTurnComplete() {
        guard !finishing else { return }
        finishing = true
        func check() {
            if audio.speaking { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: check) } else { finish() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: check)
    }
}
