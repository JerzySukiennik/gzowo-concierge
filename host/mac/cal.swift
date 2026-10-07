// cal.swift - EventKit helper for Gzowo Concierge. JSON in args, JSON out on stdout.
import Foundation
import EventKit

let store = EKEventStore()
let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone.current
    return f
}()

var outPath: String? = nil
func out(_ obj: Any) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    if let p = outPath {
        let tmp = p + ".tmp"
        try! data.write(to: URL(fileURLWithPath: tmp))
        try? FileManager.default.removeItem(atPath: p)
        try! FileManager.default.moveItem(atPath: tmp, toPath: p)
    } else {
        print(String(data: data, encoding: .utf8)!)
    }
}
func fail(_ msg: String) -> Never {
    out(["ok": false, "error": msg])
    exit(1)
}
func parseDate(_ s: String) -> Date? {
    if let d = iso.date(from: s) { return d }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
        f.dateFormat = fmt
        if let d = f.date(from: s) { return d }
    }
    return nil
}
func fmt(_ d: Date) -> String { iso.string(from: d) }

func describe(_ e: EKEvent) -> [String: Any] {
    var o: [String: Any] = [
        "id": e.eventIdentifier ?? "",
        "title": e.title ?? "",
        "start": fmt(e.startDate),
        "end": fmt(e.endDate),
        "allDay": e.isAllDay,
        "calendar": e.calendar.title,
    ]
    if let l = e.location, !l.isEmpty { o["location"] = l }
    if let n = e.notes, !n.isEmpty { o["notes"] = n }
    if e.hasRecurrenceRules { o["recurring"] = true }
    return o
}

func requestAccess() {
    let sem = DispatchSemaphore(value: 0)
    var granted = false
    var err: Error?
    if #available(macOS 14.0, *) {
        store.requestFullAccessToEvents { g, e in granted = g; err = e; sem.signal() }
    } else {
        store.requestAccess(to: .event) { g, e in granted = g; err = e; sem.signal() }
    }
    _ = sem.wait(timeout: .now() + 120)
    if !granted { fail("Calendar access denied (\(err?.localizedDescription ?? "no error")). Allow in System Settings > Privacy & Security > Calendars.") }
}

func requestRemindersAccess() {
    let sem = DispatchSemaphore(value: 0)
    var granted = false
    var err: Error?
    if #available(macOS 14.0, *) {
        store.requestFullAccessToReminders { g, e in granted = g; err = e; sem.signal() }
    } else {
        store.requestAccess(to: .reminder) { g, e in granted = g; err = e; sem.signal() }
    }
    _ = sem.wait(timeout: .now() + 120)
    if !granted { fail("Reminders access denied (\(err?.localizedDescription ?? "no error")). Allow in System Settings > Privacy & Security > Reminders.") }
}

func runScript(_ source: String) -> String {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let error { fail("AppleScript: \(error[NSAppleScript.errorMessage] as? String ?? "failed") (\(error[NSAppleScript.errorNumber] as? Int ?? 0))") }
    return result?.stringValue ?? ""
}

func asEsc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

func htmlEsc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

func describeReminder(_ r: EKReminder) -> [String: Any] {
    var o: [String: Any] = ["id": r.calendarItemIdentifier, "title": r.title ?? "", "list": r.calendar.title, "completed": r.isCompleted]
    if let c = r.dueDateComponents, let d = Calendar.current.date(from: c) { o["due"] = fmt(d); o["dueHasTime"] = c.hour != nil }
    if let n = r.notes, !n.isEmpty { o["notes"] = n }
    return o
}

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { fail("usage: cal <calendars|list|add|update|delete|get> [--key value ...]") }
args.removeFirst()
var opt: [String: String] = [:]
var i = 0
while i < args.count {
    if args[i].hasPrefix("--"), i + 1 < args.count {
        opt[String(args[i].dropFirst(2))] = args[i + 1]
        i += 2
    } else { i += 1 }
}

