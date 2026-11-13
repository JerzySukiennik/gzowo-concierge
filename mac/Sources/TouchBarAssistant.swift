// Gzowo Concierge for macOS - Touch Bar assistant: an icon in the Control Strip opens a full-width bar to type to Concierge; the reply scrolls seamlessly under a finger (private DFRFoundation/NSTouchBar calls, disabled quietly if missing).
import AppKit
import Combine

extension NSTouchBarItem.Identifier {
    static let conciergeStrip = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.strip")
    static let conciergeClose = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.close")
    static let conciergeText = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.text")
    static let conciergeLive = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.live")
    static let conciergeOpen = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.open")
    static let conciergeLock = NSTouchBarItem.Identifier("fun.gzowo.concierge.touchbar.lock")
}

private final class CatcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BarText: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }
    var placeholder = "Napisz do Concierge"
    var caret = true { didSet { if caret != oldValue { needsDisplay = true } } }
    var status = "" { didSet { if status != oldValue { needsDisplay = true } } }
    private let font = NSFont.systemFont(ofSize: 15, weight: .medium)

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        let empty = text.isEmpty
        let shown = empty ? (status.isEmpty ? placeholder : status) : text
        let color = empty ? NSColor.white.withAlphaComponent(0.45) : NSColor.white
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: shown, attributes: attrs)
        let w = ceil(str.size().width)
        let caretGap: CGFloat = empty ? 0 : 2
        let room = bounds.width - 12
        let x: CGFloat = empty ? (status.isEmpty ? 7 : 0) : (w + caretGap > room ? room - w - caretGap : 0)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).setClip()
        str.draw(at: NSPoint(x: x, y: (bounds.height - str.size().height) / 2))
        if caret && status.isEmpty {
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: empty ? 0 : x + w + caretGap, y: (bounds.height - 18) / 2, width: 2, height: 18), xRadius: 1, yRadius: 1).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        if x < 0 {
            let fade = NSGradient(starting: .black, ending: NSColor.black.withAlphaComponent(0))
            fade?.draw(in: NSRect(x: 0, y: 0, width: 26, height: bounds.height), angle: 0)
        }
    }
}

private final class ChunkView: NSScrubberItemView {
    var string = NSAttributedString() { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let h = string.size().height
        string.draw(at: NSPoint(x: 0, y: (bounds.height - h) / 2))
    }
}

@MainActor
final class TouchBarAssistant: NSObject, NSTouchBarDelegate, NSTextFieldDelegate, NSScrubberDataSource, NSScrubberFlowLayoutDelegate {
    private let model: NotchModel
    private var bar: NSTouchBar?
    private var stripItem: NSCustomTouchBarItem?
    private var textView: BarText?
    private var scrubber: NSScrubber?
    private var chunks: [NSAttributedString] = []
    private var chunkText = ""
    private let replyFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    private var catcher: CatcherPanel?
    private var field: NSTextField?
    private var previousApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var presented = false
    private var madeRegular = false
    private var showingReply = false
    private var caretTimer: Timer?
    private var typed = ""
    private var draft = ""
    private let debug = ProcessInfo.processInfo.environment["CONCIERGE_TB_TEST"] != nil
    private let key = "touchBarEnabled"
    var openLive: () -> Void = {}

