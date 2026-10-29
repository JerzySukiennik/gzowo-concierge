// Gzowo Concierge for macOS - sends a WhatsApp message the way Jurek would: opens WhatsApp, searches the chat by name, pastes the text into the composer and presses Return.
import AppKit
import ApplicationServices

@MainActor
enum WhatsAppSender {
    static let bundleID = "net.whatsapp.WhatsApp"

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func send(query: String, target: String, text: String, dryRun: Bool) async throws -> String {
        guard AXIsProcessTrusted() else { throw Failure("Apka Concierge nie ma uprawnienia Dostępność, więc nie mogę sterować WhatsAppem.") }
        if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
            throw Failure("Mac jest zablokowany, więc nie mogę wysłać.")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure("Pusta wiadomość.") }
        let previous = NSWorkspace.shared.frontmostApplication
        let app = try await launch()
        defer { if let previous, previous.bundleIdentifier != bundleID { front(previous) } }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 2)
        guard await waitFor(8, { window(ax) != nil }) else { throw Failure("WhatsApp nie otworzył okna.") }
        front(app)
        guard await waitFor(3, { frontmost(app) }) else { throw Failure("Nie udało się przełączyć na WhatsAppa, nic nie wysłałem.") }
        try await pause(0.3)

        if let search = menuItem(ax, menu: "File", suffix: "Search") { AXUIElementPerformAction(search, kAXPressAction as CFString) } else { try keys(app, 3, .maskCommand) }
        try await pause(0.5)
        try keys(app, 0, .maskCommand)
        try keys(app, 51)
        try await paste(app, query)
        var button: AXUIElement?
        _ = await waitFor(5) { button = findChat(ax, target); return button != nil }
        guard let button else { try? keys(app, 53); throw Failure("Nie znalazłem w WhatsAppie czatu „\(target)”.") }
        AXUIElementPerformAction(button, kAXPressAction as CFString)

        var composer: AXUIElement?
        var clicked = false
        _ = await waitFor(4) {
            if let c = focusedComposer(ax) { composer = c; return true }
            if !clicked, let c = find(ax, role: kAXTextAreaRole) { clicked = true; try? click(app, c) }
            return false
        }
        guard let composer else { throw Failure("Czat „\(target)” się otworzył, ale nie widzę pola wiadomości.") }
        guard (value(composer) ?? "").isEmpty else { throw Failure("W czacie „\(target)” jest niewysłany szkic, nie ruszam go.") }
        try await paste(app, text)
        guard await waitFor(3, { same(value(composer) ?? "", text) }) else {
            try? clear(app)
            throw Failure("Tekst nie wkleił się poprawnie, nic nie wysłałem.")
        }
        if dryRun {
            try clear(app)
            return "dry run ok: \(target)"
        }
        try keys(app, 36)
        guard await waitFor(4, { (value(composer) ?? "").isEmpty }) else { throw Failure("Nacisnąłem Enter, ale wiadomość została w polu. Sprawdź WhatsAppa.") }
        return "sent"
    }

    private static func launch() async throws -> NSRunningApplication {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { return running }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { throw Failure("Na tym Macu nie ma WhatsAppa.") }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        return try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private static func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
    }

    private static func waitFor(_ seconds: Double, _ check: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if check() { return true }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return check()
    }

    private static func frontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private static func front(_ app: NSRunningApplication) {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private static func keys(_ app: NSRunningApplication, _ code: CGKeyCode, _ flags: CGEventFlags = []) throws {
        guard frontmost(app) else { throw Failure("WhatsApp przestał być na wierzchu, przerwałem i nic nie wysłałem.") }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    private static func click(_ app: NSRunningApplication, _ el: AXUIElement) throws {
        guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute) else { return }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0, frontmost(app) else { throw Failure("WhatsApp przestał być na wierzchu, przerwałem i nic nie wysłałem.") }
        let at = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let back = CGEvent(source: nil)?.location
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        if let back { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)?.post(tap: .cghidEventTap) }
    }

    private static func clear(_ app: NSRunningApplication) throws {
        try keys(app, 0, .maskCommand)
        try keys(app, 51)
    }

    private static func paste(_ app: NSRunningApplication, _ text: String) async throws {
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let d = item.data(forType: type) { copy.setData(d, forType: type) } }
            return copy
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        defer {
            pb.clearContents()
            if !saved.isEmpty { pb.writeObjects(saved) }
        }
        try keys(app, 9, .maskCommand)
        try await pause(0.6)
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String {
        attr(el, name) as? String ?? ""
    }

    private static func value(_ el: AXUIElement) -> String? {
        attr(el, kAXValueAttribute) as? String
    }

    private static func window(_ ax: AXUIElement) -> AXUIElement? {
        (attr(ax, kAXWindowsAttribute) as? [AXUIElement])?.first
    }

    private static func clean(_ s: String) -> String {
        let hidden = CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        return String(String.UnicodeScalarView(s.unicodeScalars.filter { !hidden.contains($0) })).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func label(_ s: String) -> String {
        let c = clean(s).lowercased()
        let digits = c.filter(\.isNumber)
        return digits.count >= 6 && c.allSatisfy({ $0.isNumber || " +,-()".contains($0) }) ? digits : c
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        let norm = { (s: String) in s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{2028}", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        return norm(a) == norm(b)
    }

    private static func menuItem(_ ax: AXUIElement, menu: String, suffix: String) -> AXUIElement? {
        guard let bar = attr(ax, kAXMenuBarAttribute) else { return nil }
        let barEl = bar as! AXUIElement
        guard let top = children(barEl).first(where: { clean(string($0, kAXTitleAttribute)) == menu }), let list = children(top).first else { return nil }
        return children(list).first { clean(string($0, kAXTitleAttribute)).hasSuffix(suffix) }
    }

    private static func findChat(_ ax: AXUIElement, _ target: String) -> AXUIElement? {
        guard let win = window(ax) else { return nil }
        let want = label(target)
        var stack = [win], seen = 0
        while let el = stack.popLast(), seen < 4000 {
            seen += 1
            if string(el, kAXRoleAttribute) == kAXButtonRole {
                let kids = children(el)
                let names = [string(el, kAXDescriptionAttribute)] + kids.prefix(1).map { string($0, kAXDescriptionAttribute) }
                if names.contains(where: { !$0.isEmpty && label($0) == want }) { return el }
                continue
            }
            stack.append(contentsOf: children(el).reversed())
        }
        return nil
    }

    private static func find(_ ax: AXUIElement, role: String) -> AXUIElement? {
        guard let win = window(ax) else { return nil }
        var stack = [win], seen = 0
        while let el = stack.popLast(), seen < 4000 {
            seen += 1
            if string(el, kAXRoleAttribute) == role { return el }
            stack.append(contentsOf: children(el).reversed())
        }
        return nil
    }

    private static func focusedComposer(_ ax: AXUIElement) -> AXUIElement? {
        guard let f = attr(ax, kAXFocusedUIElementAttribute) else { return nil }
        let el = f as! AXUIElement
        return string(el, kAXRoleAttribute) == kAXTextAreaRole ? el : nil
    }
}
