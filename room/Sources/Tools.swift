// Concierge Pokój - tools that run on the room speaker: timers and alarms, Apple Music, iMessage, weather, calendar, volume.
import Foundation
import EventKit

struct RoomAlarm: Codable {
    var id: String
    var kind: String
    var label: String
    var fire: Date
}

final class Alarms {
    var onFire: (RoomAlarm) -> Void = { _ in }
    private(set) var items: [RoomAlarm] = []
    private var timers: [String: Timer] = [:]
    private let file = RoomConfig.dir.appendingPathComponent("alarms.json")

    init() {
        if let d = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([RoomAlarm].self, from: d) {
            items = saved.filter { $0.fire > Date().addingTimeInterval(-60) }
        }
        items.forEach(schedule)
    }

    func add(kind: String, label: String, fire: Date) -> RoomAlarm {
        let a = RoomAlarm(id: String(UUID().uuidString.prefix(6)).lowercased(), kind: kind, label: label, fire: fire)
        items.append(a)
        schedule(a)
        save()
        return a
    }

    func cancel(where match: (RoomAlarm) -> Bool) -> Int {
        let gone = items.filter(match)
        for a in gone { timers[a.id]?.invalidate(); timers[a.id] = nil }
        items.removeAll(where: match)
        save()
        return gone.count
    }

    private func schedule(_ a: RoomAlarm) {
        let t = Timer(fire: max(a.fire, Date()), interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.items.removeAll { $0.id == a.id }
            self.timers[a.id] = nil
            self.save()
            self.onFire(a)
        }
        RunLoop.main.add(t, forMode: .common)
        timers[a.id] = t
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: file) }
    }
}

final class RoomTools {
    let alarms = Alarms()
    var config: RoomConfig
    var lastUserSpeech: () -> (String, Date) = { ("", .distantPast) }
    private let store = EKEventStore()

    init(config: RoomConfig) { self.config = config }

    static let rules = """
    ROOM SPEAKER: Jurek is talking to you through the speaker in his bedroom (an old MacBook called MacPetite with a microphone and a speaker). He wakes you with the phrase "Hej Gzowo"; transcripts may show it as "hej gazowa" or similar. Never comment on the phrase, just handle what follows it. If he only said the wake phrase, answer with one short word such as "Słucham?". Keep every answer short and spoken.
    The room_* tools run on the speaker itself: timers and alarms ring in his room, music plays on the room speaker through Apple Music, messages go out as iMessage from the assistant's own Apple account. For a timer use room_timer_set, for a wake-up or any clock time use room_alarm_set.
    Messages: contacts marked trusted (mama, tata) are sent right away. For anyone else first read the message back in one sentence and ask "Wysłać?", and call room_message_send with confirmed=true only after he clearly says yes.
    When you mention yourself in Polish, call this device "głośnik w pokoju"; never use English words such as "room speaker". Before a tool that takes a moment you may say "Już sprawdzam.", but then always give the actual answer.
    After each answer the speaker keeps listening for about nine seconds, so he can simply keep talking without the wake phrase. Do not end every reply with an offer or a question; just answer.
    """

    static let offlineRules = """
    His main computer with the full Concierge is off right now, so you only have the room tools; answer general questions from your own knowledge. For his calendar use room_calendar. For things that need the main Mac (notes in Pupka, memory, files, the Mac screen) say briefly it will work once his MacBook is on.
    """

