// Concierge Pokój - offline "Hej Gzowo" detector: Vosk with a closed grammar in which the phrase (heard by the Polish model as "hej gazowa") competes with everyday words.
import Foundation

final class WakeWord {
    var onWake: (_ commandFollows: Bool) -> Void = { _ in }
    private var model: OpaquePointer?
    private var rec: OpaquePointer?

    private static let words = """
    i w na nie to że się z do jest jak co a o tak ale po za od już czy go mi ma tylko jego jej ich by może być było była był są będzie mnie ty ja my wy on ona oni ten ta te tego tej tym tu tam teraz potem dziś jutro wczoraj rano wieczorem noc dzień dobrze dobra okej no nic coś ktoś kto gdzie kiedy dlaczego bo więc jeszcze bardzo dużo mało trochę zawsze nigdy często chyba musisz muszę chcę chcesz mam masz wiem wiesz mówi mówię powiedz zobacz słuchaj chodź idź idziemy jedziemy weź daj zrób zrobić mama tata mamo tato brat siostra babcia dziadek pies kot dom szkoła szkole klasa lekcja kuchnia kuchni kuchenka pokój łazienka stół stole krzesło okno drzwi telefon komputer laptop ładowarka muzyka muzykę film gra gry obiad śniadanie kolacja woda herbata kawa chleb jabłko samochód rower autobus miasto wieś las góry morze pogoda deszcz słońce zimno ciepło gorąco piec piecu gazowym gazowe gazu gaz gazeta gazetę gotowe gotowy gosia zosia grzesiek kolego kolega jan janek ola kasia ania tomek michał piotr jeden dwa trzy cztery pięć sześć siedem osiem dziewięć dziesięć minut minuty godzina godziny sekund który która które jaki jaka jakie ile czas timer budzik alarm wyłącz włącz puść zatrzymaj stop następna głośniej ciszej proszę dziękuję cześć hejka witaj dzień dobry siema pa
    """

    init?(modelPath: String) {
        vosk_set_log_level(-1)
        guard let m = vosk_model_new(modelPath) else { return nil }
        model = m
        let phrases = ["hej gazowa", "hej", "gazowa"] + Self.words.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init) + ["[unk]"]
        guard let data = try? JSONSerialization.data(withJSONObject: phrases), let grammar = String(data: data, encoding: .utf8) else { return nil }
        rec = vosk_recognizer_new_grm(m, 16000, grammar)
        guard rec != nil else { return nil }
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
        let tokens = text.split(separator: " ").map(String.init)
        if let i = tokens.indices.first(where: { $0 + 1 < tokens.count && tokens[$0] == "hej" && tokens[$0 + 1] == "gazowa" }) { onWake(i + 2 < tokens.count) }
        else if tokens.contains("hej") || tokens.contains("gazowa") { NSLog("room: near miss '\(text)'") }
        return true
    }

    func reset() {
        if let rec { vosk_recognizer_reset(rec) }
    }
}
