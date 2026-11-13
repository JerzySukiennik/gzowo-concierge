// Gzowo Concierge for macOS - stay-awake mode (the Mac never sleeps and the open screen never dims, with the lid shut it keeps working with the screen off, until switched off) and turning the screen off on demand.
import AppKit
import IOKit.pwr_mgt

@MainActor
final class PowerControl: ObservableObject {
    @Published private(set) var lidMode = false
    @Published private(set) var working = false
    @Published private(set) var problem = ""
    private var systemHold: IOPMAssertionID = 0
    private var displayHold: IOPMAssertionID = 0
    private var screenForcedOff = false
    private let ruleFile = "/etc/sudoers.d/gzowo-concierge-clamshell"

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.screenForcedOff = false
                if self.lidMode { self.hold() }
            }
        }
        refresh()
    }

    func refresh() {
        screenForcedOff = false
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
                if !success { self.problem = "Nie udało się przełączyć trybu." }
            }
        }
    }

    func screenOff() {
        screenForcedOff = true
        drop(&displayHold)
        Task.detached { _ = Self.run("/usr/bin/pmset", ["displaysleepnow"]) }
    }

    private func hold() {
        if systemHold == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Concierge: nie usypiaj" as CFString, &systemHold)
        }
        if displayHold == 0, !screenForcedOff {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Concierge: nie gaś ekranu" as CFString, &displayHold)
        }
    }

    private func release() {
        drop(&systemHold)
        drop(&displayHold)
    }

    private func drop(_ id: inout IOPMAssertionID) {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
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
        let script = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges with prompt \"Concierge zapisze regułę, która pozwala tylko włączać i wyłączać tryb nieusypiania bez hasła. Hasło jest potrzebne tylko ten jeden raz.\""
        return run("/usr/bin/osascript", ["-e", script]) == 0
    }
}