    private typealias Present = @convention(c) (AnyObject, Selector, NSTouchBar, Int, NSString) -> Void
    private typealias Dismiss = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
    private typealias Presence = @convention(c) (NSString, Bool) -> Void

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
        guard debug else { return }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.tb-test-reply"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.model.reply = String(repeating: "To jest bardzo długa odpowiedź Concierge, która nie mieści się w jednej linii Touch Bara. ", count: 6)
                self.showingReply = true
                self.update()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.tb-test-type"), object: nil, queue: .main) { [weak self] n in
            Task { @MainActor in
                guard let self else { return }
                self.typed = (n.object as? String) ?? "Jaka jest pogoda jutro w Warszawie"
                self.showingReply = false
                self.update()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("fun.gzowo.concierge.tb-test"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.presented == true ? self?.close() : self?.present() }
        }
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
        startHeartbeat()
    }

    private var lastPolicy: NSApplication.ActivationPolicy = .regular
    private var heartbeat: Timer?

    private func startHeartbeat() {
        heartbeat?.invalidate()
        lastPolicy = NSApp.activationPolicy()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heal() }
        }
    }

    private func heal() {
        guard enabled, let h = Self.dfr, let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        let policy = NSApp.activationPolicy()
        if policy != lastPolicy, !presented {
            lastPolicy = policy
            stripItem = nil
            install()
            return
        }
        unsafeBitCast(sym, to: Presence.self)(NSTouchBarItem.Identifier.conciergeStrip.rawValue as NSString, true)
    }

    func policyChanged() {
        guard enabled, !presented else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.lastPolicy = NSApp.activationPolicy()
            self.stripItem = nil
            self.install()
        }
    }

    private func remove() {
        close()
        guard let h = Self.dfr, let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        unsafeBitCast(sym, to: Presence.self)(NSTouchBarItem.Identifier.conciergeStrip.rawValue as NSString, false)
        if let item = stripItem { _ = (NSTouchBarItem.self as AnyObject).perform(NSSelectorFromString("removeSystemTrayItem:"), with: item) }
        stripItem = nil
        heartbeat?.invalidate(); heartbeat = nil
    }

    private static func stripImage() -> NSImage {
        NSImage(size: NSSize(width: 44, height: 30), flipped: false) { rect in
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

    @objc private func tapped() { presented ? close() : present() }

    private var lockBar: NSTouchBar?

    func lock(_ on: Bool) {
        if on {
            guard lockBar == nil, let sym = class_getClassMethod(NSTouchBar.self, NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")) else { return }
            if presented { close() }
            let b = NSTouchBar()
            b.delegate = self
            b.defaultItemIdentifiers = [.conciergeLock]
            lockBar = b
            unsafeBitCast(method_getImplementation(sym), to: Present.self)(NSTouchBar.self, NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"), b, 1, NSTouchBarItem.Identifier.conciergeStrip.rawValue as NSString)
        } else if let b = lockBar, let m = class_getClassMethod(NSTouchBar.self, NSSelectorFromString("dismissSystemModalTouchBar:")) {
            unsafeBitCast(method_getImplementation(m), to: Dismiss.self)(NSTouchBar.self, NSSelectorFromString("dismissSystemModalTouchBar:"), b)
            lockBar = nil
        }
    }

    private func present() {
        guard !presented, let sym = class_getClassMethod(NSTouchBar.self, NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")) else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let b = NSTouchBar()
        b.delegate = self
        b.defaultItemIdentifiers = [.conciergeClose, .conciergeText, .conciergeLive, .conciergeOpen]
        bar = b
        typed = draft
        showingReply = draft.isEmpty && model.hasReply
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        unsafeBitCast(method_getImplementation(sym), to: Present.self)(NSTouchBar.self, sel, b, 1, NSTouchBarItem.Identifier.conciergeStrip.rawValue as NSString)
        presented = true
        openCatcher()
        update()
        caretTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let t = self?.textView else { return }; t.caret.toggle() }
        }
    }

    private func close() {
        guard presented else { return }
        presented = false
        draft = typed
        caretTimer?.invalidate(); caretTimer = nil
        if let b = bar, let m = class_getClassMethod(NSTouchBar.self, NSSelectorFromString("dismissSystemModalTouchBar:")) {
            unsafeBitCast(method_getImplementation(m), to: Dismiss.self)(NSTouchBar.self, NSSelectorFromString("dismissSystemModalTouchBar:"), b)
        }
        bar = nil
        textView = nil
        scrubber = nil
        catcher?.orderOut(nil)
        catcher = nil
        field = nil
        if !(NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }) { NSApp.hide(nil) }
        previousApp?.activate(options: [])
        previousApp = nil
        if madeRegular {
            madeRegular = false
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { NSApp.setActivationPolicy(.accessory) }
            lastPolicy = NSApp.activationPolicy()
        }
    }

    private static func sendWindowsBack() {
        for w in NSApp.windows where w.isVisible && w.canBecomeMain { w.orderBack(nil) }
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
        f.stringValue = typed
        p.contentView = f
        p.setFrameOrigin(NSPoint(x: 0, y: 0))
        catcher = p
        field = f
        let wasOurs = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular); madeRegular = true }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(f)
        (f.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: (typed as NSString).length, length: 0))
        if !wasOurs { for delay in [0.0, 0.05, 0.15, 0.4] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Self.sendWindowsBack() } } }
        for delay in [0.12, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.presented, let p = self.catcher, let f = self.field else { return }
                if !p.isKeyWindow || p.firstResponder == nil || !(p.firstResponder is NSTextView) {
                    NSApp.activate(ignoringOtherApps: true)
                    p.makeKeyAndOrderFront(nil)
                    p.makeFirstResponder(f)
                }
            }
        }
    }

    private func symbolButton(_ symbol: String, _ label: String, _ action: Selector, width: CGFloat = 64) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)) ?? NSImage(), target: self, action: action)
        b.bezelColor = NSColor(white: 0.22, alpha: 1)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: width).isActive = true
        return b
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        switch identifier {
        case .conciergeLock:
            let l = NSTextField(labelWithString: "Czyszczenie klawiatury, Touch Bar jest zablokowany")
            l.font = .systemFont(ofSize: 14, weight: .medium)
            l.textColor = NSColor.white.withAlphaComponent(0.6)
            item.view = l
        case .conciergeClose:
            item.view = symbolButton("xmark", "Zamknij", #selector(tapped), width: 56)
        case .conciergeLive:
            item.view = symbolButton("waveform", "Rozmowa na żywo", #selector(live))
        case .conciergeOpen:
            item.view = symbolButton("arrow.up.left.and.arrow.down.right", "Otwórz w wyspie", #selector(openFull))
        case .conciergeText:
            let box = NSView()
            box.translatesAutoresizingMaskIntoConstraints = false
            let t = BarText()
            t.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(t)
            let sc = NSScrubber()
            sc.register(ChunkView.self, forItemIdentifier: NSUserInterfaceItemIdentifier("chunk"))
            let flow = NSScrubberFlowLayout()
            flow.itemSpacing = 0
            sc.scrubberLayout = flow
            sc.dataSource = self
            sc.delegate = self
            sc.mode = .free
            sc.showsAdditionalContentIndicators = true
            sc.isContinuous = false
            sc.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(sc)
            NSLayoutConstraint.activate([
                box.widthAnchor.constraint(equalToConstant: 756), box.heightAnchor.constraint(equalToConstant: 30),
                t.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10), t.trailingAnchor.constraint(equalTo: box.trailingAnchor), t.topAnchor.constraint(equalTo: box.topAnchor), t.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                sc.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10), sc.trailingAnchor.constraint(equalTo: box.trailingAnchor), sc.topAnchor.constraint(equalTo: box.topAnchor), sc.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            ])
            textView = t
            scrubber = sc
            item.view = box
            update()
        default:
            return nil
        }
        return item
    }

    @objc private func openFull() {
        close()
        model.expandRequest()
    }

    @objc private func live() {
        close()
        openLive()
    }

    private func update() {
        guard let textView else { return }
        if showingReply, model.hasReply, !(model.streaming && model.reply.isEmpty) || !model.errorText.isEmpty {
            let error = !model.errorText.isEmpty
            let line = error ? model.errorText : NotchText.plain(model.reply).replacingOccurrences(of: "\n", with: " ")
            setChunks(line, color: error ? NSColor(red: 1, green: 0.45, blue: 0.43, alpha: 1) : .white)
            textView.isHidden = true
            scrubber?.isHidden = false
            return
        }
        textView.isHidden = false
        scrubber?.isHidden = true
        textView.status = showingReply && model.streaming ? (model.steps.last.map { $0 + "…" } ?? "Myślę…") : ""
        textView.text = showingReply ? "" : typed
        textView.caret = true
    }

    private func setChunks(_ text: String, color: NSColor) {
        let line = text.count > 700 ? String(text.prefix(700)).trimmingCharacters(in: .whitespaces) + "…" : text
        let key = line + color.description
        guard key != chunkText else { return }
        chunkText = key
        chunks = [NSAttributedString(string: line + "   ", attributes: [.font: replyFont, .foregroundColor: color])]
        scrubber?.reloadData()
    }

    func numberOfItems(for scrubber: NSScrubber) -> Int { chunks.count }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let v = scrubber.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("chunk"), owner: nil) as? ChunkView ?? ChunkView()
        v.string = chunks[index]
        return v
    }

    func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout, sizeForItemAt itemIndex: Int) -> NSSize {
        NSSize(width: ceil(chunks[itemIndex].boundingRect(with: NSSize(width: 100_000, height: 30), options: [.usesLineFragmentOrigin]).width) + 8, height: 30)
    }

    private func refreshReply() {
        guard presented, showingReply else { return }
        update()
    }

    func controlTextDidChange(_ obj: Notification) {
        typed = (obj.userInfo?["NSFieldEditor"] as? NSText)?.string ?? field?.stringValue ?? ""
        showingReply = false
        textView?.caret = true
        update()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !model.streaming else { return true }
            textView.string = ""
            typed = ""
            draft = ""
            showingReply = true
            model.agentMode = false
            model.text = text
            model.send()
            update()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        return false
    }
}
