// Gzowo Concierge for macOS - what starts by itself at login or boot (your agents, system agents and daemons, login items) with a switch for each.
import AppKit

struct StartupItem: Identifiable, Equatable {
    enum Kind: Int { case userAgent, systemAgent, daemon, loginItem }
    var id: String
    var kind: Kind
    var label: String
    var name: String
    var detail: String
    var enabled: Bool
    var running: Bool
    var keepAlive: Bool
    var protected: Bool
    var missing: Bool
    var file: String?
    var bundle: URL?
}

@MainActor
final class StartupItems: ObservableObject {
    @Published private(set) var items: [StartupItem] = []
    @Published private(set) var busy = Set<String>()
    @Published private(set) var problem = ""
    private let uid = getuid()
    private let removedKey = "removedLoginItems"

    var activeCount: Int { items.filter { $0.enabled && !$0.protected && !$0.missing }.count }

    func scan() {
        let uid = self.uid
        let removed = UserDefaults.standard.array(forKey: removedKey) as? [[String: String]] ?? []
        Task.detached(priority: .userInitiated) {
            let jobs = Dictionary(ProcessInfoReader.launchdJobs().map { ($0.label, $0.pid) }, uniquingKeysWith: { a, _ in a })
            let overrides = Self.overrides("gui/\(uid)")
            let systemOverrides = Self.overrides("system")
            var out: [StartupItem] = []
            let home = NSHomeDirectory()
            out += Self.agents(in: home + "/Library/LaunchAgents", kind: .userAgent, jobs: jobs, overrides: overrides)
            out += Self.agents(in: "/Library/LaunchAgents", kind: .systemAgent, jobs: jobs, overrides: overrides)
            out += Self.agents(in: "/Library/LaunchDaemons", kind: .daemon, jobs: [:], overrides: systemOverrides)
            out += Self.loginItems()
            for r in removed where !out.contains(where: { $0.kind == .loginItem && $0.name == r["name"] }) {
                out.append(StartupItem(id: "login:\(r["name"] ?? "")", kind: .loginItem, label: r["name"] ?? "", name: r["name"] ?? "", detail: (r["path"] ?? "").replacingOccurrences(of: home, with: "~"),
                                       enabled: false, running: false, keepAlive: false, protected: false, missing: false, file: r["path"], bundle: r["path"].map { URL(fileURLWithPath: $0) }))
            }
            out.sort { a, b in a.kind.rawValue != b.kind.rawValue ? a.kind.rawValue < b.kind.rawValue : (a.enabled != b.enabled ? a.enabled : a.name.localizedCompare(b.name) == .orderedAscending) }
            let result = out
            await MainActor.run { self.items = result }
        }
    }

