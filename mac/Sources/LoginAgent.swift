// Gzowo Concierge for macOS - start at login as island only: a per-user LaunchAgent that runs the app with --island.
import Foundation

enum LoginAgent {
    private static let label = "fun.gzowo.concierge.mac"
    private static let key = "launchAtLogin"
    private static var plistURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key); sync() }
    }

    static var launchedAsIsland: Bool { CommandLine.arguments.contains("--island") }

    static func sync() {
        let fm = FileManager.default
        guard enabled else { try? fm.removeItem(at: plistURL); return }
        guard let exe = Bundle.main.executablePath, exe.hasPrefix("/Applications/") || exe.contains("/Applications/") else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe, "--island"],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        if let current = try? Data(contentsOf: plistURL), current == data { return }
        try? fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: plistURL, options: .atomic)
    }
}
