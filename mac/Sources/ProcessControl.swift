// Gzowo Concierge for macOS - "stop everything": open apps, menu bar apps, background agents and stray background processes (renders, AI servers), stopped gently and then for good.
import AppKit
import Darwin

struct StopTarget: Identifiable, Equatable {
    enum Kind: Int { case app, menuApp, agent, background }
    var id: String
    var kind: Kind
    var name: String
    var detail: String
    var pids: [pid_t]
    var bundleID: String?
    var bundle: URL?
    var label: String?
    var checked: Bool
    var memory: UInt64 = 0
}

enum ProcessInfoReader {
    static func path(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    static func bsd(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size ? info : nil
    }

    static func footprint(_ pid: pid_t) -> UInt64 {
        var usage = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &usage) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) } }
        return ok == 0 ? usage.ri_phys_footprint : 0
    }

    static func args(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }
        while i < size && buf[i] == 0 { i += 1 }
        var out: [String] = []
        var start = i
        while i < size && out.count < argc {
            if buf[i] == 0 { out.append(String(decoding: buf[start..<i], as: UTF8.self)); start = i + 1 }
            i += 1
        }
        return out
    }

    static func allPids() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        return Array(pids.prefix(got)).filter { $0 > 1 }
    }

    static func launchdJobs() -> [(label: String, pid: pid_t?)] {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["list"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst().compactMap { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { return nil }
            return (String(cols[2]), Int32(cols[0]))
        }
    }
}

@MainActor
final class ProcessControl: ObservableObject {
    @Published var targets: [StopTarget] = []
    @Published private(set) var stopping = false
    @Published private(set) var stubborn: [StopTarget] = []
    @Published private(set) var lastResult = ""

    nonisolated static let protectedLabels: Set<String> = ["fun.gzowo.concierge", "fun.gzowo.concierge.mac"]
    private nonisolated static let keepApps: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.loginwindow"]
    private nonisolated static let interpreters: Set<String> = ["python", "python3", "perl", "ruby", "java", "php"]