    func set(_ item: StartupItem, on: Bool) {
        guard !item.protected, !busy.contains(item.id) else { return }
        busy.insert(item.id)
        problem = ""
        let uid = self.uid
        let removedKey = self.removedKey
        Task.detached(priority: .userInitiated) {
            var ok = true
            switch item.kind {
            case .userAgent:
                ok = Self.toggleUserAgent(item, on: on, uid: uid)
            case .systemAgent:
                PowerControl.run("/bin/launchctl", [on ? "enable" : "disable", "gui/\(uid)/\(item.label)"])
                if on, let f = item.file { PowerControl.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", f]) }
                else { PowerControl.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(item.label)"]) }
            case .daemon:
                let cmd = on ? "/bin/launchctl enable system/\(item.label); /bin/launchctl bootstrap system '\(item.file ?? "")' 2>/dev/null; true" : "/bin/launchctl disable system/\(item.label); /bin/launchctl bootout system/\(item.label) 2>/dev/null; true"
                let script = "do shell script \"\(cmd)\" with administrator privileges with prompt \"Concierge zmienia autostart usługi \(item.name).\""
                ok = PowerControl.run("/usr/bin/osascript", ["-e", script]) == 0
            case .loginItem:
                ok = Self.toggleLoginItem(item, on: on)
                if ok {
                    await MainActor.run {
                        var removed = UserDefaults.standard.array(forKey: removedKey) as? [[String: String]] ?? []
                        removed.removeAll { $0["name"] == item.name }
                        if !on, let path = item.file { removed.append(["name": item.name, "path": path]) }
                        UserDefaults.standard.set(removed, forKey: removedKey)
                    }
                }
            }
            let success = ok
            await MainActor.run {
                self.busy.remove(item.id)
                if !success { self.problem = "Nie udało się zmienić: \(item.name)." }
                self.scan()
            }
        }
    }

    func remove(_ item: StartupItem) {
        guard item.kind == .loginItem, item.missing else { return }
        Task.detached {
            _ = Self.osa("tell application \"System Events\" to delete (every login item whose name is \"\(item.label)\")")
            await MainActor.run { self.scan() }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    // MARK: readers

    private nonisolated static func overrides(_ domain: String) -> [String: Bool] {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print-disabled", domain]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var map: [String: Bool] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            map[label] = parts[1].trimmingCharacters(in: .whitespaces).hasPrefix("disabled")
        }
        return map
    }

    private nonisolated static func agents(in dir: String, kind: StartupItem.Kind, jobs: [String: pid_t?], overrides: [String: Bool]) -> [StartupItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var byLabel: [String: StartupItem] = [:]
        let home = NSHomeDirectory()
        for f in files.sorted() where f.hasSuffix(".plist") || f.hasSuffix(".plist.disabled") {
            let path = dir + "/" + f
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            let label = plist["Label"] as? String ?? String(f.prefix { $0 != "." })
            let renamed = f.hasSuffix(".disabled")
            if renamed, byLabel[label] != nil { continue }
            let args = (plist["ProgramArguments"] as? [String]) ?? (plist["Program"] as? String).map { [$0] } ?? []
            let exe = args.first ?? ""
            let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
            let keepAlive = (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] is [String: Any])
            let disabledOverride = overrides[label] ?? ((plist["Disabled"] as? Bool) ?? false)
            let pid = jobs[label] ?? nil
            let script = args.dropFirst().first { $0.hasPrefix("/") && !$0.hasSuffix(".env") }
            var detail = (script ?? exe).replacingOccurrences(of: home, with: "~")
            if !runAtLoad && !keepAlive && plist["StartInterval"] == nil && plist["StartCalendarInterval"] == nil { detail = "na żądanie · " + detail }
            let item = StartupItem(id: "\(kind.rawValue):\(label)", kind: kind, label: label, name: ProcessControl.pretty(label: label), detail: detail,
                                   enabled: !renamed && !disabledOverride, running: (pid ?? 0) > 0, keepAlive: keepAlive,
                                   protected: ProcessControl.protectedLabels.contains(label), missing: false, file: path, bundle: ProcessControl.appBundle(exe))
            if !renamed || byLabel[label] == nil { byLabel[label] = item }
        }
        return Array(byLabel.values)
    }

    private nonisolated static func osa(_ script: String) -> String? {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    private nonisolated static func loginItems() -> [StartupItem] {
        let script = """
        set out to ""
        tell application "System Events"
            repeat with li in every login item
                set p to ""
                try
                    set p to path of li
                    if p is missing value then set p to ""
                end try
                set out to out & (name of li) & tab & p & linefeed
            end repeat
        end tell
        return out
        """
        guard let text = osa(script) else { return [] }
        let home = NSHomeDirectory()
        return text.split(separator: "\n").compactMap { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let name = cols.first, !name.isEmpty else { return nil }
            let path = cols.count > 1 && cols[1] != "missing value" ? cols[1] : ""
            let missing = path.isEmpty || !FileManager.default.fileExists(atPath: path)
            return StartupItem(id: "login:\(name)", kind: .loginItem, label: name, name: name, detail: missing ? "Apki już nie ma" : path.replacingOccurrences(of: home, with: "~"),
                               enabled: true, running: false, keepAlive: false, protected: false, missing: missing, file: path.isEmpty ? nil : path, bundle: path.isEmpty ? nil : URL(fileURLWithPath: path))
        }
    }

    private nonisolated static func toggleLoginItem(_ item: StartupItem, on: Bool) -> Bool {
        if on {
            guard let path = item.file else { return false }
            return osa("tell application \"System Events\" to make login item at end with properties {path:\"\(path)\", hidden:false}") != nil
        }
        return osa("tell application \"System Events\" to delete (every login item whose name is \"\(item.label)\")") != nil
    }

    private nonisolated static func toggleUserAgent(_ item: StartupItem, on: Bool, uid: uid_t) -> Bool {
        guard let file = item.file else { return false }
        let fm = FileManager.default
        let active = file.hasSuffix(".disabled") ? String(file.dropLast(9)) : file
        let parked = active + ".disabled"
        if on {
            if !fm.fileExists(atPath: active), fm.fileExists(atPath: parked) { try? fm.moveItem(atPath: parked, toPath: active) }
            PowerControl.run("/bin/launchctl", ["enable", "gui/\(uid)/\(item.label)"])
            PowerControl.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", active])
            return fm.fileExists(atPath: active)
        }
        PowerControl.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(item.label)"])
        PowerControl.run("/bin/launchctl", ["disable", "gui/\(uid)/\(item.label)"])
        if fm.fileExists(atPath: active) {
            if fm.fileExists(atPath: parked) { try? fm.removeItem(atPath: parked) }
            try? fm.moveItem(atPath: active, toPath: parked)
        }
        return !fm.fileExists(atPath: active)
    }
}