outPath = opt["out"]
if cmd.hasPrefix("rem-") { requestRemindersAccess() } else if cmd.hasPrefix("notes-") || cmd.hasPrefix("music-") { } else { requestAccess() }

func pickCalendar(_ name: String?) -> EKCalendar {
    let writable = store.calendars(for: .event).filter { $0.allowsContentModifications }
    if let n = name, !n.isEmpty {
        if let c = writable.first(where: { $0.title.lowercased() == n.lowercased() }) { return c }
        fail("No writable calendar named '\(n)'. Available: \(writable.map { $0.title }.joined(separator: ", "))")
    }
    if let d = store.defaultCalendarForNewEvents, d.allowsContentModifications { return d }
    if let c = writable.first { return c }
    fail("No writable calendar found")
}

switch cmd {
case "calendars":
    out(["ok": true, "calendars": store.calendars(for: .event).map {
        ["title": $0.title, "source": $0.source.title, "writable": $0.allowsContentModifications] as [String: Any]
    }])

case "list":
    guard let fs = opt["from"], let ts = opt["to"], let from = parseDate(fs), let to = parseDate(ts) else { fail("list needs --from and --to (ISO)") }
    var cals: [EKCalendar]? = nil
    if let n = opt["calendar"], !n.isEmpty {
        cals = store.calendars(for: .event).filter { $0.title.lowercased() == n.lowercased() }
        if cals!.isEmpty { fail("No calendar named '\(n)'") }
    }
    let pred = store.predicateForEvents(withStart: from, end: to, calendars: cals)
    let evs = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    var res = evs.map(describe)
    if let q = opt["query"]?.lowercased(), !q.isEmpty {
        res = res.filter { ($0["title"] as? String ?? "").lowercased().contains(q) || ($0["notes"] as? String ?? "").lowercased().contains(q) || ($0["location"] as? String ?? "").lowercased().contains(q) }
    }
    out(["ok": true, "count": res.count, "events": res])

case "get":
    guard let id = opt["id"], let e = store.event(withIdentifier: id) else { fail("event not found") }
    out(["ok": true, "event": describe(e)])

case "add":
    guard let title = opt["title"], let ss = opt["start"], let start = parseDate(ss) else { fail("add needs --title and --start") }
    let ev = EKEvent(eventStore: store)
    ev.calendar = pickCalendar(opt["calendar"])
    ev.title = title
    ev.startDate = start
    let allDay = opt["allDay"] == "true"
    ev.isAllDay = allDay
    if let es = opt["end"], let end = parseDate(es) { ev.endDate = end }
    else { ev.endDate = allDay ? start : start.addingTimeInterval(3600) }
    if !allDay && ev.endDate <= ev.startDate { ev.endDate = ev.startDate.addingTimeInterval(3600) }
    if let l = opt["location"] { ev.location = l }
    if let n = opt["notes"] { ev.notes = n }
    if let a = opt["alarmMinutes"], let m = Double(a) { ev.addAlarm(EKAlarm(relativeOffset: -m * 60)) }
    do { try store.save(ev, span: .thisEvent) } catch { fail("save failed: \(error.localizedDescription)") }
    out(["ok": true, "event": describe(ev)])

case "update":
    guard let id = opt["id"], let ev = store.event(withIdentifier: id) else { fail("event not found") }
    if let t = opt["title"] { ev.title = t }
    if let s = opt["start"], let d = parseDate(s) {
        let dur = ev.endDate.timeIntervalSince(ev.startDate)
        ev.startDate = d
        if opt["end"] == nil { ev.endDate = d.addingTimeInterval(dur) }
    }
    if let e = opt["end"], let d = parseDate(e) { ev.endDate = d }
    if !ev.isAllDay && ev.endDate <= ev.startDate { ev.endDate = ev.startDate.addingTimeInterval(3600) }
    if let l = opt["location"] { ev.location = l }
    if let n = opt["notes"] { ev.notes = n }
    if let a = opt["allDay"] { ev.isAllDay = (a == "true") }
    do { try store.save(ev, span: .thisEvent) } catch { fail("save failed: \(error.localizedDescription)") }
    out(["ok": true, "event": describe(ev)])

case "delete":
    guard let id = opt["id"], let ev = store.event(withIdentifier: id) else { fail("event not found") }
    let d = describe(ev)
    do { try store.remove(ev, span: .thisEvent) } catch { fail("delete failed: \(error.localizedDescription)") }
    out(["ok": true, "deleted": d])

case "rem-lists":
    out(["ok": true, "lists": store.calendars(for: .reminder).map { ["title": $0.title, "writable": $0.allowsContentModifications] as [String: Any] }])

case "rem-list":
    var cals: [EKCalendar]? = nil
    if let n = opt["list"], !n.isEmpty {
        cals = store.calendars(for: .reminder).filter { $0.title.lowercased() == n.lowercased() }
        if cals!.isEmpty { fail("No reminders list named '\(n)'") }
    }
    let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
    let sem = DispatchSemaphore(value: 0)
    var found: [EKReminder] = []
    store.fetchReminders(matching: pred) { found = $0 ?? []; sem.signal() }
    _ = sem.wait(timeout: .now() + 20)
    let limit = Int(opt["limit"] ?? "") ?? 40
    let sorted = found.sorted { (a, b) in
        let da = a.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? Date.distantFuture
        let db = b.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? Date.distantFuture
        return da < db
    }
    out(["ok": true, "count": min(sorted.count, limit), "total": sorted.count, "reminders": Array(sorted.prefix(limit)).map(describeReminder)])

case "rem-add":
    guard let title = opt["title"] else { fail("rem-add needs --title") }
    let r = EKReminder(eventStore: store)
    r.title = title
    if let n = opt["notes"] { r.notes = n }
    var target = store.defaultCalendarForNewReminders()
    if let n = opt["list"], !n.isEmpty {
        guard let c = store.calendars(for: .reminder).first(where: { $0.title.lowercased() == n.lowercased() && $0.allowsContentModifications }) else { fail("No writable reminders list named '\(n)'") }
        target = c
    }
    guard let cal = target else { fail("No reminders list available") }
    r.calendar = cal
    if let ds = opt["due"], let d = parseDate(ds) {
        let hasTime = ds.contains("T") || ds.contains(":")
        r.dueDateComponents = Calendar.current.dateComponents(hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: d)
        if hasTime { r.addAlarm(EKAlarm(absoluteDate: d)) }
    }
    do { try store.save(r, commit: true) } catch { fail("save failed: \(error.localizedDescription)") }
    out(["ok": true, "reminder": describeReminder(r)])

case "rem-complete":
    guard let id = opt["id"], let r = store.calendarItem(withIdentifier: id) as? EKReminder else { fail("reminder not found") }
    r.isCompleted = true
    do { try store.save(r, commit: true) } catch { fail("save failed: \(error.localizedDescription)") }
    out(["ok": true, "reminder": describeReminder(r)])

case "rem-delete":
    guard let id = opt["id"], let r = store.calendarItem(withIdentifier: id) as? EKReminder else { fail("reminder not found") }
    do { try store.remove(r, commit: true) } catch { fail("delete failed: \(error.localizedDescription)") }
    out(["ok": true])

case "notes-delete":
    guard let id = opt["id"] else { fail("notes-delete needs --id") }
    _ = runScript("tell application \"Notes\" to delete note id \"\(asEsc(id))\"")
    out(["ok": true])

case "notes-search":
    let q = asEsc(opt["query"] ?? "")
    let src = """
    set q to "\(q)"
    set res to ""
    tell application "Notes"
        set found to (every note whose name contains q or plaintext contains q)
        set c to count of found
        if c > 8 then set c to 8
        repeat with i from 1 to c
            set n to item i of found
            set pt to plaintext of n
            if (length of pt) > 180 then set pt to text 1 thru 180 of pt
            set res to res & (name of n) & "||" & (id of n) & "||" & (modification date of n as string) & "||" & pt & "@@@"
        end repeat
    end tell
    return res
    """
    let raw = runScript(src)
    let items = raw.components(separatedBy: "@@@").filter { !$0.isEmpty }.map { row -> [String: Any] in
        let p = row.components(separatedBy: "||")
        return ["title": p.count > 0 ? p[0] : "", "id": p.count > 1 ? p[1] : "", "modified": p.count > 2 ? p[2] : "", "snippet": (p.count > 3 ? p[3...].joined(separator: "||") : "").replacingOccurrences(of: "\n", with: " ")]
    }
    out(["ok": true, "count": items.count, "notes": items])

case "notes-read":
    guard let id = opt["id"] else { fail("notes-read needs --id") }
    let src = """
    tell application "Notes"
        set n to note id "\(asEsc(id))"
        return (name of n) & "@@@" & (plaintext of n)
    end tell
    """
    let raw = runScript(src)
    let parts = raw.components(separatedBy: "@@@")
    let body = parts.count > 1 ? parts[1...].joined(separator: "@@@") : ""
    out(["ok": true, "title": parts.first ?? "", "text": String(body.prefix(9000))])

case "notes-add":
    guard let title = opt["title"] else { fail("notes-add needs --title") }
    let body = (opt["body"] ?? "").components(separatedBy: "\n").map { "<div>\(htmlEsc($0))</div>" }.joined()
    let html = "<div><b>\(htmlEsc(title))</b></div>" + body
    let src = """
    tell application "Notes"
        set n to make new note with properties {body:"\(asEsc(html))"}
        return id of n
    end tell
    """
    out(["ok": true, "id": runScript(src), "title": title])

case "music-now":
    let src = """
    if application "Music" is not running then return "closed"
    tell application "Music"
        if player state is stopped then return "stopped"
        return (player state as string) & "||" & (name of current track) & "||" & (artist of current track) & "||" & (album of current track)
    end tell
    """
    let raw = runScript(src)
    let p = raw.components(separatedBy: "||")
    if p.count >= 4 { out(["ok": true, "state": p[0], "track": p[1], "artist": p[2], "album": p[3]]) } else { out(["ok": true, "state": raw]) }

case "music-control":
    let action = opt["action"] ?? ""
    let cmdText: String
    switch action {
    case "play": cmdText = "play"
    case "pause": cmdText = "pause"
    case "next": cmdText = "next track"
    case "previous": cmdText = "previous track"
    case "toggle": cmdText = "playpause"
    default: fail("unknown music action")
    }
    _ = runScript("tell application \"Music\" to \(cmdText)")
    out(["ok": true, "action": action])

case "music-volume":
    let v = max(0, min(100, Int(opt["level"] ?? "") ?? 50))
    _ = runScript("tell application \"Music\" to set sound volume to \(v)")
    out(["ok": true, "volume": v])

case "music-play":
    let q = asEsc(opt["query"] ?? "")
    let src = """
    tell application "Music"
        if (count of tracks of library playlist 1) is 0 then return "emptylibrary"
        try
            set t to first track of library playlist 1 whose name contains "\(q)" or artist contains "\(q)" or album contains "\(q)"
            play t
            return (name of t) & "||" & (artist of t)
        on error
            return "notfound"
        end try
    end tell
    """
    let raw = runScript(src)
    if raw == "emptylibrary" { fail("Biblioteka aplikacji Muzyka jest pusta, więc nie ma czego odtworzyć. Ta funkcja gra tylko utwory zapisane w bibliotece, nie z katalogu Apple Music. Powiedz użytkownikowi, że musi dodać utwory do biblioteki (albo poczekać na konektor Spotify).") }
    if raw == "notfound" { fail("Nie znalazłem takiego utworu w bibliotece Muzyki. Szukam tylko po tytule, wykonawcy i albumie w lokalnej bibliotece, nie po gatunku.") }
    let p = raw.components(separatedBy: "||")
    out(["ok": true, "track": p.first ?? "", "artist": p.count > 1 ? p[1] : ""])

default:
    fail("unknown command \(cmd)")
}