    func declarations(offline: Bool) -> [[String: Any]] {
        var d: [[String: Any]] = [
            fn("room_timer_set", "Start a countdown timer that rings in the room.", ["seconds": int("Duration in seconds"), "label": str("Short label, e.g. makaron")], ["seconds"]),
            fn("room_alarm_set", "Set an alarm clock that rings with a classic bell in the room at a clock time (Europe/Warsaw). If the time already passed today it rings tomorrow.", ["time": str("HH:MM, 24-hour"), "date": str("Optional YYYY-MM-DD"), "label": str("Optional label")], ["time"]),
            fn("room_timers_list", "List running timers and alarms with their ids.", [:], []),
            fn("room_timer_cancel", "Cancel timers or alarms by id or label, or all of them.", ["id": str("Id from room_timers_list"), "label": str("Label to match"), "all": bool("Cancel everything")], []),
            fn("room_music_play", "Play music from Apple Music on the room speaker: a playlist, song, artist or album by name.", ["query": str("What to play, e.g. 'lo-fi do nauki' or 'Daft Punk Get Lucky'")], ["query"]),
            fn("room_music_control", "Control the music in the room.", ["action": enm(["pause", "resume", "next", "previous", "volume"], "Action"), "value": int("Volume 0-100 for action volume")], ["action"]),
            fn("room_music_now", "What is playing now in the room.", [:], []),
            fn("room_message_send", "Send an iMessage from the assistant's account. Use the contact name in base form (mama, tata) or a phone number.", ["to": str("Contact name or phone number"), "text": str("Message text in Polish"), "confirmed": bool("True only after Jurek said yes to sending (not needed for trusted contacts)")], ["to", "text"]),
            fn("room_weather", "Weather now and the forecast for today and tomorrow where Jurek lives.", ["day": enm(["today", "tomorrow"], "Which day")], []),
            fn("room_volume", "Set the room speaker volume.", ["level": int("0-100")], ["level"]),
        ]
        if offline { d.append(fn("room_calendar", "Jurek's calendar events for a day.", ["day": enm(["today", "tomorrow"], "Which day")], [])) }
        return d
    }

    private func fn(_ name: String, _ desc: String, _ props: [String: Any], _ required: [String]) -> [String: Any] {
        var params: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { params["required"] = required }
        return ["name": name, "description": desc, "parameters": params]
    }
    private func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private func int(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }
    private func bool(_ d: String) -> [String: Any] { ["type": "boolean", "description": d] }
    private func enm(_ v: [String], _ d: String) -> [String: Any] { ["type": "string", "enum": v, "description": d] }

    func handle(_ name: String, _ args: [String: Any]) async -> [String: Any] {
        switch name {
        case "room_timer_set":
            let s = (args["seconds"] as? NSNumber)?.intValue ?? 0
            guard s > 0, s <= 24 * 3600 else { return ["error": "Nieprawidłowy czas"] }
            let a = alarms.add(kind: "timer", label: args["label"] as? String ?? "", fire: Date().addingTimeInterval(TimeInterval(s)))
            return ["ok": true, "id": a.id, "rings_at": clock(a.fire)]
        case "room_alarm_set":
            guard let fire = alarmDate(args["time"] as? String ?? "", date: args["date"] as? String) else { return ["error": "Nie rozumiem godziny, podaj HH:MM"] }
            let a = alarms.add(kind: "alarm", label: args["label"] as? String ?? "", fire: fire)
            return ["ok": true, "id": a.id, "rings_at": dayClock(a.fire)]
        case "room_timers_list":
            return ["items": alarms.items.sorted { $0.fire < $1.fire }.map { ["id": $0.id, "kind": $0.kind, "label": $0.label, "rings_at": dayClock($0.fire), "seconds_left": Int($0.fire.timeIntervalSinceNow)] }]
        case "room_timer_cancel":
            let id = args["id"] as? String, label = (args["label"] as? String)?.lowercased(), all = args["all"] as? Bool ?? false
            let n = alarms.cancel { a in all || (id != nil && a.id == id) || (label != nil && !label!.isEmpty && a.label.lowercased().contains(label!)) }
            return ["cancelled": n]
        case "room_music_play":
            return await musicPlay(args["query"] as? String ?? "")
        case "room_music_control":
            return await musicControl(args["action"] as? String ?? "", value: (args["value"] as? NSNumber)?.intValue)
        case "room_music_now":
            let r = await osa("tell application \"Music\"\nif player state is playing then\nreturn (name of current track) & \" - \" & (artist of current track)\nelse\nreturn \"\"\nend if\nend tell")
            return r.ok ? ["playing": r.out.isEmpty ? NSNull() : r.out as Any] : ["error": r.out]
        case "room_message_send":
            return await message(to: args["to"] as? String ?? "", text: args["text"] as? String ?? "", confirmed: args["confirmed"] as? Bool ?? false)
        case "room_weather":
            return await weather(day: args["day"] as? String ?? "today")
        case "room_volume":
            let v = max(0, min(100, (args["level"] as? NSNumber)?.intValue ?? 50))
            let r = await osa("set volume output volume \(v)")
            return r.ok ? ["ok": true, "level": v] : ["error": r.out]
        case "room_calendar":
            return await calendar(day: args["day"] as? String ?? "today")
        default:
            return ["error": "Nieznane narzędzie \(name)"]
        }
    }

