// Gzowo Concierge for macOS - closed-lid mode (the Mac keeps working with the lid shut and the screen off, until switched off) and turning the screen off on demand.
import AppKit
import IOKit.pwr_mgt

@MainActor
final class PowerControl: ObservableObject {
    @Published private(set) var lidMode = false
    @Published private(set) var working = false
    @Published private(set) var problem = ""
    private var assertion: IOPMAssertionID = 0
    private let ruleFile = "/etc/sudoers.d/gzowo-concierge-clamshell"

    init() { refresh() }

    func refresh() {
        let disabled = Self.sleepDisabled()
        if disabled != lidMode { lidMode = disabled }
        disabled ? hold() : release()
    }

    func toggleLid() { setLid(!lidMode) }

    func setLid(_ on: Bool) {
        guard !working else { return }
        working = true
        problem = ""
        Task.detached { [ruleFile] in
            var ok = Self.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", on ? "1" : "0"]) == 0
            if !ok { ok = Self.installRule(ruleFile) && Self.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", on ? "1" : "0"]) == 0 }
            let now = Self.sleepDisabled()
            let success = ok
            await MainActor.run {
                self.working = false
                self.lidMode = now
                now ? self.hold() : self.release()
                if !success { self.problem = "Nie udało się przełączyć trybu klapy." }
            }
        }
    }

    func screenOff() {
        Task.detached { _ = Self.run("/usr/bin/pmset", ["displaysleepnow"]) }
    }

    private func hold() {
        guard assertion == 0 else { return }
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Concierge: tryb klapy" as CFString, &assertion)
    }

    private func release() {
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
    }

    nonisolated static func sleepDisabled() -> Bool {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").contains { $0.contains("SleepDisabled") && $0.trimmingCharacters(in: .whitespaces).hasSuffix("1") }
    }

    @discardableResult
    nonisolated static func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private nonisolated static func installRule(_ path: String) -> Bool {
        let user = NSUserName()
        guard user.range(of: "^[a-z_][a-z0-9_-]*$", options: .regularExpression) != nil else { return false }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
        let shell = "printf '%s\\n' '\(rule)' > /tmp/gzowo-clamshell && /usr/sbin/visudo -cf /tmp/gzowo-clamshell && /usr/bin/install -m 0440 -o root -g wheel /tmp/gzowo-clamshell \(path); rm -f /tmp/gzowo-clamshell"
        let script = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges with prompt \"Concierge zapisze regułę, która pozwala tylko włączać i wyłączać tryb klapy bez hasła. Hasło jest potrzebne tylko ten jeden raz.\""
        return run("/usr/bin/osascript", ["-e", script]) == 0
    }
}
