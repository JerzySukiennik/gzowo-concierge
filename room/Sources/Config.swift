// Concierge Pokój - settings from Application Support: host addresses and token, Gemini keys, contacts, location.
import Foundation

struct RoomConfig {
    var hosts: [String] = []
    var token = ""
    var geminiKeys: [String] = []
    var trusted: [String: String] = [:]
    var contacts: [String: String] = [:]
    var latitude = 52.2297
    var longitude = 21.0122
    var place = "Warszawa"
    var voice = "Puck"
    var model = "models/gemini-3.1-flash-live-preview"
    var wakeThreshold: Float = 0.5

    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ConciergeRoom", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func load() -> RoomConfig {
        var c = RoomConfig()
        if let data = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            c.hosts = j["hosts"] as? [String] ?? []
            c.token = j["token"] as? String ?? ""
            c.trusted = lower(j["trusted"] as? [String: String] ?? [:])
            c.contacts = lower(j["contacts"] as? [String: String] ?? [:])
            c.latitude = j["latitude"] as? Double ?? c.latitude
            c.longitude = j["longitude"] as? Double ?? c.longitude
            c.place = j["place"] as? String ?? c.place
            c.voice = j["voice"] as? String ?? c.voice
            c.model = j["model"] as? String ?? c.model
            c.wakeThreshold = (j["wakeThreshold"] as? NSNumber)?.floatValue ?? c.wakeThreshold
        }
        let env = dotenv(dir.appendingPathComponent(".env"))
        let keys = (env["GEMINI_API_KEYS"] ?? env["GEMINI_API_KEY"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        c.geminiKeys = keys
        if c.token.isEmpty, let t = env["CONCIERGE_TOKEN"] { c.token = t }
        return c
    }

    private static func lower(_ d: [String: String]) -> [String: String] {
        Dictionary(d.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    private static func dotenv(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.hasPrefix("#"), let eq = s.firstIndex(of: "=") else { continue }
            var v = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if v.count >= 2, let f = v.first, f == v.last, f == "\"" || f == "'" { v = String(v.dropFirst().dropLast()) }
            out[String(s[..<eq]).trimmingCharacters(in: .whitespaces)] = v
        }
        return out
    }
}