    func scan() {
        let me = ProcessInfo.processInfo.processIdentifier
        let myBundle = Bundle.main.bundleIdentifier
        Task.detached(priority: .userInitiated) {
            let running = await MainActor.run { NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0.bundleIdentifier, $0.bundleURL, $0.localizedName ?? "", $0.activationPolicy) } }
            var out: [StopTarget] = []
            var claimed = Set<pid_t>()
            var appRoots: [String] = []
            for (pid, bid, url, name, policy) in running where pid != me && bid != myBundle && policy != .prohibited {
                guard let bid, !Self.keepApps.contains(bid) else { continue }
                if let path = url?.path, path.dropLast(4).contains(".app/") || Self.isConcierge(path) { claimed.insert(pid); continue }
                if bid.hasPrefix("com.apple.") && (url?.path.hasPrefix("/System/") ?? true) && policy != .regular { continue }
                let kind: StopTarget.Kind = policy == .regular ? .app : .menuApp
                if kind == .menuApp && bid.hasPrefix("com.apple.") { continue }
                claimed.insert(pid)
                if let u = url { appRoots.append(u.path + "/") }
                let isClaude = bid == "com.anthropic.claudefordesktop"
                out.append(StopTarget(id: "app:\(pid)", kind: kind, name: name, detail: isClaude ? "Tu rozmawiasz z Claude" : (kind == .app ? "Otwarta aplikacja" : "Apka w pasku menu"),
                                      pids: [pid], bundleID: bid, bundle: url, label: nil, checked: !isClaude))
            }
            let jobs = ProcessInfoReader.launchdJobs()
            for job in jobs where Self.protectedLabels.contains(job.label) { if let pid = job.pid, pid > 0 { claimed.insert(pid) } }
            for job in jobs {
                guard let pid = job.pid, pid > 0, !claimed.contains(pid), !job.label.hasPrefix("com.apple."), !job.label.hasPrefix("application."), !Self.protectedLabels.contains(job.label) else { continue }
                let exe = ProcessInfoReader.path(pid)
                let args = ProcessInfoReader.args(pid)
                claimed.insert(pid)
                out.append(StopTarget(id: "agent:\(job.label)", kind: .agent, name: Self.pretty(label: job.label), detail: Self.describe(exe: exe, args: args),
                                      pids: [pid], bundleID: nil, bundle: Self.appBundle(exe), label: job.label, checked: true))
            }
            let uid = getuid()
            for pid in ProcessInfoReader.allPids() where pid != me && !claimed.contains(pid) {
                guard let info = ProcessInfoReader.bsd(pid), info.pbi_uid == uid, info.pbi_ppid == 1 else { continue }
                let exe = ProcessInfoReader.path(pid)
                guard !exe.isEmpty, Self.isUserProcess(exe), !appRoots.contains(where: { exe.hasPrefix($0) }), !exe.contains(".xpc/"), !exe.contains(".appex/"), !exe.contains("/Library/LoginItems/") else { continue }
                let args = ProcessInfoReader.args(pid)
                if Self.isConcierge(exe) || args.contains(where: Self.isConcierge) { continue }
                let name = URL(fileURLWithPath: exe).lastPathComponent
                out.append(StopTarget(id: "bg:\(pid)", kind: .background, name: Self.prettyProcess(name, args), detail: Self.describe(exe: exe, args: args),
                                      pids: [pid], bundleID: nil, bundle: Self.appBundle(exe), label: nil, checked: true))
            }
            for i in out.indices { out[i].memory = out[i].pids.reduce(0) { $0 + ProcessInfoReader.footprint($1) } }
            out.sort { ($0.kind.rawValue, $1.memory) < ($1.kind.rawValue, $0.memory) }
            let result = out
            await MainActor.run {
                let previous = Dictionary(uniqueKeysWithValues: self.targets.map { ($0.id, $0.checked) })
                self.targets = result.map { var t = $0; if let c = previous[t.id] { t.checked = c }; return t }
            }
        }
    }

    func toggle(_ id: String) {
        guard let i = targets.firstIndex(where: { $0.id == id }) else { return }
        targets[i].checked.toggle()
    }

    func stopChecked() {
        let chosen = targets.filter(\.checked)
        guard !chosen.isEmpty, !stopping else { return }
        stopping = true
        stubborn = []
        let uid = getuid()
        Task {
            for t in chosen {
                switch t.kind {
                case .app, .menuApp:
                    NSRunningApplication(processIdentifier: t.pids[0])?.terminate()
                case .agent:
                    if let label = t.label { await Task.detached { PowerControl.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"]) }.value }
                case .background:
                    for p in t.pids { kill(p, SIGTERM) }
                }
            }
            try? await Task.sleep(for: .seconds(3))
            for t in chosen where t.kind == .background { for p in t.pids where kill(p, 0) == 0 { kill(p, SIGKILL) } }
            try? await Task.sleep(for: .seconds(3))
            let left = chosen.filter { t in t.pids.contains { kill($0, 0) == 0 } && t.kind != .background }
            stubborn = left
            let done = chosen.count - left.count
            lastResult = left.isEmpty ? "Zatrzymane: \(done)" : "Zatrzymane: \(done), nie chce się zamknąć: \(left.count)"
            stopping = false
            scan()
        }
    }

    func force(_ t: StopTarget) {
        for p in t.pids {
            if let app = NSRunningApplication(processIdentifier: p) { app.forceTerminate() } else { kill(p, SIGKILL) }
        }
        stubborn.removeAll { $0.id == t.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.scan() }
    }

    func quit(_ app: AppUsage) {
        let apps = NSWorkspace.shared.runningApplications.filter { a in app.pids.contains(a.processIdentifier) || (app.bundle != nil && a.bundleURL == app.bundle) }
        if apps.isEmpty { for p in app.pids where p != ProcessInfo.processInfo.processIdentifier { kill(p, SIGTERM) } }
        else { apps.forEach { $0.terminate() } }
    }

    // MARK: naming

    nonisolated static func isUserProcess(_ exe: String) -> Bool {
        for bad in ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/bin/", "/Library/Apple/", "/private/var/", "/Library/PrivilegedHelperTools/"] where exe.hasPrefix(bad) { return false }
        if exe.hasPrefix("/usr/bin/") { return interpreters.contains(URL(fileURLWithPath: exe).lastPathComponent.replacingOccurrences(of: #"[0-9.]+$"#, with: "", options: .regularExpression)) }
        return true
    }

    nonisolated static func isConcierge(_ path: String) -> Bool {
        path.contains("Gzowo Concierge.app") || path.contains("/.gzowo-concierge/")
    }

    nonisolated static func appBundle(_ exe: String) -> URL? {
        guard let r = exe.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(exe[..<r.lowerBound]) + ".app")
    }

    nonisolated static func pretty(label: String) -> String {
        var parts = label.split(separator: ".").map(String.init)
        if parts.count > 2, ["fun", "com", "io", "ai", "org", "net", "application"].contains(parts[0]) { parts.removeFirst(2) }
        let s = parts.joined(separator: " ").replacingOccurrences(of: "-", with: " ")
        return s.isEmpty ? label : s.prefix(1).uppercased() + s.dropFirst()
    }

    nonisolated static func prettyProcess(_ name: String, _ args: [String]) -> String {
        let base = name.replacingOccurrences(of: #"[0-9.]+$"#, with: "", options: .regularExpression)
        if interpreters.contains(base) || ["node", "bun", "deno"].contains(base), let script = args.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            return "\(base) \(URL(fileURLWithPath: script).lastPathComponent)"
        }
        return name
    }

    nonisolated static func describe(exe: String, args: [String]) -> String {
        let home = NSHomeDirectory()
        if let script = args.dropFirst().first(where: { $0.hasPrefix("/") && !$0.hasPrefix("-") }) {
            return script.replacingOccurrences(of: home, with: "~")
        }
        return exe.replacingOccurrences(of: home, with: "~")
    }
}
