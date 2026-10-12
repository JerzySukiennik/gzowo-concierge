// Gzowo Concierge for macOS - Touch Bar assistant: a small icon in the Control Strip that expands into a text field; typed text goes to Concierge and the reply shows on the bar (uses private DFRFoundation/NSTouchBar calls, disabled quietly if they are missing).
import AppKit
import Combine

extension NSTouchBarItem.Identifier {
    static let conciergeStrip = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.strip")
    static let conciergeClose = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.close")
    static let conciergeText = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.text")
    static let conciergeOpen = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.open")
}

private final class CatcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TouchBarAssistant: NSObject, NSTouchBarDelegate, NSTextFieldDelegate {
    private let model: NotchModel
    private var bar: NSTouchBar?
    private var stripItem: NSCustomTouchBarItem?
    private var label: NSTextField?
    private var catcher: CatcherPanel?
    private var field: NSTextField?
    private var previousApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var presented = false
    private var showingReply = false
    private var caretOn = true
    private var caretTimer: Timer?
    private var typed = ""
    private let debug = ProcessInfo.processInfo.environment["CONCIERGE_TB_TEST"] != nil
    private let key = "touchBarEnabled"

    private typealias Present = @convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void
    private typealias Dismiss = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
    private typealias Presence = @convention(c) (NSString, Bool) -> Void
    private typealias CloseBox = @convention(c) (Bool) -> Void

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key); newValue ? install() : remove() }
    }

    init(model: NotchModel) {
        self.model = model
        super.init()
        Publishers.CombineLatest4(model.$reply, model.$streaming, model.$errorText, model.$steps).sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshReply() }
        }.store(in: &cancellables)
    }

    private static var dfr: UnsafeMutableRawPointer? = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

    func start() {
        if enabled { install() }
        if debug {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.present() }
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
                self?.trace("keyDown \(e.characters ?? "?") window=\(e.window.map { String(describing: type(of: $0)) } ?? "nil") key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil") responder=\(String(describing: NSApp.keyWindow?.firstResponder).prefix(40))")
                return e
            }
        }
    }

    private func trace(_ s: String) {
        guard debug else { return }
        let line = "\(Date()) \(s)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/tb-debug.log") { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(toFile: "/tmp/tb-debug.log", atomically: true, encoding: .utf8) }
    }

    private func install() {
        guard stripItem == nil, let h = Self.dfr, let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        let item = NSCustomTouchBarItem(identifier: .conciergeStrip)
        let button = NSButton(image: Self.stripImage(), target: self, action: #selector(tapped))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        item.view = button
        _ = (NSTouchBarItem.self as AnyObject).perform(NSSelectorFromString("addSystemTrayItem:"), with: item)
        unsafeBitCast(sym, to: Presence.self)(NSTouchBarItem.Identifier.conciergeStrip.rawValue as NSString, true)
        stripItem = item
    }

    private func remove() {
        close()
        guard let h = Self.dfr, let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        unsafeBitCast(sym, to: Presence.self)(NSTouchBarItem.Identifier.conciergeStrip.rawValue as NSString, false)
        if let item = stripItem { _ = (NSTouchBarItem.self as AnyObject).perform(NSSelectorFromString("removeSystemTrayItem:"), with: item) }
        stripItem = nil
    }

    private static func stripImage() -> NSImage {
        let size = NSSize(width: 44, height: 30)
        return NSImage(size: size, flipped: false) { rect in
            let d: CGFloat = 20
            let circle = NSRect(x: (rect.width - d) / 2, y: (rect.height - d) / 2, width: d, height: d)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: circle).fill()
            NSColor.black.setFill()
            for dx in [-2.6, 2.6] {
                NSBezierPath(roundedRect: NSRect(x: circle.midX + dx - 1.1, y: circle.midY - 2.6, width: 2.2, height: 5.4), xRadius: 1.1, yRadius: 1.1).fill()
            }
            return true
        }
    }

    @objc private func tapped() {
        presented ? close() : present()
    }

    private func present() {
        guard !presented, let sym = class_getClassMethod(NSTouchBar.self, NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")) else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let b = NSTouchBar()
        b.delegate = self
        b.defaultItemIdentifiers = [.conciergeClose, .conciergeText, .conciergeOpen]
        bar = b
        showingReply = false
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        unsafeBitCast(method_getImplementation(sym), to: Present.self)(NSTouchBar.self, sel, b, 1, NSTouchBarItem.Identifier.conciergeStrip.rawValue as NSString)
        presented = true
        typed = ""
        openCatcher()
        updateLabel()
        caretTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.caretOn.toggle(); self?.updateLabel() }
        }
    }

    private func close() {
        guard presented else { return }
        presented = false
        caretTimer?.invalidate(); caretTimer = nil
        if let b = bar, let m = class_getClassMethod(NSTouchBar.self, NSSelectorFromString("dismissSystemModalTouchBar:")) {
            unsafeBitCast(method_getImplementation(m), to: Dismiss.self)(NSTouchBar.self, NSSelectorFromString("dismissSystemModalTouchBar:"), b)
        }
        bar = nil
        label = nil
        catcher?.orderOut(nil)
        catcher = nil
        field = nil
        if !(NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }) { NSApp.hide(nil) }
        previousApp?.activate(options: [])
        previousApp = nil
    }

    private func openCatcher() {
        let p = CatcherPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 24), styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.alphaValue = 0
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        f.delegate = self
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        p.contentView = f
        p.setFrameOrigin(NSPoint(x: 0, y: 0))
        catcher = p
        field = f
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(f)
        for delay in [0.12, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.presented, let p = self.catcher, let f = self.field else { return }
                if !p.isKeyWindow || p.firstResponder == nil || !(p.firstResponder is NSTextView) {
                    NSApp.activate(ignoringOtherApps: true)
                    p.makeKeyAndOrderFront(nil)
                    p.makeFirstResponder(f)
                }
                self.trace("key window: \(p.isKeyWindow) responder: \(String(describing: p.firstResponder)) active: \(NSApp.isActive)")
            }
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .conciergeClose:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Zamknij") ?? NSImage(), target: self, action: #selector(tapped))
            return item
        case .conciergeText:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let l = NSTextField(labelWithString: "")
            l.font = .systemFont(ofSize: 15, weight: .medium)
            l.lineBreakMode = .byTruncatingTail
            l.maximumNumberOfLines = 1
            l.alignment = .left
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: 520).isActive = true
            label = l
            item.view = l
            updateLabel()
            return item
        case .conciergeOpen:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(image: NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: "Otwórz w wyspie") ?? NSImage(), target: self, action: #selector(openFull))
            return item
        default:
            return nil
        }
    }

    @objc private func openFull() {
        close()
        model.expandRequest()
    }

    private func updateLabel() {
        guard let label else { return }
        if showingReply {
            let line: String
            if model.streaming && model.reply.isEmpty { line = model.steps.last ?? "Myślę…" }
            else if !model.errorText.isEmpty { line = model.errorText }
            else { line = NotchText.plain(model.reply).replacingOccurrences(of: "\n", with: " ") }
            label.stringValue = line.isEmpty ? "…" : line
            label.textColor = model.errorText.isEmpty ? .white : NSColor(red: 1, green: 0.45, blue: 0.43, alpha: 1)
            return
        }
        if typed.isEmpty {
            label.stringValue = "Napisz do Concierge" + (caretOn ? "  ▏" : "")
            label.textColor = NSColor.white.withAlphaComponent(0.5)
        } else {
            label.stringValue = typed + (caretOn ? "▏" : "")
            label.textColor = .white
        }
    }

    private func refreshReply() {
        guard presented, showingReply else { return }
        updateLabel()
    }

    // MARK: typing

    func controlTextDidChange(_ obj: Notification) {
        typed = (obj.userInfo?["NSFieldEditor"] as? NSText)?.string ?? field?.stringValue ?? ""
        trace("typed: \(typed)")
        showingReply = false
        updateLabel()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            trace("enter: \(text)")
            guard !text.isEmpty, !model.streaming else { return true }
            textView.string = ""
            typed = ""
            showingReply = true
            model.agentMode = false
            model.text = text
            model.send()
            updateLabel()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        return false
    }
}