    private func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "pl_PL"); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }

    private func dayClock(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "pl_PL"); f.dateFormat = Calendar.current.isDateInToday(d) ? "'dziś' HH:mm" : "EEEE d MMMM HH:mm"; return f.string(from: d)
    }

    private func alarmDate(_ time: String, date: String?) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        var day = Date()
        if let date, !date.isEmpty {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
            guard let d = f.date(from: date) else { return nil }
            day = d
        }
        guard var fire = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) else { return nil }
        if (date ?? "").isEmpty && fire <= Date() { fire = Calendar.current.date(byAdding: .day, value: 1, to: fire) ?? fire }
        return fire
    }

    private func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }

    func osa(_ script: String) async -> (ok: Bool, out: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", script]
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch { cont.resume(returning: (false, error.localizedDescription)); return }
                p.waitUntilExit()
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                cont.resume(returning: p.terminationStatus == 0 ? (true, o) : (false, e.isEmpty ? o : e))
            }
        }
    }

    private func musicPlay(_ query: String) async -> [String: Any] {
        let q = esc(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return ["error": "Pusta prośba"] }
        let local = await osa("""
        tell application "Music"
        set pl to (every user playlist whose name contains "\(q)")
        if (count of pl) > 0 then
        play item 1 of pl
        return "playlist: " & (name of item 1 of pl)
        end if
        set hits to (search library playlist 1 for "\(q)")
        if (count of hits) > 0 then
        play item 1 of hits
        return "track: " & (name of item 1 of hits) & " - " & (artist of item 1 of hits)
        end if
        return ""
        end tell
        """)
        if local.ok && !local.out.isEmpty { return ["ok": true, "playing": local.out] }
        guard let found = await catalogSearch(query) else { return ["error": local.ok ? "Nie znalazłem tego w Apple Music" : local.out] }
        let opened = await osa("""
        tell application "Music" to activate
        open location "\(esc(found.url))"
        delay 3
        tell application "Music" to play
        delay 1
        tell application "Music" to return (player state as string) & "|" & (name of current track)
        """)
        if opened.ok, opened.out.hasPrefix("playing") { return ["ok": true, "playing": opened.out.split(separator: "|").dropFirst().joined(), "found": found.title] }
        return ["ok": false, "found": found.title, "note": "Otworzyłem utwór w Apple Music, ale nie wystartował sam."]
    }

    private func catalogSearch(_ q: String) async -> (title: String, url: String)? {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: q), URLQueryItem(name: "country", value: "pl"), URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "limit", value: "1")]
        guard let url = c.url, let (d, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let r = (j["results"] as? [[String: Any]])?.first, let link = r["trackViewUrl"] as? String else { return nil }
        let title = "\(r["trackName"] as? String ?? "") - \(r["artistName"] as? String ?? "")"
        return (title, link.replacingOccurrences(of: "https://", with: "music://"))
    }

    private func musicControl(_ action: String, value: Int?) async -> [String: Any] {
        let cmd: String
        switch action {
        case "pause": cmd = "pause"
        case "resume": cmd = "play"
        case "next": cmd = "next track"
        case "previous": cmd = "previous track"
        case "volume": cmd = "set sound volume to \(max(0, min(100, value ?? 50)))"
        default: return ["error": "Nieznana akcja"]
        }
        let r = await osa("tell application \"Music\" to \(cmd)")
        return r.ok ? ["ok": true] : ["error": r.out]
    }

    private func resolve(_ to: String) -> (handle: String, trusted: Bool)? {
        let key = to.lowercased().trimmingCharacters(in: .whitespaces)
        if let h = config.trusted[key] { return (h, true) }
        if let h = config.contacts[key] { return (h, false) }
        let digits = key.filter { $0.isNumber || $0 == "+" }
        if digits.count >= 9 { return (digits.hasPrefix("+") ? digits : (digits.count == 9 ? "+48" + digits : digits), config.trusted.values.contains(digits)) }
        if key.contains("@") { return (key, config.trusted.values.contains(key)) }
        return nil
    }

    private func message(to: String, text: String, confirmed: Bool) async -> [String: Any] {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return ["error": "Pusta wiadomość"] }
        guard let r = resolve(to) else { return ["error": "Nie znam kontaktu \(to). Poproś o numer telefonu."] }
        if !r.trusted {
            let (said, when) = lastUserSpeech()
            let yes = ["tak", "wyślij", "wysyłaj", "jasne", "pewnie", "okej", "ok", "dawaj", "no", "śmiało"]
            let words = said.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            let saidYes = Date().timeIntervalSince(when) < 30 && words.count <= 4 && words.contains(where: yes.contains)
            guard confirmed, saidYes else { return ["status": "needs_confirmation", "say": "Przeczytaj wiadomość jednym zdaniem i zapytaj: Wysłać?"] }
        }
        if ProcessInfo.processInfo.environment["ROOM_DRY_MESSAGES"] != nil { return ["ok": true, "sent_to": to, "dry_run": true] }
        let res = await osa("""
        tell application "Messages"
        set s to 1st account whose service type = iMessage
        send "\(esc(body))" to participant "\(esc(r.handle))" of s
        end tell
        """)
        return res.ok ? ["ok": true, "sent_to": to] : ["error": "Nie wysłałem: \(res.out)"]
    }

    private func weather(day: String) async -> [String: Any] {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(config.latitude)), URLQueryItem(name: "longitude", value: String(config.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,precipitation"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "Europe/Warsaw"), URLQueryItem(name: "forecast_days", value: "2"),
        ]
        guard let url = c.url, let (d, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let daily = j["daily"] as? [String: Any] else { return ["error": "Pogoda niedostępna"] }
        let i = day == "tomorrow" ? 1 : 0
        func at(_ k: String) -> Any { (daily[k] as? [Any]).flatMap { $0.count > i ? $0[i] : nil } ?? NSNull() }
        var out: [String: Any] = ["place": config.place, "day": day, "max": at("temperature_2m_max"), "min": at("temperature_2m_min"), "rain_chance": at("precipitation_probability_max"), "sky": Self.sky((at("weather_code") as? NSNumber)?.intValue ?? -1), "sunrise": at("sunrise"), "sunset": at("sunset")]
        if i == 0, let cur = j["current"] as? [String: Any] {
            out["now"] = ["temp": cur["temperature_2m"] ?? NSNull(), "feels": cur["apparent_temperature"] ?? NSNull(), "wind_kmh": cur["wind_speed_10m"] ?? NSNull(), "sky": Self.sky((cur["weather_code"] as? NSNumber)?.intValue ?? -1)]
        }
        return out
    }

    private static func sky(_ code: Int) -> String {
        switch code {
        case 0: return "bezchmurnie"
        case 1, 2: return "częściowe zachmurzenie"
        case 3: return "pochmurno"
        case 45, 48: return "mgła"
        case 51...57: return "mżawka"
        case 61...67: return "deszcz"
        case 71...77: return "śnieg"
        case 80...82: return "przelotny deszcz"
        case 85, 86: return "przelotny śnieg"
        case 95...99: return "burza"
        default: return "brak danych"
        }
    }

    private func calendar(day: String) async -> [String: Any] {
        let granted: Bool = await withCheckedContinuation { cont in store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) } }
        guard granted else { return ["error": "Brak dostępu do kalendarza na MacPetite"] }
        let start = Calendar.current.startOfDay(for: day == "tomorrow" ? Date().addingTimeInterval(86400) : Date())
        let end = start.addingTimeInterval(86400)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return ["day": day, "events": events.map { ["title": $0.title ?? "", "start": $0.isAllDay ? "cały dzień" : f.string(from: $0.startDate), "end": $0.isAllDay ? "" : f.string(from: $0.endDate)] }]
    }
}
