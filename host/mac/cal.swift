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
requestAccess()

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

default:
    fail("unknown command \(cmd)")
}
