// Concierge Pokój - offline "Hej Gzowo" detector: Vosk with a closed grammar in which the phrase (heard by the Polish model as "hej gazowa") competes with ~2000 everyday words, plus a word-timing check that rejects phrases stretched over other words.
import Foundation

final class WakeWord {
    var onWake: (_ commandFollows: Bool) -> Void = { _ in }
    var onReject: (_ text: String) -> Void = { _ in }
    private var model: OpaquePointer?
    private var rec: OpaquePointer?

    init?(modelPath: String, wordsPath: String?) {
        vosk_set_log_level(-1)
        guard let m = vosk_model_new(modelPath) else { return nil }
        model = m
        let words = wordsPath.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }?.split(whereSeparator: \.isNewline).map(String.init) ?? []
        let phrases = ["hej gazowa", "hej", "gazowa"] + words + ["[unk]"]
        guard let data = try? JSONSerialization.data(withJSONObject: phrases), let grammar = String(data: data, encoding: .utf8) else { return nil }
        rec = vosk_recognizer_new_grm(m, 16000, grammar)
        guard let rec else { return nil }
        vosk_recognizer_set_words(rec, 1)
    }

    deinit {
        if let rec { vosk_recognizer_free(rec) }
        if let model { vosk_model_free(model) }
    }

    @discardableResult
    func accept(_ chunk: Data) -> Bool {
        guard let rec else { return false }
        let final = chunk.withUnsafeBytes { raw -> Int32 in
            guard let p = raw.bindMemory(to: CChar.self).baseAddress else { return 0 }
            return vosk_recognizer_accept_waveform(rec, p, Int32(chunk.count))
        }
        guard final == 1 else { return false }
        guard let r = vosk_recognizer_result(rec),
              let j = try? JSONSerialization.jsonObject(with: Data(String(cString: r).utf8)) as? [String: Any],
              let text = j["text"] as? String else { return true }
        let words = (j["result"] as? [[String: Any]] ?? []).map { (w: $0["word"] as? String ?? "", start: $0["start"] as? Double ?? 0, end: $0["end"] as? Double ?? 0) }
        guard let i = words.indices.first(where: { $0 + 1 < words.count && words[$0].w == "hej" && words[$0 + 1].w == "gazowa" }) else {
            if text.contains("hej") || text.contains("gazowa") { NSLog("room: near miss '\(text)'") }
            return true
        }
        let hej = words[i].end - words[i].start
        let gzowo = words[i + 1].end - words[i + 1].start
        let gap = words[i + 1].start - words[i].end
        if hej > 0.38 || gap > 0.1 || gzowo < 0.22 || gzowo > 0.8 {
            NSLog("room: rejected '\(text)' (hej %.2fs, gap %.2fs, gzowo %.2fs)", hej, gap, gzowo)
            onReject(text)
            return true
        }
        onWake(i + 2 < words.count)
        return true
    }

    func reset() {
        if let rec { vosk_recognizer_reset(rec) }
    }
}
