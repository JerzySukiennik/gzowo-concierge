// Gzowo Concierge for macOS - offline mode helpers: internet reachability, the island's local-model switch, and the selected text or clipboard handed to the local model.
import AppKit
import Network

final class Connectivity: @unchecked Sendable {
    static let shared = Connectivity()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var up = true
    var onChange: (@Sendable (Bool) -> Void)?

    var online: Bool { lock.lock(); defer { lock.unlock() }; return up }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let now = path.status == .satisfied
            self.lock.lock(); let changed = now != self.up; self.up = now; self.lock.unlock()
            if changed { self.onChange?(now) }
        }
        monitor.start(queue: DispatchQueue(label: "fun.gzowo.concierge.net"))
    }
}

enum LocalMode {
    static let key = ProcessInfo.processInfo.environment["CONCIERGE_TB_TEST"] == nil ? "localMode" : "localModeTest"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }
    static var active: Bool { enabled || !Connectivity.shared.online }
}

struct LocalInfo: Equatable {
    var installed = false
    var loading = false
    var ready = false
    var model = ""
    var dictation = false
    var problem = ""
}

struct Attachment: Equatable {
    var text: String
    var app: String
    var chars: Int { text.count }
}

enum ContextGrabber {
    private static let chromium: Set<String> = ["com.brave.Browser", "com.google.Chrome", "com.microsoft.edgemac", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "company.thebrowser.Browser"]
    static let limit = 4000

    @MainActor
    static func selection() -> Attachment? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.25)
        if let id = app.bundleIdentifier, chromium.contains(id) { AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue) }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success, let s = sel as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Attachment(text: String(t.prefix(limit)), app: app.localizedName ?? "")
    }

    static func clipboard() -> Attachment? {
        guard let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return Attachment(text: String(s.prefix(limit)), app: "")
    }

    static func mentionsClipboard(_ text: String) -> Bool {
        text.range(of: "(schowk|skopiowa|wklejo|clipboard)", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
